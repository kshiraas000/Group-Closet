# Phase 6: My Clothes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `MainTabView`'s bare-bones "My Clothes" stub with a real cross-closet grid of everything the current user owns (filterable/searchable, reusing Phase 4's grid UX), and let owners manage which Closets can see an item via a new "Shared to:" toggle list inside `ItemDetailView`.

**Architecture:** `BrowseItem`/`BrowseFilters`/the filtering logic move out of `ClosetDetailViewModel` into a shared `Closet/Closet/Models/BrowseItem.swift`, since `MyClothesViewModel` is now a second real consumer of the exact same filtering behavior over a differently-sourced `[BrowseItem]` array (items owned by the user, queried directly from `items`, versus items shared into one Closet via `item_shares`). `MyClothesView` reuses the existing `ItemDetailView(items:startIndex:members:userID:)` interface unchanged — it passes a one-element `members` array containing just the viewer's own profile, since every item shown in My Clothes is owned by the viewer, so the existing owner-name lookup resolves correctly with no interface change. The one new backend capability is an `item_shares` DELETE policy (owners can unshare their own items) — Phase 3 deliberately never granted this since nothing needed it before. `ItemDetailView` gains a "Shared to:" section, visible only to the owner, that always re-fetches actual share state after every toggle rather than updating optimistically.

**Tech Stack:** SwiftUI, `@Observable`, PostgREST, supabase-swift Storage, pgTAP.

## Global Constraints

- iOS 17.0 minimum deployment target, SwiftUI `NavigationStack` + `@Observable` view models (unchanged from prior phases)
- Testing approach: Task 2 (the only backend/RLS change) gets real pgTAP coverage, matching the project's established practice for RLS changes. Tasks 1/3/4 (client-only) follow implement → verify build → manual QA → commit, not TDD.
- Any file calling `.storage.from(...)` needs `import Storage` in addition to `import Supabase`. `ItemDetailViewModel` additionally needs `import PostgREST` starting this phase, since it now queries `closets`/`item_shares` directly (previously it only touched Storage).
- No confirmation dialog before unsharing (confirmed product decision) — toggling a Closet off in "Shared to:" is immediate and reversible, exactly like toggling it back on.
- Share-toggle state (`allClosets`, `sharedClosetIDs`) is always re-fetched from the server after every toggle attempt, success or failure — never flipped optimistically client-side.
- My Clothes' filter chips are Category/Size/Color/Occasion/Search only — no Person chip (every item shown is already owned by the viewer, so filtering by owner would be a no-op).
- Item Edit/Delete stay disabled in the "•••" menu exactly as Phase 5 left them — no `UPDATE`/`DELETE` grant on `items`/`item_photos` this phase. Only `item_shares` gets a new grant.
- The stale-index tap-handler fix (Task 1) touches both `ClosetDetailView` (existing) and `MyClothesView` (new, Task 3) — look up the tapped item's index within the snapshot by ID, never trust a render-time-captured index.

---

## File Structure

- Create: `Closet/Closet/Models/BrowseItem.swift` — `BrowseItem`, `BrowseFilters`, `BrowseFiltering` (shared filtering logic)
- Modify: `Closet/Closet/Closets/ClosetDetailViewModel.swift` — forward to `BrowseFiltering` instead of duplicating it
- Modify: `Closet/Closet/Closets/ClosetDetailView.swift` — stale-index-safe tap handler
- Create: `supabase/migrations/20260808000000_item_shares_delete_policy.sql` — `item_shares` DELETE grant + policy
- Modify: `supabase/tests/database/items_rls.sql` — pgTAP coverage for the new policy
- Create: `Closet/Closet/MyClothes/MyClothesViewModel.swift`, `Closet/Closet/MyClothes/MyClothesView.swift`
- Modify: `Closet/Closet/MainTabView.swift` — wire in `MyClothesView`
- Modify: `Closet/Closet/ItemDetail/ItemDetailViewModel.swift`, `Closet/Closet/ItemDetail/ItemDetailView.swift` — "Shared to:" section

