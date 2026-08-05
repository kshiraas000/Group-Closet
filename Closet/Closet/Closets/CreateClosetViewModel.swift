import Foundation
import PostgREST
import Supabase

@Observable
final class CreateClosetViewModel {
    var name: String = ""
    var isSaving = false
    var errorMessage: String?

    private let client = SupabaseService.shared

    func create() async -> Closet? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Name is required"
            return nil
        }
        isSaving = true
        defer { isSaving = false }

        do {
            let closet: Closet = try await client
                .rpc("create_closet", params: ["p_name": name])
                .execute()
                .value
            return closet
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
