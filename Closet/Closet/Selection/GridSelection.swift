import Foundation

/// Photos-style select mode for an item grid. Which tiles are selectable is
/// the caller's call (only the user's own pieces) — this only tracks state.
/// Foundation-only so LogicTests/run.sh can compile it without the app.
struct GridSelection {
    private(set) var isActive = false
    private(set) var selectedIDs: Set<UUID> = []

    /// Selection before the current drag began, and whether that drag is
    /// selecting (started on an unselected tile) or deselecting.
    private var dragBaseline: Set<UUID>?
    private var dragSelects = true

    var count: Int { selectedIDs.count }

    /// Long-press entry: select mode starts with the pressed tile selected.
    mutating func begin(with id: UUID) {
        isActive = true
        selectedIDs = [id]
    }

    mutating func toggle(_ id: UUID) {
        guard isActive else { return }
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// Drops anything no longer visible (filtered out, deleted, unshared), so
    /// an action never touches pieces the user can't currently see.
    mutating func retain(_ visibleIDs: Set<UUID>) {
        selectedIDs.formIntersection(visibleIDs)
    }

    mutating func end() {
        isActive = false
        selectedIDs = []
        dragBaseline = nil
    }

    mutating func beginDrag(on id: UUID) {
        guard isActive else { return }
        dragBaseline = selectedIDs
        dragSelects = !selectedIDs.contains(id)
    }

    /// `covered` is every selectable tile between the drag's first tile and
    /// the one under the finger now. Recomputed from the baseline each time,
    /// so dragging back un-does tiles the drag no longer covers.
    mutating func updateDrag(covering covered: Set<UUID>) {
        guard let dragBaseline else { return }
        selectedIDs = dragSelects
            ? dragBaseline.union(covered)
            : dragBaseline.subtracting(covered)
    }

    mutating func endDrag() {
        dragBaseline = nil
    }
}
