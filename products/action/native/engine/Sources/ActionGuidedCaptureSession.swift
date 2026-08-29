import AppKit
import ActionCore
import Foundation

struct GuidedCaptureSessionResult: Encodable {
    let status: String
    let sessionId: String
    let artifactDirectory: String
    let viewport: OverlayBounds
    let videoPath: String
    let screenshots: [String]
    let tracePath: String
    let expression: String
    let expectedResult: String
    let actualResult: String
}

private struct GuidedOverlayViewport: Encodable {
    let id: String
    let bounds: OverlayBounds
    let surfaceId: String?
    let dimming: String
}

private struct GuidedOverlayState: Encodable {
    let sessionId: String
    let phase: String
    let backdrop: String
    let viewport: GuidedOverlayViewport?
    let targetApp: String?
    let summary: String
    let detail: String?
    let countdownRemaining: Int?
    let elapsedMs: Double?
    let isRecording: Bool
    let stepCurrent: Int?
    let stepTotal: Int?
    let stepLabel: String?
    let recentLogs: [String]?
}

private struct GuidedCaptureTrace: Encodable {
    struct Step: Encodable {
        let index: Int
        let label: String
        let timestamp: String
    }

    let sessionId: String
    let targetApp: String
    let startedAt: String
    let finishedAt: String
    let expression: String
    let expectedResult: String
    let actualResult: String
    let viewport: OverlayBounds
    let videoPath: String
    let screenshots: [String]
    let steps: [Step]
    let recentLogs: [String]
}

private struct CalculatorDemoPlan {
    enum Operation: CaseIterable {
        case add
        case subtract
        case multiply

        var buttonIdentifier: String {
            switch self {
            case .add: return "Add"
            case .subtract: return "Subtract"
            case .multiply: return "Multiply"
            }
        }

        var symbol: String {
            switch self {
            case .add: return "+"
            case .subtract: return "-"
            case .multiply: return "×"
            }
        }

        func result(lhs: Int, rhs: Int) -> Int {
            switch self {
            case .add: return lhs + rhs
            case .subtract: return lhs - rhs
            case .multiply: return lhs * rhs
            }
        }
    }

    let lhs: Int
    let rhs: Int
    let operation: Operation

    var expression: String {
        "\(lhs)\(operation.symbol)\(rhs)"
    }

    var expectedResult: String {
        String(operation.result(lhs: lhs, rhs: rhs))
    }

    var steps: [String] {
        Self.digitButtons(for: lhs) + [operation.buttonIdentifier] + Self.digitButtons(for: rhs) + ["Equals"]
    }

    static func random() -> CalculatorDemoPlan {
        let operation = Operation.allCases.randomElement() ?? .add
        let lhs: Int
        let rhs: Int

        switch operation {
        case .add:
            lhs = Int.random(in: 12...84)
            rhs = Int.random(in: 7...36)
        case .subtract:
            rhs = Int.random(in: 6...28)
            lhs = Int.random(in: (rhs + 12)...96)
        case .multiply:
            lhs = Int.random(in: 4...12)
            rhs = Int.random(in: 3...9)
        }

        return CalculatorDemoPlan(lhs: lhs, rhs: rhs, operation: operation)
    }

    private static func digitButtons(for number: Int) -> [String] {
        String(number).map { digit in
            switch digit {
            case "0": return "Zero"
            case "1": return "One"
            case "2": return "Two"
            case "3": return "Three"
            case "4": return "Four"
            case "5": return "Five"
            case "6": return "Six"
            case "7": return "Seven"
            case "8": return "Eight"
            case "9": return "Nine"
            default: return "Zero"
            }
        }
    }
}

@MainActor
final class GuidedCaptureSessionRunner {
    private let writer: ResponseWriter
    private let logger: DebugLogger
    private let options: CommandOptions

    init(writer: ResponseWriter, logger: DebugLogger, options: CommandOptions) {
        self.writer = writer
        self.logger = logger
        self.options = options
    }

