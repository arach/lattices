import CoreGraphics
import Foundation
import XCTest
@testable import Lattices

/// The main screen, with a display beside it on the right, as on the desk
/// these switches were first read from.
private let main = CGRect(x: 0, y: 0, width: 3440, height: 1440)
private let right = CGRect(x: 3440, y: 0, width: 1440, height: 900)
/// Where a park leaves a window here: one point in, and macOS pulls the top
/// up to keep the title bar in reach.
private let parkSpot = CGPoint(x: 3439, y: 1408)
private let parkedFrame = CGRect(origin: parkSpot, size: CGSize(width: 1200, height: 800))
private let leftHalf = CGRect(x: 0, y: 25, width: 1720, height: 1415)
private let rightHalf = CGRect(x: 1720, y: 25, width: 1720, height: 1415)
private let middle = CGRect(x: 1400, y: 100, width: 1200, height: 800)

/// Space 1 shows on the main screen and 7 on the right display; 2 is
/// another desktop.
private let stage = LayerStage.Stage(bounds: main, others: [right], spaceId: 1, currentSpaceIds: [1, 7])

private func window(_ wid: UInt32, pid: Int32, _ frame: CGRect, space: Int = 1, hidden: Bool = false) -> WindowEntry {
    WindowEntry(
        wid: wid, app: "pid \(pid)", pid: pid, title: "tideline \(wid)",
        frame: WindowFrame(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height),
        spaceIds: [space], isOnScreen: !hidden && space != 2, latticesSession: nil,
        appHidden: hidden, collapsed: hidden
    )
}

private func parked(_ wid: UInt32, pid: Int32, home: CGRect = middle, spot: CGPoint? = parkSpot) -> LayerStage.ParkedWindow {
    LayerStage.ParkedWindow(
        wid: wid, pid: pid, app: "pid \(pid)", title: "tideline \(wid)",
        frame: WindowFrame(x: home.minX, y: home.minY, w: home.width, h: home.height),
        spot: spot
    )
}

private func apps(_ pids: [Int32], hidden: Set<Int32> = [], accessory: Set<Int32> = []) -> [Int32: DesktopModel.AppFacts] {
    Dictionary(uniqueKeysWithValues: pids.map {
        ($0, DesktopModel.AppFacts(isHidden: hidden.contains($0), isRegular: !accessory.contains($0)))
    })
}

private func plan(
    _ want: Set<UInt32>,
    _ windows: [WindowEntry],
    parked: [LayerStage.ParkedWindow] = [],
    apps: [Int32: DesktopModel.AppFacts],
    frontmost: Int32? = nil,
    tucked: Set<UInt32> = []
) -> LayerStage.Plan {
    LayerStage.plan(want: want, windows: windows, parked: parked, stage: stage, apps: apps, frontmost: frontmost, tucked: tucked)
}

/// A main screen that moves windows the way macOS does: unhiding an app
/// pulls its windows out of the park corner into view.
private struct Desk {
    var frames: [UInt32: CGRect]
    let owners: [UInt32: Int32]
    var hidden = Set<Int32>()
    var ledger: [LayerStage.ParkedWindow] = []

    var windows: [WindowEntry] {
        frames.keys.sorted().map { wid in
            let pid = owners[wid] ?? 0
            return window(wid, pid: pid, frames[wid] ?? .zero, hidden: hidden.contains(pid))
        }
    }

    /// What CG lists: a hidden app's windows collapse to a point.
    var live: [UInt32: LayerStage.LiveWindow] {
        var live: [UInt32: LayerStage.LiveWindow] = [:]
        for (wid, frame) in frames {
            let pid = owners[wid] ?? 0
            let collapsed = CGRect(origin: frame.origin, size: CGSize(width: 1, height: 1))
            live[wid] = LayerStage.LiveWindow(pid: pid, frame: hidden.contains(pid) ? collapsed : frame)
        }
        return live
    }

