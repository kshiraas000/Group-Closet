# Phase 3: Add Item Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user inside a Closet pick photos from their library, tag each one (category required, size/color/occasion/caption optional), choose which other Closets to also share to, and save — items land in Postgres and their photos in Supabase Storage, both properly access-controlled.

**Architecture:** One shared `AddItemViewModel` drives a three-step wizard (`AddItemView`: pick → `PhotoTaggingView`: tag → `ShareToClosetsView`: share + save), matching how a single continuous flow with carried-forward state is idiomatically built in SwiftUI, versus Phase 1/2's one-view-model-per-screen pattern which fit independent screens. Each photo's Postgres `items` row is written only *after* its photo successfully uploads to Storage — this makes per-photo retry (spec §5) simple: a failed item never has a half-written row to clean up, retry just re-attempts that one photo's upload+insert. Photos live in a private `item-photos` Storage bucket at `{owner_id}/{item_id}/0.jpg`; `item_photos.photo_url` stores that path, not a resolved URL — turning paths into displayable signed URLs is Phase 4/5's job, not this phase's.

**Tech Stack:** SwiftUI, `@Observable`, `PhotosUI` (`PhotosPicker`), supabase-swift (`Supabase` + `PostgREST` + `Storage` modules), pgTAP.

## Global Constraints

