import CoreGraphics
import XCTest
@testable import Lattices

/// What the bezel lists after a switch: where each window is once the
/// stage's outcome has landed, and the layer a deck's switcher item names.
final class LayerSwitchPresenceTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    private let parkedFrame = CGRect(x: 3439, y: 1418, width: 1200, height: 800)
    private let tiledFrame = CGRect(x: 0, y: 25, width: 1720, height: 1415)

    private func window(
        _ wid: UInt32, _ app: String, space: Int = 1, frame: CGRect? = nil, hidden: Bool = false
    ) -> WindowEntry {
        let frame = frame ?? tiledFrame
        return WindowEntry(
            wid: wid, app: app, pid: 1, title: "\(app) \(wid)",
            frame: WindowFrame(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height),
            spaceIds: [space], isOnScreen: space == 1, latticesSession: nil, appHidden: hidden
        )
    }

    private func app(_ app: String) -> LayerProject {
        LayerProject(path: nil, group: nil, tile: nil, display: nil, app: app, title: nil, url: nil, launch: nil)
    }

    /// Space 1 is the desktop showing, 2 is Desktop 2; Spaces can't place any other.
    private func place(_ spaceIds: [Int]) -> LayerRoster.Place? {
        switch spaceIds.first {
        case 1: return .here
        case 2: return .desktop(2)
        default: return nil
        }
    }

    private func spot(_ entry: WindowEntry, outcome: LayerStage.Outcome? = nil) -> LayerOverview.Spot? {
        LayerRoster.spot(of: entry, place: place(entry.spaceIds), main: main, outcome: outcome)
    }

    // MARK: Spot after a switch

    func testTheStagesOutcomeWinsOverTheInventory() {
        var outcome = LayerStage.Outcome()
        outcome.hidden = [1]
        outcome.parked = [2]
        outcome.missing = [3]
        outcome.shown = [4]
        // The inventory still has them where they were before the stage.
        XCTAssertEqual(spot(window(1, "Slack"), outcome: outcome), .hidden)
        XCTAssertEqual(spot(window(2, "Notes"), outcome: outcome), .parked(desktop: nil))
        XCTAssertEqual(spot(window(3, "Figma"), outcome: outcome), .parked(desktop: nil))
        XCTAssertEqual(spot(window(4, "Ghostty", frame: parkedFrame), outcome: outcome), .at(.here))
        XCTAssertEqual(spot(window(5, "Mail", hidden: true), outcome: outcome), .hidden)
    }

    func testWithoutAnOutcomeTheInventorySays() {
        XCTAssertEqual(spot(window(1, "Ghostty")), .at(.here))
        XCTAssertEqual(spot(window(2, "Notes", frame: parkedFrame)), .parked(desktop: nil))
        XCTAssertEqual(spot(window(3, "Notes", space: 2, frame: parkedFrame)), .parked(desktop: 2))
        XCTAssertEqual(spot(window(4, "Slack", hidden: true)), .hidden)
        XCTAssertNil(spot(window(5, "Mail", space: 77)))
    }

    func testParkedAndHiddenAreOneStepFromHere() {
        let nearestFirst: [LayerOverview.Spot] = [
            .at(.here), .at(.display(.left, desktop: nil)), .hidden, .at(.desktop(2)),
            .parked(desktop: 2), .at(.fullScreen), .at(.display(.left, desktop: 2)), .at(.notOpen),
        ]
        let ranks = nearestFirst.map(LayerRoster.rank(of:))
        XCTAssertEqual(ranks, ranks.sorted())
        XCTAssertEqual(LayerRoster.rank(of: .parked(desktop: nil)), LayerRoster.rank(of: .hidden))
    }

    // MARK: The bezel's rows

    func testAPutAwayAppSaysSoUntilItShows() {
        XCTAssertEqual(LayerRoster.App(name: "Slack", pid: nil, spot: .hidden, tucked: true).note, "Put away")
        XCTAssertEqual(LayerRoster.App(name: "Slack", pid: nil, spot: .parked(desktop: nil), tucked: true).note, "Put away")
        XCTAssertNil(LayerRoster.App(name: "Slack", pid: nil, spot: .at(.here), tucked: true).note)
        XCTAssertEqual(LayerRoster.App(name: "Notes", pid: nil, spot: .parked(desktop: nil)).note, "Parked")
        XCTAssertEqual(LayerRoster.App(name: "Mail", pid: nil, spot: .hidden).note, "Hidden")
    }

    private func apps(
        _ layer: Layer, _ members: [LayerMembership.Member],
        outcome: LayerStage.Outcome? = nil, tucked: Set<UInt32> = [], extras: [WindowEntry] = [],
        stayed: [WindowEntry] = []
    ) -> [LayerRoster.App] {
        LayerRoster.apps(
            of: layer, members: members, place: place, missing: { _ in nil },
            spot: { LayerRoster.spot(of: $0, place: $1, main: self.main, outcome: outcome) },
            tucked: tucked, extras: extras, stayed: stayed
        )
    }

    func testTheLayersAppsAfterItsStage() {
        let layer = Layer(id: "tideline", label: "Tideline", projects: [app("Ghostty"), app("Slack")])
        var outcome = LayerStage.Outcome()
        outcome.shown = [1]
        outcome.hidden = [2]
        let members: [LayerMembership.Member] = [
            (window(1, "Ghostty", space: 1, frame: parkedFrame), false, 0),
            (window(2, "Slack"), false, 1),
        ]
        XCTAssertEqual(apps(layer, members, outcome: outcome, tucked: [2]), [
            LayerRoster.App(name: "Ghostty", pid: 1, spot: .at(.here)),
            LayerRoster.App(name: "Slack", pid: 1, spot: .hidden, tucked: true),
        ])
    }

    func testTheSceneBeyondTheEntriesIsListedAfterThem() {
        let layer = Layer(id: "tideline", label: "Tideline", projects: [app("Ghostty")])
        let members: [LayerMembership.Member] = [(window(1, "Ghostty"), false, 0)]
        let extras = [window(5, "Finder"), window(6, "Ghostty", space: 2)]
        XCTAssertEqual(apps(layer, members, extras: extras), [
            LayerRoster.App(name: "Ghostty", pid: 1, spot: .at(.here)),
            LayerRoster.App(name: "Finder", pid: 1, spot: .at(.here), extra: true),
        ])
    }

    func testAnEntrysAppNearerInTheSceneIsStillTheEntrys() {
        let layer = Layer(id: "tideline", label: "Tideline", projects: [app("Ghostty")])
        let members: [LayerMembership.Member] = [(window(1, "Ghostty", space: 2), false, 0)]
        XCTAssertEqual(apps(layer, members, extras: [window(6, "Ghostty")]), [
            LayerRoster.App(name: "Ghostty", pid: 1, spot: .at(.here)),
        ])
    }

    func testAParkedWindowIsNearerThanAnotherDesktop() {
        let layer = Layer(id: "tideline", label: "Tideline", projects: [app("Notes")])
        let members: [LayerMembership.Member] = [
            (window(1, "Notes", space: 2), false, 0),
            (window(2, "Notes", frame: parkedFrame), false, 0),
        ]
        XCTAssertEqual(apps(layer, members), [
            LayerRoster.App(name: "Notes", pid: 1, spot: .parked(desktop: nil)),
        ])
    }

    func testAShowingWindowOutranksAPutAwayOne() {
        let layer = Layer(id: "tideline", label: "Tideline", projects: [app("Slack")])
        var outcome = LayerStage.Outcome()
        outcome.hidden = [2]
        let members: [LayerMembership.Member] = [
            (window(2, "Slack"), false, 0),
            (window(3, "Slack"), false, 0),
        ]
        let rows = apps(layer, members, outcome: outcome, tucked: [2])
        XCTAssertEqual(rows, [LayerRoster.App(name: "Slack", pid: 1, spot: .at(.here))])
        XCTAssertNil(rows.first?.note)
    }

    func testWindowsThatStayedAreListedLastAndApart() {
        let layer = Layer(id: "tideline", label: "Tideline", projects: [app("Ghostty")])
        var outcome = LayerStage.Outcome()
        outcome.shown = [1]
        outcome.stayed = [7, 8, 9]
        let members: [LayerMembership.Member] = [(window(1, "Ghostty"), false, 0)]
        let stayed = [window(7, "Ghostty"), window(8, "Zoom"), window(9, "Zoom")]
        let rows = apps(layer, members, outcome: outcome, extras: [window(5, "Finder")], stayed: stayed)
        XCTAssertEqual(rows, [
            LayerRoster.App(name: "Ghostty", pid: 1, spot: .at(.here)),
            LayerRoster.App(name: "Finder", pid: 1, spot: .at(.here), extra: true),
            LayerRoster.App(name: "Ghostty", pid: 1, spot: .at(.here), stayed: true),
            LayerRoster.App(name: "Zoom", pid: 1, spot: .at(.here), stayed: true),
        ])
        XCTAssertEqual(rows.map(\.note), [nil, nil, "Stayed", "Stayed"])
    }

    // MARK: A deck's switcher item

    private let layers = [
        Layer(id: "tideline", label: "Tideline", projects: []),
        Layer(id: "harbor", label: "Harbor", projects: []),
        Layer(id: "1", label: "Numbered", projects: []),
    ]

    func testASwitcherItemNamesItsLayerById() {
        XCTAssertEqual(LayerOverview.layerIndex(fromScope: LayerOverview.scopeId(for: "harbor"), in: layers), 1)
        XCTAssertEqual(LayerOverview.layerIndex(fromScope: "workspace-layer:tideline", in: layers), 0)
    }

    func testAnOlderDecksIndexStillWorks() {
        XCTAssertEqual(LayerOverview.layerIndex(fromScope: "workspace-layer:0", in: layers), 0)
        XCTAssertEqual(LayerOverview.layerIndex(fromScope: "workspace-layer:2", in: layers), 2)
    }

    func testAnIdWinsOverAnIndex() {
        XCTAssertEqual(LayerOverview.layerIndex(fromScope: "workspace-layer:1", in: layers), 2)
    }

    func testAnItemNamingNoLayerHasNone() {
        XCTAssertNil(LayerOverview.layerIndex(fromScope: "workspace-layer:7", in: layers))
        XCTAssertNil(LayerOverview.layerIndex(fromScope: "workspace-layer:-1", in: layers))
        XCTAssertNil(LayerOverview.layerIndex(fromScope: "workspace-layer:reef", in: layers))
        XCTAssertNil(LayerOverview.layerIndex(fromScope: "layer:harbor", in: layers))
        XCTAssertNil(LayerOverview.layerIndex(fromScope: "workspace-layer:harbor", in: []))
    }
}
