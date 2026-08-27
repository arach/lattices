import AppKit
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

public enum ActionCaptureError: LocalizedError {
    case screenRecordingPermissionMissing
    case windowNotFound(String)
    case displayNotFound(String)
    case unableToEncodeImage

    public var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionMissing:
            return "Screen Recording permission has not been granted yet."
        case .windowNotFound(let bundleId):
            return "Could not find an on-screen window for \(bundleId)"
        case .displayNotFound(let detail):
            return detail
        case .unableToEncodeImage:
            return "Unable to encode screenshot as PNG"
        }
    }
}

public struct ActionWindowSelection {
    public let content: SCShareableContent
    public let window: SCWindow
    public let display: SCDisplay
}

public struct ActionRegionSelection {
    public let display: SCDisplay
    public let sourceRect: CGRect
}

public func actionShareableContent() async throws -> SCShareableContent {
    guard CGPreflightScreenCaptureAccess() else {
        throw ActionCaptureError.screenRecordingPermissionMissing
    }

    return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
}

public func actionBestWindowSelection(for bundleId: String) async throws -> ActionWindowSelection {
    let content = try await actionShareableContent()
    let candidates = content.windows.filter { window in
        window.owningApplication?.bundleIdentifier == bundleId && window.isOnScreen && window.windowLayer == 0
    }
    return try actionSelectWindow(from: candidates, content: content, target: bundleId)
}

/// Pid targeting names one process exactly, so it takes any window that process owns:
/// accessory-app panels live above layer 0 and would vanish behind the layer filter that
/// bundle-id targeting keeps for regular apps. The largest window wins outright — an
/// accessory app's detached chrome (title rails, toolbars) can report as active, and the
/// panel it belongs to is the surface worth capturing.
public func actionBestWindowSelection(pid: pid_t) async throws -> ActionWindowSelection {
    let content = try await actionShareableContent()
    let candidates = content.windows.filter { window in
        window.owningApplication?.processID == pid && window.isOnScreen
    }

    guard let largest = candidates.max(by: { lhs, rhs in
        lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
    }) else {
        throw ActionCaptureError.windowNotFound("pid \(pid)")
    }
    guard let display = actionDisplayContaining(window: largest, displays: content.displays) else {
        throw ActionCaptureError.windowNotFound("pid \(pid)")
    }

    return ActionWindowSelection(content: content, window: largest, display: display)
}

private func actionSelectWindow(
    from candidates: [SCWindow],
    content: SCShareableContent,
    target: String
) throws -> ActionWindowSelection {
    let selectedWindow: SCWindow

    if let active = candidates.first(where: \.isActive) {
        selectedWindow = active
    } else if let largest = candidates.max(by: { lhs, rhs in
        lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
    }) {
        selectedWindow = largest
    } else {
        throw ActionCaptureError.windowNotFound(target)
    }

    guard let display = actionDisplayContaining(window: selectedWindow, displays: content.displays) else {
        throw ActionCaptureError.windowNotFound(target)
    }

    return ActionWindowSelection(content: content, window: selectedWindow, display: display)
}

public func actionRegionSelection(for rect: CGRect, displays: [SCDisplay]) -> ActionRegionSelection? {
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

    return ActionRegionSelection(display: display, sourceRect: localRect)
}

public func actionCaptureAppWindowScreenshot(bundleId: String, outputPath: String) async throws {
    let selection = try await actionBestWindowSelection(for: bundleId)
    try actionWriteWindowScreenshot(selection: selection, outputPath: outputPath)
}

public func actionCaptureAppWindowScreenshot(pid: pid_t, outputPath: String) async throws {
    let selection = try await actionBestWindowSelection(pid: pid)
    try actionWriteWindowScreenshot(selection: selection, outputPath: outputPath)
}

private func actionWriteWindowScreenshot(selection: ActionWindowSelection, outputPath: String) throws {
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let window = selection.window
    guard let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(window.windowID),
        [.bestResolution, .boundsIgnoreFraming]
    ) else {
        throw ActionCaptureError.unableToEncodeImage
    }

    guard let data = actionPNGData(from: image) else {
        throw ActionCaptureError.unableToEncodeImage
    }

    try data.write(to: outputURL)
}

public func actionCaptureRegionScreenshot(rect: CGRect, outputPath: String) async throws {
    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    let content = try await actionShareableContent()
    guard let selection = actionRegionSelection(for: rect, displays: content.displays) else {
        throw ActionCaptureError.displayNotFound("Could not resolve a display for rect \(rect)")
    }

    guard let image = CGDisplayCreateImage(selection.display.displayID, rect: selection.sourceRect) else {
        throw ActionCaptureError.unableToEncodeImage
    }

    guard let data = actionPNGData(from: image) else {
        throw ActionCaptureError.unableToEncodeImage
    }

    try data.write(to: outputURL)
}

