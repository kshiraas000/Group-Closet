# Phase 2: Closets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a signed-in, onboarded user create a Closet, join one via invite code, see who's in a Closet, and leave one — the group-membership layer that Phase 3 (Add Item) and Phase 4 (Browse) build on top of.

**Architecture:** Two new Postgres `SECURITY DEFINER` RPC functions (`create_closet`, `join_closet_by_invite_code`) are the only way rows ever get inserted into `closets`/`closet_members` — this keeps the invite code as the sole access-control secret (per spec §4/§5) instead of relying on client-guessable UUIDs plus an RLS insert policy. Everything else (viewing your Closets, viewing members, leaving) goes through ordinary RLS-scoped `SELECT`/`DELETE` like Phase 1's `users` table did. Client-side: one `@Observable` view model + one `View` per screen, matching the `AuthViewModel`/`SignInView` and `OnboardingViewModel`/`OnboardingView` pattern already in the codebase.

**Tech Stack:** SwiftUI, `@Observable`, `NavigationStack`, supabase-swift (`Supabase` + `PostgREST` modules — both needed, see below), pgTAP.

## Global Constraints

- iOS 17.0 minimum deployment target (unchanged from Phase 1)
- SwiftUI with `NavigationStack` + `@Observable` view models — no Redux/TCA
- Use `SupabaseService.shared` directly (it *is* the `SupabaseClient`) — not `SupabaseService.shared.client`. Any file calling `.from(...)`, `.insert(...)`, `.rpc(...)`, or `.execute()` needs both `import Supabase` and `import PostgREST` (confirmed by the Phase 1 build: `Supabase` alone does not expose these — this bit Task 6/7 last time and cost a debugging round, see `Closet/Closet/Auth/AuthViewModel.swift` for the working import list of the `Supabase`-only case vs. `Closet/Closet/Onboarding/OnboardingViewModel.swift` for the case needing both)
- Row-Level Security is the real privacy boundary (spec §2) — every new table access path below is enforced in Postgres, not just checked in the app
- Invite codes are the **only** access-control secret for joining a Closet in v1 (spec §4, §5: "Invite links don't expire and aren't single-use... Any member can regenerate the link... as the only revocation mechanism"). Consequently: **no RLS `INSERT` policy on `closets` or `closet_members` for the `authenticated` role.** All creation/joining happens inside the two `SECURITY DEFINER` functions, which are the only code paths allowed to write those tables. Do not add a direct-insert policy as a "convenience" — it would let any authenticated user self-join any Closet by UUID without ever knowing its invite code.
- Full Universal Links deep-linking (`https://<domain>/invite/{code}`) is explicitly out of scope for this phase — spec §4 calls out that it needs "a small companion web page... outside the iOS app itself." This phase ships manual invite-code paste only (matches the onboarding flow's own fallback: "Have an invite link? Paste it," spec §3).
- No admin/moderator roles within a Closet (spec §1, §2) — every member has identical permissions; there is no "kick a member" feature, only self-service leave.
- Grid/filter/search of Closet *contents* is Phase 4 (Browse); adding items is Phase 3. This phase's Closet detail screen shows only the member list and a Leave button — no items yet, because `items`/`item_shares` have no data until Phase 3.

---

## File Structure

**iOS app** (all new files under `Closet/Closet/Closets/` unless noted):
- `Closet/Closet/Models/Closet.swift` — `Codable` struct matching the `closets` table
- `Closet/Closet/Closets/CreateClosetViewModel.swift` / `CreateClosetView.swift` — name a new Closet, calls `create_closet` RPC
- `Closet/Closet/Closets/JoinClosetViewModel.swift` / `JoinClosetView.swift` — paste an invite code, calls `join_closet_by_invite_code` RPC
- `Closet/Closet/Closets/ClosetDetailViewModel.swift` / `ClosetDetailView.swift` — member list + Leave Closet
- `Closet/Closet/Closets/ClosetsViewModel.swift` / `ClosetsListView.swift` — list of your Closets, empty state, "+" to create, entry point to join
- Modified: `Closet/Closet/MainTabView.swift` (Closets tab hosts `ClosetsListView` instead of a placeholder `Text`), `Closet/Closet/RootView.swift` (needs `userID` in the signed-in+has-profile branch, not just the onboarding branch)

**Supabase backend:**
- `supabase/migrations/20260804000000_closets_rls.sql` — `is_closet_member()` helper, `create_closet()`/`join_closet_by_invite_code()` RPC functions, RLS policies for `closets`/`closet_members`, and the closet-mate visibility policy Phase 1 explicitly deferred to this phase (see Phase 1 plan, Task 4: "multi-user profile visibility for shared closets is added in the Closets phase")
- `supabase/tests/database/closets_rls.sql` — pgTAP coverage

---

### Task 1: RLS Policies + RPC Functions + Tests

**Files:**
- Create: `supabase/migrations/20260804000000_closets_rls.sql`, `supabase/tests/database/closets_rls.sql`

**Interfaces:**
- Consumes: `public.closets`, `public.closet_members`, `public.users` tables (Phase 1, Task 3)
- Produces: `public.create_closet(p_name text) returns public.closets`, `public.join_closet_by_invite_code(p_invite_code text) returns public.closets` — every later task's client code calls these two functions by name and parameter name; RLS policies that make `SELECT`/`DELETE` on `closets`/`closet_members` and cross-member `SELECT` on `users` work automatically

- [x] **Step 1: Write the migration**

Create `supabase/migrations/20260804000000_closets_rls.sql`:

```sql
create or replace function public.is_closet_member(check_closet_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from closet_members
    where closet_id = check_closet_id and user_id = auth.uid()
  );
$$;

grant execute on function public.is_closet_member(uuid) to authenticated;

grant select on public.closets to authenticated;
grant select, delete on public.closet_members to authenticated;

create policy "Members can view their closets"
  on public.closets for select
  using (is_closet_member(id));

create policy "Members can view closet membership"
  on public.closet_members for select
  using (is_closet_member(closet_id));

create policy "Users can leave a closet themselves"
  on public.closet_members for delete
  using (user_id = auth.uid());

create policy "Users can view profiles of closet-mates"
  on public.users for select
  using (
    exists (
      select 1 from public.closet_members cm1
      join public.closet_members cm2 on cm1.closet_id = cm2.closet_id
      where cm1.user_id = auth.uid() and cm2.user_id = users.id
    )
  );

create or replace function public.create_closet(p_name text)
returns public.closets
language plpgsql
security definer
set search_path = public
as $$
declare
  new_closet public.closets;
  new_invite_code text;
begin
  new_invite_code := substr(md5(random()::text || clock_timestamp()::text), 1, 8);

  insert into closets (name, invite_code, created_by)
  values (p_name, new_invite_code, auth.uid())
  returning * into new_closet;

  insert into closet_members (user_id, closet_id)
  values (auth.uid(), new_closet.id);

  return new_closet;
end;
$$;

grant execute on function public.create_closet(text) to authenticated;

create or replace function public.join_closet_by_invite_code(p_invite_code text)
returns public.closets
language plpgsql
security definer
set search_path = public
as $$
declare
  target_closet public.closets;
begin
  select * into target_closet from closets where invite_code = p_invite_code;

  if target_closet.id is null then
    raise exception 'Invalid invite code';
  end if;

  insert into closet_members (user_id, closet_id)
  values (auth.uid(), target_closet.id)
  on conflict (user_id, closet_id) do nothing;

  return target_closet;
end;
$$;

grant execute on function public.join_closet_by_invite_code(text) to authenticated;
```

- [x] **Step 2: Write the pgTAP test**

Create `supabase/tests/database/closets_rls.sql`:

```sql
begin;
select plan(9);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com');

create temporary table captured_invite (code text);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

insert into public.users (id, name) values ('11111111-1111-1111-1111-111111111111', 'Alice');

insert into captured_invite (code)
select (public.create_closet('Roommates')).invite_code;

select is(
  (select count(*)::int from public.closets where created_by = '11111111-1111-1111-1111-111111111111'),
  1,
  'create_closet created a closet row'
);

select is(
  (select count(*)::int from public.closet_members where user_id = '11111111-1111-1111-1111-111111111111'),
  1,
  'Alice was auto-joined as a member'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
insert into public.users (id, name) values ('22222222-2222-2222-2222-222222222222', 'Bob');

select is(
  (select count(*)::int from public.closets),
  0,
  'Bob cannot see Alice''s closet before joining'
);

select is(
  (select count(*)::int from public.users where id = '11111111-1111-1111-1111-111111111111'),
  0,
  'Bob cannot see Alice''s profile before sharing a closet'
);

select throws_ok(
  $$select public.join_closet_by_invite_code('not-a-real-code')$$,
  'P0001',
  'Invalid invite code',
  'Bob cannot join with a bogus invite code'
);

select lives_ok(
  (select format('select public.join_closet_by_invite_code(%L)', (select code from captured_invite))),
  'Bob can join with the real invite code'
);

select is(
  (select count(*)::int from public.closets),
  1,
  'Bob can now see the closet he joined'
);

select is(
  (select name from public.users where id = '11111111-1111-1111-1111-111111111111'),
  'Alice',
  'Bob can now see Alice''s profile (closet-mate visibility)'
);

delete from public.closet_members
where user_id = '22222222-2222-2222-2222-222222222222';

select is(
  (select count(*)::int from public.closets),
  0,
  'Bob no longer sees the closet after leaving'
);

select * from finish();
rollback;
```

- [x] **Step 3: Apply locally and run the tests**

Run: `supabase db reset` (if this errors with a connection failure, run `supabase start` first — requires Docker running)
Expected: both existing migrations plus the new one apply cleanly

Run: `supabase test db`
Expected: `9 tests passed, 0 failed`

- [x] **Step 4: Push to the hosted project**

Run: `supabase db push`
Expected: `Applying migration 20260804000000_closets_rls.sql...` then success

Run: `supabase migration list`
Expected: the new migration's `local` and `remote` columns both show `20260804000000`

- [x] **Step 5: Commit**

```bash
git add supabase/migrations/20260804000000_closets_rls.sql supabase/tests/database/closets_rls.sql
git commit -m "Add closets/closet_members RLS, join/create RPCs, and closet-mate profile visibility"
```

---

### Task 2: Closet Model + Create Closet Screen

**Files:**
- Create: `Closet/Closet/Models/Closet.swift`, `Closet/Closet/Closets/CreateClosetViewModel.swift`, `Closet/Closet/Closets/CreateClosetView.swift`

**Interfaces:**
- Consumes: `public.create_closet(p_name text)` RPC (Task 1)
- Produces: `struct Closet: Codable, Identifiable` with `id, name, inviteCode, createdBy, createdAt` — every later task decodes rows into this type; `CreateClosetView(onCreated: () -> Void)` — Task 6 (Closets List) presents this as a sheet

- [x] **Step 1: Write the Closet model**

Create `Closet/Closet/Models/Closet.swift`:

```swift
import Foundation

struct Closet: Codable, Identifiable {
    let id: UUID
    var name: String
    let inviteCode: String
    let createdBy: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}
```

- [x] **Step 2: Write the create-closet view model**

Create `Closet/Closet/Closets/CreateClosetViewModel.swift`:

```swift
import Foundation
import PostgREST
import Supabase

@Observable
final class CreateClosetViewModel {
    var name: String = ""
    var isSaving = false
    var errorMessage: String?

    private let client = SupabaseService.shared

    func create() async -> Closet? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Name is required"
            return nil
        }
        isSaving = true
        defer { isSaving = false }

        do {
            let closet: Closet = try await client
                .rpc("create_closet", params: ["p_name": name])
                .execute()
                .value
            return closet
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
```

- [x] **Step 3: Write the create-closet view**

Per spec §3.1, creating a Closet must immediately surface a shareable invite (share sheet) — without this the invite code never leaves the device, and Task 3's join flow has nothing to test against. The view has two states: the name form, then (after creation) the invite code with a `ShareLink`.

Create `Closet/Closet/Closets/CreateClosetView.swift`:

```swift
import SwiftUI

struct CreateClosetView: View {
    @State private var viewModel = CreateClosetViewModel()
    @State private var createdCloset: Closet?
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let createdCloset {
                    inviteView(for: createdCloset)
                } else {
                    form
                }
            }
            .navigationTitle(createdCloset == nil ? "New Closet" : "Invite Friends")
            .toolbar {
                if createdCloset == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(viewModel.isSaving ? "Creating..." : "Create") {
                            Task {
                                if let closet = await viewModel.create() {
                                    onCreated()
                                    createdCloset = closet
                                }
                            }
                        }
                        .disabled(viewModel.isSaving)
                    }
                }
            }
        }
    }

    private var form: some View {
        Form {
            TextField("Closet name", text: $viewModel.name)
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
    }

    private func inviteView(for closet: Closet) -> some View {
        VStack(spacing: 16) {
            Text("\(closet.name) is ready")
                .font(.headline)
            Text("Invite code: \(closet.inviteCode)")
                .font(.title2.monospaced())
            ShareLink(item: "Join my Closet \"\(closet.name)\" on the Closet app — invite code: \(closet.inviteCode)")
            Button("Done") { dismiss() }
        }
        .padding()
    }
}
```

- [x] **Step 4: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 5: Commit**

```bash
git add Closet/Closet/Models/Closet.swift Closet/Closet/Closets/CreateClosetViewModel.swift Closet/Closet/Closets/CreateClosetView.swift
git commit -m "Add Closet model and create-closet screen"
```

---

### Task 3: Join Closet Screen

**Files:**
- Create: `Closet/Closet/Closets/JoinClosetViewModel.swift`, `Closet/Closet/Closets/JoinClosetView.swift`

**Interfaces:**
- Consumes: `public.join_closet_by_invite_code(p_invite_code text)` RPC (Task 1), `Closet` (Task 2)
- Produces: `JoinClosetView(onJoined: () -> Void)` — Task 6 presents this as a sheet

- [x] **Step 1: Write the join view model**

Create `Closet/Closet/Closets/JoinClosetViewModel.swift`:

```swift
import Foundation
import PostgREST
import Supabase

@Observable
final class JoinClosetViewModel {
    var inviteCode: String = ""
    var isJoining = false
    var errorMessage: String?

    private let client = SupabaseService.shared

    func join() async -> Closet? {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            errorMessage = "Invite code is required"
            return nil
        }
        isJoining = true
        defer { isJoining = false }

        do {
            let closet: Closet = try await client
                .rpc("join_closet_by_invite_code", params: ["p_invite_code": code])
                .execute()
                .value
            return closet
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
```

- [x] **Step 2: Write the join view**

Create `Closet/Closet/Closets/JoinClosetView.swift`:

```swift
import SwiftUI

struct JoinClosetView: View {
    @State private var viewModel = JoinClosetViewModel()
    @Environment(\.dismiss) private var dismiss
    let onJoined: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Invite code", text: $viewModel.inviteCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Join a Closet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isJoining ? "Joining..." : "Join") {
                        Task {
                            if await viewModel.join() != nil {
                                onJoined()
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isJoining)
                }
            }
        }
    }
}
```

- [x] **Step 3: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 4: Commit**

```bash
git add Closet/Closet/Closets/JoinClosetViewModel.swift Closet/Closet/Closets/JoinClosetView.swift
git commit -m "Add join-closet screen"
```

---

### Task 4: Closet Detail — Members + Leave

**Files:**
- Create: `Closet/Closet/Closets/ClosetDetailViewModel.swift`, `Closet/Closet/Closets/ClosetDetailView.swift`

**Interfaces:**
- Consumes: `Closet` (Task 2), `UserProfile` (Phase 1, Task 5), `public.closet_members` RLS-scoped `SELECT`/`DELETE` (Task 1)
- Produces: `ClosetDetailView(closet: Closet, userID: UUID)` — Task 6 (Closets List) navigates to this from a `NavigationLink`

- [x] **Step 1: Write the detail view model**

Create `Closet/Closet/Closets/ClosetDetailViewModel.swift`:

```swift
import Foundation
import PostgREST
import Supabase

private struct MemberRow: Decodable {
    let users: UserProfile
}

@Observable
final class ClosetDetailViewModel {
    var members: [UserProfile] = []
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    func loadMembers(closetID: UUID) async {
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

    func leave(closetID: UUID, userID: UUID) async -> Bool {
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

- [x] **Step 2: Write the detail view**

Create `Closet/Closet/Closets/ClosetDetailView.swift`:

```swift
import SwiftUI

struct ClosetDetailView: View {
    @State private var viewModel = ClosetDetailViewModel()
    @State private var showingLeaveConfirmation = false
    @Environment(\.dismiss) private var dismiss
    let closet: Closet
    let userID: UUID

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
            Section {
                ShareLink(item: "Join my Closet \"\(closet.name)\" on the Closet app — invite code: \(closet.inviteCode)") {
                    Label("Share Invite", systemImage: "square.and.arrow.up")
                }
            }
            Section {
                Button("Leave Closet", role: .destructive) {
                    showingLeaveConfirmation = true
                }
            }
        }
        .navigationTitle(closet.name)
        .task { await viewModel.loadMembers(closetID: closet.id) }
        .confirmationDialog(
            "Leave \(closet.name)?",
            isPresented: $showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task {
                    if await viewModel.leave(closetID: closet.id, userID: userID) {
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

- [x] **Step 4: Commit**

```bash
git add Closet/Closet/Closets/ClosetDetailViewModel.swift Closet/Closet/Closets/ClosetDetailView.swift
git commit -m "Add closet detail screen with member list and leave action"
```

---

### Task 5: Closets List Screen

**Files:**
- Create: `Closet/Closet/Closets/ClosetsViewModel.swift`, `Closet/Closet/Closets/ClosetsListView.swift`

**Interfaces:**
- Consumes: `Closet` (Task 2), `CreateClosetView` (Task 2), `JoinClosetView` (Task 3), `ClosetDetailView` (Task 4), RLS-scoped `SELECT` on `public.closets` (Task 1)
- Produces: `ClosetsListView(userID: UUID)` — Task 6 hosts this as the Closets tab

- [x] **Step 1: Write the closets list view model**

Create `Closet/Closet/Closets/ClosetsViewModel.swift`:

```swift
import Foundation
import PostgREST
import Supabase

@Observable
final class ClosetsViewModel {
    var closets: [Closet] = []
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    func loadClosets() async {
        isLoading = true
        defer { isLoading = false }
        do {
            closets = try await client
                .from("closets")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [x] **Step 2: Write the closets list view**

Create `Closet/Closet/Closets/ClosetsListView.swift`:

```swift
import SwiftUI

struct ClosetsListView: View {
    @State private var viewModel = ClosetsViewModel()
    @State private var showingCreate = false
    @State private var showingJoin = false
    let userID: UUID

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.closets.isEmpty {
                    emptyState
                } else {
                    List(viewModel.closets) { closet in
                        NavigationLink(closet.name) {
                            ClosetDetailView(closet: closet, userID: userID)
                        }
                    }
                }
            }
            .navigationTitle("Closets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await viewModel.loadClosets() }
            .sheet(isPresented: $showingCreate) {
                CreateClosetView {
                    Task { await viewModel.loadClosets() }
                }
            }
            .sheet(isPresented: $showingJoin) {
                JoinClosetView {
                    Task { await viewModel.loadClosets() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No Closets yet")
                .font(.headline)
            Button("Create a Closet") { showingCreate = true }
            Button("Have an invite link? Paste it") { showingJoin = true }
        }
    }
}
```

- [x] **Step 3: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 4: Commit**

```bash
git add Closet/Closet/Closets/ClosetsViewModel.swift Closet/Closet/Closets/ClosetsListView.swift
git commit -m "Add closets list screen with create/join entry points"
```

---

### Task 6: Wire Into Root Routing

**Files:**
- Modify: `Closet/Closet/MainTabView.swift`, `Closet/Closet/RootView.swift`

**Interfaces:**
- Consumes: `ClosetsListView` (Task 5)
- Produces: `MainTabView(userID: UUID)` — the Closets tab is no longer a placeholder

- [x] **Step 1: Give MainTabView the signed-in user's ID and host the real Closets tab**

Modify `Closet/Closet/MainTabView.swift`:

```swift
import SwiftUI

struct MainTabView: View {
    let userID: UUID

    var body: some View {
        TabView {
            ClosetsListView(userID: userID)
                .tabItem { Label("Closets", systemImage: "door.left.hand.open") }
            Text("My Clothes")
                .tabItem { Label("My Clothes", systemImage: "tshirt") }
            Text("Profile")
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}
```

- [x] **Step 2: Thread userID through to the MainTabView branch**

Modify `Closet/Closet/RootView.swift` — the existing `hasProfile == true` branch calls `MainTabView()` with no arguments; it needs the same `userID` the Onboarding branch already extracts. Restructure so both branches share one `if let userID`:

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
                    MainTabView(userID: userID)
                } else {
                    OnboardingView(userID: userID) {
                        hasProfile = true
                    }
                }
            }
        }
    }

    private func checkProfile(userID: UUID) async {
        let count = (try? await SupabaseService.shared
            .from("users")
            .select("id", head: true, count: .exact)
            .eq("id", value: userID)
            .execute()
            .count) ?? 0
        hasProfile = count > 0
    }
}
```

- [x] **Step 3: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 4: Manually verify the full flow**

On a device or Simulator: sign in → Closets tab shows empty state → "Create a Closet" → name it → invite screen appears showing the code → "Done" → appears in the list → tap in → see yourself listed as the only member, plus a "Share Invite" option. Then, with a second signed-in account, use "Have an invite link? Paste it" with the code from the first account's invite screen (or the "Share Invite" button on its Closet Detail screen) — verify it joins successfully and each account can now see the other's name in the member list. Finally, verify Leave Closet on one account removes it from that account's list without affecting the other's.

- [x] **Step 5: Commit**

```bash
git add Closet/Closet/MainTabView.swift Closet/Closet/RootView.swift
git commit -m "Wire closets list into the Closets tab"
```

---

## Roadmap: Later Phases (not yet planned in detail)

- **Phase 3 — Add Item:** camera/library multi-select, category tagging, share-to-closets, upload to Storage, `items`/`item_photos`/`item_shares` RLS
- **Phase 4 — Browse:** Closet grid, filter chips, search
- **Phase 5 — Item Detail:** Retro-style full-screen view, tap navigation within the filtered set
- **Phase 6 — My Clothes:** cross-closet item management, per-item share toggles
- **Phase 7 — Report & Block:** reason picker, mutual hide, `reports`/`blocks` RLS
- **Phase 8 — Profile:** edit profile, blocked list, delete account
