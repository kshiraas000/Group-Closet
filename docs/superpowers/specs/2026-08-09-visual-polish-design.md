# Visual Polish Pass — Design Spec

**Date:** 2026-08-09
**Status:** Approved design, pre-implementation

## 1. Why Now

All 8 roadmap phases are functionally complete on `main`. Per the standing decision from 2026-08-06, real visual design was deliberately deferred until this point rather than done per-phase, to avoid redesigning screens whose interactions weren't finished yet. Every screen currently uses plain default SwiftUI styling (system colors, system fonts, standard `List`/`Form` chrome). This spec is a **restyle only** — no new features, no changed data flow, no backend changes. Every screen keeps the exact behavior it has today; only appearance changes.

Trigger: the user found the app hard to actually use/evaluate on Simulator in its current unstyled state.

## 2. Source Material

Explored via three rounds of mockups in a Claude Design project ("Group Closet"), file `Closet Redesign Options.dc.html`, comparing color/type directions (Ink & Sage, Clay, Night Album) crossed with grid/caption treatments (Album, Refined Native, Boutique). The approved direction combines:
- **2a "Ink & Sage"** for the color and type system
- **1a "Album"**'s bare-photo-tile grid treatment (no caption on the grid — captions only appear once you open an item)
- A custom top bar / filter layout (not shown in any single mockup option), designed for closets with as many as ~20 members while keeping the common 3-7 person case a single tap

## 3. Visual Language

**Color:**
| Token | Hex | Use |
|---|---|---|
| Background | `#F7F6F1` | Screen backgrounds |
| Primary text | `#232823` | Headlines, primary content |
| Secondary text | `#6D7370` | Metadata, captions-of-captions |
| Tertiary text | `#8B918C` | Placeholder-weight text, disabled state |
| Accent (sage) | `#4A5D4E` | Active filter/tab state, primary buttons, links, selected chip |
| Divider | `rgba(35,40,35,.08)` | Hairline rules |
| Destructive | System red (unchanged) | Delete/Report/Block — matches iOS convention, not part of the palette above |

**Typography:**
- Headlines and item captions: **Lora** (serif) — bundled as `.ttf` files in the app target, registered via `Info.plist` (`UIAppFonts`). Weight 500 for headlines, 500 for captions.
- Everything else (labels, buttons, chips, filter sheet, form fields, tab bar): **DM Sans** — also bundled, weights 400/500/700 as needed.
- Both fonts accessed through `Font.custom("Lora", size:)` / `Font.custom("DM Sans", size:)` wrapped in a couple of small helpers (see §5) rather than called ad hoc — this keeps a later type-scale tweak to one file.

**Shape:** grid tile and card corner radius `4pt`; buttons and chips fully rounded (`Capsule`); photo containers in Item Detail `6pt` corner radius.

## 4. Shared Infrastructure

New file `Closet/Closet/DesignSystem/Theme.swift`: a small enum/namespace exposing the color tokens (as `Color` statics) and two font helpers (`Theme.Font.headline(_:)` for Lora, `Theme.Font.body(_:)` for DM Sans, both wrapping `Font.custom` with a fallback if the named font ever fails to register). No abstraction beyond this — colors and font wrappers only, not a full component library, since most screens need just a handful of shared primitives:

- `OwnerBadge` — small circular avatar (profile photo if set, else initial-in-a-circle), used on grid tiles and in Item Detail's top bar.
- `CategoryChipsRow` — horizontal scroll of category chips + trailing "Filter ▾" chip.
- `FilterSheet` — the Owner/Size/Color/Occasion sheet (see §6).

These three live in `Closet/Closet/DesignSystem/` alongside `Theme.swift` since Closet Detail and My Clothes both need the badge and (Closet Detail only) the chips row and filter sheet.

Font files: Lora and DM Sans variable/static `.ttf`s added under `Closet/Closet/Resources/Fonts/`, registered in `Info.plist`.

## 5. Screen-by-Screen Changes

### 5.1 Closet Detail (`ClosetDetailView.swift`) — the biggest change

Today: a single `List` with a Members section, an Items section (filter-chip row of 5 `Menu` dropdowns — Category/Person/Size/Color/Occasion — then an adaptive `LazyVGrid`), a Share-Invite row, and Leave Closet.

