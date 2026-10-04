import XCTest
@testable import Lattices

final class OverviewDragPassTests: XCTestCase {
    private func window(_ id: UInt32) -> WindowEntry {
        .init(wid: id, app: "Ghostty", pid: 123, title: "Fixture \(id)",
              frame: .init(x: 0, y: 0, w: 500, h: 400), spaceIds: [1],
              isOnScreen: true, latticesSession: nil, zIndex: Int(id))
    }
    private let display = OverviewDisplay(index: 0, name: "Fixture display", bounds: CGRect(x: 0, y: 0, width: 1000, height: 800), desktops: [1, 2], currentSpaceId: 1, displayId: 7)

    func testBatchMovesSeriallyWithOnePartialFailureReceipt() throws {
        let suite = "drag.batch." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = DragPassActions()
        let model = OverviewModel(defaults: defaults, actions: actions,
            inputs: .init(windows: [window(1), window(2)], displays: [display], main: display.bounds))
        let drag = OverviewMembershipDrag(session: model.membershipDragSession, windows: [1, 2], sourceLayer: "source", move: false)
        let destination = try XCTUnwrap(OverviewWindowDrop.destination(on: display, spaceId: 2))
        model.moveDragged(drag, to: destination)
        XCTAssertEqual(actions.calls, [1])
        XCTAssertEqual(model.moving, [1, 2])
        XCTAssertNil(model.compositionNotice)
        XCTAssertEqual(model.moveProgress, "Moving to Desktop 2…")
        model.moveDragged(drag, to: destination) // Cannot interleave another batch.
        XCTAssertEqual(actions.calls, [1])
        actions.finish?(nil)
        XCTAssertEqual(actions.calls, [1, 2])
        XCTAssertNil(model.compositionNotice)
        actions.finish?("verification timed out")
        XCTAssertTrue(model.moving.isEmpty)
        XCTAssertNil(model.moveProgress)
        XCTAssertEqual(model.compositionNotice, "Moved 1 windows to Desktop 2; Ghostty · Fixture 2: verification timed out")
        XCTAssertEqual(actions.saves, 0)
    }

    func testSameDisplayUsesCarryOnlyForOneOrdinarySourceDesktop() {
        let groups = [[1, 2, 3], [4, 5]]
        XCTAssertTrue(WindowSpaceCarry.sameDisplay(from: [1], to: 2, desktopGroups: groups))
        XCTAssertTrue(WindowSpaceCarry.sameDisplay(from: [3], to: 1, desktopGroups: groups))
        XCTAssertFalse(WindowSpaceCarry.sameDisplay(from: [1], to: 4, desktopGroups: groups))
        XCTAssertFalse(WindowSpaceCarry.sameDisplay(from: [], to: 2, desktopGroups: groups))
        XCTAssertFalse(WindowSpaceCarry.sameDisplay(from: [1, 2], to: 3, desktopGroups: groups))
        XCTAssertFalse(WindowSpaceCarry.sameDisplay(from: [1], to: 99, desktopGroups: groups))
    }

