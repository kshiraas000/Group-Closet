# Visual Polish Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle every screen in the app to the "Ink & Sage" visual language from `docs/superpowers/specs/2026-08-09-visual-polish-design.md`, with zero behavior changes — same data, same queries, same RLS, same view model logic, only appearance.

**Architecture:** One shared `Theme` namespace (colors + font helpers) and three small reusable views (`OwnerBadge`, `CategoryChipsRow`, `FilterSheet`) go in a new `Closet/Closet/DesignSystem/` folder. A small `ProfilePhotoResolver` helper (batched signed-URL resolution for member profile photos, mirroring the existing per-view-model `loadSignedURLs()` pattern for item photos) goes in `Closet/Closet/Models/`. Every other change is a per-screen restyle of an existing `View` file — no view model's public interface changes except the two additions needed to back `OwnerBadge` with real photos (`ClosetDetailViewModel.memberPhotoURLs`, `MyClothesViewModel.memberPhotoURLs`), and no new queries or RLS.

**Tech Stack:** SwiftUI, `@Observable` view models (unchanged), Lora + DM Sans bundled fonts (already added to the repo — see below), no new dependencies.

**Pre-existing setup (already done, not a task in this plan):** `Closet/Closet/Resources/Fonts/` already contains `Lora-Regular.ttf`, `Lora-Medium.ttf`, `DMSans-Regular.ttf`, `DMSans-Medium.ttf`, `DMSans-Bold.ttf` (static instances cut from the upstream OFL-licensed variable fonts) plus their `OFL.txt` license files, committed in `3c22e6b`. PostScript names are exactly `Lora-Regular`, `Lora-Medium`, `DMSans-Regular`, `DMSans-Medium`, `DMSans-Bold` — Task 1 registers them in `Info.plist` and wraps them in `Theme.Font`. The project uses an Xcode 16 file-system-synchronized group for `Closet/Closet/`, so these files (and every new file this plan creates under that folder) are automatically part of the target with no `.pbxproj` editing needed.

## Global Constraints

- iOS 17.0 minimum deployment target, unchanged.
- No new dependencies beyond the two already-bundled font families.
- No view model's query logic, RLS assumptions, or `@Observable` state shape changes except the two `memberPhotoURLs` additions named above — every other diff is confined to `View` files.
- Colors: background `#F7F6F1`, primary text `#232823`, secondary text `#6D7370`, tertiary text `#8B918C`, accent `#4A5D4E`, divider `rgba(35,40,35,.08)`. Destructive actions keep system red — not part of the palette.
- Typography: headlines/captions in Lora (`Theme.Font.headline`), everything else in DM Sans (`Theme.Font.body`).
- Grid tiles: `4pt` corner radius, `3:4` aspect ratio, 3-up fixed columns. Item Detail photo container: `6pt` corner radius.
- Testing approach: implement → verify build (`xcodebuild`) → manual QA per screen. No pgTAP coverage needed (no backend changes in this entire plan).

---

## File Structure

- Create: `Closet/Closet/DesignSystem/Theme.swift`, `Closet/Closet/DesignSystem/OwnerBadge.swift`, `Closet/Closet/DesignSystem/CategoryChipsRow.swift`, `Closet/Closet/DesignSystem/FilterSheet.swift`
- Create: `Closet/Closet/Models/ProfilePhotoResolver.swift`
- Modify: `Closet/Closet/Info.plist`, `Closet/Closet/MainTabView.swift`
- Modify: `Closet/Closet/Closets/ClosetDetailView.swift`, `Closet/Closet/Closets/ClosetDetailViewModel.swift`, `Closet/Closet/Closets/ClosetsListView.swift`, `Closet/Closet/Closets/CreateClosetView.swift`, `Closet/Closet/Closets/JoinClosetView.swift`
- Modify: `Closet/Closet/MyClothes/MyClothesView.swift`, `Closet/Closet/MyClothes/MyClothesViewModel.swift`
- Modify: `Closet/Closet/ItemDetail/ItemDetailView.swift`
- Modify: `Closet/Closet/AddItem/AddItemView.swift`, `Closet/Closet/AddItem/PhotoTaggingView.swift`, `Closet/Closet/AddItem/ShareToClosetsView.swift`
- Modify: `Closet/Closet/Onboarding/OnboardingView.swift`, `Closet/Closet/Auth/SignInView.swift`
- Modify: `Closet/Closet/Profile/ProfileView.swift`

---

### Task 1: Design System Foundation — fonts, theme, shared components, tab bar

**Files:**
- Modify: `Closet/Closet/Info.plist`
- Create: `Closet/Closet/DesignSystem/Theme.swift`
- Create: `Closet/Closet/Models/ProfilePhotoResolver.swift`
- Create: `Closet/Closet/DesignSystem/OwnerBadge.swift`
- Modify: `Closet/Closet/MainTabView.swift`

**Interfaces:**
- Consumes: `UserProfile` (Phase 1 model), `SupabaseService.shared` (existing Storage client)
- Produces: `Theme.Color.{background,primaryText,secondaryText,tertiaryText,accent,divider}`, `Theme.Font.headline(_:)`, `Theme.Font.body(_:weight:)`, `ProfilePhotoResolver.signedURLs(for:)`, `OwnerBadge` view — every later task in this plan depends on these

- [ ] **Step 1: Register the bundled fonts**

Modify `Closet/Closet/Info.plist` — add a `UIAppFonts` array (the font files are copied to the app bundle root by the synchronized group, so entries are bare filenames, not paths):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>SUPABASE_ANON_KEY</key>
	<string>$(SUPABASE_ANON_KEY)</string>
	<key>SUPABASE_URL</key>
	<string>$(SUPABASE_URL)</string>
	<key>UIAppFonts</key>
	<array>
		<string>Lora-Regular.ttf</string>
		<string>Lora-Medium.ttf</string>
		<string>DMSans-Regular.ttf</string>
		<string>DMSans-Medium.ttf</string>
		<string>DMSans-Bold.ttf</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Write the theme**

Create `Closet/Closet/DesignSystem/Theme.swift`:

```swift
import SwiftUI

enum Theme {
    enum Color {
        static let background = SwiftUI.Color(red: 0xF7 / 255, green: 0xF6 / 255, blue: 0xF1 / 255)
        static let primaryText = SwiftUI.Color(red: 0x23 / 255, green: 0x28 / 255, blue: 0x23 / 255)
        static let secondaryText = SwiftUI.Color(red: 0x6D / 255, green: 0x73 / 255, blue: 0x70 / 255)
        static let tertiaryText = SwiftUI.Color(red: 0x8B / 255, green: 0x91 / 255, blue: 0x8C / 255)
        static let accent = SwiftUI.Color(red: 0x4A / 255, green: 0x5D / 255, blue: 0x4E / 255)
        static let divider = SwiftUI.Color(red: 35 / 255, green: 40 / 255, blue: 35 / 255).opacity(0.08)
    }

    enum Font {
        enum BodyWeight {
            case regular, medium, bold
        }

        static func headline(_ size: CGFloat) -> SwiftUI.Font {
            .custom("Lora-Medium", size: size)
        }

        static func headlineRegular(_ size: CGFloat) -> SwiftUI.Font {
            .custom("Lora-Regular", size: size)
        }

        static func body(_ size: CGFloat, weight: BodyWeight = .regular) -> SwiftUI.Font {
            switch weight {
            case .regular: return .custom("DMSans-Regular", size: size)
            case .medium: return .custom("DMSans-Medium", size: size)
            case .bold: return .custom("DMSans-Bold", size: size)
            }
        }
    }
}
```

- [ ] **Step 3: Write the profile-photo signed-URL resolver**

