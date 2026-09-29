import ActionVirtualDisplay
import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import ImageIO
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
    private var showsPiP: Bool
    private let startedAt = Date()
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
    private var feed: ActionAgentLayerFeed?
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
        // SIGUSR1 brings the viewer back after the operator dismissed it (`layer pip`).
        signal(SIGUSR1, SIG_IGN)
        let showSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        showSource.setEventHandler { [weak self] in
            Task { @MainActor in await self?.showPiP() }
        }
        showSource.resume()
        signalSources.append(showSource)
        // SIGUSR2: a control request is waiting (`layer snapshot`, `layer record`).
        signal(SIGUSR2, SIG_IGN)
        let snapSource = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        snapSource.setEventHandler { [weak self] in
            Task { @MainActor in await self?.answerControl() }
        }
        snapSource.resume()
        signalSources.append(snapSource)

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
        let feed = ActionAgentLayerFeed(
            displayID: displayID,
            displayBounds: bounds,
            subjectPID: target?.processIdentifier,
            logger: logger
        )
        do {
            try await feed.start()
            self.feed = feed
        } catch {
            // The layer still works without it; only the viewer and snapshots go dark.
            logger.log("agent-layer: feed failed: \(error.localizedDescription)")
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
            await showPiP()
        }
    }

    private func showPiP() async {
        guard pip == nil, !shuttingDown, let feed else { return }
        let pip = ActionAgentLayerPiP(feed: feed, logger: logger)
        pip.onDismiss = { [weak self] in
            // The operator closed the viewer; the layer keeps working unseen.
            guard let self else { return }
            self.pip = nil
            self.showsPiP = false
            try? self.writeState()
            self.logger.log("agent-layer: pip dismissed")
        }
        self.pip = pip
        if !showsPiP {
            showsPiP = true
            try? writeState()
        }
        await pip.start(expectsWindows: !moved.isEmpty)
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
            "recording": feed?.recordingPath ?? NSNull(),
            "windows": moved.map { window in
                [
                    "pid": Int(window.pid),
                    "bundleId": window.bundleId ?? NSNull(),
                    "title": window.title ?? NSNull(),
                    "original": rectJSON(window.original),
                ] as [String: Any]
            },
            "startedAt": ISO8601DateFormatter().string(from: startedAt),
        ]
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        let url = URL(fileURLWithPath: stateFile)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private var controlPaths: (request: URL, reply: URL)? {
        guard let stateFile else { return nil }
        let dir = URL(fileURLWithPath: stateFile).deletingLastPathComponent()
        return (dir.appendingPathComponent("control.request.json"), dir.appendingPathComponent("control.reply.json"))
    }

    /// Answers the request the director left next to the state file: a snapshot, or
    /// starting or stopping a recording, all off the running feed.
    private func answerControl() async {
        guard let paths = controlPaths,
              let data = try? Data(contentsOf: paths.request),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = json["id"] as? String else {
            logger.log("agent-layer: control signal without a readable request")
            return
        }
        var reply: [String: Any]
        if let feed {
            switch json["op"] as? String {
            case "snapshot":
                reply = ActionAgentLayerSnapshotRequest(json: json).map(feed.snapshot)
                    ?? ["ok": false, "detail": "snapshot needs an out path"]
            case "record-start":
                if #unavailable(macOS 15.0) {
                    reply = ["ok": false, "detail": "recording the layer needs macOS 15"]
                } else if let out = json["out"] as? String {
                    do {
                        try await feed.startRecording(to: out)
                        reply = ["ok": true, "path": out]
                    } catch {
                        reply = ["ok": false, "detail": error.localizedDescription]
                    }
                } else {
                    reply = ["ok": false, "detail": "record-start needs an out path"]
                }
                try? writeState()
            case "record-stop":
                guard #available(macOS 15.0, *) else {
                    reply = ["ok": false, "detail": "recording the layer needs macOS 15"]
                    break
                }
                do {
                    reply = ["ok": true, "path": try await feed.stopRecording()]
                } catch {
                    reply = ["ok": false, "detail": error.localizedDescription]
                }
                try? writeState()
            default:
                reply = ["ok": false, "detail": "unknown op \(json["op"] ?? "none")"]
            }
        } else {
            reply = ["ok": false, "detail": "the layer has no feed"]
        }
        reply["id"] = id
        if let out = try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys]) {
            try? out.write(to: paths.reply, options: .atomic)
        }
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

        pip?.stop(animated: false)
        pip = nil
        // A take in progress has to be finished, or the movie is unreadable.
        Task { @MainActor in
            await self.feed?.stop()
            self.feed = nil
            self.finishShutdown(exitCode: exitCode)
        }
    }

    private func finishShutdown(exitCode: Int32) {
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

// MARK: - Feed

/// One ScreenCaptureKit stream on the layer, up for the layer's whole life: the viewer
/// draws from it, snapshots read its latest frame, and recordings hang off it, so none
/// of them pays for a capture setup. It captures the layer's display, not the subject
/// app: an app-targeted stream makes macOS badge the app's windows as shared, and the
/// badge lands in every frame. Framing to the subject happens downstream, by crop.
/// The stream only delivers when something changes, so an idle layer costs next to nothing.
@MainActor
final class ActionAgentLayerFeed {
    let displayID: CGDirectDisplayID
    let displayBounds: CGRect
    /// The app whose windows the viewer and snapshots frame; nil frames the whole layer.
    let subjectPID: pid_t?
    private let logger: DebugLogger
    private let output = ActionAgentLayerStreamOutput()
    private var stream: SCStream?

    init(displayID: CGDirectDisplayID, displayBounds: CGRect, subjectPID: pid_t?, logger: DebugLogger) {
        self.displayID = displayID
        self.displayBounds = displayBounds
        self.subjectPID = subjectPID
        self.logger = logger
    }

    func start() async throws {
        var content: SCShareableContent?
        var scDisplay: SCDisplay?
        for _ in 0..<20 {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            scDisplay = content?.displays.first { $0.displayID == displayID }
            if scDisplay != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard content != nil, let scDisplay else {
            throw ActionHostError.captureFailed("ScreenCaptureKit never listed the agent layer display")
        }

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

        let config = SCStreamConfiguration()
        let mode = CGDisplayCopyDisplayMode(displayID)
        config.width = mode?.pixelWidth ?? Int(displayBounds.width)
        config.height = mode?.pixelHeight ?? Int(displayBounds.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        // The feed holds the latest frame for snapshots; leave the stream room past it.
        config.queueDepth = 5
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        try await stream.startCapture()
        self.stream = stream
        logger.log("agent-layer feed: display \(displayID) \(config.width)x\(config.height) subject=\(subjectPID.map(String.init) ?? "all")")
    }

    func stop() async {
        output.detach()
        if #available(macOS 15.0, *), recording != nil { _ = try? await stopRecording() }
        try? await stream?.stopCapture()
        stream = nil
    }

    // MARK: Recording

    /// `SCRecordingOutput` and its delegate, typed loosely so the feed builds before macOS 15.
    private var recording: (output: AnyObject, delegate: AnyObject, path: String)?

    var recordingPath: String? { recording?.path }

    /// Start writing the feed to a movie: the same stream the viewer shows, joined
    /// mid-flight, so the take starts on the next frame with no capture setup.
    @available(macOS 15.0, *)
    func startRecording(to path: String) async throws {
        guard let stream else { throw ActionHostError.captureFailed("the layer has no feed") }
        guard recording == nil else { throw ActionHostError.captureFailed("already recording to \(recording!.path)") }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)

        let config = SCRecordingOutputConfiguration()
        config.outputURL = url
        config.outputFileType = .mov
        config.videoCodecType = .h264
        let delegate = ActionAgentLayerRecordingDelegate()
        let output = SCRecordingOutput(configuration: config, delegate: delegate)
        try stream.addRecordingOutput(output)
        recording = (output, delegate, path)
        do {
            try await delegate.started()
        } catch {
            try? stream.removeRecordingOutput(output)
            recording = nil
            throw error
        }
        logger.log("agent-layer feed: recording to \(path)")
    }

    /// Finish the movie and return its path. The feed keeps running.
    @available(macOS 15.0, *)
    func stopRecording() async throws -> String {
        guard let stream, let recording,
              let output = recording.output as? SCRecordingOutput,
              let delegate = recording.delegate as? ActionAgentLayerRecordingDelegate else {
            throw ActionHostError.captureFailed("not recording")
        }
        self.recording = nil
        try stream.removeRecordingOutput(output)
        try await delegate.finished()
        logger.log("agent-layer feed: recording finished \(recording.path)")
        return recording.path
    }

    /// Route frames into `layer`. `onFrame` fires once, on the main queue, when a frame
    /// is on it: straight away if the feed already has one.
    func attach(_ layer: AVSampleBufferDisplayLayer, onFrame: @escaping @MainActor () -> Void) {
        output.attach(layer) {
            DispatchQueue.main.async { MainActor.assumeIsolated { onFrame() } }
        }
    }

    func detach() {
        output.detach()
    }

    /// Display-local frames of the windows the feed shows, front to back.
    func windowFrames() -> [(id: CGWindowID, frame: CGRect)] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return info.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict),
                  rect.width > 40, rect.height > 40,
                  displayBounds.intersects(rect) else { return nil }
            if let subjectPID, (window[kCGWindowOwnerPID as String] as? pid_t) != subjectPID { return nil }
            return (id, rect.intersection(displayBounds).offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY))
        }
    }

    /// Display-local rect around every window the feed shows; nil when there are none.
    func windowsRect(padding: CGFloat) -> CGRect? {
        let frames = windowFrames().map(\.frame)
        guard let first = frames.first else { return nil }
        let full = CGRect(origin: .zero, size: displayBounds.size)
        return frames.dropFirst().reduce(first) { $0.union($1) }
            .insetBy(dx: -padding, dy: -padding)
            .intersection(full)
            .integral
    }

    /// Write the latest frame as a PNG, cropped to one window (by id), to the subject's
    /// windows, or to the whole layer. No capture happens here: the frame is already in hand.
    func snapshot(_ request: ActionAgentLayerSnapshotRequest) -> [String: Any] {
        guard let (pixels, receivedAt) = output.latest() else {
            return ["ok": false, "detail": "the layer has not produced a frame yet"]
        }
        let full = CGRect(origin: .zero, size: displayBounds.size)
        let crop: CGRect
        if let windowID = request.windowID {
            guard let frame = windowFrames().first(where: { $0.id == windowID })?.frame else {
                return ["ok": false, "detail": "window \(windowID) is not on the layer"]
            }
            crop = frame
        } else if request.full {
            crop = full
        } else {
            crop = windowsRect(padding: 0) ?? full
        }

        let image = CIImage(cvPixelBuffer: pixels)
        let scale = image.extent.width / max(displayBounds.width, 1)
        // CIImage runs bottom-up; the display's points run top-down.
        let pixelCrop = CGRect(
            x: crop.minX * scale,
            y: image.extent.height - crop.maxY * scale,
            width: crop.width * scale,
            height: crop.height * scale
        ).integral.intersection(image.extent)
        guard let cgImage = CIContext().createCGImage(image, from: pixelCrop) else {
            return ["ok": false, "detail": "could not read the frame"]
        }

        let url = URL(fileURLWithPath: request.out)
        let partial = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).partial")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(partial as CFURL, "public.png" as CFString, 1, nil) else {
            return ["ok": false, "detail": "could not write \(request.out)"]
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return ["ok": false, "detail": "could not write \(request.out)"]
        }
        _ = try? FileManager.default.removeItem(at: url)
        do {
            try FileManager.default.moveItem(at: partial, to: url)
        } catch {
            return ["ok": false, "detail": error.localizedDescription]
        }
        return [
            "ok": true,
            "path": request.out,
            "width": cgImage.width,
            "height": cgImage.height,
            "crop": ["x": crop.minX, "y": crop.minY, "width": crop.width, "height": crop.height],
            "windowId": request.windowID.map { Int($0) } ?? NSNull(),
            // How long the screen has been unchanged, not how stale the picture is:
            // the stream delivers whenever anything on the layer changes.
            "unchangedMs": Int(Date().timeIntervalSince(receivedAt) * 1000),
        ]
    }
}

