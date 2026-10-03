import XCTest
@testable import Lattices

final class EditorActionsTests: XCTestCase {
    private func snapshot(_ label: String = "Web") throws -> EditorBridge.Snapshot {
        let source = try EditorSubject(data: Data("""
        {"layers":[{"id":"web","label":"\(label)","projects":[{"app":"Safari"}]}]}
        """.utf8))
        return .init(subject: source, projection: try source.project(windows: [], sources: .init(isRunning: { _ in false })))
    }

    func testPlansArePureAndConfirmationIsSingleUse() throws {
        var operations: [EditorActions.Operation] = []
        let actions = EditorActions(execute: { operations.append($0); return [:] }, reveal: { [:] })
        let snap = try snapshot()
        XCTAssertEqual(actions.confirm("", snapshot: { snap })["ok"] as? Bool, false)
        for kind in ["gather", "open"] {
            let count = operations.count
            let plan = try actions.plan(["kind": kind, "layerId": "web"], snapshot: snap)
            XCTAssertEqual(operations.count, count)
            let id = try XCTUnwrap(plan["planId"] as? String)
            XCTAssertEqual(actions.confirm(id, snapshot: { snap })["ok"] as? Bool, true)
            XCTAssertEqual(operations.count, count + 1)
            XCTAssertEqual(operations.last?.mode, kind == "gather" ? "focus" : "launch")
            XCTAssertEqual(actions.confirm(id, snapshot: { snap })["ok"] as? Bool, false)
            XCTAssertEqual(operations.count, count + 1)
        }
    }

    func testExpiredAndStalePlansNeverExecute() throws {
        var now = Date()
        var executions = 0
        let actions = EditorActions(now: { now }, execute: { _ in executions += 1; return [:] }, reveal: { [:] })
        let snap = try snapshot()
        let plan = try actions.plan(["kind": "gather", "layerId": "web"], snapshot: snap)
        now.addTimeInterval(61)
        XCTAssertEqual(actions.confirm(plan["planId"] as! String, snapshot: { snap })["ok"] as? Bool, false)
        let fresh = try actions.plan(["kind": "gather", "layerId": "web"], snapshot: snap)
        XCTAssertEqual(actions.confirm(fresh["planId"] as! String, snapshot: { try self.snapshot("Changed") })["ok"] as? Bool, false)
        XCTAssertEqual(executions, 0)
    }

    func testOpenPlanPromisesNoStaging() throws {
        let actions = EditorActions(execute: { _ in XCTFail("Planning executed"); return [:] }, reveal: { [:] })
        let plan = try actions.plan(["kind": "open", "layerId": "web"], snapshot: snapshot())
        XCTAssertEqual(plan["putAwayCount"] as? Int, 0)
        XCTAssertEqual(plan["layoutCount"] as? Int, 0)
        XCTAssertEqual((plan["entries"] as? [[String: Any]])?.count, 1)
    }

    func testPassiveBridgeRequestsCannotExecute() throws {
        let snap = try snapshot()
        var effects = 0
        let bridge = EditorBridge(hostChrome: true, capture: { snap })
        bridge.actions = EditorActions(execute: { _ in effects += 1; return [:] }, reveal: { effects += 1; return [:] })
        for kind in ["capabilities", "subject.read", "preview.project", "events.subscribe"] {
            _ = bridge.reply(to: ["v": 1, "requestId": kind, "subjectId": EditorSubject.id,
                "revision": snap.subject.revision, "kind": kind, "payload": [:]])
        }
        bridge.selectLayers(["web"])
        bridge.sendUICommand("view", value: "overview")
        bridge.poll()
        XCTAssertEqual(effects, 0)
    }
    func testAssistantHasNoToolOrConfigurationFallback() {
        let arguments = EditorAssistantTransport.arguments
        for (flag, value) in [("--tools", ""), ("--mcp-config", "{\"mcpServers\":{}}"),
                              ("--setting-sources", ""), ("--settings", "{\"disableAllHooks\":true}")] {
            guard let at = arguments.firstIndex(of: flag) else { return XCTFail("Missing " + flag) }
            XCTAssertEqual(arguments[at + 1], value)
        }
        XCTAssertTrue(arguments.contains("--strict-mcp-config"))
        XCTAssertTrue(arguments.contains("--disable-slash-commands"))
    }

}
