import XCTest
@testable import LatticesKit

final class JSONValueTests: XCTestCase {
    func testJSONValueRoundTripsObjects() throws {
        let value: JSONValue = [
            "session": "lattices-c36f74",
            "position": "right",
            "display": 1,
            "execute": true,
            "ratio": 0.5,
            "items": ["window", "tmux"],
        ]

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)

        XCTAssertEqual(decoded["session"]?.stringValue, "lattices-c36f74")
        XCTAssertEqual(decoded["display"]?.intValue, 1)
        XCTAssertEqual(decoded["ratio"]?.doubleValue, 0.5)
        XCTAssertEqual(decoded["items"]?[1]?.stringValue, "tmux")
    }

    func testDecodesDaemonModels() throws {
        let value: JSONValue = [
            "wid": 42,
            "app": "iTerm2",
            "pid": 1234,
            "title": "[lattices:lattices-c36f74] zsh",
            "frame": ["x": 0.0, "y": 24.0, "w": 800.0, "h": 600.0],
            "spaceIds": [7],
            "isOnScreen": true,
            "latticesSession": "lattices-c36f74",
        ]

        let window = try value.decoded(as: LatticesWindow.self)

        XCTAssertEqual(window.wid, 42)
        XCTAssertEqual(window.frame.w, 800)
        XCTAssertEqual(window.latticesSession, "lattices-c36f74")
    }

    func testWindowTargetBuildsSparseParams() {
        let target = LatticesWindowTarget.app("Scout", title: "Inbox")

        XCTAssertEqual(target.json["app"]?.stringValue, "Scout")
        XCTAssertEqual(target.json["title"]?.stringValue, "Inbox")
        XCTAssertNil(target.json["wid"])
    }
}