    func plan(_ want: Set<UInt32>, frontmost: Int32? = nil) -> LayerStage.Plan {
        LayerStage.plan(
            want: want, windows: windows, parked: ledger, stage: stage,
            apps: apps(Array(Set(owners.values)).sorted(), hidden: hidden), frontmost: frontmost
        )
    }

    /// Runs `plan` in the stage's order: unhide, park, restore, hide.
    mutating func run(_ plan: LayerStage.Plan) {
        for pid in plan.unhide {
            hidden.remove(pid)
            for (wid, owner) in owners where owner == pid {
                guard let frame = frames[wid], frame.maxX > main.maxX else { continue }
                frames[wid] = CGRect(
                    x: main.maxX - frame.width, y: main.maxY - frame.height,
                    width: frame.width, height: frame.height
                )
            }
        }
        for wid in plan.park {
            guard let frame = frames[wid], let pid = owners[wid] else { continue }
            if !ledger.contains(where: { $0.wid == wid }) {
                ledger.append(parked(wid, pid: pid, home: frame))
            }
            frames[wid] = CGRect(origin: parkSpot, size: frame.size)
        }
        for wid in plan.restore {
            guard let index = ledger.firstIndex(where: { $0.wid == wid }) else { continue }
            let home = ledger[index].frame
            frames[wid] = CGRect(x: home.x, y: home.y, width: home.w, height: home.h)
            ledger.remove(at: index)
        }
        hidden.formUnion(plan.hide)
    }
}

final class LayerStagePlanTests: XCTestCase {
    // MARK: - Switch replay

    func testParkHideUnhideReplayEndsParked() {
        // Ghostty (10) has windows 1 and 2; Safari (20) has 3. Layer A holds
        // 1 and 3, layer B only 3.
        var desk = Desk(
            frames: [1: leftHalf, 2: middle, 3: rightHalf],
            owners: [1: 10, 2: 10, 3: 20]
        )

        // A: Ghostty stays, so its other window is parked while in view.
        let toA = desk.plan([1, 3])
        XCTAssertEqual(toA, LayerStage.Plan(park: [2]))
        desk.run(toA)
        XCTAssertEqual(desk.frames[2]?.origin, parkSpot)

        // B: nothing of Ghostty's is wanted, so it's hidden.
        let toB = desk.plan([3])
        XCTAssertEqual(toB, LayerStage.Plan(hide: [10], hidden: [1]))
        desk.run(toB)

        // A again: Ghostty comes back first, then window 2, which unhiding
        // pulled into view, is parked again even though the ledger has it.
        let backToA = desk.plan([1, 3])
        XCTAssertEqual(backToA, LayerStage.Plan(unhide: [10], park: [2], unhidden: [1]))
        desk.run(backToA)

        XCTAssertEqual(desk.frames[2]?.origin, parkSpot)
        XCTAssertEqual(desk.ledger.map(\.wid), [2])
        XCTAssertEqual(desk.ledger.first?.frame, WindowFrame(x: 1400, y: 100, w: 1200, h: 800))
        XCTAssertEqual(LayerStage.stillParked(desk.ledger, live: desk.live, main: main, hidden: []).map(\.wid), [2])
        let showing = desk.windows.filter { LayerStage.isShowing($0, on: stage) }.map(\.wid)
        XCTAssertEqual(showing, [1, 3])
    }

    func testReselectingAfterAPullBackParksAgain() {
        // Window 2 was parked, then something pulled it back into view.
        var desk = Desk(frames: [1: leftHalf, 2: middle], owners: [1: 10, 2: 10])
        desk.ledger = [parked(2, pid: 10)]

        let again = desk.plan([1])
        XCTAssertEqual(again, LayerStage.Plan(park: [2]))
        desk.run(again)
        XCTAssertEqual(desk.frames[2]?.origin, parkSpot)
    }

    // MARK: - Hidden apps

