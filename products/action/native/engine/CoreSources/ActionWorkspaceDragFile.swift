import CoreGraphics
import Foundation

struct ActionWorkspaceDragFileRequest: Equatable, Sendable {
    static let capability = "workspace.drag-file"
    static let systemPointerResource = "system-pointer"
    static let method = "workspace.dragFile"
    static let scoutBundleID = "app.openscout.scout"

    let leaseID: String
    let operationID: String
    let workflowRunID: String
    let workspaceID: String
    let fixtureURL: URL
    let finderWindowTitle: String
    let destinationBundleID: String
    let destinationWindowTitle: String
    let destinationAXIdentifier: String
    let displayBounds: CGRect

    init(params: [String: String]) throws {
        let allowed: Set<String> = [
            "leaseId", "operationId", "workflowRunId", "workspaceId", "fixtureURL",
            "finderWindowTitle", "destinationBundleId", "destinationWindowTitle",
            "destinationAXIdentifier",
            "displayX", "displayY", "displayWidth", "displayHeight",
            "protocolVersion", "authToken",
        ]
        let unexpected = Set(params.keys).subtracting(allowed)
        guard unexpected.isEmpty else {
            throw ActionWorkspaceDragFileError.invalidRequest(
                "workspace.dragFile rejects unsupported parameters: \(unexpected.sorted().joined(separator: ", "))"
            )
        }

        leaseID = try Self.required("leaseId", in: params)
        operationID = try Self.requiredIdentifier("operationId", in: params)
        workflowRunID = try Self.requiredIdentifier("workflowRunId", in: params)
        workspaceID = try Self.requiredIdentifier("workspaceId", in: params)
        finderWindowTitle = try Self.required("finderWindowTitle", in: params)
        destinationBundleID = try Self.required("destinationBundleId", in: params)
        destinationWindowTitle = try Self.required("destinationWindowTitle", in: params)
        destinationAXIdentifier = try Self.required("destinationAXIdentifier", in: params)

        guard destinationBundleID == Self.scoutBundleID else {
            throw ActionWorkspaceDragFileError.invalidRequest(
                "workspace.dragFile destination must be \(Self.scoutBundleID)"
            )
        }
        let expectedDestinationTitle = "Scout drop target · \(workspaceID) · \(workflowRunID)"
        let expectedDestinationIdentifier = "scout.action-drag-drop.\(workspaceID).\(workflowRunID).drop-zone"
        guard destinationWindowTitle == expectedDestinationTitle,
              destinationAXIdentifier == expectedDestinationIdentifier else {
            throw ActionWorkspaceDragFileError.invalidRequest(
                "workspace.dragFile destination window and AX identifier must identify the workflow run and workspace"
            )
        }

        let rawFixtureURL = try Self.required("fixtureURL", in: params)
        guard let parsedFixtureURL = URL(string: rawFixtureURL), parsedFixtureURL.isFileURL else {
            throw ActionWorkspaceDragFileError.invalidRequest("workspace.dragFile fixtureURL must be a file URL")
        }
        fixtureURL = parsedFixtureURL.standardizedFileURL
        let expectedDirectoryName = "openscout-action-drag-drop-\(workflowRunID)"
        guard fixtureURL.lastPathComponent == "Scout handoff.txt",
              fixtureURL.deletingLastPathComponent().lastPathComponent == expectedDirectoryName,
              finderWindowTitle == expectedDirectoryName else {
            throw ActionWorkspaceDragFileError.invalidRequest(
                "workspace.dragFile fixture and Finder window do not match the workflow run"
            )
        }

        let x = try Self.requiredFiniteDouble("displayX", in: params)
        let y = try Self.requiredFiniteDouble("displayY", in: params)
        let width = try Self.requiredFiniteDouble("displayWidth", in: params)
        let height = try Self.requiredFiniteDouble("displayHeight", in: params)
        guard width > 0, height > 0 else {
            throw ActionWorkspaceDragFileError.invalidRequest("workspace.dragFile display bounds must be positive")
        }
        displayBounds = CGRect(x: x, y: y, width: width, height: height)
    }

