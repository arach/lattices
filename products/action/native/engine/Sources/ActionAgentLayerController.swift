import ActionVirtualDisplay
import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

/// The agent layer: a private virtual display the operator never looks at, holding the
/// subject app's windows while an agent drives them, and a picture-in-picture panel on
/// the operator's screen that streams it.
///
/// The display sits diagonally off the bottom-right corner of the arrangement, touching
/// the nearest display only at a corner, so the operator's pointer almost never wanders
/// onto it. Everything that happens there, including blink clicks, reaches the operator
/// only through the panel.
///
/// Lifecycle mirrors the drape: a stop file, the parent pid, or SIGTERM tears it down.
/// Teardown puts every moved window back where it was before the display goes away.
@MainActor
final class ActionAgentLayerController: NSObject {
    private struct MovedWindow {
        let element: AXUIElement
        let pid: pid_t
        let bundleId: String?
        let title: String?
        let original: CGRect
    }

    private let size: CGSize
    private let showsPiP: Bool
    private let target: NSRunningApplication?
    private let stopFile: String?
    private let stateFile: String?
    private let parentProcessID: pid_t?
    /// Narrow the move to one window, so a layer can borrow a single browser window
    /// without taking the operator's others.
    private let windowID: CGWindowID?
    private let windowTitle: String?
    private let writer: ResponseWriter
    private let logger: DebugLogger

    private var display: CGVirtualDisplay?
    private var displayID: CGDirectDisplayID = 0
    private var bounds: CGRect = .zero
    private var moved: [MovedWindow] = []
    private var pip: ActionAgentLayerPiP?
    private var pollTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var shuttingDown = false

    init(options: CommandOptions) throws {
        self.writer = ResponseWriter(replyFile: options.options["reply-file"])
        self.logger = DebugLogger(path: options.options["debug-log"])
        self.size = CGSize(
            width: max(640, options.double("width", default: 1440)),
            height: max(400, options.double("height", default: 900))
        )
        self.showsPiP = !["off", "false", "0", "no"].contains(options.options["pip"]?.lowercased() ?? "on")
        self.stopFile = options.options["stop-file"]
        self.stateFile = options.options["state-file"]
        self.parentProcessID = options.options["parent-pid"].flatMap { pid_t($0) }
        self.windowID = options.options["window-id"].flatMap { CGWindowID($0) }
        self.windowTitle = options.options["window-title"].flatMap { $0.isEmpty ? nil : $0.lowercased() }
        if options.options["pid"] != nil || options.options["bundle-id"] != nil || options.options["bundle-path"] != nil {
            self.target = try resolveTargetApplication(from: options)
        } else {
            self.target = nil
        }
    }