Create `Closet/Closet/Models/ProfilePhotoResolver.swift`:

```swift
import Foundation
import Storage
import Supabase

enum ProfilePhotoResolver {
    static func signedURLs(for profiles: [UserProfile]) async -> [UUID: URL] {
        let client = SupabaseService.shared
        var resolved: [UUID: URL] = [:]
        await withTaskGroup(of: (UUID, URL?).self) { group in
            for profile in profiles {
                guard let path = profile.photoURL else { continue }
                group.addTask {
                    let url = try? await client.storage.from("profile-photos").createSignedURL(
                        path: path,
                        expiresIn: 3600,
                        transform: TransformOptions(width: 80, height: 80, resize: .cover)
                    )
                    return (profile.id, url)
                }
            }
            for await (id, url) in group {
                if let url { resolved[id] = url }
            }
        }
        return resolved
    }
}
```

This mirrors the `loadSignedURLs()` pattern already used in `ClosetDetailViewModel`/`MyClothesViewModel` for item photos (batched `withTaskGroup`, best-effort — a failed signed URL is simply omitted, not a fatal error), applied to the `profile-photos` bucket. The bucket's RLS (added in Phase 8, migration `20260809000000`) already permits viewing "your own or closet-mates' " profile photos, so no backend change is needed here.

- [ ] **Step 4: Write the owner badge**

Create `Closet/Closet/DesignSystem/OwnerBadge.swift`:

```swift
import SwiftUI

struct OwnerBadge: View {
    let profile: UserProfile?
    let signedURL: URL?
    var diameter: CGFloat = 22

    var body: some View {
        Group {
            if let signedURL {
                AsyncImage(url: signedURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initialCircle
                    }
                }
            } else {
                initialCircle
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.Color.background, lineWidth: 2))
    }

    private var initialCircle: some View {
        Circle()
            .fill(Theme.Color.accent.opacity(0.25))
            .overlay(
                Text(initial)
                    .font(Theme.Font.body(diameter * 0.42, weight: .medium))
                    .foregroundStyle(Theme.Color.primaryText)
            )
    }

    private var initial: String {
        guard let first = profile?.name.first else { return "?" }
        return String(first).uppercased()
    }
}
```

- [ ] **Step 5: Tint the tab bar**

Full new file content for `Closet/Closet/MainTabView.swift`:

```swift
import SwiftUI

struct MainTabView: View {
    let userID: UUID
    let onSignedOut: () async -> Void

    init(userID: UUID, onSignedOut: @escaping () async -> Void) {
        self.userID = userID
        self.onSignedOut = onSignedOut
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.Color.background)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            ClosetsListView(userID: userID)
                .tabItem { Label("Closets", systemImage: "door.left.hand.open") }
            MyClothesView(userID: userID)
                .tabItem { Label("My Clothes", systemImage: "tshirt") }
            ProfileView(userID: userID, onSignedOut: onSignedOut)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Theme.Color.accent)
    }
}
```

- [ ] **Step 6: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Manually verify**

On a Simulator: launch the app, sign in, and confirm the tab bar background is the new bone color (not white) and the active tab's icon/label is sage-green (not the default iOS blue). Nothing else visibly changes yet — that's expected, later tasks consume `Theme`/`OwnerBadge`/`ProfilePhotoResolver`.

- [ ] **Step 8: Commit**

```bash
git add Closet/Closet/Info.plist Closet/Closet/DesignSystem/Theme.swift Closet/Closet/Models/ProfilePhotoResolver.swift Closet/Closet/DesignSystem/OwnerBadge.swift Closet/Closet/MainTabView.swift
git commit -m "Add design system foundation: bundled fonts, theme, owner badge, tab bar tint"
```

---

### Task 2: Closet Detail — top bar, filter sheet, grid

**Files:**
- Create: `Closet/Closet/DesignSystem/CategoryChipsRow.swift`, `Closet/Closet/DesignSystem/FilterSheet.swift`
- Modify: `Closet/Closet/Closets/ClosetDetailViewModel.swift`, `Closet/Closet/Closets/ClosetDetailView.swift`

**Interfaces:**
- Consumes: `Theme`, `OwnerBadge`, `ProfilePhotoResolver` (Task 1); `BrowseFilters`/`BrowseFiltering` (unchanged, Phase 4/6)
- Produces: `CategoryChipsRow(selectedCategory:onFilterTapped:)`, `FilterSheet(filters:members:availableSizes:availableColors:availableOccasions:)`, `ClosetDetailViewModel.memberPhotoURLs: [UUID: URL]` — Task 3 reuses the two shared views; Task 4 reuses `memberPhotoURLs`

- [ ] **Step 1: Write the category chips row**

Create `Closet/Closet/DesignSystem/CategoryChipsRow.swift`:

```swift
import SwiftUI

struct CategoryChipsRow: View {
    @Binding var selectedCategory: ItemCategory?
    let onFilterTapped: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(ItemCategory.allCases) { category in
                    chip(title: category.rawValue, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
                Button(action: onFilterTapped) {
                    HStack(spacing: 4) {
                        Text("Filter")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(Theme.Font.body(13, weight: .medium))
                    .foregroundStyle(Theme.Color.primaryText)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(Theme.Color.primaryText.opacity(0.06))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.body(13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Theme.Color.background : Theme.Color.primaryText.opacity(0.75))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(isSelected ? Theme.Color.accent : Theme.Color.primaryText.opacity(0.06))
                .clipShape(Capsule())
        }
    }
}
```

- [ ] **Step 2: Write the filter sheet**

Create `Closet/Closet/DesignSystem/FilterSheet.swift`:

```swift
import SwiftUI

struct FilterSheet: View {
    @Binding var filters: BrowseFilters
    let members: [UserProfile]?
    let availableSizes: [String]
    let availableColors: [String]
    let availableOccasions: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let members {
                    Section("Owner") {
                        radioRow(title: "Everyone", isSelected: filters.ownerID == nil) {
                            filters.ownerID = nil
                        }
                        ForEach(members) { member in
                            radioRow(title: member.name, isSelected: filters.ownerID == member.id) {
                                filters.ownerID = member.id
                            }
                        }
                    }
                    .listRowBackground(Theme.Color.background)
                }

                if !availableSizes.isEmpty {
                    Section("Size") {
                        radioRow(title: "Any", isSelected: filters.size == nil) {
                            filters.size = nil
                        }
                        ForEach(availableSizes, id: \.self) { size in
                            radioRow(title: size, isSelected: filters.size == size) {
                                filters.size = size
                            }
                        }
                    }
                    .listRowBackground(Theme.Color.background)
                }

                if !availableColors.isEmpty {
                    Section("Color") {
                        radioRow(title: "Any", isSelected: filters.color == nil) {
                            filters.color = nil
                        }
                        ForEach(availableColors, id: \.self) { color in
                            radioRow(title: color, isSelected: filters.color == color) {
                                filters.color = color
                            }
                        }
                    }
                    .listRowBackground(Theme.Color.background)
                }

                if !availableOccasions.isEmpty {
                    Section("Occasion") {
                        radioRow(title: "Any", isSelected: filters.occasion == nil) {
                            filters.occasion = nil
                        }
                        ForEach(availableOccasions, id: \.self) { occasion in
                            radioRow(title: occasion, isSelected: filters.occasion == occasion) {
                                filters.occasion = occasion
                            }
                        }
                    }
                    .listRowBackground(Theme.Color.background)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(Theme.Color.accent)
                }
            }
        }
    }

    private func radioRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Theme.Font.body(16))
                    .foregroundStyle(Theme.Color.primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.Color.accent)
                }
            }
        }
    }
}
```

