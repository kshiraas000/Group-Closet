# Phase 8: Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `MainTabView`'s bare-bones "Profile" stub with a real screen: edit name/sizes, upload a profile photo, view and unblock blocked users, sign out, and delete your account.

**Architecture:** Editing name/sizes needs no backend change — `users` already has full self-scoped SELECT/INSERT/UPDATE from Phase 1. Three new backend capabilities are added in one migration: a `profile-photos` Storage bucket (mirroring `item-photos`' RLS shape, but with the UPDATE policy included from the start rather than discovered the hard way like Phase 3 was), `SELECT`/`DELETE` on `blocks` scoped to `blocker_id = auth.uid()` plus a `users` policy letting a blocker always see who they've blocked (closes a real gap: the existing closet-mates policy alone would leave a blocked-list entry unreadable once the blocked person leaves every shared Closet), and a `SECURITY DEFINER` `delete_own_account()` function that deletes `auth.users` and lets Postgres's existing cascade chain handle everything else. Sign-out (`AuthViewModel.signOut()`, unused since Phase 1) and the new delete-account both funnel through one `onSignedOut` closure threaded `RootView` → `MainTabView` → `ProfileView`, matching this codebase's existing closure-passing convention rather than threading the whole `AuthViewModel` down. That same closure also resets `RootView`'s `hasProfile` state, closing a staleness gap that sign-out becoming reachable exposes for the first time.

**Tech Stack:** SwiftUI, `@Observable`, PhotosUI, PostgREST, supabase-swift Storage, pgTAP.

## Global Constraints

- iOS 17.0 minimum deployment target, SwiftUI `NavigationStack` + `@Observable` view models (unchanged from prior phases)
- Testing approach: Task 1 (the backend/RLS/function change) gets real pgTAP coverage. Task 2 (client-only) follows implement → verify build → manual QA → commit, not TDD. Storage RLS (`profile-photos`) does not get pgTAP coverage, matching `item-photos`' precedent — manual QA covers it instead.
- No Profile-specific "manage Closets" UI — `ClosetsListView` + each Closet's existing "Leave Closet" already cover this.
- No retrofitting other screens (`ItemDetailView`'s owner avatar, Members lists) to show real profile photos — out of scope for this phase.
- No cleanup of orphaned Storage files after account deletion — a known, accepted gap (see design doc §1).
- Sign out has no confirmation dialog (low-stakes, reversible). Delete account uses the same `.confirmationDialog` pattern as "Leave Closet" — no heavier flow.
- The `onSignedOut` closure is reused for both the Sign Out button and after a successful account deletion — same mechanical action either way.
- `ProfileViewModel` is a new type, not a refactor of `OnboardingViewModel` — the two flows (pre-populated edit vs. blank first-time setup with redirect) differ enough that sharing isn't worth it.

---

## File Structure

- Create: `supabase/migrations/20260809000000_profile_photos_and_account_deletion.sql` — `profile-photos` bucket + RLS, `blocks` SELECT/DELETE, the new `users` blocked-profile-view policy, `delete_own_account()`
- Create: `supabase/tests/database/profile_rls.sql` — pgTAP coverage
- Create: `Closet/Closet/Profile/ProfileViewModel.swift`, `Closet/Closet/Profile/ProfileView.swift`
- Modify: `Closet/Closet/MainTabView.swift`, `Closet/Closet/RootView.swift`

---

### Task 1: Backend — profile photos, blocked-list access, account deletion

**Files:**
- Create: `supabase/migrations/20260809000000_profile_photos_and_account_deletion.sql`
- Create: `supabase/tests/database/profile_rls.sql`

**Interfaces:**
- Consumes: `public.users`, `public.blocks` (Phase 7), `public.closet_members` (Phase 2)
- Produces: a `profile-photos` Storage bucket with owner-upload/owner-or-closet-mate-view RLS; `authenticated` can SELECT/DELETE their own `blocks` rows; `authenticated` can SELECT the `users` row of anyone they've blocked; `public.delete_own_account()` RPC — Task 2's `ProfileViewModel` depends on all of these

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260809000000_profile_photos_and_account_deletion.sql`:

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

grant select, delete on public.blocks to authenticated;

create policy "Users can view their own blocks"
  on public.blocks for select
  using (blocker_id = auth.uid());

create policy "Users can remove their own blocks"
  on public.blocks for delete
  using (blocker_id = auth.uid());

create policy "Users can view profiles of people they've blocked"
  on public.users for select
  using (
    exists (select 1 from public.blocks where blocker_id = auth.uid() and blocked_id = users.id)
  );

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

- [ ] **Step 2: Write the pgTAP test**

Create `supabase/tests/database/profile_rls.sql`:

```sql
begin;
select plan(9);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com');

insert into public.users (id, name) values
  ('11111111-1111-1111-1111-111111111111', 'Alice'),
  ('22222222-2222-2222-2222-222222222222', 'Bob');

-- Alice and Bob share no closet at the point the blocked-profile-view
-- policy is tested below, isolating it from the pre-existing closet-mates
-- policy. This closet/membership fixture is only for the delete_own_account
-- cascade checks near the end of this file, and must be inserted now, as
-- the superuser session role — public.closets/closet_members were never
-- granted direct INSERT to authenticated (Phase 2 routes closet
-- creation/joining only through the create_closet()/
-- join_closet_by_invite_code() SECURITY DEFINER RPCs), so this would fail
-- with "permission denied for table closets" if attempted after switching
-- to authenticated below.
insert into public.closets (id, name, invite_code, created_by)
values ('33333333-3333-3333-3333-333333333333', 'Alice''s Closet', 'testcode', '11111111-1111-1111-1111-111111111111');

insert into public.closet_members (user_id, closet_id)
values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

insert into public.blocks (blocker_id, blocked_id)
values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');

select is(
  (select count(*)::int from public.blocks where blocker_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'Alice can see her own block via the blocks SELECT policy'
);

select is(
  (select name from public.users where id = '22222222-2222-2222-2222-222222222222'),
  'Bob',
  'Alice can see Bob''s name because she has blocked him, even with no shared closet'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.blocks where blocker_id = '11111111-1111-1111-1111-111111111111'),
  0,
  'Bob cannot see Alice''s block of him (blocks SELECT is blocker-only)'
);

select is(
  (select count(*)::int from public.users where id = '11111111-1111-1111-1111-111111111111'),
  0,
  'Bob cannot see Alice''s name (Alice has not blocked Bob, and they share no closet)'
);

delete from public.blocks
where blocker_id = '11111111-1111-1111-1111-111111111111' and blocked_id = '22222222-2222-2222-2222-222222222222';

-- Bob's own "Users can view their own blocks" policy (blocker_id =
-- auth.uid()) would hide Alice's row from him regardless of whether his
-- delete attempt actually succeeded — Bob is never the blocker on this row,
-- so a count from his vantage point is always 0 and can't distinguish "row
-- still there, hidden from Bob" from "row deleted." Verify from a vantage
-- point that can actually see it, same pattern already used below for the
-- delete_own_account() checks.
reset role;

select is(
  (select count(*)::int from public.blocks where blocker_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'Bob''s delete attempt does not remove Alice''s block (blocks DELETE is blocker-only)'
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

delete from public.blocks
where blocker_id = '11111111-1111-1111-1111-111111111111' and blocked_id = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.blocks where blocker_id = '11111111-1111-1111-1111-111111111111'),
  0,
  'Alice can remove her own block'
);

-- Items for the delete_own_account() cascade checks below. items has its
-- own INSERT policy scoped to owner_id = auth.uid() (Phase 3), so these
-- work fine directly under authenticated, unlike closets/closet_members
-- above.
insert into public.items (id, owner_id, category)
values ('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'Top');

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

insert into public.items (id, owner_id, category)
values ('66666666-6666-6666-6666-666666666666', '22222222-2222-2222-2222-222222222222', 'Bottom');

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select public.delete_own_account();

reset role;

select is(
  (select count(*)::int from public.users where id = '11111111-1111-1111-1111-111111111111'),
  0,
  'delete_own_account removes Alice''s public.users row'
);

select is(
  (select count(*)::int from public.items where id = '44444444-4444-4444-4444-444444444444'),
  0,
  'delete_own_account cascades to Alice''s items'
);

select is(
  (select count(*)::int from public.items where id = '66666666-6666-6666-6666-666666666666'),
  1,
  'delete_own_account does not touch Bob''s data'
);

select * from finish();
rollback;
```

- [ ] **Step 3: Apply locally and run the tests**

Run: `supabase db reset` (if this errors, run `supabase start` first — requires Docker)
Expected: all migrations apply cleanly, including the new one

Run: `supabase test db`
Expected: `9 tests passed, 0 failed` for `profile_rls.sql` (plus all previously-passing tests in the other files unaffected)

- [ ] **Step 4: Push to the hosted project**

Run: `supabase db push`
Expected: `Applying migration 20260809000000_profile_photos_and_account_deletion.sql...` then success

Run: `supabase migration list`
Expected: the new migration's `local` and `remote` columns both show `20260809000000`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260809000000_profile_photos_and_account_deletion.sql supabase/tests/database/profile_rls.sql
git commit -m "Add profile-photos bucket, blocked-list access, and account deletion"
```

---

### Task 2: Client — Profile screen

**Files:**
- Create: `Closet/Closet/Profile/ProfileViewModel.swift`
- Create: `Closet/Closet/Profile/ProfileView.swift`
- Modify: `Closet/Closet/MainTabView.swift`
- Modify: `Closet/Closet/RootView.swift`

**Interfaces:**
- Consumes: `profile-photos` bucket RLS, `blocks` SELECT/DELETE, `delete_own_account()` (Task 1), `ImageCompressor` (Phase 3), `AuthViewModel.signOut()` (Phase 1)
- Produces: a working Profile tab reachable from `MainTabView`; a working sign-out and delete-account flow reachable from `RootView` down

- [ ] **Step 1: Write the view model**

Create `Closet/Closet/Profile/ProfileViewModel.swift`:

```swift
import Foundation
import PostgREST
import Storage
import Supabase
import UIKit

struct BlockedUser: Identifiable {
    let id: UUID
    let name: String
}

@Observable
final class ProfileViewModel {
    var name: String = ""
    var topSize: String = ""
    var bottomSize: String = ""
    var shoeSize: String = ""
    var photoPath: String?
    var signedPhotoURL: URL?
    var blockedUsers: [BlockedUser] = []
    var isLoading = true
    var isSaving = false
    var isUploadingPhoto = false
    var errorMessage: String?

    private let client = SupabaseService.shared

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
        await loadBlockedUsers()
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

    private func loadSignedPhotoURL(path: String) async {
        signedPhotoURL = try? await client.storage.from("profile-photos").createSignedURL(
            path: path,
            expiresIn: 3600,
            transform: TransformOptions(width: 200, height: 200, resize: .cover)
        )
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

    func deleteAccount() async -> Bool {
        do {
            try await client.rpc("delete_own_account").execute()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
```

- [ ] **Step 2: Write the view**

Create `Closet/Closet/Profile/ProfileView.swift`:

```swift
import PhotosUI
import SwiftUI

struct ProfileView: View {
    @State private var viewModel = ProfileViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingDeleteConfirmation = false
    let userID: UUID
    let onSignedOut: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            AsyncImage(url: viewModel.signedPhotoURL) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())

                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Text(viewModel.isUploadingPhoto ? "Uploading..." : "Change Photo")
                            }
                            .disabled(viewModel.isUploadingPhoto)
                            .onChange(of: selectedPhoto) { _, newValue in
                                Task { await loadAndUploadPhoto(newValue) }
                            }
                        }
                        Spacer()
                    }
                }

                Section("Your name") {
                    TextField("Name", text: $viewModel.name)
                }

                Section("Your usual sizes") {
                    TextField("Top", text: $viewModel.topSize)
                    TextField("Bottom", text: $viewModel.bottomSize)
                    TextField("Shoe", text: $viewModel.shoeSize)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button(viewModel.isSaving ? "Saving..." : "Save") {
                        Task { await viewModel.save(userID: userID) }
                    }
                    .disabled(viewModel.isSaving)
                }

                Section("Blocked Users") {
                    if viewModel.blockedUsers.isEmpty {
                        Text("No blocked users").foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.blockedUsers) { blockedUser in
                            HStack {
                                Text(blockedUser.name)
                                Spacer()
                                Button("Unblock") {
                                    Task { await viewModel.unblock(blockedID: blockedUser.id, blockerID: userID) }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Sign Out") {
                        Task { await onSignedOut() }
                    }
                }

                Section {
                    Button("Delete Account", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                await viewModel.load(userID: userID)
            }
            .confirmationDialog(
                "Delete your account? This cannot be undone.",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task {
                        if await viewModel.deleteAccount() {
                            await onSignedOut()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func loadAndUploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await viewModel.uploadPhoto(image, userID: userID)
    }
}
```

- [ ] **Step 3: Wire Profile into the tab bar, and thread onSignedOut through**

Full new file content for `Closet/Closet/MainTabView.swift`:

```swift
import SwiftUI

struct MainTabView: View {
    let userID: UUID
    let onSignedOut: () async -> Void

    var body: some View {
        TabView {
            ClosetsListView(userID: userID)
                .tabItem { Label("Closets", systemImage: "door.left.hand.open") }
            MyClothesView(userID: userID)
                .tabItem { Label("My Clothes", systemImage: "tshirt") }
            ProfileView(userID: userID, onSignedOut: onSignedOut)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}
```

Full new file content for `Closet/Closet/RootView.swift`:

```swift
import SwiftUI
import PostgREST
import Supabase

struct RootView: View {
    let authViewModel: AuthViewModel
    @State private var hasProfile: Bool?

    var body: some View {
        Group {
            if authViewModel.isLoading {
                ProgressView()
            } else if authViewModel.session == nil {
                SignInView(authViewModel: authViewModel)
            } else if let userID = authViewModel.session?.user.id {
                if hasProfile == nil {
                    ProgressView().task { await checkProfile(userID: userID) }
                } else if hasProfile == true {
                    MainTabView(userID: userID, onSignedOut: {
                        hasProfile = nil
                        try? await authViewModel.signOut()
                    })
                } else {
                    OnboardingView(userID: userID) {
                        hasProfile = true
                    }
                }
            }
        }
    }

    private func checkProfile(userID: UUID) async {
        do {
            let count = try await SupabaseService.shared
                .from("users")
                .select("id", head: true, count: .exact)
                .eq("id", value: userID)
                .execute()
                .count ?? 0
            hasProfile = count > 0
        } catch {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await checkProfile(userID: userID)
        }
    }
}
```

Note: `hasProfile = nil` is reset **before** `signOut()` is awaited — this closes the staleness gap described in the design doc (§5): whichever user signs in next, on this device, always gets a fresh profile check rather than inheriting the previous session's cached result.

- [ ] **Step 4: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manually verify the full Profile flow**

On a device or Simulator:

1. Open the Profile tab — confirm your current name and sizes are pre-filled (not blank), matching what Onboarding originally saved.
2. Change your name or a size field, tap Save — confirm no error, then relaunch the app (or navigate away and back) and confirm the change persisted.
3. Tap "Change Photo," pick an image — confirm it uploads and displays in the circular avatar. Relaunch the app and confirm the photo still shows (persisted, not just cached in memory).
4. If you have a blocked user (from Phase 7 testing), confirm they appear in "Blocked Users" with their real name — including if you no longer share a Closet with them. Tap "Unblock" — confirm they disappear from the list, and (if you can check from their account or the Supabase dashboard) confirm their items become visible to you again in any Closet you both belong to.
5. Tap "Sign Out" — confirm you're returned to the sign-in screen immediately, no confirmation prompt.
6. Sign back in as the same user — confirm you land back in the app normally (not sent through Onboarding again).
7. On a disposable test account you don't need: tap "Delete Account," confirm the dialog, confirm — confirm you're returned to the sign-in screen, and confirm (via the Supabase dashboard, or by trying to sign in again with that Apple ID) that the account and all its data are actually gone.

- [ ] **Step 6: Commit**

```bash
git add Closet/Closet/Profile/ProfileViewModel.swift Closet/Closet/Profile/ProfileView.swift Closet/Closet/MainTabView.swift Closet/Closet/RootView.swift
git commit -m "Add Profile screen: edit profile, photo upload, blocked list, sign out, delete account"
```

---

## Roadmap: Later Phases (not yet planned in detail)

- **Design pass:** all eight roadmap phases are now functionally complete. This is the point the project deferred real visual design to (product decision, 2026-08-06) — the Retro-inspired dark/photo-forward look across the whole app, replacing the plain default SwiftUI styling used throughout Phases 4-8.
- **Known deferred gaps, still open:** the Phase 6 orphaned-share issue (sharing into a Closet you've since left is invisible/unrevocable) remains unfixed — confirmed out of scope for this phase too.
