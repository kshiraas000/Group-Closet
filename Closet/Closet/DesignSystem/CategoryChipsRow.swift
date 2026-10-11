import SwiftUI

struct CategoryChipsRow: View {
    @Binding var selectedCategories: Set<ItemCategory>
    let onFilterTapped: () -> Void

    private let curatedCategories: [ItemCategory] = [.top, .bottom, .dress]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isSelected: selectedCategories.isEmpty) {
                    selectedCategories = []
                }
                ForEach(curatedCategories) { category in
                    chip(title: category.pluralLabel, isSelected: selectedCategories.contains(category)) {
                        // Toggle: tapping a selected chip clears it, and any
                        // number of categories can be active at once.
                        if selectedCategories.contains(category) {
                            selectedCategories.remove(category)
                        } else {
                            selectedCategories.insert(category)
                        }
                    }
                }
                Button(action: onFilterTapped) {
                    HStack(spacing: 4) {
                        Text("Filter")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(Theme.Font.body(13, weight: .medium))
                    .foregroundStyle(Theme.Color.primaryText)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(Theme.Color.primaryText.opacity(0.06))
                    .clipShape(Capsule())
                }
            }
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.body(13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Theme.Color.background : Theme.Color.primaryText.opacity(0.75))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(isSelected ? Theme.Color.accent : Theme.Color.primaryText.opacity(0.06))
                .clipShape(Capsule())
        }
    }
}