Single-select per section, matching today's single-select `Menu` behavior exactly — no multi-select. A section is omitted if its options list is empty, matching today's `if !viewModel.availableSizes.isEmpty` guards. The `Owner` section is `nil` for My Clothes (Task 3) since there's no owner filter there today either.

- [ ] **Step 3: Add member photo resolution to the view model**

Full new file content for `Closet/Closet/Closets/ClosetDetailViewModel.swift`:

```swift
import Foundation
import PostgREST
import Storage
import Supabase

private struct MemberRow: Decodable {
    let users: UserProfile
}

private struct PhotoRow: Decodable {
    let photoURL: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case photoURL = "photo_url"
        case position
    }
}

private struct RawBrowseItem: Decodable {
    let id: UUID
    let ownerID: UUID
    let category: ItemCategory
    let size: String?
    let color: String?
    let occasionTags: [String]
    let caption: String?
    let createdAt: Date
    let itemPhotos: [PhotoRow]

    enum CodingKeys: String, CodingKey {
        case id, category, size, color, caption
        case ownerID = "owner_id"
        case occasionTags = "occasion_tags"
        case createdAt = "created_at"
        case itemPhotos = "item_photos"
    }
}

private struct ItemShareRow: Decodable {
    let items: RawBrowseItem
}

@Observable
final class ClosetDetailViewModel {
    var members: [UserProfile] = []
    var memberPhotoURLs: [UUID: URL] = [:]
    var items: [BrowseItem] = []
    var filters = BrowseFilters()
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    var filteredItems: [BrowseItem] {
        BrowseFiltering.filteredItems(items, filters: filters)
    }

    var availableSizes: [String] {
        BrowseFiltering.availableSizes(items)
    }

    var availableColors: [String] {
        BrowseFiltering.availableColors(items)
    }

    var availableOccasions: [String] {
        BrowseFiltering.availableOccasions(items)
    }

    func load(closetID: UUID) async {
        isLoading = true
        defer { isLoading = false }
        var failures: [String] = []

        do {
            let rows: [MemberRow] = try await client
                .from("closet_members")
                .select("users(id, name, photo_url, sizes)")
                .eq("closet_id", value: closetID)
                .execute()
                .value
            members = rows.map(\.users)
            memberPhotoURLs = await ProfilePhotoResolver.signedURLs(for: members)
        } catch {
            failures.append(error.localizedDescription)
        }

        do {
            let rows: [ItemShareRow] = try await client
                .from("item_shares")
                .select("items!inner(*, item_photos(photo_url, position))")
                .eq("closet_id", value: closetID)
                .execute()
                .value
            items = rows
                .map { Self.makeBrowseItem($0.items) }
                .sorted { $0.item.createdAt > $1.item.createdAt }
            await loadSignedURLs()
        } catch {
            failures.append(error.localizedDescription)
        }

        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    private static func makeBrowseItem(_ raw: RawBrowseItem) -> BrowseItem {
        let item = Item(
            id: raw.id,
            ownerID: raw.ownerID,
            category: raw.category,
            size: raw.size,
            color: raw.color,
            occasionTags: raw.occasionTags,
            caption: raw.caption,
            createdAt: raw.createdAt
        )
        let photoPath = raw.itemPhotos.first(where: { $0.position == 0 })?.photoURL
        return BrowseItem(item: item, photoPath: photoPath)
    }

    private func loadSignedURLs() async {
        let paths = Set(items.compactMap(\.photoPath))
        guard !paths.isEmpty else { return }

        var resolved: [String: URL] = [:]
        await withTaskGroup(of: (String, URL?).self) { group in
            for path in paths {
                group.addTask { [client] in
                    let url = try? await client.storage.from("item-photos").createSignedURL(
                        path: path,
                        expiresIn: 3600,
                        transform: TransformOptions(width: 400, height: 400, resize: .cover)
                    )
                    return (path, url)
                }
            }
            for await (path, url) in group {
                if let url { resolved[path] = url }
            }
        }

        for index in items.indices {
            if let path = items[index].photoPath {
                items[index].signedURL = resolved[path]
            }
        }
    }

    func leave(closetID: UUID, userID: UUID) async -> Bool {
        errorMessage = nil
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

(Only two lines changed from today: the new `memberPhotoURLs` property and the one new line resolving it after `members` is set.)

- [ ] **Step 4: Restyle the view**

Full new file content for `Closet/Closet/Closets/ClosetDetailView.swift`:

```swift
import SwiftUI

private struct ItemDetailContext: Identifiable {
    let id = UUID()
    let items: [BrowseItem]
    let startIndex: Int
}

struct ClosetDetailView: View {
    @State private var viewModel = ClosetDetailViewModel()
    @State private var showingLeaveConfirmation = false
    @State private var showingAddItem = false
    @State private var showingFilters = false
    @State private var detailContext: ItemDetailContext?
    @Environment(\.dismiss) private var dismiss
    let closet: Closet
    let userID: UUID
    let onLeft: () -> Void

    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        List {
            Section("Members") {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    ForEach(viewModel.members) { member in
                        Text(member.name)
                            .font(Theme.Font.body(16))
                            .foregroundStyle(Theme.Color.primaryText)
                    }
                }
            }
            .listRowBackground(Theme.Color.background)

