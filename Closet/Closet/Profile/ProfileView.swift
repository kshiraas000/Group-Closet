import PhotosUI
import SwiftUI

struct ProfileView: View {
    @State private var viewModel = ProfileViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingDeleteConfirmation = false
    let userID: UUID
    let onSignedOut: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            AsyncImage(url: viewModel.signedPhotoURL) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())

                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Text(viewModel.isUploadingPhoto ? "Uploading..." : "Change Photo")
                            }
                            .disabled(viewModel.isUploadingPhoto)
                            .onChange(of: selectedPhoto) { _, newValue in
                                Task { await loadAndUploadPhoto(newValue) }
                            }
                        }
                        Spacer()
                    }
                }

                Section("Your name") {
                    TextField("Name", text: $viewModel.name)
                }

                Section("Your usual sizes") {
                    TextField("Top", text: $viewModel.topSize)
                    TextField("Bottom", text: $viewModel.bottomSize)
                    TextField("Shoe", text: $viewModel.shoeSize)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button(viewModel.isSaving ? "Saving..." : "Save") {
                        Task { await viewModel.save(userID: userID) }
                    }
                    .disabled(viewModel.isSaving)
                }

                Section("Blocked Users") {
                    if viewModel.blockedUsers.isEmpty {
                        Text("No blocked users").foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.blockedUsers) { blockedUser in
                            HStack {
                                Text(blockedUser.name)
                                Spacer()
                                Button("Unblock") {
                                    Task { await viewModel.unblock(blockedID: blockedUser.id, blockerID: userID) }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Sign Out") {
                        Task { await onSignedOut() }
                    }
                }

                Section {
                    Button("Delete Account", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                await viewModel.load(userID: userID)
            }
            .confirmationDialog(
                "Delete your account? This cannot be undone.",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task {
                        if await viewModel.deleteAccount() {
                            await onSignedOut()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func loadAndUploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            viewModel.reportInvalidPhoto()
            return
        }
        await viewModel.uploadPhoto(image, userID: userID)
    }
}