---

### Task 1: Extract shared filtering logic + fix the stale-index tap handler

**Files:**
- Create: `Closet/Closet/Models/BrowseItem.swift`
- Modify: `Closet/Closet/Closets/ClosetDetailViewModel.swift`
- Modify: `Closet/Closet/Closets/ClosetDetailView.swift`

**Interfaces:**
- Consumes: `Item`/`ItemCategory` (Phase 3)
- Produces: `struct BrowseItem: Identifiable`, `struct BrowseFilters: Equatable`, `enum BrowseFiltering { static func filteredItems(_:filters:) -> [BrowseItem]; static func availableSizes(_:) -> [String]; static func availableColors(_:) -> [String]; static func availableOccasions(_:) -> [String] }` — Task 3's `MyClothesViewModel` consumes these directly

This task is a pure refactor (move `BrowseItem`/`BrowseFilters` to a shared file, forward `ClosetDetailViewModel`'s computed properties to it) plus a bug fix (the tap handler) — Browse's actual behavior should be unchanged except for the fix itself.

- [ ] **Step 1: Create the shared filtering file**

Create `Closet/Closet/Models/BrowseItem.swift`:

```swift
import Foundation

struct BrowseItem: Identifiable {
    var id: UUID { item.id }
    let item: Item
    let photoPath: String?
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

enum BrowseFiltering {
    static func filteredItems(_ items: [BrowseItem], filters: BrowseFilters) -> [BrowseItem] {
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

    static func availableSizes(_ items: [BrowseItem]) -> [String] {
        Array(Set(items.compactMap { $0.item.size }.filter { !$0.isEmpty })).sorted()
    }

    static func availableColors(_ items: [BrowseItem]) -> [String] {
        Array(Set(items.compactMap { $0.item.color }.filter { !$0.isEmpty })).sorted()
    }

    static func availableOccasions(_ items: [BrowseItem]) -> [String] {
        Array(Set(items.flatMap { $0.item.occasionTags })).sorted()
    }
}
```

- [ ] **Step 2: Update ClosetDetailViewModel to use the shared logic**

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

    enum CodingKeys: String, CodingKey {
        case id, category, size, color, caption
        case ownerID = "owner_id"
        case occasionTags = "occasion_tags"
        case createdAt = "created_at"
        case itemPhotos = "item_photos"
    }
}

