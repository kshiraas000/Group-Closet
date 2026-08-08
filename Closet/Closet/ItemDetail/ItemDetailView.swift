import SwiftUI

struct ItemDetailView: View {
    @State private var viewModel = ItemDetailViewModel()
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss
    let items: [BrowseItem]
    let members: [UserProfile]
    let userID: UUID
    let onShareChanged: () -> Void

    init(items: [BrowseItem], startIndex: Int, members: [UserProfile], userID: UUID, onShareChanged: @escaping () -> Void = {}) {
        self.items = items
        self.members = members
        self.userID = userID
        self.onShareChanged = onShareChanged
        _currentIndex = State(initialValue: startIndex)
    }

    private var currentItem: BrowseItem {
        items[currentIndex]
    }

    private var ownerName: String {
        members.first { $0.id == currentItem.item.ownerID }?.name ?? "Unknown"
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
        .background(Color.black)
        .preferredColorScheme(.dark)
        .task(id: currentIndex) {
            await viewModel.loadFullResURL(for: currentItem)
            if isOwner {
                await viewModel.loadShareState(itemID: currentItem.item.id)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ownerName).bold()
                    Text(currentItem.item.category.rawValue)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                Text("\(currentIndex + 1) of \(items.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                        .fill(.secondary.opacity(0.2))
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        VStack(alignment: .leading, spacing: 4) {
            if let caption = currentItem.item.caption {
                Text(caption).bold()
            }

            let chips = [currentItem.item.size, currentItem.item.color]
                .compactMap { $0 }
                + currentItem.item.occasionTags
            if !chips.isEmpty {
                Text(chips.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if isOwner {
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
            Text("Shared to").font(.footnote).foregroundStyle(.secondary)

            if let shareStateErrorMessage = viewModel.shareStateErrorMessage {
                Text(shareStateErrorMessage).font(.footnote).foregroundStyle(.red)
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
                            Spacer()
                            if viewModel.sharedClosetIDs.contains(closet.id) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .foregroundStyle(.primary)
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
                Button("Report") {}
                    .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
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
