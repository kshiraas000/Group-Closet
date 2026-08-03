# Closet — Design Spec

**Date:** 2026-08-02
**Status:** Approved design, pre-implementation

## 1. Product Definition & MVP Scope

**One-liner:** Closet — make your friend group's wardrobes as browsable as your own camera roll. You create a Closet, invite your friends, and everyone adds clothes they're happy to lend. Finding "a black dress, size S, for formal" takes five seconds instead of a scroll through hundreds of shared-album photos.

**Ambition:** Startup seed — architected so any friend group can sign up and self-organize (real auth, invite links that work for anyone, App Store review readiness), not just a personal tool for one friend group.

**Beachhead user:** College women, ~18–24, in tight friend groups (roommates, close friends). Frequent sharing for going out, formals, themed events. Visual, aesthetic-driven, high standard for app polish.

**What beats a shared Apple Photos album (the only three things that matter):**
1. Ownership is always visible on every item
2. Everything is filterable and searchable
3. Each person has a real closet, not a photo pile

**In the MVP:**
- Sign in with Apple → profile: first name, photo, usual sizes per category (powers size auto-fill and the size filter)
- Create a Closet, join via invite link (shared over iMessage/etc — no username search, no friend graph)
- Add items from inside a Closet: camera-roll multi-select or in-app camera → one required tap per item (category) → optional "also share to" other Closets → item lands in the Closet and in **My Clothes** automatically
- Closet view: edge-to-edge grid, newest first, filter chips (category · person · size · color · occasion) + text search
- Item detail view: full-screen, Retro-style (see Section 3.4)
- My Clothes: everything you've added, across all Closets; manage which Closets see each item
- Report item / Block user / Leave Closet

