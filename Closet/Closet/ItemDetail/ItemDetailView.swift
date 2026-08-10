import SwiftUI

struct ItemDetailView: View {
    @State private var viewModel = ItemDetailViewModel()
    @State private var currentIndex: Int
    @State private var showingReportConfirmation = false
    @State private var showingBlockConfirmation = false
    @State private var showingActionAlert = false
    @State private var actionAlertMessage = ""
    @Environment(\.dismiss) private var dismiss
    let items: [BrowseItem]
    let members: [UserProfile]
    let memberPhotoURLs: [UUID: URL]
    let userID: UUID
    let onShareChanged: () -> Void
    let onBlocked: () -> Void

    init(
        items: [BrowseItem],
        startIndex: Int,
        members: [UserProfile],
        memberPhotoURLs: [UUID: URL] = [:],
        userID: UUID,
        onShareChanged: @escaping () -> Void = {},
        onBlocked: @escaping () -> Void = {}
    ) {
        self.items = items
        self.members = members
        self.memberPhotoURLs = memberPhotoURLs
        self.userID = userID
        self.onShareChanged = onShareChanged
        self.onBlocked = onBlocked
        _currentIndex = State(initialValue: startIndex)
    }

    private var currentItem: BrowseItem {
        items[currentIndex]
    }

    private var owner: UserProfile? {
        members.first { $0.id == currentItem.item.ownerID }
    }

    private var ownerName: String {
        owner?.name ?? "Unknown"
    }

    private var isOwner: Bool {
        currentItem.item.ownerID == userID
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            photoArea
            bottomInfo
        }
        .background(Theme.Color.background)
        .task(id: currentIndex) {
            await viewModel.loadFullResURL(for: currentItem)
            if isOwner {
                await viewModel.loadShareState(itemID: currentItem.item.id)
            }
        }
        .confirmationDialog("Report this item?", isPresented: $showingReportConfirmation, titleVisibility: .visible) {
            Button("Report", role: .destructive) {
                Task {
                    let success = await viewModel.report(itemID: currentItem.item.id, reporterID: userID)
                    actionAlertMessage = success ? "Reported" : "Something went wrong. Please try again."
                    showingActionAlert = true
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Block \(ownerName)?", isPresented: $showingBlockConfirmation, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task {
                    let success = await viewModel.block(blockedID: currentItem.item.ownerID, blockerID: userID)
                    if success {
                        onBlocked()
                        dismiss()
                    } else {
                        actionAlertMessage = "Something went wrong. Please try again."
                        showingActionAlert = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("", isPresented: $showingActionAlert) {
            Button("OK") {}
        } message: {
            Text(actionAlertMessage)
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            HStack(spacing: 8) {
                OwnerBadge(profile: owner, signedURL: memberPhotoURLs[currentItem.item.ownerID], diameter: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ownerName)
                        .font(Theme.Font.body(15, weight: .medium))
                        .foregroundStyle(Theme.Color.primaryText)
                    Text(currentItem.item.category.rawValue)
                        .font(Theme.Font.body(12))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                Text("\(currentIndex + 1) of \(items.count)")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
        }
        .padding()
    }

    private var photoArea: some View {
        ZStack {
            AsyncImage(url: viewModel.url(for: currentItem)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                } else {
                    Rectangle()
                        .fill(Theme.Color.accent.opacity(0.08))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 16)

            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goToPrevious() }
                Color.clear
                    .contentShape(Rectangle())
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goToNext() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let caption = currentItem.item.caption {
                Text(caption)
                    .font(Theme.Font.headline(24))
                    .foregroundStyle(Theme.Color.primaryText)
            }

            let chips = [currentItem.item.size, currentItem.item.color]
                .compactMap { $0 }
                + currentItem.item.occasionTags
            if !chips.isEmpty {
                Text(chips.joined(separator: " · "))
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.secondaryText)
            }

            if isOwner {
                Divider().overlay(Theme.Color.divider).padding(.top, 8)
                sharedToSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .overlay(alignment: .bottomTrailing) {
            moreMenu
        }
    }

    private var sharedToSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shared to")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.secondaryText)

            if let shareStateErrorMessage = viewModel.shareStateErrorMessage {
                Text(shareStateErrorMessage)
                    .font(Theme.Font.body(12))
                    .foregroundStyle(.red)
            }

            if viewModel.isLoadingShareState {
                ProgressView()
            } else {
                ForEach(viewModel.allClosets) { closet in
                    Button {
                        Task {
                            await viewModel.toggleShare(itemID: currentItem.item.id, closetID: closet.id)
                            onShareChanged()
                        }
                    } label: {
                        HStack {
                            Text(closet.name)
                                .font(Theme.Font.body(15))
                            Spacer()
                            if viewModel.sharedClosetIDs.contains(closet.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Color.accent)
                            }
                        }
                    }
                    .foregroundStyle(Theme.Color.primaryText)
                }
            }
        }
        .padding(.top, 8)
    }

    private var moreMenu: some View {
        Menu {
            if isOwner {
                Button("Edit") {}
                    .disabled(true)
                Button("Delete", role: .destructive) {}
                    .disabled(true)
            } else {
                Button("Report") { showingReportConfirmation = true }
                Button("Block \(ownerName)", role: .destructive) { showingBlockConfirmation = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .padding()
    }

    private func goToNext() {
        currentIndex = min(currentIndex + 1, items.count - 1)
    }

    private func goToPrevious() {
        currentIndex = max(currentIndex - 1, 0)
    }
}
