import Foundation
import Storage
import Supabase

enum ProfilePhotoResolver {
    static func signedURLs(for profiles: [UserProfile]) async -> [UUID: URL] {
        let client = SupabaseService.shared
        var resolved: [UUID: URL] = [:]
        await withTaskGroup(of: (UUID, URL?).self) { group in
            for profile in profiles {
                guard let path = profile.photoURL else { continue }
                group.addTask {
                    let url = try? await client.storage.from("profile-photos").createSignedURL(
                        path: path,
                        expiresIn: 3600,
                        transform: TransformOptions(width: 80, height: 80, resize: .cover)
                    )
                    return (profile.id, url)
                }
            }
            for await (id, url) in group {
                if let url { resolved[id] = url }
            }
        }
        return resolved
    }
}
