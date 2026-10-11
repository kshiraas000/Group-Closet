import SwiftUI

struct ActiveFiltersRow: View {
    @Binding var filters: BrowseFilters
    let ownerName: String?

    private var chips: [(label: String, clear: () -> Void)] {
        var result: [(label: String, clear: () -> Void)] = []
        if let ownerName {
            result.append((ownerName, { filters.ownerID = nil }))
        }
        if let size = filters.size {
            result.append((size, { filters.size = nil }))
        }
        if let color = filters.color {
            result.append((color, { filters.color = nil }))
        }
        if let occasion = filters.occasion {
            result.append((occasion, { filters.occasion = nil }))
        }
        return result
    }

    var body: some View {
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        Button(action: chip.clear) {
                            HStack(spacing: 5) {
                                Text(chip.label)
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .font(Theme.Font.body(12.5, weight: .medium))
                            .foregroundStyle(Theme.Color.background)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Theme.Color.accent)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }
}
