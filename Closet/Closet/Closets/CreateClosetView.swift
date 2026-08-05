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
                    }
                }
            }
        }
    }

    private var form: some View {
        Form {
            TextField("Closet name", text: $viewModel.name)
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
    }

    private func inviteView(for closet: Closet) -> some View {
        VStack(spacing: 16) {
            Text("\(closet.name) is ready")
                .font(.headline)
            Text("Invite code: \(closet.inviteCode)")
                .font(.title2.monospaced())
            ShareLink(item: "Join my Closet \"\(closet.name)\" on the Closet app — invite code: \(closet.inviteCode)")
            Button("Done") { dismiss() }
        }
        .padding()
    }
}
