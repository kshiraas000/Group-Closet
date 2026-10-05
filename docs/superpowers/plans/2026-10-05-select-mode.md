# Select Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Photos-style multi-select on the Closet and My Clothes grids, with a bottom action bar to add to / remove from closets, bulk-edit tags, and delete — for the user's own pieces only.

**Architecture:** Selection state and bulk-edit merge rules are pure, Foundation-only value types (`GridSelection`, `BulkEdit`) so they can be tested with a `swiftc` harness — the Xcode project has no test target. Supabase writes live in one stateless `BulkItemActions` enum. Each grid view owns a `GridSelection` in `@State`, swaps its top bar while selecting, and shows a shared `SelectionActionBar`. Drag-across-tiles is a separate final task using an iOS 18 `UIGestureRecognizerRepresentable` that only begins on a horizontal drag, so vertical scrolling keeps working.

**Tech Stack:** SwiftUI (iOS 17 deployment target; drag-select is iOS 18+ and silently absent on 17), supabase-swift (PostgREST + Storage), Xcode 26 synchronized folders.

**Spec:** No separate spec doc — scope agreed in conversation on 2026-10-05:
- Long-press a tile in either grid enters Select mode; then taps toggle.
- Closet grid: other people's pieces are not selectable (dimmed).
- Action bar: Add to Closet, Remove from Closet, Edit Tags, Delete. **No Share, no Favorite** (Favorite comes in the Favorites phase).
- Remove from Closet: in a closet grid removes from *this* closet; in My Clothes asks which closet.
- Edit Tags (bulk): category, size, color are set only if the user filled them in; occasions are **appended**, never replace.
- Delete: confirmation, then delete rows, then storage objects (same order and reasoning as `ItemDetailViewModel.deleteItem`).
- Drag across tiles to select several, Photos-style (horizontal start) — last, separable task.
- Light haptic on selection changes.

## Global Constraints

- iOS deployment target stays **17.0**; any iOS 18 API must be behind `if #available(iOS 18.0, *)`.
- **No backend/migration changes.** Existing RLS already allows: owner INSERT/DELETE on `item_shares` (insert also requires closet membership), owner UPDATE of `(category, size, color, occasion_tags, caption)` on `items`, owner DELETE on `items` (cascades `item_photos`, `item_shares`), owner DELETE of own objects in `item-photos` storage.
- `items` UPDATE is column-scoped: never send `id`, `owner_id`, or `created_at` in an update payload or PostgREST returns a permission error.
- Use `Theme.Color.*` / `Theme.Font.*` for every color and font; no new colors except `.red` for destructive, matching existing code.
- New app source files go under `Closet/Closet/Selection/` — the project uses `PBXFileSystemSynchronizedRootGroup`, so files there are compiled into the app automatically; **do not edit `project.pbxproj`**.
- Test harness lives in `Closet/LogicTests/` (outside the synchronized `Closet/Closet/` folder so it is never compiled into the app).
- Commit messages: one short subject line, no trailers.
- Build check command (used throughout):
  `cd Closet && xcodebuild -project Closet.xcodeproj -scheme Closet -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'error:|\*\* BUILD'`
  Expected: `** BUILD SUCCEEDED **`

## Review Focus

1. **Filter/search changes while selecting** — a selected piece that gets filtered out of view must be dropped from the selection, so Delete never acts on pieces the user can't see. Pinned by `testRetainDropsHiddenIDs` (Task 1) and the `.onChange` wiring in Tasks 4 and 5.
2. **Long-press then release must not immediately toggle the tile back off** — the gesture setup must keep tap and long-press exclusive. Pinned by `testBeginSelectsExactlyOnce` (Task 1) plus manual QA step in Task 4.
3. **Adding to a closet the piece is already in** must not error on the `(item_id, closet_id)` primary key. Pinned by using `upsert(..., ignoreDuplicates: true)` in Task 2 and a manual QA step in Task 6.
4. **Bulk edit with every field left blank** must not fire any network writes or wipe existing values. Pinned by `testEmptyEditIsNoOp` and `testBlankFieldsLeaveValuesUntouched` (Task 1); Save disabled when `edit.isEmpty` (Task 3).
5. **Duplicate occasions on append** ("formal" added to a piece already tagged "Formal") must not produce duplicates. Pinned by `testAppendOccasionsDedupesCaseInsensitively` (Task 1).

---

## File Structure

| File | Responsibility |
|---|---|
| `Closet/Closet/Selection/GridSelection.swift` (create) | Pure selection state: active flag, selected IDs, toggle, retain, drag baseline. |
| `Closet/Closet/Selection/BulkEdit.swift` (create) | Pure bulk-edit value + merge rules + occasion parsing. |
| `Closet/Closet/Selection/BulkItemActions.swift` (create) | Supabase writes: delete, add/remove shares, apply bulk edit. |
| `Closet/Closet/Selection/SelectionChrome.swift` (create) | `SelectionActionBar` and `SelectionCheckmark` views. |
| `Closet/Closet/Selection/ClosetPickerSheet.swift` (create) | Sheet listing the user's closets to pick one. |
| `Closet/Closet/Selection/BulkEditView.swift` (create) | Sheet to build a `BulkEdit`. |
| `Closet/Closet/Selection/DragSelectGesture.swift` (create, Task 7) | iOS 18 horizontal-pan recognizer + tile-frame preference key. |
| `Closet/Closet/Closets/ClosetDetailView.swift` (modify) | Wire select mode into the closet grid. |
| `Closet/Closet/MyClothes/MyClothesView.swift` (modify) | Wire select mode into My Clothes. |
| `Closet/LogicTests/SelectionLogicTests.swift` (create) | Assertion tests for the two pure types. |
| `Closet/LogicTests/run.sh` (create) | Compiles pure files + tests with `swiftc` and runs them. |

---

### Task 1: Pure selection + bulk-edit logic with tests