    func run() async throws {
        enum OperatorDecision {
            case none
            case startNow
            case cancelBeforeCapture
            case interruptCapture
        }

        let sessionId = "guided-\(timestampSlug())-\(UUID().uuidString.prefix(6))"
        let artifactDirectory = try makeArtifactDirectory(sessionId: sessionId)
        let overlayStatePath = artifactDirectory.appendingPathComponent("overlay-state.json").path
        let overlayStopPath = artifactDirectory.appendingPathComponent("overlay.stop").path
        let overlayReplyPath = artifactDirectory.appendingPathComponent("overlay.reply.json").path
        let overlayLogPath = artifactDirectory.appendingPathComponent("overlay.log").path
        let overlayControlPath = artifactDirectory.appendingPathComponent("overlay.controls").path
        let recordingStopPath = artifactDirectory.appendingPathComponent("record.stop").path
        let recordingFinishedPath = artifactDirectory.appendingPathComponent("record.finished").path
        let recordingReplyPath = artifactDirectory.appendingPathComponent("record.reply.json").path
        let recordingLogPath = artifactDirectory.appendingPathComponent("record.log").path
        let videoPath = artifactDirectory.appendingPathComponent("session.mov").path
        let stagedScreenshotPath = artifactDirectory.appendingPathComponent("stage.png").path
        let resultScreenshotPath = artifactDirectory.appendingPathComponent("result.png").path
        let tracePath = artifactDirectory.appendingPathComponent("trace.json").path

        let targetBundleId = "com.apple.calculator"
        var recentLogs: [String] = []
        var traceSteps: [GuidedCaptureTrace.Step] = []
        let startedAt = ISO8601DateFormatter().string(from: Date())
        let startTime = Date()
        var currentStep: Int?
        var totalSteps: Int?
        var recordingProcess: Process?
        var captureWasStarted = false

        func appendLog(_ message: String) {
            logger.log("guided-session: \(message)")
            recentLogs.append(message)
            if recentLogs.count > 8 {
                recentLogs.removeFirst(recentLogs.count - 8)
            }
        }

        func appendStep(_ label: String) {
            traceSteps.append(
                GuidedCaptureTrace.Step(
                    index: traceSteps.count + 1,
                    label: label,
                    timestamp: ISO8601DateFormatter().string(from: Date())
                )
            )
        }

        func elapsedMs() -> Double {
            Date().timeIntervalSince(startTime) * 1000
        }

        func clearCalculatorInput() throws {
            let clearCandidates = ["AllClear", "Clear"]
            for label in clearCandidates {
                if (try? clickCalculatorButton(label: label)) != nil {
                    return
                }
            }
            throw ActionHostError.accessibilityLookupFailed("Could not find Calculator clear button (AllClear/Clear)")
        }

        func consumeOverlayCommands() -> [String] {
            guard FileManager.default.fileExists(atPath: overlayControlPath),
                  let raw = try? String(contentsOfFile: overlayControlPath, encoding: .utf8) else {
                return []
            }

            let commands = raw
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            guard !commands.isEmpty else {
                return []
            }

            try? "".write(toFile: overlayControlPath, atomically: true, encoding: .utf8)
            return commands
        }

        func operatorDecision(for phase: String) -> OperatorDecision {
            for command in consumeOverlayCommands() {
                switch (phase, command) {
                case ("countdown", "start"):
                    appendLog("operator skipped countdown")
                    return .startNow
                case ("countdown", "stop"), ("countdown", "quit"), ("countdown", "clear"):
                    appendLog("operator cancelled before capture")
                    return .cancelBeforeCapture
                case ("recording", "stop"), ("recording", "quit"):
                    appendLog("operator interrupted capture")
                    return .interruptCapture
                default:
                    continue
                }
            }

            return .none
        }

        func waitForOperatorDecision(timeout: TimeInterval, phase: String) -> OperatorDecision {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                let decision = operatorDecision(for: phase)
                switch decision {
                case .none:
                    break
                case .startNow, .cancelBeforeCapture, .interruptCapture:
                    return decision
                }
                usleep(50_000)
            }
            return operatorDecision(for: phase)
        }

        func stopRecordingIfNeeded() throws {
            guard captureWasStarted else {
                return
            }

            try writeMarkerFile(path: recordingStopPath, contents: "stop\n")
            try waitForFinishedSignal(at: recordingFinishedPath)
            recordingProcess?.waitUntilExit()
            captureWasStarted = false
        }

        let overlayViewportId = "calculator-primary"
        let overlayBackdrop = options.options["backdrop"] ?? "gradient"

        try await MainActor.run {
            try ActionNativeAutomation.launchApplication(bundleId: targetBundleId)
        }
        appendLog("launched Calculator")
        appendStep("launch Calculator")

        let initialFrame = try waitForWindowFrame(bundleId: targetBundleId, timeout: 6)
        let visibleFrame = try await mainVisibleFrame(containing: initialFrame)
        let targetRect = centeredRect(size: initialFrame.size, in: visibleFrame)
        try ActionNativeAutomation.setWindowFrame(bundleId: targetBundleId, rect: targetRect)
        try ActionNativeAutomation.activateApplication(bundleId: targetBundleId)
        usleep(220_000)
        let finalFrame = try waitForWindowFrame(bundleId: targetBundleId, timeout: 3)
        let captureFrame = try await waitForCaptureWindowFrame(bundleId: targetBundleId, fallback: finalFrame)
        let viewportBounds = OverlayBounds(
            x: captureFrame.origin.x,
            y: captureFrame.origin.y,
            width: captureFrame.size.width,
            height: captureFrame.size.height
        )
        appendLog("fit Calculator to viewport")
        appendStep("fit Calculator to viewport")

