import XCTest
@testable import Lattices

final class LayerForecastTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 2000, height: 1000)

    private func window(_ id: UInt32, _ app: String, z: Int, frame: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 500)) -> WindowEntry {
        WindowEntry(wid: id, app: app, pid: 1, title: "Window \(id)",
                    frame: WindowFrame(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height),
                    spaceIds: [1], isOnScreen: true, latticesSession: nil, zIndex: z)
    }

    private func make(
        want: Set<UInt32>, members: Set<UInt32>, windows: [WindowEntry],
        homes: [UInt32: CGRect] = [:], planned: [(wid: UInt32, frame: CGRect)] = [],
        showing: Set<UInt32>, tucked: Set<UInt32> = []
    ) -> LayerForecast {
        LayerForecast.make(want: want, members: members, windows: windows, bounds: bounds,
                           homes: homes, planned: planned, showing: showing, tucked: tucked)
    }

    func testScalesToTheScreenAndKeepsItsAspect() {
        let forecast = make(want: [1], members: [1], windows: [window(1, "Zed", z: 0)], showing: [1])
        XCTAssertEqual(forecast.aspect, 2)
        XCTAssertEqual(forecast.tiles.map(\.frame), [CGRect(x: 0, y: 0, width: 0.5, height: 0.5)])
    }

    func testStacksSceneBehindMembersAndTheLayoutLeadInFront() {
        let windows = [window(1, "Zed", z: 0), window(2, "Ghostty", z: 1), window(3, "Notes", z: 2)]
        let forecast = make(want: [1, 2, 3], members: [1, 2], windows: windows,
                            planned: [(2, CGRect(x: 1000, y: 0, width: 1000, height: 1000)), (1, bounds)],
                            showing: [1, 2, 3])
        XCTAssertEqual(forecast.tiles.map(\.app), ["Notes", "Zed", "Ghostty"])
        XCTAssertEqual(forecast.tiles.last?.frame, CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(forecast.tiles.first?.member, false)
    }

    func testAParkedWindowComesBackHome() {
        let parked = window(1, "Zed", z: 0, frame: CGRect(x: 1990, y: 990, width: 400, height: 300))
        let forecast = make(want: [1], members: [1], windows: [parked],
                            homes: [1: CGRect(x: 500, y: 250, width: 1000, height: 500)], showing: [])
        XCTAssertEqual(forecast.tiles.first?.frame, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        XCTAssertEqual(forecast.tiles.first?.returning, true)
    }

    func testCountsWhatGoesAwayByApp() {
        let windows = [window(1, "Zed", z: 0), window(2, "Safari", z: 1), window(3, "Safari", z: 2), window(4, "Mail", z: 3)]
        let forecast = make(want: [1], members: [1], windows: windows, showing: [1, 2, 3, 4])
        XCTAssertEqual(forecast.putAwayCount, 3)
        XCTAssertEqual(forecast.putAway, ["Safari", "Mail"])
    }

    func testAnEmptyLayerKeepsTheScreenBarWhatItTucks() {
        let windows = [window(1, "Zed", z: 0), window(2, "Safari", z: 1)]
        let forecast = make(want: [], members: [], windows: windows, showing: [1, 2], tucked: [2])
        XCTAssertEqual(forecast.tiles.map(\.app), ["Zed"])
        XCTAssertEqual(forecast.putAway, ["Safari"])
    }

    func testSkipsWindowsOffTheScreen() {
        let off = window(1, "Zed", z: 0, frame: CGRect(x: 2500, y: 0, width: 500, height: 500))
        XCTAssertTrue(make(want: [1], members: [1], windows: [off], showing: []).tiles.isEmpty)
    }

    func testNotesSayWhereInPlainWords() {
        XCTAssertNil(LayerForecast.note(for: .here))
        XCTAssertEqual(LayerForecast.note(for: .desktop(3)), "Stays on Desktop 3")
        XCTAssertEqual(LayerForecast.note(for: .display(.left, desktop: nil)), "On the left display")
        XCTAssertEqual(LayerForecast.note(for: .display(.other, desktop: 2)), "On the other display")
        XCTAssertEqual(LayerForecast.note(for: .noWindow), "No window open")
        XCTAssertEqual(LayerForecast.note(for: .notOpen), "Not running")
    }
}
