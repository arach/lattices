import XCTest
@testable import Lattices

/// Regression guard for the Inventory movement completion: refreshing the
/// desktop inventory must assign a fresh snapshot (never leave it nil/blank)
/// and must not disturb the selection.
final class CommandModeInventoryRefreshTests: XCTestCase {
    func testRefreshDesktopInventoryProducesSnapshotAndKeepsSelection() {
        let state = CommandModeState()
        state.selectedWindowIds = [42, 7]
        XCTAssertNil(state.desktopSnapshot)

        state.refreshDesktopInventory()

        XCTAssertNotNil(state.desktopSnapshot)
        XCTAssertEqual(state.selectedWindowIds, [42, 7])
    }
}
