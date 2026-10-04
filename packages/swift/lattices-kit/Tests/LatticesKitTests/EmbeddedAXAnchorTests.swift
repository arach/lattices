import CoreGraphics
import XCTest
@testable import LatticesKit

/// Synthetic accessibility trees: nothing here reads or drives a real app.
private final class FakeNode: EmbeddedAXAnchorNode {
    let name: String
    let anchorRole: String?
    let anchorValue: String?
    var kids: EmbeddedAXChildren<FakeNode>

    init(_ name: String, role: String? = "AXGroup", value: String? = nil, kids: [FakeNode]? = nil, failed: Bool = false) {
        self.name = name
        self.anchorRole = role
        self.anchorValue = value
        if failed {
            self.kids = .failed
        } else if let kids {
            self.kids = .children(kids)
        } else {
            self.kids = .leaf
        }
    }

    func anchorChildren() -> EmbeddedAXChildren<FakeNode> { kids }
}

private final class FakeApp: EmbeddedAXAnchorApplication {
    var root: FakeNode
    var enhanced: Bool?
    var setSucceeds = true
    var focusSucceeds = true
    var foreign: Set<String> = []
    /// Tree published once the enhanced flag is on, as Chromium does.
    var exposedRoot: FakeNode?
    private(set) var flagWrites: [Bool] = []
    private(set) var focused: [String] = []

    init(root: FakeNode, enhanced: Bool? = false) {
        self.root = root
        self.enhanced = enhanced
    }

    func enhancedUserInterface() -> Bool? { enhanced }

    func setEnhancedUserInterface(_ enabled: Bool) -> Bool {
        flagWrites.append(enabled)
        guard setSucceeds else { return false }
        enhanced = enabled
        if enabled, let exposedRoot { root = exposedRoot }
        return true
    }

    func owns(_ node: FakeNode) -> Bool { !foreign.contains(node.name) }

    func focus(_ node: FakeNode) -> Bool {
        focused.append(node.name)
        return focusSucceeds
    }
}

private let textRoles: Set<String> = ["AXTextArea", "AXTextField"]

private func composer(_ name: String, _ value: String, role: String = "AXTextArea") -> FakeNode {
    FakeNode(name, role: role, value: value)
}

private func window(_ kids: [FakeNode]) -> FakeNode {
    FakeNode("app", role: "AXApplication", kids: [FakeNode("window", role: "AXWindow", kids: kids)])
}

/// A clock that advances only when the poll loop sleeps.
private final class FakeClock {
    var now = Date(timeIntervalSince1970: 0)
    var sleeps = 0
    func sleep(_ interval: TimeInterval) {
        sleeps += 1
        now = now.addingTimeInterval(interval)
    }
}

private func focus(
    _ value: String,
    in app: FakeApp,
    limits: EmbeddedAXAnchorLimits = .standard,
    timeout: TimeInterval = 1,
    clock: FakeClock = FakeClock()
) throws -> (node: FakeNode, depth: Int) {
    try EmbeddedAXAnchor.focusUnique(
        holding: value,
        in: app,
        roles: textRoles,
        limits: limits,
        exposeTimeout: timeout,
        now: { clock.now },
        sleep: clock.sleep
    )
}

private func assertNotFound(_ body: @autoclosure () throws -> Any, containing fragment: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try body(), file: file, line: line) { error in
        guard case .elementNotFound(let detail)? = error as? EmbeddedLatticesError else {
            return XCTFail("Expected elementNotFound, got \(error)", file: file, line: line)
        }
        XCTAssertTrue(detail.contains(fragment), "\(detail) lacks \(fragment)", file: file, line: line)
    }
}

final class EmbeddedAXAnchorTests: XCTestCase {
    // MARK: Matching

    func testFocusesTheOnlyElementHoldingTheText() throws {
        let app = FakeApp(root: window([
            composer("other", "something else"),
            FakeNode("pane", kids: [composer("target", "ship  it\n now", role: "AXTextField")]),
        ]))

        let hit = try focus("ship it now", in: app)

        XCTAssertEqual(hit.node.name, "target")
        XCTAssertEqual(hit.depth, 3)
        XCTAssertEqual(app.focused, ["target"])
        XCTAssertEqual(app.flagWrites, [], "A direct hit never touches the enhanced flag")
    }

