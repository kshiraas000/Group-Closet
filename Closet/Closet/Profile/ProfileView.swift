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
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else {
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
                                                .foregroundStyle(Theme.Color.tertiaryText)
                                        }
                                    }
                                    .frame(width: 96, height: 96)
                                    .clipShape(Circle())

                                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                        Text(viewModel.isUploadingPhoto ? "Uploading..." : "Change Photo")
                                            .font(Theme.Font.body(14, weight: .medium))
                                    }
                                    .tint(Theme.Color.accent)
                                    .disabled(viewModel.isUploadingPhoto)
                                    .onChange(of: selectedPhoto) { _, newValue in
                                        Task { await loadAndUploadPhoto(newValue) }
                                    }
                                }
                                Spacer()
                            }
                        }
                        .listRowBackground(Theme.Color.background)

                        Section("Your name") {
                            TextField("Name", text: $viewModel.name)
                                .font(Theme.Font.body(16))
                        }
                        .listRowBackground(Theme.Color.background)

                        Section("Your usual sizes") {
                            TextField("Top", text: $viewModel.topSize)
                                .font(Theme.Font.body(16))
                            TextField("Bottom", text: $viewModel.bottomSize)
                                .font(Theme.Font.body(16))
                            TextField("Shoe", text: $viewModel.shoeSize)
                                .font(Theme.Font.body(16))
                        }
                        .listRowBackground(Theme.Color.background)

                        if let errorMessage = viewModel.errorMessage {
                            Section {
                                Text(errorMessage)
                                    .font(Theme.Font.body(14))
                                    .foregroundStyle(.red)
                            }
                            .listRowBackground(Theme.Color.background)
                        }

                        Section {
                            Button(viewModel.isSaving ? "Saving..." : "Save") {
                                Task { await viewModel.save(userID: userID) }
                            }
                            .font(Theme.Font.body(16, weight: .medium))
                            .disabled(viewModel.isSaving || !viewModel.hasLoadedProfile)
                            .tint(Theme.Color.accent)
                        }
                        .listRowBackground(Theme.Color.background)

                        Section("Blocked Users") {
                            if viewModel.blockedUsers.isEmpty {
                                Text("No blocked users")
                                    .font(Theme.Font.body(14))
                                    .foregroundStyle(Theme.Color.secondaryText)
                            } else {
                                ForEach(viewModel.blockedUsers) { blockedUser in
                                    HStack {
                                        Text(blockedUser.name)
                                            .font(Theme.Font.body(16))
                                        Spacer()
                                        Button("Unblock") {
                                            Task { await viewModel.unblock(blockedID: blockedUser.id, blockerID: userID) }
                                        }
                                        .font(Theme.Font.body(14, weight: .medium))
                                        .tint(Theme.Color.accent)
                                    }
                                }
                            }
                        }
                        .listRowBackground(Theme.Color.background)

                        Section {
                            Button("Sign Out") {
                                Task { await onSignedOut() }
                            }
                            .font(Theme.Font.body(16))
                            .foregroundStyle(Theme.Color.primaryText)
                        }
                        .listRowBackground(Theme.Color.background)

                        Section {
                            Button("Delete Account", role: .destructive) {
                                showingDeleteConfirmation = true
                            }
                            .font(Theme.Font.body(16))
                        }
                        .listRowBackground(Theme.Color.background)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.Color.background)
                }
            }
            .background(Theme.Color.background)
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
