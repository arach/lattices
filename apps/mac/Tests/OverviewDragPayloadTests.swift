import CoreGraphics
import XCTest
@testable import Lattices

final class OverviewDragPayloadTests: XCTestCase {
    private let physical = OverviewDisplay(
        index: 0, name: "DELL", bounds: CGRect(x: 0, y: 0, width: 3440, height: 1440),
        desktops: [1, 3], currentSpaceId: 3, displayId: 10
    )
    private let virtual = OverviewDisplay(
        index: 2, name: "Action Agent Layer", bounds: CGRect(x: 3440, y: 0, width: 1440, height: 900),
        desktops: [1955, 1956, 2200, 2377], currentSpaceId: 2377,
        spaceIds: [1955, 1956, 2200, 2377, 3000], displayId: 20
    )
    private let wid: UInt32 = 111784

    private func projection(spaceId: Int = 1956, hidden: Bool = false, displays: [OverviewDisplay]? = nil) -> OverviewProjection {
        let window = WindowEntry(
            wid: wid, app: "Ghostty", pid: 1100, title: "Disposable move fixture",
            frame: WindowFrame(x: 3440, y: 0, w: 900, h: 600),
            spaceIds: [spaceId], isOnScreen: false, latticesSession: nil,
            zIndex: 1, appHidden: hidden
        )
        return OverviewProjection.make(
            .init(windows: [window], displays: displays ?? [physical, virtual], main: physical.bounds),
            scope: .all, selection: []
        )
    }

    func testInactiveVirtualWindowCanDropOnPhysicalDesktopWithTheSameNumber() throws {
        let destination = try XCTUnwrap(OverviewWindowDrop.destination(on: physical, spaceId: 3))
        XCTAssertEqual(destination.title, "DELL · Desktop 2")
        XCTAssertEqual(destination.spaceId, 3)
        XCTAssertEqual(
            OverviewWindowDrop.window(
                from: [.init(wid: wid)], to: destination, projection: projection(), moving: []
            ),
            wid
        )
    }

    func testDropOntoTheWindowsExistingDesktopIsRejected() throws {
        let destination = try XCTUnwrap(OverviewWindowDrop.destination(on: virtual, spaceId: 1956))
        XCTAssertNil(OverviewWindowDrop.window(
            from: [.init(wid: wid)], to: destination, projection: projection(), moving: []
        ))
    }

    func testMapDropUsesItsDisplayedSpaceAndThumbnailCanTargetAnInactiveDesktop() throws {
        let map = try XCTUnwrap(OverviewWindowDrop.destination(on: physical, spaceId: physical.currentSpaceId))
        let thumbnail = try XCTUnwrap(OverviewWindowDrop.destination(on: physical, spaceId: 1))
        XCTAssertEqual(map.spaceId, 3)
        XCTAssertEqual(thumbnail.spaceId, 1)
        XCTAssertEqual(OverviewWindowDrop.window(
            from: [.init(wid: wid)], to: thumbnail, projection: projection(), moving: []
        ), wid)
    }

    func testFullScreenAndForeignSpacesAreNotDropDestinations() {
        XCTAssertNil(OverviewWindowDrop.destination(on: virtual, spaceId: 3000))
        XCTAssertNil(OverviewWindowDrop.destination(on: physical, spaceId: 1956))
    }

    func testDropRechecksWindowEligibility() throws {
        let destination = try XCTUnwrap(OverviewWindowDrop.destination(on: physical, spaceId: 3))
        XCTAssertNil(OverviewWindowDrop.window(
            from: [.init(wid: wid)], to: destination, projection: projection(hidden: true), moving: []
        ))
        XCTAssertNil(OverviewWindowDrop.window(
            from: [.init(wid: wid)], to: destination, projection: projection(spaceId: 3000), moving: []
        ))
        XCTAssertNil(OverviewWindowDrop.window(
            from: [.init(wid: 999)], to: destination, projection: projection(), moving: []
        ))
    }

    func testDropRejectsMissingMultipleAndBusyWindowPayloads() throws {
        let destination = try XCTUnwrap(OverviewWindowDrop.destination(on: physical, spaceId: 3))
        let projection = projection()
        XCTAssertNil(OverviewWindowDrop.window(from: [], to: destination, projection: projection, moving: []))
        XCTAssertNil(OverviewWindowDrop.window(
            from: [.init(wid: wid), .init(wid: wid)], to: destination, projection: projection, moving: []
        ))
        XCTAssertNil(OverviewWindowDrop.window(
            from: [.init(wid: wid)], to: destination, projection: projection, moving: [42]
        ))
    }

    func testDropRejectsDestinationRemovedDuringDrag() throws {
        let destination = try XCTUnwrap(OverviewWindowDrop.destination(on: physical, spaceId: 3))
        XCTAssertNil(OverviewWindowDrop.window(
            from: [.init(wid: wid)], to: destination, projection: projection(displays: [virtual]), moving: []
        ))
    }

    func testDropRejectsReplacedDisplayEvenWhenItsIndexAndSpacesMatch() throws {
        let destination = try XCTUnwrap(OverviewWindowDrop.destination(on: physical, spaceId: 3))
        let replaced = OverviewDisplay(
            index: physical.index, name: physical.name, bounds: physical.bounds,
            desktops: physical.desktops, currentSpaceId: physical.currentSpaceId, displayId: 99
        )
        XCTAssertNil(OverviewWindowDrop.window(
            from: [.init(wid: wid)], to: destination, projection: projection(displays: [replaced, virtual]), moving: []
        ))
    }
}
