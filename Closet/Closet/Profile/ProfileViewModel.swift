import Foundation
import PostgREST
import Storage
import Supabase
import UIKit

struct BlockedUser: Identifiable {
    let id: UUID
    let name: String
}

@Observable
final class ProfileViewModel {
    var name: String = ""
    var topSize: String = ""
    var bottomSize: String = ""
    var shoeSize: String = ""
    var photoPath: String?
    var signedPhotoURL: URL?
    var blockedUsers: [BlockedUser] = []
    var hasLoadedProfile = false
    var isLoading = true
    var isSaving = false
    var isUploadingPhoto = false
    var errorMessage: String?

    private let client = SupabaseService.shared

    func load(userID: UUID) async {
        isLoading = true
        defer { isLoading = false }
        var failures: [String] = []

        do {
            let profile: UserProfile = try await client
                .from("users")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value
            name = profile.name
            topSize = profile.sizes["top"] ?? ""
            bottomSize = profile.sizes["bottom"] ?? ""
            shoeSize = profile.sizes["shoe"] ?? ""
            photoPath = profile.photoURL
            hasLoadedProfile = true
        } catch {
            failures.append(error.localizedDescription)
        }

        if let photoPath {
            await loadSignedPhotoURL(path: photoPath)
        }

        if let blockedUsersError = await loadBlockedUsers() {
            failures.append(blockedUsersError)
        }

        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    func save(userID: UUID) async -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Name is required"
            return false
        }
        isSaving = true
        defer { isSaving = false }

        var sizes: [String: String] = [:]
        if !topSize.isEmpty { sizes["top"] = topSize }
        if !bottomSize.isEmpty { sizes["bottom"] = bottomSize }
        if !shoeSize.isEmpty { sizes["shoe"] = shoeSize }

        struct ProfileUpdate: Encodable {
            let name: String
            let sizes: [String: String]
        }

        do {
            try await client
                .from("users")
                .update(ProfileUpdate(name: name, sizes: sizes))
                .eq("id", value: userID)
                .execute()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func uploadPhoto(_ image: UIImage, userID: UUID) async {
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        guard let imageData = ImageCompressor.compress(image) else {
            errorMessage = "Could not process image"
            return
        }
        let path = "\(userID.uuidString.lowercased())/photo.jpg"

        struct PhotoUpdate: Encodable {
            let photoURL: String
            enum CodingKeys: String, CodingKey { case photoURL = "photo_url" }
        }

        do {
            try await client.storage.from("profile-photos").upload(
                path,
                data: imageData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
            try await client.from("users").update(PhotoUpdate(photoURL: path)).eq("id", value: userID).execute()
            photoPath = path
            errorMessage = nil
            await loadSignedPhotoURL(path: path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSignedPhotoURL(path: String) async {
        signedPhotoURL = try? await client.storage.from("profile-photos").createSignedURL(
            path: path,
            expiresIn: 3600,
            transform: TransformOptions(width: 200, height: 200, resize: .cover)
        )
    }

    func loadBlockedUsers() async -> String? {
        do {
            struct BlockRow: Decodable {
                let blockedID: UUID
                enum CodingKeys: String, CodingKey { case blockedID = "blocked_id" }
            }
            let rows: [BlockRow] = try await client
                .from("blocks")
                .select("blocked_id")
                .execute()
                .value
            let blockedIDs = rows.map(\.blockedID)
            guard !blockedIDs.isEmpty else {
                blockedUsers = []
                return nil
            }

            struct NameRow: Decodable {
                let id: UUID
                let name: String
            }
            let names: [NameRow] = try await client
                .from("users")
                .select("id, name")
                .in("id", values: blockedIDs)
                .execute()
                .value
            blockedUsers = names.map { BlockedUser(id: $0.id, name: $0.name) }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func unblock(blockedID: UUID, blockerID: UUID) async {
        do {
            try await client
                .from("blocks")
                .delete()
                .eq("blocker_id", value: blockerID)
                .eq("blocked_id", value: blockedID)
                .execute()
            errorMessage = await loadBlockedUsers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reportInvalidPhoto() {
        errorMessage = "Could not load that photo"
    }

    func deleteAccount(userID: UUID) async -> Bool {
        do {
            try await removeStoredPhotos(userID: userID)
            try await client.rpc("delete_own_account").execute()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Photos have to go before the account does: the rows in storage.objects
    /// are only metadata, so dropping them in SQL would unlink the files while
    /// leaving the bytes in the bucket. Only the Storage API deletes for real,
    /// and once the auth user is gone the paths are no longer readable.
    private func removeStoredPhotos(userID: UUID) async throws {
        struct ItemRow: Decodable { let id: UUID }
        struct PhotoRow: Decodable {
            let photoURL: String
            enum CodingKeys: String, CodingKey { case photoURL = "photo_url" }
        }

        let items: [ItemRow] = try await client
            .from("items")
            .select("id")
            .eq("owner_id", value: userID)
            .execute()
            .value

        if !items.isEmpty {
            let photos: [PhotoRow] = try await client
                .from("item_photos")
                .select("photo_url")
                .in("item_id", values: items.map(\.id))
                .execute()
                .value
            let paths = photos.map(\.photoURL)
            if !paths.isEmpty {
                _ = try await client.storage.from("item-photos").remove(paths: paths)
            }
        }

        if let photoPath {
            _ = try await client.storage.from("profile-photos").remove(paths: [photoPath])
        }
    }
}
