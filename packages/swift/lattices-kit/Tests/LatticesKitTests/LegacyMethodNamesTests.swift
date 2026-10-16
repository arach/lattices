import XCTest
@testable import LatticesKit

final class LegacyMethodNamesTests: XCTestCase {
    func testNewNamesFallBackToOldNames() {
        XCTAssertEqual(LegacyMethodNames.fallback(for: "windows.place", params: nil), "window.place")
        XCTAssertEqual(LegacyMethodNames.fallback(for: "sessions.launch", params: nil), "session.launch")
        XCTAssertEqual(LegacyMethodNames.fallback(for: "search.query", params: nil), "lattices.search")
        XCTAssertNil(LegacyMethodNames.fallback(for: "windows.list", params: nil))
    }

    func testMergedMethodsPickTheOldNameFromParams() {
        XCTAssertEqual(LegacyMethodNames.fallback(for: "tmux.list", params: nil), "tmux.sessions")
        XCTAssertEqual(
            LegacyMethodNames.fallback(for: "tmux.list", params: .object(["includeOrphans": .bool(true)])),
            "tmux.inventory"
        )
        XCTAssertEqual(LegacyMethodNames.fallback(for: "ocr.history", params: nil), "ocr.recent")
        XCTAssertNil(LegacyMethodNames.fallback(for: "ocr.history", params: .object(["wid": .int(42)])))
    }

    func testOnlyAnUnknownMethodErrorForTheSameMethodTriggersFallback() {
        XCTAssertTrue(LegacyMethodNames.isUnknownMethod(
            LatticesError.daemonError("Unknown method: windows.place"), method: "windows.place"))
        XCTAssertFalse(LegacyMethodNames.isUnknownMethod(
            LatticesError.daemonError("Missing parameter: wid"), method: "windows.place"))
        XCTAssertFalse(LegacyMethodNames.isUnknownMethod(LatticesError.disconnected, method: "windows.place"))
    }
}
