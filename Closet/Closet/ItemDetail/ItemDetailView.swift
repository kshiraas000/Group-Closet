import SwiftUI

struct ItemDetailView: View {
    @State private var viewModel = ItemDetailViewModel()
    @State private var currentIndex: Int
    @State private var showingReportConfirmation = false
    @State private var showingBlockConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingEditSheet = false
    @State private var showingSharingSheet = false
    @State private var editedItem: Item?
    @State private var showingActionAlert = false
    @State private var actionAlertMessage = ""
    @State private var zoomScale: CGFloat = 1
    @State private var lastZoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    @State private var lastZoomOffset: CGSize = .zero
    @State private var dragTranslation: CGFloat = 0
    @State private var stripDragBase: CGFloat?
    @State private var stripOffset: CGFloat?
    @Environment(\.dismiss) private var dismiss
    let items: [BrowseItem]
    let members: [UserProfile]
    let memberPhotoURLs: [UUID: URL]
    let userID: UUID
    let onShareChanged: () -> Void
    let onBlocked: () -> Void
    let onItemChanged: () -> Void

    init(
        items: [BrowseItem],
        startIndex: Int,
        members: [UserProfile],
        memberPhotoURLs: [UUID: URL] = [:],
        userID: UUID,
        onShareChanged: @escaping () -> Void = {},
        onBlocked: @escaping () -> Void = {},
        onItemChanged: @escaping () -> Void = {}
    ) {
        self.items = items
        self.members = members
        self.memberPhotoURLs = memberPhotoURLs
        self.userID = userID
        self.onShareChanged = onShareChanged
        self.onBlocked = onBlocked
        self.onItemChanged = onItemChanged
        _currentIndex = State(initialValue: startIndex)
    }

    private var currentItem: BrowseItem {
        items[currentIndex]
    }

    private var displayedItem: Item {
        editedItem ?? currentItem.item
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
            // The strip holds one fixed screen position (so it never jumps
            // while swiping) and the photo decides how it reads: a tall
            // photo fills the whole area, so the strip floats fully inside
            // it; a short/landscape photo ends above the strip, so the strip
            // naturally sits below the image on the background instead.
            ZStack(alignment: .bottom) {
                photoArea
                if items.count > 1 {
                    thumbnailStrip
                        .padding(.bottom, 10)
                }
            }
            bottomInfo
        }
        .background(Theme.Color.background)
        .task(id: currentIndex) {
            editedItem = nil
            zoomScale = 1
            lastZoomScale = 1
            zoomOffset = .zero
            lastZoomOffset = .zero
            await viewModel.loadFullResURL(for: currentItem)
            // Prefetch neighbors so they're ready as they slide in mid-swipe.
            if currentIndex + 1 < items.count {
                await viewModel.loadFullResURL(for: items[currentIndex + 1])
            }
            if currentIndex > 0 {
                await viewModel.loadFullResURL(for: items[currentIndex - 1])
            }
            if isOwner {
                await viewModel.loadShareState(itemID: currentItem.item.id)
            }
        }
        .sheet(isPresented: $showingSharingSheet) {
            sharingSheet
        }
        .sheet(isPresented: $showingEditSheet) {
            EditItemView(item: displayedItem) { category, size, color, occasionTags, caption in
                let success = await viewModel.updateItem(
                    itemID: currentItem.item.id,
                    category: category,
                    size: size,
                    color: color,
                    occasionTags: occasionTags,
                    caption: caption
                )
                if success {
                    editedItem = Item(
                        id: currentItem.item.id,
                        ownerID: currentItem.item.ownerID,
                        category: category,
                        size: size.isEmpty ? nil : size,
                        color: color.isEmpty ? nil : color,
                        occasionTags: occasionTags,
                        caption: caption.isEmpty ? nil : caption,
                        createdAt: currentItem.item.createdAt
                    )
                    onItemChanged()
                }
                return success
            }
        }
        .confirmationDialog("Delete this item?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    let success = await viewModel.deleteItem(currentItem)
                    if success {
                        onItemChanged()
                        dismiss()
                    } else {
                        actionAlertMessage = "Something went wrong. Please try again."
                        showingActionAlert = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
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
                    Text(displayedItem.category.rawValue)
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
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Theme.Color.background)
    }