        func writeOverlayState(
            phase: String,
            summary: String,
            detail: String?,
            countdownRemaining: Int?,
            isRecording: Bool,
            stepCurrent: Int?,
            stepTotal: Int?,
            stepLabel: String?
        ) throws {
            let state = GuidedOverlayState(
                sessionId: sessionId,
                phase: phase,
                backdrop: overlayBackdrop,
                viewport: GuidedOverlayViewport(
                    id: overlayViewportId,
                    bounds: viewportBounds,
                    surfaceId: targetBundleId,
                    dimming: "outside"
                ),
                targetApp: "Calculator",
                summary: summary,
                detail: detail,
                countdownRemaining: countdownRemaining,
                elapsedMs: elapsedMs(),
                isRecording: isRecording,
                stepCurrent: stepCurrent,
                stepTotal: stepTotal,
                stepLabel: stepLabel,
                recentLogs: recentLogs
            )

            let data = try JSONEncoder.pretty.encode(state)
            try data.write(to: URL(fileURLWithPath: overlayStatePath))
        }

        func finishCancelledRun(summary: String, detail: String, captureWasLive: Bool) throws {
            try writeOverlayState(
                phase: "cancelled",
                summary: summary,
                detail: detail,
                countdownRemaining: nil,
                isRecording: false,
                stepCurrent: currentStep,
                stepTotal: totalSteps,
                stepLabel: captureWasLive ? "operator interrupt" : "countdown cancelled"
            )
            usleep(500_000)
            if captureWasLive {
                try stopRecordingIfNeeded()
                appendLog("capture stopped after operator interrupt")
                appendStep("interrupt recording")
            }
            try writeMarkerFile(path: overlayStopPath, contents: "stop\n")
            try writer.write(
                ActionHostResponse(
                    status: "cancelled",
                    outputPath: captureWasLive ? videoPath : nil,
                    detail: detail
                )
            )
        }

        try writeOverlayState(
            phase: "staging",
            summary: "Viewport locked on Calculator",
            detail: "Preparing capture session",
            countdownRemaining: nil,
            isRecording: false,
            stepCurrent: nil,
            stepTotal: nil,
            stepLabel: "staged"
        )

        try launchAppBundleCommand(
            arguments: [
                "stage-overlay",
                "--state-file", overlayStatePath,
                "--stop-file", overlayStopPath,
                "--reply-file", overlayReplyPath,
                "--debug-log", overlayLogPath,
                "--control-file", overlayControlPath,
            ]
        )
        try waitForReplyFile(at: overlayReplyPath, timeout: 5, expecting: "overlay-running")
        defer {
            try? writeMarkerFile(path: overlayStopPath, contents: "stop\n")
            if let recordingProcess, recordingProcess.isRunning {
                try? writeMarkerFile(path: recordingStopPath, contents: "stop\n")
            }
        }

        try await captureAppWindowScreenshot(
            bundleId: targetBundleId,
            outputPath: stagedScreenshotPath,
            writer: ResponseWriter(replyFile: artifactDirectory.appendingPathComponent("stage-screenshot.reply.json").path)
        )
        appendLog("captured staged screenshot")
        appendStep("capture stage screenshot")

        var skipCountdown = false
        for remaining in stride(from: 3, through: 1, by: -1) {
            try writeOverlayState(
                phase: "countdown",
                summary: "Recording begins in \(remaining)",
                detail: "Viewport locked and armed",
                countdownRemaining: remaining,
                isRecording: false,
                stepCurrent: nil,
                stepTotal: nil,
                stepLabel: "countdown"
            )
            appendLog("countdown \(remaining)")
            switch waitForOperatorDecision(timeout: 1.0, phase: "countdown") {
            case .none:
                break
            case .startNow:
                skipCountdown = true
            case .cancelBeforeCapture:
                try finishCancelledRun(
                    summary: "Capture cancelled",
                    detail: "Countdown interrupted before recording started.",
                    captureWasLive: false
                )
                return
            case .interruptCapture:
                break
            }

            if skipCountdown {
                break
            }
        }

        try writeOverlayState(
            phase: "recording",
            summary: "Recording Calculator session",
            detail: "Starting region capture",
            countdownRemaining: nil,
            isRecording: true,
            stepCurrent: 0,
            stepTotal: 0,
            stepLabel: "capture live"
        )

