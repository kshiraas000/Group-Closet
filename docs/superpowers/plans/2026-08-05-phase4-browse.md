# Phase 4: Browse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `ClosetDetailView`'s bare-bones "Items" list (Phase 3 throwaway scaffolding) with a real edge-to-edge photo grid — newest first, filterable by category/person/size/color/occasion, searchable by caption/category/color, with photos resolved from Storage paths into displayable signed URLs.

**Architecture:** `ClosetDetailViewModel.load` is extended to embed `item_photos` and the owner's `users.name` in its existing `item_shares` query, decoding into a new display-only `BrowseItem` (wraps the existing `Item` + photo path + owner name + a resolved signed URL) — `Item` itself, which maps 1:1 to the `items` table and is used elsewhere, is left untouched. After items load, one signed URL per distinct photo path is resolved concurrently via `withTaskGroup` (supabase-swift 2.54.1's batch `createSignedURLs` has no resize-transform parameter, so per-item `createSignedURL(path:expiresIn:transform:)` calls are fired concurrently instead — see Task 1). Filtering and search run entirely client-side over the already-loaded items via a `BrowseFilters` struct and a computed `filteredItems` — no re-querying Supabase per filter change.

**Tech Stack:** SwiftUI, `@Observable`, PostgREST nested embeds, supabase-swift Storage (`createSignedURL` with `TransformOptions`).

## Global Constraints

- iOS 17.0 minimum deployment target, SwiftUI `NavigationStack` + `@Observable` view models (unchanged from prior phases)
- No backend/migration changes in this phase — Phase 3's `storage.objects` SELECT policy (`supabase/migrations/20260804000004_items_storage_rls.sql`) already gates `item-photos` access by ownership/sharing, and signed-URL generation goes through that same RLS. Do not add a migration for this phase.
- Any file calling `.storage.from(...)` needs `import Storage` in addition to `import Supabase`/`import PostgREST` — same module-splitting gap called out in Phase 3's plan.
- **supabase-swift 2.54.1's batch `createSignedURLs(paths:expiresIn:)` does not accept a `transform` parameter** — only the single-item `createSignedURL(path:expiresIn:download:transform:cacheNonce:)` does (verified directly against the checked-out package source, `Sources/Storage/StorageFileApi.swift`). Thumbnails must be resolved via concurrent per-path `createSignedURL` calls (Task 1), not a single batch call.
- Testing approach: per the product spec §6 ("manual/exploratory QA for SwiftUI flows... no formal TDD process for the UI layer") and Phase 2/3's precedent in this codebase, tasks below follow implement → verify build → manual QA → commit, not red/green TDD. No new pgTAP coverage is needed since this phase has no schema/RLS changes.
- Filter combination logic: AND across chip types, single-select within each type (confirmed design decision — not "OR within a chip type").
- Chip values for size/color/occasion are derived from the currently-loaded items (distinct, non-empty), not a fixed predefined list.

---

## File Structure

- Modify: `Closet/Closet/Closets/ClosetDetailViewModel.swift` — `BrowseItem`, `BrowseFilters`, extended `load` query, concurrent signed-URL resolution, `filteredItems`/`availableSizes`/`availableColors`/`availableOccasions`
- Modify: `Closet/Closet/Closets/ClosetDetailView.swift` — Items section becomes filter chips + edge-to-edge photo grid + `.searchable`

---

### Task 1: BrowseItem model, extended items query, and signed URL resolution

**Files:**
- Modify: `Closet/Closet/Closets/ClosetDetailViewModel.swift`
- Modify: `Closet/Closet/Closets/ClosetDetailView.swift`

**Interfaces:**
- Consumes: `Item`/`ItemCategory` (Phase 3), `UserProfile` (Phase 1/2), `Closet` (Phase 2), `SupabaseService.shared`
- Produces: `struct BrowseItem: Identifiable { var id: UUID; let item: Item; let photoPath: String?; let ownerName: String; var signedURL: URL? = nil }`; `ClosetDetailViewModel.items: [BrowseItem]` (was `[Item]`) sorted newest-first; `ClosetDetailViewModel.load(closetID:)` (signature unchanged) — Task 2 adds filtering on top of this same `items` array

This task keeps `ClosetDetailView` building on top of the new data shape with the smallest possible edit (rename `item` → `browseItem`, add a small thumbnail so the signed-URL fetch is actually visible/verifiable) — it does **not** build the final chip/grid UI. Task 2 replaces this Items section wholesale.

- [ ] **Step 1: Replace `ClosetDetailViewModel.swift`**

Full new file content for `Closet/Closet/Closets/ClosetDetailViewModel.swift`:

