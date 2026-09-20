import CoreGraphics
import XCTest
@testable import Lattices

final class GridLayoutConfigTests: XCTestCase {
    func testDecodesLegacyTiledLayout() throws {
        let json = """
        {
          "layouts": {
            "split": {
              "windows": [
                { "app": "Ghostty", "tile": "left" },
                { "app": "Safari", "tile": "right", "title": "Docs" }
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(GridFile.self, from: json)
        let layout = try XCTUnwrap(file.layouts?["split"])
        XCTAssertEqual(layout.windows.count, 2)
        XCTAssertEqual(layout.windows[0].tile, "left")
        XCTAssertEqual(layout.windows[1].title, "Docs")
        XCTAssertFalse(layout.usesMasterStack)
        guard case .named("left") = layout.placement(at: 0) else {
            return XCTFail("expected named left tile")
        }
    }

    func testDecodesMasterStackLayoutWithoutTiles() throws {
        let json = """
        {
          "layouts": {
            "command-center": {
              "engine": "master-stack",
              "gap": 4,
              "masterRatio": 0.62,
              "masterCount": 1,
              "management": {
                "reconcile": "lifecycle",
                "ambiguity": "fail",
                "fullscreen": "skip",
                "debounceMilliseconds": 250
              },
              "windows": [
                { "id": "assistant", "app": "ChatGPT", "title": "ChatGPT" },
                { "id": "agents", "app": "Scout", "title": "Scout" },
                { "id": "talkie", "app": "Talkie", "title": "Talkie" }
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let file = try JSONDecoder().decode(GridFile.self, from: json)
        let layout = try XCTUnwrap(file.layouts?["command-center"])
        XCTAssertTrue(layout.usesMasterStack)
        XCTAssertEqual(layout.masterRatio, 0.62)
        XCTAssertEqual(layout.windows[0].id, "assistant")
        XCTAssertNil(layout.windows[0].tile)

        let master = try XCTUnwrap(layout.masterStackFractions(at: 0))
        XCTAssertEqual(master.x, 0, accuracy: 0.0001)
        XCTAssertEqual(master.y, 0, accuracy: 0.0001)
        XCTAssertEqual(master.w, 0.62, accuracy: 0.0001)
        XCTAssertEqual(master.h, 1, accuracy: 0.0001)

        let stackTop = try XCTUnwrap(layout.masterStackFractions(at: 1))
        XCTAssertEqual(stackTop.x, 0.62, accuracy: 0.0001)
        XCTAssertEqual(stackTop.y, 0, accuracy: 0.0001)
        XCTAssertEqual(stackTop.w, 0.38, accuracy: 0.0001)
        XCTAssertEqual(stackTop.h, 0.5, accuracy: 0.0001)

        let stackBottom = try XCTUnwrap(layout.masterStackFractions(at: 2))
        XCTAssertEqual(stackBottom.x, 0.62, accuracy: 0.0001)
        XCTAssertEqual(stackBottom.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(stackBottom.w, 0.38, accuracy: 0.0001)
        XCTAssertEqual(stackBottom.h, 0.5, accuracy: 0.0001)
    }

    func testDescribeDecodingErrorNamesMissingKey() {
        struct NeedsTile: Decodable { let tile: String }
        let data = Data(#"{}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(NeedsTile.self, from: data)) { error in
            let message = WorkspaceManager.describeDecodingError(error)
            XCTAssertTrue(message.contains("missing key 'tile'"), message)
        }
    }
}
