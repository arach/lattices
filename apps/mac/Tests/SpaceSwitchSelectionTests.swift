import XCTest
@testable import Lattices

final class SpaceSwitchSelectionTests: XCTestCase {
    func testTapIsImmediateButRepeatsWaitForRelease() throws {
        var state = try XCTUnwrap(SpaceSwitchSelection(ordered: Array(1...18), current: 1))
        state.press(1, repeated: false)
        XCTAssertEqual(state.target, 2)
        XCTAssertFalse(state.scrubbing)
        for _ in 0..<16 { state.press(1, repeated: true) }
        XCTAssertEqual(state.target, 18)
        XCTAssertTrue(state.scrubbing)
        state.release()
        XCTAssertFalse(state.scrubbing)
        XCTAssertEqual(state.target, 18)
    }

    func testExcessRepeatsAtEdgeDoNotBuildUpOnReversal() throws {
        var state = try XCTUnwrap(SpaceSwitchSelection(ordered: Array(1...18), current: 17))
        for _ in 0..<100 { state.press(1, repeated: true) }
        state.press(-1, repeated: false)
        XCTAssertEqual(state.target, 17)
        XCTAssertTrue(state.scrubbing, "Changing direction within a hold must not start real transit")
        for _ in 0..<100 { state.press(-1, repeated: true) }
        state.press(1, repeated: true)
        XCTAssertEqual(state.target, 2)
    }

    func testSelectionUsesSpaceIDsAndIncludesFullscreenPositions() throws {
        var state = try XCTUnwrap(SpaceSwitchSelection(ordered: [9, 41, 6, 99], current: 41))
        state.press(1, repeated: true)
        XCTAssertEqual(state.target, 6)
        state.press(-1, repeated: true)
        XCTAssertEqual(state.target, 41)
        XCTAssertNil(SpaceSwitchSelection(ordered: [], current: 1))
        XCTAssertNil(SpaceSwitchSelection(ordered: [9, 41], current: 1))
    }
}