            Section("Items") {
                CategoryChipsRow(selectedCategory: $viewModel.filters.category) {
                    showingFilters = true
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Theme.Color.background)

                if viewModel.filteredItems.isEmpty {
                    Text(viewModel.items.isEmpty ? "No items yet" : "No items match your filters")
                        .font(Theme.Font.body(14))
                        .foregroundStyle(Theme.Color.secondaryText)
                        .listRowBackground(Theme.Color.background)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 10) {
                        ForEach(viewModel.filteredItems) { browseItem in
                            Button {
                                openDetail(for: browseItem)
                            } label: {
                                itemCell(browseItem)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Theme.Color.background)
                }
            }

            Section {
                ShareLink(item: "Join my Closet \"\(closet.name)\" on the Closet app — invite code: \(closet.inviteCode)") {
                    Label("Share Invite", systemImage: "square.and.arrow.up")
                }
                .font(Theme.Font.body(16))
                .tint(Theme.Color.accent)
            }
            .listRowBackground(Theme.Color.background)

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(Theme.Font.body(14))
                        .foregroundStyle(.red)
                }
                .listRowBackground(Theme.Color.background)
            }

            Section {
                Button("Leave Closet", role: .destructive) {
                    showingLeaveConfirmation = true
                }
                .font(Theme.Font.body(16))
            }
            .listRowBackground(Theme.Color.background)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Color.background)
        .searchable(text: $viewModel.filters.searchText)
        .navigationTitle(closet.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .tint(Theme.Color.accent)
            }
        }
        .task {
            await viewModel.load(closetID: closet.id)
        }
        .sheet(isPresented: $showingAddItem) {
            AddItemView(closetID: closet.id, userID: userID) {
                Task { await viewModel.load(closetID: closet.id) }
            }
        }
        .sheet(isPresented: $showingFilters) {
            FilterSheet(
                filters: $viewModel.filters,
                members: viewModel.members,
                availableSizes: viewModel.availableSizes,
                availableColors: viewModel.availableColors,
                availableOccasions: viewModel.availableOccasions
            )
        }
        .fullScreenCover(item: $detailContext) { context in
            ItemDetailView(
                items: context.items,
                startIndex: context.startIndex,
                members: viewModel.members,
                userID: userID,
                onShareChanged: { Task { await viewModel.load(closetID: closet.id) } },
                onBlocked: { Task { await viewModel.load(closetID: closet.id) } }
            )
        }
        .confirmationDialog(
            "Leave \(closet.name)?",
            isPresented: $showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task {
                    if await viewModel.leave(closetID: closet.id, userID: userID) {
                        onLeft()
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func openDetail(for browseItem: BrowseItem) {
        let snapshot = viewModel.filteredItems
        if let index = snapshot.firstIndex(where: { $0.id == browseItem.id }) {
            detailContext = ItemDetailContext(items: snapshot, startIndex: index)
        }
    }

    private func itemCell(_ browseItem: BrowseItem) -> some View {
        let owner = viewModel.members.first { $0.id == browseItem.item.ownerID }
        return AsyncImage(url: browseItem.signedURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(Theme.Color.accent.opacity(0.12))
            }
        }
        .aspectRatio(3 / 4, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .bottomLeading) {
            OwnerBadge(profile: owner, signedURL: owner.flatMap { viewModel.memberPhotoURLs[$0.id] })
                .padding(6)
        }
    }
}
```

Note: the `ItemDetailView(...)` call here is **unchanged** from today — Item Detail itself isn't restyled until Task 4, which is also when it gains the parameter needed to show `OwnerBadge` there. Don't add that parameter in this task; it would leave `ItemDetailView`'s signature and this call site out of sync until Task 4 lands, breaking the build in between.

- [ ] **Step 5: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Manually verify**

Open a Closet with a few items from more than one member:
1. Confirm the top shows a search field, then a horizontally-scrollable row of category chips (All + your 6 categories) ending in a "Filter ▾" chip.
2. Tap "Filter ▾" — confirm a sheet opens with Owner (radio list of members + Everyone), and Size/Color/Occasion sections that only appear when there's data for them. Picking one, then tapping Done, actually filters the grid.
3. Confirm the grid is 3 columns of bare photos (no caption or "Owner · Size" text underneath), each with a small circular badge in the bottom-left corner showing that item's owner — their profile photo if they've set one (Phase 8), otherwise their initial.
4. Confirm Members, Share Invite, and Leave Closet still work exactly as before, just restyled.

- [ ] **Step 7: Commit**

```bash
git add Closet/Closet/DesignSystem/CategoryChipsRow.swift Closet/Closet/DesignSystem/FilterSheet.swift Closet/Closet/Closets/ClosetDetailViewModel.swift Closet/Closet/Closets/ClosetDetailView.swift
git commit -m "Restyle Closet Detail: search + category chips + filter sheet + bare-photo grid"
```

---

### Task 3: My Clothes — same top bar and grid pattern, no owner badge

**Files:**
- Modify: `Closet/Closet/MyClothes/MyClothesView.swift`

**Interfaces:**
- Consumes: `CategoryChipsRow`, `FilterSheet` (Task 2); `Theme` (Task 1)
- Produces: nothing new — `MyClothesViewModel` is untouched in this task (its `memberPhotoURLs` addition happens in Task 4, alongside Item Detail's restyle)

- [ ] **Step 1: Restyle the view**

Full new file content for `Closet/Closet/MyClothes/MyClothesView.swift`:

```swift
import SwiftUI

private struct ItemDetailContext: Identifiable {
    let id = UUID()
    let items: [BrowseItem]
    let startIndex: Int
}

struct MyClothesView: View {
    @State private var viewModel = MyClothesViewModel()
    @State private var detailContext: ItemDetailContext?
    @State private var showingFilters = false
    let userID: UUID

    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading {
                    ProgressView()
                        .listRowBackground(Theme.Color.background)
                } else {
                    CategoryChipsRow(selectedCategory: $viewModel.filters.category) {
                        showingFilters = true
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Theme.Color.background)

                    if viewModel.filteredItems.isEmpty {
                        Text(viewModel.items.isEmpty ? "No items yet" : "No items match your filters")
                            .font(Theme.Font.body(14))
                            .foregroundStyle(Theme.Color.secondaryText)
                            .listRowBackground(Theme.Color.background)
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: 10) {
                            ForEach(viewModel.filteredItems) { browseItem in
                                Button {
                                    openDetail(for: browseItem)
                                } label: {
                                    itemCell(browseItem)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(Theme.Color.background)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.body(14))
                        .foregroundStyle(.red)
                        .listRowBackground(Theme.Color.background)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .searchable(text: $viewModel.filters.searchText)
            .navigationTitle("My Clothes")
            .task {
                await viewModel.load(userID: userID)
            }
            .refreshable {
                await viewModel.load(userID: userID)
            }
            .sheet(isPresented: $showingFilters) {
                FilterSheet(
                    filters: $viewModel.filters,
                    members: nil,
                    availableSizes: viewModel.availableSizes,
                    availableColors: viewModel.availableColors,
                    availableOccasions: viewModel.availableOccasions
                )
            }
            .fullScreenCover(item: $detailContext) { context in
                ItemDetailView(
                    items: context.items,
                    startIndex: context.startIndex,
                    members: [viewModel.myProfile].compactMap { $0 },
                    userID: userID
                )
            }
        }
    }

    private func openDetail(for browseItem: BrowseItem) {
        let snapshot = viewModel.filteredItems
        if let index = snapshot.firstIndex(where: { $0.id == browseItem.id }) {
            detailContext = ItemDetailContext(items: snapshot, startIndex: index)
        }
    }

    private func itemCell(_ browseItem: BrowseItem) -> some View {
        AsyncImage(url: browseItem.signedURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(Theme.Color.accent.opacity(0.12))
            }
        }
        .aspectRatio(3 / 4, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
```

`members: nil` tells `FilterSheet` to omit the Owner section — every item here is already yours, matching today's behavior (no owner filter exists in `MyClothesViewModel` either). No `OwnerBadge` on these tiles, per the design spec. The `ItemDetailView(...)` call is **unchanged** from today, for the same reason as Task 2 — its new parameter arrives in Task 4.

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manually verify**

Open the My Clothes tab: confirm the same search + category chips + Filter sheet pattern as Closet Detail, but the Filter sheet has no Owner section, and grid tiles have no owner badge (bare photo only). Pull-to-refresh still works.

- [ ] **Step 4: Commit**

```bash
git add Closet/Closet/MyClothes/MyClothesView.swift
git commit -m "Restyle My Clothes: same category chips + filter sheet + bare-photo grid as Closet Detail"
```

---

### Task 4: Item Detail — restyle, owner badge, caption-only-here

**Files:**
- Modify: `Closet/Closet/ItemDetail/ItemDetailView.swift`
- Modify: `Closet/Closet/Closets/ClosetDetailView.swift` (one call site)
- Modify: `Closet/Closet/MyClothes/MyClothesViewModel.swift`, `Closet/Closet/MyClothes/MyClothesView.swift` (one call site)

**Interfaces:**
- Consumes: `Theme`, `OwnerBadge`, `ProfilePhotoResolver` (Task 1); `ClosetDetailViewModel.memberPhotoURLs` (Task 2)
- Produces: `ItemDetailView` gains a required `memberPhotoURLs: [UUID: URL]` parameter; `MyClothesViewModel.memberPhotoURLs: [UUID: URL]`

- [ ] **Step 1: Restyle Item Detail and add the new parameter**

Full new file content for `Closet/Closet/ItemDetail/ItemDetailView.swift`:

```swift
import SwiftUI

struct ItemDetailView: View {
    @State private var viewModel = ItemDetailViewModel()
    @State private var currentIndex: Int
    @State private var showingReportConfirmation = false
    @State private var showingBlockConfirmation = false
    @State private var showingActionAlert = false
    @State private var actionAlertMessage = ""
    @Environment(\.dismiss) private var dismiss
    let items: [BrowseItem]
    let members: [UserProfile]
    let memberPhotoURLs: [UUID: URL]
    let userID: UUID
    let onShareChanged: () -> Void
    let onBlocked: () -> Void

    init(
        items: [BrowseItem],
        startIndex: Int,
        members: [UserProfile],
        memberPhotoURLs: [UUID: URL] = [:],
        userID: UUID,
        onShareChanged: @escaping () -> Void = {},
        onBlocked: @escaping () -> Void = {}
    ) {
        self.items = items
        self.members = members
        self.memberPhotoURLs = memberPhotoURLs
        self.userID = userID
        self.onShareChanged = onShareChanged
        self.onBlocked = onBlocked
        _currentIndex = State(initialValue: startIndex)
    }

    private var currentItem: BrowseItem {
        items[currentIndex]
    }

    private var owner: UserProfile? {
        members.first { $0.id == currentItem.item.ownerID }
    }

    private var ownerName: String {
        owner?.name ?? "Unknown"
    }

    private var isOwner: Bool {
        currentItem.item.ownerID == userID
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            photoArea
            bottomInfo
        }
        .background(Theme.Color.background)
        .task(id: currentIndex) {
            await viewModel.loadFullResURL(for: currentItem)
            if isOwner {
                await viewModel.loadShareState(itemID: currentItem.item.id)
            }
        }
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
        .alert("", isPresented: $showingActionAlert) {
            Button("OK") {}
        } message: {
            Text(actionAlertMessage)
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            HStack(spacing: 8) {
                OwnerBadge(profile: owner, signedURL: memberPhotoURLs[currentItem.item.ownerID], diameter: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ownerName)
                        .font(Theme.Font.body(15, weight: .medium))
                        .foregroundStyle(Theme.Color.primaryText)
                    Text(currentItem.item.category.rawValue)
                        .font(Theme.Font.body(12))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                Text("\(currentIndex + 1) of \(items.count)")
                    .font(Theme.Font.body(12))
                    .foregroundStyle(Theme.Color.tertiaryText)
            }
        }
        .padding()
    }

    private var photoArea: some View {
        ZStack {
            AsyncImage(url: viewModel.url(for: currentItem)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                } else {
                    Rectangle()
                        .fill(Theme.Color.accent.opacity(0.08))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 16)

            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goToPrevious() }
                Color.clear
                    .contentShape(Rectangle())
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goToNext() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let caption = currentItem.item.caption {
                Text(caption)
                    .font(Theme.Font.headline(24))
                    .foregroundStyle(Theme.Color.primaryText)
            }

            let chips = [currentItem.item.size, currentItem.item.color]
                .compactMap { $0 }
                + currentItem.item.occasionTags
            if !chips.isEmpty {
                Text(chips.joined(separator: " · "))
                    .font(Theme.Font.body(13))
                    .foregroundStyle(Theme.Color.secondaryText)
            }

            if isOwner {
                Divider().overlay(Theme.Color.divider).padding(.top, 8)
                sharedToSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .overlay(alignment: .bottomTrailing) {
            moreMenu
        }
    }

    private var sharedToSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shared to")
                .font(Theme.Font.body(12))
                .foregroundStyle(Theme.Color.secondaryText)

            if let shareStateErrorMessage = viewModel.shareStateErrorMessage {
                Text(shareStateErrorMessage)
                    .font(Theme.Font.body(12))
                    .foregroundStyle(.red)
            }

            if viewModel.isLoadingShareState {
                ProgressView()
            } else {
                ForEach(viewModel.allClosets) { closet in
                    Button {
                        Task {
                            await viewModel.toggleShare(itemID: currentItem.item.id, closetID: closet.id)
                            onShareChanged()
                        }
                    } label: {
                        HStack {
                            Text(closet.name)
                                .font(Theme.Font.body(15))
                            Spacer()
                            if viewModel.sharedClosetIDs.contains(closet.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Color.accent)
                            }
                        }
                    }
                    .foregroundStyle(Theme.Color.primaryText)
                }
            }
        }
        .padding(.top, 8)
    }

    private var moreMenu: some View {
        Menu {
            if isOwner {
                Button("Edit") {}
                    .disabled(true)
                Button("Delete", role: .destructive) {}
                    .disabled(true)
            } else {
                Button("Report") { showingReportConfirmation = true }
                Button("Block \(ownerName)", role: .destructive) { showingBlockConfirmation = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundStyle(Theme.Color.secondaryText)
        }
        .padding()
    }

    private func goToNext() {
        currentIndex = min(currentIndex + 1, items.count - 1)
    }

    private func goToPrevious() {
        currentIndex = max(currentIndex - 1, 0)
    }
}
```

This is the one screen that changes in kind, not just polish: the forced `.preferredColorScheme(.dark)` and black background are gone, replaced with the same bone/Ink & Sage look as the rest of the app (design doc §5.2) — so the whole app reads as one identity instead of one dark screen surrounded by light ones. The caption is now shown here in Lora and **only** here — no other screen shows a caption after this plan. `memberPhotoURLs` defaults to `[:]` so any caller not yet updated still compiles (both current call sites are updated in this same task, but the default keeps the signature forgiving of a caller found later).

- [ ] **Step 2: Thread `memberPhotoURLs` from Closet Detail**

Modify `Closet/Closet/Closets/ClosetDetailView.swift` — in the `.fullScreenCover(item: $detailContext)` block, add one argument:

```swift
        .fullScreenCover(item: $detailContext) { context in
            ItemDetailView(
                items: context.items,
                startIndex: context.startIndex,
                members: viewModel.members,
                memberPhotoURLs: viewModel.memberPhotoURLs,
                userID: userID,
                onShareChanged: { Task { await viewModel.load(closetID: closet.id) } },
                onBlocked: { Task { await viewModel.load(closetID: closet.id) } }
            )
        }
```

- [ ] **Step 3: Add member photo resolution to My Clothes and thread it through**

Full new file content for `Closet/Closet/MyClothes/MyClothesViewModel.swift`:

```swift
import Foundation
import PostgREST
import Storage
import Supabase

private struct PhotoRow: Decodable {
    let photoURL: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case photoURL = "photo_url"
        case position
    }
}

private struct RawItem: Decodable {
    let id: UUID
    let ownerID: UUID
    let category: ItemCategory
    let size: String?
    let color: String?
    let occasionTags: [String]
    let caption: String?
    let createdAt: Date
    let itemPhotos: [PhotoRow]

    enum CodingKeys: String, CodingKey {
        case id, category, size, color, caption
        case ownerID = "owner_id"
        case occasionTags = "occasion_tags"
        case createdAt = "created_at"
        case itemPhotos = "item_photos"
    }
}

@Observable
final class MyClothesViewModel {
    var myProfile: UserProfile?
    var memberPhotoURLs: [UUID: URL] = [:]
    var items: [BrowseItem] = []
    var filters = BrowseFilters()
    var isLoading = true
    var errorMessage: String?

    private let client = SupabaseService.shared

    var filteredItems: [BrowseItem] {
        BrowseFiltering.filteredItems(items, filters: filters)
    }

    var availableSizes: [String] {
        BrowseFiltering.availableSizes(items)
    }

    var availableColors: [String] {
        BrowseFiltering.availableColors(items)
    }

    var availableOccasions: [String] {
        BrowseFiltering.availableOccasions(items)
    }

    func load(userID: UUID) async {
        isLoading = true
        defer { isLoading = false }

        myProfile = try? await client
            .from("users")
            .select()
            .eq("id", value: userID)
            .single()
            .execute()
            .value
        memberPhotoURLs = await ProfilePhotoResolver.signedURLs(for: [myProfile].compactMap { $0 })

        do {
            let rows: [RawItem] = try await client
                .from("items")
                .select("*, item_photos(photo_url, position)")
                .eq("owner_id", value: userID)
                .execute()
                .value
            items = rows
                .map(Self.makeBrowseItem)
                .sorted { $0.item.createdAt > $1.item.createdAt }
            await loadSignedURLs()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func makeBrowseItem(_ raw: RawItem) -> BrowseItem {
        let item = Item(
            id: raw.id,
            ownerID: raw.ownerID,
            category: raw.category,
            size: raw.size,
            color: raw.color,
            occasionTags: raw.occasionTags,
            caption: raw.caption,
            createdAt: raw.createdAt
        )
        let photoPath = raw.itemPhotos.first(where: { $0.position == 0 })?.photoURL
        return BrowseItem(item: item, photoPath: photoPath)
    }

    private func loadSignedURLs() async {
        let paths = Set(items.compactMap(\.photoPath))
        guard !paths.isEmpty else { return }

        var resolved: [String: URL] = [:]
        await withTaskGroup(of: (String, URL?).self) { group in
            for path in paths {
                group.addTask { [client] in
                    let url = try? await client.storage.from("item-photos").createSignedURL(
                        path: path,
                        expiresIn: 3600,
                        transform: TransformOptions(width: 400, height: 400, resize: .cover)
                    )
                    return (path, url)
                }
            }
            for await (path, url) in group {
                if let url { resolved[path] = url }
            }
        }

        for index in items.indices {
            if let path = items[index].photoPath {
                items[index].signedURL = resolved[path]
            }
        }
    }
}
```

Modify `Closet/Closet/MyClothes/MyClothesView.swift` — in the `.fullScreenCover(item: $detailContext)` block, add one argument:

```swift
            .fullScreenCover(item: $detailContext) { context in
                ItemDetailView(
                    items: context.items,
                    startIndex: context.startIndex,
                    members: [viewModel.myProfile].compactMap { $0 },
                    memberPhotoURLs: viewModel.memberPhotoURLs,
                    userID: userID
                )
            }
```

- [ ] **Step 4: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manually verify**

Open an item from both Closet Detail and My Clothes:
1. Confirm the background is now bone/light, not black — no forced dark mode.
2. Confirm the owner's badge (photo or initial) shows in the top-left, matching the grid tile's badge for that same owner.
3. Confirm the caption (if the item has one) shows here in a large serif font — and confirm it does **not** show anywhere on the grid (Task 2/3 already removed it there).
4. As the owner, confirm the "Shared to" toggle list still works exactly as before (Phase 6 behavior unchanged). As a non-owner, confirm nothing about sharing is shown (matching today — this was deliberately not extended, see design doc §5.2).
5. Confirm Report/Block (non-owner) and the disabled Edit/Delete (owner) menu items still work as before.

- [ ] **Step 6: Commit**

```bash
git add Closet/Closet/ItemDetail/ItemDetailView.swift Closet/Closet/Closets/ClosetDetailView.swift Closet/Closet/MyClothes/MyClothesViewModel.swift Closet/Closet/MyClothes/MyClothesView.swift
git commit -m "Restyle Item Detail: drop forced dark mode, add owner badge, caption shown only here"
```

---

### Task 5: Closets List, Create Closet, Join Closet

**Files:**
- Modify: `Closet/Closet/Closets/ClosetsListView.swift`, `Closet/Closet/Closets/CreateClosetView.swift`, `Closet/Closet/Closets/JoinClosetView.swift`

**Interfaces:**
- Consumes: `Theme` (Task 1)
- Produces: nothing new

- [ ] **Step 1: Restyle Closets List**

Full new file content for `Closet/Closet/Closets/ClosetsListView.swift`:

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
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.body(14))
                        .foregroundStyle(.red)
                } else if viewModel.closets.isEmpty {
                    emptyState
                } else {
                    List(viewModel.closets) { closet in
                        NavigationLink {
                            ClosetDetailView(closet: closet, userID: userID) {
                                Task { await viewModel.loadClosets() }
                            }
                        } label: {
                            Text(closet.name)
                                .font(Theme.Font.headline(20))
                                .foregroundStyle(Theme.Color.primaryText)
                        }
                        .listRowBackground(Theme.Color.background)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.Color.background)
                }
            }
            .background(Theme.Color.background)
            .navigationTitle("Closets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Create a Closet") { showingCreate = true }
                        Button("Join with invite code") { showingJoin = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(Theme.Color.accent)
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
                .font(Theme.Font.headline(22))
                .foregroundStyle(Theme.Color.primaryText)
            Button("Create a Closet") { showingCreate = true }
                .font(Theme.Font.body(16, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            Button("Have an invite link? Paste it") { showingJoin = true }
                .font(Theme.Font.body(16))
                .foregroundStyle(Theme.Color.accent)
        }
    }
}
```

Per design doc §5.4, this is restyle-only — no member avatars or item count on each row (that data isn't loaded today and adding it would be a new query, not a restyle; the concrete "N members, tap to expand" idea is recorded there as a future enhancement, not built now).

- [ ] **Step 2: Restyle Create Closet**

Full new file content for `Closet/Closet/Closets/CreateClosetView.swift`:

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
            .background(Theme.Color.background)
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
                        .tint(Theme.Color.accent)
                    }
                }
            }
        }
    }

    private var form: some View {
        Form {
            TextField("Closet name", text: $viewModel.name)
                .font(Theme.Font.body(16))
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.body(14))
                    .foregroundStyle(.red)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Color.background)
    }

    private func inviteView(for closet: Closet) -> some View {
        VStack(spacing: 16) {
            Text("\(closet.name) is ready")
                .font(Theme.Font.headline(22))
                .foregroundStyle(Theme.Color.primaryText)
            Text("Invite code: \(closet.inviteCode)")
                .font(Theme.Font.body(18, weight: .medium))
                .foregroundStyle(Theme.Color.secondaryText)
            ShareLink(item: "Join my Closet \"\(closet.name)\" on the Closet app — invite code: \(closet.inviteCode)")
                .font(Theme.Font.body(16, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            Button("Done") { dismiss() }
                .font(Theme.Font.body(16, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
        }
        .padding()
    }
}
```

- [ ] **Step 3: Restyle Join Closet**

Full new file content for `Closet/Closet/Closets/JoinClosetView.swift`:

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
                    .font(Theme.Font.body(16))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.body(14))
                        .foregroundStyle(.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
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
                    .tint(Theme.Color.accent)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manually verify**

Confirm the Closets tab's list rows show closet names in the new serif headline font on a bone background. Create a new Closet and confirm the form/invite screen is restyled but works identically (name entry, invite code display, share sheet). Join a Closet by invite code and confirm the same for that flow.

- [ ] **Step 6: Commit**

```bash
git add Closet/Closet/Closets/ClosetsListView.swift Closet/Closet/Closets/CreateClosetView.swift Closet/Closet/Closets/JoinClosetView.swift
git commit -m "Restyle Closets List, Create Closet, and Join Closet"
```

---

### Task 6: Add Item flow

**Files:**
- Modify: `Closet/Closet/AddItem/AddItemView.swift`, `Closet/Closet/AddItem/PhotoTaggingView.swift`, `Closet/Closet/AddItem/ShareToClosetsView.swift`

**Interfaces:**
- Consumes: `Theme` (Task 1)
- Produces: nothing new

- [ ] **Step 1: Restyle the container**

Full new file content for `Closet/Closet/AddItem/AddItemView.swift`:

```swift
import PhotosUI
import SwiftUI

struct AddItemView: View {
    @State private var viewModel = AddItemViewModel()
    @State private var step: Step = .picking
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @Environment(\.dismiss) private var dismiss
    let closetID: UUID
    let userID: UUID
    let onItemsSaved: () -> Void

    enum Step {
        case picking
        case tagging
        case sharing
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .picking:
                    pickerView
                case .tagging:
                    PhotoTaggingView(viewModel: viewModel) {
                        step = .sharing
                    }
                case .sharing:
                    ShareToClosetsView(
                        viewModel: viewModel,
                        currentClosetID: closetID,
                        ownerID: userID
                    ) {
                        onItemsSaved()
                        dismiss()
                    }
                }
            }
            .background(Theme.Color.background)
            .navigationTitle("Add Items")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await viewModel.loadDefaultSizes(userID: userID) }
    }

    private var pickerView: some View {
        VStack(spacing: 24) {
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 20, matching: .images) {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
                    .font(Theme.Font.body(16, weight: .medium))
            }
            .tint(Theme.Color.accent)
            .onChange(of: selectedPhotos) { _, newValue in
                Task { await loadImages(from: newValue) }
            }
        }
        .padding()
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        guard !images.isEmpty else { return }
        viewModel.startTagging(images: images)
        step = .tagging
    }
}
```

- [ ] **Step 2: Restyle the tagging screen**

Full new file content for `Closet/Closet/AddItem/PhotoTaggingView.swift`:

```swift
import SwiftUI

