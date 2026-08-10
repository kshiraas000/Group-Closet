import SwiftUI

struct JoinClosetView: View {
    @State private var viewModel = JoinClosetViewModel()
    @Environment(\.dismiss) private var dismiss
    let onJoined: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $viewModel.inviteCode)
                        .font(Theme.Font.body(16))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(Theme.Font.body(14))
                            .foregroundStyle(.red)
                    }
                }
                .listRowBackground(Theme.Color.background)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
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
                    .tint(Theme.Color.accent)
                }
            }
        }
    }
}