```swift
import Foundation
import PostgREST
import Storage
import Supabase

private struct MemberRow: Decodable {
    let users: UserProfile
}

private struct PhotoRow: Decodable {
    let photoURL: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case photoURL = "photo_url"
        case position
    }
}

private struct OwnerRow: Decodable {
    let name: String
}

private struct RawBrowseItem: Decodable {
    let id: UUID
    let ownerID: UUID
    let category: ItemCategory
    let size: String?
    let color: String?
    let occasionTags: [String]
    let caption: String?
    let createdAt: Date
    let itemPhotos: [PhotoRow]
    let users: OwnerRow

    enum CodingKeys: String, CodingKey {
        case id, category, size, color, caption
        case ownerID = "owner_id"
        case occasionTags = "occasion_tags"
        case createdAt = "created_at"
        case itemPhotos = "item_photos"
        case users
    }
}

private struct ItemShareRow: Decodable {
    let items: RawBrowseItem
}

struct BrowseItem: Identifiable {
    var id: UUID { item.id }
    let item: Item
    let photoPath: String?
    let ownerName: String
    var signedURL: URL? = nil
}

@Observable
final class ClosetDetailViewModel {
    var members: [UserProfile] = []
    var items: [BrowseItem] = []
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    func load(closetID: UUID) async {
        isLoading = true
        defer { isLoading = false }
        var failures: [String] = []

        do {
            let rows: [MemberRow] = try await client
                .from("closet_members")
                .select("users(id, name, photo_url, sizes)")
                .eq("closet_id", value: closetID)
                .execute()
                .value
            members = rows.map(\.users)
        } catch {
            failures.append(error.localizedDescription)
        }

        do {
            let rows: [ItemShareRow] = try await client
                .from("item_shares")
                .select("items(*, item_photos(photo_url, position), users(name))")
                .eq("closet_id", value: closetID)
                .execute()
                .value
            items = rows
                .map { Self.makeBrowseItem($0.items) }
                .sorted { $0.item.createdAt > $1.item.createdAt }
            await loadSignedURLs()
        } catch {
            failures.append(error.localizedDescription)
        }

        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private static func makeBrowseItem(_ raw: RawBrowseItem) -> BrowseItem {
        let item = Item(
            id: raw.id,
            ownerID: raw.ownerID,
            category: raw.category,
            size: raw.size,
            color: raw.color,
            occasionTags: raw.occasionTags,
            caption: raw.caption,
            createdAt: raw.createdAt
        )
        let photoPath = raw.itemPhotos.first(where: { $0.position == 0 })?.photoURL
        return BrowseItem(item: item, photoPath: photoPath, ownerName: raw.users.name)
    }

    private func loadSignedURLs() async {
        let paths = Set(items.compactMap(\.photoPath))
        guard !paths.isEmpty else { return }

        var resolved: [String: URL] = [:]
        await withTaskGroup(of: (String, URL?).self) { group in
            for path in paths {
                group.addTask { [client] in
                    let url = try? await client.storage.from("item-photos").createSignedURL(
                        path: path,
                        expiresIn: 3600,
                        transform: TransformOptions(width: 400, height: 400, resize: .cover)
                    )
                    return (path, url)
                }
            }
            for await (path, url) in group {
                if let url { resolved[path] = url }
            }
        }

        for index in items.indices {
            if let path = items[index].photoPath {
                items[index].signedURL = resolved[path]
            }
        }
    }

    func leave(closetID: UUID, userID: UUID) async -> Bool {
        errorMessage = nil
        do {
            try await client
                .from("closet_members")
                .delete()
                .eq("closet_id", value: closetID)
                .eq("user_id", value: userID)
                .execute()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
```

- [ ] **Step 2: Update `ClosetDetailView.swift`'s Items section to match the new data shape**

Full new file content for `Closet/Closet/Closets/ClosetDetailView.swift`:

```swift
import SwiftUI

struct ClosetDetailView: View {
    @State private var viewModel = ClosetDetailViewModel()
    @State private var showingLeaveConfirmation = false
    @State private var showingAddItem = false
    @Environment(\.dismiss) private var dismiss
    let closet: Closet
    let userID: UUID
    let onLeft: () -> Void

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
                if viewModel.items.isEmpty {
                    Text("No items yet").foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.items) { browseItem in
                        HStack {
                            AsyncImage(url: browseItem.signedURL) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFill()
                                } else {
                                    Rectangle().fill(.secondary.opacity(0.2))
                                }
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading) {
                                Text(browseItem.item.category.rawValue)
                                if let caption = browseItem.item.caption {
                                    Text(caption).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
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
}
```

- [ ] **Step 3: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manually verify signed URLs resolve**

