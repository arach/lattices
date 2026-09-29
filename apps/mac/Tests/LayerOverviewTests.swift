import CoreGraphics
import XCTest
@testable import Lattices

final class LayerOverviewTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 3440, height: 1440)

    /// Where the stage leaves a window: one point in from the corner, less
    /// what macOS clamps back.
    private let parkedFrame = CGRect(x: 3439, y: 1418, width: 1200, height: 800)
    private let tiledFrame = CGRect(x: 0, y: 25, width: 1720, height: 1415)

    private func spot(_ place: LayerRoster.Place, _ frame: CGRect, hidden: Bool = false) -> LayerOverview.Spot {
        LayerOverview.spot(place: place, frame: frame, appHidden: hidden, main: main)
    }

    func testAWindowInThePlaceItsSpacesSay() {
        XCTAssertEqual(spot(.here, tiledFrame), .at(.here))
        XCTAssertEqual(spot(.desktop(2), tiledFrame), .at(.desktop(2)))
        XCTAssertEqual(spot(.display(.left, desktop: nil), CGRect(x: -3840, y: -396, width: 1920, height: 2160)),
                       .at(.display(.left, desktop: nil)))
    }

    func testAWindowInTheCornerIsParked() {
        XCTAssertEqual(spot(.here, parkedFrame), .parked(desktop: nil))
        XCTAssertEqual(spot(.desktop(3), parkedFrame), .parked(desktop: 3))
    }

    func testAHiddenAppsWindowIsHiddenWhereverItIs() {
        XCTAssertEqual(spot(.here, tiledFrame, hidden: true), .hidden)
        XCTAssertEqual(spot(.here, parkedFrame, hidden: true), .hidden)
    }

    func testTheCornerIsTheStagesForty() {
        XCTAssertTrue(LayerOverview.isParked(CGRect(x: 3400, y: 1000, width: 900, height: 600), main: main))
        XCTAssertFalse(LayerOverview.isParked(CGRect(x: 3399, y: 1000, width: 900, height: 600), main: main))
        // Past the edge: on a display to the right, or below.
        XCTAssertFalse(LayerOverview.isParked(CGRect(x: 3440, y: 1000, width: 900, height: 600), main: main))
        XCTAssertFalse(LayerOverview.isParked(CGRect(x: 3420, y: 1440, width: 900, height: 600), main: main))
    }

    func testNotes() {
        XCTAssertNil(LayerOverview.Spot.at(.here).note)
        XCTAssertEqual(LayerOverview.Spot.at(.desktop(2)).note, "Desktop 2")
        XCTAssertEqual(LayerOverview.Spot.parked(desktop: nil).note, "Parked")
        XCTAssertEqual(LayerOverview.Spot.parked(desktop: 2).note, "Parked, Desktop 2")
        XCTAssertEqual(LayerOverview.Spot.hidden.note, "Hidden")
    }

    func testOnlyWindowsOnAShowingDesktopShow() {
        XCTAssertTrue(LayerOverview.Spot.at(.here).isShowing)
        XCTAssertTrue(LayerOverview.Spot.at(.display(.left, desktop: nil)).isShowing)
        XCTAssertFalse(LayerOverview.Spot.at(.display(.left, desktop: 2)).isShowing)
        XCTAssertFalse(LayerOverview.Spot.at(.desktop(2)).isShowing)
        XCTAssertFalse(LayerOverview.Spot.at(.fullScreen).isShowing)
        XCTAssertFalse(LayerOverview.Spot.parked(desktop: nil).isShowing)
        XCTAssertFalse(LayerOverview.Spot.hidden.isShowing)
    }

    func testShowingIds() {
        let overview = LayerOverview(index: 1, id: "fab", label: "fab", layout: "auto", isActive: false, entries: [
            .init(index: 0, name: "Ghostty", pattern: "mini: fab", windows: [
                .init(wid: 10, app: "Ghostty", title: "mini: fab · claude", spot: .at(.here)),
                .init(wid: 11, app: "Ghostty", title: "mini: fab · docs", spot: .parked(desktop: nil)),
            ], missing: nil),
            .init(index: 1, name: "Google Chrome", pattern: "fab", windows: [], missing: .noWindow),
        ])
        XCTAssertEqual(overview.slot, 2)
        XCTAssertEqual(overview.windows.map(\.wid), [10, 11])
        XCTAssertEqual(overview.showingIds, [10])
    }

    func testScopeIds() {
        let scope = LayerOverview.scopeId(for: "talkie")
        XCTAssertEqual(LayerOverview.layerId(fromScope: scope), "talkie")
        XCTAssertNil(LayerOverview.layerId(fromScope: "8F14E45F-CEA1-467A-9BA6-7C2B1F6E4A10"))
    }
}