    func testStaleHiddenPidIsDropped() {
        XCTAssertEqual(LayerStage.stillHidden([10, 20, 30], hidden: [20], settling: []), [20])
        XCTAssertEqual(LayerStage.stillHidden([10, 20], hidden: [], settling: [10]), [10])
        XCTAssertEqual(LayerStage.stillHidden([20, 10, 20], hidden: [10, 20], settling: []), [20, 10])
    }

    // MARK: - Pruning

    func testCollapsedHiddenWindowIsNotPruned() {
        let ledger = [parked(2, pid: 10)]
        let collapsed = [UInt32(2): LayerStage.LiveWindow(pid: 10, frame: CGRect(x: 0, y: 0, width: 1, height: 1))]
        XCTAssertEqual(LayerStage.stillParked(ledger, live: collapsed, main: main, hidden: []).map(\.wid), [2])

        // A hidden app's window stays parked wherever CG lists it.
        let listed = [UInt32(2): LayerStage.LiveWindow(pid: 10, frame: middle)]
        XCTAssertEqual(LayerStage.stillParked(ledger, live: listed, main: main, hidden: [10]).map(\.wid), [2])
    }

    func testDraggedBackClosedAndReusedWindowsArePruned() {
        let ledger = [parked(2, pid: 10), parked(3, pid: 10), parked(4, pid: 10)]
        let live: [UInt32: LayerStage.LiveWindow] = [
            2: LayerStage.LiveWindow(pid: 10, frame: middle),
            4: LayerStage.LiveWindow(pid: 99, frame: parkedFrame),
        ]
        XCTAssertTrue(LayerStage.stillParked(ledger, live: live, main: main, hidden: []).isEmpty)
    }

    func testPulledBackReadsTheSpotOrTheCorner() {
        func pulled(_ entry: LayerStage.ParkedWindow, _ frame: CGRect) -> Bool {
            LayerStage.isPulledBack(entry, live: [2: LayerStage.LiveWindow(pid: 10, frame: frame)], main: main)
        }
        let entry = parked(2, pid: 10)
        XCTAssertFalse(pulled(entry, parkedFrame))
        XCTAssertTrue(pulled(entry, CGRect(x: 2240, y: 640, width: 1200, height: 800)))
        XCTAssertFalse(pulled(entry, CGRect(x: 2240, y: 640, width: 1, height: 1)))
        // An older ledger has no spot; the corner stands in.
        let older = parked(2, pid: 10, spot: nil)
        XCTAssertFalse(pulled(older, CGRect(x: 3420, y: 1300, width: 1200, height: 800)))
        XCTAssertTrue(pulled(older, middle))
    }

    func testDeadWindowsLeaveScenesAndTucked() {
        let lists: [String: [UInt32]] = ["work@1": [1, 2], "work@2": [3], "read": [2, 4]]
        XCTAssertEqual(LayerStage.pruneDead(lists, alive: [1, 4]), ["work@1": [1], "read": [4]])
    }

    func testALetOutWindowWaitsUntilAStageShowsIt() {
        // 3 is on another desktop: not shown, so it waits for a switch there.
        XCTAssertEqual(LayerStage.stillUntucked([1, 3], claimed: [], shown: [1]), [3])
        // Another layer claims 3 now: it's that layer's.
        XCTAssertNil(LayerStage.stillUntucked([1, 3], claimed: [3], shown: [1]))
        XCTAssertEqual(LayerStage.stillUntucked([1, 3], claimed: [], shown: []), [1, 3])
    }

    // MARK: - Want

    func testEmptyWantHidesAndParksNothing() {
        let windows = [
            window(1, pid: 10, leftHalf),
            window(2, pid: 20, rightHalf),
            window(4, pid: 30, middle, space: 2),
        ]
        // The layer's only member is on another desktop, and its scene is gone.
        let want = LayerStage.want(own: [4], scene: [9], claimed: [], tucked: [], windows: windows, stage: stage)
        XCTAssertTrue(want.isEmpty)
        XCTAssertEqual(plan(want, windows, apps: apps([10, 20, 30])), LayerStage.Plan())
    }

