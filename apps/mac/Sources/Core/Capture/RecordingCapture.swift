import AppKit
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

private struct RecordingProbeResponse: Codable {
    let status: String
    let outputPath: String?
    let detail: String?
}

private enum RecordingCaptureError: LocalizedError {
    case screenRecordingPermissionMissing
    case windowNotFound(String)
    case displayNotFound(String)
    case missingOption(String)
    case unsupportedOS(String)

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionMissing:
            return "Screen Recording permission has not been granted yet."
        case .windowNotFound(let detail):
            return "Could not find an on-screen window for \(detail)"
        case .displayNotFound(let detail):
            return detail
        case .missingOption(let option):
            return "Missing required option \(option)"
        case .unsupportedOS(let detail):
            return detail
        }
    }
}

private final class RecordingResponseWriter {
    private let replyFile: String?

    init(replyFile: String?) {
        self.replyFile = replyFile
    }

    func write(_ response: RecordingProbeResponse) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(response)

        if let replyFile, !replyFile.isEmpty {
            let url = URL(fileURLWithPath: replyFile)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0a]))
        }
    }
}

private final class RecordingDebugLogger {
    private let path: String?

    init(path: String?) {
        self.path = path
    }

    func log(_ message: String) {
        guard let path, !path.isEmpty else { return }
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        let url = URL(fileURLWithPath: path)

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try Data(line.utf8).write(to: url)
            }
        } catch {
            FileHandle.standardError.write(Data("Lattices recording debug log failed: \(error.localizedDescription)\n".utf8))
        }
    }
}

private final class RecordingAsyncResultBox<Value> {
    var result: Result<Value, Error>?
}

private struct RecordingCommandOptions {
    let options: [String: String]

    init(arguments: [String]) {
        var parsed: [String: String] = [:]
        var iterator = arguments.dropFirst().makeIterator()
        while let key = iterator.next() {
            guard key.hasPrefix("--"), let value = iterator.next() else {
                continue
            }
            parsed[String(key.dropFirst(2))] = value
        }
        self.options = parsed
    }

    func required(_ key: String) throws -> String {
        guard let value = options[key], !value.isEmpty else {
            throw RecordingCaptureError.missingOption("--\(key)")
        }
        return value
    }

    func double(_ key: String, default defaultValue: Double) -> Double {
        guard let value = options[key], let number = Double(value) else {
            return defaultValue
        }
        return number
    }
}

private struct RecordingWindowSelection {
    let content: SCShareableContent
    let window: SCWindow
    let display: SCDisplay
}

private struct RecordingRegionSelection {
    let display: SCDisplay
    let sourceRect: CGRect
}

private func recordingShareableContent() async throws -> SCShareableContent {
    guard CGPreflightScreenCaptureAccess() else {
        throw RecordingCaptureError.screenRecordingPermissionMissing
    }
    return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
}

private func recordingDisplayContaining(window: SCWindow, displays: [SCDisplay]) -> SCDisplay? {
    let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
    return displays.first(where: { $0.frame.contains(center) }) ?? displays.first
}

private func recordingRegionSelection(for rect: CGRect, displays: [SCDisplay]) -> RecordingRegionSelection? {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    guard let display = displays.first(where: { $0.frame.contains(center) }) ?? displays.first else {
        return nil
    }

    let localRect = CGRect(
        x: rect.origin.x - display.frame.origin.x,
        y: rect.origin.y - display.frame.origin.y,
        width: rect.width,
        height: rect.height
    )
    return RecordingRegionSelection(display: display, sourceRect: localRect)
}

private func recordingRectArea(_ rect: CGRect) -> CGFloat {
    max(rect.width, 0) * max(rect.height, 0)
}

