import SwiftUI

struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    let item: Item
    let onSave: (ItemCategory, String, String, [String], String) async -> Bool

    @State private var category: ItemCategory
    @State private var size: String
    @State private var color: String
    @State private var occasionTags: String
    @State private var caption: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(item: Item, onSave: @escaping (ItemCategory, String, String, [String], String) async -> Bool) {
        self.item = item
        self.onSave = onSave
        _category = State(initialValue: item.category)
        _size = State(initialValue: item.size ?? "")
        _color = State(initialValue: item.color ?? "")
        _occasionTags = State(initialValue: item.occasionTags.joined(separator: ", "))
        _caption = State(initialValue: item.caption ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Add a caption", text: $caption)
                        .font(Theme.Font.headline(22))
                        .foregroundStyle(Theme.Color.primaryText)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Category")
                            .font(Theme.Font.body(15, weight: .medium))
                            .foregroundStyle(Theme.Color.primaryText)
                        let columns = [GridItem(.adaptive(minimum: 90))]
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(ItemCategory.allCases) { cat in
                                chip(cat)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("More details (optional)")
                            .font(Theme.Font.body(15, weight: .medium))
                            .foregroundStyle(Theme.Color.primaryText)
                        VStack(spacing: 8) {
                            TextField("Size", text: $size).textFieldStyle(.roundedBorder)
                            TextField("Color", text: $color).textFieldStyle(.roundedBorder)
                            TextField("Occasions (comma separated)", text: $occasionTags).textFieldStyle(.roundedBorder)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Font.body(14))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .background(Theme.Color.background)
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(Theme.Font.body(15))
                .foregroundStyle(Theme.Color.secondaryText)

            Spacer()

            Text("Edit Item")
                .font(Theme.Font.body(15, weight: .medium))
                .foregroundStyle(Theme.Color.primaryText)

            Spacer()

            Button(isSaving ? "Saving..." : "Save") {
                Task { await save() }
            }
            .font(Theme.Font.body(15, weight: .medium))
            .foregroundStyle(Theme.Color.accent)
            .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func chip(_ cat: ItemCategory) -> some View {
        Button {
            category = cat
        } label: {
            Text(cat.rawValue)
                .font(Theme.Font.body(14, weight: category == cat ? .medium : .regular))
                .foregroundStyle(category == cat ? Theme.Color.background : Theme.Color.primaryText.opacity(0.75))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(category == cat ? Theme.Color.accent : Theme.Color.primaryText.opacity(0.06))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let tags = occasionTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let success = await onSave(category, size, color, tags, caption)
        isSaving = false
        if success {
            dismiss()
        } else {
            errorMessage = "Something went wrong. Please try again."
        }
    }
}
