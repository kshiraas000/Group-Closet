# Phase 5: Item Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up the grid cells Phase 4 left as no-ops: tapping an item in `ClosetDetailView`'s grid opens a full-screen detail view (owner, category, full photo, caption, size/color/occasion) with tap-left/tap-right navigation scoped to whatever filtered/sorted set the grid was showing when it was opened, plus an inert "•••" menu (Report / Edit / Delete — all disabled, no backend exists for any of them yet).

**Architecture:** A new `ItemDetailView` + `ItemDetailViewModel` pair (matching the `AddItem`/`Closets` per-screen-view-model convention already used in this codebase) is presented via `.fullScreenCover(item:)` from `ClosetDetailView`, driven by a small `Identifiable` context struct that snapshots `viewModel.filteredItems` and the tapped index at tap time — this snapshot is what makes the "X of Y" counter stay scoped to the set the user opened from, even if the underlying grid's filters change while the detail view is open. Owner name is looked up **client-side** against the already-loaded `members` array (matched by `ownerID`) rather than via a PostgREST embed — Phase 4's final review found that exact embed pattern (`users(name)` on the items query) threw and wiped out the whole grid whenever an item's sharer had left the closet; looking it up against already-loaded data instead just returns `nil` (shown as "Unknown") for that case, with no query risk at all.

**Tech Stack:** SwiftUI, `@Observable`, supabase-swift Storage (`createSignedURL` with `TransformOptions`, same API Phase 4 verified against the installed package).

## Global Constraints

- iOS 17.0 minimum deployment target, SwiftUI `NavigationStack` + `@Observable` view models (unchanged from prior phases)
- No backend/migration changes in this phase — the "•••" menu exists visually but every option is `.disabled(true)`; Report (Phase 7) and item Edit/Delete (no `UPDATE`/`DELETE` grant exists on `items`/`item_photos` yet) are both unimplemented on purpose.
- Any file calling `.storage.from(...)` needs `import Storage` in addition to `import Supabase`.
- Testing approach: per this project's established convention (Phase 2/3/4 precedent), tasks below follow implement → verify build → manual QA → commit, not TDD. No new pgTAP coverage is needed since this phase has no schema/RLS changes.
- `UserProfile.photoURL` is never populated anywhere in the app today (only write site, `OnboardingViewModel.swift`, always sets it to `nil`) — the owner "avatar" in the top bar is a placeholder system icon, not a real photo. Do not add photo-fetching logic for it; there is nothing to fetch yet.
- Tap navigation: right third of the photo → next item (clamped at the last item, no wraparound); left third → previous item (clamped at the first item, no wraparound); middle third → no-op. Not specified beyond this by the product spec.
- The detail view forces `.preferredColorScheme(.dark)`. This is a functional requirement, not visual design/polish (which is deferred to a later dedicated pass per prior product decision): the screen has a hardcoded black background, and without forcing dark appearance, default text/icon colors would render black-on-black in a device set to Light Mode, making the screen unusable, not just unstyled.
- The "•••" menu's options depend on whether the *currently displayed* item (not the item the sheet was opened with) is owned by the viewer — recompute per navigation, since ownership varies item-to-item within a set.

---

## File Structure

- Create: `Closet/Closet/ItemDetail/ItemDetailViewModel.swift` — caches one full-resolution signed URL per visited item
- Create: `Closet/Closet/ItemDetail/ItemDetailView.swift` — the full-screen view: top bar, photo with tap zones, caption/chips, "•••" menu
- Modify: `Closet/Closet/Closets/ClosetDetailView.swift` — grid cells become tappable, opening `ItemDetailView` via `.fullScreenCover`

---

### Task 1: ItemDetailViewModel + ItemDetailView

**Files:**
- Create: `Closet/Closet/ItemDetail/ItemDetailViewModel.swift`
- Create: `Closet/Closet/ItemDetail/ItemDetailView.swift`

**Interfaces:**
- Consumes: `BrowseItem` (Phase 4), `UserProfile` (Phase 1/2), `Item`/`ItemCategory` (Phase 3), `SupabaseService.shared`
- Produces: `ItemDetailViewModel` (`func url(for item: BrowseItem) -> URL?`, `func loadFullResURL(for item: BrowseItem) async`); `ItemDetailView(items: [BrowseItem], startIndex: Int, members: [UserProfile], userID: UUID)` — Task 2 presents this from `ClosetDetailView`