        let frameX = String(describing: captureFrame.origin.x)
        let frameY = String(describing: captureFrame.origin.y)
        let frameWidth = String(describing: captureFrame.size.width)
        let frameHeight = String(describing: captureFrame.size.height)
        let recordingArguments: [String] = [
            "record-region",
            "--x", frameX,
            "--y", frameY,
            "--width", frameWidth,
            "--height", frameHeight,
            "--output", videoPath,
            "--stop-file", recordingStopPath,
            "--finished-file", recordingFinishedPath,
            "--reply-file", recordingReplyPath,
            "--debug-log", recordingLogPath,
            "--fps", "30",
            "--scale", "1",
        ]
        recordingProcess = try launchChildProcess(arguments: recordingArguments)
        try waitForReplyFile(at: recordingReplyPath, timeout: 8, expecting: "recording")
        captureWasStarted = true
        appendLog("recording started")
        appendStep("start region recording")

        let demoPlan = CalculatorDemoPlan.random()
        totalSteps = demoPlan.steps.count
        try clearCalculatorInput()
        if waitForOperatorDecision(timeout: 0.22, phase: "recording") == .interruptCapture {
            try finishCancelledRun(
                summary: "Capture interrupted",
                detail: "Recording stopped before the scripted demo finished.",
                captureWasLive: true
            )
            return
        }

        for (index, buttonLabel) in demoPlan.steps.enumerated() {
            currentStep = index + 1
            let humanStep = "Tap \(buttonLabel)"
            try writeOverlayState(
                phase: "recording",
                summary: "Running \(demoPlan.expression)",
                detail: "\(demoPlan.expression) -> \(demoPlan.expectedResult)",
                countdownRemaining: nil,
                isRecording: true,
                stepCurrent: currentStep,
                stepTotal: demoPlan.steps.count,
                stepLabel: humanStep
            )
            appendLog(humanStep)
            appendStep(humanStep)
            try clickCalculatorButton(label: buttonLabel)
            if waitForOperatorDecision(timeout: 0.22, phase: "recording") == .interruptCapture {
                try finishCancelledRun(
                    summary: "Capture interrupted",
                    detail: "Recording stopped before the scripted demo finished.",
                    captureWasLive: true
                )
                return
            }
        }

        var actualResult = ""
        let resultDeadline = Date().addingTimeInterval(3)
        while Date() < resultDeadline {
            actualResult = (try? ActionNativeAutomation.calculatorDisplayValue()) ?? actualResult
            if actualResult == demoPlan.expectedResult {
                break
            }
            if waitForOperatorDecision(timeout: 0.12, phase: "recording") == .interruptCapture {
                try finishCancelledRun(
                    summary: "Capture interrupted",
                    detail: "Recording stopped before the scripted demo finished.",
                    captureWasLive: true
                )
                return
            }
        }
        appendLog("result \(actualResult)")
        appendStep("read result \(actualResult)")

        try await captureAppWindowScreenshot(
            bundleId: targetBundleId,
            outputPath: resultScreenshotPath,
            writer: ResponseWriter(replyFile: artifactDirectory.appendingPathComponent("result-screenshot.reply.json").path)
        )
        appendLog("captured result screenshot")
        appendStep("capture result screenshot")

        try writeOverlayState(
            phase: "completing",
            summary: "Stopping capture",
            detail: "\(demoPlan.expression) = \(actualResult)",
            countdownRemaining: nil,
            isRecording: true,
            stepCurrent: demoPlan.steps.count,
            stepTotal: demoPlan.steps.count,
            stepLabel: "finalizing artifacts"
        )

        try stopRecordingIfNeeded()
        appendLog("recording finished")
        appendStep("finish recording")

        let trace = GuidedCaptureTrace(
            sessionId: sessionId,
            targetApp: targetBundleId,
            startedAt: startedAt,
            finishedAt: ISO8601DateFormatter().string(from: Date()),
            expression: demoPlan.expression,
            expectedResult: demoPlan.expectedResult,
            actualResult: actualResult,
            viewport: viewportBounds,
            videoPath: videoPath,
            screenshots: [stagedScreenshotPath, resultScreenshotPath],
            steps: traceSteps,
            recentLogs: recentLogs
        )
        try JSONEncoder.pretty.encode(trace).write(to: URL(fileURLWithPath: tracePath))