public func actionCaptureScreenScreenshot(outputPath: String) throws {
    // The window and region paths reach this guard through actionShareableContent().
    // This one talks to CGDisplayCreateImage directly, which does not fail without
    // Screen Recording permission — it returns a desktop-only image with every window
    // missing. So the caller got a black PNG reported as a successful capture, and OCR
    // and vision then ran on it. Refusing is the honest answer.
    guard CGPreflightScreenCaptureAccess() else {
        throw ActionCaptureError.screenRecordingPermissionMissing
    }

    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
        throw ActionCaptureError.unableToEncodeImage
    }

    guard let data = actionPNGData(from: image) else {
        throw ActionCaptureError.unableToEncodeImage
    }

    try data.write(to: outputURL)
}

@available(macOS 15.0, *)
public final class ActionCaptureRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate, SCStreamOutput {
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private let logger: (String) -> Void
    private let sampleBufferQueue = DispatchQueue(label: "dev.action.capture.sample-buffer")
    private var finishedSignalPath: String?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?
    private var recordingStarted = false
    private var recordingFinished = false
    private var recordingError: Error?

    public init(logger: @escaping (String) -> Void = { _ in }) {
        self.logger = logger
    }

    public func recordRegion(
        rect: CGRect,
        outputPath: String,
        stopSignalPath: String?,
        finishedSignalPath: String?,
        fps: Double,
        scale: Double
    ) async throws {
        logger("record-region: begin rect=\(rect) outputPath=\(outputPath)")
        self.finishedSignalPath = finishedSignalPath
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let content = try await actionShareableContent()
        guard let selection = actionRegionSelection(for: rect, displays: content.displays) else {
            throw ActionCaptureError.displayNotFound("Could not resolve a display for rect \(rect)")
        }

        logger("record-region: display frame=\(selection.display.frame) sourceRect=\(selection.sourceRect)")
        let filter = SCContentFilter(display: selection.display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(selection.sourceRect.width * scale), 1)
        configuration.height = max(Int(selection.sourceRect.height * scale), 1)
        configuration.minimumFrameInterval = CMTime(seconds: 1 / max(fps, 1), preferredTimescale: 600)
        configuration.sourceRect = selection.sourceRect

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleBufferQueue)
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

        if let stopSignalPath {
            try waitForStopSignal(at: stopSignalPath)
        } else {
            _ = try FileHandle.standardInput.readToEnd()
        }

        try await stream.stopCapture()
        try await waitForRecordingFinish()
        try writeSignalFile(path: finishedSignalPath, contents: "finished\n")
    }

    public func recordAppWindow(
        bundleId: String,
        outputPath: String,
        stopSignalPath: String?,
        finishedSignalPath: String?
    ) async throws {
        logger("record: begin bundleId=\(bundleId) outputPath=\(outputPath)")
        self.finishedSignalPath = finishedSignalPath
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let selection = try await actionBestWindowSelection(for: bundleId)
        let window = selection.window
        let filter = SCContentFilter(display: selection.display, including: [window])
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(window.frame.width), 1)
        configuration.height = max(Int(window.frame.height), 1)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.sourceRect = window.frame

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleBufferQueue)
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

        if let stopSignalPath {
            try waitForStopSignal(at: stopSignalPath)
        } else {
            _ = try FileHandle.standardInput.readToEnd()
        }

        try await stream.stopCapture()
        try await waitForRecordingFinish()
        try writeSignalFile(path: finishedSignalPath, contents: "finished\n")
    }

    private func waitForStopSignal(at path: String) throws {
        let stopURL = URL(fileURLWithPath: path)
        while !FileManager.default.fileExists(atPath: stopURL.path) {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func waitForRecordingStart() async throws {
        if let recordingError {
            throw recordingError
        }
        if recordingStarted {
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
    }

    private func waitForRecordingFinish() async throws {
        if let recordingError {
            throw recordingError
        }
        if recordingFinished {
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
        }
    }

    private func writeSignalFile(path: String?, contents: String) throws {
        guard let path else {
            return
        }

        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    public func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        recordingError = error
        try? writeSignalFile(path: finishedSignalPath, contents: "error:\(error.localizedDescription)\n")
        startContinuation?.resume(throwing: error)
        startContinuation = nil
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
    }

    public func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        recordingStarted = true
        startContinuation?.resume()
        startContinuation = nil
    }

    public func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        recordingFinished = true
        finishContinuation?.resume()
        finishContinuation = nil
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        recordingError = error
        try? writeSignalFile(path: finishedSignalPath, contents: "error:\(error.localizedDescription)\n")
        startContinuation?.resume(throwing: error)
        startContinuation = nil
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        _ = sampleBuffer
        _ = outputType
    }
}

private func actionDisplayContaining(window: SCWindow, displays: [SCDisplay]) -> SCDisplay? {
    let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
    return displays.first(where: { $0.frame.contains(center) }) ?? displays.first
}

private func actionPNGData(from image: CGImage) -> Data? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    return bitmap.representation(using: .png, properties: [:])
}
