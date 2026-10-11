import SwiftUI

struct FilterSheet: View {
    @Binding var filters: BrowseFilters
    let members: [UserProfile]?
    let availableSizes: [String]
    let availableColors: [String]
    let availableOccasions: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let members {
                    Section("Owner") {
                        radioRow(title: "Everyone", isSelected: filters.ownerID == nil) {
                            filters.ownerID = nil
                        }
                        ForEach(members) { member in
                            radioRow(title: member.name, isSelected: filters.ownerID == member.id) {
                                filters.ownerID = member.id
                            }
                        }
                    }
                    .listRowBackground(Theme.Color.background)
                }

                Section("Category") {
                    radioRow(title: "Any", isSelected: filters.categories.isEmpty) {
                        filters.categories = []
                    }
                    ForEach(ItemCategory.allCases) { category in
                        radioRow(title: category.pluralLabel, isSelected: filters.categories.contains(category)) {
                            if filters.categories.contains(category) {
                                filters.categories.remove(category)
                            } else {
                                filters.categories.insert(category)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.Color.background)

                if !availableSizes.isEmpty {
                    Section("Size") {
                        radioRow(title: "Any", isSelected: filters.size == nil) {
                            filters.size = nil
                        }
                        ForEach(availableSizes, id: \.self) { size in
                            radioRow(title: size, isSelected: filters.size == size) {
                                filters.size = size
                            }
                        }
                    }
                    .listRowBackground(Theme.Color.background)
                }

                if !availableColors.isEmpty {
                    Section("Color") {
                        radioRow(title: "Any", isSelected: filters.color == nil) {
                            filters.color = nil
                        }
                        ForEach(availableColors, id: \.self) { color in
                            radioRow(title: color, isSelected: filters.color == color) {
                                filters.color = color
                            }
                        }
                    }
                    .listRowBackground(Theme.Color.background)
                }

                if !availableOccasions.isEmpty {
                    Section("Occasion") {
                        radioRow(title: "Any", isSelected: filters.occasion == nil) {
                            filters.occasion = nil
                        }
                        ForEach(availableOccasions, id: \.self) { occasion in
                            radioRow(title: occasion, isSelected: filters.occasion == occasion) {
                                filters.occasion = occasion
                            }
                        }
                    }
                    .listRowBackground(Theme.Color.background)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(Theme.Color.accent)
                }
            }
        }
    }

    private func radioRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Theme.Font.body(16))
                    .foregroundStyle(Theme.Color.primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.Color.accent)
                }
            }
        }
    }
}
