import XCTest
@testable import Lattices

final class EditorGeometryTests: XCTestCase {
    private func window(_ id: UInt32, space: Int = 1) -> WindowEntry {
        WindowEntry(wid: id, app: "Safari", pid: 1, title: "Page \(id)",
                    frame: WindowFrame(x: 50, y: 50, w: 400, h: 300), spaceIds: [space],
                    isOnScreen: true, latticesSession: nil, zIndex: Int(id))
    }
    private var displays: [OverviewDisplay] {
        [.init(index: 0, name: "Main", bounds: CGRect(x: 0, y: 0, width: 1200, height: 800),
               desktops: [1, 2], currentSpaceId: 1, displayId: 42),
         .init(index: 1, name: "Left", bounds: CGRect(x: -800, y: -100, width: 800, height: 600),
               desktops: [3], currentSpaceId: 3, displayId: 43)]
    }
    private func subject(_ projects: String = "{\"app\":\"Safari\"}") throws -> EditorSubject {
        try EditorSubject(data: Data("{\"layers\":[{\"id\":\"web\",\"label\":\"Web\",\"layout\":\"columns\",\"projects\":[\(projects)]}]}".utf8))
    }
    func testReadOnlyPreviewUsesNativePlannerAndPreservesInput() throws {
        let subject = try subject()
        let windows = [window(1), window(2)]
        let sources = LayerMembership.Sources(isContent: { _ in true }, isRunning: { _ in false })
        let visible = CGRect(x: 0, y: 24, width: 1200, height: 776)
        let geometry = EditorGeometry(windows: windows, displays: displays, mainID: 42,
                                      visibleFrame: visible, standardWindows: [1, 2])
        let revision = subject.revision, source = subject.source
        let projection = try subject.project(windows: windows, sources: sources, geometry: geometry)
        let groups = try XCTUnwrap(projection["groups"] as? [[String: Any]])
        let preview = try XCTUnwrap(groups[0]["preview"] as? [String: Any])
        XCTAssertEqual(preview["layout"] as? String, "columns")
        XCTAssertEqual(preview["displayId"] as? String, "42")
        let frames = try XCTUnwrap(preview["frames"] as? [[String: Any]])
        XCTAssertEqual(frames.count, 2)
        let expected = LayerLayout.frames(.columns, types: [.browser, .browser], aspect: 1200 / 776)
        for (item, box) in zip(frames, expected) {
            let raw = WindowTiler.tileFrame(fractions: (box.minX, box.minY, box.width, box.height), inDisplay: visible)
            let frame = try XCTUnwrap(item["frame"] as? [String: CGFloat])
            XCTAssertEqual(frame["x"], raw.minX.rounded())
            XCTAssertEqual(frame["w"], raw.maxX.rounded() - raw.minX.rounded())
        }
        XCTAssertEqual(subject.revision, revision)
        XCTAssertEqual(subject.source, source)
        XCTAssertEqual(windows[0].frame.x, 50)
        XCTAssertEqual(windows[1].frame.w, 400)
        let repeated = try subject.project(windows: windows, sources: sources, geometry: geometry)
        XCTAssertEqual(projection["snapshotId"] as? String, repeated["snapshotId"] as? String)
    }
    func testMissingEligibilityDoesNotInventPreviewAndUnknownFramesStayNull() throws {
        let subject = try subject()
        let unknown = WindowEntry(wid: 1, app: "Safari", pid: 1, title: "Unknown",
            frame: WindowFrame(x: 50, y: 50, w: 400, h: 300), spaceIds: [],
            isOnScreen: false, latticesSession: nil, zIndex: 0)
        let geometry = EditorGeometry(windows: [unknown], displays: displays, mainID: 42,
                                      visibleFrame: CGRect(x: 0, y: 24, width: 1200, height: 776))
        let projection = try subject.project(windows: [unknown], sources: .init(isContent: { _ in true }), geometry: geometry)
        let group = (projection["groups"] as! [[String: Any]])[0]
        XCTAssertNil(group["preview"])
        let row = (group["rows"] as! [[String: Any]])[0]
        XCTAssertTrue(row["frame"] is NSNull)
        XCTAssertEqual(row["frameSource"] as? String, "unavailable")
    }
    func testGeometryMatchesOverviewAndAmbiguousRuleHasNoIndex() throws {
        let entry = "{\"app\":\"Safari\"}"
        let subject = try subject(entry + "," + entry)
        let windows = [window(1, space: 2)]
        let geometry = EditorGeometry(windows: windows, displays: displays, mainID: 42)
        let projection = try subject.project(windows: windows, sources: .init(isContent: { _ in true }), geometry: geometry)
        let row = ((projection["groups"] as! [[String: Any]])[0]["rows"] as! [[String: Any]])[0]
        XCTAssertTrue(row["matchedRule"] is NSNull)
        XCTAssertEqual(row["frameSource"] as? String, "lastKnown")
        XCTAssertEqual(row["displayId"] as? String, "42")
        let frame = row["frame"] as! [String: CGFloat]
        XCTAssertEqual(frame["x"], geometry.rows[1]?.frame?.minX)
        let wire = projection["displays"] as! [[String: Any]]
        XCTAssertEqual((wire[1]["frame"] as! [String: CGFloat])["x"], -800)
        XCTAssertEqual(wire[0]["main"] as? Bool, true)
    }
    func testPlannerExcludesPlacedTuckedOtherDesktopAndUnverifiedWindows() throws {
        let members: [LayerMembership.Member] = [(window(1), false, 0), (window(2), true, 0),
                                                 (window(3, space: 2), false, 0), (window(4), false, 0)]
        let planned = LayerLayout.plan(.auto, members: members, excluding: [1], main: displays[0].bounds,
            otherDisplays: [displays[1].bounds], currentSpace: 1,
            visibleFrame: CGRect(x: 0, y: 24, width: 1200, height: 776), standardWindows: [1, 2, 3])
        XCTAssertTrue(planned.isEmpty)
    }
}
