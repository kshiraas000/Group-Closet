import SwiftUI

struct ClosetDetailView: View {
    @State private var viewModel = ClosetDetailViewModel()
    @State private var showingLeaveConfirmation = false
    @Environment(\.dismiss) private var dismiss
    let closet: Closet
    let userID: UUID

    var body: some View {
        List {
            Section("Members") {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    ForEach(viewModel.members) { member in
                        Text(member.name)
                    }
                }
            }
            Section {
                ShareLink(item: "Join my Closet \"\(closet.name)\" on the Closet app — invite code: \(closet.inviteCode)") {
                    Label("Share Invite", systemImage: "square.and.arrow.up")
                }
            }
            Section {
                Button("Leave Closet", role: .destructive) {
                    showingLeaveConfirmation = true
                }
            }
        }
        .navigationTitle(closet.name)
        .task { await viewModel.loadMembers(closetID: closet.id) }
        .confirmationDialog(
            "Leave \(closet.name)?",
            isPresented: $showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task {
                    if await viewModel.leave(closetID: closet.id, userID: userID) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