    func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.shutdown() }
            }
            source.resume()
            signalSources.append(source)
        }

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        Task { @MainActor in
            do {
                try await self.start()
            } catch {
                self.logger.log("agent-layer: failed: \(error.localizedDescription)")
                try? self.writer.write(ActionHostResponse(status: "error", outputPath: nil, detail: error.localizedDescription))
                self.shutdown(exitCode: 1)
            }
        }
        app.run()
    }

    // MARK: Start

    private func start() async throws {
        try createDisplay()
        try await waitForDisplay()
        placeOffCorner()
        bounds = CGDisplayBounds(displayID)
        logger.log("agent-layer: display \(displayID) at \(bounds)")

        if let target {
            await moveWindows(of: target)
        }
        try writeState()
        try writer.write(
            ActionHostResponse(
                status: "agent-layer-running",
                outputPath: stateFile,
                detail: String(ProcessInfo.processInfo.processIdentifier)
            )
        )

        if showsPiP {
            let pip = ActionAgentLayerPiP(displayID: displayID, displayBounds: bounds, logger: logger)
            self.pip = pip
            await pip.start()
        }
    }

    private func createDisplay() throws {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.queue = DispatchQueue.main
        descriptor.name = "Action Agent Layer"
        descriptor.maxPixelsWide = UInt32(size.width)
        descriptor.maxPixelsHigh = UInt32(size.height)
        // ~110 ppi, so the system picks a sane default scale.
        descriptor.sizeInMillimeters = CGSize(width: size.width / 110 * 25.4, height: size.height / 110 * 25.4)
        descriptor.vendorID = ActionAgentLayerDisplay.vendorID
        descriptor.productID = ActionAgentLayerDisplay.productID
        descriptor.serialNum = UInt32(ProcessInfo.processInfo.processIdentifier)

        guard let display = CGVirtualDisplay(descriptor: descriptor) else {
            throw ActionHostError.unsupportedOS("could not create the agent layer's virtual display")
        }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 0
        settings.modes = [CGVirtualDisplayMode(width: UInt(size.width), height: UInt(size.height), refreshRate: 60)]
        guard display.apply(settings) else {
            throw ActionHostError.unsupportedOS("the agent layer's virtual display refused its mode")
        }
        self.display = display
        self.displayID = display.displayID
    }

    private func waitForDisplay() async throws {
        for _ in 0..<60 {
            if ActionAgentLayerDisplay.displays().contains(displayID) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ActionHostError.unsupportedOS("the agent layer's virtual display never came online")
    }

    /// Diagonal to the bottom-right-most display, touching it only at the corner.
    private func placeOffCorner() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let others = ids.prefix(Int(count)).filter { $0 != displayID && !ActionAgentLayerDisplay.isAgentLayer($0) }
        guard let anchor = others.map(CGDisplayBounds).max(by: { ($0.maxX + $0.maxY) < ($1.maxX + $1.maxY) }) else {
            return
        }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        CGConfigureDisplayOrigin(config, displayID, Int32(anchor.maxX), Int32(anchor.maxY))
        // .forAppOnly: the arrangement reverts when this process exits, whatever happens to it.
        let result = CGCompleteDisplayConfiguration(config, .forAppOnly)
        logger.log("agent-layer: placed off \(anchor) result=\(result.rawValue)")
    }

    // MARK: Windows

    private func moveWindows(of app: NSRunningApplication) async {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        // A freshly launched host can read an empty window list for a moment.
        var windows: [AXUIElement] = []
        for attempt in 0..<20 {
            windows = (copyAttribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter(isSelected)
            if !windows.isEmpty {
                if attempt > 0 { logger.log("agent-layer: windows visible after \(attempt) retries") }
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !windows.isEmpty else {
            logger.log("agent-layer: \(targetLabel(for: app)) exposes no matching windows")
            return
        }

        // Clear of the layer's menu bar, cascaded so every window stays reachable.
        let inset = CGPoint(x: bounds.minX + 24, y: bounds.minY + 48)
        let room = CGSize(width: bounds.width - 48, height: bounds.height - 72)
        for (index, window) in windows.enumerated() {
            if (copyAttribute(window, kAXMinimizedAttribute) as? Bool) == true { continue }
            guard let origin = axPoint(copyAttribute(window, kAXPositionAttribute)),
                  let extent = axSize(copyAttribute(window, kAXSizeAttribute)) else { continue }
            let original = CGRect(origin: origin, size: extent)
            let step = CGFloat(index) * 28
            var frame = CGRect(
                x: inset.x + step,
                y: inset.y + step,
                width: min(extent.width, room.width - step),
                height: min(extent.height, room.height - step)
            )
            frame.size.width = max(frame.size.width, 200)
            frame.size.height = max(frame.size.height, 120)
            setFrame(window, frame)
            moved.append(
                MovedWindow(
                    element: window,
                    pid: app.processIdentifier,
                    bundleId: app.bundleIdentifier,
                    title: copyAttribute(window, kAXTitleAttribute) as? String,
                    original: original
                )
            )
        }
        logger.log("agent-layer: moved \(moved.count) window(s) of \(targetLabel(for: app))")
    }

    private func isSelected(_ window: AXUIElement) -> Bool {
        if let windowID, axWindowID(window) != windowID { return false }
        if let windowTitle {
            let title = (copyAttribute(window, kAXTitleAttribute) as? String)?.lowercased() ?? ""
            if !title.contains(windowTitle) { return false }
        }
        return true
    }

    private func restoreWindows() {
        for window in moved.reversed() {
            setFrame(window.element, window.original)
        }
        logger.log("agent-layer: restored \(moved.count) window(s)")
        moved.removeAll()
    }

    /// Size, then position, then size again: a window that doesn't fit where it's going
    /// gets clamped by the system, and the second size lands once it's there.
    private func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var size = frame.size
        var origin = frame.origin
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if let pointValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    // MARK: State

    private func writeState() throws {
        guard let stateFile else { return }
        let state: [String: Any] = [
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "displayId": Int(displayID),
            "bounds": rectJSON(bounds),
            "pip": showsPiP,
            "windows": moved.map { window in
                [
                    "pid": Int(window.pid),
                    "bundleId": window.bundleId ?? NSNull(),
                    "title": window.title ?? NSNull(),
                    "original": rectJSON(window.original),
                ] as [String: Any]
            },
            "startedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        let url = URL(fileURLWithPath: stateFile)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func rectJSON(_ rect: CGRect) -> [String: Double] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }

    // MARK: Teardown

    private func tick() {
        if let stopFile, FileManager.default.fileExists(atPath: stopFile) {
            logger.log("agent-layer: stop file received")
            shutdown()
            return
        }
        if let parentProcessID, kill(parentProcessID, 0) != 0 {
            logger.log("agent-layer: parent \(parentProcessID) is gone, closing")
            shutdown()
        }
    }

    private func shutdown(exitCode: Int32 = 0) {
        guard !shuttingDown else { return }
        shuttingDown = true
        pollTimer?.invalidate()
        pollTimer = nil

        pip?.stop()
        pip = nil
        restoreWindows()
        // Releasing the object removes the display; macOS reflows anything left on it.
        display = nil
        if let stateFile { try? FileManager.default.removeItem(atPath: stateFile) }
        if let stopFile { try? FileManager.default.removeItem(atPath: stopFile) }

        // Same reason as the drape: an accessory app with no key window never dequeues
        // the event `NSApplication.stop` waits for, so leaving is the whole teardown.
        logger.log("agent-layer: down")
        Darwin.exit(exitCode)
    }
}

// MARK: - AX helpers

private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}

private func axPoint(_ value: AnyObject?) -> CGPoint? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
}

private func axSize(_ value: AnyObject?) -> CGSize? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
}

// MARK: - Picture in picture

/// A floating panel in the operator's bottom-right corner, streaming the agent layer.
/// The stream crops to the windows on the layer, so a small app fills the panel instead
/// of floating in an empty desktop; the crop follows them as they move and resize.
@MainActor
final class ActionAgentLayerPiP {
    private static let width: CGFloat = 380
    private static let margin: CGFloat = 16
    private static let cropPadding: CGFloat = 12

    private let displayID: CGDirectDisplayID
    private let displayBounds: CGRect
    private let logger: DebugLogger
    private var panel: NSPanel?
    private let videoLayer = AVSampleBufferDisplayLayer()
    private var stream: SCStream?
    private let output: ActionAgentLayerStreamOutput
    private var crop: CGRect = .zero
    private var cropTimer: Timer?

    init(displayID: CGDirectDisplayID, displayBounds: CGRect, logger: DebugLogger) {
        self.displayID = displayID
        self.displayBounds = displayBounds
        self.logger = logger
        self.output = ActionAgentLayerStreamOutput(layer: videoLayer)
    }

    func start() async {
        crop = currentCrop()
        showPanel()
        do {
            try await startStream()
        } catch {
            logger.log("agent-layer pip: stream failed: \(error.localizedDescription)")
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.followWindows() }
        }
        cropTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        cropTimer?.invalidate()
        cropTimer = nil
        stream?.stopCapture { _ in }
        stream = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: Panel

    private func showPanel() {
        guard let screen = NSScreen.screens.first(where: { screenNumber($0) != displayID }) ?? NSScreen.main else { return }
        let height = (Self.width * crop.height / max(crop.width, 1)).rounded()
        let visible = screen.visibleFrame
        let frame = CGRect(
            x: visible.maxX - Self.width - Self.margin,
            y: visible.minY + Self.margin,
            width: Self.width,
            height: height
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.title = "Action Agent Layer"
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentAspectRatio = frame.size
        panel.minSize = CGSize(width: 220, height: 120)

        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        if let root = content.layer {
            root.cornerRadius = 10
            root.cornerCurve = .continuous
            root.masksToBounds = true
            root.backgroundColor = NSColor(srgbRed: 0x10 / 255, green: 0x15 / 255, blue: 0x18 / 255, alpha: 1).cgColor
            root.borderWidth = 1
            root.borderColor = NSColor(white: 0.95, alpha: 0.16).cgColor

            videoLayer.frame = root.bounds
            videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            videoLayer.videoGravity = .resizeAspect
            root.addSublayer(videoLayer)

            // The one coral: this surface is live.
            let dot = CALayer()
            dot.frame = CGRect(x: 10, y: root.bounds.height - 16, width: 6, height: 6)
            dot.autoresizingMask = [.layerMinYMargin]
            dot.cornerRadius = 3
            dot.backgroundColor = NSColor(srgbRed: 0xEF / 255, green: 0x6A / 255, blue: 0x47 / 255, alpha: 1).cgColor
            root.addSublayer(dot)
        }
        panel.contentView = content
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func screenNumber(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    // MARK: Stream

    private func startStream() async throws {
        var scDisplay: SCDisplay?
        for _ in 0..<20 {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            scDisplay = content.displays.first { $0.displayID == displayID }
            if scDisplay != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let scDisplay else {
            throw ActionHostError.captureFailed("ScreenCaptureKit never listed the agent layer display")
        }

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration(), delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        try await stream.startCapture()
        self.stream = stream
        logger.log("agent-layer pip: streaming display \(displayID) crop=\(crop)")
    }

    private func configuration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = crop
        // Twice the panel's width is plenty for a thumbnail and keeps the encoder idle.
        let scale = min(1, (Self.width * 2) / max(crop.width, 1))
        config.width = Int((crop.width * scale).rounded())
        config.height = Int((crop.height * scale).rounded())
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return config
    }

    /// Display-local crop around every window on the layer; the whole layer when it's empty.
    private func currentCrop() -> CGRect {
        let full = CGRect(origin: .zero, size: displayBounds.size)
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return full }
        var union: CGRect?
        for window in info {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict),
                  rect.width > 40, rect.height > 40,
                  displayBounds.intersects(rect) else { continue }
            union = union.map { $0.union(rect) } ?? rect
        }
        guard let union else { return full }
        let local = union
            .intersection(displayBounds)
            .offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)
            .insetBy(dx: -Self.cropPadding, dy: -Self.cropPadding)
            .intersection(full)
        return local.integral
    }

    private func followWindows() async {
        let next = currentCrop()
        guard abs(next.minX - crop.minX) > 4 || abs(next.minY - crop.minY) > 4
            || abs(next.width - crop.width) > 4 || abs(next.height - crop.height) > 4 else { return }
        crop = next
        if let panel {
            // Keep the panel's bottom-right corner put; width stays, height follows the crop.
            let frame = panel.frame
            let height = (frame.width * next.height / max(next.width, 1)).rounded()
            panel.contentAspectRatio = CGSize(width: frame.width, height: height)
            panel.setFrame(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height), display: true, animate: false)
        }
        try? await stream?.updateConfiguration(configuration())
    }
}

/// Hands ScreenCaptureKit frames to the panel's display layer on the capture queue.
private final class ActionAgentLayerStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.arach.action.agent-layer.pip")
    private let layer: AVSampleBufferDisplayLayer

    init(layer: AVSampleBufferDisplayLayer) {
        self.layer = layer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, isComplete(sampleBuffer) else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        if #available(macOS 15.0, *) {
            let renderer = layer.sampleBufferRenderer
            if renderer.status == .failed { renderer.flush() }
            renderer.enqueue(sampleBuffer)
        } else {
            if layer.status == .failed { layer.flush() }
            layer.enqueue(sampleBuffer)
        }
    }

    private func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// The WindowServer id behind an accessibility window, matching `kCGWindowNumber`.
private func axWindowID(_ window: AXUIElement) -> CGWindowID? {
    var id: CGWindowID = 0
    return _AXUIElementGetWindow(window, &id) == .success && id != 0 ? id : nil
}
