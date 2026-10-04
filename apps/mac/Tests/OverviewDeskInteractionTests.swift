import XCTest
@testable import Lattices

final class OverviewDeskInteractionTests: XCTestCase {
    func testSnapZonesAndPlacementGeometryAgree() throws {
        let size = CGSize(width: 600, height: 300)
        let cases: [(CGPoint, OverviewSnap)] = [
            (.init(x: 300, y: 10), .full), (.init(x: 50, y: 120), .left),
            (.init(x: 500, y: 120), .right), (.init(x: 10, y: 270), .leftThird),
            (.init(x: 300, y: 270), .middleThird), (.init(x: 580, y: 270), .rightThird)]
        for (point, zone) in cases {
            XCTAssertEqual(OverviewSnap.at(point, in: size), zone)
            let f = try XCTUnwrap(PlacementSpec(string: zone.placement)?.fractions)
            XCTAssertEqual(zone.fractions, CGRect(x: f.0, y: f.1, width: f.2, height: f.3))
        }
        XCTAssertNil(OverviewSnap.at(.init(x: -1, y: 20), in: size))
        XCTAssertNil(OverviewSnap.at(.init(x: 700, y: 20), in: size))
        XCTAssertNil(OverviewSnap.at(.zero, in: .zero))
        XCTAssertNil(OverviewSnap.at(.init(x: CGFloat.nan, y: 0), in: size))
        XCTAssertEqual(OverviewSnap.at(.init(x: 600, y: 300), in: size), .rightThird)
    }

    func testToolbarClampsIncludingOversizedAndResizedWindow() {
        let room = CGSize(width: 900, height: 500), toolbar = CGSize(width: 600, height: 44)
        XCTAssertEqual(OverviewDeskPreferences.clamp(.init(x: -100, y: -50), toolbar: toolbar, room: room), .zero)
        XCTAssertEqual(OverviewDeskPreferences.clamp(.init(x: 800, y: 490), toolbar: toolbar, room: room), .init(x: 300, y: 456))
        XCTAssertEqual(OverviewDeskPreferences.clamp(.init(x: 300, y: 456), toolbar: toolbar, room: .init(width: 400, height: 200)), .init(x: 0, y: 156))
        XCTAssertEqual(OverviewDeskPreferences.clamp(.init(x: 50, y: 50), toolbar: toolbar, room: .zero), .zero)
    }

    func testPinHideAndToolbarPersistenceAreOnlyUserDefaults() {
        let suite = "desk.preferences." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let empty = OverviewProjection.Inputs(windows: [], displays: [], main: .zero)
        let model = OverviewModel(defaults: defaults, inputs: empty)
        model.pinDisplay(12)
        XCTAssertEqual(model.deskPreferences.pinned, 12)
        model.hideDisplay(12)
        XCTAssertNil(model.deskPreferences.pinned)
        XCTAssertTrue(model.deskPreferences.hidden.contains(12))
        model.pinDisplay(12)
        XCTAssertFalse(model.deskPreferences.hidden.contains(12))
        model.hideDisplay(13)
        let key = OverviewDeskPreferences.sizeKey(.init(width: 900, height: 500))
        model.deskPreferences.toolbar[key] = .init(x: 24, y: 100)
        model.saveDeskPreferences()
        let reloaded = OverviewModel(defaults: defaults, inputs: empty)
        XCTAssertEqual(reloaded.deskPreferences, model.deskPreferences)
        reloaded.restoreDisplay(13)
        XCTAssertFalse(reloaded.deskPreferences.hidden.contains(13))
        XCTAssertNotEqual(key, OverviewDeskPreferences.sizeKey(.init(width: 800, height: 500)))
    }

    func testScreenDropPlacesOnCurrentAndLastKnownDesktopWithVerifiedFakeRelocation() throws {
        let suite = "desk.drop." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let display = OverviewDisplay(index: 0, name: "Fixture", bounds: CGRect(x: 0, y: 0, width: 1000, height: 800), desktops: [1, 2], currentSpaceId: 1, displayId: 9)
        let window = WindowEntry(wid: 4, app: "Fixture", pid: 123, title: "Draggable", frame: .init(x: 0, y: 0, w: 400, h: 300), spaceIds: [1], isOnScreen: true, latticesSession: nil, zIndex: 0)
        let actions = DeskPlacementActions()
        let model = OverviewModel(defaults: defaults, actions: actions, inputs: .init(windows: [window], displays: [display], main: display.bounds))
        let drag = OverviewMembershipDrag(session: model.membershipDragSession, windows: [4], sourceLayer: nil, move: false)
        for space in [1, 2] {
            model.moveDragged(drag, to: try XCTUnwrap(OverviewWindowDrop.destination(on: display, spaceId: space)), snap: .left)
            XCTAssertTrue(actions.results.last?.verified == true)
            XCTAssertEqual(actions.results.last?.after.spaceIds, [space])
            XCTAssertEqual(actions.results.last?.after.frame, CGRect(x: 0, y: 0, width: 500, height: 800))
            XCTAssertEqual(model.compositionNotice, "Moved Fixture to Desktop \(space)")
        }
        XCTAssertNil(OverviewWindowDrop.destination(on: display, spaceId: 999))
        model.moveDragged(.init(session: "foreign", windows: [4], sourceLayer: nil, move: false),
                          to: try XCTUnwrap(OverviewWindowDrop.destination(on: display, spaceId: 2)), snap: .full)
        XCTAssertEqual(actions.results.count, 2)
    }
}

private final class DeskPlacementActions: OverviewActions {
    var results: [WindowRelocation.Result] = []
    func moveAndPlace(wid: UInt32, pid: Int32, destination: OverviewMoveDestination, snap: OverviewSnap, completion: @escaping (String?) -> Void) {
        let before = WindowRelocation.Snapshot(frame: CGRect(x: 0, y: 0, width: 400, height: 300), displayId: "fixture", spaceIds: [1])
        var state = before
        let fraction = snap.fractions
        let frame = CGRect(x: fraction.minX * 1000, y: fraction.minY * 800, width: fraction.width * 1000, height: fraction.height * 800)
        let env = WindowRelocation.Environment(
            displays: { [.init(id: "fixture", index: 0, currentSpaceId: 1, spaceIds: [1, 2])] },
            snapshot: { state },
            moveSpace: { state = .init(frame: state.frame, displayId: "fixture", spaceIds: [$0]); return nil },
            moveFrame: { state = .init(frame: $0, displayId: "fixture", spaceIds: [1]) },
            wait: { _ in state })
        let result = WindowRelocation.execute(from: before, to: .init(displayId: "fixture", spaceId: destination.spaceId, frame: frame), tolerance: 6, environment: env)
        results.append(result)
        completion(result.verified ? nil : result.failure)
    }
    func moveToSpace(wid: UInt32, pid: Int32, spaceId: Int, displayId: UInt32, completion: @escaping (String?) -> Void) { XCTFail("Snap must use combined relocation") }
    func saveLayer(_ plan: LayerEditPlan) throws { XCTFail("No workspace edits") }
    func rearrange(layerId: String) throws { XCTFail("No workspace edits") }
    func focus(wid: UInt32, pid: Int32) { XCTFail("No live focus") }
    func place(wid: UInt32, pid: Int32, position: TilePosition, displayId: UInt32) { XCTFail("No unverified placement") }
    func distribute(_ windows: [(wid: UInt32, pid: Int32)], displayId: UInt32, shape: [Int]?) { XCTFail("No distribute") }
}
