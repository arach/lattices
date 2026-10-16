import XCTest
@testable import Lattices

final class EditorUndoTests: XCTestCase {
    private func window(_ x: Double = 0, pid: Int32 = 10) -> EditorUndo.WindowState {
        .init(id: 1, pid: pid, frame: CGRect(x: x, y: 0, width: 500, height: 300), displayId: "main")
    }
    func testRestoresFramesAndParkedWindowsInReverseOrder() throws {
        let stack = EditorUndo()
        stack.record(.init(actionId: "a", label: "Gather", at: Date(), opened: false,
                           moves: [.frame(before: window(), after: window(20), parked: true), .hide(pid: 10, wasHidden: false)]))
        var order: [String] = []
        let result = try stack.undo("a", environment: .init(window: { _ in self.window(20) },
            restore: { state, parked in
                XCTAssertEqual(state.frame.minX, 0); XCTAssertTrue(parked)
                order.append("frame"); return true
            }, isHidden: { _ in true }, unhide: { _ in order.append("unhide"); return true }))
        XCTAssertEqual(order, ["unhide", "frame"])
        XCTAssertEqual(result.restored, 2)
        XCTAssertNil(stack.newestUndoableActionId)
    }
    func testMovedAndClosedWindowsAreSkipped() throws {
        for current in [window(100), nil, window(20, pid: 999)] {
            let stack = EditorUndo()
            stack.record(.init(actionId: "a", label: "Gather", at: Date(), opened: false,
                               moves: [.frame(before: window(), after: window(20), parked: false)]))
            let result = try stack.undo("a", environment: .init(window: { _ in current },
                restore: { _, _ in XCTFail("Must not fight user changes"); return true },
                isHidden: { _ in false }, unhide: { _ in false }))
            XCTAssertEqual(result.restored, 0)
            XCTAssertEqual(result.skipped.count, 1)
        }
    }
    func testAlreadyHiddenAppsStayHidden() throws {
        let stack = EditorUndo()
        stack.record(.init(actionId: "a", label: "Gather", at: Date(), opened: false,
                           moves: [.hide(pid: 10, wasHidden: true)]))
        _ = try stack.undo("a", environment: .init(window: { _ in nil }, restore: { _, _ in false },
            isHidden: { _ in true }, unhide: { _ in XCTFail("Was already hidden"); return false }))
    }
    func testNewestOnlySingleUseAndTenEntryLimit() throws {
        let stack = EditorUndo()
        let environment = EditorUndo.Environment(window: { _ in nil }, restore: { _, _ in false },
                                                 isHidden: { _ in nil }, unhide: { _ in false })
        for id in 0..<12 {
            stack.record(.init(actionId: "\(id)", label: "Open", at: Date(), opened: true, moves: []))
        }
        XCTAssertEqual(stack.entries.count, 10)
        XCTAssertThrowsError(try stack.undo("10", environment: environment))
        XCTAssertTrue(try stack.undo("11", environment: environment).openedAppsStayOpen)
        XCTAssertThrowsError(try stack.undo("11", environment: environment))
        XCTAssertEqual(stack.newestUndoableActionId, "10")
        _ = try stack.undo("10", environment: environment)
    }
}