**Files:**
- Create: `Closet/Closet/Selection/GridSelection.swift`
- Create: `Closet/Closet/Selection/BulkEdit.swift`
- Create: `Closet/LogicTests/SelectionLogicTests.swift`
- Create: `Closet/LogicTests/run.sh`

**Interfaces:**
- Consumes: `Item`, `ItemCategory` from `Closet/Closet/Models/Item.swift` (unchanged).
- Produces:
  - `struct GridSelection` with `isActive: Bool`, `selectedIDs: Set<UUID>`, `count: Int`, `begin(with: UUID)`, `toggle(_: UUID)`, `retain(_: Set<UUID>)`, `end()`, `beginDrag(on: UUID)`, `updateDrag(covering: Set<UUID>)`, `endDrag()`.
  - `struct BulkEdit` with `category: ItemCategory?`, `size: String`, `color: String`, `occasionsText: String`, `isEmpty: Bool`, `applied(to: Item) -> Item`, `static parseOccasions(_: String) -> [String]`.

- [ ] **Step 1: Write the test harness script**

`Closet/LogicTests/run.sh`:

```bash
#!/bin/bash
# The Xcode project has no test target, so the pure (Foundation-only) logic is
# compiled together with these assertion tests and run as a plain executable.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)/logic-tests"
xcrun swiftc -o "$out" \
  Closet/Models/Item.swift \
  Closet/Selection/GridSelection.swift \
  Closet/Selection/BulkEdit.swift \
  LogicTests/SelectionLogicTests.swift
"$out"
```

Run: `chmod +x Closet/LogicTests/run.sh`

- [ ] **Step 2: Write the failing tests**

`Closet/LogicTests/SelectionLogicTests.swift`:

```swift
import Foundation

var failures = 0
func check(_ condition: Bool, _ name: String, line: Int = #line) {
    if condition {
        print("PASS \(name)")
    } else {
        print("FAIL \(name) (line \(line))")
        failures += 1
    }
}

let a = UUID(), b = UUID(), c = UUID()

func makeItem(size: String? = "M", color: String? = "Black", occasions: [String] = ["Formal"]) -> Item {
    Item(id: a, ownerID: b, category: .dress, size: size, color: color,
         occasionTags: occasions, caption: "Slip dress", createdAt: Date(timeIntervalSince1970: 0))
}

// GridSelection

do {
    var s = GridSelection()
    s.begin(with: a)
    check(s.isActive && s.selectedIDs == [a], "testBeginSelectsExactlyOnce")
}
do {
    var s = GridSelection()
    s.begin(with: a)
    s.toggle(b)
    s.toggle(a)
    check(s.selectedIDs == [b] && s.isActive, "testToggleAddsAndRemoves")
}
do {
    var s = GridSelection()
    s.begin(with: a)
    s.toggle(a)
    check(s.isActive && s.count == 0, "testDeselectingLastStaysInSelectMode")
}
do {
    var s = GridSelection()
    s.begin(with: a)
    s.toggle(b)
    s.retain([b, c])
    check(s.selectedIDs == [b], "testRetainDropsHiddenIDs")
}
do {
    var s = GridSelection()
    s.begin(with: a)
    s.end()
    check(!s.isActive && s.selectedIDs.isEmpty, "testEndClears")
}
do {
    var s = GridSelection()
    s.toggle(a)
    check(!s.isActive && s.selectedIDs.isEmpty, "testToggleIgnoredWhenInactive")
}
do {
    // Drag starting on an unselected tile selects; shrinking the drag back
    // restores tiles it no longer covers to their pre-drag state.
    var s = GridSelection()
    s.begin(with: c)
    s.beginDrag(on: a)
    s.updateDrag(covering: [a, b])
    check(s.selectedIDs == [a, b, c], "testDragSelectsCoveredRange")
    s.updateDrag(covering: [a])
    check(s.selectedIDs == [a, c], "testDragShrinkRestoresBaseline")
    s.endDrag()
}
do {
    // Drag starting on a selected tile deselects.
    var s = GridSelection()
    s.begin(with: a)
    s.toggle(b)
    s.beginDrag(on: a)
    s.updateDrag(covering: [a, b])
    check(s.selectedIDs.isEmpty, "testDragFromSelectedDeselects")
    s.endDrag()
}

// BulkEdit

do {
    check(BulkEdit().isEmpty, "testEmptyEditIsNoOp")
    var e = BulkEdit()
    e.occasionsText = " , "
    check(e.isEmpty, "testWhitespaceOccasionsCountAsEmpty")
}
do {
    let item = makeItem()
    let result = BulkEdit().applied(to: item)
    check(result.size == "M" && result.color == "Black" && result.category == .dress
          && result.occasionTags == ["Formal"], "testBlankFieldsLeaveValuesUntouched")
}
do {
    var e = BulkEdit()
    e.category = .top
    e.size = "  S "
    e.color = "Red"
    let result = e.applied(to: makeItem())
    check(result.category == .top && result.size == "S" && result.color == "Red", "testFilledFieldsOverwrite")
    check(result.caption == "Slip dress" && result.id == a, "testCaptionAndIdentityPreserved")
}
do {
    var e = BulkEdit()
    e.occasionsText = "formal, Date night,date night"
    let result = e.applied(to: makeItem(occasions: ["Formal"]))
    check(result.occasionTags == ["Formal", "Date night"], "testAppendOccasionsDedupesCaseInsensitively")
}
do {
    check(BulkEdit.parseOccasions(" a, ,b ,") == ["a", "b"], "testParseOccasions")
}

if failures > 0 {
    print("\(failures) FAILED")
    exit(1)
}
print("ALL PASSED")
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `Closet/LogicTests/run.sh`
Expected: compile error — `cannot find 'GridSelection' in scope` (files don't exist yet).

- [ ] **Step 4: Implement `GridSelection`**

`Closet/Closet/Selection/GridSelection.swift`:

```swift
import Foundation