    func testTuckedMemberIsParkedNotShown() {
        let windows = [window(1, pid: 10, leftHalf), window(2, pid: 10, middle)]
        let want = LayerStage.want(own: [1, 2], scene: [], claimed: [], tucked: [2], windows: windows, stage: stage)
        XCTAssertEqual(want, [1])
        XCTAssertEqual(plan(want, windows, apps: apps([10])), LayerStage.Plan(park: [2]))
    }

    func testAnEmptyWantPutsAwayOnlyWhatsTucked() {
        let windows = [
            window(1, pid: 10, leftHalf),
            window(2, pid: 20, rightHalf),
            window(3, pid: 20, middle),
        ]
        // Nothing else of its app shows: the app hides.
        XCTAssertEqual(plan([], windows, apps: apps([10, 20]), tucked: [1]), LayerStage.Plan(hide: [10], hidden: [1]))
        // Its app keeps a window showing: it parks.
        XCTAssertEqual(plan([], windows, apps: apps([10, 20]), tucked: [2]), LayerStage.Plan(park: [2]))
        // Nothing tucked shows here.
        XCTAssertEqual(plan([], windows, apps: apps([10, 20]), tucked: [9]), LayerStage.Plan())
    }

    func testSceneKeepsWhatItTucksWhereverItIs() {
        let windows = [
            window(1, pid: 10, leftHalf),
            window(5, pid: 30, parkedFrame),
            window(6, pid: 40, middle, hidden: true),
            window(7, pid: 50, middle, space: 2),
        ]
        XCTAssertEqual(LayerStage.scene(of: windows, stage: stage, claimed: [1], settling: []), [])
        XCTAssertEqual(LayerStage.scene(of: windows, stage: stage, claimed: [1], settling: [], keeping: [5, 6, 7]), [5, 6])
    }

    func testSceneExtrasAreRestored() {
        // Notes' window 5 was showing beside the layer when it was left, and
        // was parked since. Window 6 is in the scene too, but another layer
        // holds it now.
        let windows = [
            window(1, pid: 10, leftHalf),
            window(5, pid: 30, parkedFrame),
            window(6, pid: 40, rightHalf),
        ]
        let want = LayerStage.want(own: [1], scene: [5, 6], claimed: [6], tucked: [], windows: windows, stage: stage)
        XCTAssertEqual(want, [1, 5])
        let restore = plan(want, windows, parked: [parked(5, pid: 30)], apps: apps([10, 30, 40]))
        XCTAssertEqual(restore, LayerStage.Plan(restore: [5], hide: [40], hidden: [6]))
    }

    func testSceneIsWhatShowsUnclaimed() {
        let windows = [
            window(1, pid: 10, leftHalf),
            window(2, pid: 20, rightHalf),
            window(3, pid: 30, parkedFrame),
            window(4, pid: 40, middle, space: 2),
            window(5, pid: 50, middle),
        ]
        let scene = LayerStage.scene(of: windows, stage: stage, claimed: [1], settling: [5])
        XCTAssertEqual(scene, [2])
    }

    // MARK: - Put away

    func testHideGoesFrontmostLast() {
        let windows = [window(1, pid: 10, leftHalf), window(2, pid: 20, rightHalf), window(3, pid: 30, middle)]
        let away = plan([3], windows, apps: apps([10, 20, 30]), frontmost: 10)
        XCTAssertEqual(away.hide, [20, 10])
        XCTAssertEqual(away.hidden, [1, 2])
        XCTAssertTrue(away.park.isEmpty)
    }