private func recordingBestWindowSelection(bundleId: String) async throws -> RecordingWindowSelection {
    let content = try await recordingShareableContent()
    let candidates = content.windows.filter { window in
        window.owningApplication?.bundleIdentifier == bundleId &&
            window.isOnScreen &&
            window.windowLayer == 0
    }
    let sizable = candidates.filter { $0.frame.width >= 320 && $0.frame.height >= 240 }
    let primary = sizable.isEmpty ? candidates : sizable

    let selected: SCWindow
    if let active = primary.first(where: \.isActive) {
        selected = active
    } else if let largest = primary.max(by: { recordingRectArea($0.frame) < recordingRectArea($1.frame) }) {
        selected = largest
    } else {
        throw RecordingCaptureError.windowNotFound(bundleId)
    }

    guard let display = recordingDisplayContaining(window: selected, displays: content.displays) else {
        throw RecordingCaptureError.windowNotFound(bundleId)
    }
    return RecordingWindowSelection(content: content, window: selected, display: display)
}

@available(macOS 15.0, *)
@MainActor
private final class LatticesWindowRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private let writer: RecordingResponseWriter
    private let logger: RecordingDebugLogger
    private var finishedSignalPath: String?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?
    private var recordingStarted = false
    private var recordingFinished = false
    private var recordingError: Error?

    init(writer: RecordingResponseWriter, logger: RecordingDebugLogger) {
        self.writer = writer
        self.logger = logger
    }

    func recordRegion(
        rect: CGRect,
        outputPath: String,
        stopSignalPath: String?,
        finishedSignalPath: String?,
        fps: Double,
        scale: Double
    ) async throws {
        logger.log("record-region: begin rect=\(rect) outputPath=\(outputPath)")
        self.finishedSignalPath = finishedSignalPath
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let content = try await recordingShareableContent()
        guard let selection = recordingRegionSelection(for: rect, displays: content.displays) else {
            throw RecordingCaptureError.displayNotFound("Could not resolve a display for rect \(rect)")
        }

        let filter = SCContentFilter(display: selection.display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(selection.sourceRect.width * scale), 1)
        configuration.height = max(Int(selection.sourceRect.height * scale), 1)
        configuration.minimumFrameInterval = CMTime(seconds: 1 / max(fps, 1), preferredTimescale: 600)
        configuration.sourceRect = selection.sourceRect
        configuration.showsCursor = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        try stream.addRecordingOutput(recordingOutput)

        self.stream = stream
        self.recordingOutput = recordingOutput

        try await stream.startCapture()
        try await waitForRecordingStart()
        try writer.write(RecordingProbeResponse(status: "recording", outputPath: outputPath, detail: nil))

        try waitForStopSignalOrStdin(stopSignalPath)

        try await stream.stopCapture()
        try await waitForRecordingFinish()
        try writer.write(RecordingProbeResponse(status: "finished", outputPath: outputPath, detail: nil))
        try writeSignalFile(path: finishedSignalPath, contents: "finished\n")
    }

    func recordAppWindow(
        bundleId: String,
        outputPath: String,
        stopSignalPath: String?,
        finishedSignalPath: String?
    ) async throws {
        logger.log("record-window: begin bundleId=\(bundleId) outputPath=\(outputPath)")
        self.finishedSignalPath = finishedSignalPath
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let selection = try await recordingBestWindowSelection(bundleId: bundleId)
        let window = selection.window
        let filter = SCContentFilter(display: selection.display, including: [window])
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(window.frame.width), 1)
        configuration.height = max(Int(window.frame.height), 1)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.sourceRect = window.frame
        configuration.showsCursor = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        try stream.addRecordingOutput(recordingOutput)

        self.stream = stream
        self.recordingOutput = recordingOutput

        try await stream.startCapture()
        try await waitForRecordingStart()
        try writer.write(RecordingProbeResponse(status: "recording", outputPath: outputPath, detail: nil))

        try waitForStopSignalOrStdin(stopSignalPath)

        try await stream.stopCapture()
        try await waitForRecordingFinish()
        try writer.write(RecordingProbeResponse(status: "finished", outputPath: outputPath, detail: nil))
        try writeSignalFile(path: finishedSignalPath, contents: "finished\n")
    }

    private func waitForStopSignalOrStdin(_ path: String?) throws {
        guard let path, !path.isEmpty else {
            _ = try FileHandle.standardInput.readToEnd()
            return
        }

        while !FileManager.default.fileExists(atPath: path) {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func waitForRecordingStart() async throws {
        if let recordingError { throw recordingError }
        if recordingStarted { return }
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
    }

    private func waitForRecordingFinish() async throws {
        if let recordingError { throw recordingError }
        if recordingFinished { return }
        try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
        }
    }

    private func writeSignalFile(path: String?, contents: String) throws {
        guard let path, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    private func handleRecordingFailure(_ error: Error) {
        recordingError = error
        try? writeSignalFile(path: finishedSignalPath, contents: "error:\(error.localizedDescription)\n")
        startContinuation?.resume(throwing: error)
        startContinuation = nil
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in self.handleRecordingFailure(error) }
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.recordingStarted = true
            self.startContinuation?.resume()
            self.startContinuation = nil
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.recordingFinished = true
            self.finishContinuation?.resume()
            self.finishContinuation = nil
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.handleRecordingFailure(error) }
    }
}

