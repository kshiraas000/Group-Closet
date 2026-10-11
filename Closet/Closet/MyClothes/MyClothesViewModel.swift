import Foundation
import PostgREST
import Storage
import Supabase

private struct PhotoRow: Decodable {
    let photoURL: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case photoURL = "photo_url"
        case position
    }
}

private struct RawItem: Decodable {
    let id: UUID
    let ownerID: UUID
    let category: ItemCategory
    let size: String?
    let color: String?
    let occasionTags: [String]
    let caption: String?
    let createdAt: Date
    let itemPhotos: [PhotoRow]

    enum CodingKeys: String, CodingKey {
        case id, category, size, color, caption
        case ownerID = "owner_id"
        case occasionTags = "occasion_tags"
        case createdAt = "created_at"
        case itemPhotos = "item_photos"
    }
}

@Observable
final class MyClothesViewModel {
    var myProfile: UserProfile?
    var memberPhotoURLs: [UUID: URL] = [:]
    var items: [BrowseItem] = []
    var filters = BrowseFilters()
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    var filteredItems: [BrowseItem] {
        BrowseFiltering.filteredItems(items, filters: filters)
    }

    var availableSizes: [String] {
        BrowseFiltering.availableSizes(items)
    }

    var availableColors: [String] {
        BrowseFiltering.availableColors(items)
    }

    var availableOccasions: [String] {
        BrowseFiltering.availableOccasions(items)
    }

    func load(userID: UUID) async {
        // Only the very first load (no items yet) blocks the UI with a
        // spinner. This view model now persists across tab switches, so a
        // reload on returning to the tab should refresh silently behind
        // whatever's already showing, not flash the whole screen blank.
        if items.isEmpty {
            isLoading = true
        }
        defer { isLoading = false }

        myProfile = try? await client
            .from("users")
            .select()
            .eq("id", value: userID)
            .single()
            .execute()
            .value
        memberPhotoURLs = await ProfilePhotoResolver.signedURLs(for: [myProfile].compactMap { $0 })

        do {
            let rows: [RawItem] = try await client
                .from("items")
                .select("*, item_photos(photo_url, position)")
                .eq("owner_id", value: userID)
                .execute()
                .value
            items = rows
                .map(Self.makeBrowseItem)
                .sorted { $0.item.createdAt > $1.item.createdAt }
            await loadSignedURLs()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func makeBrowseItem(_ raw: RawItem) -> BrowseItem {
        let item = Item(
            id: raw.id,
            ownerID: raw.ownerID,
            category: raw.category,
            size: raw.size,
            color: raw.color,
            occasionTags: raw.occasionTags,
            caption: raw.caption,
            createdAt: raw.createdAt
        )
        let photoPath = raw.itemPhotos.first(where: { $0.position == 0 })?.photoURL
        return BrowseItem(item: item, photoPath: photoPath)
    }

    private func loadSignedURLs() async {
        let paths = Set(items.compactMap(\.photoPath))
        guard !paths.isEmpty else { return }

        var resolved: [String: URL] = [:]
        await withTaskGroup(of: (String, URL?).self) { group in
            for path in paths {
                group.addTask { [client] in
                    let url = try? await client.storage.from("item-photos").createSignedURL(
                        path: path,
                        expiresIn: 3600,
                        transform: TransformOptions(width: 400, height: 400, resize: .cover)
                    )
                    return (path, url)
                }
            }
            for await (path, url) in group {
                if let url { resolved[path] = url }
            }
        }

        for index in items.indices {
            if let path = items[index].photoPath {
                items[index].signedURL = resolved[path]
            }
        }
    }
}
