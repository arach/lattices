import XCTest
@testable import Lattices

enum MonitorLayoutFixture {
    static func inputs(_ count: Int, off: Int? = nil) -> OverviewProjection.Inputs {
        var displays: [OverviewDisplay] = []
        var windows: [WindowEntry] = []
        var x: CGFloat = 0
        for i in 0..<count {
            let size = i == 0 ? CGSize(width: 3440, height: 1440) : i == 1 ? CGSize(width: 1920, height: 1080) : CGSize(width: 1512, height: 982)
            let bounds = CGRect(origin: CGPoint(x: x, y: 0), size: size)
            let space = 10 * (i + 1)
            displays.append(.init(index: i, name: ["Studio", "LG UltraFine", "Built-in Retina"][i % 3], bounds: bounds,
                desktops: [space, space + 1, space + 2], currentSpaceId: space, displayId: UInt32(100 + i),
                availability: off == i ? .off : .online, isMain: i == 0))
            for j in 0..<2 {
                windows.append(.init(wid: UInt32(i * 2 + j + 1), app: j == 0 ? "Ghostty" : "TextEdit", pid: 99999,
                    title: j == 0 ? "lattices · swift build" : "Workspace notes", frame: .init(x: x + CGFloat(j) * size.width / 2 + 20,
                    y: 40, w: size.width / 2 - 40, h: size.height - 100), spaceIds: [space], isOnScreen: off != i, latticesSession: nil, zIndex: j))
            }
            x += size.width
        }
        return .init(windows: windows, displays: displays, main: displays.first?.bounds ?? .zero)
    }
}

final class OverviewMonitorLayoutTests: XCTestCase {
    private func desk(_ count: Int) -> [OverviewDeskMonitor] {
        OverviewProjection.make(MonitorLayoutFixture.inputs(count), scope: OverviewScope(), selection: []).desk
    }

    private func assertFits(_ plan: OverviewMonitorLayout.Plan, monitors: [OverviewDeskMonitor], room: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        let bounds = CGRect(origin: .zero, size: room).insetBy(dx: -1, dy: -1)
        for p in plan.placements {
            XCTAssertTrue(bounds.contains(p.frame), "outside room: \(p)", file: file, line: line)
            let d = monitors.first { $0.id == p.id }!.display
            XCTAssertEqual(p.map.height, p.map.width * d.bounds.height / d.bounds.width, accuracy: 1, file: file, line: line)
            for q in plan.placements where q.id != p.id {
                XCTAssertFalse(p.frame.intersects(q.frame), "overlapping monitors", file: file, line: line)
            }
        }
    }