@available(macOS 15.0, *)
@MainActor
final class LatticesRecordingProbeAppRunner {
    private static var retainedRunner: LatticesRecordingProbeAppRunner?

    enum Target {
        case region(CGRect)
        case appWindow(String)
    }

    struct Configuration {
        let target: Target
        let outputPath: String
        let stopSignalPath: String?
        let finishedSignalPath: String?
        let fps: Double
        let scale: Double
        let replyFile: String?
        let debugLogPath: String?
    }

    private let configuration: Configuration
    private let writer: RecordingResponseWriter
    private let logger: RecordingDebugLogger
    private var window: NSWindow?

    init(configuration: Configuration) {
        self.configuration = configuration
        self.writer = RecordingResponseWriter(replyFile: configuration.replyFile)
        self.logger = RecordingDebugLogger(path: configuration.debugLogPath)
    }

    static func startFromCommandLineIfNeeded() -> Bool {
        guard CommandLine.arguments.contains("recording-probe") else {
            return false
        }

        do {
            let configuration = try configurationFromCommandLine()
            let runner = LatticesRecordingProbeAppRunner(configuration: configuration)
            retainedRunner = runner
            runner.start()
        } catch {
            let writer = RecordingResponseWriter(replyFile: optionValue("reply-file"))
            try? writer.write(RecordingProbeResponse(
                status: "error",
                outputPath: optionValue("output"),
                detail: error.localizedDescription
            ))
            NSApplication.shared.terminate(nil)
        }
        return true
    }

    private static func configurationFromCommandLine() throws -> Configuration {
        let options = RecordingCommandOptions(arguments: CommandLine.arguments)
        let outputPath = try options.required("output")
        let target: Target

        if let bundleId = options.options["bundle-id"], !bundleId.isEmpty {
            target = .appWindow(bundleId)
        } else {
            let x = Double(try options.required("x")) ?? 0
            let y = Double(try options.required("y")) ?? 0
            let width = Double(try options.required("width")) ?? 0
            let height = Double(try options.required("height")) ?? 0
            target = .region(CGRect(x: x, y: y, width: width, height: height))
        }

        return Configuration(
            target: target,
            outputPath: outputPath,
            stopSignalPath: options.options["stop-file"],
            finishedSignalPath: options.options["finished-file"],
            fps: options.double("fps", default: 30),
            scale: options.double("scale", default: 1),
            replyFile: options.options["reply-file"],
            debugLogPath: options.options["debug-log"]
        )
    }

    private static func optionValue(_ key: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--\(key)"),
              args.indices.contains(index + 1)
        else {
            return nil
        }
        return args[index + 1]
    }

