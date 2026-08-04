import Foundation
import PostgREST
import Supabase

@Observable
final class OnboardingViewModel {
    var name: String = ""
    var topSize: String = ""
    var bottomSize: String = ""
    var shoeSize: String = ""
    var isSaving = false
    var errorMessage: String?

    private let client = SupabaseService.shared

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

        let profile = UserProfile(id: userID, name: name, photoURL: nil, sizes: sizes)

        do {
            try await client.from("users").insert(profile).execute()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
