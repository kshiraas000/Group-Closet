import Foundation
import Storage
import Supabase

@Observable
final class ItemDetailViewModel {
    private var fullResURLs: [UUID: URL] = [:]
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
}