    func validateFixture(fileManager: FileManager = .default) throws {
        let values = try fixtureURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ActionWorkspaceDragFileError.fixtureRejected
        }
        guard fixtureURL.resolvingSymlinksInPath().standardizedFileURL == fixtureURL.standardizedFileURL else {
            throw ActionWorkspaceDragFileError.fixtureRejected
        }
        guard fileManager.fileExists(atPath: fixtureURL.path) else {
            throw ActionWorkspaceDragFileError.fixtureRejected
        }
    }

    private static func required(_ key: String, in params: [String: String]) throws -> String {
        guard let value = params[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw ActionWorkspaceDragFileError.invalidRequest("workspace.dragFile requires \(key)")
        }
        return value
    }

    private static func requiredIdentifier(_ key: String, in params: [String: String]) throws -> String {
        let value = try required(key, in: params)
        guard value.count <= 200,
              value.range(of: #"^[A-Za-z0-9._:@-]+$"#, options: .regularExpression) != nil else {
            throw ActionWorkspaceDragFileError.invalidRequest("workspace.dragFile requires a valid \(key)")
        }
        return value
    }

    private static func requiredFiniteDouble(_ key: String, in params: [String: String]) throws -> Double {
        let raw = try required(key, in: params)
        guard let value = Double(raw), value.isFinite else {
            throw ActionWorkspaceDragFileError.invalidRequest("workspace.dragFile requires a finite \(key)")
        }
        return value
    }
}

enum ActionWorkspaceDragFileError: LocalizedError, Equatable {
    case invalidRequest(String)
    case fixtureRejected
    case sourceNotFound
    case destinationNotFound
    case displayBoundsRejected
    case cancelled
    case pointerCleanupFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let detail): return detail
        case .fixtureRejected: return "The exact run-owned Scout handoff fixture was not available"
        case .sourceNotFound: return "Finder did not expose the exact fixture through AXURL"
        case .destinationNotFound: return "The exact Scout drop-target window was not available"
        case .displayBoundsRejected: return "Resolved drag geometry is outside the workspace display bounds"
        case .cancelled: return "workspace.dragFile was cancelled"
        case .pointerCleanupFailed(let detail): return "Pointer cleanup failed: \(detail)"
        }
    }
}

struct ActionWorkspaceDragResolution: Equatable, Sendable {
    let source: CGPoint
    let destination: CGPoint
    let finderWindowFrame: CGRect
    let destinationWindowFrame: CGRect
}

protocol ActionWorkspaceDragResolving: Sendable {
    func resolve(_ request: ActionWorkspaceDragFileRequest) throws -> ActionWorkspaceDragResolution
}

struct ActionNativeWorkspaceDragResolver: ActionWorkspaceDragResolving {
    func resolve(_ request: ActionWorkspaceDragFileRequest) throws -> ActionWorkspaceDragResolution {
        try ActionNativeAutomation.resolveWorkspaceDragFile(request)
    }
}

protocol ActionPointerGestureBackend: Sendable {
    func pointerPosition() throws -> CGPoint
    func warp(to point: CGPoint) throws
    func mouseDown(at point: CGPoint) throws
    func mouseDragged(to point: CGPoint) throws
    func mouseUp(at point: CGPoint) throws
    func wait(microseconds: UInt32)
}

struct ActionCGPointerGestureBackend: ActionPointerGestureBackend {
    func pointerPosition() throws -> CGPoint {
        guard let point = CGEvent(source: nil)?.location else {
            throw ActionWorkspaceDragFileError.pointerCleanupFailed("unable to snapshot cursor position")
        }
        return point
    }

    func warp(to point: CGPoint) throws {
        let result = CGWarpMouseCursorPosition(point)
        guard result == .success else {
            throw ActionWorkspaceDragFileError.pointerCleanupFailed("cursor warp returned \(result.rawValue)")
        }
    }

    func mouseDown(at point: CGPoint) throws { try post(.leftMouseDown, at: point) }
    func mouseDragged(to point: CGPoint) throws { try post(.leftMouseDragged, at: point) }
    func mouseUp(at point: CGPoint) throws { try post(.leftMouseUp, at: point) }
    func wait(microseconds: UInt32) { usleep(microseconds) }

    private func post(_ type: CGEventType, at point: CGPoint) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                  mouseEventSource: source,
                  mouseType: type,
                  mouseCursorPosition: point,
                  mouseButton: .left
              ) else {
            throw ActionNativeAutomationError.accessibilityActionFailed("Unable to create pointer event")
        }
        event.post(tap: .cghidEventTap)
    }
}

struct ActionPointerGestureEngine: Sendable {
    let backend: any ActionPointerGestureBackend

    init(backend: any ActionPointerGestureBackend = ActionCGPointerGestureBackend()) {
        self.backend = backend
    }

