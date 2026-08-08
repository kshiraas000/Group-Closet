# Phase 6: My Clothes — Design Spec

**Date:** 2026-08-08
**Status:** Approved design, pre-implementation

## 1. Goal

Replace `MainTabView`'s bare-bones "My Clothes" stub (`Text("My Clothes")`, Phase 1 scaffolding) with a real cross-closet view of everything the current user owns — same grid/filter/search UX as Phase 4's Browse, scoped to items you own rather than one Closet's shares (product spec §3.3). Tapping an item opens the existing `ItemDetailView` (Phase 5), which gains a new "Shared to:" section letting the owner toggle which Closets can see the item (product spec §3.3's "manage which Closets see each item").

**In scope:**
- `MyClothesView` + `MyClothesViewModel`: items you own across all Closets, filterable/searchable, no Person chip (redundant — everything shown is already yours)
- `item_shares` DELETE policy + grant (the one new backend capability this phase needs)
- `ItemDetailView`'s new "Shared to:" section, owner-only, toggle add/remove
- Extracting `BrowseItem`/`BrowseFilters`/filtering logic out of `ClosetDetailViewModel` into a shared location, since My Clothes is now a second real consumer
- Fixing the stale-index tap-navigation risk in both `ClosetDetailView` and the new `MyClothesView` (see §3) — Phase 5's final review flagged this as latent-but-unreachable until a removal path existed; this phase adds one

**Out of scope:**
- Item Edit/Delete — still no `UPDATE`/`DELETE` grant on `items`/`item_photos`; the "•••" menu's Edit/Delete options stay disabled exactly as Phase 5 left them
- A "which Closet is this shared to" filter chip on My Clothes — not requested by the spec ("Same grid + filter UI" reads as category/size/color/occasion/search, minus Person); the toggle list inside the detail view already exposes this information
- Any confirmation dialog before unsharing — confirmed with the user: immediate, reversible toggle, matching how Add Item's original "share to" checkboxes already behave

## 2. Shared Filtering Logic

`ClosetDetailViewModel.swift` currently defines `BrowseItem`, `BrowseFilters`, and the `filteredItems`/`availableSizes`/`availableColors`/`availableOccasions` computed properties directly on itself (Phase 4). `MyClothesViewModel` needs the exact same filtering behavior over a differently-sourced `[BrowseItem]` array, so these move to a new shared file:

`Closet/Closet/Models/BrowseItem.swift`:
```swift
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

`ClosetDetailViewModel` keeps its own private `RawBrowseItem`/`PhotoRow`/`ItemShareRow` decode types and `makeBrowseItem` mapping function — those are specific to its `item_shares`-joined query shape and aren't shared. Its `filteredItems`/`availableSizes`/etc. become one-line forwarders to `BrowseFiltering`. `filters.ownerID` (the Person filter) stays in the shared `BrowseFilters` struct since `ClosetDetailView` still uses it — `MyClothesView` just never renders a chip that sets it, so it stays permanently `nil` there and every item passes that check trivially.

## 3. My Clothes Data Flow

`MyClothesViewModel` queries the `items` table directly, filtered by ownership — no `item_shares` join needed, since ownership alone determines what appears in My Clothes (regardless of how many, or how few, Closets an item is shared to):

```swift
items.select("*, item_photos(photo_url, position)").eq("owner_id", value: userID)
```

The existing `items` RLS SELECT policy (`can_view_item`) already permits this — the owner clause covers it directly, no policy change needed for the read side.

Alongside this, `MyClothesViewModel` fetches the current user's own `UserProfile` row once (`users` table, single row by `id`) and stores it as `myProfile: UserProfile?`. This is passed to `ItemDetailView` as `members: [myProfile].compactMap { $0 }` — reusing Phase 5's exact existing interface unchanged, since every item's owner in My Clothes is the viewer themselves, and the existing `members.first { $0.id == ownerID }?.name ?? "Unknown"` lookup resolves correctly against a one-element array containing just yourself.

Signed URLs for grid thumbnails and the tap-to-detail flow reuse the same patterns Phase 4/5 established (concurrent per-path `createSignedURL` with a resize transform for the grid, snapshot-the-filtered-set-at-tap-time for detail navigation).

## 4. The Stale-Index Fix

Both `ClosetDetailView`'s and (new) `MyClothesView`'s grid cells currently would compute a tapped cell's `startIndex` from the `ForEach`'s enumeration at render time, while separately reading `viewModel.filteredItems` fresh at tap time to build the snapshot passed into `ItemDetailView`. If the set shrinks between a cell rendering and the user tapping it — which becomes possible for the first time once this phase's unshare action exists — the baked-in index and the freshly-read array can disagree, either opening the wrong item or (if the set shrank enough) crashing on an out-of-bounds index.

Fix (applied to both files): look up the tapped item's index within the snapshot itself, by ID, at the moment of the tap:

```swift
let snapshot = viewModel.filteredItems
if let index = snapshot.firstIndex(where: { $0.id == browseItem.id }) {
    detailContext = ItemDetailContext(items: snapshot, startIndex: index)
}
```

If the tapped item has *already* vanished from the snapshot by the time the tap is processed (a narrower race than before, but not impossible), the `if let` simply does nothing — no detail view opens, no crash. This is a plain code fix, not a new capability, so it's paired with Task 1 rather than treated as its own task.

## 5. Share-Toggle Backend

New migration granting the one capability this phase actually needs — the ability for an owner to remove their own item's share into a Closet:

```sql
grant delete on public.item_shares to authenticated;