/// Bridges `SCRecordingOutput`'s delegate callbacks to awaitable start and finish.
@available(macOS 15.0, *)
private final class ActionAgentLayerRecordingDelegate: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var startResult: Result<Void, Error>?
    private var finishResult: Result<Void, Error>?
    private var startWaiter: CheckedContinuation<Void, Error>?
    private var finishWaiter: CheckedContinuation<Void, Error>?

    func started() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if let startResult { continuation.resume(with: startResult) } else { startWaiter = continuation }
            }
        }
    }

    func finished() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if let finishResult { continuation.resume(with: finishResult) } else { finishWaiter = continuation }
            }
        }
    }

    private func settle(start: Result<Void, Error>?, finish: Result<Void, Error>?) {
        lock.withLock {
            if let start, startResult == nil {
                startResult = start
                startWaiter?.resume(with: start)
                startWaiter = nil
            }
            if let finish, finishResult == nil {
                finishResult = finish
                finishWaiter?.resume(with: finish)
                finishWaiter = nil
            }
        }
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        settle(start: .success(()), finish: nil)
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        settle(start: nil, finish: .success(()))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        settle(start: .failure(error), finish: .failure(error))
    }
}

struct ActionAgentLayerSnapshotRequest {
    let id: String
    let out: String
    let windowID: CGWindowID?
    let full: Bool

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String, let out = json["out"] as? String else { return nil }
        self.id = id
        self.out = out
        self.windowID = (json["windowId"] as? NSNumber).map { CGWindowID($0.uint32Value) }
        self.full = json["full"] as? Bool ?? false
    }
}

