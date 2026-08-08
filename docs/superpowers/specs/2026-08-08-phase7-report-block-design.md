# Phase 7: Report & Block — Design Spec

**Date:** 2026-08-08
**Status:** Approved design, pre-implementation

## 1. Goal

Enable the "Report" option Phase 5 left disabled in `ItemDetailView`'s "•••" menu, and add a new "Block" option alongside it — both reachable only for items you don't own, matching Phase 5's existing owner/non-owner menu split. Blocking mutually hides items between the two users, everywhere, immediately (product spec §3.6, §5).

**Deviation from the original product spec, confirmed with the user:** the spec called for a reason picker on Report. The user decided to drop it — Report is now a one-tap-and-confirm action with no reason captured.

**In scope:**
- `reports`/`blocks` tables (already exist since Phase 1, RLS-enabled but with zero grants/policies — fully untouched until now) get INSERT policies
- `can_view_item()` gains a mutual-block check — the single change point that cascades correctly to `items`, `item_photos`, and `storage.objects` (item photos), since a Phase 5 migration already routes all of those through this one function
- Report: confirm → insert → alert confirmation, no reason
- Block: confirm → insert → dismiss the detail view → reload the presenting Closet's grid

**Out of scope:**
- Any reason capture for reports (dropped, see above)
- Hiding a blocked person from Closet Members lists, filter chips, or anything membership-related — confirmed with the user: items only
- Unblock UI, a "blocked users" list, or any admin/moderation review UI — Phase 8 (Profile) and beyond, matching the product spec's explicit "no in-app moderation UI beyond [confirmation]"
- Reporting or blocking a user from anywhere other than item detail (e.g., Members lists, a future Profile) — no such entry point exists yet
- Any change to `item_shares`' SELECT policy — its residual "closet-mate can see a shared row exists" gap (see §2) predates this phase and doesn't leak actual item content

## 2. Backend: One Change Point Cascades Correctly

Traced every RLS policy touching item visibility:

- `items` SELECT: `using (can_view_item(id))`
- `item_photos` SELECT: `using (can_view_item(item_id))`
- `storage.objects` SELECT (item photos): owner-path bypass, else `can_view_item(...)` — this used to be an inline duplicate of the ownership/sharing check (Phase 3), but a Phase 5 migration (`20260805000001_storage_update_policy_and_path_guard.sql`) replaced the duplicate with an actual call to `can_view_item()`, specifically to avoid two copies of the same logic drifting apart. That fix means this phase gets photo-hiding for free.
- `item_shares` SELECT is the one exception: `can_view_item(item_id) or exists (select 1 from closet_members where closet_id = item_shares.closet_id and user_id = auth.uid())` — the second branch means a closet-mate can still see that *some* item_shares row exists even when `can_view_item` denies it post-block. This is pre-existing (not introduced by this phase) and doesn't leak content: the embedded `items`/`item_photos` data in any real query still resolves to nothing, since those two tables' own SELECT policies correctly deny it. Not fixing this — it's a bare existence leak of a join row, not the item itself, and out of this phase's stated scope.

Given this, the only backend change needed for "mutual hide, everywhere, immediately" is:

```sql
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

`create or replace function` preserves the existing grant (`execute` to `authenticated`, already revoked from `public` since Phase 4) — no grant changes needed for this function. The `not exists` clause checks both directions of the `blocks` table's directional `(blocker_id, blocked_id)` pair, which is what makes the hide mutual regardless of who blocked whom.

The storage `select` policy's owner-bypass branch (`(storage.foldername(name))[1] = auth.uid()::text`) is unaffected by this change — it only ever lets a user see their *own* uploaded photos, which must stay true even if someone else has blocked them. Blocking only ever affects the *other* person's ability to see *your* items, never your own.

## 3. Reports & Blocks Tables: Minimal Grants

Neither table has any grant or policy yet (confirmed: `grep`-ed every migration, only the Phase 1 schema/RLS-enable touches them). Both only need INSERT — nothing in this phase reads them back:

```sql
grant insert on public.reports to authenticated;

create policy "Users can create reports as themselves"
  on public.reports for insert
  with check (reporter_id = auth.uid());

grant insert on public.blocks to authenticated;

create policy "Users can block others as themselves"
  on public.blocks for insert
  with check (blocker_id = auth.uid() and blocked_id != auth.uid());
