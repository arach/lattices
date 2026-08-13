import XCTest
@testable import Lattices

/// Pure-model coverage for the shared right-click movement menu used by
/// Desktop Inventory and Studio: display cycling/wrap, current-display
/// handling, single-display hiding, multi-selection titles and targeting,
/// and truthful receipt summaries.
final class WindowMoveMenuModelTests: XCTestCase {
    private func display(_ index: Int, name: String? = nil, current: Bool = false) -> WindowMoveMenuModel.Display {
        WindowMoveMenuModel.Display(index: index, name: name ?? "Display \(index + 1)", isCurrent: current)
    }

    private func target(_ wid: UInt32) -> WindowMoveMenuModel.Target {
        WindowMoveMenuModel.Target(wid: wid, pid: Int32(wid) + 1000)
    }

    // MARK: - Availability

    func testSingleDisplayHidesMovement() {
        let model = WindowMoveMenuModel(displays: [display(0, current: true)], targets: [target(1)])
        XCTAssertFalse(model.isAvailable)
        XCTAssertNil(model.nextDisplay)
        XCTAssertFalse(model.includesPlacement)
    }

    func testNoTargetsHidesMovement() {
        let model = WindowMoveMenuModel(displays: [display(0, current: true), display(1)], targets: [])
        XCTAssertFalse(model.isAvailable)
        XCTAssertNil(model.nextDisplay)
    }

    func testTwoDisplaysShowMovement() {
        let model = WindowMoveMenuModel(displays: [display(0, current: true), display(1)], targets: [target(1)])
        XCTAssertTrue(model.isAvailable)
        XCTAssertTrue(model.includesPlacement)
    }

    // MARK: - Next-display cycling

    func testNextDisplayStepsThroughTopology() {
        let model = WindowMoveMenuModel(
            displays: [display(0), display(1, current: true), display(2)],
            targets: [target(1)]
        )
        XCTAssertEqual(model.nextDisplay?.index, 2)
    }

    func testNextDisplayWrapsFromLastToFirst() {
        let model = WindowMoveMenuModel(
            displays: [display(0), display(1), display(2, current: true)],
            targets: [target(1)]
        )
        XCTAssertEqual(model.nextDisplay?.index, 0)
    }

    func testNextDisplayFallsBackToFirstWhenAnchorUnresolved() {
        // No display is marked current (anchor could not be resolved) —
        // cycling still yields a deterministic target.
        let model = WindowMoveMenuModel(displays: [display(0), display(1)], targets: [target(1)])
        XCTAssertEqual(model.nextDisplay?.index, 0)
    }

    func testCurrentDisplayIsMarked() {
        let model = WindowMoveMenuModel(
            displays: [display(0), display(1, current: true)],
            targets: [target(1)]
        )
        XCTAssertEqual(model.currentDisplay?.index, 1)
    }

    // MARK: - Titles

    func testSingleWindowTitles() {
        let model = WindowMoveMenuModel(displays: [display(0, current: true), display(1)], targets: [target(1)])
        XCTAssertEqual(model.nextMonitorTitle, "Move to Next Monitor")
        XCTAssertEqual(model.moveToMonitorTitle, "Move to Monitor")
    }

    func testMultiWindowTitlesCountTargets() {
        let model = WindowMoveMenuModel(
            displays: [display(0, current: true), display(1)],
            targets: [target(1), target(2), target(3)]
        )
        XCTAssertEqual(model.nextMonitorTitle, "Move 3 Windows to Next Monitor")
        XCTAssertEqual(model.moveToMonitorTitle, "Move 3 Windows to Monitor")
    }

    // MARK: - Placement gating

    func testMultiSelectionOmitsPlacement() {
        // Several windows sent to one slot would overlap; Move & Place must
        // disappear for multi-target menus.
        let model = WindowMoveMenuModel(
            displays: [display(0, current: true), display(1)],
            targets: [target(1), target(2)]
        )
        XCTAssertTrue(model.isAvailable)
        XCTAssertFalse(model.includesPlacement)
    }

    func testCurrentDisplayDisabledOnlyForSingleTarget() {
        // Single window: its own display is not a meaningful target.
        let single = WindowMoveMenuModel(
            displays: [display(0, current: true), display(1)],
            targets: [target(1)]
        )
        XCTAssertTrue(single.isDisabled(single.displays[0]))
        XCTAssertFalse(single.isDisabled(single.displays[1]))

        // Multi-selection may span monitors — the anchor display must stay
        // selectable so the whole selection can gather onto it.
        let multi = WindowMoveMenuModel(
            displays: [display(0, current: true), display(1)],
            targets: [target(1), target(2)]
        )
        XCTAssertFalse(multi.isDisabled(multi.displays[0]))
        XCTAssertFalse(multi.isDisabled(multi.displays[1]))
    }

