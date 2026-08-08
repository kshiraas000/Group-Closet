import Foundation
import PostgREST
import Storage
import Supabase

@Observable
final class ItemDetailViewModel {
    private var fullResURLs: [UUID: URL] = [:]
    var allClosets: [Closet] = []
    var sharedClosetIDs: Set<UUID> = []
    var shareStateErrorMessage: String?
    var isLoadingShareState = false

    private let client = SupabaseService.shared

    func url(for item: BrowseItem) -> URL? {
        fullResURLs[item.id]
    }

    func loadFullResURL(for item: BrowseItem) async {
        guard fullResURLs[item.id] == nil, let path = item.photoPath else { return }
        let url = try? await client.storage.from("item-photos").createSignedURL(
            path: path,
            expiresIn: 3600,
            transform: TransformOptions(width: 1200, resize: .contain)
        )
        if let url {
            fullResURLs[item.id] = url
        }
    }

    func loadShareState(itemID: UUID) async {
        shareStateErrorMessage = nil
        isLoadingShareState = true
        defer { isLoadingShareState = false }
        allClosets = []
        sharedClosetIDs = []

        do {
            allClosets = try await client
                .from("closets")
                .select()
                .execute()
                .value
        } catch {
            shareStateErrorMessage = error.localizedDescription
        }

        do {
            struct ShareRow: Decodable {
                let closetID: UUID
                enum CodingKeys: String, CodingKey { case closetID = "closet_id" }
            }
            let rows: [ShareRow] = try await client
                .from("item_shares")
                .select("closet_id")
                .eq("item_id", value: itemID)
                .execute()
                .value
            sharedClosetIDs = Set(rows.map(\.closetID))
        } catch {
            shareStateErrorMessage = error.localizedDescription
        }
    }

    func toggleShare(itemID: UUID, closetID: UUID) async {
        shareStateErrorMessage = nil
        do {
            if sharedClosetIDs.contains(closetID) {
                try await client
                    .from("item_shares")
                    .delete()
                    .eq("item_id", value: itemID)
                    .eq("closet_id", value: closetID)
                    .execute()
            } else {
                struct NewShare: Encodable {
                    let itemID: UUID
                    let closetID: UUID
                    enum CodingKeys: String, CodingKey {
                        case itemID = "item_id"
                        case closetID = "closet_id"
                    }
                }
                try await client
                    .from("item_shares")
                    .insert(NewShare(itemID: itemID, closetID: closetID))
                    .execute()
            }
        } catch {
            shareStateErrorMessage = error.localizedDescription
        }
        await loadShareState(itemID: itemID)
    }
}
