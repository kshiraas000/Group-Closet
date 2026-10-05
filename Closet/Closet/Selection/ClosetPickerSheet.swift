import PostgREST
import Supabase
import SwiftUI

/// Lists the closets the user belongs to (RLS scopes `closets` to members)
/// and hands back the one they tap.
struct ClosetPickerSheet: View {
    let title: String
    let excludingClosetID: UUID?
    let onPick: (Closet) -> Void

    @State private var closets: [Closet] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Theme.Color.background)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.body(14))
                        .foregroundStyle(.red)
                        .listRowBackground(Theme.Color.background)
                } else if closets.isEmpty {
                    Text(excludingClosetID == nil ? "You're not in any Closets yet" : "You're not in any other Closets")
                        .font(Theme.Font.body(14))
                        .foregroundStyle(Theme.Color.secondaryText)
                        .listRowBackground(Theme.Color.background)
                } else {
                    ForEach(closets) { closet in
                        Button {
                            dismiss()
                            onPick(closet)
                        } label: {
                            Text(closet.name)
                                .font(Theme.Font.body(16))
                                .foregroundStyle(Theme.Color.primaryText)
                        }
                        .listRowBackground(Theme.Color.background)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(Theme.Color.accent)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            let all: [Closet] = try await SupabaseService.shared
                .from("closets")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            closets = all.filter { $0.id != excludingClosetID }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