    func testPlacementSlotsCoverCanonicalNamedPositions() {
        let slots = WindowMoveMenuModel.placementSlots
        XCTAssertTrue(slots.contains(.maximize))
        XCTAssertTrue(slots.contains(.center))
        for half: TilePosition in [.left, .right, .top, .bottom] {
            XCTAssertTrue(slots.contains(half))
        }
        for quarter: TilePosition in [.topLeft, .topRight, .bottomLeft, .bottomRight] {
            XCTAssertTrue(slots.contains(quarter))
        }
        for third: TilePosition in [.leftThird, .centerThird, .rightThird] {
            XCTAssertTrue(slots.contains(third))
        }
    }

    // MARK: - Right-click target rule

    func testClickOutsideSelectionTargetsClickedWindowOnly() {
        let clicked = target(9)
        let selection = [target(1), target(2)]
        XCTAssertEqual(WindowMoveMenuModel.resolveTargets(clicked: clicked, selection: selection), [clicked])
    }

    func testClickInsideMultiSelectionTargetsWholeSelection() {
        let selection = [target(1), target(2), target(3)]
        XCTAssertEqual(
            WindowMoveMenuModel.resolveTargets(clicked: target(2), selection: selection),
            selection
        )
    }

    func testClickOnSoleSelectedWindowTargetsItAlone() {
        let clicked = target(1)
        XCTAssertEqual(WindowMoveMenuModel.resolveTargets(clicked: clicked, selection: [clicked]), [clicked])
    }

    // MARK: - Accessibility labels

    func testAccessibilityLabelsNameActionAndTarget() {
        let model = WindowMoveMenuModel(
            displays: [display(0, current: true), display(1, name: "Studio Display")],
            targets: [target(1), target(2)]
        )
        XCTAssertEqual(
            model.moveAccessibilityLabel(to: model.displays[1]),
            "Move 2 windows to Studio Display"
        )
    }

    func testSingleWindowAccessibilityLabelNamesTargetDisplay() {
        let model = WindowMoveMenuModel(
            displays: [display(0, current: true), display(1, name: "Studio Display")],
            targets: [target(1)]
        )
        XCTAssertEqual(
            model.moveAccessibilityLabel(to: model.displays[1]),
            "Move window to Studio Display"
        )
    }

    func testPlacementAccessibilityLabelNamesSlotAndDisplay() {
        let model = WindowMoveMenuModel(
            displays: [display(0, current: true), display(1, name: "Studio Display")],
            targets: [target(1)]
        )
        let label = model.placeAccessibilityLabel(slot: .bottomRight, on: model.displays[1])
        XCTAssertEqual(label, "Move window to Studio Display and place \(TilePosition.bottomRight.label)")
    }

    // MARK: - Truthful receipts

    func testMoveOutcomeFullSuccess() {
        let single = WindowMovementService.moveOutcome(okWids: [11], total: 1, blocked: false, displayName: "DELL U2720Q")
        XCTAssertTrue(single.ok)
        XCTAssertEqual(single.message, "Moved to DELL U2720Q")
        XCTAssertEqual(single.movedWids, [11])

        let multi = WindowMovementService.moveOutcome(okWids: [1, 2, 3], total: 3, blocked: false, displayName: "DELL U2720Q")
        XCTAssertTrue(multi.ok)
        XCTAssertEqual(multi.message, "Moved 3 windows to DELL U2720Q")
        XCTAssertEqual(multi.movedWids, [1, 2, 3])
    }

    func testMoveOutcomeBlockedIsNotSuccess() {
        let outcome = WindowMovementService.moveOutcome(okWids: [], total: 1, blocked: true, displayName: "DELL")
        XCTAssertFalse(outcome.ok)
        XCTAssertTrue(outcome.message.contains("Accessibility"))
        XCTAssertTrue(outcome.movedWids.isEmpty)
    }

    func testMoveOutcomePartialCarriesOnlySuccessfulWids() {
        let outcome = WindowMovementService.moveOutcome(okWids: [7], total: 3, blocked: false, displayName: "DELL")
        XCTAssertFalse(outcome.ok)
        XCTAssertTrue(outcome.message.contains("1/3"))
        XCTAssertEqual(outcome.movedWids, [7])
    }

    func testMoveOutcomeUnverifiedIsNotReportedAsMovedAndCarriesNoWids() {
        let outcome = WindowMovementService.moveOutcome(okWids: [], total: 1, blocked: false, displayName: "DELL")
        XCTAssertFalse(outcome.ok)
        XCTAssertTrue(outcome.message.contains("not verified"))
        XCTAssertTrue(outcome.movedWids.isEmpty)
    }
}
