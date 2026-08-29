@testable import ActionCore
import CoreGraphics
import Foundation
import XCTest

final class ActionWorkspaceDragFileTests: XCTestCase {
    func testProtocolMethodAndExactRequestEncoding() throws {
        XCTAssertEqual(ActionAgentMethod.workspaceDragFile.rawValue, "workspace.dragFile")
        let params = validParams()
        let request = ActionAgentRequest(id: "request-1", method: ActionAgentMethod.workspaceDragFile.rawValue, params: params)
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ActionAgentRequest.self, from: data)
        XCTAssertEqual(decoded.id, "request-1")
        XCTAssertEqual(decoded.method, "workspace.dragFile")
        XCTAssertEqual(decoded.params, params)
    }

    func testPerLaunchCapabilityTokenFileIsUserOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("action-auth-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let authentication = try ActionAgentAuthentication.create(rootURL: root)
        XCTAssertTrue(authentication.matches(authentication.token))
        XCTAssertFalse(authentication.matches(authentication.token + "x"))
        let attributes = try FileManager.default.attributesOfItem(atPath: authentication.tokenFile.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)
        let stored = try String(contentsOf: authentication.tokenFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(stored, authentication.token)
        XCTAssertNoThrow(try authentication.authorize(
            params: ["protocolVersion": "2", "authToken": authentication.token],
            protocolVersion: "2"
        ))
        XCTAssertThrowsError(try authentication.authorize(
            params: ["protocolVersion": "1", "authToken": authentication.token],
            protocolVersion: "2"
        )) { error in
            guard case ActionAgentAuthenticationError.protocolVersionRequired("2") = error else {
                return XCTFail("Expected protocol negotiation failure, got \(error)")
            }
        }
        XCTAssertThrowsError(try authentication.authorize(
            params: ["protocolVersion": "2", "authToken": "wrong"],
            protocolVersion: "2"
        )) { error in
            guard case ActionAgentAuthenticationError.invalidToken = error else {
                return XCTFail("Expected authentication failure, got \(error)")
            }
        }
    }

    func testSemanticRequestRejectsCoordinateAndArbitraryDestinationInputs() throws {
        var params = validParams()
        params["fromX"] = "400"
        XCTAssertThrowsError(try ActionWorkspaceDragFileRequest(params: params)) { error in
            XCTAssertTrue(error.localizedDescription.contains("unsupported parameters"))
        }

        params = validParams()
        params["destinationBundleId"] = "com.apple.finder"
        XCTAssertThrowsError(try ActionWorkspaceDragFileRequest(params: params)) { error in
            XCTAssertTrue(error.localizedDescription.contains(ActionWorkspaceDragFileRequest.scoutBundleID))
        }
    }

    func testFixtureMustBeExactRegularRunScopedFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openscout-action-drag-drop-run-1", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = root.appendingPathComponent("Scout handoff.txt")
        try Data("handoff\n".utf8).write(to: fixture)

        var params = validParams()
        params["fixtureURL"] = fixture.absoluteString
        let request = try ActionWorkspaceDragFileRequest(params: params)
        XCTAssertNoThrow(try request.validateFixture())

        params["fixtureURL"] = root.appendingPathComponent("other.txt").absoluteString
        XCTAssertThrowsError(try ActionWorkspaceDragFileRequest(params: params))
    }

    func testResolvedGeometryMustStayWithinDisplayAndExactWindows() throws {
        let display = CGRect(x: 1_000, y: 0, width: 1_200, height: 900)
        let valid = ActionWorkspaceDragResolution(
            source: CGPoint(x: 1_200, y: 300),
            destination: CGPoint(x: 1_800, y: 300),
            finderWindowFrame: CGRect(x: 1_050, y: 100, width: 500, height: 700),
            destinationWindowFrame: CGRect(x: 1_600, y: 100, width: 500, height: 700)
        )
        XCTAssertNoThrow(try ActionWorkspaceDragFileOperation.validate(resolution: valid, inside: display))

        let escaped = ActionWorkspaceDragResolution(
            source: valid.source,
            destination: CGPoint(x: 999, y: 300),
            finderWindowFrame: valid.finderWindowFrame,
            destinationWindowFrame: valid.destinationWindowFrame
        )
        XCTAssertThrowsError(try ActionWorkspaceDragFileOperation.validate(resolution: escaped, inside: display))
    }

    func testGestureSuccessPostsMouseUpAndRestoresPointer() throws {
        let backend = RecordingPointerBackend(pointer: CGPoint(x: 42, y: 24))
        let engine = ActionPointerGestureEngine(backend: backend)
        try engine.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200)) {}

        let events = backend.events
        XCTAssertTrue(events.contains("down:100.0,100.0"))
        XCTAssertTrue(events.contains("up:200.0,200.0"))
        XCTAssertEqual(events.last, "warp:42.0,24.0")
    }

    func testCancellationDuringInterpolationStillPostsMouseUpAndRestoresPointer() throws {
        let backend = RecordingPointerBackend(pointer: CGPoint(x: 42, y: 24))
        let engine = ActionPointerGestureEngine(backend: backend)
        var checks = 0
        XCTAssertThrowsError(
            try engine.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200)) {
                checks += 1
                if checks == 5 { throw ActionWorkspaceDragFileError.cancelled }
            }
        ) { error in
            XCTAssertEqual(error as? ActionWorkspaceDragFileError, .cancelled)
        }

        let events = backend.events
        XCTAssertTrue(events.contains(where: { $0.hasPrefix("up:") }))
        XCTAssertEqual(events.last, "warp:42.0,24.0")
    }

    func testDragEventFailureStillPostsMouseUpAndRestoresPointer() throws {
        let backend = RecordingPointerBackend(pointer: CGPoint(x: 42, y: 24), failFirstDrag: true)
        let engine = ActionPointerGestureEngine(backend: backend)
        XCTAssertThrowsError(
            try engine.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200)) {}
        )
        let events = backend.events
        XCTAssertTrue(events.contains(where: { $0.hasPrefix("up:") }))
        XCTAssertEqual(events.last, "warp:42.0,24.0")
    }

    func testSameConnectionCancelRunsWhileDragIsInFlightAndCleansUp() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("action-concurrent-cancel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtureDirectory = root.appendingPathComponent(
            "openscout-action-drag-drop-run-1",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        let fixtureURL = fixtureDirectory.appendingPathComponent("Scout handoff.txt")
        try Data("handoff\n".utf8).write(to: fixtureURL)

        let store = ActionDriveLeaseStore(
            rootURL: root.appendingPathComponent("leases", isDirectory: true),
            publishesPresence: false
        )
        let ownerID = "connection-1"
        let begun = try await store.begin(
            ownerID: ownerID,
            agent: "Agent A",
            task: "action-drag-drop",
            mode: "attention",
            sessionID: "session-run-1",
            implicit: false,
            attentionApproval: "approved",
            capability: ActionWorkspaceDragFileRequest.capability,
            resource: ActionWorkspaceDragFileRequest.systemPointerResource,
            workflowRunID: "run-1",
            workspaceID: "agent:grok.main"
        )
        var params = validParams()
        params["leaseId"] = begun.lease.leaseId
        params["fixtureURL"] = fixtureURL.absoluteString
        let request = try ActionWorkspaceDragFileRequest(params: params)

        let mouseDown = DispatchSemaphore(value: 0)
        let cancellationWritten = DispatchSemaphore(value: 0)
        let backend = CoordinatedPointerBackend(
            pointer: CGPoint(x: 42, y: 24),
            mouseDown: mouseDown,
            cancellationWritten: cancellationWritten
        )
        let operation = ActionWorkspaceDragFileOperation(
            driveStore: store,
            resolver: FixedWorkspaceDragResolver(),
            gestureEngine: ActionPointerGestureEngine(backend: backend),
            cursorCue: ImmediateCursorCue()
        )
        let scheduler = ActionAgentRequestScheduler(
            responseQueue: DispatchQueue(label: "action.tests.responses")
        )
        let recorder = ConcurrentResponseRecorder()
        let dragReplied = expectation(description: "drag replied")
        let cancelReplied = expectation(description: "cancel replied")

        scheduler.dispatch(
            receiveNext: {
                DispatchQueue.global().async {
                    guard mouseDown.wait(timeout: .now() + 2) == .success else { return }
                    scheduler.dispatch(
                        receiveNext: {},
                        process: {
                            do {
                                _ = try await store.cancelWorkspaceOperation(
                                    ownerID: ownerID,
                                    leaseID: begun.lease.leaseId,
                                    operationID: request.operationID
                                )
                                cancellationWritten.signal()
                                return ActionAgentResponse(id: "cancel", ok: true)
                            } catch {
                                cancellationWritten.signal()
                                return ActionAgentResponse(
                                    id: "cancel",
                                    ok: false,
                                    error: error.localizedDescription
                                )
                            }
                        },
                        send: { response in
                            recorder.append(response)
                            cancelReplied.fulfill()
                        }
                    )
                }
            },
            process: {
                do {
                    _ = try await operation.execute(request: request, ownerID: ownerID)
                    return ActionAgentResponse(id: "drag", ok: true)
                } catch {
                    return ActionAgentResponse(id: "drag", ok: false, error: error.localizedDescription)
                }
            },
            send: { response in
                recorder.append(response)
                dragReplied.fulfill()
            }
        )

        await fulfillment(of: [cancelReplied, dragReplied], timeout: 3)
        let responses = recorder.responses
        XCTAssertEqual(responses.first(where: { $0.id == "cancel" })?.ok, true)
        XCTAssertEqual(responses.first(where: { $0.id == "drag" })?.ok, false)
        XCTAssertTrue(
            responses.first(where: { $0.id == "drag" })?.error?.contains("cancelled") == true
        )
        XCTAssertTrue(backend.events.contains(where: { $0.hasPrefix("up:") }))
        XCTAssertEqual(backend.events.last, "warp:42.0,24.0")
    }

    func testActionOwnedFinderFrameStaysInsideWorkspaceDisplay() {
        let display = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let finder = ActionWorkspaceDragFileOperation.finderFrame(in: display)
        XCTAssertTrue(display.contains(finder))
        XCTAssertEqual(finder.minX, display.minX + 48)
        XCTAssertEqual(finder.minY, display.minY + 48)
        XCTAssertLessThan(finder.midX, display.midX)
    }

    private func validParams() -> [String: String] {
        [
            "leaseId": "lease-1",
            "operationId": "operation-1",
            "workflowRunId": "run-1",
            "workspaceId": "agent:grok.main",
            "fixtureURL": "file:///tmp/openscout-action-drag-drop-run-1/Scout%20handoff.txt",
            "finderWindowTitle": "openscout-action-drag-drop-run-1",
            "destinationBundleId": ActionWorkspaceDragFileRequest.scoutBundleID,
            "destinationWindowTitle": "Scout drop target · agent:grok.main · run-1",
            "destinationAXIdentifier": "scout.action-drag-drop.agent:grok.main.run-1.drop-zone",
            "displayX": "1000",
            "displayY": "0",
            "displayWidth": "1200",
            "displayHeight": "900",
        ]
    }
}