New layout:
- Search field, then `CategoryChipsRow` (All + the 6 `ItemCategory` values, horizontally scrollable, trailing "Filter ▾" chip), replacing the current 5-`Menu` row.
- Tapping "Filter ▾" opens a sheet (`FilterSheet`) with four sections — **Owner** (single-select radio list: "Everyone" + one row per closet member, sourced from `viewModel.members` exactly as today's Person menu was), **Size**, **Color**, **Occasion** (single-select radio lists, sourced from the existing `availableSizes`/`availableColors`/`availableOccasions`). No filtering logic changes — `BrowseFilters` and `BrowseFiltering` are untouched; this is purely relocating the same five filters from inline menus into one sheet, matching the mockup's explicit reasoning (five always-visible dropdowns doesn't scale past a handful of members, but most closets only ever need Category quickly).
- Grid: 3-up (`GridItem(.flexible())` × 3, not the current `.adaptive(minimum: 110)`), `3:4` aspect ratio tiles, bare photo, no caption/owner-size line underneath. Each tile gets an `OwnerBadge` overlaid bottom-left.
- Members list and Share Invite / Leave Closet rows keep their current position and behavior, restyled to the theme (bone background, sage accent, DM Sans).

### 5.2 Item Detail (`ItemDetailView.swift`)

Today this is the one screen with deliberate (if minimal) design: full black background, `.preferredColorScheme(.dark)`, white-on-black chrome. This is the one place the visual direction actually changes in kind, not just in polish: it moves to the same bone/Ink & Sage language as the rest of the app (background `#F7F6F1`, no forced dark color scheme) rather than staying black, so the whole app reads as one consistent identity instead of one dark screen surrounded by light ones.

- Top bar: `OwnerBadge` + owner name (DM Sans, bold) + muted category subtitle, "✕" to dismiss, position counter ("3 of 12") — same content as today, restyled.
- Photo area: unchanged behavior (tap left/right thirds to page, `scaledToFit`), corner radius `6pt`, sage-tinted placeholder while loading.
- Below the photo: caption in Lora (this becomes the *only* place a caption is shown anywhere in the app), then the existing size/color/occasion tag line in muted DM Sans.
- Existing owner-only "Shared to" interactive toggle list is kept exactly as-is functionally, restyled — visible only to owners, same as today. Non-owners see nothing about sharing here, matching current behavior; a "Shared to N closets" summary for non-owners was in the original mockup but is deliberately dropped — computing it accurately would need a non-owner-visible share count, which risks the same class of RLS-undercounting bug flagged in Phase 7's technical debt notes (item_shares rows outside a closet the viewer belongs to are invisible to them), and it's a new feature, not a restyle.
- "•••" menu (Report/Block for non-owners, disabled Edit/Delete for owners) — unchanged behavior, restyled icon/menu appearance only.

### 5.3 My Clothes (`MyClothesView.swift`)

Same `CategoryChipsRow` + `FilterSheet` pattern as Closet Detail, minus the Owner section (every item is already yours — no `ownerID` filter exists here today either). Grid: same 3-up bare-tile treatment as Closet Detail, but **no** `OwnerBadge` (redundant when every tile is yours).

### 5.4 Closets List (`ClosetsListView.swift`)

Restyle only: closet rows get the theme's typography (closet name in Lora) instead of a bare `List` of plain text rows. `ClosetsViewModel` currently loads only `id`/`name`/`inviteCode`/`createdBy`/`createdAt` — no member list or item count — so the mockup's "Maya, Priya & Jules · 34 pieces" subtitle is **not** included here; adding it would mean a new per-closet query (member names + item count), which is a data/feature change, not a restyle. Deferred, not silently dropped: worth a future small enhancement once someone wants it, but out of scope for this pass.

### 5.5 Add Item flow, Onboarding, Sign In, Create/Join Closet, Profile

Restyle only — background, typography, buttons, chips, form fields all pull from `Theme`, no behavior changes:
- `AddItemView` / `PhotoTaggingView` / `ShareToClosetsView` — category-selection chips restyled to match `CategoryChipsRow`'s chip look (not the shared component itself, since these are single-select-during-tagging rather than a filter); form fields and buttons restyled.
- `OnboardingView`, `SignInView`, `CreateClosetView`, `JoinClosetView` — restyled to theme; no layout restructuring beyond what's needed to fit the new type scale.
- `ProfileView` — restyled `Form` (background, typography, buttons); the `isLoading`/`hasLoadedProfile` gating from Phase 8 is unchanged.

### 5.6 Tab Bar (`MainTabView.swift`)

Tab bar background bone, active tab tinted sage, inactive tabs muted — SwiftUI's standard `.tint()`/appearance APIs, no custom tab bar view.

## 6. Filter Sheet Detail

```
Owner
○ Everyone
○ Maya
○ Priya
○ Jules
...

Size
○ Any
○ S
○ M
...

Color
○ Any
...

Occasion
○ Any
...
```

Single-select per section (radio-style, matching today's single-select `Menu` behavior — you could only pick one size/color/etc. at a time before, and that doesn't change). Presented as a `.sheet` from the "Filter ▾" chip. A section is omitted entirely if its options list is empty (matching today's `if !viewModel.availableSizes.isEmpty` guards).

## 7. Explicitly Out of Scope

- No new features, no changed filtering semantics, no new queries or RLS changes — this is a client-side, presentation-only pass.
- No multi-select filters (e.g., picking two sizes at once) — out of scope, matches current single-select behavior.
- No animation/transition polish beyond what SwiftUI gives you for free (sheet presentation, tab switching) — not part of this pass.
- No changes to `ItemDetailViewModel`, `ClosetDetailViewModel`, `MyClothesViewModel`, `BrowseFiltering`, or any Supabase query — verified screen-by-screen above.
- Dark mode / `.preferredColorScheme` handling beyond removing Item Detail's forced dark mode — the app does not attempt to separately support system dark mode in this pass (out of scope; today's app doesn't either).

## 8. Testing Approach

No backend changes, so no pgTAP coverage needed. This is implement → verify build → manual QA per screen, same approach Phase 8's client-only task used. Given the number of screens touched, manual QA should cover: Closets List, Closet Detail (grid, search, category chips, Filter sheet — all four sections), My Clothes, Item Detail (paging, caption display, Shared-to list, Report/Block menu), Add Item flow (all three steps), Profile, Onboarding, Sign In, tab bar appearance in both active/inactive states.

## 9. Global Constraints

- iOS 17.0 minimum deployment target, unchanged.
- No new dependencies beyond the two bundled font families.
- Every existing view model, query, and RLS policy is unchanged — this spec only touches SwiftUI `View` files (plus two new small shared view files and one theme file).
- Match existing project convention: `@Observable` view models untouched; views stay in their current per-feature folders; the three new shared components go in a new `Closet/Closet/DesignSystem/` folder.
