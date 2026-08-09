# Phase 8: Profile — Design Spec

**Date:** 2026-08-09
**Status:** Approved design, pre-implementation

## 1. Goal

Replace `MainTabView`'s bare-bones "Profile" stub (`Text("Profile")`, Phase 1 scaffolding) with a real screen: edit name/sizes, upload a profile photo, view and unblock blocked users, sign out, and delete your account (product spec §3.5).

**In scope:**
- Editing name + top/bottom/shoe sizes (no backend change needed — `users` already has full self-scoped SELECT/INSERT/UPDATE from Phase 1)
- Profile photo upload (new `profile-photos` Storage bucket + RLS)
- Blocked users list + unblock (`blocks` gains SELECT + DELETE, both scoped to `blocker_id = auth.uid()`)
- Sign out (wires up `AuthViewModel.signOut()`, which has existed unused since Phase 1)
- Delete account (a `SECURITY DEFINER` Postgres function that deletes the `auth.users` row; every other table already cascades from there)

**Out of scope, confirmed with the user:**
- A Profile-specific "manage Closets" list — `ClosetsListView` + each Closet's existing "Leave Closet" already cover this; Profile does not duplicate it
- Retrofitting the Phase 6 orphaned-share gap (sharing into a Closet you've since left) — unblocking is a separate mechanism from that gap; stays deferred
- Retrofitting other screens (`ItemDetailView`'s owner avatar, Members lists) to show real profile photos now that upload exists — not part of "Phase 8: Profile" as scoped by the roadmap; a natural fast-follow, not built here
- Cleaning up orphaned Storage files after account deletion — Postgres's cascade doesn't reach Storage objects; the files become permanently inaccessible garbage (nothing can construct a valid RLS-passing query for them once the owning rows are gone) but aren't deleted. A real but non-urgent storage-cost concern, not a correctness or security issue.

## 2. Profile Editing

No backend change. `20260803000001_users_rls.sql` already grants `authenticated` `select, insert, update` on `users`, scoped to `auth.uid() = id`. A new `ProfileViewModel` (not a reuse of `OnboardingViewModel` — the flows differ enough: Profile pre-populates from an existing row and never redirects, Onboarding starts blank and redirects on completion) handles load/save:

```swift
func load(userID: UUID) async {
    isLoading = true
    defer { isLoading = false }
    do {
        let profile: UserProfile = try await client
            .from("users")
            .select()
            .eq("id", value: userID)
            .single()
            .execute()
            .value
        name = profile.name
        topSize = profile.sizes["top"] ?? ""
        bottomSize = profile.sizes["bottom"] ?? ""
        shoeSize = profile.sizes["shoe"] ?? ""
        photoPath = profile.photoURL
        errorMessage = nil
    } catch {
        errorMessage = error.localizedDescription
    }
    if let photoPath {
        await loadSignedPhotoURL(path: photoPath)
    }
}

func save(userID: UUID) async -> Bool {
    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
        errorMessage = "Name is required"
        return false
    }
    isSaving = true
    defer { isSaving = false }

    var sizes: [String: String] = [:]
    if !topSize.isEmpty { sizes["top"] = topSize }
    if !bottomSize.isEmpty { sizes["bottom"] = bottomSize }
    if !shoeSize.isEmpty { sizes["shoe"] = shoeSize }

    struct ProfileUpdate: Encodable {
        let name: String
        let sizes: [String: String]
    }

    do {
        try await client
            .from("users")
            .update(ProfileUpdate(name: name, sizes: sizes))
            .eq("id", value: userID)
            .execute()
        errorMessage = nil
        return true
    } catch {
        errorMessage = error.localizedDescription
        return false
    }
}
```

This mirrors `OnboardingViewModel.save`'s size-dictionary construction exactly (same three fields, same convention), but uses `.update()` scoped by `eq("id", ...)` rather than `.upsert()`, since we know the row already exists — semantically correct for an edit rather than a first-time create.

## 3. Profile Photo

New Storage bucket, one file per user, always overwritten — no per-item path segment needed since a profile has exactly one photo:

```sql
insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', false)
on conflict (id) do nothing;

create policy "Users can upload their own profile photo"
  on storage.objects for insert
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can overwrite their own profile photo"
  on storage.objects for update
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can view their own or closet-mates' profile photos"
  on storage.objects for select
  using (
    bucket_id = 'profile-photos'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (
        select 1 from public.closet_members cm1
        join public.closet_members cm2 on cm1.closet_id = cm2.closet_id
        where cm1.user_id = auth.uid()
        and cm2.user_id = ((storage.foldername(name))[1])::uuid
      )
    )
  );
```

The SELECT policy deliberately mirrors `20260804000000_closets_rls.sql`'s "Users can view profiles of closet-mates" `users`-table policy exactly, so photo visibility always matches profile visibility.

The UPDATE policy is included from the start (not discovered the hard way like Phase 3's item-photo upload was) — `upsert: true` on the client's Storage upload needs `UPDATE` privilege regardless of whether a conflict actually occurs, and a profile photo is re-uploaded far more often than an item photo (an item photo is set once; a profile photo can be changed any time from this same screen).

**Path-guard note:** Phase 5 had to add a UUID-shape guard to `item-photos`' paths because that bucket's INSERT policy only validated the *owner* segment, leaving the *item-id* segment unchecked, so a malformed item-id could slip through and later break a `::uuid` cast. That gap can't recur here: `profile-photos` has only one path segment (`{user_id}/photo.jpg`), and the INSERT/UPDATE policies already constrain that single segment to exactly `auth.uid()::text` — a malformed path can never be created in the first place.

Client:

```swift
func uploadPhoto(_ image: UIImage, userID: UUID) async {
    isUploadingPhoto = true
    defer { isUploadingPhoto = false }
    guard let imageData = ImageCompressor.compress(image) else {
        errorMessage = "Could not process image"
        return
    }
    let path = "\(userID.uuidString.lowercased())/photo.jpg"

    struct PhotoUpdate: Encodable {
        let photoURL: String
        enum CodingKeys: String, CodingKey { case photoURL = "photo_url" }
    }

    do {
        try await client.storage.from("profile-photos").upload(
            path,
            data: imageData,
            options: FileOptions(contentType: "image/jpeg", upsert: true)
        )
        try await client.from("users").update(PhotoUpdate(photoURL: path)).eq("id", value: userID).execute()
        photoPath = path
        errorMessage = nil
        await loadSignedPhotoURL(path: path)
    } catch {
        errorMessage = error.localizedDescription
    }
}

func loadSignedPhotoURL(path: String) async {
    signedPhotoURL = try? await client.storage.from("profile-photos").createSignedURL(
        path: path,
        expiresIn: 3600,
        transform: TransformOptions(width: 200, height: 200, resize: .cover)
    )
}
```

Reuses `ImageCompressor` (Phase 3) unchanged — same downscale/compress need, no reason for a second implementation.

## 4. Blocked Users List + Unblock

`blocks` currently has only `insert` granted (Phase 7). This phase adds:

```sql
grant select, delete on public.blocks to authenticated;

create policy "Users can view their own blocks"
  on public.blocks for select
  using (blocker_id = auth.uid());

create policy "Users can remove their own blocks"
  on public.blocks for delete
  using (blocker_id = auth.uid());
```

Deliberately scoped to `blocker_id = auth.uid()` only — you can see and manage who *you've* blocked, never who's blocked *you*.

**A real gap caught during design, not left for final review to find:** the `users` table's only SELECT policies are self-view and closet-mates. If a blocked person leaves every Closet you two shared (nothing in this phase's design changes that — blocking never touches membership), the "closet-mates" clause stops applying, and the blocked-users list would show an unreadable entry (an id with no fetchable name) for someone you specifically need to identify in order to unblock. Fixing this needs one more `users` policy:

```sql
create policy "Users can view profiles of people they've blocked"
  on public.users for select
  using (
    exists (select 1 from public.blocks where blocker_id = auth.uid() and blocked_id = users.id)
  );
```

This is narrowly motivated by the one screen that needs it (you can always identify someone you've chosen to block, regardless of continued closet overlap) and doesn't expose anything to anyone who hasn't already taken that action.

Client (two plain queries rather than a PostgREST embed — `blocks` has two FKs to `users`, `blocker_id` and `blocked_id`, so an embedded `users(...)` select would be ambiguous without an explicit relationship hint; two simple queries avoid that entirely for a list that's realistically always short):

```swift
struct BlockedUser: Identifiable {
    let id: UUID
    let name: String
}

func loadBlockedUsers() async {
    do {
        struct BlockRow: Decodable {
            let blockedID: UUID
            enum CodingKeys: String, CodingKey { case blockedID = "blocked_id" }
        }
        let rows: [BlockRow] = try await client
            .from("blocks")
            .select("blocked_id")
            .execute()
            .value
        let blockedIDs = rows.map(\.blockedID)
        guard !blockedIDs.isEmpty else {
            blockedUsers = []
            return
        }

        struct NameRow: Decodable {
            let id: UUID
            let name: String
        }
        let names: [NameRow] = try await client
            .from("users")
            .select("id, name")
            .in("id", values: blockedIDs)
            .execute()
            .value
        blockedUsers = names.map { BlockedUser(id: $0.id, name: $0.name) }
        errorMessage = nil
    } catch {
        errorMessage = error.localizedDescription
    }
}

func unblock(blockedID: UUID, blockerID: UUID) async {
    do {
        try await client
            .from("blocks")
            .delete()
            .eq("blocker_id", value: blockerID)
            .eq("blocked_id", value: blockedID)
            .execute()
        await loadBlockedUsers()
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

`unblock` re-fetches the list afterward rather than optimistically removing the row client-side — same "always re-sync from the server" discipline Phase 6's share-toggle established.

## 5. Sign Out

`AuthViewModel.signOut()` (`Closet/Closet/Auth/AuthViewModel.swift`) has existed since Phase 1 and has never been called from anywhere. `RootView` owns the `AuthViewModel` instance but currently only passes `userID: UUID` down to `MainTabView` — no path exists yet for a child screen to trigger sign-out. Rather than thread the whole `AuthViewModel` down through `MainTabView` into `ProfileView` (which would give `ProfileView` access to unrelated auth state), a small closure is threaded instead, matching the existing convention of passing closures across screen boundaries (`ClosetDetailView`'s `onLeft`, `AddItemView`'s `onItemsSaved`, etc.):

- `RootView` passes `MainTabView(userID: userID, onSignedOut: { try? await authViewModel.signOut() })`
- `MainTabView` passes that same closure through to `ProfileView`
- `ProfileView`'s "Sign Out" button calls it directly; no confirmation dialog (low-stakes, trivially reversible by signing back in)

The same closure is reused after a successful account deletion (§6) — clearing the local session is the same mechanical action either way.

**A real gap this makes reachable for the first time:** `RootView`'s `@State private var hasProfile: Bool?` persists for as long as `RootView` itself stays alive — which, since it sits at the app's root, is the whole app session. Sign-out has existed on `AuthViewModel` since Phase 1 but was never callable from anywhere, so `hasProfile` never had a reason to go stale. Now that it's reachable: if Alice signs out and a *different* user (say, Bob, who hasn't onboarded) signs in on the same device, `hasProfile` still holds Alice's earlier `true` and `RootView` would send Bob straight into `MainTabView` under his own `userID`, skipping `OnboardingView` entirely — his `users` row would never get created, breaking every subsequent load that assumes it exists. Fix: the `onSignedOut` closure passed into `MainTabView` also resets `hasProfile = nil`, so the next sign-in re-triggers `checkProfile`, regardless of whether it's the same person or someone new.

**Ordering matters here, and the final whole-plan review caught a real bug in this design's first draft:** the reset must happen *after* `signOut()` completes, not before. supabase-swift clears its local session before making the network sign-out call, so if `hasProfile = nil` runs first, `RootView` re-enters the `hasProfile == nil` branch *while `authViewModel.session` is still non-nil* and fires `checkProfile` concurrently with the in-flight sign-out — racing an unauthenticated `users` count query against session teardown. If that race resolves to `hasProfile = false`, the very next sign-in (including the same user signing straight back in) is routed through `OnboardingView` instead of `MainTabView`, and `OnboardingViewModel.save`'s upsert overwrites the real profile — including nulling `photo_url` and replacing saved sizes — with blank onboarding defaults. Silent data loss on the phase's own happy path. Correct ordering:

```swift
onSignedOut: {
    try? await authViewModel.signOut()
    hasProfile = nil
}
```

Once `signOut()` completes and `session` is `nil`, `RootView` renders `SignInView` — which reads neither `hasProfile` nor `checkProfile` — so resetting afterward is both safe and sufficient; there is no window where a stale or racing value can be read.

## 6. Delete Account

A `SECURITY DEFINER` function, callable via RPC, deletes the caller's own `auth.users` row:

```sql
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;
```

Traced the full cascade chain before choosing this approach: `public.users.id references auth.users(id) on delete cascade`, and every other table cascades from `public.users` — `closet_members`, `items` (which itself cascades to `item_photos`/`item_shares`), `reports` (both as `reporter_id` and `reported_user_id`), `blocks` (both as `blocker_id` and `blocked_id`). The one non-cascading FK, `closets.created_by`, is already `on delete set null` (fixed in Phase 2, matching the product spec's "a Closet stays intact when its creator leaves" rule) — so deleting a user never blocks on a closet they created. One function call, one transaction, everything Postgres-side is handled.

Client:

```swift
func deleteAccount() async -> Bool {
    do {
        try await client.rpc("delete_own_account").execute()
        return true
    } catch {
        errorMessage = error.localizedDescription
        return false
    }
}
```

`ProfileView` gates this behind a `.confirmationDialog` (matching the existing "Leave Closet" pattern — no heavier "type DELETE to confirm" flow, since a plain destructive-styled confirmation is what every other irreversible-ish action in this app already uses). On success, it calls the same `onSignedOut` closure from §5 to clear the local session and let `RootView` navigate back to `SignInView`.

## 7. Error Handling

- Profile load/save failures: `errorMessage` banner, same pattern as every other view model in the app
- Photo upload failure: `errorMessage` banner; the previous photo (if any) stays displayed, nothing is cleared optimistically
- Unblock failures: `errorMessage` banner; the list re-fetches regardless (§4), so it can never show a stale state
- Delete-account failure: `errorMessage` banner, account and session remain untouched — safe to retry
- Sign-out has no failure path worth surfacing (`try?` swallows it, matching how the app already treats sign-out as best-effort elsewhere — there's no meaningful recovery action for a user to take if clearing a local session fails)

## 8. Testing

This phase touches RLS in two ways that get real pgTAP coverage, matching the project's established practice:
- `blocks` SELECT/DELETE policies, and the new `users` policy allowing a blocker to see who they've blocked
- `delete_own_account()` — given this is a high-stakes, irreversible operation, it gets explicit test coverage: calling it as user A cascades away A's `items`/`closet_members`/etc. and does not affect user B's data

Storage RLS (`profile-photos`) does not get pgTAP coverage, consistent with the project's established convention (`item-photos` never got it either) — manual/exploratory QA covers it instead.

Manual/exploratory QA for the SwiftUI side: editing name/sizes persists and reloads correctly; uploading a photo displays it and persists across app relaunch; the blocked list shows correct names (including for someone no longer sharing a Closet with you) and unblock actually restores visibility of their items; sign out returns to the sign-in screen; delete account (on a disposable test account) removes the ability to sign back in with that identity and returns to sign-in.