This task is not reachable from anywhere in the app yet (nothing presents it) — it's verified by build success only. Task 2 wires it in and does the first real manual QA of the full flow.

- [ ] **Step 1: Write the view model**

Create `Closet/Closet/ItemDetail/ItemDetailViewModel.swift`:

```swift
import Foundation
import Storage
import Supabase

@Observable
final class ItemDetailViewModel {
    private var fullResURLs: [UUID: URL] = [:]
    private let client = SupabaseService.shared

    func url(for item: BrowseItem) -> URL? {
        fullResURLs[item.id]
    }

    func loadFullResURL(for item: BrowseItem) async {
        guard fullResURLs[item.id] == nil, let path = item.photoPath else { return }
        let url = try? await client.storage.from("item-photos").createSignedURL(
            path: path,
            expiresIn: 3600,
            transform: TransformOptions(width: 1200, resize: .contain)
        )
        if let url {
            fullResURLs[item.id] = url
        }
    }
}
```

- [ ] **Step 2: Write the detail view**

Create `Closet/Closet/ItemDetail/ItemDetailView.swift`:

```swift
import SwiftUI

struct ItemDetailView: View {
    @State private var viewModel = ItemDetailViewModel()
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss
    let items: [BrowseItem]
    let members: [UserProfile]
    let userID: UUID

    init(items: [BrowseItem], startIndex: Int, members: [UserProfile], userID: UUID) {
        self.items = items
        self.members = members
        self.userID = userID
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .overlay(alignment: .bottomTrailing) {
            moreMenu
        }
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
```

- [ ] **Step 3: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Closet/Closet/ItemDetail/ItemDetailViewModel.swift Closet/Closet/ItemDetail/ItemDetailView.swift
git commit -m "Add ItemDetailView and its view model (not yet reachable)"
```

---

### Task 2: Wire tap-to-open into Closet Detail

**Files:**
- Modify: `Closet/Closet/Closets/ClosetDetailView.swift`

**Interfaces:**
- Consumes: `ItemDetailView` (Task 1), `BrowseItem`/`ClosetDetailViewModel.filteredItems` (Phase 4)
- Produces: a working end-to-end tap-to-detail flow reachable from any Closet's grid

- [ ] **Step 1: Make grid cells tappable and present the detail view**

Full new file content for `Closet/Closet/Closets/ClosetDetailView.swift`:

```swift
import SwiftUI

private struct ItemDetailContext: Identifiable {
    let id = UUID()
    let items: [BrowseItem]
    let startIndex: Int
}

struct ClosetDetailView: View {
    @State private var viewModel = ClosetDetailViewModel()
    @State private var showingLeaveConfirmation = false
    @State private var showingAddItem = false
    @State private var detailContext: ItemDetailContext?
    @Environment(\.dismiss) private var dismiss
    let closet: Closet
    let userID: UUID
    let onLeft: () -> Void