    func testIgnoresMatchingTextOutsideTheRequestedRoles() {
        let app = FakeApp(root: window([FakeNode("label", role: "AXStaticText", value: "hello")]), enhanced: true)

        assertNotFound(try focus("hello", in: app), containing: "No text element")
        XCTAssertEqual(app.focused, [])
    }

    func testRequiresWholeValueNotSubstring() {
        let app = FakeApp(root: window([composer("c", "hello world")]), enhanced: true)

        assertNotFound(try focus("hello", in: app), containing: "No text element")
    }

    func testRejectsEmptyAnchor() {
        let app = FakeApp(root: window([composer("c", "")]))

        assertNotFound(try focus(" \n\t", in: app), containing: "empty value")
        XCTAssertEqual(app.flagWrites, [])
    }

    // MARK: Ambiguity

    func testRejectsTwoElementsHoldingTheSameText() {
        let app = FakeApp(root: window([composer("a", "draft"), FakeNode("g", kids: [composer("b", "draft ")])]))

        assertNotFound(try focus("draft", in: app), containing: "More than one")
        XCTAssertEqual(app.focused, [], "Nothing is focused when the anchor is ambiguous")
    }

    func testAmbiguityAfterExposureStillFailsAndRestoresFlag() {
        let app = FakeApp(root: window([]))
        app.exposedRoot = window([composer("a", "draft"), composer("b", "draft")])

        assertNotFound(try focus("draft", in: app), containing: "More than one")
        XCTAssertEqual(app.flagWrites, [true, false])
        XCTAssertEqual(app.enhanced, false)
        XCTAssertEqual(app.focused, [])
    }

    func testRejectsMatchOwnedByAnotherProcess() {
        let app = FakeApp(root: window([composer("embedded", "draft")]))
        app.foreign = ["embedded"]

        assertNotFound(try focus("draft", in: app), containing: "another process")
        XCTAssertEqual(app.focused, [])
    }

    func testFocusFailureThrows() {
        let app = FakeApp(root: window([composer("c", "draft")]))
        app.focusSucceeds = false

        assertNotFound(try focus("draft", in: app), containing: "Couldn't focus")
    }

    // MARK: Traversal limits

    func testElementLimitMakesALoneMatchIncomplete() {
        // The match is found early, but a duplicate could sit past the limit.
        let fillers = (0..<10).map { FakeNode("f\($0)") }
        let app = FakeApp(root: window([composer("c", "draft")] + fillers), enhanced: true)

        assertNotFound(
            try focus("draft", in: app, limits: EmbeddedAXAnchorLimits(maxDepth: 64, maxElements: 5)),
            containing: "more than 5 elements"
        )
        XCTAssertEqual(app.focused, [])
    }

    func testTreeThatFitsTheElementLimitExactlyIsComplete() throws {
        // app, window, composer: three elements.
        let app = FakeApp(root: window([composer("c", "draft")]))

        let hit = try focus("draft", in: app, limits: EmbeddedAXAnchorLimits(maxDepth: 64, maxElements: 3))
        XCTAssertEqual(hit.node.name, "c")
    }

    func testDepthLimitWithUnreadChildrenIsIncomplete() {
        let deep = FakeNode("d1", kids: [FakeNode("d2", kids: [composer("dupe", "draft")])])
        let app = FakeApp(root: window([composer("c", "draft"), deep]), enhanced: true)

        assertNotFound(
            try focus("draft", in: app, limits: EmbeddedAXAnchorLimits(maxDepth: 2, maxElements: 100)),
            containing: "deeper than 2"
        )
    }

    func testDepthLimitOnLeavesIsNotIncomplete() throws {
        let app = FakeApp(root: window([composer("c", "draft")]))

        let hit = try focus("draft", in: app, limits: EmbeddedAXAnchorLimits(maxDepth: 2, maxElements: 100))
        XCTAssertEqual(hit.node.name, "c")
    }

    func testUnreadableChildrenMakeTraversalIncomplete() {
        let app = FakeApp(root: window([composer("c", "draft"), FakeNode("broken", failed: true)]), enhanced: true)

        assertNotFound(try focus("draft", in: app), containing: "Couldn't read")
        XCTAssertEqual(app.focused, [])
    }