**Explicitly out of scope for v1:**
- Borrowing logistics, availability tracking, calendars, messaging, payments, AI features
- Comments, likes/reactions
- Push notifications
- Multiple photos per item (schema supports it; UI doesn't expose it — see Section 2)
- Outfit tagging
- Android, web
- Admin/moderator roles within a Closet (see Section 2 — no member has special privileges)
- Kicking a member out of a Closet (Block covers "I don't want to see this person's stuff"; leaving is self-service only)

## 2. Data Model

**Entities:**

- **User** — `id, name, photo_url, sizes (jsonb, e.g. {top: "M", bottom: "6", shoe: "8"})`
- **Closet** — `id, name, invite_code, created_by, created_at`
- **ClosetMember** — `user_id, closet_id, joined_at`. **Unique on (user_id, closet_id).** No `role` column — no member has special privileges over another. Any member can share the invite link; any member can regenerate it (invalidating the old one). `Closet.created_by` is provenance only, not a permissions flag.
- **Item** — `id, owner_id, category (enum: Top/Bottom/Dress/Outerwear/Shoes/Accessory), size, color, occasion_tags (array), caption, created_at`
- **ItemPhoto** — `id, item_id, photo_url, position, created_at`. One-to-many so a future "add more photos" feature is additive (new UI, no migration). **MVP only ever inserts one row per item** (position 0); no "add more photos" UI, no reordering UI in v1.
- **ItemShare** — `item_id, closet_id`. **Unique on (item_id, closet_id).** An Item belongs to exactly one owner but fans out to many Closets via ItemShare — this is how "add to one Closet, also share to others" and "My Clothes shows everything regardless of Closet" both work without duplicating photos or data.
- **Report** — `id, item_id (nullable), reported_user_id (nullable), reporter_id, reason, created_at`
- **Block** — `blocker_id, blocked_id, created_at`

**Privacy boundary (Supabase Row-Level Security):** a user can see an Item only if there's an ItemShare row linking it to a Closet they're a ClosetMember of, or if they're the owner. Enforced at the database level, not just in app UI — this is the actual security boundary.

## 3. Screens & Flows

**Onboarding:**
1. Sign in with Apple
2. Name, photo, sizes per category (all optional except name)
3. Land on Closets tab: invite-link deep link → straight into joining that Closet; otherwise empty state = "Create a Closet" or "Have an invite link? Paste it"

**Tab bar:** Closets · My Clothes · Profile

**3.1 Closets tab**
- List of your Closets (name, member avatars, item count) → tap into one
- "+" → Create Closet (name it) → generates a shareable invite link (share sheet) → any member can later re-share or regenerate it
- Inside a Closet: grid + filter chips (category · person · size · color · occasion) + search, "+" to add items, members icon (see who's in it, leave Closet)

**3.2 Add item flow** (entered from inside a specific Closet)
1. Tap "+" → Camera or Photo Library (multi-select, up to ~20)
2. Fast swipe-through: one required tap per photo (category); size auto-fills from profile default for that category, editable; color/occasion/caption optional, collapsed by default
3. "Also share to:" checkboxes for other Closets you're in (none pre-checked — current Closet is already implied)
4. Save → item appears in this Closet's grid and in My Clothes immediately

**3.3 My Clothes tab**
- Same grid + filter UI, scoped to items you own, across all Closets
- Tap an item → detail view, with a "Shared to:" list to toggle which Closets see it

**3.4 Item detail view** (Retro-inspired, dark/photo-forward, minimal chrome)
- Top bar: owner avatar + name (bold) · muted subtitle = category · "X of Y" counter (position within the current filtered/sorted set) · X to close
- Full-bleed photo
- Below photo: caption (bold, if present) · muted secondary line with size/color/occasion chips
- No like icon, no tagged-friends avatars, no location — cut from the reference design per product decision
- Bottom-right "..." menu: Report (everyone) or Edit/Delete (owner only)
- Navigation: tap right third of photo → next item in the current filtered/sorted set; tap left third → previous item. The counter reflects this — it's scoped to whatever set you opened the item from (e.g. a filtered "Dresses, size S" view), not the whole unfiltered Closet.

**3.5 Profile tab**
- Name, photo, sizes (editable) · Blocked users list · Leave/manage Closets · Sign out · Delete account (required by App Store guidelines)

**3.6 Report / Block**
- Report item or user → reason picker sheet → submits to Report table, toast confirmation, no in-app moderation UI beyond that
- Block user → mutually hides items between blocker and blocked, everywhere, immediately (existing items, not just future ones) · reachable from item detail or profile

## 4. Technical Architecture

**Client:** Native iOS, SwiftUI, iOS 17+ target. `NavigationStack` + `@Observable` view models — no heavier architecture (Redux-style/TCA) needed at this scope. Native chosen over cross-platform for performance and gesture feel (fast swipe-through tagging, smooth grid scrolling, tap-navigation in the detail view).

**Backend:** Supabase
- **Postgres** for the Section 2 schema, Row-Level Security as the real privacy boundary
- **Supabase Auth** — Sign in with Apple (required by App Store guidelines whenever another third-party sign-in is offered; also the best fit for this audience — no password, no email friction)
- **Supabase Storage** — private bucket for item photos; signed URLs generated only for photos the requesting user can see, scoped the same way RLS scopes rows
- **Supabase Realtime** — not used in v1. New items appear on pull-to-refresh / tab reopen. Deferred to avoid subscription-lifecycle complexity that isn't core to the value prop yet.

**Image handling:** Client-side downscale/compress before upload (target ~1–2MB, long edge ~1600px). Grid thumbnails via Supabase Storage's on-the-fly image transformation (resize param in the URL) rather than generating/storing separate thumbnail files.

**Invite links:** Universal Links (`https://<domain>/invite/{code}`) — deep-link into the app if installed, fall back to an App Store landing page if not. Requires a small companion web page + `apple-app-site-association` file, outside the iOS app itself.

**Push notifications:** Not in v1 (matches the Section 1 cut). Noting only that APNs setup is its own entitlement/certificate work whenever it's added later — not a blocker now.

## 5. Edge Cases & Error Handling

**Edge cases:**
- Member leaves a Closet / deletes account: their items disappear from that Closet (ItemShare cascade), but the Items and other ItemShares survive — leaving one Closet doesn't remove your closet everywhere. Full account deletion cascades everything.
- Last member leaves a Closet: Closet stays intact (in case someone rejoins via the link), no auto-delete.
- Invite links don't expire and aren't single-use — match how group texts already work. Any member can regenerate the link, invalidating the old one, as the only revocation mechanism (no per-invite tracking in v1).
- Blocked user's existing items are hidden immediately, not just future ones. Mutual.
- Duplicate photo selection across sessions: no dedup, creates two Items — not worth detecting.

**Error handling:**
- Upload failures: per-photo retry, not all-or-nothing (a batch of 15 where photo 12 fails shouldn't lose 1–11)
- RLS denial (e.g. viewing something you've lost access to) surfaces as generic "not found," never a permission error — avoids leaking existence of content someone can't see
- Offline: read-only cached grid, clear "you're offline" state for any write action — no offline queue/sync in v1

## 6. Testing Approach

UI-and-data-flow heavy rather than algorithm-heavy. Priorities:
- RLS policy tests at the Supabase level — this is the actual privacy boundary and needs real coverage, not just app-level trust
- Manual/exploratory QA for SwiftUI flows over heavy unit/snapshot testing at this stage
- No formal TDD process proposed for the UI layer given MVP scope
