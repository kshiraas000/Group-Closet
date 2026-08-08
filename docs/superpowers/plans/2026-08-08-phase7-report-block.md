# Phase 7: Report & Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable the "Report" option Phase 5 left disabled in `ItemDetailView`'s "•••" menu, and add a new "Block" option alongside it. Blocking mutually hides items between the two users, everywhere, immediately.

**Architecture:** The `reports`/`blocks` tables have existed with RLS enabled since Phase 1 but have never had a single grant or policy — this phase gives them the minimal INSERT-only policies they need. The mutual-hide mechanism is a single change point: `can_view_item()`, the `SECURITY DEFINER` function every item-visibility policy already routes through (confirmed by tracing every RLS policy that touches `items`/`item_photos`/`storage.objects`), gains a block check that cascades correctly everywhere without touching any other policy. Report is a one-tap-confirm-alert flow with no reason captured (product decision — the original spec's reason picker was dropped). Block additionally dismisses the detail view and reloads the presenting Closet's grid on success, via a new `onBlocked` callback mirroring Phase 6's `onShareChanged` pattern exactly.

**Tech Stack:** SwiftUI, `@Observable`, PostgREST, pgTAP.

## Global Constraints

- iOS 17.0 minimum deployment target, SwiftUI `NavigationStack` + `@Observable` view models (unchanged from prior phases)
- Testing approach: Task 1 (the backend/RLS change) gets real pgTAP coverage. Task 2 (client-only) follows implement → verify build → manual QA → commit, not TDD.
- No reason is captured for reports — the product decision was to drop the reason picker entirely. `reports.reason` becomes nullable; the client never sets it.
- Blocking only affects item/photo visibility — Closet Members lists, filter chips, and closet membership itself are explicitly untouched (confirmed product decision).
- No unblock UI, no "blocked users" list, no moderation/admin UI of any kind — out of scope for this phase.
- Both Report and Block require a confirmation dialog before submitting (confirmed product decision) — neither is a bare one-tap action.
- Report keeps the detail view open afterward (nothing becomes invisible); Block dismisses the detail view on success (the current item just became invisible to the viewer).
- `MyClothesView` needs no changes in this phase — its `ItemDetailView` presentation never reaches the non-owner menu branch where Report/Block live, since My Clothes only ever shows items the viewer owns.

---

## File Structure

- Create: `supabase/migrations/20260808000001_reports_blocks_policies.sql` — INSERT policies for `reports`/`blocks`, `reports.reason` made nullable, `can_view_item()` gains the mutual-block check
- Create: `supabase/tests/database/reports_blocks_rls.sql` — pgTAP coverage
- Modify: `Closet/Closet/ItemDetail/ItemDetailViewModel.swift` — `report`/`block` methods
- Modify: `Closet/Closet/ItemDetail/ItemDetailView.swift` — enabled Report + new Block menu options, confirmation dialogs, result alert
- Modify: `Closet/Closet/Closets/ClosetDetailView.swift` — wire the new `onBlocked` callback

---

### Task 1: Backend — reports/blocks policies and the mutual-block check

**Files:**
- Create: `supabase/migrations/20260808000001_reports_blocks_policies.sql`
- Create: `supabase/tests/database/reports_blocks_rls.sql`

**Interfaces:**
- Consumes: `public.reports`, `public.blocks` (schema since Phase 1, untouched until now), `public.can_view_item(uuid)` (Phase 4)
- Produces: `authenticated` can INSERT into `reports`/`blocks` as themselves only; `can_view_item()` returns `false` whenever either party has blocked the other — Task 2's `report`/`block` client methods depend on this

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260808000001_reports_blocks_policies.sql`:

```sql
grant insert on public.reports to authenticated;

create policy "Users can create reports as themselves"
  on public.reports for insert
  with check (reporter_id = auth.uid());

grant insert on public.blocks to authenticated;

create policy "Users can block others as themselves"
  on public.blocks for insert
  with check (blocker_id = auth.uid() and blocked_id != auth.uid());

alter table public.reports alter column reason drop not null;

create or replace function public.can_view_item(check_item_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from items i
    where i.id = check_item_id
    and (
      i.owner_id = auth.uid()
      or exists (
        select 1 from item_shares s
        join closet_members cm on cm.closet_id = s.closet_id
        where s.item_id = i.id and cm.user_id = auth.uid()
      )
    )
    and not exists (
      select 1 from blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = i.owner_id)
         or (b.blocker_id = i.owner_id and b.blocked_id = auth.uid())
    )
  );
