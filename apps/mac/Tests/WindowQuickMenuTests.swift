import XCTest
@testable import Lattices

final class WindowQuickMenuTests: XCTestCase {
    private func down(
        _ stroke: inout WindowQuickMenuStroke,
        control: Bool = true, option: Bool = true, command: Bool = false, shift: Bool = false
    ) -> WindowQuickMenuStroke.Verdict {
        stroke.rightMouseDown(control: control, option: option, command: command, shift: shift)
    }

    func testControlOptionStrokeIsTheMenus() {
        var stroke = WindowQuickMenuStroke()

        XCTAssertEqual(down(&stroke), .consume)
        XCTAssertTrue(stroke.isActive)
        XCTAssertEqual(stroke.rightMouseDragged(), .consume)
        XCTAssertEqual(stroke.rightMouseUp(), .open)
        XCTAssertTrue(stroke.menuOpen)
        XCTAssertEqual(stroke.rightMouseUp(), .pass)
    }

    func testPlainAndPartialRightClicksPass() {
        var stroke = WindowQuickMenuStroke()

        XCTAssertEqual(down(&stroke, control: false, option: false), .pass)
        XCTAssertEqual(stroke.rightMouseDragged(), .pass)
        XCTAssertEqual(stroke.rightMouseUp(), .pass)
        XCTAssertEqual(down(&stroke, option: false), .pass)
        XCTAssertEqual(down(&stroke, control: false), .pass)
        XCTAssertFalse(stroke.isActive)
    }

    func testHyperChordPasses() {
        var stroke = WindowQuickMenuStroke()

        XCTAssertEqual(down(&stroke, command: true, shift: true), .pass)
        XCTAssertEqual(down(&stroke, command: true), .pass)
        XCTAssertEqual(down(&stroke, shift: true), .pass)
        XCTAssertEqual(stroke.rightMouseUp(), .pass)
    }

    func testClicksPassWhileTheMenuIsUp() {
        var stroke = WindowQuickMenuStroke()
        _ = down(&stroke)
        _ = stroke.rightMouseUp()

        XCTAssertEqual(down(&stroke), .pass)
        XCTAssertEqual(stroke.rightMouseUp(), .pass)
        XCTAssertTrue(stroke.isActive)

        stroke.menuClosed()
        XCTAssertFalse(stroke.isActive)
        XCTAssertEqual(down(&stroke), .consume)
    }

    func testStrokeStaysOwnedWhenModifiersLiftMidway() {
        var stroke = WindowQuickMenuStroke()
        _ = down(&stroke)

        // Modifiers aren't consulted after the down.
        XCTAssertEqual(stroke.rightMouseDragged(), .consume)
        XCTAssertEqual(stroke.rightMouseUp(), .open)
    }

    func testResetDropsAStrokeWhoseReleaseWasLost() {
        var stroke = WindowQuickMenuStroke()
        _ = down(&stroke)

        stroke.reset()
        XCTAssertFalse(stroke.isActive)
        XCTAssertEqual(stroke.rightMouseUp(), .pass)
    }

    func testNextPlainDownEndsAStaleStroke() {
        var stroke = WindowQuickMenuStroke()
        _ = down(&stroke)

        XCTAssertEqual(down(&stroke, control: false, option: false), .pass)
        XCTAssertFalse(stroke.isActive)
        XCTAssertEqual(stroke.rightMouseUp(), .pass)
    }
}