struct PhotoTaggingView: View {
    @Bindable var viewModel: AddItemViewModel
    @State private var currentIndex = 0
    let onFinished: () -> Void

    var body: some View {
        VStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(viewModel.draftItems.enumerated()), id: \.element.id) { index, _ in
                    tagForm(index: index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
            .background(Theme.Color.background)

            Button(currentIndex == viewModel.draftItems.count - 1 ? "Continue" : "Next") {
                if currentIndex < viewModel.draftItems.count - 1 {
                    currentIndex += 1
                } else {
                    onFinished()
                }
            }
            .font(Theme.Font.body(16, weight: .medium))
            .disabled(!viewModel.draftItems.indices.contains(currentIndex) || viewModel.draftItems[currentIndex].category == nil)
            .tint(Theme.Color.accent)
            .padding()
        }
        .background(Theme.Color.background)
    }

    private func tagForm(index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(uiImage: viewModel.draftItems[index].image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Category")
                    .font(Theme.Font.body(15, weight: .medium))
                    .foregroundStyle(Theme.Color.primaryText)
                let columns = [GridItem(.adaptive(minimum: 90))]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(ItemCategory.allCases) { category in
                        Button(category.rawValue) {
                            viewModel.selectCategory(category, forItemAt: index)
                        }
                        .font(Theme.Font.body(14))
                        .buttonStyle(.bordered)
                        .tint(viewModel.draftItems[index].category == category ? Theme.Color.accent : Theme.Color.tertiaryText)
                    }
                }

                DisclosureGroup("More details (optional)") {
                    VStack(spacing: 8) {
                        TextField("Size", text: $viewModel.draftItems[index].size)
                            .textFieldStyle(.roundedBorder)
                        TextField("Color", text: $viewModel.draftItems[index].color)
                            .textFieldStyle(.roundedBorder)
                        TextField("Occasions (comma separated)", text: $viewModel.draftItems[index].occasionTags)
                            .textFieldStyle(.roundedBorder)
                        TextField("Caption", text: $viewModel.draftItems[index].caption)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .font(Theme.Font.body(15))
                .foregroundStyle(Theme.Color.primaryText)
                .tint(Theme.Color.accent)
            }
            .padding()
        }
        .background(Theme.Color.background)
    }
}
```

- [ ] **Step 3: Restyle the share screen**

Full new file content for `Closet/Closet/AddItem/ShareToClosetsView.swift`:

```swift
import SwiftUI
import PostgREST
import Supabase

