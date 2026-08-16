import Foundation

struct BrowseItem: Identifiable {
    var id: UUID { item.id }
    let item: Item
    let photoPath: String?
    var signedURL: URL? = nil
}

struct BrowseFilters: Equatable {
    /// Empty means "all categories" — otherwise an item matches if it's in the set.
    var categories: Set<ItemCategory> = []
    var ownerID: UUID?
    var size: String?
    var color: String?
    var occasion: String?
    var searchText: String = ""
}

enum BrowseFiltering {
    static func filteredItems(_ items: [BrowseItem], filters: BrowseFilters) -> [BrowseItem] {
        items.filter { browseItem in
            if !filters.categories.isEmpty, !filters.categories.contains(browseItem.item.category) {
                return false
            }
            if let ownerID = filters.ownerID, browseItem.item.ownerID != ownerID {
                return false
            }
            if let size = filters.size, browseItem.item.size != size {
                return false
            }
            if let color = filters.color, browseItem.item.color != color {
                return false
            }
            if let occasion = filters.occasion, !browseItem.item.occasionTags.contains(occasion) {
                return false
            }
            if !filters.searchText.isEmpty {
                let query = filters.searchText.lowercased()
                let haystack = [
                    browseItem.item.caption,
                    browseItem.item.category.rawValue,
                    browseItem.item.color
                ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
                if !haystack.contains(query) {
                    return false
                }
            }
            return true
        }
    }

    static func availableSizes(_ items: [BrowseItem]) -> [String] {
        Array(Set(items.compactMap { $0.item.size }.filter { !$0.isEmpty })).sorted()
    }

    static func availableColors(_ items: [BrowseItem]) -> [String] {
        Array(Set(items.compactMap { $0.item.color }.filter { !$0.isEmpty })).sorted()
    }

    static func availableOccasions(_ items: [BrowseItem]) -> [String] {
        Array(Set(items.flatMap { $0.item.occasionTags })).sorted()
    }
}
