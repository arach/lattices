import XCTest
@testable import Lattices

final class EditorLayoutTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 25, width: 3440, height: 1390)
    private var displays: [OverviewDisplay] {
        [.init(index: 0, name: "DELL", bounds: CGRect(x: 0, y: 0, width: 3440, height: 1440),
               desktops: [1, 2], currentSpaceId: 1, displayId: 42),
         .init(index: 1, name: "Left", bounds: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
               desktops: [3], currentSpaceId: 3, displayId: 43)]
    }
    private func window(_ id: UInt32, _ app: String, space: Int = 2,
                        frame: CGRect = CGRect(x: 100, y: 100, width: 600, height: 500)) -> WindowEntry {
        WindowEntry(wid: id, app: app, pid: 1, title: "Window \(id)",
                    frame: WindowFrame(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height),
                    spaceIds: [space], isOnScreen: space == 1 || space == 3, latticesSession: nil, zIndex: Int(id))
    }
    private func subject(_ projects: String, layout: String = "auto") throws -> EditorSubject {
        try EditorSubject(data: Data("{\"layers\":[{\"id\":\"talkie\",\"label\":\"Talkie\",\"layout\":\"\(layout)\",\"projects\":[\(projects)]}]}".utf8))
    }
    private func project(_ subject: EditorSubject, _ windows: [WindowEntry], standard: Set<UInt32> = []) throws -> [String: Any] {
        let geometry = EditorGeometry(windows: windows, displays: displays, mainID: 42, visibleFrame: visible,
                                      standardWindows: standard,
                                      visibleFrames: [43: CGRect(x: -1920, y: 25, width: 1920, height: 1055)])
        let projection = try subject.project(windows: windows, sources: .init(isContent: { _ in true }, isRunning: { _ in false }), geometry: geometry)
        return try XCTUnwrap((projection["groups"] as! [[String: Any]])[0]["layout"] as? [String: Any])
    }
    private func boxes(_ layout: [String: Any], _ key: String) -> [CGRect] {
        (layout[key] as! [[String: Any]]).compactMap { item in
            guard let b = item["unitFrame"] as? [String: CGFloat] else { return nil }
            return CGRect(x: b["x"]!, y: b["y"]!, width: b["w"]!, height: b["h"]!)
        }
    }
    func testTalkieDesignExistsOnOtherDesktopAndAllUsesNativeThirtyFortyThirty() throws {
        let subject = try subject(#"{"app":"Ghostty"},{"app":"Talkie"},{"app":"Xcode"},{"app":"Devin"},{"match":{"titleContains":"unknown app"}}"#)
        let windows = [window(1, "Ghostty"), window(2, "Ghostty"), window(3, "Talkie")]
        let revision = subject.revision, source = subject.source
        let layout = try project(subject, windows)
        XCTAssertEqual(boxes(layout, "openTargets"), [CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)])
        XCTAssertEqual(boxes(layout, "allTargets"), LayerLayout.frames(.auto,
            types: [.terminal, .other, .editor, .editor], aspect: visible.width / visible.height))
        let targets = layout["openTargets"] as! [[String: Any]]
        XCTAssertEqual(targets.map { $0["entryIndex"] as! Int }, [0, 0, 1])
        XCTAssertTrue(targets.allSatisfy { $0["status"] as? String == "wontMove" && $0["reason"] as? String == "on another desktop" })
        let lanes = (layout["lanes"] as! [String: Any])["all"] as! [[String: Any]]
        XCTAssertEqual(lanes.map { ($0["w"] as! CGFloat * 100).rounded() }, [30, 40, 30])
        let skipped = layout["skipped"] as! [[String: Any]]
        XCTAssertEqual(skipped.first?["entryIndex"] as? Int, 4)
        XCTAssertEqual(skipped.first?["reason"] as? String, "no app name")
        XCTAssertEqual(subject.revision, revision); XCTAssertEqual(subject.source, source)
        XCTAssertEqual(windows[0].frame.x, 100)
    }
    func testMovesStaysAndEligibilityDoNotRemoveDesignedTargets() throws {
        let subject = try subject(#"{"app":"Ghostty"},{"app":"Talkie"}"#)
        let left = WindowTiler.tileFrame(fractions: (0, 0, 0.5, 1), inDisplay: visible)
        let layout = try project(subject, [window(1, "Ghostty", space: 1, frame: left), window(2, "Talkie", space: 1)], standard: [1, 2])
        XCTAssertEqual((layout["openTargets"] as! [[String: Any]]).map { $0["status"] as! String }, ["stays", "moves"])
        let unavailable = try project(subject, [window(1, "Ghostty", space: 1), window(2, "Talkie", space: 3,
            frame: CGRect(x: -1800, y: 100, width: 600, height: 500))])
        XCTAssertEqual(boxes(unavailable, "openTargets").count, 2)
        XCTAssertTrue((unavailable["openTargets"] as! [[String: Any]]).allSatisfy { $0["status"] as? String == "wontMove" && !($0["reason"] as! String).isEmpty })
    }
    func testExplicitPlacementIsNotRedistributedAndUnknownPlacementIsSkipped() throws {
        let subject = try subject(#"{"app":"Ghostty","tile":"left","display":1},{"app":"Talkie"},{"app":"Xcode","display":1}"#)
        let layout = try project(subject, [window(1, "Ghostty"), window(2, "Talkie")])
        let open = layout["openTargets"] as! [[String: Any]]
        XCTAssertEqual(open[0]["displayId"] as? String, "43")
        XCTAssertEqual((open[0]["frame"] as! [String: CGFloat])["x"], -1920)
        XCTAssertEqual(boxes(layout, "openTargets")[1], LayerLayout.frames(.auto, types: [.other], aspect: visible.width / visible.height)[0])
        XCTAssertEqual((layout["skipped"] as! [[String: Any]]).first?["entryIndex"] as? Int, 2)
    }
    func testNoneAndDuplicateEntriesAreExplicit() throws {
        let subject = try subject(#"{"app":"Ghostty"},{"app":"Ghostty"}"#, layout: "none")
        let layout = try project(subject, [window(1, "Ghostty")])
        XCTAssertEqual(layout["kind"] as? String, "none")
        XCTAssertTrue(boxes(layout, "allTargets").isEmpty)
        XCTAssertEqual((layout["skipped"] as! [[String: Any]]).count, 2)
        XCTAssertEqual((layout["openTargets"] as! [[String: Any]])[0]["ambiguous"] as? Bool, true)
    }
}