$$;
```

- [ ] **Step 2: Write the pgTAP test**

Create `supabase/tests/database/reports_blocks_rls.sql`:

```sql
begin;
select plan(9);

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

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

insert into public.items (id, owner_id, category)
values ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'Top');

insert into public.item_shares (item_id, closet_id)
values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333');

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

insert into public.items (id, owner_id, category)
values ('66666666-6666-6666-6666-666666666666', '22222222-2222-2222-2222-222222222222', 'Bottom');

insert into public.item_shares (item_id, closet_id)
values ('66666666-6666-6666-6666-666666666666', '33333333-3333-3333-3333-333333333333');

select is(
  (select count(*)::int from public.items where id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Bob can see Alice''s item before any block (baseline)'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select is(
  (select count(*)::int from public.items where id = '66666666-6666-6666-6666-666666666666'),
  1,
  'Alice can see Bob''s item before any block (baseline)'
);

insert into public.reports (item_id, reporter_id)
values ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111');

-- reports has no SELECT grant to authenticated at all (by design — nothing in
-- this phase reads it back), so verifying the insert actually landed requires
-- stepping outside the authenticated role's privileges entirely; reset role
-- returns to the session's original (superuser) role, which can read any
-- table regardless of grants or RLS. Immediately restore authenticated +
-- the JWT claim afterward, since every other assertion in this file depends
-- on acting as a specific real user.
reset role;

select is(
  (select count(*)::int from public.reports where item_id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Alice can report an item as herself, with no reason'
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select throws_ok(
  $$insert into public.reports (item_id, reporter_id) values ('44444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222')$$,
  '42501',
  null,
  'Alice cannot file a report claiming to be Bob'
);

select throws_ok(
  $$insert into public.blocks (blocker_id, blocked_id) values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111')$$,
  '42501',
  null,
  'Alice cannot insert a block claiming to be Bob'
);

select throws_ok(
  $$insert into public.blocks (blocker_id, blocked_id) values ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111')$$,
  '42501',
  null,
  'Alice cannot block herself'
);

insert into public.blocks (blocker_id, blocked_id)
values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');

-- Same reasoning as the reports check above: blocks has no SELECT grant to
-- authenticated either, so bypass to verify, then restore the role/claim.
reset role;

select is(
  (select count(*)::int from public.blocks where blocker_id = '11111111-1111-1111-1111-111111111111' and blocked_id = '22222222-2222-2222-2222-222222222222'),
  1,
  'Alice can block Bob as herself'
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select is(
  (select count(*)::int from public.items where id = '66666666-6666-6666-6666-666666666666'),
  0,
  'Alice can no longer see Bob''s item after blocking him'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.items where id = '44444444-4444-4444-4444-444444444444'),
  0,
  'Bob can no longer see Alice''s item after Alice blocked him (mutual hide)'
);

select * from finish();
rollback;
```

- [ ] **Step 3: Apply locally and run the tests**

Run: `supabase db reset` (if this errors, run `supabase start` first — requires Docker)
Expected: all migrations apply cleanly, including the new one

Run: `supabase test db`
Expected: `9 tests passed, 0 failed` for `reports_blocks_rls.sql` (plus all previously-passing tests in the other files unaffected)

- [ ] **Step 4: Push to the hosted project**

Run: `supabase db push`
Expected: `Applying migration 20260808000001_reports_blocks_policies.sql...` then success

Run: `supabase migration list`
Expected: the new migration's `local` and `remote` columns both show `20260808000001`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260808000001_reports_blocks_policies.sql supabase/tests/database/reports_blocks_rls.sql
git commit -m "Add reports/blocks INSERT policies and mutual-block visibility check"
```

---

### Task 2: Client — Report and Block in Item Detail

**Files:**
- Modify: `Closet/Closet/ItemDetail/ItemDetailViewModel.swift`
- Modify: `Closet/Closet/ItemDetail/ItemDetailView.swift`
- Modify: `Closet/Closet/Closets/ClosetDetailView.swift`

**Interfaces:**
- Consumes: `reports`/`blocks` INSERT policies (Task 1)
- Produces: a working end-to-end Report and Block flow reachable from any non-owned item's detail view

- [ ] **Step 1: Add report and block methods to the view model**

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
    var isLoadingShareState = false

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
        isLoadingShareState = true
        defer { isLoadingShareState = false }
        allClosets = []
        sharedClosetIDs = []

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

    func report(itemID: UUID, reporterID: UUID) async -> Bool {
        do {
            struct NewReport: Encodable {
                let itemID: UUID
                let reporterID: UUID
                enum CodingKeys: String, CodingKey {
                    case itemID = "item_id"
                    case reporterID = "reporter_id"
                }
            }
            try await client.from("reports").insert(NewReport(itemID: itemID, reporterID: reporterID)).execute()
            return true
        } catch {
            return false
        }
    }

    func block(blockedID: UUID, blockerID: UUID) async -> Bool {
        do {
            struct NewBlock: Encodable {
                let blockerID: UUID
                let blockedID: UUID
                enum CodingKeys: String, CodingKey {
                    case blockerID = "blocker_id"
                    case blockedID = "blocked_id"
                }
            }
            try await client.from("blocks").insert(NewBlock(blockerID: blockerID, blockedID: blockedID)).execute()
            return true
        } catch {
            return false
        }
    }
}
```

- [ ] **Step 2: Enable Report and add Block to the detail view**

Full new file content for `Closet/Closet/ItemDetail/ItemDetailView.swift`:

```swift
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
    let userID: UUID
    let onShareChanged: () -> Void
    let onBlocked: () -> Void

    init(items: [BrowseItem], startIndex: Int, members: [UserProfile], userID: UUID, onShareChanged: @escaping () -> Void = {}, onBlocked: @escaping () -> Void = {}) {
        self.items = items
        self.members = members
        self.userID = userID
        self.onShareChanged = onShareChanged
        self.onBlocked = onBlocked
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
                Button("Report") { showingReportConfirmation = true }
                Button("Block \(ownerName)", role: .destructive) { showingBlockConfirmation = true }
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

- [ ] **Step 3: Wire the onBlocked callback in Closet Detail**

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
            ItemDetailView(
                items: context.items,
                startIndex: context.startIndex,
                members: viewModel.members,
                userID: userID,
                onShareChanged: { Task { await viewModel.load(closetID: closet.id) } },
                onBlocked: { Task { await viewModel.load(closetID: closet.id) } }
            )
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

- [ ] **Step 5: Manually verify Report and Block**

On a device or Simulator, as a user viewing an item owned by someone else (from inside a shared Closet, not My Clothes):

1. Tap "•••" — confirm you see both "Report" and "Block [name]" (not disabled).
2. Tap "Report" — confirm a confirmation dialog appears; cancel it and confirm nothing happens. Tap "Report" again and confirm this time — confirm an alert says "Reported" and the detail view stays open on the same item.
3. Tap "•••" → "Block [name]" — confirm a confirmation dialog appears; cancel it and confirm nothing happens (the item is still visible). Tap "Block [name]" again and confirm this time — confirm the detail view closes and, back on the Closet's grid, the blocked user's item(s) are gone.
4. As the blocked user (a second test account, or by checking the Supabase dashboard's `blocks` table), confirm they likewise can no longer see the blocking user's items in that same Closet — this is the mutual half of "mutual hide" and is hard to verify without a second account, so checking the `items`/`blocks` tables directly in the Supabase dashboard is an acceptable substitute if a second device/account isn't available.
5. Confirm you (the owner) can still see your own items normally — being blocked by someone, or blocking someone, should never affect what you see of your own stuff.

- [ ] **Step 6: Commit**

```bash
git add Closet/Closet/ItemDetail/ItemDetailViewModel.swift Closet/Closet/ItemDetail/ItemDetailView.swift Closet/Closet/Closets/ClosetDetailView.swift
git commit -m "Enable Report and add Block to Item Detail"
```

---

## Roadmap: Later Phases (not yet planned in detail)

- **Phase 8 — Profile:** edit profile, blocked users list (unblock UI), delete account. Also the natural point to revisit the Phase 6 gap where sharing into a Closet you've since left is invisible/unrevocable, since both are "what happens when a relationship ends" questions.
- **Design pass:** deferred until Phases 5-8 are functionally complete (product decision, 2026-08-06) — real visual design (Retro-inspired dark/photo-forward look) across the whole app happens in one dedicated pass, not per-phase.