- iOS 17.0 minimum deployment target (unchanged from Phase 1/2)
- SwiftUI with `NavigationStack` + `@Observable` view models — no Redux/TCA
- Use `SupabaseService.shared` directly — not `.shared.client`. Any file calling `.from(...)`/`.rpc(...)`/`.execute()` needs both `import Supabase` and `import PostgREST`. **New this phase:** any file calling `.storage.from(...).upload(...)` additionally needs `import Storage` — supabase-swift splits each capability (Auth, PostgREST, Storage) into its own module that must be imported explicitly wherever it's used, regardless of what `import Supabase` alone already covers. This exact gap cost a debugging round in Phase 2 for `PostgREST`; don't repeat it for `Storage`.
- Row-Level Security is the real privacy boundary (spec §2) — items/item_photos/item_shares visibility and Storage object access are both enforced in Postgres, not just checked in the app.
- **Camera capture is out of scope for this phase** (explicit product decision) — only `PhotosPicker` (library, multi-select up to 20) is built. Camera capture is a small, self-contained addition later.
- **MVP only ever writes ONE `item_photos` row per item** (`position = 0`), per spec §2 — `item_photos` is one-to-many in the schema for a future "add more photos" feature, but no multi-photo UI exists yet.
- **"Also share to" is one batch-level selection**, applied identically to every photo in a single Add Item session — not configured per-photo. This matches the spec listing it as step 3, after step 2's per-photo tagging, not embedded within it (spec §3.2).
- Photo storage path convention: `{owner_id}/{item_id}/0.jpg` in a private `item-photos` bucket. `item_photos.photo_url` stores this **path**, not a resolved URL — despite the column's name (fixed from Phase 1's schema, not renamed here). Generating actual signed/displayable URLs is Phase 4/5's concern.
- Upload failures retry per-item, not all-or-nothing (spec §5): a photo's `items` row is written to Postgres only *after* that photo's Storage upload succeeds, so a failed item never leaves an orphaned row — retry re-attempts that one item's upload+insert independently of the batch's other items.
- This plan assumes Supabase's default Storage setup already grants `authenticated` baseline access to `storage.objects` (standard for every Supabase project) and that RLS policies are the actual gate, same as every other table in this app — Task 1 doesn't add a `grant` statement for `storage.objects` because none should be needed; if upload/view fails with a permission error despite the policies looking correct, check this assumption first.
- No pgTAP coverage for `storage.objects` policies in this phase — consistent with spec §6 ("manual/exploratory QA for SwiftUI flows" as the project's stated approach for anything UI/client-flow-adjacent). Storage upload behavior is exercised via the real upload path in Task 5's manual verification instead.
- Grid/filter/search display of items (spec §3.1 Closet grid, §3.3 My Clothes) is Phase 4 — this phase's only way to see a saved item is a bare-bones placeholder list (category + caption text only, no photos, no styling) added to `ClosetDetailView`, the same kind of throwaway scaffolding Phase 1 used for `MainTabView`'s stub tabs. Phase 4 replaces it wholesale.

---

## File Structure

**iOS app:**
- `Closet/Closet/Models/Item.swift` — `ItemCategory` enum + `Item` `Codable` struct matching the `items` table
- `Closet/Closet/AddItem/AddItemViewModel.swift` — `@Observable`; owns the whole flow's state (draft items, share-to selection) and the save orchestration
- `Closet/Closet/AddItem/PhotoTaggingView.swift` — per-photo swipe-through tagging (category required, size/color/occasion/caption optional)
- `Closet/Closet/AddItem/ImageCompressor.swift` — downscale + JPEG-compress a `UIImage` before upload
- `Closet/Closet/AddItem/ShareToClosetsView.swift` — pick which other Closets to also share to, trigger save, show per-item progress/retry
- `Closet/Closet/AddItem/AddItemView.swift` — top-level sheet: `PhotosPicker` entry + wizard-step coordinator
- Modified: `Closet/Closet/Closets/ClosetDetailViewModel.swift` (loads this Closet's items), `Closet/Closet/Closets/ClosetDetailView.swift` ("+" button opens `AddItemView`; bare-bones items list)

**Supabase backend:**
- `supabase/migrations/20260804000004_items_storage_rls.sql` — `item-photos` Storage bucket, RLS for `items`/`item_photos`/`item_shares`, RLS for `storage.objects`
- `supabase/tests/database/items_rls.sql` — pgTAP coverage for the three Postgres tables (not Storage, see Global Constraints)

---

### Task 1: Storage Bucket + items/item_photos/item_shares RLS + Tests

**Files:**
- Create: `supabase/migrations/20260804000004_items_storage_rls.sql`, `supabase/tests/database/items_rls.sql`

**Interfaces:**
- Consumes: `public.items`, `public.item_photos`, `public.item_shares` tables (Phase 1, Task 3), `public.closet_members` (Phase 2)
- Produces: a private `item-photos` Storage bucket; RLS making `items`/`item_photos`/`item_shares` insert/select work for owners and closet-mates; RLS on `storage.objects` scoped by the `{owner_id}/{item_id}/...` path convention — every later task's upload/query code depends on this path convention exactly

- [x] **Step 1: Write the migration**

Create `supabase/migrations/20260804000004_items_storage_rls.sql`:

```sql
insert into storage.buckets (id, name, public)
values ('item-photos', 'item-photos', false)
on conflict (id) do nothing;

grant select, insert on public.items to authenticated;
grant select, insert on public.item_photos to authenticated;
grant select, insert on public.item_shares to authenticated;

-- SECURITY DEFINER, same reason as Phase 2's is_closet_member: items' SELECT policy
-- needs to check item_shares, and item_shares' SELECT policy needs to check items.
-- Two ordinary policies referencing each other directly causes infinite RLS
-- recursion (found the hard way in Task 1's first implementation attempt). This
-- helper bypasses RLS internally, breaking the cycle, exactly like is_closet_member
-- does for closets/closet_members.
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
  );
$$;

revoke execute on function public.can_view_item(uuid) from public;
grant execute on function public.can_view_item(uuid) to authenticated;

create policy "Users can view items they own or that are shared with them"
  on public.items for select
  using (can_view_item(id));

create policy "Users can insert their own items"
  on public.items for insert
  with check (owner_id = auth.uid());

create policy "Users can view photos of items they can see"
  on public.item_photos for select
  using (can_view_item(item_id));

create policy "Users can insert photos for their own items"
  on public.item_photos for insert
  with check (
    exists (select 1 from public.items where id = item_photos.item_id and owner_id = auth.uid())
  );

create policy "Users can view shares for items they can see"
  on public.item_shares for select
  using (
    can_view_item(item_id)
    or exists (select 1 from public.closet_members where closet_id = item_shares.closet_id and user_id = auth.uid())
  );

create policy "Item owners can share their own items to closets they're in"
  on public.item_shares for insert
  with check (
    exists (select 1 from public.items where id = item_shares.item_id and owner_id = auth.uid())
    and exists (select 1 from public.closet_members where closet_id = item_shares.closet_id and user_id = auth.uid())
  );

create policy "Users can upload photos to their own folder"
  on storage.objects for insert
  with check (
    bucket_id = 'item-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can view photos of items they can see"
  on storage.objects for select
  using (
    bucket_id = 'item-photos'
    and exists (
      select 1 from public.items i
      where i.id = ((storage.foldername(name))[2])::uuid
      and (
        i.owner_id = auth.uid()
        or exists (
          select 1 from public.item_shares s
          join public.closet_members cm on cm.closet_id = s.closet_id
          where s.item_id = i.id and cm.user_id = auth.uid()
        )
      )
    )
  );

create policy "Users can delete their own item photos"
  on storage.objects for delete
  using (
    bucket_id = 'item-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
```

- [x] **Step 2: Write the pgTAP test**

Create `supabase/tests/database/items_rls.sql`:

```sql
begin;
select plan(8);

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

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

insert into public.item_shares (item_id, closet_id)
values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333');

select is(
  (select count(*)::int from public.item_shares where item_id = '44444444-4444-4444-4444-444444444444'),
  1,
  'Alice can share her own item to a closet she is in'
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

select * from finish();
rollback;
```

- [x] **Step 3: Apply locally and run the tests**

Run: `supabase db reset` (if this errors, run `supabase start` first — requires Docker)
Expected: all migrations apply cleanly, including the new one

Run: `supabase test db`
Expected: `25 tests passed, 0 failed` (8 new + 17 existing)

- [x] **Step 4: Push to the hosted project**

Run: `supabase db push`
Expected: `Applying migration 20260804000004_items_storage_rls.sql...` then success

Run: `supabase migration list`
Expected: the new migration's `local` and `remote` columns both show `20260804000004`

- [x] **Step 5: Commit**

```bash
git add supabase/migrations/20260804000004_items_storage_rls.sql supabase/tests/database/items_rls.sql
git commit -m "Add item-photos Storage bucket and RLS for items/item_photos/item_shares"
```

---

### Task 2: Item Model + Photo Tagging Screen

**Files:**
- Create: `Closet/Closet/Models/Item.swift`, `Closet/Closet/AddItem/AddItemViewModel.swift`, `Closet/Closet/AddItem/PhotoTaggingView.swift`

**Interfaces:**
- Consumes: nothing from earlier phases beyond `SupabaseService.shared`
- Produces: `ItemCategory` enum, `Item` struct (used by Task 5's items list); `AddItemViewModel` with `draftItems: [DraftItem]`, `func loadDefaultSizes(userID: UUID) async`, `func startTagging(images: [UIImage])`, `func selectCategory(_:forItemAt:)` — Task 3 adds save-related members to this same class; `PhotoTaggingView(viewModel:onFinished:)` — Task 4 presents this as the flow's second step

- [x] **Step 1: Write the Item model**

Create `Closet/Closet/Models/Item.swift`:

```swift
import Foundation

enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case top = "Top"
    case bottom = "Bottom"
    case dress = "Dress"
    case outerwear = "Outerwear"
    case shoes = "Shoes"
    case accessory = "Accessory"

    var id: String { rawValue }
}

struct Item: Codable, Identifiable {
    let id: UUID
    let ownerID: UUID
    var category: ItemCategory
    var size: String?
    var color: String?
    var occasionTags: [String]
    var caption: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case category, size, color
        case occasionTags = "occasion_tags"
        case caption
        case createdAt = "created_at"
    }
}
```

- [x] **Step 2: Write the Add Item view model**

Create `Closet/Closet/AddItem/AddItemViewModel.swift`:

```swift
import Foundation
import PostgREST
import Supabase
import UIKit

enum SaveState: Equatable {
    case pending
    case saving
    case saved
    case failed(String)
}

struct DraftItem: Identifiable {
    let id = UUID()
    var image: UIImage
    var category: ItemCategory?
    var size: String = ""
    var color: String = ""
    var occasionTags: String = ""
    var caption: String = ""
    var saveState: SaveState = .pending
}

@Observable
final class AddItemViewModel {
    var draftItems: [DraftItem] = []
    private var defaultSizes: [String: String] = [:]

    private let client = SupabaseService.shared

    func loadDefaultSizes(userID: UUID) async {
        struct SizesRow: Decodable { let sizes: [String: String] }
        let row: SizesRow? = try? await client
            .from("users")
            .select("sizes")
            .eq("id", value: userID)
            .single()
            .execute()
            .value
        defaultSizes = row?.sizes ?? [:]
    }

    func startTagging(images: [UIImage]) {
        draftItems = images.map { DraftItem(image: $0) }
    }

    func selectCategory(_ category: ItemCategory, forItemAt index: Int) {
        draftItems[index].category = category
        if draftItems[index].size.isEmpty {
            draftItems[index].size = defaultSize(for: category)
        }
    }

    private func defaultSize(for category: ItemCategory) -> String {
        switch category {
        case .top: return defaultSizes["top"] ?? ""
        case .bottom: return defaultSizes["bottom"] ?? ""
        case .shoes: return defaultSizes["shoe"] ?? ""
        case .dress, .outerwear, .accessory: return ""
        }
    }
}
```

- [x] **Step 3: Write the photo tagging view**

Create `Closet/Closet/AddItem/PhotoTaggingView.swift`:

```swift
import SwiftUI

struct PhotoTaggingView: View {
    @Bindable var viewModel: AddItemViewModel
    @State private var currentIndex = 0
    let onFinished: () -> Void

    var body: some View {
        VStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(viewModel.draftItems.enumerated()), id: \.element.id) { index, _ in
                    tagForm(index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page)

            Button(currentIndex == viewModel.draftItems.count - 1 ? "Continue" : "Next") {
                if currentIndex < viewModel.draftItems.count - 1 {
                    currentIndex += 1
                } else {
                    onFinished()
                }
            }
            .disabled(!viewModel.draftItems.indices.contains(currentIndex) || viewModel.draftItems[currentIndex].category == nil)
            .padding()
        }
    }

    private func tagForm(index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(uiImage: viewModel.draftItems[index].image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)

                Text("Category").font(.headline)
                let columns = [GridItem(.adaptive(minimum: 90))]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(ItemCategory.allCases) { category in
                        Button(category.rawValue) {
                            viewModel.selectCategory(category, forItemAt: index)
                        }
                        .buttonStyle(.bordered)
                        .tint(viewModel.draftItems[index].category == category ? .blue : .gray)
                    }
                }

                DisclosureGroup("More details (optional)") {
                    VStack(spacing: 8) {
                        TextField("Size", text: $viewModel.draftItems[index].size)
                            .textFieldStyle(.roundedBorder)
                        TextField("Color", text: $viewModel.draftItems[index].color)
                            .textFieldStyle(.roundedBorder)
                        TextField("Occasions (comma separated)", text: $viewModel.draftItems[index].occasionTags)
                            .textFieldStyle(.roundedBorder)
                        TextField("Caption", text: $viewModel.draftItems[index].caption)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding()
        }
    }
}
```

- [x] **Step 4: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 5: Commit**

```bash
git add Closet/Closet/Models/Item.swift Closet/Closet/AddItem/AddItemViewModel.swift Closet/Closet/AddItem/PhotoTaggingView.swift
git commit -m "Add Item model and photo tagging screen"
```

---

### Task 3: Share-To-Closets + Save Screen

**Files:**
- Create: `supabase/migrations/20260805000000_item_photos_unique_position.sql`, `Closet/Closet/AddItem/ImageCompressor.swift`, `Closet/Closet/AddItem/ShareToClosetsView.swift`
- Modify: `Closet/Closet/AddItem/AddItemViewModel.swift`

Retry safety in `save()` comes from checking whether each row already exists before inserting it — not from `upsert`/`ON CONFLICT`, which needs `UPDATE` privilege that `authenticated` deliberately doesn't have on these tables yet (edit/delete is a later phase; discovered the hard way when Task 3's first implementation attempt tried `upsert` and hit `permission denied for table items` even on non-conflicting rows, since Postgres's `ON CONFLICT` handling requires `UPDATE` grant regardless of whether a row actually conflicts). The new migration's unique constraint on `item_photos(item_id, position)` isn't load-bearing for this check-then-insert approach the way it would have been for `upsert`, but it's still worth keeping as a genuine data-integrity guarantee (nothing should ever be able to create two photo rows at the same position for one item, regardless of how retry is implemented).

**Interfaces:**
- Consumes: `AddItemViewModel`/`DraftItem`/`SaveState` (Task 2), `Closet` (Phase 2), `Item`/`ItemCategory` (Task 2)
- Produces: `AddItemViewModel.saveAll(currentClosetID:ownerID:)` and `.save(itemAt:currentClosetID:ownerID:)`, `AddItemViewModel.shareToClosetIDs: Set<UUID>`; `ShareToClosetsView(viewModel:currentClosetID:ownerID:onDone:)` — Task 4 presents this as the flow's third step

- [x] **Step 1: Add the missing unique constraint on item_photos**

Create `supabase/migrations/20260805000000_item_photos_unique_position.sql`:

```sql
alter table public.item_photos
  add constraint item_photos_item_id_position_key unique (item_id, position);
```

Run: `supabase db reset` then `supabase test db` — expect all existing tests still passing (this only adds a constraint, doesn't change any policy).
Run: `supabase db push` then `supabase migration list` to confirm it applied to the hosted project.

- [x] **Step 2: Write the image compressor**

Create `Closet/Closet/AddItem/ImageCompressor.swift`:

```swift
import UIKit

enum ImageCompressor {
    static func compress(_ image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.75) -> Data? {
        resize(image, maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxDimension else { return image }
        let scale = maxDimension / longEdge
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
```

- [x] **Step 3: Add save orchestration to the view model**

Modify `Closet/Closet/AddItem/AddItemViewModel.swift` — add `import Storage`, the `shareToClosetIDs` property, and the save methods + private `Encodable` payload structs. Full new file content:

```swift
import Foundation
import PostgREST
import Storage
import Supabase
import UIKit

enum SaveState: Equatable {
    case pending
    case saving
    case saved
    case failed(String)
}

struct DraftItem: Identifiable {
    let id = UUID()
    var image: UIImage
    var category: ItemCategory?
    var size: String = ""
    var color: String = ""
    var occasionTags: String = ""
    var caption: String = ""
    var saveState: SaveState = .pending
}

@Observable
final class AddItemViewModel {
    var draftItems: [DraftItem] = []
    var shareToClosetIDs: Set<UUID> = []
    private var defaultSizes: [String: String] = [:]

    private let client = SupabaseService.shared

    func loadDefaultSizes(userID: UUID) async {
        struct SizesRow: Decodable { let sizes: [String: String] }
        let row: SizesRow? = try? await client
            .from("users")
            .select("sizes")
            .eq("id", value: userID)
            .single()
            .execute()
            .value
        defaultSizes = row?.sizes ?? [:]
    }

    func startTagging(images: [UIImage]) {
        draftItems = images.map { DraftItem(image: $0) }
    }

    func selectCategory(_ category: ItemCategory, forItemAt index: Int) {
        draftItems[index].category = category
        if draftItems[index].size.isEmpty {
            draftItems[index].size = defaultSize(for: category)
        }
    }

    private func defaultSize(for category: ItemCategory) -> String {
        switch category {
        case .top: return defaultSizes["top"] ?? ""
        case .bottom: return defaultSizes["bottom"] ?? ""
        case .shoes: return defaultSizes["shoe"] ?? ""
        case .dress, .outerwear, .accessory: return ""
        }
    }

    func saveAll(currentClosetID: UUID, ownerID: UUID) async {
        for index in draftItems.indices {
            guard draftItems[index].saveState != .saved else { continue }
            await save(itemAt: index, currentClosetID: currentClosetID, ownerID: ownerID)
        }
    }

    func save(itemAt index: Int, currentClosetID: UUID, ownerID: UUID) async {
        draftItems[index].saveState = .saving
        let draft = draftItems[index]
        guard let category = draft.category else {
            draftItems[index].saveState = .failed("Missing category")
            return
        }

        do {
            let itemID = draft.id
            guard let imageData = ImageCompressor.compress(draft.image) else {
                draftItems[index].saveState = .failed("Could not process image")
                return
            }
            // Lowercased: Swift's UUID interpolation is uppercase, but Postgres's
            // uuid::text cast (used by storage.objects' RLS policies) is always
            // lowercase — an uppercase path segment would never match auth.uid()::text.
            let ownerSegment = ownerID.uuidString.lowercased()
            let itemSegment = itemID.uuidString.lowercased()
            let path = "\(ownerSegment)/\(itemSegment)/0.jpg"

            try await client.storage.from("item-photos").upload(
                path,
                data: imageData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )

            let occasionTags = draft.occasionTags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            // save() can be re-invoked on the same itemID via the retry button
            // after a partial prior failure. authenticated only has SELECT+INSERT
            // on these tables (no UPDATE — edit/delete is a later phase), so
            // idempotency comes from checking whether each row already exists
            // before inserting it, not from ON CONFLICT DO UPDATE (which needs
            // UPDATE privilege Postgres enforces even when nothing would change).
            if try await !rowExists(table: "items", column: "id", value: itemID) {
                let newItem = NewItem(
                    id: itemID,
                    ownerID: ownerID,
                    category: category,
                    size: draft.size.isEmpty ? nil : draft.size,
                    color: draft.color.isEmpty ? nil : draft.color,
                    occasionTags: occasionTags,
                    caption: draft.caption.isEmpty ? nil : draft.caption
                )
                try await client.from("items").insert(newItem).execute()
            }

            if try await !rowExists(table: "item_photos", column: "item_id", value: itemID) {
                let newPhoto = NewItemPhoto(itemID: itemID, photoURL: path, position: 0)
                try await client.from("item_photos").insert(newPhoto).execute()
            }

            var closetIDs = shareToClosetIDs
            closetIDs.insert(currentClosetID)
            let alreadyShared = try await existingShareClosetIDs(itemID: itemID)
            let missingShares = closetIDs.subtracting(alreadyShared)
            if !missingShares.isEmpty {
                let shares = missingShares.map { NewItemShare(itemID: itemID, closetID: $0) }
                try await client.from("item_shares").insert(shares).execute()
            }

            draftItems[index].saveState = .saved
        } catch {
            draftItems[index].saveState = .failed(error.localizedDescription)
        }
    }

    private func rowExists(table: String, column: String, value: UUID) async throws -> Bool {
        let count = try await client
            .from(table)
            .select(column, head: true, count: .exact)
            .eq(column, value: value)
            .execute()
            .count ?? 0
        return count > 0
    }

    private func existingShareClosetIDs(itemID: UUID) async throws -> Set<UUID> {
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
        return Set(rows.map(\.closetID))
    }
}

private struct NewItem: Encodable {
    let id: UUID
    let ownerID: UUID
    let category: ItemCategory
    let size: String?
    let color: String?
    let occasionTags: [String]
    let caption: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case category, size, color
        case occasionTags = "occasion_tags"
        case caption
    }
}

private struct NewItemPhoto: Encodable {
    let itemID: UUID
    let photoURL: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case photoURL = "photo_url"
        case position
    }
}

private struct NewItemShare: Encodable {
    let itemID: UUID
    let closetID: UUID

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case closetID = "closet_id"
    }
}
```

- [x] **Step 4: Write the share-to-closets + save view**

Create `Closet/Closet/AddItem/ShareToClosetsView.swift`:

```swift
import SwiftUI
import PostgREST
import Supabase

struct ShareToClosetsView: View {
    @Bindable var viewModel: AddItemViewModel
    @State private var otherClosets: [Closet] = []
    @State private var isLoadingClosets = true
    let currentClosetID: UUID
    let ownerID: UUID
    let onDone: () -> Void

    private var isSaving: Bool {
        viewModel.draftItems.contains { $0.saveState == .saving }
    }

    private var allSaved: Bool {
        !viewModel.draftItems.isEmpty && viewModel.draftItems.allSatisfy { $0.saveState == .saved }
    }

    var body: some View {
        VStack {
            List {
                Section("Also share to") {
                    if isLoadingClosets {
                        ProgressView()
                    } else if otherClosets.isEmpty {
                        Text("You're not in any other Closets").foregroundStyle(.secondary)
                    } else {
                        ForEach(otherClosets) { closet in
                            Button {
                                toggle(closet.id)
                            } label: {
                                HStack {
                                    Text(closet.name)
                                    Spacer()
                                    if viewModel.shareToClosetIDs.contains(closet.id) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                Section("Items") {
                    ForEach(Array(viewModel.draftItems.enumerated()), id: \.element.id) { index, draft in
                        HStack {
                            Text(draft.category?.rawValue ?? "Untagged")
                            Spacer()
                            itemStatusView(index: index, state: draft.saveState)
                        }
                    }
                }
            }

            if allSaved {
                Button("Done") { onDone() }
                    .padding()
            } else {
                Button(isSaving ? "Saving..." : "Save") {
                    Task { await viewModel.saveAll(currentClosetID: currentClosetID, ownerID: ownerID) }
                }
                .disabled(isSaving)
                .padding()
            }
        }
        .task { await loadOtherClosets() }
    }

    private func toggle(_ closetID: UUID) {
        if viewModel.shareToClosetIDs.contains(closetID) {
            viewModel.shareToClosetIDs.remove(closetID)
        } else {
            viewModel.shareToClosetIDs.insert(closetID)
        }
    }

    private func loadOtherClosets() async {
        isLoadingClosets = true
        defer { isLoadingClosets = false }
        let all: [Closet] = (try? await SupabaseService.shared
            .from("closets")
            .select()
            .execute()
            .value) ?? []
        otherClosets = all.filter { $0.id != currentClosetID }
    }

    @ViewBuilder
    private func itemStatusView(index: Int, state: SaveState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
        case .saving:
            ProgressView()
        case .saved:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Button {
                Task { await viewModel.save(itemAt: index, currentClosetID: currentClosetID, ownerID: ownerID) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise.circle.fill")
            }
            .foregroundStyle(.red)
            .help(message)
        }
    }
}
```

- [x] **Step 5: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 6: Commit**

```bash
git add Closet/Closet/AddItem/ImageCompressor.swift Closet/Closet/AddItem/ShareToClosetsView.swift Closet/Closet/AddItem/AddItemViewModel.swift
git commit -m "Add image compression and share-to-closets save screen"
```

---

### Task 4: Photo Picker Entry Screen

**Files:**
- Create: `Closet/Closet/AddItem/AddItemView.swift`

**Interfaces:**
- Consumes: `AddItemViewModel` (Task 2/3), `PhotoTaggingView` (Task 2), `ShareToClosetsView` (Task 3)
- Produces: `AddItemView(closetID: UUID, userID: UUID, onItemsSaved: () -> Void)` — Task 5 presents this as a sheet from `ClosetDetailView`

- [x] **Step 1: Write the picker + coordinator view**

Create `Closet/Closet/AddItem/AddItemView.swift`:

```swift
import PhotosUI
import SwiftUI

struct AddItemView: View {
    @State private var viewModel = AddItemViewModel()
    @State private var step: Step = .picking
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @Environment(\.dismiss) private var dismiss
    let closetID: UUID
    let userID: UUID
    let onItemsSaved: () -> Void

    enum Step {
        case picking
        case tagging
        case sharing
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .picking:
                    pickerView
                case .tagging:
                    PhotoTaggingView(viewModel: viewModel) {
                        step = .sharing
                    }
                case .sharing:
                    ShareToClosetsView(
                        viewModel: viewModel,
                        currentClosetID: closetID,
                        ownerID: userID
                    ) {
                        onItemsSaved()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Add Items")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await viewModel.loadDefaultSizes(userID: userID) }
    }

    private var pickerView: some View {
        VStack(spacing: 24) {
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 20, matching: .images) {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
            .onChange(of: selectedPhotos) { _, newValue in
                Task { await loadImages(from: newValue) }
            }
        }
        .padding()
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        guard !images.isEmpty else { return }
        viewModel.startTagging(images: images)
        step = .tagging
    }
}
```

- [x] **Step 2: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 3: Commit**

```bash
git add Closet/Closet/AddItem/AddItemView.swift
git commit -m "Add photo picker entry screen, completing the Add Item flow"
```

---

### Task 5: Wire Into Closet Detail

**Files:**
- Modify: `Closet/Closet/Closets/ClosetDetailViewModel.swift`, `Closet/Closet/Closets/ClosetDetailView.swift`

**Interfaces:**
- Consumes: `AddItemView` (Task 4), `Item` (Task 2)
- Produces: a working end-to-end Add Item flow reachable from inside any Closet

- [x] **Step 1: Add item loading to the Closet detail view model**

Modify `Closet/Closet/Closets/ClosetDetailViewModel.swift` — add an `items` property and `loadItems` method. Full new file content:

```swift
import Foundation
import PostgREST
import Supabase

private struct MemberRow: Decodable {
    let users: UserProfile
}

private struct ItemShareRow: Decodable {
    let items: Item
}

@Observable
final class ClosetDetailViewModel {
    var members: [UserProfile] = []
    var items: [Item] = []
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    func loadMembers(closetID: UUID) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [MemberRow] = try await client
                .from("closet_members")
                .select("users(id, name, photo_url, sizes)")
                .eq("closet_id", value: closetID)
                .execute()
                .value
            members = rows.map(\.users)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadItems(closetID: UUID) async {
        errorMessage = nil
        do {
            let rows: [ItemShareRow] = try await client
                .from("item_shares")
                .select("items(*)")
                .eq("closet_id", value: closetID)
                .execute()
                .value
            items = rows.map(\.items)
        } catch {
            errorMessage = error.localizedDescription
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

- [x] **Step 2: Wire the "+" button and items list into the Closet detail view**

Modify `Closet/Closet/Closets/ClosetDetailView.swift` — add a `showingAddItem` sheet, a toolbar "+" button, and an "Items" section. Full new file content:

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
                    ForEach(viewModel.items) { item in
                        VStack(alignment: .leading) {
                            Text(item.category.rawValue)
                            if let caption = item.caption {
                                Text(caption).font(.footnote).foregroundStyle(.secondary)
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
            await viewModel.loadMembers(closetID: closet.id)
            await viewModel.loadItems(closetID: closet.id)
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemView(closetID: closet.id, userID: userID) {
                Task { await viewModel.loadItems(closetID: closet.id) }
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

- [x] **Step 3: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 4: Manually verify the full flow**

On a device or Simulator: open a Closet → tap "+" → choose 2-3 photos from the library → for each, tap a category (Next enables only once a category is picked) → optionally expand "More details" and fill in a size/color/caption on one → after the last photo, tap Continue → on the share screen, optionally check another Closet you're in → tap Save → watch each item show a checkmark (or a retry icon if one fails — tap it to retry) → once all show checkmarks, tap Done → back on Closet Detail, confirm the new items appear in the "Items" section with the right category/caption. Then check the Supabase dashboard: Table Editor → `items`/`item_photos`/`item_shares` should show the new rows, and Storage → `item-photos` bucket should show the uploaded file(s) under `{your user id}/{item id}/0.jpg`.

- [x] **Step 5: Commit**

```bash
git add Closet/Closet/Closets/ClosetDetailViewModel.swift Closet/Closet/Closets/ClosetDetailView.swift
git commit -m "Wire Add Item flow and a bare-bones items list into Closet Detail"
```

---

## Roadmap: Later Phases (not yet planned in detail)

- **Phase 4 — Browse:** Closet grid, filter chips, search — replaces this phase's bare-bones items list with the real Retro-style grid, including signed-URL photo display
- **Phase 5 — Item Detail:** Retro-style full-screen view, tap navigation within the filtered set
- **Phase 6 — My Clothes:** cross-closet item management, per-item share toggles
- **Phase 7 — Report & Block:** reason picker, mutual hide, `reports`/`blocks` RLS
- **Phase 8 — Profile:** edit profile, blocked list, delete account
