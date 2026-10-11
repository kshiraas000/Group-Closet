import Foundation

/// A bulk tag edit across several pieces. Blank fields mean "leave as is" —
/// so bulk edit can set values but never clear them, which keeps an
/// accidental Save with empty fields harmless. Occasions are appended.
struct BulkEdit {
    var category: ItemCategory?
    var size: String = ""
    var color: String = ""
    var occasionsText: String = ""

    private var trimmedSize: String { size.trimmingCharacters(in: .whitespaces) }
    private var trimmedColor: String { color.trimmingCharacters(in: .whitespaces) }
    private var addedOccasions: [String] { Self.parseOccasions(occasionsText) }

    var isEmpty: Bool {
        category == nil && trimmedSize.isEmpty && trimmedColor.isEmpty && addedOccasions.isEmpty
    }

    func applied(to item: Item) -> Item {
        var result = item
        if let category { result.category = category }
        if !trimmedSize.isEmpty { result.size = trimmedSize }
        if !trimmedColor.isEmpty { result.color = trimmedColor }
        for occasion in addedOccasions
        where !result.occasionTags.contains(where: { $0.caseInsensitiveCompare(occasion) == .orderedSame }) {
            result.occasionTags.append(occasion)
        }
        return result
    }

    /// Same comma-separated rule AddItem and EditItem use.
    static func parseOccasions(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
