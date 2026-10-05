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

// GridDragSelect

do {
    let order = [a, b, c]
    let covered = GridDragSelect.coveredIDs(order: order, from: c, to: a, selectable: [a, c])
    check(covered == [a, c], "testCoveredRangeIsOrderIndependentAndSkipsUnselectable")
    check(GridDragSelect.coveredIDs(order: order, from: a, to: UUID(), selectable: [a]) == [],
          "testCoveredRangeEmptyForUnknownID")
}

if failures > 0 {
    print("\(failures) FAILED")
    exit(1)
}
print("ALL PASSED")
