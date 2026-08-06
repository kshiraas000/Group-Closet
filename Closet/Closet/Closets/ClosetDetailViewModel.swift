import Foundation
import PostgREST
import Storage
import Supabase

private struct MemberRow: Decodable {
    let users: UserProfile
}

private struct PhotoRow: Decodable {
    let photoURL: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case photoURL = "photo_url"
        case position
    }
}

private struct OwnerRow: Decodable {
    let name: String
}

private struct RawBrowseItem: Decodable {
    let id: UUID
    let ownerID: UUID
    let category: ItemCategory
    let size: String?
    let color: String?
    let occasionTags: [String]
    let caption: String?
    let createdAt: Date
    let itemPhotos: [PhotoRow]
    let users: OwnerRow

    enum CodingKeys: String, CodingKey {
        case id, category, size, color, caption
        case ownerID = "owner_id"
        case occasionTags = "occasion_tags"
        case createdAt = "created_at"
        case itemPhotos = "item_photos"
        case users
    }
}

private struct ItemShareRow: Decodable {
    let items: RawBrowseItem
}

struct BrowseItem: Identifiable {
    var id: UUID { item.id }
    let item: Item
    let photoPath: String?
    let ownerName: String
    var signedURL: URL? = nil
}

struct BrowseFilters: Equatable {
    var category: ItemCategory?
    var ownerID: UUID?
    var size: String?
    var color: String?
    var occasion: String?
    var searchText: String = ""
}

@Observable
final class ClosetDetailViewModel {
    var members: [UserProfile] = []
    var items: [BrowseItem] = []
    var filters = BrowseFilters()
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    var filteredItems: [BrowseItem] {
        items.filter { browseItem in
            if let category = filters.category, browseItem.item.category != category {
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

    var availableSizes: [String] {
        Array(Set(items.compactMap { $0.item.size }.filter { !$0.isEmpty })).sorted()
    }

    var availableColors: [String] {
        Array(Set(items.compactMap { $0.item.color }.filter { !$0.isEmpty })).sorted()
    }

    var availableOccasions: [String] {
        Array(Set(items.flatMap { $0.item.occasionTags })).sorted()
    }

    func load(closetID: UUID) async {
        isLoading = true
        defer { isLoading = false }
        var failures: [String] = []

        do {
            let rows: [MemberRow] = try await client
                .from("closet_members")
                .select("users(id, name, photo_url, sizes)")
                .eq("closet_id", value: closetID)
                .execute()
                .value
            members = rows.map(\.users)
        } catch {
            failures.append(error.localizedDescription)
        }

        do {
            let rows: [ItemShareRow] = try await client
                .from("item_shares")
                .select("items(*, item_photos(photo_url, position), users(name))")
                .eq("closet_id", value: closetID)
                .execute()
                .value
            items = rows
                .map { Self.makeBrowseItem($0.items) }
                .sorted { $0.item.createdAt > $1.item.createdAt }
            await loadSignedURLs()
        } catch {
            failures.append(error.localizedDescription)
        }

        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private static func makeBrowseItem(_ raw: RawBrowseItem) -> BrowseItem {
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
        return BrowseItem(item: item, photoPath: photoPath, ownerName: raw.users.name)
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

    func leave(closetID: UUID, userID: UUID) async -> Bool {
        errorMessage = nil
        do {
            try await client
                .from("closet_members")
                .delete()
                .eq("closet_id", value: closetID)
                .eq("user_id", value: userID)
                .execute()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
