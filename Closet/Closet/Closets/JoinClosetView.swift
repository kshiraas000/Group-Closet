import SwiftUI

struct JoinClosetView: View {
    @State private var viewModel = JoinClosetViewModel()
    @Environment(\.dismiss) private var dismiss
    let onJoined: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Invite code", text: $viewModel.inviteCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Join a Closet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isJoining ? "Joining..." : "Join") {
                        Task {
                            if await viewModel.join() != nil {
                                onJoined()
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isJoining)
                }
            }
        }
    }
}
