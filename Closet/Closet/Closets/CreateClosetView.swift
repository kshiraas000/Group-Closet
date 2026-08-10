import SwiftUI

struct CreateClosetView: View {
    @State private var viewModel = CreateClosetViewModel()
    @State private var createdCloset: Closet?
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let createdCloset {
                    inviteView(for: createdCloset)
                } else {
                    form
                }
            }
            .background(Theme.Color.background)
            .navigationTitle(createdCloset == nil ? "New Closet" : "Invite Friends")
            .toolbar {
                if createdCloset == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(viewModel.isSaving ? "Creating..." : "Create") {
                            Task {
                                if let closet = await viewModel.create() {
                                    onCreated()
                                    createdCloset = closet
                                }
                            }
                        }
                        .disabled(viewModel.isSaving)
                        .tint(Theme.Color.accent)
                    }
                }
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Closet name", text: $viewModel.name)
                    .font(Theme.Font.body(16))
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
    }

    private func inviteView(for closet: Closet) -> some View {
        VStack(spacing: 16) {
            Text("\(closet.name) is ready")
                .font(Theme.Font.headline(22))
                .foregroundStyle(Theme.Color.primaryText)
            Text("Invite code: \(closet.inviteCode)")
                .font(Theme.Font.body(18, weight: .medium))
                .foregroundStyle(Theme.Color.secondaryText)
            ShareLink(item: "Join my Closet \"\(closet.name)\" on the Closet app — invite code: \(closet.inviteCode)")
                .font(Theme.Font.body(16, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            Button("Done") { dismiss() }
                .font(Theme.Font.body(16, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
        }
        .padding()
    }
}
