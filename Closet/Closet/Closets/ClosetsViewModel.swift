import Foundation
import PostgREST
import Supabase

@Observable
final class ClosetsViewModel {
    var closets: [Closet] = []
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    func loadClosets() async {
        isLoading = true
        defer { isLoading = false }
        do {
            closets = try await client
                .from("closets")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