```

The `blocked_id != auth.uid()` clause prevents a degenerate self-block at the database level, not just the UI — since this is a `WITH CHECK` (INSERT) violation, attempting it throws `42501` (unlike the `DELETE ... USING` case Phase 6 got wrong — `WITH CHECK` failures on INSERT always throw, confirmed against Phase 3's existing INSERT policies, which behave the same way).

`reports.reason` is currently `not null`, but no reason is captured anymore:

```sql
alter table public.reports alter column reason drop not null;
```

Reporting an item sets `item_id` only (`reported_user_id` stays `null`) — the schema's two nullable fields represent two distinct report shapes ("report this item" vs. "report this user directly"), and only the item-detail entry point exists in this phase.

## 4. Client: Report

`ItemDetailViewModel` gains:

```swift
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
```

`ItemDetailView`'s `moreMenu` non-owner branch changes from a disabled `Button("Report") {}` to an enabled one that triggers a confirmation dialog, then an alert confirming the result — satisfying the spec's "toast confirmation" with the simplest native mechanism, consistent with the project's stated preference for functional-not-polished UI at this stage:

```swift
Button("Report") { showingReportConfirmation = true }
```

New state on `ItemDetailView`: `@State private var showingReportConfirmation = false`, `@State private var showingBlockConfirmation = false`, `@State private var showingActionAlert = false`, `@State private var actionAlertMessage = ""`.

```swift
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
.alert("", isPresented: $showingActionAlert) {
    Button("OK") {}
} message: {
    Text(actionAlertMessage)
}
```

Reporting does not change what's visible — the view stays open on the same item after the alert dismisses. `showingActionAlert`/`actionAlertMessage` are shared with Block's failure path (§5) — only one of Report/Block can be in flight at a time from a single menu, so no risk of one overwriting the other's message.

## 5. Client: Block

`ItemDetailViewModel` gains:

```swift
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
```

`moreMenu`'s non-owner branch gains a second option:

```swift
Button("Block \(ownerName)", role: .destructive) { showingBlockConfirmation = true }
```

```swift
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
```

On successful block, unlike Report, the item the viewer was just looking at has become invisible to them (per §2) — continuing to page through the current `items` snapshot risks showing broken/placeholder content for any other items by the same now-blocked owner still in that set. Rather than trying to live-filter the in-memory snapshot mid-session, `ItemDetailView` dismisses itself immediately on success (no alert needed — the screen closing and the item vanishing from the grid *is* the confirmation) and calls a new `onBlocked: () -> Void = {}` callback (mirroring Phase 6's `onShareChanged` pattern exactly) that tells the presenter to reload. Only a failed block shows the shared failure alert, since nothing changed and the view stays open:

```swift
init(items: [BrowseItem], startIndex: Int, members: [UserProfile], userID: UUID, onShareChanged: @escaping () -> Void = {}, onBlocked: @escaping () -> Void = {})
```

`ClosetDetailView` wires `onBlocked: { Task { await viewModel.load(closetID: closet.id) } }` — the reload naturally drops the now-invisible item(s) from the grid, since the underlying query is RLS-filtered by `can_view_item`.

`MyClothesView` does not need to wire `onBlocked` (or `onShareChanged`) at all: since My Clothes only ever shows items the viewer owns, `isOwner` is always `true` there, so the "•••" menu's non-owner branch — where Report/Block live — never renders. The default no-op parameter values mean `MyClothesView`'s existing call site needs no changes.

## 6. Error Handling

- Report/Block failures: the confirmation alert shows a generic failure message; the user can retry the same action (both are simple one-shot inserts, safe to retry)
- No optimistic UI changes for either action — both wait for the network call before showing any confirmation or dismissing anything
- A self-block attempt can't reach the confirmation dialog in the first place (the "Block" option only ever renders in the non-owner branch, and you can't be a non-owner of your own item) — the database-level `blocked_id != auth.uid()` check is defense in depth, not something the UI needs to guard against separately

## 7. Testing

New `supabase/tests/database/reports_blocks_rls.sql`:
- A user can insert a report as themselves (`reporter_id = auth.uid()`)
- A user cannot insert a report claiming to be someone else (`throws_ok`, `42501`)
- A user can insert a block as themselves
- A user cannot insert a block claiming to be someone else (`throws_ok`, `42501`)
- A user cannot block themselves (`throws_ok`, `42501` — a `WITH CHECK` violation, confirmed to actually throw unlike Phase 6's `DELETE ... USING` case)
- The core mutual-hide behavior, built on the same Alice/Bob/shared-item fixture pattern as `items_rls.sql`: before blocking, confirm Bob can see Alice's item shared into their mutual Closet (baseline); Alice blocks Bob; confirm Bob can no longer see Alice's item; confirm Alice can no longer see any of Bob's items shared into that same Closet (proving the hide runs in both directions, not just blocker-can't-see-blocked)

Manual/exploratory QA for the SwiftUI side (Report shows a confirmation and an alert without changing what's visible; Block shows a confirmation, then the detail view closes and the item is gone from the grid), consistent with the project's established testing approach.
