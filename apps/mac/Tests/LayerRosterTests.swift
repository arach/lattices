import CoreGraphics
import XCTest
@testable import Lattices

final class LayerRosterTests: XCTestCase {
    /// The main display showing Desktop 2 of three, with a full-screen app
    /// (9) after them, and a display on its left showing Desktop 1 of two.
    private let displays = [
        DisplaySpaces(displayIndex: 0, displayId: "main", spaces: [
            SpaceInfo(id: 1, index: 1, display: 0, isCurrent: false),
            SpaceInfo(id: 3, index: 2, display: 0, isCurrent: true),
            SpaceInfo(id: 4, index: 3, display: 0, isCurrent: false),
        ], currentSpaceId: 3, orderedSpaceIds: [1, 3, 4, 9]),
        DisplaySpaces(displayIndex: 1, displayId: "side", spaces: [
            SpaceInfo(id: 1058, index: 1, display: 1, isCurrent: true),
            SpaceInfo(id: 1060, index: 2, display: 1, isCurrent: false),
        ], currentSpaceId: 1058, orderedSpaceIds: [1058, 1060]),
    ]

    private func place(_ spaceIds: [Int]) -> LayerRoster.Place? {
        LayerRoster.place(of: spaceIds, in: displays, main: "main", sides: ["side": .left])
    }

    func testPlacesAWindowByItsDesktop() {
        XCTAssertEqual(place([3]), .here)
        XCTAssertEqual(place([1]), .desktop(1))
        XCTAssertEqual(place([4]), .desktop(3))
        XCTAssertEqual(place([1058]), .display(.left, desktop: nil))
        XCTAssertEqual(place([1060]), .display(.left, desktop: 2))
        XCTAssertEqual(place([9]), .fullScreen)
    }

    func testAWindowOnEveryDesktopIsHere() {
        XCTAssertEqual(place([1, 3, 4, 1058]), .here)
    }

    func testAWindowSpacesCantPlaceHasNoPlace() {
        XCTAssertNil(place([]))
        XCTAssertNil(place([77]))
    }

    func testNotes() {
        XCTAssertNil(LayerRoster.Place.here.note)
        XCTAssertEqual(LayerRoster.Place.desktop(1).note, "Desktop 1")
        XCTAssertEqual(LayerRoster.Place.display(.left, desktop: nil).note, "Left display")
        XCTAssertEqual(LayerRoster.Place.display(.left, desktop: 2).note, "Desktop 2, left")
        XCTAssertEqual(LayerRoster.Place.noWindow.note, "No window")
        XCTAssertEqual(LayerRoster.Place.notOpen.note, "Not open")
    }

    // MARK: A layer's apps

    private func window(_ wid: UInt32, _ app: String, space: Int, pid: Int32 = 1) -> WindowEntry {
        WindowEntry(
            wid: wid, app: app, pid: pid, title: "\(app) \(wid)", frame: WindowFrame(x: 0, y: 0, w: 800, h: 600),
            spaceIds: [space], isOnScreen: space == 3, latticesSession: nil
        )
    }

    private func app(_ app: String) -> LayerProject {
        LayerProject(path: nil, group: nil, tile: nil, display: nil, app: app, title: nil, url: nil, launch: nil)
    }

    private func apps(_ layer: Layer, _ members: [LayerMembership.Member], missing: [String: LayerRoster.App] = [:]) -> [LayerRoster.App] {
        LayerRoster.apps(of: layer, members: members, place: place, missing: { $0.app.flatMap { missing[$0] } })
    }

    func testAnAppIsListedOnceAtItsNearestWindow() {
        let layer = Layer(id: "tideline", label: "Tideline", projects: [app("Ghostty"), app("Google Chrome")])
        let members: [LayerMembership.Member] = [
            (window(1, "Ghostty", space: 1, pid: 7), false, 0),
            (window(2, "Ghostty", space: 3, pid: 7), false, 0),
            (window(3, "Google Chrome", space: 1060, pid: 8), false, 1),
        ]
        XCTAssertEqual(apps(layer, members), [
            LayerRoster.App(name: "Ghostty", pid: 7, place: .here),
            LayerRoster.App(name: "Google Chrome", pid: 8, place: .display(.left, desktop: 2)),
        ])
    }

    func testAnEntryHoldingNothingPlacedListsWhatItPointsAt() {
        let layer = Layer(id: "tideline", label: "Tideline", projects: [app("Ghostty"), app("Figma"), app("Safari")])
        let members: [LayerMembership.Member] = [
            (window(1, "Ghostty", space: 4), false, 0),
            // Spaces can't place it, so the entry counts as holding nothing.
            (window(2, "Safari", space: 77, pid: 9), false, 2),
        ]
        let missing = [
            "Figma": LayerRoster.App(name: "Figma", pid: nil, place: .notOpen),
            "Safari": LayerRoster.App(name: "Safari", pid: 9, place: .noWindow),
        ]
        XCTAssertEqual(apps(layer, members, missing: missing), [
            LayerRoster.App(name: "Ghostty", pid: 1, place: .desktop(3)),
            LayerRoster.App(name: "Figma", pid: nil, place: .notOpen),
            LayerRoster.App(name: "Safari", pid: 9, place: .noWindow),
        ])
    }

    func testTwoEntriesForOneAppShareARow() {
        let layer = Layer(id: "tideline", label: "Tideline", projects: [app("Ghostty"), app("ghostty")])
        let members: [LayerMembership.Member] = [(window(1, "Ghostty", space: 1, pid: 7), false, 0)]
        let missing = ["ghostty": LayerRoster.App(name: "ghostty", pid: 7, place: .noWindow)]
        XCTAssertEqual(apps(layer, members, missing: missing), [LayerRoster.App(name: "Ghostty", pid: 7, place: .desktop(1))])
    }

    func testSides() {
        let main = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        XCTAssertEqual(LayerRoster.side(of: CGRect(x: -3840, y: -396, width: 3840, height: 2160), from: main), .left)
        XCTAssertEqual(LayerRoster.side(of: CGRect(x: 3440, y: 0, width: 1920, height: 1080), from: main), .right)
        XCTAssertEqual(LayerRoster.side(of: CGRect(x: 760, y: -1080, width: 1920, height: 1080), from: main), .above)
    }
}