// MARK: - Picture in picture

/// A floating panel in the operator's bottom-right corner, drawing the layer's feed.
/// It frames the subject's windows, so a small app fills the panel instead of floating
/// in an empty desktop; the frame follows them as they move and resize.
@MainActor
final class ActionAgentLayerPiP {
    private static let width: CGFloat = 380
    private static let margin: CGFloat = 16
    private static let cropPadding: CGFloat = 12

    private let feed: ActionAgentLayerFeed
    private let logger: DebugLogger
    private var panel: NSPanel?
    private var viewer: ActionAgentLayerViewerView?
    private var crop: CGRect = .zero
    private var cropTimer: Timer?
    /// Called once the operator's close button has taken the viewer down.
    var onDismiss: (() -> Void)?
    private var presented = false

    init(feed: ActionAgentLayerFeed, logger: DebugLogger) {
        self.feed = feed
        self.logger = logger
    }

    private var fullCrop: CGRect { CGRect(origin: .zero, size: feed.displayBounds.size) }

    func start(expectsWindows: Bool) async {
        crop = feed.windowsRect(padding: Self.cropPadding) ?? fullCrop
        // Windows the layer just moved reach the window list a beat later; launching on
        // the full display would snap to the window half a second in.
        if expectsWindows {
            for _ in 0..<15 where crop == fullCrop {
                try? await Task.sleep(for: .milliseconds(40))
                crop = feed.windowsRect(padding: Self.cropPadding) ?? fullCrop
            }
        }
        showPanel()
        guard let viewer else { return }
        // Launch on a frame, so the viewer grows in already showing the layer rather
        // than as an empty box. A feed that never delivers still gets a viewer.
        feed.attach(viewer.videoLayer) { [weak self] in
            // Enqueued isn't drawn yet; give the frame a couple of refreshes to land.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.present() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.present() }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.followWindows() }
        }
        cropTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        logger.log("agent-layer pip: up crop=\(crop)")
    }

