import XCTest
@testable import Lattices

final class CompanionDeckSpaceTests: XCTestCase {

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
}