On a device or Simulator, signed in as a user with at least one item saved (from Phase 3 testing, or add one now): open that Closet → confirm each row in "Items" now shows a small (44×44) thumbnail of the item's actual photo next to its category/caption, instead of no image. If a photo fails to resolve, confirm a plain gray box shows instead of a crash (this exercises the `try?` fallback in `loadSignedURLs`). Also confirm items appear newest-first if you have more than one.

- [ ] **Step 5: Commit**

```bash
git add Closet/Closet/Closets/ClosetDetailViewModel.swift Closet/Closet/Closets/ClosetDetailView.swift
git commit -m "Load item photos and owner names, resolving Storage paths to signed URLs"
```

---

### Task 2: Filter chips, search, and edge-to-edge grid

**Files:**
- Modify: `Closet/Closet/Closets/ClosetDetailViewModel.swift`
- Modify: `Closet/Closet/Closets/ClosetDetailView.swift`

**Interfaces:**
- Consumes: `BrowseItem`, `ClosetDetailViewModel.items` (Task 1), `ItemCategory` (Phase 3), `UserProfile` (Phase 1/2)
- Produces: `struct BrowseFilters` (`category: ItemCategory?`, `ownerID: UUID?`, `size: String?`, `color: String?`, `occasion: String?`, `searchText: String`); `ClosetDetailViewModel.filters: BrowseFilters`, `.filteredItems: [BrowseItem]`, `.availableSizes/.availableColors/.availableOccasions: [String]` — the completed Phase 4 Browse UI

- [ ] **Step 1: Add filters and derived-value computed properties to the view model**

Full new file content for `Closet/Closet/Closets/ClosetDetailViewModel.swift`:

```swift
import Foundation
import PostgREST
import Storage
import Supabase

private struct MemberRow: Decodable {
    let users: UserProfile
}

private struct PhotoRow: Decodable {
    let photoURL: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case photoURL = "photo_url"
        case position
    }
}

private struct OwnerRow: Decodable {
    let name: String
}

private struct RawBrowseItem: Decodable {
    let id: UUID
    let ownerID: UUID
    let category: ItemCategory
    let size: String?
    let color: String?
    let occasionTags: [String]
    let caption: String?
    let createdAt: Date
    let itemPhotos: [PhotoRow]
    let users: OwnerRow

    enum CodingKeys: String, CodingKey {
        case id, category, size, color, caption
        case ownerID = "owner_id"
        case occasionTags = "occasion_tags"
        case createdAt = "created_at"
        case itemPhotos = "item_photos"
        case users
    }
}

private struct ItemShareRow: Decodable {
    let items: RawBrowseItem
}

struct BrowseItem: Identifiable {
    var id: UUID { item.id }
    let item: Item
    let photoPath: String?
    let ownerName: String
    var signedURL: URL? = nil
}

struct BrowseFilters: Equatable {
    var category: ItemCategory?
    var ownerID: UUID?
    var size: String?
    var color: String?
    var occasion: String?
    var searchText: String = ""
}

@Observable
final class ClosetDetailViewModel {
    var members: [UserProfile] = []
    var items: [BrowseItem] = []
    var filters = BrowseFilters()
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    var filteredItems: [BrowseItem] {
        items.filter { browseItem in
            if let category = filters.category, browseItem.item.category != category {
                return false
            }
            if let ownerID = filters.ownerID, browseItem.item.ownerID != ownerID {
                return false
            }
            if let size = filters.size, browseItem.item.size != size {
                return false
            }
            if let color = filters.color, browseItem.item.color != color {
                return false
            }
            if let occasion = filters.occasion, !browseItem.item.occasionTags.contains(occasion) {
                return false
            }
            if !filters.searchText.isEmpty {
                let query = filters.searchText.lowercased()
                let haystack = [
                    browseItem.item.caption,
                    browseItem.item.category.rawValue,
                    browseItem.item.color
                ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
                if !haystack.contains(query) {
                    return false
                }
            }
            return true
        }
    }

    var availableSizes: [String] {
        Array(Set(items.compactMap { $0.item.size }.filter { !$0.isEmpty })).sorted()
    }

    var availableColors: [String] {
        Array(Set(items.compactMap { $0.item.color }.filter { !$0.isEmpty })).sorted()
    }

    var availableOccasions: [String] {
        Array(Set(items.flatMap { $0.item.occasionTags })).sorted()
    }

    func load(closetID: UUID) async {
        isLoading = true
        defer { isLoading = false }
        var failures: [String] = []

        do {
            let rows: [MemberRow] = try await client
                .from("closet_members")
                .select("users(id, name, photo_url, sizes)")
                .eq("closet_id", value: closetID)
                .execute()
                .value
            members = rows.map(\.users)
        } catch {
            failures.append(error.localizedDescription)
        }

        do {
            let rows: [ItemShareRow] = try await client
                .from("item_shares")
                .select("items(*, item_photos(photo_url, position), users(name))")
                .eq("closet_id", value: closetID)
                .execute()
                .value
            items = rows
                .map { Self.makeBrowseItem($0.items) }
                .sorted { $0.item.createdAt > $1.item.createdAt }
            await loadSignedURLs()
        } catch {
            failures.append(error.localizedDescription)
        }

        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private static func makeBrowseItem(_ raw: RawBrowseItem) -> BrowseItem {
        let item = Item(
            id: raw.id,
            ownerID: raw.ownerID,
            category: raw.category,
            size: raw.size,
            color: raw.color,
            occasionTags: raw.occasionTags,
            caption: raw.caption,
            createdAt: raw.createdAt
        )
        let photoPath = raw.itemPhotos.first(where: { $0.position == 0 })?.photoURL
        return BrowseItem(item: item, photoPath: photoPath, ownerName: raw.users.name)
    }

    private func loadSignedURLs() async {
        let paths = Set(items.compactMap(\.photoPath))
        guard !paths.isEmpty else { return }

        var resolved: [String: URL] = [:]
        await withTaskGroup(of: (String, URL?).self) { group in
            for path in paths {
                group.addTask { [client] in
                    let url = try? await client.storage.from("item-photos").createSignedURL(
                        path: path,
                        expiresIn: 3600,
                        transform: TransformOptions(width: 400, height: 400, resize: .cover)
                    )
                    return (path, url)
                }
            }
            for await (path, url) in group {
                if let url { resolved[path] = url }
            }
        }

        for index in items.indices {
            if let path = items[index].photoPath {
                items[index].signedURL = resolved[path]
            }
        }
    }

    func leave(closetID: UUID, userID: UUID) async -> Bool {
        errorMessage = nil
        do {
            try await client
                .from("closet_members")
                .delete()
                .eq("closet_id", value: closetID)
                .eq("user_id", value: userID)
                .execute()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
```