private final class RecordingPointerBackend: ActionPointerGestureBackend, @unchecked Sendable {
    private let lock = NSLock()
    private let pointer: CGPoint
    private let failFirstDrag: Bool
    private var didFailDrag = false
    private var recorded: [String] = []

    init(pointer: CGPoint, failFirstDrag: Bool = false) {
        self.pointer = pointer
        self.failFirstDrag = failFirstDrag
    }

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func pointerPosition() throws -> CGPoint { pointer }
    func warp(to point: CGPoint) throws { append("warp", point) }
    func mouseDown(at point: CGPoint) throws { append("down", point) }
    func mouseDragged(to point: CGPoint) throws {
        append("drag", point)
        if failFirstDrag, !didFailDrag {
            didFailDrag = true
            throw TestPointerError.failed
        }
    }
    func mouseUp(at point: CGPoint) throws { append("up", point) }
    func wait(microseconds: UInt32) {}

    private func append(_ name: String, _ point: CGPoint) {
        lock.lock()
        recorded.append("\(name):\(point.x),\(point.y)")
        lock.unlock()
    }
}

private enum TestPointerError: Error {
    case failed
}

private struct FixedWorkspaceDragResolver: ActionWorkspaceDragResolving {
    func resolve(_ request: ActionWorkspaceDragFileRequest) throws -> ActionWorkspaceDragResolution {
        ActionWorkspaceDragResolution(
            source: CGPoint(x: 1_200, y: 300),
            destination: CGPoint(x: 1_800, y: 300),
            finderWindowFrame: CGRect(x: 1_050, y: 100, width: 500, height: 700),
            destinationWindowFrame: CGRect(x: 1_600, y: 100, width: 500, height: 700)
        )
    }
}

