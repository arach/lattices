import XCTest
@testable import Lattices

/// Pure unit tests for Lattices previous/next Space navigation.
///
/// Product path under test: resolve an adjacent Space ID, then switch via
/// SkyLight (`switchToSpace`) — mouse gestures (`space.previous` /
/// `space.next`), companion deck relative focus, etc.
///
/// These tests do **not** exercise macOS Mission Control Control+Left/Right
/// system shortcuts. Live SkyLight switches are intentionally out of scope
/// (would move the real desktop).
final class AdjacentSpaceTests: XCTestCase {

    // MARK: - Gesture / tiler adjacent target (space.previous / space.next)

    /// Same resolution used by mouse-gesture `space.previous` (−1) / `space.next` (+1).
    func testAdjacentSpaceMovesNextAndPrevious() {
        let spaces = [
            SpaceInfo(id: 10, index: 1, display: 0, isCurrent: true),
            SpaceInfo(id: 11, index: 2, display: 0, isCurrent: false),
            SpaceInfo(id: 12, index: 3, display: 0, isCurrent: false),
        ]

        XCTAssertEqual(
            WindowTiler.adjacentSpace(in: spaces, currentSpaceId: 11, offset: -1)?.id,
            10,
            "space.previous should target the prior Space id"
        )
        XCTAssertEqual(
            WindowTiler.adjacentSpace(in: spaces, currentSpaceId: 11, offset: 1)?.id,
            12,
            "space.next should target the following Space id"
        )
        XCTAssertEqual(
            WindowTiler.adjacentSpace(in: spaces, currentSpaceId: 10, offset: 1)?.id,
            11
        )
    }

    func testAdjacentSpaceBoundsReturnNil() {
        let spaces = [
            SpaceInfo(id: 10, index: 1, display: 0, isCurrent: true),
            SpaceInfo(id: 11, index: 2, display: 0, isCurrent: false),
        ]

        XCTAssertNil(
            WindowTiler.adjacentSpace(in: spaces, currentSpaceId: 10, offset: -1),
            "no previous Space on the first slot"
        )
        XCTAssertNil(
            WindowTiler.adjacentSpace(in: spaces, currentSpaceId: 11, offset: 1),
            "no next Space on the last slot"
        )
        XCTAssertNil(WindowTiler.adjacentSpace(in: spaces, currentSpaceId: 99, offset: 1))
        XCTAssertNil(WindowTiler.adjacentSpace(in: [], currentSpaceId: 10, offset: 1))
    }

    func testAdjacentSpaceOffsetZeroReturnsCurrent() {
        let spaces = [
            SpaceInfo(id: 10, index: 1, display: 0, isCurrent: false),
            SpaceInfo(id: 11, index: 2, display: 0, isCurrent: true),
        ]
        XCTAssertEqual(
            WindowTiler.adjacentSpace(in: spaces, currentSpaceId: 11, offset: 0)?.id,
            11
        )
    }

    // MARK: - Companion deck relative focus (spaces.focusRelative)

    func testRelativeSpaceTargetDirection() {
        let display = DisplaySpaces(
            displayIndex: 0,
            displayId: "main",
            spaces: [
                SpaceInfo(id: 10, index: 1, display: 0, isCurrent: false),
                SpaceInfo(id: 11, index: 2, display: 0, isCurrent: true),
                SpaceInfo(id: 12, index: 3, display: 0, isCurrent: false),
            ],
            currentSpaceId: 11
        )

        XCTAssertEqual(LatticesDeckHost.relativeSpaceTarget(in: display, direction: -1)?.id, 10)
        XCTAssertEqual(LatticesDeckHost.relativeSpaceTarget(in: display, direction: 1)?.id, 12)
        XCTAssertNil(LatticesDeckHost.relativeSpaceTarget(in: display, direction: 2))
    }

    func testRelativeSpaceTargetAtEnds() {
        let firstCurrent = DisplaySpaces(
            displayIndex: 0,
            displayId: "main",
            spaces: [
                SpaceInfo(id: 10, index: 1, display: 0, isCurrent: true),
                SpaceInfo(id: 11, index: 2, display: 0, isCurrent: false),
            ],
            currentSpaceId: 10
        )
        XCTAssertNil(LatticesDeckHost.relativeSpaceTarget(in: firstCurrent, direction: -1))
        XCTAssertEqual(LatticesDeckHost.relativeSpaceTarget(in: firstCurrent, direction: 1)?.id, 11)

        let lastCurrent = DisplaySpaces(
            displayIndex: 0,
            displayId: "main",
            spaces: [
                SpaceInfo(id: 10, index: 1, display: 0, isCurrent: false),
                SpaceInfo(id: 11, index: 2, display: 0, isCurrent: true),
            ],
            currentSpaceId: 11
        )
        XCTAssertNil(LatticesDeckHost.relativeSpaceTarget(in: lastCurrent, direction: 1))
        XCTAssertEqual(LatticesDeckHost.relativeSpaceTarget(in: lastCurrent, direction: -1)?.id, 10)
    }

    /// Deck may receive Control+arrow key events from the phone, but Lattices
    /// must map them to relative Space targets (SkyLight), not synthesize the
    /// system Mission Control shortcut.
    func testCompanionKeyChordMapsToRelativeDirectionNotSystemShortcut() {
        let host = LatticesDeckHost.shared

        XCTAssertEqual(host.spaceSwitchDirection(key: "left", modifiers: ["control"]), -1)
        XCTAssertEqual(host.spaceSwitchDirection(key: "right", modifiers: ["ctrl"]), 1)
        XCTAssertEqual(host.spaceSwitchDirection(key: "←", modifiers: ["⌃"]), -1)
        XCTAssertEqual(host.spaceSwitchDirection(key: "→", modifiers: ["Control"]), 1)

        // Without Control, leave the chord alone (not a space switch).
        XCTAssertNil(host.spaceSwitchDirection(key: "left", modifiers: ["command"]))
        XCTAssertNil(host.spaceSwitchDirection(key: "up", modifiers: ["control"]))
        XCTAssertNil(host.spaceSwitchDirection(key: "right", modifiers: []))
    }

    // MARK: - Mouse gesture defaults → Lattices actions

    func testDefaultMouseShortcutsWireSpacePreviousAndNextActions() {
        let rules = MouseShortcutConfig.defaults.rules
        let previous = rules.first { $0.id == "space-previous" }
        let next = rules.first { $0.id == "space-next" }

        XCTAssertNotNil(previous)
        XCTAssertNotNil(next)
        XCTAssertEqual(previous?.enabled, true)
        XCTAssertEqual(next?.enabled, true)
        // Action types drive WindowTiler.switchToAdjacentSpace — not OS shortcuts.
        XCTAssertEqual(previous?.action.type, .spacePrevious)
        XCTAssertEqual(next?.action.type, .spaceNext)
        XCTAssertEqual(MouseShortcutActionType.spacePrevious.rawValue, "space.previous")
        XCTAssertEqual(MouseShortcutActionType.spaceNext.rawValue, "space.next")
        XCTAssertEqual(previous?.trigger.button, .middle)
        XCTAssertEqual(next?.trigger.button, .middle)
        XCTAssertEqual(previous?.trigger.kind, .drag)
        XCTAssertEqual(next?.trigger.kind, .drag)
        XCTAssertEqual(previous?.trigger.direction, .left)
        XCTAssertEqual(next?.trigger.direction, .right)
    }
}
