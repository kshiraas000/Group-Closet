# Phase 4: Browse — Design Spec

**Date:** 2026-08-05
**Status:** Approved design, pre-implementation

## 1. Goal

Replace `ClosetDetailView`'s bare-bones "Items" list (category + caption text only, added as throwaway scaffolding in Phase 3) with the real browse experience described in the product spec §3.1: an edge-to-edge photo grid, newest first, with filter chips (category · person · size · color · occasion) and text search. Includes resolving Storage paths into displayable signed URLs, which Phase 3 explicitly deferred.

**Out of scope for this phase** (per the Phase 3 roadmap and product spec):
- Item detail view / tap navigation into a full-screen view — that's Phase 5. Tapping a grid cell is a no-op.
- My Clothes tab (cross-closet view) — that's Phase 6.
- Any backend/RLS changes — Phase 3's `storage.objects` policies already gate `item-photos` access correctly for signed-URL generation; this phase is client-side only.

## 2. Architecture & Data Flow

`ClosetDetailViewModel.loadItems` (originally `load`) currently queries:

```
item_shares.select("items(*)").eq("closet_id", value: closetID)
```

This only returns the `items` row shape (`Item` struct) — no photo, no owner name. This phase extends the query to embed both:

```
item_shares.select("items(*, item_photos(photo_url, position), users(name))")
  .eq("closet_id", value: closetID)
```

Decoded into a new raw row type, then mapped into a display-only `BrowseItem`:

```swift
struct BrowseItem: Identifiable {
    let item: Item
    let photoPath: String?      // item_photos row at position 0, if any
    let ownerName: String
    var signedURL: URL?         // filled in after the batch signed-URL call
}
```

The existing `Item` struct (Task 2 of Phase 3, maps 1:1 to the `items` table) is left untouched — it's used elsewhere and shouldn't grow fields that belong to a join. `ClosetDetailViewModel.items` changes type from `[Item]` to `[BrowseItem]`.

**Signed URLs:** supabase-swift 2.54.1's batch `createSignedURLs(paths:expiresIn:)` does not accept a `transform` parameter — only the single-item `createSignedURL(path:expiresIn:transform:)` does. So instead of one batch call, fire one `createSignedURL` per distinct non-nil `photoPath` concurrently via a `TaskGroup`:

```swift
var results: [String: URL] = [:]
await withTaskGroup(of: (String, URL?).self) { group in
    for path in paths {
        group.addTask {
            let url = try? await client.storage.from("item-photos").createSignedURL(
                path: path,
                expiresIn: 3600,
                transform: TransformOptions(width: 400, height: 400, resize: .cover)
            )
            return (path, url)
        }
    }
    for await (path, url) in group {
        if let url { results[path] = url }
    }
}
```

Results are mapped back onto `BrowseItem.signedURL` by matching path. This is N concurrent requests rather than 1, but preserves the actual goal (small transformed thumbnails, fast grid scroll) — acceptable at MVP data scale (a friend group's closet: tens of items, not thousands). Using the non-throwing `withTaskGroup` (each task swallows its own error via `try?`) means one item's signed-URL failure doesn't cancel the others — it just leaves that one path unmapped, matching §5's per-item placeholder behavior instead of an all-or-nothing failure.

If this batch call fails, items still render — with a placeholder icon in place of the photo — rather than blocking the whole grid on a Storage error. This matches the existing pattern (see `cde9439`) of surfacing errors without hiding data that did load successfully.

## 3. Filtering & Search

A `BrowseFilters` struct (new, owned by `ClosetDetailViewModel` or a dedicated view state) holds one optional selection per chip type:

```swift
struct BrowseFilters {
    var category: ItemCategory?
    var ownerID: UUID?
    var size: String?
    var color: String?
    var occasion: String?
    var searchText: String = ""
}
```

**Combination logic:** AND across chip types, single-select within each type — e.g. category=Top AND person=Alice both must match; there is no "Top OR Bottom" within the category chip. This keeps the chip UI simple (tap to select, tap again to clear) and avoids query-building complexity disproportionate to this phase's scope.

**Chip value sources:**
- Category: fixed `ItemCategory.allCases`
- Person: closet members already loaded via `loadMembers`
- Size / Color / Occasion: derived — distinct, non-empty values pulled from the currently-loaded `BrowseItem`s. A chip only ever appears if at least one item would match it; no dead-end filters. `occasion_tags` is an array field, so occasion chip values are the flattened distinct set across all items' tag arrays.

**Search:** matches caption + category + color (substring, case-insensitive) — the fields a user would plausibly type a free-text guess for. Owner name and occasion are already covered by their own chips, so search doesn't duplicate them.

**Evaluation:** entirely client-side over the already-loaded `BrowseItem`s via a computed `filteredItems` — no re-query to Supabase on filter/search change. This matches the "derive chip values from loaded items" decision and is appropriate at MVP data scale (a friend group's closet, not thousands of items).

## 4. UI

`ClosetDetailView` keeps its existing `List` structure — Members, Share Invite, Leave Closet stay exactly as they are; only the "Items" `Section` changes:

- A horizontal `ScrollView` row of filter chips (category · person · size · color · occasion), each toggleable; active chip visually distinguished (same pattern as `PhotoTaggingView`'s category buttons — tap to select/tint, tap again to clear)
- Below that, a `LazyVGrid` of thumbnails (2–3 adaptive columns), edge-to-edge via `.listRowInsets(EdgeInsets())` on that row, each cell an `AsyncImage(url: item.signedURL)` with a placeholder for nil/loading/failed states
- `.searchable(text:)` attached to the view, bound into `BrowseFilters.searchText`
- Grid cells are plain views with no tap gesture attached — Phase 5 adds the `Button`/navigation behavior

Empty state ("No items yet" / "No items match your filters") replaces the current bare "No items yet" text, distinguishing "closet has no items" from "filters exclude everything."

## 5. Error Handling

- Item/member load failures: unchanged, existing `errorMessage` banner pattern
- Signed-URL batch failure: items render with a placeholder image, not blocked (§2)
- No new RLS-driven "not found" cases introduced — this phase only reads rows the user could already read via existing Phase 1–3 RLS

## 6. Testing

No new pgTAP coverage — no schema or RLS changes in this phase. Manual/exploratory QA for the SwiftUI flow (grid renders, chips filter correctly alone and combined, search narrows the grid, empty states appear correctly, signed URLs display real photos), consistent with the project's stated testing approach (product spec §6) and Phase 3's precedent.