    func stop(animated: Bool) {
        cropTimer?.invalidate()
        cropTimer = nil
        feed.detach()
        guard let panel else { return }
        self.panel = nil
        guard animated, !Self.reduceMotion else {
            panel.orderOut(nil)
            return
        }
        // Settle back toward the corner it came from, fading as it goes.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(Self.tucked(panel.frame, scale: 0.94), display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            // Idle overlays leave the window list, not just go transparent.
            panel.orderOut(nil)
        })
    }

    private func dismiss() {
        stop(animated: true)
        onDismiss?()
    }

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// `frame` shrunk toward its bottom-right corner, nudged down: where the viewer
    /// launches from and settles back to.
    private static func tucked(_ frame: CGRect, scale: CGFloat) -> CGRect {
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        return CGRect(x: frame.maxX - size.width, y: frame.minY - 10, width: size.width, height: size.height)
    }

    // MARK: Panel

    private func showPanel() {
        let displayID = feed.displayID
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

        let content = ActionAgentLayerViewerView(frame: CGRect(origin: .zero, size: frame.size), displaySize: feed.displayBounds.size)
        content.crop = crop
        let close = ActionAgentLayerCloseButton(frame: CGRect(x: frame.width - 28, y: frame.height - 28, width: 20, height: 20))
        close.autoresizingMask = [.minXMargin, .minYMargin]
        close.onPress = { [weak self] in self?.dismiss() }
        content.addSubview(close)
        content.addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: close,
                userInfo: [ActionAgentLayerCloseButton.viewerKey: true]
            )
        )
        panel.contentView = content
        self.panel = panel
        self.viewer = content
    }

    /// Launch: grow out of the screen corner and fade up, expo out. Runs once.
    private func present() {
        guard !presented, let panel else { return }
        presented = true
        let frame = panel.frame
        guard !Self.reduceMotion else {
            panel.orderFrontRegardless()
            return
        }
        panel.alphaValue = 0
        panel.setFrame(Self.tucked(frame, scale: 0.82), display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.42
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    private func screenNumber(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func followWindows() {
        let next = feed.windowsRect(padding: Self.cropPadding) ?? fullCrop
        guard abs(next.minX - crop.minX) > 4 || abs(next.minY - crop.minY) > 4
            || abs(next.width - crop.width) > 4 || abs(next.height - crop.height) > 4 else { return }
        crop = next
        viewer?.crop = next
        guard let panel else { return }
        // Keep the panel's bottom edge put; width stays, height follows the crop.
        let frame = panel.frame
        let height = (frame.width * next.height / max(next.width, 1)).rounded()
        panel.contentAspectRatio = CGSize(width: frame.width, height: height)
        let resized = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height)
        if Self.reduceMotion || !presented {
            panel.setFrame(resized, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                panel.animator().setFrame(resized, display: true)
            }
        }
    }
}

/// The viewer's content: the whole-layer feed, positioned so `crop` fills the bounds.
/// Cropping is layout, not a stream reconfiguration, so the frame can follow the
/// windows without the stream restarting.
private final class ActionAgentLayerViewerView: NSView {
    let videoLayer = AVSampleBufferDisplayLayer()
    private let displaySize: CGSize
    var crop: CGRect = .zero { didSet { needsLayout = true } }

    init(frame: NSRect, displaySize: CGSize) {
        self.displaySize = displaySize
        super.init(frame: frame)
        wantsLayer = true
        guard let root = layer else { return }
        root.cornerRadius = 10
        root.cornerCurve = .continuous
        root.masksToBounds = true
        root.backgroundColor = NSColor(srgbRed: 0x10 / 255, green: 0x15 / 255, blue: 0x18 / 255, alpha: 1).cgColor
        root.borderWidth = 1
        root.borderColor = NSColor(white: 0.95, alpha: 0.16).cgColor

        videoLayer.videoGravity = .resize
        root.addSublayer(videoLayer)

        // The one coral: this surface is live. Above the video.
        let dot = CALayer()
        dot.frame = CGRect(x: 10, y: root.bounds.height - 16, width: 6, height: 6)
        dot.autoresizingMask = [.layerMinYMargin]
        dot.cornerRadius = 3
        dot.zPosition = 1
        dot.backgroundColor = NSColor(srgbRed: 0xEF / 255, green: 0x6A / 255, blue: 0x47 / 255, alpha: 1).cgColor
        root.addSublayer(dot)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        guard crop.width > 0, crop.height > 0 else { return }
        // Scale so the crop's width fills ours; lay the whole display out from its top-left,
        // shifted so the crop's top-left lands on ours. Layer space runs bottom-up.
        let k = bounds.width / crop.width
        let height = displaySize.height * k
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = CGRect(
            x: -crop.minX * k,
            y: bounds.height + crop.minY * k - height,
            width: displaySize.width * k,
            height: height
        )
        CATransaction.commit()
    }
}

/// Keeps the feed's latest frame and hands frames to an attached display layer, on
/// the capture queue.
private final class ActionAgentLayerStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.arach.action.agent-layer.feed")
    private let lock = NSLock()
    private var layer: AVSampleBufferDisplayLayer?
    private var onAttachedFrame: (() -> Void)?
    private var latestBuffer: CMSampleBuffer?
    private var latestAt = Date.distantPast

    func attach(_ layer: AVSampleBufferDisplayLayer, onFrame: @escaping () -> Void) {
        queue.async { [self] in
            lock.withLock {
                self.layer = layer
                self.onAttachedFrame = onFrame
            }
            // A feed that's been running has a frame already; show it now.
            if let latest = lock.withLock({ latestBuffer }) { deliver(latest) }
        }
    }

    func detach() {
        lock.withLock {
            layer = nil
            onAttachedFrame = nil
        }
    }

    func latest() -> (CVPixelBuffer, Date)? {
        lock.withLock {
            guard let buffer = latestBuffer, let pixels = CMSampleBufferGetImageBuffer(buffer) else { return nil }
            return (pixels, latestAt)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, isComplete(sampleBuffer) else { return }
        lock.withLock {
            latestBuffer = sampleBuffer
            latestAt = Date()
        }
        deliver(sampleBuffer)
    }

    private func deliver(_ sampleBuffer: CMSampleBuffer) {
        let (layer, onFrame) = lock.withLock { () -> (AVSampleBufferDisplayLayer?, (() -> Void)?) in
            let pending = onAttachedFrame
            onAttachedFrame = nil
            return (self.layer, pending)
        }
        guard let layer else { return }
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
        onFrame?()
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

/// The viewer's close control: a 20pt ink disc with a thin ×, shown while the pointer
/// is over the viewer. It owns the viewer's tracking area so it can fade itself in.
private final class ActionAgentLayerCloseButton: NSView {
    var onPress: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        alphaValue = 0
        setAccessibilityRole(.button)
        setAccessibilityLabel("Hide viewer")
    }

    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Marks the viewer-wide tracking area, as opposed to the button's own.
    static let viewerKey = "viewer"

    override func mouseEntered(with event: NSEvent) {
        if isViewerArea(event) { fade(to: 1) } else { hovering = true }
    }

    override func mouseExited(with event: NSEvent) {
        if isViewerArea(event) { fade(to: 0) } else { hovering = false }
    }

    private func isViewerArea(_ event: NSEvent) -> Bool {
        event.trackingArea?.userInfo?[Self.viewerKey] as? Bool == true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self && $0.userInfo == nil }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let disc = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        NSColor(srgbRed: 0x10 / 255, green: 0x15 / 255, blue: 0x18 / 255, alpha: hovering ? 0.92 : 0.72).setFill()
        disc.fill()
        NSColor(white: 0.95, alpha: 0.16).setStroke()
        disc.lineWidth = 1
        disc.stroke()

        let inset: CGFloat = 7
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: inset, y: inset))
        cross.line(to: CGPoint(x: bounds.width - inset, y: bounds.height - inset))
        cross.move(to: CGPoint(x: inset, y: bounds.height - inset))
        cross.line(to: CGPoint(x: bounds.width - inset, y: inset))
        cross.lineWidth = 1.25
        cross.lineCapStyle = .round
        NSColor(white: 0.95, alpha: hovering ? 1 : 0.8).setStroke()
        cross.stroke()
    }

    private func fade(to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            animator().alphaValue = alpha
        }
    }
}