/// Photos-style select mode for an item grid. Which tiles are selectable is
/// the caller's call (only the user's own pieces) — this only tracks state.
/// Foundation-only so LogicTests/run.sh can compile it without the app.
struct GridSelection {
    private(set) var isActive = false
    private(set) var selectedIDs: Set<UUID> = []

    /// Selection before the current drag began, and whether that drag is
    /// selecting (started on an unselected tile) or deselecting.
    private var dragBaseline: Set<UUID>?
    private var dragSelects = true

    var count: Int { selectedIDs.count }

    /// Long-press entry: select mode starts with the pressed tile selected.
    mutating func begin(with id: UUID) {
        isActive = true
        selectedIDs = [id]
    }

    mutating func toggle(_ id: UUID) {
        guard isActive else { return }
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// Drops anything no longer visible (filtered out, deleted, unshared), so
    /// an action never touches pieces the user can't currently see.
    mutating func retain(_ visibleIDs: Set<UUID>) {
        selectedIDs.formIntersection(visibleIDs)
    }

    mutating func end() {
        isActive = false
        selectedIDs = []
        dragBaseline = nil
    }

    mutating func beginDrag(on id: UUID) {
        guard isActive else { return }
        dragBaseline = selectedIDs
        dragSelects = !selectedIDs.contains(id)
    }

    /// `covered` is every selectable tile between the drag's first tile and
    /// the one under the finger now. Recomputed from the baseline each time,
    /// so dragging back un-does tiles the drag no longer covers.
    mutating func updateDrag(covering covered: Set<UUID>) {
        guard let dragBaseline else { return }
        selectedIDs = dragSelects
            ? dragBaseline.union(covered)
            : dragBaseline.subtracting(covered)
    }

    mutating func endDrag() {
        dragBaseline = nil
    }
}
```

- [ ] **Step 5: Implement `BulkEdit`**

`Closet/Closet/Selection/BulkEdit.swift`:

```swift
import Foundation

/// A bulk tag edit across several pieces. Blank fields mean "leave as is" —
/// so bulk edit can set values but never clear them, which keeps an
/// accidental Save with empty fields harmless. Occasions are appended.
struct BulkEdit {
    var category: ItemCategory?
    var size: String = ""
    var color: String = ""
    var occasionsText: String = ""

    private var trimmedSize: String { size.trimmingCharacters(in: .whitespaces) }
    private var trimmedColor: String { color.trimmingCharacters(in: .whitespaces) }
    private var addedOccasions: [String] { Self.parseOccasions(occasionsText) }

    var isEmpty: Bool {
        category == nil && trimmedSize.isEmpty && trimmedColor.isEmpty && addedOccasions.isEmpty
    }

    func applied(to item: Item) -> Item {
        var result = item
        if let category { result.category = category }
        if !trimmedSize.isEmpty { result.size = trimmedSize }
        if !trimmedColor.isEmpty { result.color = trimmedColor }
        for occasion in addedOccasions
        where !result.occasionTags.contains(where: { $0.caseInsensitiveCompare(occasion) == .orderedSame }) {
            result.occasionTags.append(occasion)
        }
        return result
    }