    func testOneFillsAvailableAspectFittedRoomInWideAndTallCanvases() {
        let monitors = desk(1)
        for room in [CGSize(width: 1100, height: 430), CGSize(width: 520, height: 850)] {
            let plan = OverviewMonitorLayout.plan(monitors, in: room, preferred: nil)
            XCTAssertEqual(plan.arrangement, .single)
            assertFits(plan, monitors: monitors, room: room)
            let p = plan.placements[0]
            XCTAssertTrue(p.frame.width >= room.width - 2 || p.frame.height >= room.height - 2)
        }
    }
    func testTwoChooseSideBySideWideAndStackedTall() {
        let monitors = desk(2)
        for (room, choice) in [(CGSize(width: 1200, height: 430), OverviewMonitorLayout.Arrangement.spatial),
                               (CGSize(width: 500, height: 900), .stacked)] {
            let plan = OverviewMonitorLayout.plan(monitors, in: room, preferred: nil)
            XCTAssertEqual(plan.arrangement, choice)
            assertFits(plan, monitors: monitors, room: room)
        }
    }
    func testEveryMonitorSharesOneScale() {
        for count in [2, 3] {
            let monitors = desk(count)
            for room in [CGSize(width: 1200, height: 460), CGSize(width: 540, height: 950), CGSize(width: 1600, height: 700)] {
                for preferred in [nil, UInt32(101)] as [UInt32?] {
                    let plan = OverviewMonitorLayout.plan(monitors, in: room, preferred: preferred)
                    XCTAssertEqual(plan.placements.count, count)
                    XCTAssertEqual(plan.placements.first?.id, Int(preferred ?? 100))
                    assertFits(plan, monitors: monitors, room: room)
                    let scales = plan.placements.map { p in p.map.width / monitors.first { $0.id == p.id }!.display.bounds.width }
                    XCTAssertLessThan((scales.max()! - scales.min()!) * 1440, 2, "unequal scales \(scales) in \(room)")
                }
            }
        }
    }
    func testSpatialFollowsTheDeskArrangement() {
        // A panel left of main and the agent layer hanging below main's right edge.
        var input = MonitorLayoutFixture.inputs(3)
        func place(_ i: Int, _ bounds: CGRect) {
            let d = input.displays[i]
            input.displays[i] = .init(index: d.index, name: d.name, bounds: bounds, desktops: d.desktops,
                currentSpaceId: d.currentSpaceId, displayId: d.displayId, availability: d.availability, isMain: d.isMain)
        }
        place(1, CGRect(x: -3840, y: 0, width: 3840, height: 2160))
        place(2, CGRect(x: 3440, y: 1440, width: 1440, height: 900))
        let monitors = OverviewProjection.make(input, scope: OverviewScope(), selection: []).desk
        let room = CGSize(width: 1600, height: 700)
        let plan = OverviewMonitorLayout.plan(monitors, in: room, preferred: nil)
        XCTAssertEqual(plan.arrangement, .spatial)
        assertFits(plan, monitors: monitors, room: room)
        let frame = { (id: Int) in plan.placements.first { $0.id == id }!.frame }
        XCTAssertLessThan(frame(101).maxX, frame(100).minX)
        XCTAssertGreaterThan(frame(102).minX, frame(100).maxX)
        XCTAssertGreaterThan(frame(102).minY, frame(100).minY)
        XCTAssertGreaterThan(plan.placements.first { $0.id == 101 }!.map.width, plan.placements.first { $0.id == 100 }!.map.width)
    }
    func testOffEmptyAsleepAndMirroredCollapseButExplicitChoicesWin() throws {
        let suite = "monitors.activity." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var input = MonitorLayoutFixture.inputs(3, off: 1)
        input.windows.removeAll { $0.spaceIds == [30] }
        let model = OverviewModel(defaults: defaults, inputs: input)
        XCTAssertEqual(model.expandedMonitors.map(\.display.displayId), [100])
        XCTAssertEqual(model.inactiveReason(input.displays[1]), "off")
        XCTAssertEqual(model.inactiveReason(input.displays[2]), "empty")
        XCTAssertEqual(OverviewMonitorLayout.plan(model.expandedMonitors, in: .init(width: 1000, height: 400), preferred: nil).arrangement, .single)
        model.restoreDisplay(101)
        XCTAssertEqual(model.expandedMonitors.count, 2)
        model.pinDisplay(102)
        XCTAssertEqual(model.expandedMonitors.count, 3)
        model.hideDisplay(102)
        XCTAssertEqual(model.expandedMonitors.count, 2)
        for state in [OverviewDisplay.Availability.asleep, .mirrored] {
            input.displays[0].availability = state; model.update(input)
            XCTAssertEqual(model.inactiveReason(input.displays[0]), state.rawValue)
            XCTAssertFalse(model.expandedMonitors.contains { $0.display.displayId == 100 })
        }
        let loaded = OverviewDeskPreferences.load(defaults)
        XCTAssertTrue(loaded.hidden.contains(102)); XCTAssertTrue(loaded.revealed?.contains(101) == true)
        let old = Data(#"{"pinned":101,"hidden":[102],"toolbar":{}}"#.utf8)
        let migrated = try JSONDecoder().decode(OverviewDeskPreferences.self, from: old)
        XCTAssertEqual(migrated.pinned, 101); XCTAssertEqual(migrated.hidden, [102])
    }
    func testDisconnectedDisplayKeepsIdentityAndReturnsWithoutDuplicates() {
        let original = MonitorLayoutFixture.inputs(3).displays
        let unplugged = OverviewModel.retainingDisconnected(current: [original[0], original[2]], previous: original)
        XCTAssertEqual(unplugged.count, 3)
        XCTAssertEqual(unplugged.first { $0.displayId == 101 }?.availability, .off)
        XCTAssertEqual(Set(unplugged.map(\.index)).count, 3)
        let returned = OverviewModel.retainingDisconnected(current: original, previous: unplugged)
        XCTAssertEqual(returned, original)
    }
    func testActivityDoesNotDependOnSearchOrViewedDesktop() {
        let suite = "monitors.scope." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverviewModel(defaults: defaults, inputs: MonitorLayoutFixture.inputs(3))
        model.chooseDesktop(11)
        XCTAssertEqual(model.expandedMonitors.count, 3)
    }
    func testCarryRejectsUnsettledLeftwardDesktopAndAmbiguousWindow() {
        var stable = WindowSpaceCarry.StableFrame()
        XCTAssertNil(stable.observe(CGRect(x: 1673, y: 1, width: 245, height: 129), at: 0))
        XCTAssertNil(stable.observe(CGRect(x: 1550, y: 80, width: 245, height: 129), at: 0.15))
        let expanded = CGRect(x: 1473, y: 102, width: 245, height: 129)
        XCTAssertNil(stable.observe(expanded, at: 0.3))
        XCTAssertNil(stable.observe(expanded, at: 0.4))
        XCTAssertEqual(stable.observe(expanded, at: 0.6), expanded)
        XCTAssertNil(stable.observe(nil, at: 1))
        XCTAssertNil(stable.observe(expanded, at: 1.1))
        XCTAssertEqual(WindowSpaceCarry.thumbnailFrame(candidates: [expanded], observed: nil), expanded)
        XCTAssertNil(WindowSpaceCarry.thumbnailFrame(candidates: [expanded, expanded], observed: expanded))
    }
}