    func testPhysicalDropWaitsUntilPointerReleaseBeforeOpeningMissionControl() throws {
        let suite = "drag.native-end." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = DragPassActions()
        let model = OverviewModel(defaults: defaults, actions: actions,
            inputs: .init(windows: [window(1)], displays: [display], main: display.bounds))
        let drag = OverviewMembershipDrag(session: model.membershipDragSession, windows: [1], sourceLayer: nil, move: false)
        model.activeDrag = drag
        model.moveDragged(drag, to: try XCTUnwrap(OverviewWindowDrop.destination(on: display, spaceId: 2)))
        XCTAssertTrue(actions.calls.isEmpty)
        XCTAssertEqual(model.moveProgress, "Moving to Desktop 2…")
        model.finishDrag()
        XCTAssertTrue(actions.calls.isEmpty, "Wait until the pointer release callback returns")
        let finished = expectation(description: "move starts after pointer release")
        DispatchQueue.main.async {
            XCTAssertEqual(actions.calls, [1])
            actions.finish?(nil)
            XCTAssertEqual(model.compositionNotice, "Moved Ghostty to Desktop 2")
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
    }

    func testMenuAndSingleDropReportProgressAndAppResultWithoutChangingViewedDesktop() throws {
        let suite = "drag.single." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = DragPassActions()
        let model = OverviewModel(defaults: defaults, actions: actions,
            inputs: .init(windows: [window(1)], displays: [display], main: display.bounds))
        let destination = try XCTUnwrap(OverviewWindowDrop.destination(on: display, spaceId: 2))
        XCTAssertTrue(model.move(1, to: destination))
        XCTAssertEqual(model.moveProgress, "Moving to Desktop 2…")
        actions.finish?(nil)
        XCTAssertNil(model.moveProgress)
        XCTAssertEqual(model.compositionNotice, "Moved Ghostty to Desktop 2")
        let viewed = model.scope.spaceId
        model.moveDragged(.init(session: model.membershipDragSession, windows: [1], sourceLayer: nil, move: false), to: destination)
        XCTAssertEqual(model.moveProgress, "Moving to Desktop 2…")
        actions.finish?(nil)
        XCTAssertEqual(model.compositionNotice, "Moved Ghostty to Desktop 2")
        XCTAssertEqual(model.scope.spaceId, viewed)
        XCTAssertEqual(model.projection.displays.first?.currentSpaceId, 1)
        XCTAssertTrue(model.move(1, to: destination))
        actions.finish?("Mission Control didn't open")
        XCTAssertTrue(model.actionError?.contains("Mission Control didn't open") == true)
        XCTAssertNil(model.moveProgress)
        XCTAssertNil(model.compositionNotice)
    }

    func testDroppedRowShowsOnTargetAtOnceAndReturnsOnFailure() throws {
        let suite = "drag.pending." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = DragPassActions()
        let model = OverviewModel(defaults: defaults, actions: actions,
            inputs: .init(windows: [window(1)], displays: [display], main: display.bounds))
        let destination = try XCTUnwrap(OverviewWindowDrop.destination(on: display, spaceId: 2))
        model.moveDragged(.init(session: model.membershipDragSession, windows: [1], sourceLayer: nil, move: false), to: destination)
        XCTAssertEqual(model.projection.all[1]?.spaceId, 2, "The row moves before the carry finishes")
        XCTAssertEqual(model.moving, [1])
        actions.finish?("the drop didn't take")
        XCTAssertEqual(model.projection.all[1]?.spaceId, 1, "A failed carry puts the row back")
        XCTAssertTrue(model.moving.isEmpty)
    }

    func testBatchRunsVerifiedRelocationWithEnvironmentFakes() throws {
        let suite = "drag.verified." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = DragPassActions()
        actions.verifyWithEnvironment = true
        let model = OverviewModel(defaults: defaults, actions: actions,
            inputs: .init(windows: [window(1), window(2)], displays: [display], main: display.bounds))
        let drag = OverviewMembershipDrag(session: model.membershipDragSession, windows: [1, 2], sourceLayer: nil, move: false)
        model.moveDragged(drag, to: try XCTUnwrap(OverviewWindowDrop.destination(on: display, spaceId: 2)))
        XCTAssertEqual(actions.calls, [1, 2])
        XCTAssertEqual(actions.verified, [1, 2])
        XCTAssertEqual(model.compositionNotice, "Moved 2 windows to Desktop 2")
        XCTAssertEqual(actions.saves, 0)
    }

    func testNewLayerDropStagesAndCancelDoesNotPersist() throws {
        let suite = "drag.stage." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let actions = DragPassActions()
        let model = OverviewModel(defaults: defaults, actions: actions,
            inputs: .init(windows: [window(1), window(2)], displays: [display], main: display.bounds))
        model.receiveMembership(.init(session: "foreign", windows: [1], sourceLayer: nil, move: false), into: "__new_layer__")
        XCTAssertNil(model.composition)
        model.receiveMembership(.init(session: model.membershipDragSession, windows: [2, 1, 1], sourceLayer: "source", move: false), into: "__new_layer__")
        XCTAssertEqual(model.composition?.windows.map(\.wid), [1, 2])
        XCTAssertEqual(model.composition?.moveSources, ["source"])
        XCTAssertEqual(model.composition?.name, "")
        model.composition = nil // Sheet cancellation.
        XCTAssertEqual(actions.saves, 0)
        XCTAssertTrue(actions.calls.isEmpty)
    }

    func testCreateMovesPinEntriesInSingleTemporaryFixtureWrite() throws {
        let windows = [window(1), window(2)]
        let original = WorkspaceManager.creating(label: "Source", windows: windows, in: [])
        let result = WorkspaceManager.creatingMoving(label: "Destination", windows: windows,
            tiles: OverviewComposition(windows: windows).tiles, sourceLayers: [original[0].id],
            in: original, live: windows, sources: .init())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(result.layers).write(to: url, options: .atomic)
        let saved = try JSONDecoder().decode([Layer].self, from: Data(contentsOf: url))
        XCTAssertTrue(saved[0].projects.isEmpty)
        XCTAssertEqual(Set(saved[1].projects.flatMap { $0.pins ?? [] }.map(\.wid)), [1, 2])
        XCTAssertTrue(saved[1].projects.allSatisfy { $0.tile != nil })
        XCTAssertFalse(result.retained)
    }

    func testNewLayerUsesTheExistingMoveRulesForBroadSourceEntries() {
        let windows = [window(1), window(2)]
        let source = Layer(id: "source", label: "Source", projects: [LayerProject(path: nil, group: nil, tile: nil, display: nil, app: "Ghostty", title: nil, url: nil, launch: nil)])
        let existingDestination = WorkspaceManager.creating(label: "Destination", windows: [windows[0]], in: [source])
        let expected = WorkspaceManager.moving(windows[0], from: 0, to: 1,
            in: existingDestination, live: windows, sources: .init())
        let result = WorkspaceManager.creatingMoving(label: "Destination", windows: [windows[0]], tiles: [:],
            sourceLayers: ["source"], in: [source], live: windows, sources: .init())
        XCTAssertEqual(result.retained, expected.outcome == .copied)
        XCTAssertEqual(result.layers[0].projects.count, 1, "The rule for the other window must survive")
        let ownership = LayerMembership.resolve(result.layers, windows: windows, sources: .init())
        XCTAssertEqual(ownership.owners[1]?.layerId, result.layers[1].id)
        XCTAssertEqual(ownership.owners[2]?.layerId, "source")
    }

    func testHoverLabelsMatchPayloadOperation() {
        let add = OverviewMembershipDrag(session: "fixture", windows: [1, 2], sourceLayer: "source", move: false)
        let move = OverviewMembershipDrag(session: "fixture", windows: [1, 2], sourceLayer: "source", move: true)
        XCTAssertEqual(OverviewDragLabel.layer("Talkie", id: "talkie", drag: add), "Add to Talkie")
        XCTAssertEqual(OverviewDragLabel.layer("Talkie", id: "talkie", drag: move), "Move to Talkie")
        XCTAssertEqual(OverviewDragLabel.layer("", id: "__new_layer__", drag: move), "New layer with 2 windows")
        XCTAssertEqual(OverviewDragLabel.desktop(2), "Move to Desktop 2")
    }
}

private final class DragPassActions: OverviewActions {
    var calls: [UInt32] = []
    var saves = 0
    var verifyWithEnvironment = false
    var verified: [UInt32] = []
    var finish: ((String?) -> Void)?
    func moveToSpace(wid: UInt32, pid: Int32, spaceId: Int, displayId: UInt32, completion: @escaping (String?) -> Void) {
        calls.append(wid)
        if verifyWithEnvironment {
            let frame = CGRect(x: 0, y: 0, width: 500, height: 400)
            var state = WindowRelocation.Snapshot(frame: frame, displayId: "fixture", spaceIds: [1])
            let environment = WindowRelocation.Environment(
                displays: { [.init(id: "fixture", index: 0, currentSpaceId: 1, spaceIds: [1, 2])] },
                snapshot: { state },
                moveSpace: { space in state = .init(frame: frame, displayId: "fixture", spaceIds: [space]); return nil },
                moveFrame: { _ in XCTFail("Same display must not move frame") },
                wait: { _ in state })
            let result = WindowRelocation.execute(from: state,
                to: .init(displayId: "fixture", spaceId: spaceId, frame: frame),
                tolerance: 6, environment: environment)
            if result.verified { verified.append(wid) }
            completion(result.verified ? nil : "Fixture verification failed")
        } else { finish = completion }
    }
    func saveLayer(_ plan: LayerEditPlan) throws { saves += 1 }
    func rearrange(layerId: String) throws { XCTFail("Unexpected rearrange") }
    func focus(wid: UInt32, pid: Int32) { XCTFail("Unexpected focus") }
    func place(wid: UInt32, pid: Int32, position: TilePosition, displayId: UInt32) { XCTFail("Unexpected placement") }
    func distribute(_ windows: [(wid: UInt32, pid: Int32)], displayId: UInt32, shape: [Int]?) { XCTFail("Unexpected distribute") }
}