- [ ] **Step 2: Replace the Items section with filter chips + edge-to-edge grid, and add search**

Full new file content for `Closet/Closet/Closets/ClosetDetailView.swift`:

```swift
import SwiftUI

struct ClosetDetailView: View {
    @State private var viewModel = ClosetDetailViewModel()
    @State private var showingLeaveConfirmation = false
    @State private var showingAddItem = false
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
                        ForEach(viewModel.filteredItems) { browseItem in
                            itemCell(browseItem)
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

- [ ] **Step 3: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manually verify the full Browse experience**

On a device or Simulator, in a Closet with several items spanning different categories, owners, and (if you set them during Add Item) sizes/colors/occasion tags:

1. Confirm a horizontal row of filter chips appears above an edge-to-edge multi-column grid of photo thumbnails, newest item first.
2. Tap the Category chip, pick a specific category — confirm the grid narrows to only that category and the chip's label updates to show the selected value. Reopen the menu and pick "All Categories" — confirm all items return.
3. Repeat for the Person chip (pick a specific member, confirm narrowing, then "Everyone" to clear).
4. If the closet has items with different sizes, colors, or occasion tags, repeat for those chips too (they only appear when at least one item has a non-empty value for that field).
5. Select two chips at once (e.g. a Category and a Person that both match at least one common item) — confirm only items matching both selections show.
6. Type into the search field — confirm the grid narrows to items whose caption, category, or color contains the typed text (case-insensitive); clear the search and confirm everything returns.
7. In a Closet with zero items, confirm "No items yet" shows. In a non-empty Closet, pick a filter combination that matches nothing and confirm "No items match your filters" shows instead (distinguishing the two empty states).
8. Confirm thumbnails show real photos (not placeholders) for items that have a completed photo upload from Phase 3.

- [ ] **Step 5: Commit**

```bash
git add Closet/Closet/Closets/ClosetDetailViewModel.swift Closet/Closet/Closets/ClosetDetailView.swift
git commit -m "Add filter chips, search, and edge-to-edge photo grid to Closet Detail"
```

---

## Roadmap: Later Phases (not yet planned in detail)

- **Phase 5 — Item Detail:** Retro-style full-screen view, tap navigation within the filtered set (wires up the grid cells this phase left as no-ops)
- **Phase 6 — My Clothes:** cross-closet item management, per-item share toggles
- **Phase 7 — Report & Block:** reason picker, mutual hide, `reports`/`blocks` RLS
- **Phase 8 — Profile:** edit profile, blocked list, delete account
