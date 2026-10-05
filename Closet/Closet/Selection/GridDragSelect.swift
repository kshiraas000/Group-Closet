import Foundation

enum GridDragSelect {
    /// Every selectable id between `from` and `to` (inclusive) in grid order,
    /// whichever direction the finger went. Empty if either id is unknown.
    static func coveredIDs(order: [UUID], from: UUID, to: UUID, selectable: Set<UUID>) -> Set<UUID> {
        guard let start = order.firstIndex(of: from), let end = order.firstIndex(of: to) else { return [] }
        return Set(order[min(start, end)...max(start, end)]).intersection(selectable)
    }
}
