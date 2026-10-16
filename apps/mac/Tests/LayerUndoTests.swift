import XCTest
@testable import Lattices

final class LayerUndoTests: XCTestCase {
    private func app(_ app: String) -> LayerProject {
        LayerProject(path: nil, group: nil, tile: nil, display: nil, app: app, title: nil, url: nil, launch: nil, pins: nil)
    }

    private func layer(_ id: String, _ apps: [String] = [], label: String? = nil) -> Layer {
        Layer(id: id, label: label ?? id, projects: apps.map(app))
    }

    private func summary(_ old: [Layer], _ new: [Layer]) -> String {
        WorkspaceManager.changeSummary(from: old, to: new)
    }

    func testNamesACreatedLayer() {
        XCTAssertEqual(summary([layer("a")], [layer("a"), layer("terms")]), "creating 'terms'")
    }

    func testNamesADeletedLayer() {
        XCTAssertEqual(summary([layer("a"), layer("b")], [layer("a")]), "deleting 'b'")
    }

    func testNamesARenameWithoutCallingItAnEdit() {
        XCTAssertEqual(summary([layer("a")], [layer("a", label: "Alpha")]), "renaming 'a' to 'Alpha'")
    }

    func testCreatingThatTakesFromOthersNamesBoth() {
        let old = [layer("a", ["Ghostty"]), layer("b", ["Zed"])]
        let new = [layer("a"), layer("b", ["Zed"]), layer("c", ["Ghostty"])]
        XCTAssertEqual(summary(old, new), "creating 'c', editing 'a'")
    }

    func testCountsEditsPastTwo() {
        let old = ["a", "b", "c", "d"].map { layer($0) }
        let new = ["a", "b", "c", "d"].map { layer($0, ["Zed"]) }
        XCTAssertEqual(summary(old, new), "editing 'a', 'b' +2")
    }

    func testReorder() {
        XCTAssertEqual(summary([layer("a"), layer("b")], [layer("b"), layer("a")]), "reordering layers")
    }
}
