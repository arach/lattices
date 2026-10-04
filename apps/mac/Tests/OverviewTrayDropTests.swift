import XCTest
@testable import Lattices

final class OverviewTrayDropTests: XCTestCase {
    func testColumnUsesDisplayAndAbsoluteSpaceRatherThanTitle() throws {
        let suite = "tray.dest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverviewModel(defaults: defaults, inputs: OverviewDragFixture.trayInputs(space: 2))
        let group = try XCTUnwrap(OverviewTray(model: model).groups.first { $0.spaceId == 1 })
        XCTAssertEqual(group.destination?.displayId, 900)
        XCTAssertEqual(group.destination?.spaceId, 1)
        XCTAssertEqual(group.destination?.desktop, 1)
        let unplaced = OverviewTray.Group(id: "unplaced", title: "Not on a Space", detail: "", rows: [], display: nil, spaceId: nil)
        XCTAssertNil(unplaced.destination)
        let unsupported = OverviewTray.Group(id: "99", title: "Desktop 1", detail: "", rows: [], display: group.display, spaceId: 99)
        XCTAssertNil(unsupported.destination)
    }

    func testReadbackMovesRowBetweenColumnsWithoutChangingViewedDesktop() {
        let suite = "tray.readback." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverviewModel(defaults: defaults, inputs: OverviewDragFixture.trayInputs(space: 2))
        XCTAssertTrue(OverviewTray(model: model).groups.first { $0.spaceId == 2 }!.rows.contains { $0.wid == 900001 })
        model.update(OverviewDragFixture.trayInputs(space: 1))
        let groups = OverviewTray(model: model).groups
        XCTAssertTrue(groups.first { $0.spaceId == 1 }!.rows.contains { $0.wid == 900001 })
        XCTAssertFalse(groups.contains { $0.spaceId == 2 && $0.rows.contains { $0.wid == 900001 } })
        XCTAssertNil(model.scope.spaceId)
        XCTAssertEqual(model.projection.displays.first?.currentSpaceId, 3)
    }
}