    private func start() {
        NSApp.setActivationPolicy(.accessory)
        showHiddenWindow()

        let configuration = self.configuration
        let writer = self.writer
        let logger = self.logger
        Task { @MainActor in
            let recorder = LatticesWindowRecorder(writer: writer, logger: logger)
            do {
                switch configuration.target {
                case .region(let rect):
                    try await recorder.recordRegion(
                        rect: rect,
                        outputPath: configuration.outputPath,
                        stopSignalPath: configuration.stopSignalPath,
                        finishedSignalPath: configuration.finishedSignalPath,
                        fps: configuration.fps,
                        scale: configuration.scale
                    )
                case .appWindow(let bundleId):
                    try await recorder.recordAppWindow(
                        bundleId: bundleId,
                        outputPath: configuration.outputPath,
                        stopSignalPath: configuration.stopSignalPath,
                        finishedSignalPath: configuration.finishedSignalPath
                    )
                }
                Self.retainedRunner = nil
                NSApplication.shared.terminate(nil)
            } catch {
                logger.log("recording-probe failed: \(error.localizedDescription)")
                try? writer.write(RecordingProbeResponse(
                    status: "error",
                    outputPath: configuration.outputPath,
                    detail: error.localizedDescription
                ))
                if let finishedSignalPath = configuration.finishedSignalPath {
                    let url = URL(fileURLWithPath: finishedSignalPath)
                    try? FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try? Data("error:\(error.localizedDescription)\n".utf8).write(to: url)
                }
                Self.retainedRunner = nil
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func showHiddenWindow() {
        let window = NSWindow(
            contentRect: CGRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        self.window = window
    }
}

enum LatticesRecordingProbeLauncher {
    static func launchRegion(
        rect: CGRect,
        outputPath: String,
        stopSignalPath: String?,
        finishedSignalPath: String?,
        debugLogPath: String?,
        fps: Double,
        scale: Double
    ) async throws -> [String: String] {
        var arguments = [
            "recording-probe",
            "--x", String(describing: rect.origin.x),
            "--y", String(describing: rect.origin.y),
            "--width", String(describing: rect.size.width),
            "--height", String(describing: rect.size.height),
            "--output", outputPath,
            "--fps", String(describing: fps),
            "--scale", String(describing: scale),
        ]
        appendSignals(
            to: &arguments,
            stopSignalPath: stopSignalPath,
            finishedSignalPath: finishedSignalPath,
            debugLogPath: debugLogPath
        )
        return try await launch(arguments: arguments, outputPath: outputPath)
    }

    static func launchAppWindow(
        bundleId: String,
        outputPath: String,
        stopSignalPath: String?,
        finishedSignalPath: String?,
        debugLogPath: String?
    ) async throws -> [String: String] {
        var arguments = [
            "recording-probe",
            "--bundle-id", bundleId,
            "--output", outputPath,
        ]
        appendSignals(
            to: &arguments,
            stopSignalPath: stopSignalPath,
            finishedSignalPath: finishedSignalPath,
            debugLogPath: debugLogPath
        )
        return try await launch(arguments: arguments, outputPath: outputPath, detail: bundleId)
    }

    private static func appendSignals(
        to arguments: inout [String],
        stopSignalPath: String?,
        finishedSignalPath: String?,
        debugLogPath: String?
    ) {
        if let stopSignalPath, !stopSignalPath.isEmpty {
            arguments.append(contentsOf: ["--stop-file", stopSignalPath])
        }
        if let finishedSignalPath, !finishedSignalPath.isEmpty {
            arguments.append(contentsOf: ["--finished-file", finishedSignalPath])
        }
        if let debugLogPath, !debugLogPath.isEmpty {
            arguments.append(contentsOf: ["--debug-log", debugLogPath])
        }
    }

    private static func launch(
        arguments: [String],
        outputPath: String,
        detail: String? = nil
    ) async throws -> [String: String] {
        let bundleURL = try resolveAppBundleURL()
        let replyFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lattices-recording-probe-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: replyFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundleURL.path, "--args"] + arguments + ["--reply-file", replyFile.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw RouterError.custom("Failed to launch recording probe via open(1)")
        }

        let response = try await waitForProbeReply(at: replyFile)
        if response.status == "error" {
            throw RouterError.custom(response.detail ?? "Recording probe failed to start")
        }

        var result: [String: String] = [
            "status": response.status,
            "outputPath": response.outputPath ?? outputPath,
        ]
        if let detail { result["detail"] = detail }
        return result
    }

    private static func waitForProbeReply(at replyFile: URL) async throws -> RecordingProbeResponse {
        for _ in 0..<100 {
            if let data = try? Data(contentsOf: replyFile), !data.isEmpty {
                return try JSONDecoder().decode(RecordingProbeResponse.self, from: data)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw RouterError.custom("Recording probe did not acknowledge launch")
    }

    private static func resolveAppBundleURL() throws -> URL {
        let bundleURL = Bundle.main.bundleURL
        var fallbackAppBundleURL: URL?

        func inspect(candidate: URL) -> URL? {
            guard candidate.pathExtension == "app" else { return nil }
            if fallbackAppBundleURL == nil {
                fallbackAppBundleURL = candidate
            }
            if candidate.lastPathComponent == "Lattices.app" {
                return candidate
            }
            return nil
        }

        if let resolved = inspect(candidate: bundleURL) {
            return resolved
        }

        if let executableURL = Bundle.main.executableURL {
            var candidate = executableURL.deletingLastPathComponent()
            while candidate.path != "/" {
                if let resolved = inspect(candidate: candidate) {
                    return resolved
                }
                candidate.deleteLastPathComponent()
            }
        }

        if let fallbackAppBundleURL {
            return fallbackAppBundleURL
        }

        throw RouterError.custom("Unable to resolve Lattices.app bundle URL for recording probe")
    }
}

extension CaptureController {
    func recordWindow(params: JSON?) throws -> JSON {
        let source = params?["source"]?.stringValue ?? "daemon"
        let target = try resolveWindow(params: params)
        let frame = CGRect(
            x: target.frame.x,
            y: target.frame.y,
            width: target.frame.w,
            height: target.frame.h
        )
        let title = params?["title"]?.stringValue ?? "Record \(target.app)"
        let run = try resolveRun(params: params, title: title, source: source, surfaces: [.window(target)])
        let mode = params?["mode"]?.stringValue ?? "region"
        let fps = params?["fps"]?.numericDouble ?? 30
        let scale = params?["scale"]?.numericDouble ?? 1
        let filename = recordingFilename(params?["filename"]?.stringValue, fallback: "recording-window-\(target.wid)-\(Self.recordingTimestamp()).mov")

        let request = RecordingRequest(
            run: run,
            title: title,
            source: source,
            filename: filename,
            fps: fps,
            scale: scale,
            targetDescription: "window \(target.wid)",
            surfaceMetadata: [
                "wid": .int(Int(target.wid)),
                "app": .string(target.app),
                "title": .string(target.title),
                "frame": .object([
                    "x": .double(target.frame.x),
                    "y": .double(target.frame.y),
                    "w": .double(target.frame.w),
                    "h": .double(target.frame.h),
                ]),
            ]
        )

        if mode == "app-window" || mode == "window" {
            guard let bundleId = NSRunningApplication(processIdentifier: target.pid)?.bundleIdentifier else {
                throw RouterError.custom("Unable to resolve bundle id for \(target.app)")
            }
            return try startRecording(request: request) { outputPath, stopPath, finishedPath, debugPath in
                try await LatticesRecordingProbeLauncher.launchAppWindow(
                    bundleId: bundleId,
                    outputPath: outputPath,
                    stopSignalPath: stopPath,
                    finishedSignalPath: finishedPath,
                    debugLogPath: debugPath
                )
            }
        }

        return try startRecording(request: request) { outputPath, stopPath, finishedPath, debugPath in
            try await LatticesRecordingProbeLauncher.launchRegion(
                rect: frame,
                outputPath: outputPath,
                stopSignalPath: stopPath,
                finishedSignalPath: finishedPath,
                debugLogPath: debugPath,
                fps: fps,
                scale: scale
            )
        }
    }

    func recordRegion(params: JSON?) throws -> JSON {
        let source = params?["source"]?.stringValue ?? "daemon"
        let x = params?["x"]?.numericDouble
        let y = params?["y"]?.numericDouble
        let width = params?["width"]?.numericDouble ?? params?["w"]?.numericDouble
        let height = params?["height"]?.numericDouble ?? params?["h"]?.numericDouble

        let rect: CGRect
        let surfaces: [RunSurface]
        if let x, let y, let width, let height {
            rect = CGRect(x: x, y: y, width: width, height: height)
            surfaces = [
                RunSurface(
                    id: "region-\(Int(x))-\(Int(y))-\(Int(width))-\(Int(height))",
                    kind: "region",
                    wid: nil,
                    app: nil,
                    title: "Screen region",
                    frame: RunFrame(WindowFrame(x: x, y: y, w: width, h: height)),
                    latticesSession: nil,
                    x: nil,
                    y: nil
                )
            ]
        } else {
            let target = try resolveWindow(params: params)
            rect = CGRect(
                x: target.frame.x,
                y: target.frame.y,
                width: target.frame.w,
                height: target.frame.h
            )
            surfaces = [.window(target)]
        }

        let title = params?["title"]?.stringValue ?? "Record Region"
        let run = try resolveRun(params: params, title: title, source: source, surfaces: surfaces)
        let fps = params?["fps"]?.numericDouble ?? 30
        let scale = params?["scale"]?.numericDouble ?? 1
        let filename = recordingFilename(params?["filename"]?.stringValue, fallback: "recording-region-\(Self.recordingTimestamp()).mov")

        let request = RecordingRequest(
            run: run,
            title: title,
            source: source,
            filename: filename,
            fps: fps,
            scale: scale,
            targetDescription: "region \(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width))x\(Int(rect.height))",
            surfaceMetadata: [
                "frame": .object([
                    "x": .double(rect.origin.x),
                    "y": .double(rect.origin.y),
                    "w": .double(rect.width),
                    "h": .double(rect.height),
                ]),
            ]
        )

        return try startRecording(request: request) { outputPath, stopPath, finishedPath, debugPath in
            try await LatticesRecordingProbeLauncher.launchRegion(
                rect: rect,
                outputPath: outputPath,
                stopSignalPath: stopPath,
                finishedSignalPath: finishedPath,
                debugLogPath: debugPath,
                fps: fps,
                scale: scale
            )
        }
    }

    func stopRecording(params: JSON?) throws -> JSON {
        let runId = params?["runId"]?.stringValue ?? params?["id"]?.stringValue
        let wait = params?["wait"]?.boolValue ?? true
        let timeoutMs = params?["timeoutMs"]?.intValue ?? 30_000

        let run: RunSession?
        if let runId, !runId.isEmpty {
            run = RunStore.shared.get(id: runId)
        } else {
            run = nil
        }

        let artifact = run?.artifacts.last(where: { $0.kind == "recording" })
        let stopPath = params?["stopFile"]?.stringValue ?? artifact?.metadata["stopFile"]?.stringValue
        let finishedPath = params?["finishedFile"]?.stringValue ?? artifact?.metadata["finishedFile"]?.stringValue

        guard let stopPath, !stopPath.isEmpty else {
            throw RouterError.missingParam("runId or stopFile")
        }

        let stopURL = URL(fileURLWithPath: stopPath)
        try FileManager.default.createDirectory(at: stopURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stop\n".utf8).write(to: stopURL)

        if let runId, !runId.isEmpty {
            _ = try? RunStore.shared.appendTrace(
                id: runId,
                kind: "capture.recording.stopRequested",
                summary: "Requested recording stop",
                data: ["stopFile": .string(stopPath)]
            )
        }

        var marker = ""
        var finished = false
        if wait, let finishedPath, !finishedPath.isEmpty {
            let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
            while Date() < deadline {
                if FileManager.default.fileExists(atPath: finishedPath) {
                    marker = (try? String(contentsOfFile: finishedPath, encoding: .utf8)) ?? ""
                    finished = true
                    break
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }

        var responseRun: RunSession? = nil
        if let runId, !runId.isEmpty {
            let outputPath = artifact?.path
            let byteSize = outputPath.flatMap { path in
                (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue
            }
            let data: [String: JSON] = [
                "stopFile": .string(stopPath),
                "finishedFile": .string(finishedPath ?? ""),
                "finished": .bool(finished),
                "marker": .string(marker.trimmingCharacters(in: .whitespacesAndNewlines)),
                "byteSize": .int(byteSize ?? 0),
            ]

            if marker.hasPrefix("error:") {
                responseRun = try? RunStore.shared.fail(
                    id: runId,
                    summary: "Recording failed",
                    data: data
                )
            } else if finished || !wait {
                responseRun = try? RunStore.shared.complete(
                    id: runId,
                    summary: finished ? "Recording finished" : "Recording stop requested",
                    data: data
                )
            } else {
                responseRun = try? RunStore.shared.appendTrace(
                    id: runId,
                    kind: "capture.recording.stopTimedOut",
                    summary: "Timed out waiting for recording finish marker",
                    data: data
                )
            }
        }

        return .object([
            "ok": .bool(finished || !wait),
            "finished": .bool(finished),
            "stopFile": .string(stopPath),
            "finishedFile": .string(finishedPath ?? ""),
            "marker": .string(marker.trimmingCharacters(in: .whitespacesAndNewlines)),
            "run": responseRun?.json ?? .null,
        ])
    }

    private struct RecordingRequest {
        let run: RunSession
        let title: String
        let source: String
        let filename: String
        let fps: Double
        let scale: Double
        let targetDescription: String
        let surfaceMetadata: [String: JSON]
    }

    private func startRecording(
        request: RecordingRequest,
        launch: @escaping (_ outputPath: String, _ stopPath: String, _ finishedPath: String, _ debugPath: String) async throws -> [String: String]
    ) throws -> JSON {
        let run = request.run
        let outputURL = RunStore.shared.artifactURL(for: run, filename: request.filename)
        let stopURL = RunStore.shared.artifactURL(for: run, filename: "recording.stop")
        let finishedURL = RunStore.shared.artifactURL(for: run, filename: "recording.finished")
        let debugURL = RunStore.shared.artifactURL(for: run, filename: "recording.log")

        try? FileManager.default.removeItem(at: outputURL)
        try? FileManager.default.removeItem(at: stopURL)
        try? FileManager.default.removeItem(at: finishedURL)
        try? FileManager.default.removeItem(at: debugURL)

        _ = try RunStore.shared.markRunning(
            id: run.id,
            summary: "Starting recording",
            data: [
                "target": .string(request.targetDescription),
                "output": .string(outputURL.path),
                "stopFile": .string(stopURL.path),
                "finishedFile": .string(finishedURL.path),
            ]
        )

        do {
            let probe = try waitForAsync {
                try await launch(outputURL.path, stopURL.path, finishedURL.path, debugURL.path)
            }

            var metadata = request.surfaceMetadata
            metadata["state"] = .string("recording")
            metadata["stopFile"] = .string(stopURL.path)
            metadata["finishedFile"] = .string(finishedURL.path)
            metadata["debugLog"] = .string(debugURL.path)
            metadata["fps"] = .double(request.fps)
            metadata["scale"] = .double(request.scale)
            metadata["probeStatus"] = .string(probe["status"] ?? "recording")

            let artifact = RunStore.shared.makeArtifact(
                run: run,
                kind: "recording",
                url: outputURL,
                mimeType: "video/quicktime",
                metadata: metadata
            )
            let updated = try RunStore.shared.appendArtifact(artifact)
            let responseRun = try RunStore.shared.appendTrace(
                id: updated.id,
                kind: "capture.recording.started",
                summary: "Recording started",
                data: [
                    "artifactId": .string(artifact.id),
                    "path": .string(artifact.path),
                    "stopFile": .string(stopURL.path),
                    "finishedFile": .string(finishedURL.path),
                ]
            )

            return .object([
                "ok": .bool(true),
                "run": responseRun.json,
                "artifact": artifact.json,
                "stopFile": .string(stopURL.path),
                "finishedFile": .string(finishedURL.path),
                "debugLog": .string(debugURL.path),
                "probe": .object(probe.mapValues { .string($0) }),
            ])
        } catch {
            _ = try? RunStore.shared.fail(
                id: run.id,
                summary: "Recording failed to start",
                data: [
                    "error": .string(error.localizedDescription),
                    "output": .string(outputURL.path),
                ]
            )
            throw error
        }
    }

    private func waitForAsync<T>(_ block: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = RecordingAsyncResultBox<T>()
        Task.detached {
            do {
                box.result = Result.success(try await block())
            } catch {
                box.result = Result.failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.result!.get()
    }

    private func recordingFilename(_ raw: String?, fallback: String) -> String {
        let name = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallback
            : raw!.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return safe.lowercased().hasSuffix(".mov") ? safe : "\(safe).mov"
    }

    private static func recordingTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
