import XCTest
@testable import Lattices

/// A swipe the Dock queued must hold the next press until it lands, so a
/// burst of presses can't stack swipes and overshoot.
final class PendingSpaceSwipeTests: XCTestCase {
    private let swipe = WindowTiler.PendingSpaceSwipe(displayId: "main", fromSpaceId: 5, postedAt: 100)

    func testStillOnTheOldSpaceIsInFlight() {
        XCTAssertEqual(swipe.status(currentSpaceId: 5, at: 101), .inFlight)
    }

    func testAnyOtherSpaceMeansItLanded() {
        XCTAssertEqual(swipe.status(currentSpaceId: 4, at: 100.3), .landed)
        // The Dock applied a queued burst: still a landing, plan from there.
        XCTAssertEqual(swipe.status(currentSpaceId: 1, at: 102), .landed)
    }

    func testAnUnreadableDisplayIsNotALanding() {
        XCTAssertEqual(swipe.status(currentSpaceId: nil, at: 101), .inFlight)
        XCTAssertEqual(swipe.status(currentSpaceId: 0, at: 101), .inFlight)
    }

    func testAfterTheWindowItIsTreatedAsLost() {
        let late = 100 + WindowTiler.PendingSpaceSwipe.window
        XCTAssertEqual(swipe.status(currentSpaceId: 5, at: late), .expired)
    }
}