private struct ItemShareRow: Decodable {
    let items: RawBrowseItem
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
        BrowseFiltering.filteredItems(items, filters: filters)
    }

    var availableSizes: [String] {
        BrowseFiltering.availableSizes(items)
    }

    var availableColors: [String] {
        BrowseFiltering.availableColors(items)
    }

    var availableOccasions: [String] {
        BrowseFiltering.availableOccasions(items)
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
                .select("items(*, item_photos(photo_url, position))")
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
        return BrowseItem(item: item, photoPath: photoPath)
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

- [ ] **Step 3: Fix the stale-index tap handler in ClosetDetailView**

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
                        ForEach(viewModel.filteredItems) { browseItem in
                            Button {
                                openDetail(for: browseItem)
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

    private func openDetail(for browseItem: BrowseItem) {
        let snapshot = viewModel.filteredItems
        if let index = snapshot.firstIndex(where: { $0.id == browseItem.id }) {
            detailContext = ItemDetailContext(items: snapshot, startIndex: index)
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

- [ ] **Step 4: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manually verify Browse still works identically**

On a device or Simulator, open a Closet with several items and confirm the grid, filter chips (including Person), search, and tap-to-detail all behave exactly as they did before this change — this task should be invisible from the outside except for the underlying bug fix.

- [ ] **Step 6: Commit**

```bash
git add Closet/Closet/Models/BrowseItem.swift Closet/Closet/Closets/ClosetDetailViewModel.swift Closet/Closet/Closets/ClosetDetailView.swift
git commit -m "Extract shared browse-filtering logic and fix stale-index tap navigation"
```

---

### Task 2: item_shares DELETE policy + pgTAP coverage

**Files:**
- Create: `supabase/migrations/20260808000000_item_shares_delete_policy.sql`
- Modify: `supabase/tests/database/items_rls.sql`

**Interfaces:**
- Consumes: `public.item_shares`, `public.items` (Phase 1/3)
- Produces: `authenticated` can delete an `item_shares` row for an item they own — Task 4's `ItemDetailViewModel.toggleShare` depends on this

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260808000000_item_shares_delete_policy.sql`:

```sql
grant delete on public.item_shares to authenticated;

create policy "Item owners can remove their own item shares"
  on public.item_shares for delete
  using (
    exists (select 1 from public.items where id = item_shares.item_id and owner_id = auth.uid())
  );
```

- [ ] **Step 2: Add pgTAP coverage**

Modify `supabase/tests/database/items_rls.sql` — bump the plan count from 11 to 14, and add three assertions at the end (before `select * from finish();`). Full new file content:

```sql
begin;
select plan(14);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com');

insert into public.users (id, name) values
  ('11111111-1111-1111-1111-111111111111', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'Bob');

insert into public.closets (id, name, invite_code, created_by) values
  ('33333333-3333-3333-3333-333333333333', 'Shared Closet', 'testcode', '11111111-1111-1111-1111-111111111111');

insert into public.closet_members (user_id, closet_id) values
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333'),
  ('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333');

-- Fixture for the "Alice cannot share into a closet she isn't in" test below:
-- a second closet Bob created and belongs to, that Alice never joined.
insert into public.closets (id, name, invite_code, created_by) values
  ('55555555-5555-5555-5555-555555555555', 'Bob''s Other Closet', 'bobcode', '22222222-2222-2222-2222-222222222222');

insert into public.closet_members (user_id, closet_id) values
  ('22222222-2222-2222-2222-222222222222', '55555555-5555-5555-5555-555555555555');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

insert into public.items (id, owner_id, category)
values ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'Top');

select is(
  (select count(*)::int from public.items where owner_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'Alice can insert her own item'
);

insert into public.item_photos (item_id, photo_url, position)
values ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111/44444444-4444-4444-4444-444444444444/0.jpg', 0);

select is(
  (select count(*)::int from public.item_photos where item_id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Alice can insert a photo for her own item'
);

select throws_ok(
  $$insert into public.item_photos (item_id, photo_url, position) values ('44444444-4444-4444-4444-444444444444', 'duplicate.jpg', 0)$$,
  '23505',
  null,
  'Cannot insert a second photo at the same position for the same item'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.items where id = '44444444-4444-4444-4444-444444444444'),
  0,
  'Bob cannot see Alice''s item before it is shared'
);

select throws_ok(
  $$insert into public.item_shares (item_id, closet_id) values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333')$$,
  '42501',
  null,
  'Bob cannot share an item he does not own'
);

select throws_ok(
  $$insert into public.item_photos (item_id, photo_url, position) values ('44444444-4444-4444-4444-444444444444', 'fake/path/0.jpg', 0)$$,
  '42501',
  null,
  'Bob cannot insert a photo for an item he does not own'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

insert into public.item_shares (item_id, closet_id)
values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333');

select is(
  (select count(*)::int from public.item_shares where item_id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Alice can share her own item to a closet she is in'
);

select throws_ok(
  $$insert into public.item_shares (item_id, closet_id) values ('44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555')$$,
  '42501',
  null,
  'Alice cannot share her item into a closet she is not a member of'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.items where id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Bob can see the item once it is shared to a closet he is in'
);

select is(
  (select count(*)::int from public.item_photos where item_id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Bob can see the shared item''s photo row'
);

select throws_ok(
  $$insert into public.items (id, owner_id, category) values ('55555555-5555-5555-5555-555555555555', '11111111-1111-1111-1111-111111111111', 'Top')$$,
  '42501',
  null,
  'Bob cannot insert an item on Alice''s behalf'
);

-- A DELETE governed only by a `USING` policy never raises 42501 the way an
-- INSERT/UPDATE `WITH CHECK` violation does — RLS just filters the row out,
-- so the statement silently affects 0 rows. Assert that instead of throws_ok.
delete from public.item_shares
where item_id = '44444444-4444-4444-4444-444444444444' and closet_id = '33333333-3333-3333-3333-333333333333';

select is(
  (select count(*)::int from public.item_shares where item_id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Bob''s delete attempt does not remove Alice''s share (RLS filters it silently)'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

delete from public.item_shares
where item_id = '44444444-4444-4444-4444-444444444444' and closet_id = '33333333-3333-3333-3333-333333333333';

select is(
  (select count(*)::int from public.item_shares where item_id = '44444444-4444-4444-4444-444444444444'),
  0,
  'Alice can remove her own item''s share'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.items where id = '44444444-4444-4444-4444-444444444444'),
  0,
  'Bob can no longer see the item after Alice removes the share'
);

select * from finish();
rollback;
```

- [ ] **Step 3: Apply locally and run the tests**

Run: `supabase db reset` (if this errors, run `supabase start` first — requires Docker)
Expected: all migrations apply cleanly, including the new one

Run: `supabase test db`
Expected: `14 tests passed, 0 failed`

- [ ] **Step 4: Push to the hosted project**

Run: `supabase db push`
Expected: `Applying migration 20260808000000_item_shares_delete_policy.sql...` then success

Run: `supabase migration list`
Expected: the new migration's `local` and `remote` columns both show `20260808000000`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260808000000_item_shares_delete_policy.sql supabase/tests/database/items_rls.sql
git commit -m "Let item owners remove their own item_shares rows"
```

---

### Task 3: My Clothes screen

**Files:**
- Create: `Closet/Closet/MyClothes/MyClothesViewModel.swift`
- Create: `Closet/Closet/MyClothes/MyClothesView.swift`
- Modify: `Closet/Closet/MainTabView.swift`

**Interfaces:**
- Consumes: `BrowseItem`/`BrowseFilters`/`BrowseFiltering` (Task 1), `ItemDetailView` (Phase 5), `Item`/`ItemCategory` (Phase 3), `UserProfile` (Phase 1/2)
- Produces: a working "My Clothes" tab reachable from `MainTabView`

- [ ] **Step 1: Write the view model**

Create `Closet/Closet/MyClothes/MyClothesViewModel.swift`:

```swift
import Foundation
import PostgREST
import Storage
import Supabase

private struct PhotoRow: Decodable {
    let photoURL: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case photoURL = "photo_url"
        case position
    }
}

private struct RawItem: Decodable {
    let id: UUID
    let ownerID: UUID
    let category: ItemCategory
    let size: String?
    let color: String?
    let occasionTags: [String]
    let caption: String?
    let createdAt: Date
    let itemPhotos: [PhotoRow]

    enum CodingKeys: String, CodingKey {
        case id, category, size, color, caption
        case ownerID = "owner_id"
        case occasionTags = "occasion_tags"
        case createdAt = "created_at"
        case itemPhotos = "item_photos"
    }
}

@Observable
final class MyClothesViewModel {
    var myProfile: UserProfile?
    var items: [BrowseItem] = []
    var filters = BrowseFilters()
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    var filteredItems: [BrowseItem] {
        BrowseFiltering.filteredItems(items, filters: filters)
    }

    var availableSizes: [String] {
        BrowseFiltering.availableSizes(items)
    }

    var availableColors: [String] {
        BrowseFiltering.availableColors(items)
    }

    var availableOccasions: [String] {
        BrowseFiltering.availableOccasions(items)
    }

    func load(userID: UUID) async {
        isLoading = true
        defer { isLoading = false }

        myProfile = try? await client
            .from("users")
            .select()
            .eq("id", value: userID)
            .single()
            .execute()
            .value

        do {
            let rows: [RawItem] = try await client
                .from("items")
                .select("*, item_photos(photo_url, position)")
                .eq("owner_id", value: userID)
                .execute()
                .value
            items = rows
                .map(Self.makeBrowseItem)
                .sorted { $0.item.createdAt > $1.item.createdAt }
            await loadSignedURLs()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func makeBrowseItem(_ raw: RawItem) -> BrowseItem {
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
        return BrowseItem(item: item, photoPath: photoPath)
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
}
```

- [ ] **Step 2: Write the view**

Create `Closet/Closet/MyClothes/MyClothesView.swift`:

```swift
import SwiftUI

private struct ItemDetailContext: Identifiable {
    let id = UUID()
    let items: [BrowseItem]
    let startIndex: Int
}

struct MyClothesView: View {
    @State private var viewModel = MyClothesViewModel()
    @State private var detailContext: ItemDetailContext?
    let userID: UUID

    private let gridColumns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    filterChipsRow

                    if viewModel.filteredItems.isEmpty {
                        Text(viewModel.items.isEmpty ? "No items yet" : "No items match your filters")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: 2) {
                            ForEach(viewModel.filteredItems) { browseItem in
                                Button {
                                    openDetail(for: browseItem)
                                } label: {
                                    itemCell(browseItem)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .searchable(text: $viewModel.filters.searchText)
            .navigationTitle("My Clothes")
            .task {
                await viewModel.load(userID: userID)
            }
            .fullScreenCover(item: $detailContext) { context in
                ItemDetailView(
                    items: context.items,
                    startIndex: context.startIndex,
                    members: [viewModel.myProfile].compactMap { $0 },
                    userID: userID
                )
            }
        }
    }

    private func openDetail(for browseItem: BrowseItem) {
        let snapshot = viewModel.filteredItems
        if let index = snapshot.firstIndex(where: { $0.id == browseItem.id }) {
            detailContext = ItemDetailContext(items: snapshot, startIndex: index)
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

- [ ] **Step 3: Wire it into the tab bar**

Full new file content for `Closet/Closet/MainTabView.swift`:

```swift
import SwiftUI

struct MainTabView: View {
    let userID: UUID

    var body: some View {
        TabView {
            ClosetsListView(userID: userID)
                .tabItem { Label("Closets", systemImage: "door.left.hand.open") }
            MyClothesView(userID: userID)
                .tabItem { Label("My Clothes", systemImage: "tshirt") }
            Text("Profile")
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}
```

- [ ] **Step 4: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manually verify My Clothes**

On a device or Simulator, with a user who has added items across more than one Closet: open the "My Clothes" tab → confirm it shows every item that user owns, regardless of which Closet(s) it's shared to, in a grid matching Browse's look. Confirm Category/Size/Color/Occasion filters and search all narrow the grid correctly, and that there's no Person filter chip. Tap an item → confirm the same full-screen detail view opens, showing your own name as the owner. Confirm a user with zero items sees "No items yet."

- [ ] **Step 6: Commit**

```bash
git add Closet/Closet/MyClothes/MyClothesViewModel.swift Closet/Closet/MyClothes/MyClothesView.swift Closet/Closet/MainTabView.swift
git commit -m "Add My Clothes tab, scoped to items the current user owns"
```

---

### Task 4: "Shared to:" toggle in Item Detail

**Files:**
- Modify: `Closet/Closet/ItemDetail/ItemDetailViewModel.swift`
- Modify: `Closet/Closet/ItemDetail/ItemDetailView.swift`

**Interfaces:**
- Consumes: `item_shares` DELETE policy (Task 2), `Closet` (Phase 2)
- Produces: a working share-toggle UI inside `ItemDetailView`, reachable from both `ClosetDetailView` and `MyClothesView`

- [ ] **Step 1: Add share-state loading and toggling to the view model**

Full new file content for `Closet/Closet/ItemDetail/ItemDetailViewModel.swift`:

```swift
import Foundation
import PostgREST
import Storage
import Supabase

@Observable
final class ItemDetailViewModel {
    private var fullResURLs: [UUID: URL] = [:]
    var allClosets: [Closet] = []
    var sharedClosetIDs: Set<UUID> = []
    var shareStateErrorMessage: String?

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

    func loadShareState(itemID: UUID) async {
        shareStateErrorMessage = nil

        do {
            allClosets = try await client
                .from("closets")
                .select()
                .execute()
                .value
        } catch {
            shareStateErrorMessage = error.localizedDescription
        }

        do {
            struct ShareRow: Decodable {
                let closetID: UUID
                enum CodingKeys: String, CodingKey { case closetID = "closet_id" }
            }
            let rows: [ShareRow] = try await client
                .from("item_shares")
                .select("closet_id")
                .eq("item_id", value: itemID)
                .execute()
                .value
            sharedClosetIDs = Set(rows.map(\.closetID))
        } catch {
            shareStateErrorMessage = error.localizedDescription
        }
    }

    func toggleShare(itemID: UUID, closetID: UUID) async {
        shareStateErrorMessage = nil
        do {
            if sharedClosetIDs.contains(closetID) {
                try await client
                    .from("item_shares")
                    .delete()
                    .eq("item_id", value: itemID)
                    .eq("closet_id", value: closetID)
                    .execute()
            } else {
                struct NewShare: Encodable {
                    let itemID: UUID
                    let closetID: UUID
                    enum CodingKeys: String, CodingKey {
                        case itemID = "item_id"
                        case closetID = "closet_id"
                    }
                }
                try await client
                    .from("item_shares")
                    .insert(NewShare(itemID: itemID, closetID: closetID))
                    .execute()
            }
        } catch {
            shareStateErrorMessage = error.localizedDescription
        }
        await loadShareState(itemID: itemID)
    }
}
```

- [ ] **Step 2: Add the "Shared to:" section to the view**

Full new file content for `Closet/Closet/ItemDetail/ItemDetailView.swift`:

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

            ForEach(viewModel.allClosets) { closet in
                Button {
                    Task { await viewModel.toggleShare(itemID: currentItem.item.id, closetID: closet.id) }
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
```

- [ ] **Step 3: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manually verify the share-toggle flow**

On a device or Simulator, as a user who owns items and belongs to more than one Closet:

1. Open one of your own items' detail view (from either My Clothes or a Closet's grid) — confirm a "Shared to" section appears below the caption/chips line, listing every Closet you're in, with a checkmark next to ones it's currently shared to.
2. Tap an unchecked Closet — confirm it becomes checked, and (if you have access to that Closet's grid) the item now appears there too.
3. Tap a checked Closet to uncheck it — confirm it becomes unchecked immediately (no confirmation prompt), and the item disappears from that Closet's grid for other members, while still appearing in your own My Clothes.
4. Open an item you do **not** own — confirm no "Shared to" section appears at all.
5. Confirm the "Shared to" list and the "•••" button remain independently tappable even when the list has several Closets in it (i.e. the "•••" button doesn't block the last Closet row's checkmark) — if it does overlap, note it as a design-pass item rather than a blocker.
6. Navigate to a different item you own via left/right tap navigation — confirm the "Shared to" list updates to that item's actual share state.

- [ ] **Step 5: Commit**

```bash
git add Closet/Closet/ItemDetail/ItemDetailViewModel.swift Closet/Closet/ItemDetail/ItemDetailView.swift
git commit -m "Let item owners toggle which Closets an item is shared to"
```

---

## Roadmap: Later Phases (not yet planned in detail)

- **Phase 7 — Report & Block:** reason picker, mutual hide, `reports`/`blocks` RLS — makes the "•••" menu's Report option functional
- **Phase 8 — Profile:** edit profile, blocked list, delete account — likely where profile photo upload would be added
- **Design pass:** deferred until Phases 5-8 are functionally complete (product decision, 2026-08-06) — real visual design (Retro-inspired dark/photo-forward look) across the whole app happens in one dedicated pass, not per-phase. Known items already flagged for that pass: the X/close button's small hit target and the "Shared to"/"•••" overlay collision risk noted in Task 4's manual QA.
