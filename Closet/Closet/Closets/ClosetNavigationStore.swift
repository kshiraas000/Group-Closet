import Foundation

// Owned by MainTabView so it survives tab switches (the tab content itself is
// rebuilt from scratch each switch, so this state cannot live in the views).
// Everything except `didAutoOpen` also persists across launches.
@Observable
final class ClosetNavigationStore {
    private enum Key {
        static let openCloset = "openClosetID"
        static let favoriteCloset = "favoriteClosetID"
        static let recentOrder = "recentClosetOrder"
        static let cachedClosets = "cachedClosets"
    }

    /// The closet the user is currently inside; nil means the list is showing.
    var openClosetID: UUID? {
        didSet { write(openClosetID, forKey: Key.openCloset) }
    }

    var favoriteClosetID: UUID? {
        didSet { write(favoriteClosetID, forKey: Key.favoriteCloset) }
    }

    /// Most-recently-opened first.
    private(set) var recentOrder: [UUID] {
        didSet {
            UserDefaults.standard.set(recentOrder.map(\.uuidString), forKey: Key.recentOrder)
        }
    }

    /// Session-only: the launch-time auto-open should happen once, so that
    /// tapping "‹ Closets" and then switching tabs doesn't force the user
    /// back into a closet they deliberately backed out of.
    var didAutoOpen = false

    /// Bumped when the Closets tab is tapped while already showing. The stack
    /// lives in ClosetsListView's private State, so this is how the tab bar
    /// asks it to pop — the counter, not a Bool, so repeat taps still fire.
    private(set) var popToRootRequests = 0

    func requestPopToRoot() {
        popToRootRequests += 1
    }

    /// Last known closets, so a restored navigation stack can render its
    /// destination immediately instead of waiting on the network — waiting is
    /// what made the Closets list flash before pushing.
    private var cachedClosets: [Closet]

    init() {
        let defaults = UserDefaults.standard
        openClosetID = (defaults.string(forKey: Key.openCloset)).flatMap(UUID.init(uuidString:))
        favoriteClosetID = (defaults.string(forKey: Key.favoriteCloset)).flatMap(UUID.init(uuidString:))
        recentOrder = (defaults.stringArray(forKey: Key.recentOrder) ?? []).compactMap(UUID.init(uuidString:))
        cachedClosets = (defaults.data(forKey: Key.cachedClosets))
            .flatMap { try? JSONDecoder().decode([Closet].self, from: $0) } ?? []
    }

    func cacheClosets(_ closets: [Closet]) {
        // Never let a failed or not-yet-finished load clear the cache: doing
        // so can blank out a destination that is currently on screen.
        guard !closets.isEmpty else { return }
        cachedClosets = closets
        if let data = try? JSONEncoder().encode(closets) {
            UserDefaults.standard.set(data, forKey: Key.cachedClosets)
        }
    }

    func cachedCloset(id: UUID) -> Closet? {
        cachedClosets.first { $0.id == id }
    }

    /// The stack to start in, resolved synchronously at view-construction
    /// time so no intermediate list is ever rendered.
    func initialPath() -> [UUID] {
        if let open = openClosetID, cachedCloset(id: open) != nil {
            return [open]
        }
        if !didAutoOpen,
           let recent = recentOrder.first(where: { cachedCloset(id: $0) != nil }) {
            return [recent]
        }
        if !didAutoOpen, cachedClosets.count == 1, let only = cachedClosets.first {
            return [only.id]
        }
        return []
    }

    func markOpened(_ closetID: UUID) {
        openClosetID = closetID
        recentOrder.removeAll { $0 == closetID }
        recentOrder.insert(closetID, at: 0)
    }

    func toggleFavorite(_ closetID: UUID) {
        favoriteClosetID = favoriteClosetID == closetID ? nil : closetID
    }

    func forget(_ closetID: UUID) {
        if openClosetID == closetID { openClosetID = nil }
        if favoriteClosetID == closetID { favoriteClosetID = nil }
        recentOrder.removeAll { $0 == closetID }
    }

    /// Favorite first, then most-recently-opened, then whatever order the
    /// server returned (newest-created first).
    func sorted(_ closets: [Closet]) -> [Closet] {
        closets.enumerated().sorted { lhs, rhs in
            rank(lhs.element, fallback: lhs.offset) < rank(rhs.element, fallback: rhs.offset)
        }
        .map(\.element)
    }

    /// The closet to open automatically when no explicit choice is stored:
    /// the last one viewed, or — for a single-closet user — their only closet.
    func autoOpenTarget(in closets: [Closet]) -> UUID? {
        if let recent = recentOrder.first(where: { id in closets.contains { $0.id == id } }) {
            return recent
        }
        return closets.count == 1 ? closets.first?.id : nil
    }

    private func rank(_ closet: Closet, fallback: Int) -> (Int, Int, Int) {
        let isFavorite = closet.id == favoriteClosetID ? 0 : 1
        let recentIndex = recentOrder.firstIndex(of: closet.id) ?? Int.max
        return (isFavorite, recentIndex, fallback)
    }

    private func write(_ id: UUID?, forKey key: String) {
        let defaults = UserDefaults.standard
        if let id {
            defaults.set(id.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
