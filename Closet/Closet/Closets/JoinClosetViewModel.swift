import Foundation
import PostgREST
import Supabase

struct ClosetPreview: Decodable {
    let closetID: UUID
    let name: String
    let memberCount: Int
    let pieceCount: Int
    let alreadyMember: Bool

    enum CodingKeys: String, CodingKey {
        case closetID = "closet_id"
        case name
        case memberCount = "member_count"
        case pieceCount = "piece_count"
        case alreadyMember = "already_member"
    }
}

@Observable
final class JoinClosetViewModel {
    static let codeLength = 10

    var inviteCode: String = ""
    var isJoining = false
    var isLoadingPreview = false
    var errorMessage: String?
    var preview: ClosetPreview?

    private let client = SupabaseService.shared
    private var previewTask: Task<Void, Never>?

    /// Call after setting `inviteCode` (the view's TextField binding already
    /// filters and upper-cases it). Cancels any in-flight preview and starts
    /// a new one once the code reaches full length.
    func codeChanged() {
        preview = nil
        errorMessage = nil
        previewTask?.cancel()
        guard inviteCode.count == Self.codeLength else { return }
        let code = inviteCode
        previewTask = Task { await loadPreview(code: code) }
    }

    @MainActor
    private func loadPreview(code: String) async {
        isLoadingPreview = true
        defer { isLoadingPreview = false }
        do {
            let row: ClosetPreview = try await client
                .rpc("preview_closet_by_invite_code", params: ["p_invite_code": code])
                .single()
                .execute()
                .value
            // The code may have changed (or the task been cancelled) while
            // this was in flight — a stale result must never overwrite it.
            guard !Task.isCancelled, inviteCode == code else { return }
            preview = row
        } catch {
            guard !Task.isCancelled, inviteCode == code else { return }
            errorMessage = "That code doesn't match a closet"
        }
    }

    /// Returns the closet to open. For a closet the user is already in, this
    /// skips the join RPC entirely rather than re-joining a no-op.
    func join() async -> UUID? {
        guard let preview else { return nil }
        if preview.alreadyMember {
            return preview.closetID
        }
        isJoining = true
        defer { isJoining = false }
        do {
            let closet: Closet = try await client
                .rpc("join_closet_by_invite_code", params: ["p_invite_code": inviteCode])
                .execute()
                .value
            return closet.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