    private let gridColumns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        List {
            Section("Members") {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    ForEach(viewModel.members) { member in
                        Text(member.name)
                    }
                }
            }
            Section("Items") {
                filterChipsRow

                if viewModel.filteredItems.isEmpty {
                    Text(viewModel.items.isEmpty ? "No items yet" : "No items match your filters")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { index, browseItem in
                            Button {
                                detailContext = ItemDetailContext(items: viewModel.filteredItems, startIndex: index)
                            } label: {
                                itemCell(browseItem)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                ShareLink(item: "Join my Closet \"\(closet.name)\" on the Closet app — invite code: \(closet.inviteCode)") {
                    Label("Share Invite", systemImage: "square.and.arrow.up")
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            Section {
                Button("Leave Closet", role: .destructive) {
                    showingLeaveConfirmation = true
                }
            }
        }
        .searchable(text: $viewModel.filters.searchText)
        .navigationTitle(closet.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await viewModel.load(closetID: closet.id)
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemView(closetID: closet.id, userID: userID) {
                Task { await viewModel.load(closetID: closet.id) }
            }
        }
        .fullScreenCover(item: $detailContext) { context in
            ItemDetailView(items: context.items, startIndex: context.startIndex, members: viewModel.members, userID: userID)
        }
        .confirmationDialog(
            "Leave \(closet.name)?",
            isPresented: $showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task {
                    if await viewModel.leave(closetID: closet.id, userID: userID) {
                        onLeft()
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("All Categories") { viewModel.filters.category = nil }
                    ForEach(ItemCategory.allCases) { category in
                        Button(category.rawValue) { viewModel.filters.category = category }
                    }
                } label: {
                    chipLabel("Category", value: viewModel.filters.category?.rawValue)
                }

                Menu {
                    Button("Everyone") { viewModel.filters.ownerID = nil }
                    ForEach(viewModel.members) { member in
                        Button(member.name) { viewModel.filters.ownerID = member.id }
                    }
                } label: {
                    chipLabel("Person", value: viewModel.members.first { $0.id == viewModel.filters.ownerID }?.name)
                }

                if !viewModel.availableSizes.isEmpty {
                    Menu {
                        Button("Any Size") { viewModel.filters.size = nil }
                        ForEach(viewModel.availableSizes, id: \.self) { size in
                            Button(size) { viewModel.filters.size = size }
                        }
                    } label: {
                        chipLabel("Size", value: viewModel.filters.size)
                    }
                }

                if !viewModel.availableColors.isEmpty {
                    Menu {
                        Button("Any Color") { viewModel.filters.color = nil }
                        ForEach(viewModel.availableColors, id: \.self) { color in
                            Button(color) { viewModel.filters.color = color }
                        }
                    } label: {
                        chipLabel("Color", value: viewModel.filters.color)
                    }
                }

                if !viewModel.availableOccasions.isEmpty {
                    Menu {
                        Button("Any Occasion") { viewModel.filters.occasion = nil }
                        ForEach(viewModel.availableOccasions, id: \.self) { occasion in
                            Button(occasion) { viewModel.filters.occasion = occasion }
                        }
                    } label: {
                        chipLabel("Occasion", value: viewModel.filters.occasion)
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private func chipLabel(_ title: String, value: String?) -> some View {
        Text(value ?? title)
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(value == nil ? Color.secondary.opacity(0.15) : Color.blue.opacity(0.2))
            .clipShape(Capsule())
    }

    private func itemCell(_ browseItem: BrowseItem) -> some View {
        AsyncImage(url: browseItem.signedURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(height: 110)
        .clipped()
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manually verify the full Item Detail experience**

On a device or Simulator, in a Closet with several items (some yours, some belonging to other members if possible, spanning different categories/captions/sizes/colors/occasions):

1. Tap a grid cell — confirm a full-screen dark view opens showing that item's photo (may take a moment to load the larger image), the owner's name and category in the top bar, and the correct "X of Y" position for where it sits in the currently-filtered grid.
2. Tap the right third of the photo repeatedly — confirm it advances through the set in order, the counter updates each time, and tapping again on the last item does nothing (no crash, no wraparound to the first item).
3. Tap the left third repeatedly — confirm it goes backward the same way, and tapping again on the first item does nothing.
4. Tap the middle third of the photo — confirm nothing happens.
5. Confirm the caption (if the item has one) and a size/color/occasion line appear below the photo, updating correctly as you navigate between items.
6. Tap the "•••" button — if you own the currently-displayed item, confirm you see disabled "Edit" and "Delete" options; if you don't own it, confirm you see a disabled "Report" option instead. Navigate to a different item you don't own (or do own) and reopen the menu — confirm the options update accordingly.
7. Apply a filter or search in the grid first (e.g. one category), then tap into an item from that filtered view — confirm the "X of Y" counter and navigation are scoped to just the filtered items, not the whole closet.
8. Tap the X button — confirm it dismisses back to the grid.

- [ ] **Step 4: Commit**

```bash
git add Closet/Closet/Closets/ClosetDetailView.swift
git commit -m "Wire tap-to-open Item Detail into the Closet grid"
```

---

## Roadmap: Later Phases (not yet planned in detail)

- **Phase 6 — My Clothes:** cross-closet item management, per-item share toggles
- **Phase 7 — Report & Block:** reason picker, mutual hide, `reports`/`blocks` RLS — this is what would make Phase 5's "Report" menu option functional
- **Phase 8 — Profile:** edit profile, blocked list, delete account — likely where profile photo upload would be added, which would make Phase 5's owner avatar show a real photo
- **Design pass:** deferred until Phases 5-8 are functionally complete (product decision, 2026-08-06) — real visual design (Retro-inspired dark/photo-forward look) across the whole app happens in one dedicated pass, not per-phase