private struct ImmediateCursorCue: ActionWorkspaceDragCursorCueing {
    func showCountdown(
        lease: ActionDriveLease,
        at point: CGPoint,
        checkCancellation: () throws -> Void
    ) throws {
        try checkCancellation()
    }

    func move(to point: CGPoint, lease: ActionDriveLease) throws {}
    func stop(lease: ActionDriveLease) {}
}

private final class CoordinatedPointerBackend: ActionPointerGestureBackend, @unchecked Sendable {
    private let lock = NSLock()
    private let pointer: CGPoint
    private let mouseDownGate: DispatchSemaphore
    private let cancellationWritten: DispatchSemaphore
    private var isDown = false
    private var didWaitForCancellation = false
    private var recorded: [String] = []

    init(
        pointer: CGPoint,
        mouseDown: DispatchSemaphore,
        cancellationWritten: DispatchSemaphore
    ) {
        self.pointer = pointer
        self.mouseDownGate = mouseDown
        self.cancellationWritten = cancellationWritten
    }

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func pointerPosition() throws -> CGPoint { pointer }
    func warp(to point: CGPoint) throws { append("warp", point) }
    func mouseDown(at point: CGPoint) throws {
        lock.lock()
        isDown = true
        lock.unlock()
        append("down", point)
        mouseDownGate.signal()
    }
    func mouseDragged(to point: CGPoint) throws { append("drag", point) }
    func mouseUp(at point: CGPoint) throws {
        append("up", point)
        lock.lock()
        isDown = false
        lock.unlock()
    }

    func wait(microseconds: UInt32) {
        lock.lock()
        let shouldWait = isDown && !didWaitForCancellation
        if shouldWait { didWaitForCancellation = true }
        lock.unlock()
        if shouldWait {
            _ = cancellationWritten.wait(timeout: .now() + 2)
        }
    }

    private func append(_ name: String, _ point: CGPoint) {
        lock.lock()
        recorded.append("\(name):\(point.x),\(point.y)")
        lock.unlock()
    }
}

private final class ConcurrentResponseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ActionAgentResponse] = []

    var responses: [ActionAgentResponse] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ response: ActionAgentResponse) {
        lock.lock()
        storage.append(response)
        lock.unlock()
    }
}