    private var photoArea: some View {
        // GeometryReader pins the image to the exact available size: without
        // it, scaledToFill/scaledToFit inside a flexible frame lets each
        // photo's intrinsic size leak into layout — the view grows past the
        // screen edges, shoving the top bar down and the caption off-screen.
        GeometryReader { geo in
            // Pages are positioned arithmetically rather than by stacking
            // them in an HStack: every page is the same fixed width and sits
            // exactly `pageStride` from its neighbor, so the gap can never
            // vary with a photo's aspect ratio or intrinsic size.
            let pageStride = geo.size.width + pageGutter
            ZStack {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    photoView(for: item, in: geo.size, isCurrent: index == currentIndex)
                        .offset(x: CGFloat(index - currentIndex) * pageStride + dragTranslation)
                }

                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if zoomScale == 1 { goToPrevious() }
                        }
                    Color.clear
                        .contentShape(Rectangle())
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if zoomScale == 1 { goToNext() }
                        }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoomScale = min(max(lastZoomScale * value, 1), 4)
                            zoomOffset = clampedZoomOffset(zoomOffset, in: geo.size)
                        }
                        .onEnded { _ in
                            lastZoomScale = zoomScale
                            if zoomScale == 1 {
                                zoomOffset = .zero
                                lastZoomOffset = .zero
                            } else {
                                zoomOffset = clampedZoomOffset(zoomOffset, in: geo.size)
                                lastZoomOffset = zoomOffset
                            }
                        },
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            if zoomScale > 1 {
                                zoomOffset = clampedZoomOffset(CGSize(
                                    width: lastZoomOffset.width + value.translation.width,
                                    height: lastZoomOffset.height + value.translation.height
                                ), in: geo.size)
                                return
                            }
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let atLeadingEdge = currentIndex == 0 && value.translation.width > 0
                            let atTrailingEdge = currentIndex == items.count - 1 && value.translation.width < 0
                            // Rubber-band resistance past the first/last photo.
                            dragTranslation = (atLeadingEdge || atTrailingEdge)
                                ? value.translation.width / 3
                                : value.translation.width
                        }
                        .onEnded { value in
                            if zoomScale > 1 {
                                lastZoomOffset = zoomOffset
                                return
                            }
                            if abs(value.translation.height) > abs(value.translation.width),
                               value.translation.height > 100 {
                                dismiss()
                                return
                            }
                            let threshold = geo.size.width / 3
                            var target = currentIndex
                            if value.translation.width < -threshold || value.predictedEndTranslation.width < -geo.size.width / 2 {
                                target = min(currentIndex + 1, items.count - 1)
                            } else if value.translation.width > threshold || value.predictedEndTranslation.width > geo.size.width / 2 {
                                target = max(currentIndex - 1, 0)
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                currentIndex = target
                                dragTranslation = 0
                            }
                        }
                )
            )
        }
        .clipped()
    }

    private func photoView(for item: BrowseItem, in size: CGSize, isCurrent: Bool) -> some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .overlay {
                AsyncImage(url: viewModel.url(for: item) ?? item.signedURL) { phase in
                    if case .success(let image) = phase {
                        // Fitted into a deliberately over-tall box so the
                        // binding constraint is always the width: every photo
                        // therefore displays at exactly the page width, with
                        // zero side margins. That's what keeps the visible
                        // gap between photos constant — margins, not the
                        // gutter, are what made it vary by aspect ratio.
                        // Anything taller than the page is cropped by the
                        // .clipped() below; shorter photos stay centered.
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: size.width, height: size.height * 3)
                    } else {
                        Color.clear
                    }
                }
            }
            .clipped()
            .scaleEffect(isCurrent ? zoomScale : 1)
            .offset(isCurrent ? zoomOffset : .zero)
    }

    private func clampedZoomOffset(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let maxX = size.width * (zoomScale - 1) / 2
        let maxY = size.height * (zoomScale - 1) / 2
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private let thumbSize: CGFloat = 44
    private let thumbSpacing: CGFloat = 8
    private let pageGutter: CGFloat = 20

    private func stripAnchorOffset(for index: Int, width: CGFloat) -> CGFloat {
        width / 2 - (CGFloat(index) * (thumbSize + thumbSpacing) + thumbSize / 2)
    }

    private var thumbnailStrip: some View {
        // A Photos-style filmstrip: the strip scrolls continuously under
        // your finger (1:1 tracking, not stepping), the selection follows
        // whichever thumbnail is nearest the center as you drag, and on
        // release the nearest thumbnail snaps to center. Tapping a
        // thumbnail still jumps straight to it.
        GeometryReader { geo in
            let step = thumbSize + thumbSpacing
            let anchored = stripAnchorOffset(for: currentIndex, width: geo.size.width)
            // Deliberately NOT Buttons: a SwiftUI Button claims the touch on
            // press and never hands it to a parent DragGesture, so any drag
            // starting on a thumbnail would be swallowed. Plain views with
            // onTapGesture compose correctly with the strip's drag.
            ZStack(alignment: Alignment(horizontal: .leading, vertical: .center)) {
                Color.clear
                    .contentShape(Rectangle())

                HStack(spacing: thumbSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        AsyncImage(url: item.signedURL) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                Rectangle().fill(Theme.Color.accent.opacity(0.12))
                            }
                        }
                        .frame(width: thumbSize, height: thumbSize)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.Color.accent, lineWidth: index == currentIndex ? 2 : 0)
                        )
                        .opacity(index == currentIndex ? 1 : 0.55)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.15)) {
                                currentIndex = index
                            }
                        }
                    }
                }
                .offset(x: stripOffset ?? anchored)
            }
            // Gesture lives on the full-size container, not the offset
            // HStack — otherwise the hit area slides away with the strip.
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if stripDragBase == nil {
                            stripDragBase = stripOffset ?? anchored
                        }
                        let minOffset = stripAnchorOffset(for: items.count - 1, width: geo.size.width)
                        let maxOffset = stripAnchorOffset(for: 0, width: geo.size.width)
                        let raw = min(max((stripDragBase ?? anchored) + value.translation.width, minOffset), maxOffset)
                        stripOffset = raw
                        let nearest = Int(((geo.size.width / 2 - thumbSize / 2 - raw) / step).rounded())
                        let clamped = max(0, min(items.count - 1, nearest))
                        if clamped != currentIndex {
                            // Photo pager should snap instantly while
                            // scrubbing, not run its page-slide animation.
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                currentIndex = clamped
                            }
                        }
                    }
                    .onEnded { _ in
                        stripDragBase = nil
                        withAnimation(.easeOut(duration: 0.2)) {
                            stripOffset = nil
                        }
                    }
            )
        }
        .frame(height: thumbSize + 12)
    }

    private var detailChipsText: String {
        ([displayedItem.size, displayedItem.color].compactMap { $0 } + displayedItem.occasionTags)
            .joined(separator: " · ")
    }

    private var bottomInfo: some View {
        // Fixed height with always-present lines (blank placeholders when a
        // field is missing): the caption block must never change size, or
        // the photo area — and the strip layered on it — would shift
        // vertically as you page between items with different metadata.
        VStack(alignment: .leading, spacing: 4) {
            Text(displayedItem.caption ?? " ")
                .font(Theme.Font.headline(22))
                .foregroundStyle(Theme.Color.primaryText)
                .lineLimit(1)

            Text(detailChipsText.isEmpty ? " " : detailChipsText)
                .font(Theme.Font.body(13))
                .foregroundStyle(Theme.Color.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .frame(height: 74, alignment: .top)
        .overlay(alignment: .bottomTrailing) {
            moreMenu
        }
    }

    private var sharingSheet: some View {
        NavigationStack {
            List {
                if let shareStateErrorMessage = viewModel.shareStateErrorMessage {
                    Text(shareStateErrorMessage)
                        .font(Theme.Font.body(12))
                        .foregroundStyle(.red)
                        .listRowBackground(Theme.Color.background)
                }

                if viewModel.isLoadingShareState {
                    ProgressView()
                        .listRowBackground(Theme.Color.background)
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
                                    .font(Theme.Font.body(16))
                                Spacer()
                                if viewModel.sharedClosetIDs.contains(closet.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.Color.accent)
                                }
                            }
                        }
                        .foregroundStyle(Theme.Color.primaryText)
                        .listRowBackground(Theme.Color.background)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Shared to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingSharingSheet = false }
                        .tint(Theme.Color.accent)
                }
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            if isOwner {
                Button("Edit") { showingEditSheet = true }
                Button("Manage Sharing") { showingSharingSheet = true }
                Button("Delete", role: .destructive) { showingDeleteConfirmation = true }
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

    // Tap navigation swaps the image directly — only a swipe gets the
    // interactive sliding transition.
    private func goToNext() {
        currentIndex = min(currentIndex + 1, items.count - 1)
    }

    private func goToPrevious() {
        currentIndex = max(currentIndex - 1, 0)
    }
}