    /// Same comma-separated rule AddItem and EditItem use.
    static func parseOccasions(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `Closet/LogicTests/run.sh`
Expected: every line `PASS …`, last line `ALL PASSED`, exit 0.

- [ ] **Step 7: Build the app**

Run the build check command from Global Constraints.
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add Closet/Closet/Selection/GridSelection.swift Closet/Closet/Selection/BulkEdit.swift Closet/LogicTests
git commit -m "Add grid selection and bulk edit logic with tests"
```

---

### Task 2: Bulk Supabase actions

**Files:**
- Create: `Closet/Closet/Selection/BulkItemActions.swift`

**Interfaces:**
- Consumes: `BulkEdit.applied(to:)` (Task 1), `BrowseItem` (`Models/BrowseItem.swift`), `SupabaseService.shared`.
- Produces: `enum BulkItemActions` with
  - `static func delete(_ items: [BrowseItem]) async throws`
  - `static func addShares(itemIDs: [UUID], closetID: UUID) async throws`
  - `static func removeShares(itemIDs: [UUID], closetID: UUID) async throws`
  - `static func apply(_ edit: BulkEdit, to items: [Item]) async throws`

There is no automated test for this task (it only talks to the network); it is verified by build here and by manual QA in Task 6.

- [ ] **Step 1: Implement**

`Closet/Closet/Selection/BulkItemActions.swift`:

```swift
import Foundation
import PostgREST
import Storage
import Supabase

/// Supabase writes for select mode. RLS only lets these succeed on the
/// caller's own items, which is also the only thing select mode can select.
enum BulkItemActions {
    private static var client: SupabaseClient { SupabaseService.shared }

    /// Rows first, then storage — same order and reason as
    /// ItemDetailViewModel.deleteItem: if the row delete fails nothing has
    /// changed; a dangling storage object is harmless, a dangling row is not.
    static func delete(_ items: [BrowseItem]) async throws {
        guard !items.isEmpty else { return }
        try await client
            .from("items")
            .delete()
            .in("id", values: items.map(\.id))
            .execute()
        let paths = items.compactMap(\.photoPath)
        if !paths.isEmpty {
            _ = try? await client.storage.from("item-photos").remove(paths: paths)
        }
    }

    /// ignoreDuplicates (ON CONFLICT DO NOTHING) so pieces already in the
    /// closet don't trip the (item_id, closet_id) primary key. DO NOTHING
    /// needs only INSERT privilege, unlike DO UPDATE.
    static func addShares(itemIDs: [UUID], closetID: UUID) async throws {
        guard !itemIDs.isEmpty else { return }
        struct NewShare: Encodable {
            let itemID: UUID
            let closetID: UUID
            enum CodingKeys: String, CodingKey {
                case itemID = "item_id"
                case closetID = "closet_id"
            }
        }
        try await client
            .from("item_shares")
            .upsert(
                itemIDs.map { NewShare(itemID: $0, closetID: closetID) },
                onConflict: "item_id,closet_id",
                ignoreDuplicates: true
            )
            .execute()
    }

    static func removeShares(itemIDs: [UUID], closetID: UUID) async throws {
        guard !itemIDs.isEmpty else { return }
        try await client
            .from("item_shares")
            .delete()
            .eq("closet_id", value: closetID)
            .in("item_id", values: itemIDs)
            .execute()
    }

    /// One update per item: appended occasions make each row's new value
    /// different. Only the column-granted fields are sent (see the
    /// tighten_items_edit_delete migration).
    static func apply(_ edit: BulkEdit, to items: [Item]) async throws {
        guard !edit.isEmpty else { return }
        struct ItemUpdate: Encodable {
            let category: ItemCategory
            let size: String?
            let color: String?
            let occasionTags: [String]
            enum CodingKeys: String, CodingKey {
                case category, size, color
                case occasionTags = "occasion_tags"
            }
        }
        for item in items {
            let updated = edit.applied(to: item)
            try await client
                .from("items")
                .update(ItemUpdate(
                    category: updated.category,
                    size: updated.size,
                    color: updated.color,
                    occasionTags: updated.occasionTags
                ))
                .eq("id", value: item.id)
                .execute()
        }
    }
}
```

- [ ] **Step 2: Build**

Run the build check command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Closet/Closet/Selection/BulkItemActions.swift
git commit -m "Add bulk item actions for select mode"
```

---

### Task 3: Shared select-mode UI pieces

**Files:**
- Create: `Closet/Closet/Selection/SelectionChrome.swift`
- Create: `Closet/Closet/Selection/ClosetPickerSheet.swift`
- Create: `Closet/Closet/Selection/BulkEditView.swift`

**Interfaces:**
- Consumes: `BulkEdit` (Task 1), `Closet` model, `Theme`.
- Produces:
  - `struct SelectionCheckmark: View` — `init(isSelected: Bool)`
  - `struct SelectionActionBar: View` — `init(count: Int, removeTitle: String, onAdd: @escaping () -> Void, onRemove: @escaping () -> Void, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void)`
  - `struct SelectionTopBar: View` — `init(count: Int, onDone: @escaping () -> Void)`
  - `struct ClosetPickerSheet: View` — `init(title: String, excludingClosetID: UUID?, onPick: @escaping (Closet) -> Void)`
  - `struct BulkEditView: View` — `init(count: Int, onSave: @escaping (BulkEdit) async -> Bool)`

- [ ] **Step 1: Implement `SelectionChrome.swift`**

```swift
import SwiftUI

/// Bottom-trailing tick on a selected tile, Photos-style.
struct SelectionCheckmark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(isSelected ? Theme.Color.accent : .white, isSelected ? .white : .clear)
            .shadow(color: .black.opacity(0.3), radius: 2)
            .padding(6)
    }
}

/// Replaces a grid screen's normal top bar while selecting.
struct SelectionTopBar: View {
    let count: Int
    let onDone: () -> Void

    var body: some View {
        HStack {
            Text(count == 0 ? "Select Items" : "\(count) Selected")
                .font(Theme.Font.body(15, weight: .medium))
                .foregroundStyle(Theme.Color.primaryText)
            Spacer()
            Button("Done", action: onDone)
                .font(Theme.Font.body(15, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct SelectionActionBar: View {
    let count: Int
    let removeTitle: String
    let onAdd: () -> Void
    let onRemove: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            action("Add to Closet", systemImage: "plus.rectangle.on.rectangle", action: onAdd)
            action(removeTitle, systemImage: "minus.rectangle", action: onRemove)
            action("Edit Tags", systemImage: "tag", action: onEdit)
            action("Delete", systemImage: "trash", tint: .red, action: onDelete)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Theme.Color.background)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Color.divider).frame(height: 0.5)
        }
        .disabled(count == 0)
        .opacity(count == 0 ? 0.4 : 1)
    }

    private func action(
        _ title: String,
        systemImage: String,
        tint: Color = Theme.Color.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                Text(title)
                    .font(Theme.Font.body(10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Implement `ClosetPickerSheet.swift`**

```swift
import PostgREST
import Supabase
import SwiftUI

/// Lists the closets the user belongs to (RLS scopes `closets` to members)
/// and hands back the one they tap.
struct ClosetPickerSheet: View {
    let title: String
    let excludingClosetID: UUID?
    let onPick: (Closet) -> Void

    @State private var closets: [Closet] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Theme.Color.background)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.body(14))
                        .foregroundStyle(.red)
                        .listRowBackground(Theme.Color.background)
                } else if closets.isEmpty {
                    Text(excludingClosetID == nil ? "You're not in any Closets yet" : "You're not in any other Closets")
                        .font(Theme.Font.body(14))
                        .foregroundStyle(Theme.Color.secondaryText)
                        .listRowBackground(Theme.Color.background)
                } else {
                    ForEach(closets) { closet in
                        Button {
                            dismiss()
                            onPick(closet)
                        } label: {
                            Text(closet.name)
                                .font(Theme.Font.body(16))
                                .foregroundStyle(Theme.Color.primaryText)
                        }
                        .listRowBackground(Theme.Color.background)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Color.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(Theme.Color.accent)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            let all: [Closet] = try await SupabaseService.shared
                .from("closets")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            closets = all.filter { $0.id != excludingClosetID }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 3: Implement `BulkEditView.swift`**

```swift
import SwiftUI

struct BulkEditView: View {
    let count: Int
    let onSave: (BulkEdit) async -> Bool

    @State private var edit = BulkEdit()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Only the fields you fill in change. Occasions are added to each piece's existing ones.")
                        .font(Theme.Font.body(13))
                        .foregroundStyle(Theme.Color.secondaryText)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Category")
                            .font(Theme.Font.body(15, weight: .medium))
                            .foregroundStyle(Theme.Color.primaryText)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                            ForEach(ItemCategory.allCases) { category in
                                chip(category)
                            }
                        }
                    }

                    VStack(spacing: 8) {
                        TextField("Size", text: $edit.size).textFieldStyle(.roundedBorder)
                        TextField("Color", text: $edit.color).textFieldStyle(.roundedBorder)
                        TextField("Add occasions (comma separated)", text: $edit.occasionsText)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Font.body(14))
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .background(Theme.Color.background)
            .navigationTitle("Edit \(count) Piece\(count == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(Theme.Color.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || edit.isEmpty)
                    .tint(Theme.Color.accent)
                }
            }
        }
    }

    /// Tapping the selected category again un-sets it ("leave as is").
    private func chip(_ category: ItemCategory) -> some View {
        let isSelected = edit.category == category
        return Button {
            edit.category = isSelected ? nil : category
        } label: {
            Text(category.rawValue)
                .font(Theme.Font.body(14, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Theme.Color.background : Theme.Color.primaryText.opacity(0.75))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Theme.Color.accent : Theme.Color.primaryText.opacity(0.06))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let success = await onSave(edit)
        isSaving = false
        if success {
            dismiss()
        } else {
            errorMessage = "Something went wrong. Please try again."
        }
    }
}
```

- [ ] **Step 4: Build**

Run the build check command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Closet/Closet/Selection/SelectionChrome.swift Closet/Closet/Selection/ClosetPickerSheet.swift Closet/Closet/Selection/BulkEditView.swift
git commit -m "Add select mode bars, closet picker and bulk edit sheet"
```

---

### Task 4: Select mode in the closet grid

**Files:**
- Modify: `Closet/Closet/Closets/ClosetDetailView.swift`

**Interfaces:**
- Consumes: `GridSelection` (Task 1), `BulkItemActions` (Task 2), `SelectionTopBar`, `SelectionActionBar`, `SelectionCheckmark`, `ClosetPickerSheet`, `BulkEditView` (Task 3).
- Produces: nothing used by later tasks except the tile structure Task 7 attaches frames to (`itemCell(_:)` stays the per-tile view).

Current state to know: the grid `ForEach` wraps each `itemCell(browseItem)` in a `Button { openDetail(for:) }` with `.buttonStyle(.plain)`; `itemCell` ends with `.clipped().contentShape(Rectangle()).overlay(alignment: .bottomLeading) { OwnerBadge… }`. `topBar` holds back button, ••• menu and `+`. The body's root is `VStack(spacing: 0) { topBar; ScrollView {…} }`.

- [ ] **Step 1: Add state**

Below `@State private var detailContext: ItemDetailContext?` add:

```swift
    @State private var selection = GridSelection()
    @State private var showingBulkDeleteConfirmation = false
    @State private var showingBulkEdit = false
    @State private var showingAddToClosetPicker = false
    @State private var showingBulkActionError = false
```

- [ ] **Step 2: Swap the top bar and add the action bar**

Replace the body's opening `VStack(spacing: 0) {\n            topBar` with:

```swift
        VStack(spacing: 0) {
            if selection.isActive {
                SelectionTopBar(count: selection.count) { selection.end() }
            } else {
                topBar
            }
```

and immediately after the `ScrollView { … }` closing brace (still inside the root `VStack`), add:

```swift
            if selection.isActive {
                SelectionActionBar(
                    count: selection.count,
                    removeTitle: "Remove",
                    onAdd: { showingAddToClosetPicker = true },
                    onRemove: { Task { await removeSelectedFromThisCloset() } },
                    onEdit: { showingBulkEdit = true },
                    onDelete: { showingBulkDeleteConfirmation = true }
                )
            }
```

- [ ] **Step 3: Replace the tile Button with tap + long-press**

A `Button` fires its action on release even after a long hold, which would toggle the just-selected tile straight back off. Replace the grid's `ForEach` body:

```swift
                            ForEach(viewModel.filteredItems) { browseItem in
                                Button {
                                    openDetail(for: browseItem)
                                } label: {
                                    itemCell(browseItem)
                                }
                                .buttonStyle(.plain)
                            }
```

with:

```swift
                            ForEach(viewModel.filteredItems) { browseItem in
                                // Tap and long-press as separate gestures, not a
                                // Button: a Button also fires on release after a
                                // long hold, un-selecting the tile it just selected.
                                itemCell(browseItem)
                                    .onTapGesture { tileTapped(browseItem) }
                                    .onLongPressGesture(minimumDuration: 0.35) {
                                        if !selection.isActive, isOwned(browseItem) {
                                            selection.begin(with: browseItem.id)
                                        }
                                    }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction(named: "Select") {
                                        if !selection.isActive, isOwned(browseItem) {
                                            selection.begin(with: browseItem.id)
                                        }
                                    }
                            }
```

- [ ] **Step 4: Show selection state on the tile**

In `itemCell(_:)`, append after the existing `.overlay(alignment: .bottomLeading) { … }` (so it becomes the last modifiers of the returned view):

```swift
            .overlay(alignment: .bottomTrailing) {
                if selection.isActive, isOwned(browseItem) {
                    SelectionCheckmark(isSelected: selection.selectedIDs.contains(browseItem.id))
                }
            }
            // Other people's pieces can't be selected in select mode.
            .opacity(selection.isActive && !isOwned(browseItem) ? 0.35 : 1)
```

- [ ] **Step 5: Add helpers and actions**

Add these methods next to `openDetail(for:)`:

```swift
    private func isOwned(_ browseItem: BrowseItem) -> Bool {
        browseItem.item.ownerID == userID
    }

    private func tileTapped(_ browseItem: BrowseItem) {
        if selection.isActive {
            if isOwned(browseItem) { selection.toggle(browseItem.id) }
        } else {
            openDetail(for: browseItem)
        }
    }

    private var selectedItems: [BrowseItem] {
        viewModel.items.filter { selection.selectedIDs.contains($0.id) }
    }

    /// Runs a bulk action, then reloads and leaves select mode on success.
    private func runBulk(_ action: () async throws -> Void) async {
        do {
            try await action()
            selection.end()
        } catch {
            showingBulkActionError = true
        }
        await viewModel.load(closetID: closet.id)
    }

    private func removeSelectedFromThisCloset() async {
        let ids = Array(selection.selectedIDs)
        await runBulk { try await BulkItemActions.removeShares(itemIDs: ids, closetID: closet.id) }
    }
```

- [ ] **Step 6: Wire sheets, dialog, haptics and pruning**

Add after the existing `.sheet(isPresented: $showingMembers) { membersSheet }`:

```swift
        .sheet(isPresented: $showingAddToClosetPicker) {
            ClosetPickerSheet(title: "Add to Closet", excludingClosetID: closet.id) { target in
                let ids = Array(selection.selectedIDs)
                Task { await runBulk { try await BulkItemActions.addShares(itemIDs: ids, closetID: target.id) } }
            }
        }
        .sheet(isPresented: $showingBulkEdit) {
            BulkEditView(count: selection.count) { edit in
                let items = selectedItems.map(\.item)
                do {
                    try await BulkItemActions.apply(edit, to: items)
                    selection.end()
                    await viewModel.load(closetID: closet.id)
                    return true
                } catch {
                    return false
                }
            }
        }
        .confirmationDialog(
            "Delete \(selection.count) piece\(selection.count == 1 ? "" : "s")?",
            isPresented: $showingBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let items = selectedItems
                Task { await runBulk { try await BulkItemActions.delete(items) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes them from every closet and can't be undone.")
        }
        .alert("Something went wrong. Please try again.", isPresented: $showingBulkActionError) {
            Button("OK") {}
        }
        .sensoryFeedback(.selection, trigger: selection.selectedIDs)
        .onChange(of: viewModel.filteredItems.map(\.id)) { _, visible in
            selection.retain(Set(visible))
        }
```

- [ ] **Step 7: Build**

Run the build check command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Re-run logic tests**

Run: `Closet/LogicTests/run.sh` — Expected: `ALL PASSED`

- [ ] **Step 9: Commit**

```bash
git add Closet/Closet/Closets/ClosetDetailView.swift
git commit -m "Add select mode to the closet grid"
```

---

### Task 5: Select mode in My Clothes

**Files:**
- Modify: `Closet/Closet/MyClothes/MyClothesView.swift`

**Interfaces:**
- Consumes: same as Task 4.
- Produces: nothing for later tasks except `itemCell(_:)` as the per-tile view (Task 7).

Current state to know: body is `NavigationStack { ScrollView { VStack { header; SearchField; … grid } } .background … }`. Every item here is the user's own, so every tile is selectable. "Remove from Closet" must ask which closet.

- [ ] **Step 1: Add state**

Below `@State private var showingFilters = false` add:

```swift
    @State private var selection = GridSelection()
    @State private var showingBulkDeleteConfirmation = false
    @State private var showingBulkEdit = false
    @State private var showingAddToClosetPicker = false
    @State private var showingRemoveFromClosetPicker = false
    @State private var showingBulkActionError = false
```

- [ ] **Step 2: Put the bars around the scroll view**

Wrap the `ScrollView { … }` (inside `NavigationStack`) so the structure becomes:

```swift
        NavigationStack {
            VStack(spacing: 0) {
                if selection.isActive {
                    SelectionTopBar(count: selection.count) { selection.end() }
                }

                ScrollView {
                    // … existing content unchanged …
                }

                if selection.isActive {
                    SelectionActionBar(
                        count: selection.count,
                        removeTitle: "Remove from…",
                        onAdd: { showingAddToClosetPicker = true },
                        onRemove: { showingRemoveFromClosetPicker = true },
                        onEdit: { showingBulkEdit = true },
                        onDelete: { showingBulkDeleteConfirmation = true }
                    )
                }
            }
            .background(Theme.Color.background)
            // … the existing modifiers that were on ScrollView (.toolbar(.hidden…),
            // .task, .refreshable, .sheet(filters), .fullScreenCover) move here,
            // except .refreshable which must stay on the ScrollView itself …
```

Keep `.refreshable { … }` attached directly to the `ScrollView` (refreshable only works on the scrollable view). Move the remaining modifiers to the `VStack`.

- [ ] **Step 3: Replace the tile Button with tap + long-press**

Replace the grid `ForEach` body exactly as in Task 4 Step 3 but without ownership checks:

```swift
                            ForEach(viewModel.filteredItems) { browseItem in
                                // Tap and long-press as separate gestures, not a
                                // Button: a Button also fires on release after a
                                // long hold, un-selecting the tile it just selected.
                                itemCell(browseItem)
                                    .onTapGesture { tileTapped(browseItem) }
                                    .onLongPressGesture(minimumDuration: 0.35) {
                                        if !selection.isActive { selection.begin(with: browseItem.id) }
                                    }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction(named: "Select") {
                                        if !selection.isActive { selection.begin(with: browseItem.id) }
                                    }
                            }
```

- [ ] **Step 4: Checkmark on the tile**

In `itemCell(_:)`, after `.contentShape(Rectangle())` append:

```swift
            .overlay(alignment: .bottomTrailing) {
                if selection.isActive {
                    SelectionCheckmark(isSelected: selection.selectedIDs.contains(browseItem.id))
                }
            }
```

- [ ] **Step 5: Helpers**

Add next to `openDetail(for:)`:

```swift
    private func tileTapped(_ browseItem: BrowseItem) {
        if selection.isActive {
            selection.toggle(browseItem.id)
        } else {
            openDetail(for: browseItem)
        }
    }

    private var selectedItems: [BrowseItem] {
        viewModel.items.filter { selection.selectedIDs.contains($0.id) }
    }

    /// Runs a bulk action, then reloads and leaves select mode on success.
    private func runBulk(_ action: () async throws -> Void) async {
        do {
            try await action()
            selection.end()
        } catch {
            showingBulkActionError = true
        }
        await viewModel.load(userID: userID)
    }
```

- [ ] **Step 6: Sheets, dialog, haptics, pruning**

Add to the `VStack`'s modifier chain (next to the existing `.sheet(isPresented: $showingFilters)`):

```swift
            .sheet(isPresented: $showingAddToClosetPicker) {
                ClosetPickerSheet(title: "Add to Closet", excludingClosetID: nil) { target in
                    let ids = Array(selection.selectedIDs)
                    Task { await runBulk { try await BulkItemActions.addShares(itemIDs: ids, closetID: target.id) } }
                }
            }
            .sheet(isPresented: $showingRemoveFromClosetPicker) {
                ClosetPickerSheet(title: "Remove from Closet", excludingClosetID: nil) { target in
                    let ids = Array(selection.selectedIDs)
                    Task { await runBulk { try await BulkItemActions.removeShares(itemIDs: ids, closetID: target.id) } }
                }
            }
            .sheet(isPresented: $showingBulkEdit) {
                BulkEditView(count: selection.count) { edit in
                    let items = selectedItems.map(\.item)
                    do {
                        try await BulkItemActions.apply(edit, to: items)
                        selection.end()
                        await viewModel.load(userID: userID)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            .confirmationDialog(
                "Delete \(selection.count) piece\(selection.count == 1 ? "" : "s")?",
                isPresented: $showingBulkDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    let items = selectedItems
                    Task { await runBulk { try await BulkItemActions.delete(items) } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes them from every closet and can't be undone.")
            }
            .alert("Something went wrong. Please try again.", isPresented: $showingBulkActionError) {
                Button("OK") {}
            }
            .sensoryFeedback(.selection, trigger: selection.selectedIDs)
            .onChange(of: viewModel.filteredItems.map(\.id)) { _, visible in
                selection.retain(Set(visible))
            }
```

- [ ] **Step 7: Build and test**

Run the build check command → `** BUILD SUCCEEDED **`; run `Closet/LogicTests/run.sh` → `ALL PASSED`.

- [ ] **Step 8: Commit**

```bash
git add Closet/Closet/MyClothes/MyClothesView.swift
git commit -m "Add select mode to My Clothes"
```

---

### Task 6: Manual QA pass (Tasks 1–5)

No code. Run on a simulator or device signed in with two accounts sharing one closet (account B adds 2 pieces). Fix anything that fails before Task 7; each fix is its own commit.

- [ ] Long-press your own tile in a closet → select mode, tile ticked, one haptic; release does **not** untick it.
- [ ] Long-press another member's tile → nothing happens. In select mode their tiles are dimmed and taps do nothing.
- [ ] Tap tiles → toggle; counter in top bar updates; deselect all → "Select Items", action bar disabled.
- [ ] Done → normal top bar, back button and ••• menu work; tapping a tile opens item detail again.
- [ ] Select 2, type a search that hides one → counter drops to 1.
- [ ] Remove (closet grid) → pieces vanish from this closet, still present in My Clothes.
- [ ] Add to Closet → pick another closet → pieces appear there. Repeat with a piece already in that closet → no error.
- [ ] Edit Tags with all fields blank → Save disabled. Set size "S" + occasion "formal" on 2 pieces where one already has "Formal" → both size S, no duplicate occasion, captions unchanged.
- [ ] Delete 2 → confirmation → gone from every closet and My Clothes.
- [ ] My Clothes: same flows; "Remove from…" asks which closet.
- [ ] Airplane mode → Delete → "Something went wrong" alert, stays in select mode, nothing lost.
- [ ] Light and dark mode: checkmarks and action bar readable.

---

### Task 7: Drag across tiles to select (iOS 18+)

**Files:**
- Create: `Closet/Closet/Selection/DragSelectGesture.swift`
- Modify: `Closet/Closet/Closets/ClosetDetailView.swift`
- Modify: `Closet/Closet/MyClothes/MyClothesView.swift`

**Interfaces:**
- Consumes: `GridSelection.beginDrag(on:)`, `updateDrag(covering:)`, `endDrag()` (Task 1); `itemCell(_:)` and `selection` state (Tasks 4–5).
- Produces: `TileFramesKey` preference key, `.reportTileFrame(id:)` view modifier, `DragSelectGesture` (iOS 18), `GridDragSelect.coveredIDs(...)`.

Why UIKit: a SwiftUI `DragGesture` inside a `ScrollView` wins over the scroll view's pan and blocks vertical scrolling. A `UIPanGestureRecognizer` whose delegate refuses to begin unless the initial motion is horizontal lets vertical drags fall through to scrolling — exactly how Photos behaves. `UIGestureRecognizerRepresentable` (iOS 18) is the supported bridge; on iOS 17 the gesture is simply not attached.

- [ ] **Step 1: Add the covered-range rule to the tests (failing)**

Append to `Closet/LogicTests/SelectionLogicTests.swift`, **above** the final `if failures > 0` block:

```swift
// GridDragSelect

do {
    let order = [a, b, c]
    let covered = GridDragSelect.coveredIDs(order: order, from: c, to: a, selectable: [a, c])
    check(covered == [a, c], "testCoveredRangeIsOrderIndependentAndSkipsUnselectable")
    check(GridDragSelect.coveredIDs(order: order, from: a, to: UUID(), selectable: [a]) == [],
          "testCoveredRangeEmptyForUnknownID")
}
```

Add `Closet/Selection/GridDragSelect.swift \` to the `swiftc` file list in `Closet/LogicTests/run.sh` (after `BulkEdit.swift`).

Run: `Closet/LogicTests/run.sh` — Expected: fails to compile, `cannot find 'GridDragSelect'`.

- [ ] **Step 2: Implement the pure range rule**

Create `Closet/Closet/Selection/GridDragSelect.swift`:

```swift
import Foundation

enum GridDragSelect {
    /// Every selectable id between `from` and `to` (inclusive) in grid order,
    /// whichever direction the finger went. Empty if either id is unknown.
    static func coveredIDs(order: [UUID], from: UUID, to: UUID, selectable: Set<UUID>) -> Set<UUID> {
        guard let start = order.firstIndex(of: from), let end = order.firstIndex(of: to) else { return [] }
        return Set(order[min(start, end)...max(start, end)]).intersection(selectable)
    }
}
```

Run: `Closet/LogicTests/run.sh` — Expected: `ALL PASSED`.

- [ ] **Step 3: Implement the gesture and frame reporting**

Create `Closet/Closet/Selection/DragSelectGesture.swift`:

```swift
import SwiftUI
import UIKit

/// Each tile's frame in the grid's coordinate space, so a drag location can
/// be mapped back to the tile under the finger.
struct TileFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func reportTileFrame(id: UUID, in space: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: TileFramesKey.self, value: [id: geo.frame(in: .named(space))])
        })
    }
}

/// Pan that only begins when the first motion is mostly horizontal, so
/// vertical drags still scroll the grid (the Photos behaviour).
@available(iOS 18.0, *)
struct DragSelectGesture: UIGestureRecognizerRepresentable {
    let coordinateSpace: String
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(context.converter.location(in: .named(coordinateSpace)))
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }
}
```

If the compiler rejects `CoordinateSpaceConverter` as the parameter type, use `UIGestureRecognizerRepresentableCoordinateSpaceConverter` (the SDK's concrete type; verified in the iOS 26 SDK swiftinterface on 2026-10-05).

- [ ] **Step 4: Wire into `ClosetDetailView`**

Add state:

```swift
    @State private var tileFrames: [UUID: CGRect] = [:]
    @State private var dragAnchorID: UUID?
```

On the `LazyVGrid` add (after its closing brace):

```swift
                        .coordinateSpace(.named("grid"))
                        .onPreferenceChange(TileFramesKey.self) { tileFrames = $0 }
                        .modifier(DragSelectModifier(
                            isEnabled: selection.isActive,
                            onChanged: dragChanged,
                            onEnded: dragEnded
                        ))
```

In the `ForEach`, add `.reportTileFrame(id: browseItem.id, in: "grid")` after `itemCell(browseItem)`.

Add methods:

```swift
    private func dragChanged(_ location: CGPoint) {
        guard let id = tileFrames.first(where: { $0.value.contains(location) })?.key else { return }
        if dragAnchorID == nil {
            guard let tile = viewModel.filteredItems.first(where: { $0.id == id }), isOwned(tile) else { return }
            dragAnchorID = id
            selection.beginDrag(on: id)
        }
        guard let anchor = dragAnchorID else { return }
        let order = viewModel.filteredItems.map(\.id)
        let selectable = Set(viewModel.filteredItems.filter(isOwned).map(\.id))
        selection.updateDrag(covering: GridDragSelect.coveredIDs(order: order, from: anchor, to: id, selectable: selectable))
    }

    private func dragEnded() {
        dragAnchorID = nil
        selection.endDrag()
    }
```

Add the availability-gating modifier to `DragSelectGesture.swift`:

```swift
/// Attaches DragSelectGesture on iOS 18+ while select mode is on; a no-op
/// otherwise (tap-to-select still works everywhere).
struct DragSelectModifier: ViewModifier {
    let isEnabled: Bool
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), isEnabled {
            content.gesture(DragSelectGesture(coordinateSpace: "grid", onChanged: onChanged, onEnded: onEnded))
        } else {
            content
        }
    }
}
```

- [ ] **Step 5: Wire into `MyClothesView`**

Same as Step 4 (state, `LazyVGrid` modifiers, `.reportTileFrame`), with these methods (every tile is selectable):

```swift
    private func dragChanged(_ location: CGPoint) {
        guard let id = tileFrames.first(where: { $0.value.contains(location) })?.key else { return }
        if dragAnchorID == nil {
            dragAnchorID = id
            selection.beginDrag(on: id)
        }
        guard let anchor = dragAnchorID else { return }
        let order = viewModel.filteredItems.map(\.id)
        selection.updateDrag(covering: GridDragSelect.coveredIDs(order: order, from: anchor, to: id, selectable: Set(order)))
    }

    private func dragEnded() {
        dragAnchorID = nil
        selection.endDrag()
    }
```

- [ ] **Step 6: Build and test**

Run the build check command → `** BUILD SUCCEEDED **`; `Closet/LogicTests/run.sh` → `ALL PASSED`.

- [ ] **Step 7: Manual QA**

- [ ] In select mode, drag sideways from an unselected tile across 4 tiles → all 4 tick; drag back over 2 → those 2 untick.
- [ ] Drag sideways starting on a selected tile → covered tiles untick.
- [ ] Vertical drag in select mode still scrolls the grid.
- [ ] Out of select mode, sideways drags do nothing; swipe-back from the left edge still pops the closet.
- [ ] Closet grid: drag across another member's tiles never selects them.

- [ ] **Step 8: Commit**

```bash
git add Closet/Closet/Selection/GridDragSelect.swift Closet/Closet/Selection/DragSelectGesture.swift Closet/Closet/Closets/ClosetDetailView.swift Closet/Closet/MyClothes/MyClothesView.swift Closet/LogicTests
git commit -m "Add drag-across-tiles selection"
```
