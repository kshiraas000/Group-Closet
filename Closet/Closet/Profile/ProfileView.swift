import PhotosUI
import SwiftUI

struct ProfileView: View {
    // Owned by MainTabView, not @State here — see MainTabView.profileViewModel.
    @Bindable var viewModel: ProfileViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingCropImage: UIImage?
    @State private var showingDeleteConfirmation = false
    @AppStorage("isDarkMode") private var isDarkMode = false
    let userID: UUID
    let onSignedOut: () async -> Void

    private let letterSizes = ["XS", "S", "M", "L", "XL", "XXL"]
    private let shoeSizes: [String] = stride(from: 5.0, through: 13.0, by: 0.5).map {
        $0.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", $0) : String(format: "%.1f", $0)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            Text("Profile")
                                .font(Theme.Font.headline(32))
                                .foregroundStyle(Theme.Color.primaryText)

                            photoSection

                            VStack(alignment: .leading, spacing: 8) {
                                sectionLabel("Your usual sizes")
                                card {
                                    sizeRow(label: "Top", value: $viewModel.topSize, options: letterSizes)
                                    Divider().overlay(Theme.Color.divider)
                                    sizeRow(label: "Bottom", value: $viewModel.bottomSize, options: letterSizes)
                                    Divider().overlay(Theme.Color.divider)
                                    sizeRow(label: "Shoe", value: $viewModel.shoeSize, options: shoeSizes)
                                }
                            }

                            if let errorMessage = viewModel.errorMessage {
                                Text(errorMessage)
                                    .font(Theme.Font.body(14))
                                    .foregroundStyle(.red)
                            }

                            Button {
                                Task { await viewModel.save(userID: userID) }
                            } label: {
                                Text(viewModel.isSaving ? "Saving..." : "Save changes")
                                    .font(Theme.Font.body(16, weight: .medium))
                                    .foregroundStyle(Theme.Color.background)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .background(Theme.Color.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .disabled(viewModel.isSaving || !viewModel.hasLoadedProfile)
                            .opacity(viewModel.isSaving || !viewModel.hasLoadedProfile ? 0.6 : 1)

                            VStack(alignment: .leading, spacing: 8) {
                                sectionLabel("Blocked users")
                                card {
                                    if viewModel.blockedUsers.isEmpty {
                                        Text("No blocked users")
                                            .font(Theme.Font.body(14))
                                            .foregroundStyle(Theme.Color.secondaryText)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 13)
                                    } else {
                                        ForEach(Array(viewModel.blockedUsers.enumerated()), id: \.element.id) { index, blockedUser in
                                            if index > 0 {
                                                Divider().overlay(Theme.Color.divider)
                                            }
                                            HStack {
                                                Text(blockedUser.name)
                                                    .font(Theme.Font.body(16))
                                                    .foregroundStyle(Theme.Color.primaryText)
                                                Spacer()
                                                Button("Unblock") {
                                                    Task { await viewModel.unblock(blockedID: blockedUser.id, blockerID: userID) }
                                                }
                                                .font(Theme.Font.body(14, weight: .medium))
                                                .tint(Theme.Color.accent)
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 13)
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                sectionLabel("Appearance")
                                card {
                                    Toggle(isOn: $isDarkMode) {
                                        Text("Dark Mode")
                                            .font(Theme.Font.body(16))
                                            .foregroundStyle(Theme.Color.primaryText)
                                    }
                                    .tint(Theme.Color.accent)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                sectionLabel("About")
                                card {
                                    legalRow("Privacy Policy", url: LegalLinks.privacy)
                                    Divider().overlay(Theme.Color.divider)
                                    legalRow("Terms of Use", url: LegalLinks.terms)
                                    Divider().overlay(Theme.Color.divider)
                                    legalRow("Support", url: LegalLinks.support)
                                }
                            }

                            VStack(spacing: 18) {
                                Button("Sign Out") {
                                    Task { await onSignedOut() }
                                }
                                .font(Theme.Font.body(15))
                                .foregroundStyle(Theme.Color.secondaryText)

                                Button("Delete Account", role: .destructive) {
                                    showingDeleteConfirmation = true
                                }
                                .font(Theme.Font.body(15))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(Theme.Color.background)
            .toolbar(.hidden, for: .navigationBar)
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
                        if await viewModel.deleteAccount(userID: userID) {
                            await onSignedOut()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { pendingCropImage != nil },
            set: { if !$0 { pendingCropImage = nil } }
        )) {
            if let pendingCropImage {
                PhotoCropView(image: pendingCropImage) {
                    self.pendingCropImage = nil
                    self.selectedPhoto = nil
                } onCrop: { cropped in
                    self.pendingCropImage = nil
                    self.selectedPhoto = nil
                    Task { await viewModel.uploadPhoto(cropped, userID: userID) }
                }
            }
        }
    }

    private var photoSection: some View {
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

            TextField("Your name", text: $viewModel.name)
                .font(Theme.Font.body(19, weight: .medium))
                .foregroundStyle(Theme.Color.primaryText)
                .multilineTextAlignment(.center)

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
        .frame(maxWidth: .infinity)
    }

    private func legalRow(_ title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(title)
                    .font(Theme.Font.body(16))
                    .foregroundStyle(Theme.Color.primaryText)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.Font.body(12, weight: .medium))
            .foregroundStyle(Theme.Color.secondaryText)
            .tracking(0.4)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Theme.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sizeRow(label: String, value: Binding<String>, options: [String]) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) { value.wrappedValue = option }
            }
        } label: {
            HStack {
                Text(label)
                    .font(Theme.Font.body(16))
                    .foregroundStyle(Theme.Color.secondaryText)
                Spacer()
                Text(value.wrappedValue.isEmpty ? "Not set" : value.wrappedValue)
                    .font(Theme.Font.body(16))
                    .foregroundStyle(value.wrappedValue.isEmpty ? Theme.Color.tertiaryText : Theme.Color.primaryText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadAndUploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            viewModel.reportInvalidPhoto()
            return
        }
        pendingCropImage = image
    }
}
