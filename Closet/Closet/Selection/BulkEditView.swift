import SwiftUI

struct BulkEditView: View {
    let count: Int
    let onSave: (BulkEdit) async -> Bool

    @State private var edit = BulkEdit()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Only the fields you fill in change. Occasions are added to each piece's existing ones.")
                        .font(Theme.Font.body(13))
                        .foregroundStyle(Theme.Color.secondaryText)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Category")
                            .font(Theme.Font.body(15, weight: .medium))
                            .foregroundStyle(Theme.Color.primaryText)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                            ForEach(ItemCategory.allCases) { category in
                                chip(category)
                            }
                        }
                    }

                    VStack(spacing: 8) {
                        TextField("Size", text: $edit.size).textFieldStyle(.roundedBorder)
                        TextField("Color", text: $edit.color).textFieldStyle(.roundedBorder)
                        TextField("Add occasions (comma separated)", text: $edit.occasionsText)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Font.body(14))
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .background(Theme.Color.background)
            .navigationTitle("Edit \(count) Piece\(count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(Theme.Color.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || edit.isEmpty)
                    .tint(Theme.Color.accent)
                }
            }
        }
    }

    /// Tapping the selected category again un-sets it ("leave as is").
    private func chip(_ category: ItemCategory) -> some View {
        let isSelected = edit.category == category
        return Button {
            edit.category = isSelected ? nil : category
        } label: {
            Text(category.rawValue)
                .font(Theme.Font.body(14, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Theme.Color.background : Theme.Color.primaryText.opacity(0.75))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Theme.Color.accent : Theme.Color.primaryText.opacity(0.06))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let success = await onSave(edit)
        isSaving = false
        if success {
            dismiss()
        } else {
            errorMessage = "Something went wrong. Please try again."
        }
    }
}
