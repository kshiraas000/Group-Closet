# App Store Connect metadata

Drafted from what the code actually does. Character limits noted; App Store
Connect enforces them.

---

## Listing

**App Name** (30) — `Group Closet`

**Subtitle** (30) — `Share one closet with friends` (29)

Alternatives: `The closet you share` (20) · `One closet, shared` (18)

**Primary category** — Lifestyle
**Secondary category** — Shopping

Lifestyle fits the "wardrobe you share with your people" framing better than
Shopping, which skews commerce. Nothing is bought or sold in the app.

---

## Promotional text (170)

Editable without a new build — use it for seasonal hooks later.

> Start the closet you keep borrowing from anyway. Add what you own, invite the
> people you actually swap clothes with, and see everything in one place.

(163)

---

## Description (4000)

> **One closet, shared between you.**
>
> You already borrow from your roommate, your sister, your best friend. Group
> Closet is where that actually lives — one shared wardrobe everyone can see,
> instead of a group chat full of "can I borrow that top?"
>
> **Add a piece in seconds**
> Take a photo or pick one from your library, name it, and tag the category,
> size and colour. Add several at once and tag them in one pass.
>
> **Invite with a code**
> Every closet has a short invite code. Share it once — no accounts to look up,
> no requests to approve, no one hunting for a username.
>
> **Choose what you share**
> Each piece goes only to the closets you pick. Everything else stays in My
> Clothes, visible to you alone. You can move a piece in or out whenever you
> want.
>
> **Find what actually fits**
> Filter by size, colour, occasion or owner, or search the whole closet. See at
> a glance whose piece is whose.
>
> **Make as many closets as you need**
> One for your apartment, one for your sisters, one for formal things. A piece
> can live in several at once.
>
> Group Closet is free, has no ads, and never sells your data.

---

## Keywords (100, comma-separated, no spaces after commas)

```
shared closet,wardrobe,borrow clothes,roommates,outfit,capsule,swap,friends,style,fashion closet
```

(96) Do **not** repeat "group" or "closet" — Apple already indexes the app name
and subtitle, so repeating them wastes characters.

---

## URLs

| Field | Value |
|---|---|
| Support URL | `https://aashnak.me/groupcloset/support.html` |
| Marketing URL | `https://aashnak.me/groupcloset/` |
| Privacy Policy URL | `https://aashnak.me/groupcloset/privacy.html` |

---

## App Privacy labels

Derived from the schema and the client. The app stores `name`, `photo_url` and
`sizes` in `public.users`; photos in the `item-photos` and `profile-photos`
buckets; item metadata in `items`. Email is held only by Supabase Auth via Sign
in with Apple — the app never reads or writes it.

### Data collected and linked to the user

| Category | Type | Purpose |
|---|---|---|
| Contact Info | Name | App Functionality |
| Contact Info | Email Address | App Functionality |
| User Content | Photos or Videos | App Functionality |
| User Content | Other User Content | App Functionality |
| Identifiers | User ID | App Functionality |

"Other User Content" covers item names, sizes, colours, occasion tags and
closet names.

### Not collected

Location, contacts, browsing/search history, purchases, financial info,
health & fitness, diagnostics, usage data, advertising identifiers.

**Clothing sizes are not health data.** They describe garments, not the body,
and belong under User Content — not Health & Fitness.

### Tracking

**No.** The only third-party SDK is `supabase-swift`. No analytics, no
attribution, no ad networks. Answer "No" to tracking and declare no data used
to track.

---

## Age rating

Answer the questionnaire honestly. The one that matters: the app **does** have
user-generated content. Also true, and worth having ready:

- Users can report items and other users (`reports` table)
- Users can block other users (`blocks` table)
- A Terms of Use is linked in-app and published

Guideline 1.2 requires all three for UGC apps. You have them.

---

## App Review notes

Paste something like this. Without it a reviewer signs in, sees an empty app,
and may never reach the core feature.

> Group Closet is a shared wardrobe. Sign in with Apple to create an account.
>
> **Important:** a new account starts empty by design — closets are created or
> joined by the user. To see the main experience:
>
> 1. Tap **+** on the Closets tab to create a closet
> 2. Add a piece via **+** (camera or photo library)
> 3. Open the closet to browse, filter and search
>
> To see a populated shared closet with multiple members, use the demo account:
> **Apple ID:** [fill in] / **Invite code:** [fill in]
>
> Account deletion: Profile tab → Delete Account. This removes the account,
> all items, and all uploaded photos.
>
> Moderation: items can be reported and users blocked from the item detail
> screen.

---

## Still to fill in

- [ ] Demo account credentials, or a closet invite code with real content
- [ ] Copyright string (e.g. `2026 Aashna Kshirsagar`)
- [ ] Confirm the screenshot slot: files are 1290×2796 (6.7"); named `6.9in-*`