struct ShareToClosetsView: View {
    @Bindable var viewModel: AddItemViewModel
    @State private var otherClosets: [Closet] = []
    @State private var isLoadingClosets = true
    @State private var closetsErrorMessage: String?
    let currentClosetID: UUID
    let ownerID: UUID
    let onDone: () -> Void

    private var isSaving: Bool {
        viewModel.draftItems.contains { $0.saveState == .saving }
    }

    private var allSaved: Bool {
        !viewModel.draftItems.isEmpty && viewModel.draftItems.allSatisfy { $0.saveState == .saved }
    }

    var body: some View {
        VStack {
            List {
                Section("Also share to") {
                    if isLoadingClosets {
                        ProgressView()
                    } else if let closetsErrorMessage {
                        Text(closetsErrorMessage)
                            .font(Theme.Font.body(14))
                            .foregroundStyle(.red)
                    } else if otherClosets.isEmpty {
                        Text("You're not in any other Closets")
                            .font(Theme.Font.body(14))
                            .foregroundStyle(Theme.Color.secondaryText)
                    } else {
                        ForEach(otherClosets) { closet in
                            Button {
                                toggle(closet.id)
                            } label: {
                                HStack {
                                    Text(closet.name)
                                        .font(Theme.Font.body(16))
                                    Spacer()
                                    if viewModel.shareToClosetIDs.contains(closet.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.Color.accent)
                                    }
                                }
                            }
                            .foregroundStyle(Theme.Color.primaryText)
                        }
                    }
                }
                .listRowBackground(Theme.Color.background)

                Section("Items") {
                    ForEach(Array(viewModel.draftItems.enumerated()), id: \.element.id) { index, draft in
                        HStack {
                            Text(draft.category?.rawValue ?? "Untagged")
                                .font(Theme.Font.body(16))
                                .foregroundStyle(Theme.Color.primaryText)
                            Spacer()
                            itemStatusView(index: index, state: draft.saveState)
                        }
                    }
                }
                .listRowBackground(Theme.Color.background)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)

            if allSaved {
                Button("Done") { onDone() }
                    .font(Theme.Font.body(16, weight: .medium))
                    .tint(Theme.Color.accent)
                    .padding()
            } else {
                Button(isSaving ? "Saving..." : "Save") {
                    Task { await viewModel.saveAll(currentClosetID: currentClosetID, ownerID: ownerID) }
                }
                .font(Theme.Font.body(16, weight: .medium))
                .disabled(isSaving)
                .tint(Theme.Color.accent)
                .padding()
            }
        }
        .background(Theme.Color.background)
        .task { await loadOtherClosets() }
    }

    private func toggle(_ closetID: UUID) {
        if viewModel.shareToClosetIDs.contains(closetID) {
            viewModel.shareToClosetIDs.remove(closetID)
        } else {
            viewModel.shareToClosetIDs.insert(closetID)
        }
    }

    private func loadOtherClosets() async {
        isLoadingClosets = true
        closetsErrorMessage = nil
        defer { isLoadingClosets = false }
        do {
            let all: [Closet] = try await SupabaseService.shared
                .from("closets")
                .select()
                .execute()
                .value
            otherClosets = all.filter { $0.id != currentClosetID }
        } catch {
            closetsErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func itemStatusView(index: Int, state: SaveState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(Theme.Color.tertiaryText)
        case .saving:
            ProgressView()
        case .saved:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Button {
                Task { await viewModel.save(itemAt: index, currentClosetID: currentClosetID, ownerID: ownerID) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise.circle.fill")
            }
            .foregroundStyle(.red)
            .help(message)
        }
    }
}
```

- [ ] **Step 4: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manually verify**

Run the full Add Item flow from a Closet: pick photos, tag each with a category (confirm the selected category chip turns sage, not blue) and optional details, then confirm the "Also share to" / save screen still saves items and shows per-item status (pending/saving/saved/failed with retry) correctly. New items should still appear in the Closet grid and My Clothes afterward.

- [ ] **Step 6: Commit**

```bash
git add Closet/Closet/AddItem/AddItemView.swift Closet/Closet/AddItem/PhotoTaggingView.swift Closet/Closet/AddItem/ShareToClosetsView.swift
git commit -m "Restyle Add Item flow"
```

---

### Task 7: Onboarding and Sign In

**Files:**
- Modify: `Closet/Closet/Onboarding/OnboardingView.swift`, `Closet/Closet/Auth/SignInView.swift`

**Interfaces:**
- Consumes: `Theme` (Task 1)
- Produces: nothing new

- [ ] **Step 1: Restyle Onboarding**

Full new file content for `Closet/Closet/Onboarding/OnboardingView.swift`:

```swift
import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    let userID: UUID
    let onComplete: () -> Void

    var body: some View {
        Form {
            Section("Your name") {
                TextField("Name", text: $viewModel.name)
                    .font(Theme.Font.body(16))
            }
            Section("Your usual sizes (optional)") {
                TextField("Top", text: $viewModel.topSize)
                    .font(Theme.Font.body(16))
                TextField("Bottom", text: $viewModel.bottomSize)
                    .font(Theme.Font.body(16))
                TextField("Shoe", text: $viewModel.shoeSize)
                    .font(Theme.Font.body(16))
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.body(14))
                    .foregroundStyle(.red)
            }
            Button(viewModel.isSaving ? "Saving..." : "Continue") {
                Task {
                    if await viewModel.save(userID: userID) {
                        onComplete()
                    }
                }
            }
            .font(Theme.Font.body(16, weight: .medium))
            .disabled(viewModel.isSaving)
            .tint(Theme.Color.accent)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Color.background)
    }
}
```

- [ ] **Step 2: Restyle Sign In**

Full new file content for `Closet/Closet/Auth/SignInView.swift`:

```swift
import SwiftUI
import AuthenticationServices
import CryptoKit