    func drag(
        from start: CGPoint,
        to end: CGPoint,
        durationMilliseconds: Int = 500,
        checkCancellation: () throws -> Void
    ) throws {
        let savedPointer = try backend.pointerPosition()
        var lastPoint = start
        var mouseIsDown = false
        var operationError: Error?

        do {
            try checkCancellation()
            try backend.warp(to: start)
            backend.wait(microseconds: 10_000)
            try checkCancellation()
            try backend.mouseDown(at: start)
            mouseIsDown = true
            backend.wait(microseconds: 15_000)

            let duration = max(40, durationMilliseconds)
            let steps = max(6, duration / 10)
            let delay = UInt32((Double(duration) * 1_000 / Double(steps)).rounded())
            for index in 1...steps {
                try checkCancellation()
                let ratio = Double(index) / Double(steps)
                lastPoint = CGPoint(
                    x: start.x + ((end.x - start.x) * ratio),
                    y: start.y + ((end.y - start.y) * ratio)
                )
                try backend.mouseDragged(to: lastPoint)
                backend.wait(microseconds: delay)
            }
            try backend.mouseUp(at: end)
            mouseIsDown = false
        } catch {
            operationError = error
        }

        var cleanupFailures: [String] = []
        if mouseIsDown {
            do { try backend.mouseUp(at: lastPoint) }
            catch { cleanupFailures.append("mouseUp: \(error.localizedDescription)") }
        }
        do { try backend.warp(to: savedPointer) }
        catch { cleanupFailures.append("restore: \(error.localizedDescription)") }

        if !cleanupFailures.isEmpty {
            let operationDetail = operationError.map { "operation: \($0.localizedDescription); " } ?? ""
            throw ActionWorkspaceDragFileError.pointerCleanupFailed(
                operationDetail + cleanupFailures.joined(separator: "; ")
            )
        }
        if let operationError { throw operationError }
    }
}

private struct ActionWorkspaceDragCancellationChecker {
    let stopFile: String
    let operationID: String
    let operationStopFile: String?

    func check() throws {
        guard !operationID.isEmpty else {
            throw ActionWorkspaceDragFileError.cancelled
        }
        if Task.isCancelled
            || FileManager.default.fileExists(atPath: stopFile)
            || operationStopFile.map({ FileManager.default.fileExists(atPath: $0) }) == true {
            throw ActionWorkspaceDragFileError.cancelled
        }
    }
}

protocol ActionWorkspaceDragCursorCueing: Sendable {
    func showCountdown(lease: ActionDriveLease, at point: CGPoint, checkCancellation: () throws -> Void) throws
    func move(to point: CGPoint, lease: ActionDriveLease) throws
    func stop(lease: ActionDriveLease)
}

struct ActionAgentCursorCue: ActionWorkspaceDragCursorCueing {
    func showCountdown(
        lease: ActionDriveLease,
        at point: CGPoint,
        checkCancellation: () throws -> Void
    ) throws {
        try write(lease: lease, point: point, phase: "countdown", countdown: 3)
        try launchIfNeeded(lease: lease)
        for remaining in stride(from: 3, through: 1, by: -1) {
            try checkCancellation()
            try write(lease: lease, point: point, phase: "countdown", countdown: remaining)
            usleep(650_000)
        }
        try checkCancellation()
    }

    func move(to point: CGPoint, lease: ActionDriveLease) throws {
        try write(lease: lease, point: point, phase: "drag", countdown: 0)
    }

    func stop(lease: ActionDriveLease) {
        try? Data("stop\n".utf8).write(to: stopURL(for: lease), options: .atomic)
    }