        try writeOverlayState(
            phase: "completed",
            summary: "Session complete",
            detail: "\(demoPlan.expression) = \(actualResult)",
            countdownRemaining: nil,
            isRecording: false,
            stepCurrent: demoPlan.steps.count,
            stepTotal: demoPlan.steps.count,
            stepLabel: "artifacts saved"
        )
        usleep(800_000)
        try writeMarkerFile(path: overlayStopPath, contents: "stop\n")
        try writer.write(
            GuidedCaptureSessionResult(
                status: "completed",
                sessionId: sessionId,
                artifactDirectory: artifactDirectory.path,
                viewport: viewportBounds,
                videoPath: videoPath,
                screenshots: [stagedScreenshotPath, resultScreenshotPath],
                tracePath: tracePath,
                expression: demoPlan.expression,
                expectedResult: demoPlan.expectedResult,
                actualResult: actualResult
            )
        )
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private func timestampSlug() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}

private func makeArtifactDirectory(sessionId: String) throws -> URL {
    let base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Action/sessions", isDirectory: true)
        .appendingPathComponent(sessionId, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}

private func centeredRect(size: CGSize, in visibleFrame: CGRect) -> CGRect {
    CGRect(
        x: round(visibleFrame.midX - (size.width / 2)),
        y: round(visibleFrame.midY - (size.height / 2)),
        width: size.width,
        height: size.height
    )
}

private func mainVisibleFrame(containing rect: CGRect) async throws -> CGRect {
    try await MainActor.run {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(center) || $0.frame.contains(center) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            throw ActionHostError.captureFailed("No screen available for guided session")
        }
        return screen.visibleFrame
    }
}

private func waitForWindowFrame(bundleId: String, timeout: TimeInterval) throws -> CGRect {
    let deadline = Date().addingTimeInterval(timeout)
    var lastError: Error?

    while Date() < deadline {
        do {
            return try ActionNativeAutomation.getWindowFrame(bundleId: bundleId)
        } catch {
            lastError = error
            usleep(120_000)
        }
    }

    throw lastError ?? ActionHostError.captureFailed("Timed out waiting for window frame for \(bundleId)")
}

private func waitForCaptureWindowFrame(bundleId: String, fallback: CGRect, timeout: TimeInterval = 3) async throws -> CGRect {
    let deadline = Date().addingTimeInterval(timeout)
    var latestFrame: CGRect?

    while Date() < deadline {
        if let selection = try? await bestWindowSelection(for: bundleId) {
            let frame = selection.window.frame.standardized.integral
            if frame.width > 1, frame.height > 1 {
                return frame
            }
            latestFrame = frame
        }
        usleep(120_000)
    }

    return latestFrame ?? fallback
}

private func waitForCalculatorResult(expected: String, timeout: TimeInterval) throws -> String {
    let deadline = Date().addingTimeInterval(timeout)
    var latestValue = ""

    while Date() < deadline {
        latestValue = (try? ActionNativeAutomation.calculatorDisplayValue()) ?? latestValue
        if latestValue == expected {
            return latestValue
        }
        usleep(120_000)
    }

    return latestValue
}

private func waitForReplyFile(at path: String, timeout: TimeInterval, expecting status: String) throws {
    let deadline = Date().addingTimeInterval(timeout)
    let url = URL(fileURLWithPath: path)

    while Date() < deadline {
        if let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let replyStatus = object["status"] as? String {
            if replyStatus == status {
                return
            }
            if replyStatus == "error" {
                let detail = object["detail"] as? String ?? "Unknown child process error"
                throw ActionHostError.captureFailed(detail)
            }
        }
        usleep(100_000)
    }

    throw ActionHostError.captureFailed("Timed out waiting for child command status \(status)")
}

@discardableResult
private func launchChildProcess(arguments: [String]) throws -> Process {
    guard let executableURL = Bundle.main.executableURL else {
        throw ActionHostError.captureFailed("Could not resolve Action executable for guided session")
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    try process.run()
    return process
}

private func launchAppBundleCommand(arguments: [String]) throws {
    let bundleURL = try resolveCurrentAppBundleURL()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-n", bundleURL.path, "--args"] + arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        throw ActionHostError.captureFailed("Failed to launch Action.app child command via open(1)")
    }
}

private func resolveCurrentAppBundleURL() throws -> URL {
    let bundleURL = Bundle.main.bundleURL
    if bundleURL.pathExtension == "app" {
        return bundleURL
    }

    if let executableURL = Bundle.main.executableURL {
        var candidate = executableURL.deletingLastPathComponent()
        while candidate.path != "/" {
            if candidate.pathExtension == "app" {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
    }

    throw ActionHostError.captureFailed("Unable to resolve current Action.app bundle URL")
}

private func writeMarkerFile(path: String, contents: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: url)
}