struct SignInView: View {
    let authViewModel: AuthViewModel
    @State private var currentNonce: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("Closet")
                .font(Theme.Font.headline(44))
                .foregroundStyle(Theme.Color.primaryText)

            SignInWithAppleButton(.signIn) { request in
                let nonce = randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName]
                request.nonce = sha256(nonce)
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 40)

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.background)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                errorMessage = "Could not read Apple ID credential"
                return
            }
            Task {
                do {
                    try await authViewModel.signInWithApple(idToken: idToken, nonce: nonce)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
```

`.frame(maxWidth: .infinity, maxHeight: .infinity)` is added so the bone background fills the whole screen — without it, the `VStack` (and its background) only sizes to its content, leaving the rest of the screen white.

- [ ] **Step 3: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manually verify**

Sign out (Profile tab, restyled in Task 8) and confirm the Sign In screen shows the bone background full-bleed with the serif "Closet" title. Sign in, and if routed to Onboarding (new account), confirm its form is restyled but saves correctly and proceeds into the app.

- [ ] **Step 5: Commit**

```bash
git add Closet/Closet/Onboarding/OnboardingView.swift Closet/Closet/Auth/SignInView.swift
git commit -m "Restyle Onboarding and Sign In"
```

---

### Task 8: Profile

**Files:**
- Modify: `Closet/Closet/Profile/ProfileView.swift`

**Interfaces:**
- Consumes: `Theme` (Task 1)
- Produces: nothing new

- [ ] **Step 1: Restyle the view**

Full new file content for `Closet/Closet/Profile/ProfileView.swift`:

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
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else {
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
                                                .foregroundStyle(Theme.Color.tertiaryText)
                                        }
                                    }
                                    .frame(width: 96, height: 96)
                                    .clipShape(Circle())

                                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                        Text(viewModel.isUploadingPhoto ? "Uploading..." : "Change Photo")
                                            .font(Theme.Font.body(14, weight: .medium))
                                    }
                                    .tint(Theme.Color.accent)
                                    .disabled(viewModel.isUploadingPhoto)
                                    .onChange(of: selectedPhoto) { _, newValue in
                                        Task { await loadAndUploadPhoto(newValue) }
                                    }
                                }
                                Spacer()
                            }
                        }
                        .listRowBackground(Theme.Color.background)

                        Section("Your name") {
                            TextField("Name", text: $viewModel.name)
                                .font(Theme.Font.body(16))
                        }
                        .listRowBackground(Theme.Color.background)

                        Section("Your usual sizes") {
                            TextField("Top", text: $viewModel.topSize)
                                .font(Theme.Font.body(16))
                            TextField("Bottom", text: $viewModel.bottomSize)
                                .font(Theme.Font.body(16))
                            TextField("Shoe", text: $viewModel.shoeSize)
                                .font(Theme.Font.body(16))
                        }
                        .listRowBackground(Theme.Color.background)

                        if let errorMessage = viewModel.errorMessage {
                            Section {
                                Text(errorMessage)
                                    .font(Theme.Font.body(14))
                                    .foregroundStyle(.red)
                            }
                            .listRowBackground(Theme.Color.background)
                        }

                        Section {
                            Button(viewModel.isSaving ? "Saving..." : "Save") {
                                Task { await viewModel.save(userID: userID) }
                            }
                            .font(Theme.Font.body(16, weight: .medium))
                            .disabled(viewModel.isSaving || !viewModel.hasLoadedProfile)
                            .tint(Theme.Color.accent)
                        }
                        .listRowBackground(Theme.Color.background)

                        Section("Blocked Users") {
                            if viewModel.blockedUsers.isEmpty {
                                Text("No blocked users")
                                    .font(Theme.Font.body(14))
                                    .foregroundStyle(Theme.Color.secondaryText)
                            } else {
                                ForEach(viewModel.blockedUsers) { blockedUser in
                                    HStack {
                                        Text(blockedUser.name)
                                            .font(Theme.Font.body(16))
                                        Spacer()
                                        Button("Unblock") {
                                            Task { await viewModel.unblock(blockedID: blockedUser.id, blockerID: userID) }
                                        }
                                        .font(Theme.Font.body(14, weight: .medium))
                                        .tint(Theme.Color.accent)
                                    }
                                }
                            }
                        }
                        .listRowBackground(Theme.Color.background)

                        Section {
                            Button("Sign Out") {
                                Task { await onSignedOut() }
                            }
                            .font(Theme.Font.body(16))
                            .foregroundStyle(Theme.Color.primaryText)
                        }
                        .listRowBackground(Theme.Color.background)

                        Section {
                            Button("Delete Account", role: .destructive) {
                                showingDeleteConfirmation = true
                            }
                            .font(Theme.Font.body(16))
                        }
                        .listRowBackground(Theme.Color.background)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.Color.background)
                }
            }
            .background(Theme.Color.background)
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
              let image = UIImage(data: data) else {
            viewModel.reportInvalidPhoto()
            return
        }
        await viewModel.uploadPhoto(image, userID: userID)
    }
}
```

Every Phase 8 behavior is preserved exactly — the `isLoading` gate, the `hasLoadedProfile` Save-button guard, and the `reportInvalidPhoto()` call on a bad photo pick are all still there, untouched. Only fonts/colors are added. The big 96pt avatar stays a bespoke `AsyncImage` + placeholder (not `OwnerBadge`, which is sized and bordered for small corner badges, not a hero profile photo).

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild -project Closet/Closet.xcodeproj -scheme Closet -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manually verify**

Open the Profile tab: confirm the whole app is now visually consistent end-to-end (tab bar, Closets, My Clothes, Item Detail, Add Item, Onboarding/Sign In, Profile all share the same bone background, sage accent, and Lora/DM Sans typography). Confirm editing name/sizes, changing photo, unblocking a blocked user, signing out, and deleting an account all still work exactly as in Phase 8 — this task changed no logic, only appearance.

- [ ] **Step 4: Commit**

```bash
git add Closet/Closet/Profile/ProfileView.swift
git commit -m "Restyle Profile"
```
