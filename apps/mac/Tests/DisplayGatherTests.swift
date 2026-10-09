import XCTest
@testable import Lattices

final class DisplayGatherTests: XCTestCase {
    private let left = DisplayGather.Screen(
        index: 0, id: "A", name: "Studio", frame: CGRect(x: 0, y: 0, width: 2000, height: 1000),
        visible: CGRect(x: 0, y: 30, width: 2000, height: 970), isMain: true
    )
    private let right = DisplayGather.Screen(
        index: 1, id: "B", name: "HDMI", frame: CGRect(x: 2000, y: 0, width: 1000, height: 500),
        visible: CGRect(x: 2000, y: 0, width: 1000, height: 500), isMain: false
    )

    private func window(_ id: UInt32, _ app: String, z: Int, _ frame: CGRect) -> WindowEntry {
        WindowEntry(wid: id, app: app, pid: 1, title: "Window \(id)",
                    frame: WindowFrame(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height),
                    spaceIds: [1], isOnScreen: true, latticesSession: nil, zIndex: z)
    }

    func testOwnerIsTheDisplayHoldingMostOfTheWindow() {
        let straddling = CGRect(x: 1800, y: 0, width: 600, height: 400)
        XCTAssertEqual(DisplayGather.owner(of: straddling, among: [left, right])?.id, "B")
        XCTAssertNil(DisplayGather.owner(of: CGRect(x: 5000, y: 0, width: 10, height: 10), among: [left, right]))
    }

    func testCarryKeepsPlaceAndProportions() {
        let unit = DisplayGather.unit(of: CGRect(x: 2500, y: 0, width: 500, height: 250), in: right.visible)
        XCTAssertEqual(unit, CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(DisplayGather.carry(unit, to: left.visible), CGRect(x: 1000, y: 30, width: 1000, height: 485))
    }

    func testCarryStaysInside() {
        let carried = DisplayGather.carry(CGRect(x: 0.9, y: -0.2, width: 1.4, height: 0.01), to: left.visible)
        XCTAssertEqual(carried.minX, 0)
        XCTAssertEqual(carried.width, 2000)
        XCTAssertGreaterThanOrEqual(carried.minY, left.visible.minY)
        XCTAssertGreaterThan(carried.height, 0)
    }

    func testWindowsOnADisplayBackToFront() {
        let inventory = [
            window(1, "Zed", z: 0, CGRect(x: 2100, y: 50, width: 400, height: 300)),
            window(2, "Safari", z: 3, CGRect(x: 100, y: 100, width: 800, height: 600)),
            window(3, "Ghostty", z: 5, CGRect(x: 2000, y: 0, width: 1000, height: 500)),
        ]
        let kept = DisplayGather.windows(on: right, among: [left, right], from: inventory)
        XCTAssertEqual(kept.map(\.wid), [3, 1])
    }

    func testSummaryNamesFrontAppsFirst() {
        let kept = ["A", "B", "C", "D", "B"].enumerated().map {
            DisplayGather.Kept(wid: UInt32($0.offset), pid: 1, app: $0.element, title: "", unit: .zero)
        }
        XCTAssertEqual(DisplayGather.summary(kept), "5 windows · B, D, C +1")
    }
}
