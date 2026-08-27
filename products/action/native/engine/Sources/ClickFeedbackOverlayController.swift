import AppKit
import ActionCore
import Foundation

/// One pulse in flight. `startedAtUptime` comes from the recorded event, not from the moment the
/// overlay noticed the line, so a slow read shortens the pulse rather than shifting it in time.
private struct ClickPulse {
    let correlationId: String
    /// CoreGraphics global point, exactly as recorded.
    let point: CGPoint
    let startedAtUptime: Double
}

/// Draws a short pulse at each Action-driven primary press.
///
/// Deliberately minimal: no synthetic cursor, no motion trail, no supervision label, and no call
/// into `NSCursor` — the operator keeps the ordinary macOS pointer. The only input is the pointer
/// event log the click itself wrote, so what is drawn and what is recorded cannot disagree.
@MainActor
final class ClickFeedbackOverlayController: NSObject {
    private let eventLogPath: String
    private let stopFile: String
    private let writer: ResponseWriter
    private let logger: DebugLogger

    private var overlayWindow: NSWindow?
    private var overlayView: ClickFeedbackOverlayView?
    private var pollTimer: Timer?
    private var displayTimer: Timer?

    private var log: ActionPointerEventLog?
    private var readOffset: UInt64 = 0
    private var pending = Data()
    private var pulses: [ClickPulse] = []
    private var seenCorrelationIDs = Set<String>()

    private var pulseDuration: TimeInterval = 0.32
    private var pulseRadius: CGFloat = 34

    /// How long the overlay keeps running after the log stops growing, when no stop file arrives.
    private static let idleExpirySeconds: TimeInterval = 900

    init(
        eventLogPath: String,
        stopFile: String,
        replyFile: String?,
        debugLogPath: String?
    ) {
        self.eventLogPath = eventLogPath
        self.stopFile = stopFile
        self.writer = ResponseWriter(replyFile: replyFile)
        self.logger = DebugLogger(path: debugLogPath)
    }

    func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // The recording writes the header before starting the overlay, but a detached spawn can
        // still win the race, so keep trying rather than exiting.
        openLogIfNeeded()

        try writer.write(
            ActionHostResponse(
                status: "click-feedback-overlay-running",
                outputPath: eventLogPath,
                detail: String(ProcessInfo.processInfo.processIdentifier)
            )
        )
        logger.log(
            "click-feedback: started pid=\(ProcessInfo.processInfo.processIdentifier) log=\(eventLogPath)"
        )

