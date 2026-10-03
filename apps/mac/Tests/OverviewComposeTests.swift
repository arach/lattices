import XCTest
@testable import Lattices

final class OverviewComposeTests: XCTestCase {
    private func window(_ wid: UInt32, _ app: String) -> WindowEntry {
        WindowEntry(wid: wid, app: app, pid: 1, title: app + " example",
            frame: WindowFrame(x: 20, y: 30, w: 800, h: 600),
            spaceIds: [99], isOnScreen: false, latticesSession: nil, zIndex: Int(wid))
    }
    func testTerminalChromeCompositionUsesHalfLanesEvenWhenChromeIsFirst() throws {
        let draft = OverviewComposition(windows: [window(1, "Google Chrome"), window(2, "Ghostty")])
        XCTAssertEqual(draft.preview[2], CGRect(x: 0, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(draft.preview[1], CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        let layers = WorkspaceManager.creating(label: "Chrome + terminal", windows: draft.windows,
            tiles: draft.tiles, entries: [], in: [])
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0].projects.count, 2)
        XCTAssertTrue(layers[0].projects.allSatisfy { $0.tile != nil })
        // Off-desktop windows are retained; this pure operation performs no write.
        XCTAssertEqual(Set(layers[0].projects.flatMap { $0.pins ?? [] }.map(\.wid)), [1, 2])
    }
    func testSlotsAndFullArePersistedExactlyAsPreview() {
        var draft = OverviewComposition(windows: [window(1, "Ghostty")])
        XCTAssertEqual(draft.preview[1]?.minX, 0)
        draft.slots[1] = .right
        XCTAssertEqual(draft.preview[1]?.minX, 0.5)
        draft.slots[1] = .middle
        XCTAssertEqual(draft.preview[1]?.minX, 0.3)
        XCTAssertEqual(draft.preview[1]?.width, 0.4)
        draft.slots[1] = .full
        XCTAssertEqual(draft.preview[1], CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    func testDefaultsAndDeduplication() {
        XCTAssertEqual(OverviewComposition.Slot.suggested("Ghostty"), .left)
        XCTAssertEqual(OverviewComposition.Slot.suggested("Google Chrome"), .right)
        XCTAssertEqual(OverviewComposition.Slot.suggested("Xcode"), .middle)
        let w = window(1, "Ghostty")
        XCTAssertEqual(OverviewComposition(windows: [w, w]).windows.count, 1)
    }
    func testDragCarriesSelectionOnlyWhenDraggingASelectedWindow() {
        XCTAssertEqual(OverviewMembershipDrag.carried(clicked: 2, selected: [1, 2]), [1, 2])
        XCTAssertEqual(OverviewMembershipDrag.carried(clicked: 3, selected: [1, 2]), [3])
    }
    func testDragRoundTripPreservesOptionMoveSource() throws {
        let payload = OverviewMembershipDrag(session: "fixture", windows: [1, 2], sourceLayer: "a", move: true)
        XCTAssertEqual(try JSONDecoder().decode(OverviewMembershipDrag.self,
            from: JSONEncoder().encode(payload)), payload)
    }
    func testForeignDragCannotEditWorkspace() {
        let suite = "compose-drag." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverviewModel(defaults: defaults, inputs: .init(windows: [], displays: [], main: .zero))
        model.receiveMembership(.init(session: "foreign", windows: [1], sourceLayer: nil, move: false), into: "test")
        XCTAssertNil(model.compositionNotice)
        XCTAssertNil(model.actionError)
    }

}