create policy "Item owners can remove their own item shares"
  on public.item_shares for delete
  using (
    exists (select 1 from public.items where id = item_shares.item_id and owner_id = auth.uid())
  );
```

Adding a share (re-checking a previously-unshared Closet) needs no new policy — Phase 3's existing INSERT policy ("Item owners can share their own items to closets they're in") already covers it exactly. No changes to `items`/`item_photos` grants — Edit/Delete stays out of scope (see §1).

## 6. Share-Toggle UI

`ItemDetailViewModel` gains:

```swift
var allClosets: [Closet] = []
var sharedClosetIDs: Set<UUID> = []
var shareStateErrorMessage: String?

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
    await loadShareState(itemID: itemID)  // always re-fetch actual state, success or failure — never an optimistic guess
}
```

`loadShareState` fires via `.task(id: currentIndex)` alongside the existing full-res-photo fetch, but only when `isOwner` is true for the currently-displayed item (non-owners never see or fetch this data — RLS would reject a delete attempt regardless, but there's no reason to even query it client-side for an item you don't own).

`ItemDetailView` gains a new section (visible only when `isOwner`, positioned below the existing caption/size/color/occasion line): a list of `allClosets`, each row toggleable, checked when its ID is in `sharedClosetIDs`. Tapping calls `toggleShare` immediately — no confirmation (confirmed with the user, §1) — and re-fetches actual share state afterward rather than optimistically flipping the checkmark client-side, so the UI can never show a state the database doesn't actually have. A failed toggle surfaces `shareStateErrorMessage` inline in this section rather than failing silently.

## 7. Error Handling

- My Clothes item-load failures: same `errorMessage` banner pattern as `ClosetDetailViewModel`
- Share-toggle failures: surfaced inline in the "Shared to:" section; state is re-fetched after every toggle attempt (success or failure) so displayed checkmarks always reflect the database, never an optimistic guess
- Signed-URL and full-res-photo failures: unchanged from Phases 4/5 (per-item placeholder, never blocks the rest of the grid or navigation)
- The stale-index fix (§4) turns a would-be crash into a silent no-op tap — acceptable since the alternative (the item vanished a moment ago) has no meaningful action to take anyway

## 8. Testing

This phase touches RLS for the first time since Phase 3, so it gets real pgTAP coverage (unlike Phases 4/5, which were purely client-side): a new test (or an addition to `supabase/tests/database/items_rls.sql`) verifying an item's owner can delete their own `item_shares` row, a non-owner cannot delete a share for an item they don't own, and — after deletion — the item correctly stops appearing to other members of that Closet (while still appearing in the owner's own `items` query, since My Clothes doesn't depend on shares at all).

Manual/exploratory QA for the SwiftUI side (My Clothes grid/filters/search, share toggling, the stale-index fix's tap-still-works behavior), consistent with the project's established approach and Phase 3/4/5's precedent.