    func testAppWithWindowsElsewhereOrNoDockIconIsParked() {
        let windows = [
            window(1, pid: 10, leftHalf),
            window(2, pid: 20, rightHalf),
            window(8, pid: 20, CGRect(x: 3500, y: 100, width: 800, height: 600), space: 7),
            window(3, pid: 30, middle),
        ]
        let away = plan([1], windows, apps: apps([10, 20, 30], accessory: [30]))
        XCTAssertEqual(away, LayerStage.Plan(park: [2, 3]))
    }

    // MARK: - A display beside the main screen

    func testDisplayOnTheRightKeepsParkDetection() {
        XCTAssertTrue(LayerStage.Stage.canPark(main, others: [right]))
        XCTAssertTrue(LayerStage.Stage.inParkCorner(parkedFrame, of: main))
        XCTAssertFalse(LayerStage.Stage.inParkCorner(CGRect(x: 3500, y: 100, width: 800, height: 600), of: main))
        XCTAssertFalse(LayerStage.isShowing(window(2, pid: 10, parkedFrame), on: stage))
        XCTAssertFalse(stage.contains(window(8, pid: 20, CGRect(x: 3500, y: 100, width: 800, height: 600), space: 7)))

        let live: [UInt32: LayerStage.LiveWindow] = [
            1: LayerStage.LiveWindow(pid: 10, frame: leftHalf),
            2: LayerStage.LiveWindow(pid: 10, frame: parkedFrame),
            8: LayerStage.LiveWindow(pid: 20, frame: CGRect(x: 3500, y: 100, width: 800, height: 600)),
            9: LayerStage.LiveWindow(pid: 20, frame: CGRect(x: 3440, y: 1420, width: 30, height: 20), layer: 25),
        ]
        XCTAssertEqual(LayerStage.strays(in: live, tracked: [], main: main) { _ in true }, [2])
        XCTAssertTrue(LayerStage.strays(in: live, tracked: [2], main: main) { _ in true }.isEmpty)
        XCTAssertEqual(LayerStage.stillParked([parked(2, pid: 10)], live: live, main: main, hidden: []).map(\.wid), [2])

        // One below the corner is where parked windows would land.
        XCTAssertFalse(LayerStage.Stage.canPark(main, others: [CGRect(x: 3440, y: 1440, width: 1920, height: 1080)]))
    }

    // MARK: - Persisted state

    func testOlderStateFileDecodes() throws {
        let json = """
        {
          "hiddenPids" : [ 501 ],
          "parked" : [
            {
              "app" : "Ghostty",
              "frame" : { "h" : 800, "w" : 1200, "x" : 1400, "y" : 100 },
              "pid" : 501,
              "title" : "tideline — zsh",
              "wid" : 2
            }
          ],
          "scenes" : { "work@1" : [ 5 ] }
        }
        """
        let state = try JSONDecoder().decode(LayerStage.State.self, from: Data(json.utf8))
        XCTAssertEqual(state.hiddenPids, [501])
        XCTAssertEqual(state.parked.map(\.wid), [2])
        XCTAssertNil(state.parked.first?.spot)
        XCTAssertEqual(state.scenes, ["work@1": [5]])
        XCTAssertTrue(state.tucked.isEmpty)

        XCTAssertEqual(try JSONDecoder().decode(LayerStage.State.self, from: Data("{}".utf8)), LayerStage.State())
    }

    func testStateRoundTrips() throws {
        var state = LayerStage.State()
        state.parked = [parked(2, pid: 501)]
        state.hiddenPids = [502]
        state.scenes = ["work@1": [5]]
        state.tucked = ["work": [3]]
        state.untucked = ["work": [4]]
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(LayerStage.State.self, from: data), state)
    }

    func testEmptyTuckedAndUntuckedStayOutOfTheFile() throws {
        var state = LayerStage.State()
        state.scenes = ["work@1": [5]]
        let written = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        XCTAssertFalse(written.contains("tucked"))
        XCTAssertTrue(written.contains("scenes"))
        XCTAssertEqual(try JSONDecoder().decode(LayerStage.State.self, from: Data(written.utf8)), state)
    }
}