    func testCyclicTreeIsBoundedByTheElementLimit() {
        let loop = FakeNode("loop")
        loop.kids = .children([loop])
        let app = FakeApp(root: loop, enhanced: true)

        assertNotFound(
            try focus("draft", in: app, limits: EmbeddedAXAnchorLimits(maxDepth: 1_000_000, maxElements: 50)),
            containing: "more than 50"
        )
    }

    // MARK: AXEnhancedUserInterface

    func testExposesWebContentThenRestoresFlag() throws {
        let app = FakeApp(root: window([]))
        app.exposedRoot = window([FakeNode("web", kids: [composer("c", "draft")])])

        let hit = try focus("draft", in: app)

        XCTAssertEqual(hit.node.name, "c")
        XCTAssertEqual(app.flagWrites, [true, false])
        XCTAssertEqual(app.enhanced, false)
    }

    func testRestoresFlagWhenNothingAppearsBeforeTimeout() {
        let app = FakeApp(root: window([]))
        let clock = FakeClock()

        assertNotFound(try focus("draft", in: app, timeout: 1, clock: clock), containing: "No text element")
        XCTAssertEqual(app.flagWrites, [true, false])
        XCTAssertEqual(app.enhanced, false)
        XCTAssertEqual(clock.sleeps, 4, "Polls every 0.25s for the 1s timeout, then gives up")
    }

    func testLeavesFlagAloneWhenAlreadyOn() {
        let app = FakeApp(root: window([]), enhanced: true)

        assertNotFound(try focus("draft", in: app), containing: "No text element")
        XCTAssertEqual(app.flagWrites, [])
        XCTAssertEqual(app.enhanced, true)
    }

    func testLeavesFlagAloneWhenUnreadable() {
        let app = FakeApp(root: window([]), enhanced: nil)

        assertNotFound(try focus("draft", in: app), containing: "No text element")
        XCTAssertEqual(app.flagWrites, [])
    }

    func testDoesNotWriteFlagBackWhenTurningItOnFailed() {
        let app = FakeApp(root: window([]))
        app.setSucceeds = false
        let clock = FakeClock()

        assertNotFound(try focus("draft", in: app, clock: clock), containing: "No text element")
        XCTAssertEqual(app.flagWrites, [true], "Only the failed attempt; no restore of a flag we never set")
        XCTAssertEqual(clock.sleeps, 0, "No waiting when the content can't be exposed")
    }

    func testRestoresFlagWhenExposedTreeIsIncomplete() {
        let app = FakeApp(root: window([]))
        app.exposedRoot = window([FakeNode("broken", failed: true)])

        assertNotFound(try focus("draft", in: app), containing: "Couldn't read")
        XCTAssertEqual(app.flagWrites, [true, false])
    }

    // MARK: Process-targeted key press

    func testKeyPressPostsDownAndUpToTheTargetProcessOnly() throws {
        var posted: [(keyDown: Bool, keyCode: Int64, flags: CGEventFlags, pid: pid_t)] = []

        try EmbeddedProcessKeyPress.press("cmd+return", pid: 4242) { event, pid in
            posted.append((
                event.type == .keyDown,
                event.getIntegerValueField(.keyboardEventKeycode),
                event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]),
                pid
            ))
        }

        XCTAssertEqual(posted.count, 2)
        XCTAssertEqual(posted.map(\.keyDown), [true, false])
        XCTAssertEqual(posted.map(\.keyCode), [36, 36])
        XCTAssertEqual(posted.map(\.flags), [.maskCommand, .maskCommand])
        XCTAssertEqual(posted.map(\.pid), [4242, 4242])
    }

    func testKeyPressRejectsMissingProcessWithoutPosting() {
        for pid: pid_t in [0, -1] {
            var posts = 0
            XCTAssertThrowsError(try EmbeddedProcessKeyPress.press("return", pid: pid) { _, _ in posts += 1 }) { error in
                guard case .invalidConfig? = error as? EmbeddedLatticesError else {
                    return XCTFail("Expected invalidConfig, got \(error)")
                }
            }
            XCTAssertEqual(posts, 0, "pid \(pid) must not fall back to a global post")
        }
    }

    func testKeyPressRejectsUnknownKeyWithoutPosting() {
        var posts = 0
        XCTAssertThrowsError(try EmbeddedProcessKeyPress.press("hyper+banana", pid: 4242) { _, _ in posts += 1 })
        XCTAssertEqual(posts, 0)
    }
}