        ensureWindow()
        startPolling()
        startDisplayLoop()
        app.run()
    }

    private func openLogIfNeeded() {
        guard log == nil else {
            return
        }
        guard let opened = (try? ActionPointerEventLog.open(path: eventLogPath)) ?? nil else {
            return
        }
        log = opened
        pulseDuration = max(0.08, opened.header.feedback.durationMs / 1000.0)
        pulseRadius = max(8, CGFloat(opened.header.feedback.radius))
        // Start after the header line; everything past it is an event this overlay should show.
        readOffset = 0
        pending = Data()
        drainNewLines()
    }

    private func startPolling() {
        // 30 Hz keeps the pulse within a frame of the press without spinning on the file.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startDisplayLoop() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.renderFrame()
            }
        }
        displayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        if FileManager.default.fileExists(atPath: stopFile) {
            shutdown(reason: "stop-file")
            return
        }
        openLogIfNeeded()
        drainNewLines()
    }

    /// Reads whatever the click processes appended since the last poll. Partial trailing lines are
    /// held back until their newline arrives, so a line that lands mid-read is never half-decoded.
    private func drainNewLines() {
        guard let handle = FileHandle(forReadingAtPath: eventLogPath) else {
            return
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: readOffset)
        } catch {
            return
        }
        guard let chunk = try? handle.readToEnd(), !chunk.isEmpty else {
            return
        }
        readOffset += UInt64(chunk.count)
        pending.append(chunk)

        guard let lastNewline = pending.lastIndex(of: 0x0a) else {
            return
        }
        let complete = pending[pending.startIndex...lastNewline]
        pending = Data(pending[pending.index(after: lastNewline)...])

        guard let text = String(data: Data(complete), encoding: .utf8) else {
            return
        }
        for event in ActionPointerEventLog.decodeEvents(from: text) {
            enqueue(event)
        }
    }

    private func enqueue(_ event: ActionPointerEvent) {
        // A primary press is the beat worth showing. Releases and drag motion would read as a
        // trail, which is exactly what this overlay is not.
        guard event.phase == .down, event.button == .left else {
            return
        }
        guard seenCorrelationIDs.insert(event.correlationId).inserted else {
            return
        }
        pulses.append(
            ClickPulse(
                correlationId: event.correlationId,
                point: event.point,
                startedAtUptime: event.uptime
            )
        )
        logger.log(
            "click-feedback: pulse id=\(event.correlationId) at=\(event.at) elapsedMs=\(event.recordingElapsedMs)"
        )
    }

    /// Full desktop bounds in AppKit coordinates. One window across every screen keeps a pulse
    /// correct when the click lands on a secondary display.
    private func desktopFrame() -> CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    private func ensureWindow() {
        let frame = desktopFrame()
        guard !frame.isNull, !frame.isEmpty else {
            return
        }
        if let existing = overlayWindow, existing.frame == frame {
            return
        }

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.setFrame(frame, display: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Clicks must reach the app underneath: this window is decoration over a real gesture.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false

        let view = ClickFeedbackOverlayView(frame: CGRect(origin: .zero, size: frame.size))
        panel.contentView = view
        panel.orderFrontRegardless()

        overlayWindow?.orderOut(nil)
        overlayWindow = panel
        overlayView = view
    }

    /// CoreGraphics global space has its origin at the top-left of the primary display; AppKit
    /// measures up from its bottom-left. Recorded points are CG, so they are flipped once here.
    private func appKitPoint(fromCoreGraphics point: CGPoint) -> CGPoint {
        guard let primary = NSScreen.screens.first else {
            return point
        }
        return CGPoint(x: point.x, y: primary.frame.maxY - point.y)
    }

    private func renderFrame() {
        ensureWindow()
        guard let view = overlayView, let window = overlayWindow else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        pulses.removeAll { now - $0.startedAtUptime > pulseDuration }
        if pulses.count > 32 {
            pulses.removeFirst(pulses.count - 32)
        }

        let origin = window.frame.origin
        let models: [ClickPulseModel] = pulses.compactMap { pulse in
            let progress = (now - pulse.startedAtUptime) / pulseDuration
            guard progress >= 0, progress <= 1 else {
                return nil
            }
            let appKit = appKitPoint(fromCoreGraphics: pulse.point)
            return ClickPulseModel(
                point: CGPoint(x: appKit.x - origin.x, y: appKit.y - origin.y),
                progress: CGFloat(progress),
                maxRadius: pulseRadius
            )
        }

        if models.isEmpty && view.pulses.isEmpty {
            return
        }
        view.pulses = models
        view.needsDisplay = true
    }

    private func shutdown(reason: String) {
        logger.log("click-feedback: shutdown pid=\(ProcessInfo.processInfo.processIdentifier) reason=\(reason)")
        pollTimer?.invalidate()
        displayTimer?.invalidate()
        overlayWindow?.orderOut(nil)
        try? FileManager.default.removeItem(atPath: stopFile)
        NSApplication.shared.terminate(nil)
    }
}

struct ClickPulseModel {
    let point: CGPoint
    let progress: CGFloat
    let maxRadius: CGFloat
}

final class ClickFeedbackOverlayView: NSView {
    var pulses: [ClickPulseModel] = []

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for pulse in pulses {
            draw(pulse)
        }
    }

    /// A single ring that expands and fades. Two strokes — a dark halo under a light core — keep
    /// it legible on both a white document and a dark terminal without introducing a brand colour
    /// that would read as a synthetic cursor.
    private func draw(_ pulse: ClickPulseModel) {
        let eased = 1 - pow(1 - pulse.progress, 3)
        let radius = 6 + (pulse.maxRadius - 6) * eased
        let alpha = max(0, 1 - pulse.progress) * 0.9

        let rect = CGRect(
            x: pulse.point.x - radius,
            y: pulse.point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let ring = NSBezierPath(ovalIn: rect)

        ring.lineWidth = 3.0
        NSColor(calibratedWhite: 0, alpha: alpha * 0.38).setStroke()
        ring.stroke()

        ring.lineWidth = 1.6
        NSColor(calibratedWhite: 1, alpha: alpha).setStroke()
        ring.stroke()

        // A brief contact dot marks the exact hotspot for the first third of the pulse.
        guard pulse.progress < 0.34 else {
            return
        }
        let dotAlpha = alpha * (1 - pulse.progress / 0.34)
        let dot = NSBezierPath(
            ovalIn: CGRect(x: pulse.point.x - 2.5, y: pulse.point.y - 2.5, width: 5, height: 5)
        )
        NSColor(calibratedWhite: 1, alpha: dotAlpha).setFill()
        dot.fill()
        NSColor(calibratedWhite: 0, alpha: dotAlpha * 0.45).setStroke()
        dot.lineWidth = 0.8
        dot.stroke()
    }
}
