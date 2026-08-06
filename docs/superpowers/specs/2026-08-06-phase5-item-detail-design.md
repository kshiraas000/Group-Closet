# Phase 5: Item Detail — Design Spec

**Date:** 2026-08-06
**Status:** Approved design, pre-implementation

## 1. Goal

Wire up the grid cells Phase 4 left as no-ops: tapping an item in `ClosetDetailView`'s grid opens a full-screen, Retro-style detail view (product spec §3.4) showing the item's full photo, owner, category, caption, and size/color/occasion, with tap-to-navigate to the next/previous item within the same filtered/sorted set the grid was showing when it was opened.

**In scope:**
- Full-screen photo view with top bar (owner + category + "X of Y" counter + close), caption/chips below the photo, tap-left/tap-right navigation
- A "•••" menu, present but fully disabled (Report for everyone, Edit/Delete for the owner) — see §4

**Out of scope for this phase:**
- Any backend change. Report (Phase 7) and item Edit/Delete (no `UPDATE`/`DELETE` grant exists on `items`/`item_photos` yet) are both unimplemented; the menu exists visually per product decision but every option is inert.
- Profile photo upload — `UserProfile.photoURL` is a real column but nothing in the app populates it yet (confirmed: only write site is `OnboardingViewModel.swift:29`, which always sets it to `nil`). The owner avatar will render as a placeholder until a future phase adds upload.
- Reuse from My Clothes (Phase 6) — not built yet; this phase's `ItemDetailView` interface is generic enough to be reused later, but nothing here builds for that beyond a clean interface.

## 2. Avoiding Phase 4's Bug Pattern

Phase 4 originally embedded owner name via a PostgREST nested query (`users(name)`) on the items query, which threw and wiped out the whole grid whenever the owner had left the closet (RLS then returns `null` for a non-optional field). That embed was removed entirely once found to be unused.

This phase needs owner name (and, eventually, an avatar) for the top bar, but avoids repeating the bug: it looks up the owner **client-side** from `ClosetDetailViewModel.members` (already loaded for the Members section and the Person filter chip) by matching `BrowseItem.item.ownerID`. If the owner isn't found — because they left the closet after sharing the item, the exact scenario that broke Phase 4 — the lookup returns `nil` instead of throwing, and the UI shows a fallback label ("Unknown") instead of crashing. No new query, no new embed, no new fragility.

## 3. Data Flow & Navigation

**Opening the detail view:** `ClosetDetailView` gains a small `Identifiable` context struct:

```swift
private struct ItemDetailContext: Identifiable {
    let id = UUID()
    let items: [BrowseItem]
    let startIndex: Int
}
```

Tapping a grid cell sets `@State private var detailContext: ItemDetailContext?` to `ItemDetailContext(items: viewModel.filteredItems, startIndex: <tapped index>)`, presented via `.fullScreenCover(item: $detailContext)`. Capturing `viewModel.filteredItems` at tap time (arrays are value types in Swift) is what makes the "X of Y" counter scoped to "whatever set you opened it from" per spec §3.4 — if the grid's filters change after the detail view is open, the open detail view's set doesn't change underneath it.

**Inside `ItemDetailView`:** owns `@State private var currentIndex: Int` (initialized from `startIndex`). Tapping the right third of the photo does `currentIndex = min(currentIndex + 1, items.count - 1)`; the left third does `currentIndex = max(currentIndex - 1, 0)` — both clamped, no wraparound past either end. The middle third is a no-op (not specified by the product spec beyond left/right). An explicit X button in the top bar calls `dismiss()` — `fullScreenCover` has no swipe-to-dismiss, so this is the only way out, matching spec §3.4's "X to close."

**Photo resolution:** the grid's 400×400 `.cover`-cropped thumbnails aren't good enough for a full-screen "full-bleed photo." `ItemDetailViewModel` fetches one new signed URL per item the user actually visits, sized larger (1200px, `resize: .contain` so nothing is cropped — the grid crops for a tidy square, the detail view should show the whole photo), and caches it by item ID so revisiting an item earlier in the same set within the same session doesn't re-fetch:

```swift
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
        if let url { fullResURLs[item.id] = url }
    }
}
```

The view triggers `loadFullResURL(for:)` whenever `currentIndex` changes (via `.task(id: currentIndex)`), and renders `AsyncImage(url: viewModel.url(for: items[currentIndex]))` with a placeholder while it loads or if it fails — same non-blocking failure pattern Phase 4 established for grid thumbnails (one bad photo doesn't break navigation to the next item).

## 4. UI Layout

Per product spec §3.4:

- **Top bar:** leading = placeholder avatar (a person-silhouette system image; see §1 — no real photos exist yet) + owner name (bold, or "Unknown" per §2's fallback) with category as a muted subtitle beneath; trailing = "`{currentIndex+1} of {items.count}`" counter (muted) + an X button that dismisses
- **Photo:** full-bleed, uncropped (`.scaledToFit()` against the 1200px `.contain`-transformed image)
- **Below the photo:** caption in bold if present; a muted secondary line listing size/color/occasion as plain (non-interactive) text chips — display-only, unlike the grid's tappable filter chips
- **No like icon, no tagged-friends avatars, no location** — explicitly cut per product spec §3.4
- **Bottom-right "•••" menu:** a `Menu` whose options depend on whether `currentIndex`'s item's `ownerID == userID`:
  - Owner: "Edit" and "Delete" (destructive style), both `.disabled(true)`
  - Non-owner: "Report", `.disabled(true)`
  
  Disabled `Menu` items render viewer-grayed and are inert on tap — sufficient to read as "not available yet" without extra "coming soon" copy. Recomputed per `currentIndex` since ownership varies item-to-item within a set.

## 5. Error Handling

- Full-res signed URL fetch failure: same as Phase 4's grid thumbnails — the specific item shows a placeholder instead of a photo; navigation to other items in the set is unaffected (per-item `try?`, no propagated throw).
- Owner not found in `members` (they left the closet): fallback "Unknown" label, no crash — this is the direct fix for Phase 4's bug pattern (§2).
- No RLS-driven "not found" cases introduced — this phase only displays data the grid already successfully loaded and displayed under existing RLS.

## 6. Testing

No new pgTAP coverage — no schema/RLS/backend changes in this phase. Manual/exploratory QA for the SwiftUI flow (tap into an item, navigate forward/back through a filtered set, confirm the counter and clamping at both ends, confirm the "•••" menu shows the right disabled options for owned vs. not-owned items, confirm the owner name shows correctly and falls back gracefully for an item whose owner has left the closet), consistent with the project's stated testing approach and Phase 3/4's precedent.
