import AppKit
import SwiftUI
import XCTest
@testable import Lattices

final class SpaceSwitchBezelTests: XCTestCase {
    private func window(_ id: UInt32, _ app: String, space: Int, z: Int) -> WindowEntry {
        WindowEntry(wid: id, app: app, pid: 1, title: "Window \(id)",
                    frame: WindowFrame(x: 0, y: 0, w: 800, h: 600),
                    spaceIds: [space], isOnScreen: true, latticesSession: nil, zIndex: z)
    }

    func testSpaceIsNamedByItsAppsFrontmostFirst() {
        let windows = [
            window(1, "Safari", space: 3, z: 4),
            window(2, "Ghostty", space: 3, z: 1),
            window(3, "Ghostty", space: 3, z: 2),
            window(4, "Lattices", space: 3, z: 0),
            window(5, "Notes", space: 7, z: 3),
        ]
        XCTAssertEqual(SpaceSwitchBezel.apps(onSpace: 3, in: windows), ["Ghostty", "Safari"])
        XCTAssertEqual(SpaceSwitchBezel.apps(onSpace: 9, in: windows), [])
    }

    func testSpaceNameKeepsToThreeApps() {
        let windows = ["A", "B", "C", "D"].enumerated().map { window(UInt32($0.offset), $0.element, space: 1, z: $0.offset) }
        XCTAssertEqual(SpaceSwitchBezel.apps(onSpace: 1, in: windows), ["A", "B", "C"])
    }

    /// Writes the tray to SPACE_BEZEL_RENDER_DIR for review.
    @MainActor
    func testRenderTray() throws {
        guard let dir = ProcessInfo.processInfo.environment["SPACE_BEZEL_RENDER_DIR"] else {
            throw XCTSkip("Set SPACE_BEZEL_RENDER_DIR to render the tray")
        }
        let cases: [(String, Int, Int?, Int, [String])] = [
            ("right", 1, 3, 14, ["Ghostty", "Google Chrome", "Scout"]),
            ("left", -1, 2, 4, ["Xcode"]),
            ("empty", 1, 5, 6, []),
            ("edge", 1, nil, 4, []),
        ]
        for (name, direction, target, total, apps) in cases {
            let state = SpaceBezelState()
            state.direction = direction
            state.activeIndex = target ?? total
            state.edge = target == nil
            state.total = total
            state.apps = apps
            let renderer = ImageRenderer(content: SpaceSwitchBezelView(state: state).background(Color(white: 0.5)))
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                XCTFail("render failed for \(name)"); continue
            }
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("space-tray-\(name).png"))
        }
    }
}