    private func write(
        lease: ActionDriveLease,
        point: CGPoint,
        phase: String,
        countdown: Int
    ) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: stopURL(for: lease))
        let now = Date()
        let state: [String: Any] = [
            "x": point.x,
            "y": point.y,
            "coordinateSpace": "quartz",
            "agent": lease.agent,
            "label": lease.task,
            "phase": phase,
            "countdown": countdown,
            "cueId": UUID().uuidString,
            "updatedAt": ISO8601DateFormatter().string(from: now),
            "expiresAt": ISO8601DateFormatter().string(from: now.addingTimeInterval(30)),
        ]
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateURL(for: lease), options: .atomic)
    }

    private func launchIfNeeded(lease: ActionDriveLease) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-n", try actionAppURL().path, "--args", "agent-cursor-overlay",
            "--state-file", stateURL(for: lease).path,
            "--stop-file", stopURL(for: lease).path,
            "--lease-stop-file", lease.stopFile,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ActionWorkspaceDragFileError.invalidRequest("Unable to launch the Action cursor cue")
        }
    }

    private var rootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/runtime/drive/cursors", isDirectory: true)
    }

    private func stateURL(for lease: ActionDriveLease) -> URL {
        rootURL.appendingPathComponent("\(sanitized(lease.leaseId)).json")
    }

    private func stopURL(for lease: ActionDriveLease) -> URL {
        URL(fileURLWithPath: stateURL(for: lease).path + ".stop")
    }

    private func sanitized(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "_", options: .regularExpression)
    }

    private func actionAppURL() throws -> URL {
        var candidate = Bundle.main.bundleURL
        while candidate.path != "/" {
            if candidate.lastPathComponent == "Action.app" { return candidate }
            candidate.deleteLastPathComponent()
        }
        throw ActionWorkspaceDragFileError.invalidRequest("Unable to resolve Action.app for the cursor cue")
    }
}

struct ActionWorkspaceDragFileResult: Equatable, Sendable {
    let operationID: String
    let source: CGPoint
    let destination: CGPoint
}

struct ActionWorkspaceDragFileOperation: Sendable {
    let driveStore: ActionDriveLeaseStore
    let resolver: any ActionWorkspaceDragResolving
    let gestureEngine: ActionPointerGestureEngine
    let cursorCue: any ActionWorkspaceDragCursorCueing

    init(
        driveStore: ActionDriveLeaseStore,
        resolver: any ActionWorkspaceDragResolving = ActionNativeWorkspaceDragResolver(),
        gestureEngine: ActionPointerGestureEngine = ActionPointerGestureEngine(),
        cursorCue: any ActionWorkspaceDragCursorCueing = ActionAgentCursorCue()
    ) {
        self.driveStore = driveStore
        self.resolver = resolver
        self.gestureEngine = gestureEngine
        self.cursorCue = cursorCue
    }

    func execute(
        request: ActionWorkspaceDragFileRequest,
        ownerID: String
    ) async throws -> ActionWorkspaceDragFileResult {
        try request.validateFixture()
        let lease = try await driveStore.authorizeWorkspaceDrag(
            ownerID: ownerID,
            leaseID: request.leaseID,
            operationID: request.operationID,
            workflowRunID: request.workflowRunID,
            workspaceID: request.workspaceID
        )
        let cancellation = ActionWorkspaceDragCancellationChecker(
            stopFile: lease.stopFile,
            operationID: request.operationID,
            operationStopFile: lease.operationStopFile
        )
        defer {
            cursorCue.stop(lease: lease)
            if resolver is ActionNativeWorkspaceDragResolver {
                try? ActionNativeAutomation.closeWorkspaceFinderWindow(title: request.finderWindowTitle)
            }
        }
        let resolution = try resolver.resolve(request)
        try Self.validate(resolution: resolution, inside: request.displayBounds)

        try cursorCue.showCountdown(lease: lease, at: resolution.source) {
            try cancellation.check()
        }
        try cancellation.check()
        try cursorCue.move(to: resolution.destination, lease: lease)
        try gestureEngine.drag(from: resolution.source, to: resolution.destination) {
            try cancellation.check()
        }
        return ActionWorkspaceDragFileResult(
            operationID: request.operationID,
            source: resolution.source,
            destination: resolution.destination
        )
    }

    static func validate(resolution: ActionWorkspaceDragResolution, inside display: CGRect) throws {
        let frames = [resolution.finderWindowFrame, resolution.destinationWindowFrame]
        guard display.width > 0,
              display.height > 0,
              frames.allSatisfy({ $0.width > 0 && $0.height > 0 && display.contains($0) }),
              display.insetBy(dx: 1, dy: 1).contains(resolution.source),
              display.insetBy(dx: 1, dy: 1).contains(resolution.destination),
              resolution.finderWindowFrame.contains(resolution.source),
              resolution.destinationWindowFrame.contains(resolution.destination) else {
            throw ActionWorkspaceDragFileError.displayBoundsRejected
        }
    }

    static func finderFrame(in display: CGRect) -> CGRect {
        let inset: CGFloat = 48
        let gap: CGFloat = 32
        let usableWidth = max(640, display.width - (inset * 2))
        let width = min(720, max(420, (usableWidth - gap) * 0.52))
        return CGRect(
            x: display.minX + inset,
            y: display.minY + inset,
            width: width,
            height: max(420, display.height - (inset * 2))
        )
    }
}
