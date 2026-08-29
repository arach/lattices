import AppKit
import Foundation

/// Long-lived synthetic agent cursor for drive leases.
///
/// Stays up until the stop file appears. A state JSON steers position and click
/// flashes. Motion uses a short wind-up, a fast Trek-style warp, then ease-in
/// lock — with a short trail while traveling and a bicycle-balance sway parked.
struct AgentCursorState: Codable, Equatable {
    var x: Double?
    var y: Double?
    /// `appkit` (legacy/default) or `quartz`. Quartz input is converted once at the overlay edge.
    var coordinateSpace: String?
    var agent: String?
    var label: String?
    /// `idle` | `click` | `type` | `key` | `countdown`
    var phase: String?
    /// Full string for type cues; revealed over time with key sounds.
    var typingText: String?
    /// Single key / chord label for press-key cues.
    var keyLabel: String?
    /// Seconds remaining in a pre-focus warning (3, 2, 1).
    var countdown: Int?
    /// Unique per act so repeated clicks/types re-trigger sound + visuals.
    var cueId: String?
    /// Optional region the cursor is presenting — same coordinate space as `x`/`y`.
    var highlight: AgentCursorHighlight?
    /// Renewable deadline after which this detached overlay releases itself.
    var expiresAt: String?
    var updatedAt: String?
}

struct AgentCursorHighlight: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

private struct TrailSample {
    var point: CGPoint
    var at: TimeInterval
}

@MainActor
final class AgentCursorOverlayController: NSObject {
    private let stateFile: String
    private let stopFile: String
    private let leaseStopFile: String?
    private let writer: ResponseWriter
    private let logger: DebugLogger
    private var overlayWindow: NSWindow?
    private var overlayView: AgentCursorOverlayView?
    private var pollTimer: Timer?
    private var displayTimer: Timer?
    private var lastStateData: Data?
    private var state = AgentCursorState(phase: "idle")

    private var targetPoint: CGPoint?
    private var travelPoint: CGPoint?
    private var moveOrigin: CGPoint?
    private var moveStartedAt: TimeInterval?
    private var moveDuration: TimeInterval = 0.28
    private var isTraveling = false

    private var clickStartedAt: Date?
    private var typingStartedAt: Date?
    private var typingFullText: String = ""
    private var typingRevealCount: Int = 0
    private var nextTypingSoundAt: TimeInterval = 0
    private var lastCueId: String?
    private var lastCountdownValue: Int?
    private let soundPlayer = DemoCueSoundPlayer()
    private let startedAt = Date()
    private var trail: [TrailSample] = []
    private var lastFrameAt: TimeInterval = 0
    private static let idleExpirySeconds: TimeInterval = 90
    private static let iso8601Format = Date.ISO8601FormatStyle()
    private static let fractionalISO8601Format = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// Rest pose of a real pointer: from the lower-right, tip toward upper-left.
    /// Steeper than vertical so it never reads as a rocket.
    private let brandLean: CGFloat = -38.0 * .pi / 180.0
    /// Extra motion on top of the rest pose — idle breath, arrival settle, click strike.
    private var leanAngle: CGFloat = 0
    private var leanVelocity: CGFloat = 0
    private var pendingClick = false
    private var settleUntil: TimeInterval = 0

    init(
        stateFile: String,
        stopFile: String,
        leaseStopFile: String?,
        replyFile: String?,
        debugLogPath: String?
    ) {
        self.stateFile = stateFile
        self.stopFile = stopFile
        self.leaseStopFile = leaseStopFile
        self.writer = ResponseWriter(replyFile: replyFile)
        self.logger = DebugLogger(path: debugLogPath)
    }

    func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: stateFile).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: stateFile) {
            let seed = AgentCursorState(
                x: nil,
                y: nil,
                agent: "Agent",
                label: "driving",
                phase: "idle",
                expiresAt: Date().addingTimeInterval(Self.idleExpirySeconds).formatted(Self.fractionalISO8601Format),
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            try JSONEncoder().encode(seed).write(to: URL(fileURLWithPath: stateFile))
        }

        try writer.write(
            ActionHostResponse(
                status: "agent-cursor-overlay-running",
                outputPath: nil,
                detail: String(ProcessInfo.processInfo.processIdentifier)
            )
        )
        logger.log(
            "agent-cursor: started pid=\(ProcessInfo.processInfo.processIdentifier) state=\(stateFile) leaseStop=\(leaseStopFile ?? "none")"
        )

        reloadState(force: true)
        ensureWindow()
        startPolling()
        startDisplayLoop()
        app.run()
    }

    private func startPolling() {
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
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
            shutdown(reason: "cursor-stop-file")
            return
        }
        if let leaseStopFile,
           FileManager.default.fileExists(atPath: leaseStopFile) {
            shutdown(reason: "lease-stop-file")
            return
        }
        reloadState(force: false)
        if stateIsExpired(at: Date()) {
            shutdown(reason: "idle-expiry")
        }
    }

    private func reloadState(force: Bool) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)) else {
            return
        }
        if !force, data == lastStateData {
            return
        }
        guard let decoded = try? JSONDecoder().decode(AgentCursorState.self, from: data) else {
            return
        }
        lastStateData = data
        let previous = state
        state = decoded

        let nextTarget = resolvePoint(from: decoded)
        let previousTarget = targetPoint
        targetPoint = nextTarget
        if travelPoint == nil {
            travelPoint = nextTarget
            moveOrigin = nextTarget
            isTraveling = false
        } else if previousTarget == nil
            || hypot(nextTarget.x - (previousTarget?.x ?? nextTarget.x),
                     nextTarget.y - (previousTarget?.y ?? nextTarget.y)) > 1.5 {
            beginMove(to: nextTarget)
        }

        handleCueTransition(from: previous, to: decoded)
    }

    private func handleCueTransition(from previous: AgentCursorState, to decoded: AgentCursorState) {
        let phase = (decoded.phase ?? "idle").lowercased()
        let cueChanged = decoded.cueId != nil && decoded.cueId != lastCueId
        let phaseChanged = (previous.phase ?? "").lowercased() != phase
            || previous.typingText != decoded.typingText
            || previous.keyLabel != decoded.keyLabel
            || cueChanged

        guard phaseChanged || cueChanged else {
            return
        }
        if let cueId = decoded.cueId {
            lastCueId = cueId
        }

        switch phase {
        case "countdown":
            let value = decoded.countdown ?? 0
            if value != lastCountdownValue, value > 0 {
                lastCountdownValue = value
                // Soft tick each second of the pre-focus warning.
                soundPlayer.playClick()
            }
            clickStartedAt = nil
            typingStartedAt = nil
        case "click":
            typingStartedAt = nil
            typingFullText = ""
            typingRevealCount = 0
            lastCountdownValue = nil
            if isTraveling {
                pendingClick = true
            } else {
                fireClickCue()
            }
        case "type":
            let text = decoded.typingText ?? decoded.label ?? ""
            typingFullText = text
            typingRevealCount = 0
            typingStartedAt = Date()
            nextTypingSoundAt = 0
            clickStartedAt = nil
            lastCountdownValue = nil
            if !text.isEmpty {
                // First keytick immediately so type cues never feel silent.
                soundPlayer.playTyping()
                typingRevealCount = min(1, text.count)
                nextTypingSoundAt = 0.07
            }
        case "key":
            clickStartedAt = Date()
            typingStartedAt = Date()
            typingFullText = decoded.keyLabel ?? decoded.label ?? "key"
            typingRevealCount = typingFullText.count
            lastCountdownValue = nil
            soundPlayer.playClick()
        default:
            lastCountdownValue = nil
            break
        }
    }

    private func fireClickCue() {
        clickStartedAt = Date()
        settleUntil = Date().timeIntervalSince(startedAt) + 0.28
        soundPlayer.playClick()
    }

    private func beginMove(to target: CGPoint) {
        let from = travelPoint ?? target
        moveOrigin = from
        targetPoint = target
        let distance = hypot(target.x - from.x, target.y - from.y)
        // Fast warp: short overall, still room for wind-up + lock.
        // Peak feels like a Trek jump — most of the distance in the middle third.
        moveDuration = min(0.38, max(0.11, Double(distance) / 2400.0))
        moveStartedAt = Date().timeIntervalSince(startedAt)
        isTraveling = distance > 0.8
        if isTraveling {
            trail.removeAll(keepingCapacity: true)
            trail.append(TrailSample(point: from, at: moveStartedAt ?? 0))
        }
    }

    private func resolvePoint(from state: AgentCursorState) -> CGPoint {
        if let x = state.x, let y = state.y, x.isFinite, y.isFinite {
            if state.coordinateSpace?.lowercased() == "quartz" {
                let mainDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
                return CGPoint(x: x, y: mainDisplayHeight - y)
            }
            return CGPoint(x: x, y: y)
        }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(
            x: frame.origin.x + frame.width * 0.72,
            y: frame.origin.y + frame.height * 0.62
        )
    }

    private func ensureWindow() {
        let point = travelPoint ?? resolvePoint(from: state)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            return
        }

        if let existing = overlayWindow, existing.screen == screen {
            return
        }

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: screen.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.setFrame(screen.frame, display: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false

        let view = AgentCursorOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        panel.contentView = view
        panel.orderFrontRegardless()

        overlayWindow?.orderOut(nil)
        overlayWindow = panel
        overlayView = view
    }

    /// Trek-style ease: short wind-up, long fast warp, short lock-in.
    /// Most of the path is covered in the middle — not a slow cubic all the way.
    private static func trekEase(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        // 0–18% wind-up covers ~10% of distance
        if x < 0.18 {
            let u = x / 0.18
            return 0.10 * (u * u)
        }
        // 18–80% warp covers ~80% of distance — high, near-linear speed
        if x < 0.80 {
            let u = (x - 0.18) / 0.62
            return 0.10 + 0.80 * u
        }
        // 80–100% lock-in covers last ~10% with ease-out
        let u = (x - 0.80) / 0.20
        let easeOut = 1 - (1 - u) * (1 - u) * (1 - u)
        return 0.90 + 0.10 * easeOut
    }

    private func renderFrame() {
        ensureWindow()
        guard let screen = overlayWindow?.screen ?? NSScreen.main else {
            return
        }

        let now = Date().timeIntervalSince(startedAt)
        let dt = lastFrameAt > 0 ? min(0.05, now - lastFrameAt) : 1.0 / 60.0
        lastFrameAt = now

        var speed: CGFloat = 0
        if let target = targetPoint, let origin = moveOrigin, let t0 = moveStartedAt, isTraveling {
            let u = (now - t0) / max(0.001, moveDuration)
            if u >= 1 {
                travelPoint = target
                isTraveling = false
                speed = 0
                settleUntil = now + 0.32
                if pendingClick {
                    pendingClick = false
                    fireClickCue()
                }
            } else {
                let eased = Self.trekEase(u)
                let prevU = max(0, (now - dt - t0) / max(0.001, moveDuration))
                let prevEased = Self.trekEase(prevU)
                let x = origin.x + (target.x - origin.x) * eased
                let y = origin.y + (target.y - origin.y) * eased
                let prev = CGPoint(
                    x: origin.x + (target.x - origin.x) * prevEased,
                    y: origin.y + (target.y - origin.y) * prevEased
                )
                travelPoint = CGPoint(x: x, y: y)
                speed = CGFloat(hypot(x - prev.x, y - prev.y) / max(dt, 0.001))
                trail.append(TrailSample(point: CGPoint(x: x, y: y), at: now))
            }
        } else if let target = targetPoint {
            travelPoint = target
        }

        // Slightly longer trail so the warp streak reads at higher speed.
        let trailHorizon = now - 0.14
        trail.removeAll { $0.at < trailHorizon }

        guard var global = travelPoint else {
            return
        }

        let travelDamping: CGFloat = isTraveling ? 0.18 : 1.0
        stepBalance(dt: dt, amplitude: travelDamping)

        // Brand lean is the resting pose; bicycle micro-sway rides on top.
        let lean = brandLean + leanAngle
        let balanceOffset = CGPoint(
            x: sin(lean) * 2.6,
            y: (1 - cos(lean)) * 1.0
        )
        global.x += balanceOffset.x
        global.y += balanceOffset.y

        let local = CGPoint(
            x: global.x - screen.frame.origin.x,
            y: global.y - screen.frame.origin.y
        )

        let localTrail = trail.map { sample -> CGPoint in
            CGPoint(
                x: sample.point.x - screen.frame.origin.x,
                y: sample.point.y - screen.frame.origin.y
            )
        }

        var clickProgress: CGFloat?
        if let clickStartedAt {
            let elapsed = Date().timeIntervalSince(clickStartedAt)
            if elapsed < 0.34 {
                clickProgress = CGFloat(elapsed / 0.34)
            } else if (state.phase ?? "").lowercased() != "key" {
                self.clickStartedAt = nil
            }
        }

        // Reveal typing text + key ticks over ~55ms per character (capped).
        var typingVisible: String?
        var showCaret = false
        if let typingStartedAt, !typingFullText.isEmpty {
            let elapsed = Date().timeIntervalSince(typingStartedAt)
            let perChar = 0.055
            let targetCount = min(typingFullText.count, max(1, Int(elapsed / perChar) + 1))
            while typingRevealCount < targetCount {
                typingRevealCount += 1
                if Date().timeIntervalSince(startedAt) >= nextTypingSoundAt {
                    soundPlayer.playTyping()
                    nextTypingSoundAt = Date().timeIntervalSince(startedAt) + 0.048
                }
            }
            let end = typingFullText.index(typingFullText.startIndex, offsetBy: typingRevealCount)
            typingVisible = String(typingFullText[..<end])
            showCaret = typingRevealCount < typingFullText.count
                || elapsed < Double(typingFullText.count) * perChar + 0.35
            if elapsed > Double(typingFullText.count) * perChar + 1.2 {
                // Keep final text on badge briefly, then clear local typing anim.
                if elapsed > Double(typingFullText.count) * perChar + 2.4 {
                    self.typingStartedAt = nil
                }
            }
        }

        let phase = (state.phase ?? "idle").lowercased()
        let badgeLabel: String? = {
            if phase == "countdown", let n = state.countdown, n > 0 {
                return "pointer in \(n)…"
            }
            if phase == "type", let typingVisible, !typingVisible.isEmpty {
                return typingVisible
            }
            if phase == "key" {
                return state.keyLabel ?? state.label
            }
            if phase == "click" {
                return state.label ?? "click"
            }
            return state.label
        }()

        var localHighlight: CGRect?
        if let box = state.highlight, box.width > 4, box.height > 4 {
            localHighlight = CGRect(
                x: box.x - screen.frame.origin.x,
                y: box.y - screen.frame.origin.y,
                width: box.width,
                height: box.height
            )
        }

        overlayView?.model = AgentCursorRenderModel(
            point: local,
            trail: localTrail,
            agent: state.agent ?? "Agent",
            label: badgeLabel,
            clickProgress: clickProgress,
            leanAngle: lean,
            speed: speed,
            isTraveling: isTraveling,
            typingVisible: typingVisible,
            showCaret: showCaret,
            isKeyCue: phase == "key",
            countdown: phase == "countdown" ? state.countdown : nil,
            highlight: localHighlight
        )
        overlayView?.needsDisplay = true
    }

    private func stepBalance(dt: TimeInterval, amplitude: CGFloat) {
        let now = Date().timeIntervalSince(startedAt)
        let t = now
        // Idle breath plus a quicker fidget — reads as attention, not a screensaver.
        let noise = sin(t * 1.15) * 0.72 + sin(t * 2.4 + 0.6) * 0.38 + sin(t * 4.1 + 1.1) * 0.16
        var drive = CGFloat(noise) * 1.25 * amplitude
        if now < settleUntil {
            let remaining = settleUntil - now
            drive += sin((0.32 - remaining) * 18) * 0.22 * CGFloat(remaining / 0.32)
        }
        let spring: CGFloat = 16.0
        let damping: CGFloat = 4.8
        let accel = -spring * leanAngle - damping * leanVelocity + drive
        leanVelocity += accel * CGFloat(dt)
        leanAngle += leanVelocity * CGFloat(dt)
        leanAngle = min(0.14, max(-0.14, leanAngle))
    }

    private func stateIsExpired(at now: Date) -> Bool {
        if let expiresAt = state.expiresAt,
           let deadline = Self.parseISO8601Date(expiresAt) {
            return deadline <= now
        }
        if let updatedAt = state.updatedAt,
           let lastUpdate = Self.parseISO8601Date(updatedAt) {
            return now.timeIntervalSince(lastUpdate) >= Self.idleExpirySeconds
        }
        return now.timeIntervalSince(startedAt) >= Self.idleExpirySeconds
    }

    private static func parseISO8601Date(_ raw: String) -> Date? {
        (try? Date(raw, strategy: fractionalISO8601Format))
            ?? (try? Date(raw, strategy: iso8601Format))
    }

    private func shutdown(reason: String) {
        logger.log("agent-cursor: shutdown pid=\(ProcessInfo.processInfo.processIdentifier) reason=\(reason)")
        pollTimer?.invalidate()
        displayTimer?.invalidate()
        overlayWindow?.orderOut(nil)
        try? FileManager.default.removeItem(atPath: stateFile)
        try? FileManager.default.removeItem(atPath: stopFile)
        NSApplication.shared.terminate(nil)
    }
}

struct AgentCursorRenderModel {
    var point: CGPoint
    var trail: [CGPoint]
    var agent: String
    var label: String?
    var clickProgress: CGFloat?
    var leanAngle: CGFloat
    var speed: CGFloat
    var isTraveling: Bool
    var typingVisible: String?
    var showCaret: Bool
    var isKeyCue: Bool
    var countdown: Int?
    var highlight: CGRect?
}

final class AgentCursorOverlayView: NSView {
    // Brand tokens aligned with StageHUDTheme (coral / paper / canvas).
    private static let brandCoral = NSColor(calibratedRed: 0.937, green: 0.416, blue: 0.278, alpha: 1)
    private static let brandCoralHot = NSColor(calibratedRed: 1.0, green: 0.49, blue: 0.32, alpha: 1)
    private static let brandPaper = NSColor(calibratedRed: 0.953, green: 0.922, blue: 0.867, alpha: 1)
    private static let brandCanvas = NSColor(calibratedRed: 0.055, green: 0.071, blue: 0.074, alpha: 0.88)

    /// Tip is the hotspot; dimensions stay close to the standard macOS pointer.
    private static let triangleHeight: CGFloat = 19

    var model: AgentCursorRenderModel?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let model else {
            return
        }

        drawTrail(model.trail, head: model.point, speed: model.speed)
        if let highlight = model.highlight {
            drawHighlight(highlight)
        }
        if let countdown = model.countdown, countdown > 0 {
            drawCountdown(at: model.point, value: countdown, lean: model.leanAngle)
        }
        if let clickProgress = model.clickProgress {
            drawClickRing(at: model.point, progress: clickProgress)
        }
        drawTriangle(at: model.point, lean: model.leanAngle)
        if let typing = model.typingVisible, !typing.isEmpty, !model.isKeyCue {
            drawTypingCaption(near: model.point, text: typing, showCaret: model.showCaret, lean: model.leanAngle)
        }
        if model.isKeyCue, let key = model.label, !key.isEmpty {
            drawKeyCap(near: model.point, key: key, lean: model.leanAngle)
        }
        drawBadge(near: model.point, agent: model.agent, label: model.label, lean: model.leanAngle)
    }

    private func drawCountdown(at point: CGPoint, value: Int, lean: CGFloat) {
        // Amber warning halo — attention is about to take the real pointer.
        let pulse = 0.55 + 0.45 * abs(sin(Date().timeIntervalSince1970 * 4.0))
        let radius = CGFloat(28 + 6 * pulse)
        let halo = NSBezierPath(
            ovalIn: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        NSColor(calibratedRed: 0.894, green: 0.725, blue: 0.412, alpha: 0.14 + 0.10 * pulse).setFill()
        halo.fill()
        NSColor(calibratedRed: 0.894, green: 0.725, blue: 0.412, alpha: 0.55).setStroke()
        halo.lineWidth = 2.0
        halo.stroke()

        let font = NSFont.systemFont(ofSize: 34, weight: .bold)
        let text = "\(value)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.98, green: 0.90, blue: 0.62, alpha: 0.96),
            .kern: -0.5,
        ]
        let size = text.size(withAttributes: attrs)
        let origin = CGPoint(
            x: point.x - size.width / 2 + lean * 6,
            y: point.y + 22
        )

        let plate = CGRect(
            x: origin.x - 10,
            y: origin.y - 4,
            width: size.width + 20,
            height: size.height + 8
        )
        let platePath = NSBezierPath(roundedRect: plate, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.05, alpha: 0.72).setFill()
        platePath.fill()
        NSColor(calibratedRed: 0.894, green: 0.725, blue: 0.412, alpha: 0.45).setStroke()
        platePath.lineWidth = 1
        platePath.stroke()

        text.draw(at: origin, withAttributes: attrs)

        let captionFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let caption = "taking pointer" as NSString
        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: captionFont,
            .foregroundColor: Self.brandPaper.withAlphaComponent(0.85),
            .kern: 0.6,
        ]
        let capSize = caption.size(withAttributes: captionAttrs)
        caption.draw(
            at: CGPoint(x: plate.midX - capSize.width / 2, y: plate.maxY + 4),
            withAttributes: captionAttrs
        )
    }

    private func drawTypingCaption(near point: CGPoint, text: String, showCaret: Bool, lean: CGFloat) {
        let display = text.count > 42 ? "…" + String(text.suffix(41)) : text
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Self.brandPaper.withAlphaComponent(0.95),
            .kern: 0.15,
        ]
        let caret = showCaret && Int(Date().timeIntervalSince1970 * 2.2) % 2 == 0 ? "▋" : " "
        let line = display + caret
        let size = (line as NSString).size(withAttributes: attrs)
        let padX: CGFloat = 10
        let padY: CGFloat = 7
        let rect = CGRect(
            x: point.x + 18 + lean * 8,
            y: point.y + 10,
            width: size.width + padX * 2,
            height: size.height + padY * 2
        )
        let bubble = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = CGSize(width: 0, height: -2)
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.35)
        shadow.set()
        Self.brandCanvas.setFill()
        bubble.fill()
        NSGraphicsContext.restoreGraphicsState()
        Self.brandPaper.withAlphaComponent(0.14).setStroke()
        bubble.lineWidth = 1
        bubble.stroke()
        (line as NSString).draw(
            at: CGPoint(x: rect.minX + padX, y: rect.minY + padY - 1),
            withAttributes: attrs
        )
    }

    private func drawKeyCap(near point: CGPoint, key: String, lean: CGFloat) {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Self.brandPaper.withAlphaComponent(0.96),
            .kern: 0.4,
        ]
        let size = (key as NSString).size(withAttributes: attrs)
        let padX: CGFloat = 11
        let padY: CGFloat = 7
        let rect = CGRect(
            x: point.x + 18 + lean * 8,
            y: point.y + 10,
            width: max(36, size.width + padX * 2),
            height: size.height + padY * 2
        )
        let cap = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = CGSize(width: 0, height: -2)
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.32)
        shadow.set()
        NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.12, alpha: 0.92).setFill()
        cap.fill()
        NSGraphicsContext.restoreGraphicsState()
        Self.brandCoral.withAlphaComponent(0.55).setStroke()
        cap.lineWidth = 1.1
        cap.stroke()
        let textX = rect.midX - size.width / 2
        (key as NSString).draw(
            at: CGPoint(x: textX, y: rect.minY + padY - 1),
            withAttributes: attrs
        )
    }

    private func drawHighlight(_ rect: CGRect) {
        let inset = rect.insetBy(dx: -3, dy: -3)
        let frame = NSBezierPath(roundedRect: inset, xRadius: 10, yRadius: 10)
        NSColor(calibratedRed: 0.953, green: 0.922, blue: 0.867, alpha: 0.07).setFill()
        frame.fill()
        NSColor(calibratedRed: 0.953, green: 0.922, blue: 0.867, alpha: 0.42).setStroke()
        frame.lineWidth = 1.4
        frame.stroke()

        let inner = NSBezierPath(roundedRect: inset.insetBy(dx: 1.2, dy: 1.2), xRadius: 9, yRadius: 9)
        NSColor(calibratedRed: 0.937, green: 0.416, blue: 0.278, alpha: 0.28).setStroke()
        inner.lineWidth = 1.0
        inner.stroke()
    }

    private func drawTrail(_ points: [CGPoint], head: CGPoint, speed: CGFloat) {
        guard points.count >= 2 else {
            return
        }

        var samples = points
        if let last = samples.last, hypot(last.x - head.x, last.y - head.y) > 0.5 {
            samples.append(head)
        }

        let speedBoost = min(1.0, max(0.35, Double(speed) / 1800.0))
        let count = samples.count
        for index in 0..<(count - 1) {
            let fade = CGFloat(index + 1) / CGFloat(count)
            let alpha = CGFloat((0.06 + 0.40 * fade * fade) * speedBoost)
            let width = CGFloat(0.9 + 2.5 * fade)

            let segment = NSBezierPath()
            segment.move(to: samples[index])
            segment.line(to: samples[index + 1])
            segment.lineCapStyle = .round
            segment.lineJoinStyle = .round

            segment.lineWidth = width + 1.2
            NSColor(calibratedWhite: 0.04, alpha: alpha * 0.30).setStroke()
            segment.stroke()

            segment.lineWidth = width
            NSColor.white.withAlphaComponent(alpha * 0.72).setStroke()
            segment.stroke()
        }
    }

    private func drawClickRing(at point: CGPoint, progress: CGFloat) {
        let ease = 1 - pow(1 - progress, 2.4)
        let radius = CGFloat(7 + 18 * ease)
        let alpha = CGFloat(0.42 * pow(1 - progress, 1.5))
        let path = NSBezierPath(
            ovalIn: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        path.lineWidth = CGFloat(1.7 - 0.8 * progress)
        NSColor.black.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private func drawTriangle(at point: CGPoint, lean: CGFloat) {
        let h = Self.triangleHeight
        let path = NSBezierPath()
        path.move(to: .zero)
        path.line(to: CGPoint(x: 0, y: -h))
        path.line(to: CGPoint(x: 4.8, y: -14.2))
        path.line(to: CGPoint(x: 8.2, y: -20.2))
        path.line(to: CGPoint(x: 11.0, y: -18.5))
        path.line(to: CGPoint(x: 7.6, y: -12.7))
        path.line(to: CGPoint(x: 14.4, y: -11.9))
        path.close()
        path.lineJoinStyle = .round
        path.lineCapStyle = .round

        var transform = AffineTransform(translationByX: point.x, byY: point.y)
        transform.rotate(byRadians: lean)
        path.transform(using: transform)

        NSGraphicsContext.saveGraphicsState()
        let ambient = NSShadow()
        ambient.shadowBlurRadius = 8
        ambient.shadowOffset = CGSize(width: 0, height: -1.5)
        ambient.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.24)
        ambient.set()
        NSColor(calibratedWhite: 0, alpha: 0.001).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        let contact = NSShadow()
        contact.shadowBlurRadius = 3.0
        contact.shadowOffset = CGSize(width: 0, height: -1.0)
        contact.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.32)
        contact.set()
        NSColor.black.withAlphaComponent(0.98).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.96).setStroke()
        path.lineWidth = 1.35
        path.stroke()
    }

    /// Angular metal plaque — thin grotesque/mono type, near-sharp corners, brushed surface.
    private func drawBadge(near point: CGPoint, agent: String, label: String?, lean: CGFloat) {
        let primary = agent.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondary = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let line: String
        if let secondary, !secondary.isEmpty {
            line = "\(primary)  ·  \(secondary)"
        } else {
            line = primary
        }

        let font = Self.labelFont(size: 10.5)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.82, alpha: 0.92),
            .kern: 0.85, // open tracking — space-grotesque feel
        ]
        let textSize = (line as NSString).size(withAttributes: attrs)

        let padX: CGFloat = 9
        let padY: CGFloat = 5.5
        let markSize: CGFloat = 4
        let gap: CGFloat = 7
        let width = padX + markSize + gap + textSize.width + padX
        let height = max(20, textSize.height + padY * 2)

        let origin = CGPoint(
            x: point.x + 16 + lean * 10,
            y: point.y - (height + 13)
        )
        let rect = CGRect(origin: origin, size: CGSize(width: width, height: height))
        // Near-angular: tiny radius, not a pill.
        let corner: CGFloat = 2.5
        let plate = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

        // Soft dark bloom behind the plate — more blur, less hard drop.
        NSGraphicsContext.saveGraphicsState()
        let bloom = NSShadow()
        bloom.shadowBlurRadius = 22
        bloom.shadowOffset = CGSize(width: 0, height: -2)
        bloom.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.55)
        bloom.set()
        NSColor(calibratedWhite: 0, alpha: 0.001).setFill()
        plate.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        let contact = NSShadow()
        contact.shadowBlurRadius = 14
        contact.shadowOffset = CGSize(width: 0, height: -3)
        contact.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.48)
        contact.set()
        // Darker metal core.
        NSColor(calibratedRed: 0.07, green: 0.075, blue: 0.07, alpha: 0.96).setFill()
        plate.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Brushed metal gradient — darker graphite, restrained highlights.
        // Bottom stop kept closer to mid so the lower slice doesn't read as a heavy bar.
        if let metal = NSGradient(colors: [
            NSColor(calibratedRed: 0.22, green: 0.23, blue: 0.21, alpha: 0.97),
            NSColor(calibratedRed: 0.11, green: 0.115, blue: 0.11, alpha: 0.98),
            NSColor(calibratedRed: 0.08, green: 0.085, blue: 0.08, alpha: 0.98),
            NSColor(calibratedRed: 0.12, green: 0.125, blue: 0.12, alpha: 0.96),
        ]) {
            NSGraphicsContext.saveGraphicsState()
            plate.addClip()
            metal.draw(in: rect, angle: 90)
            NSGraphicsContext.restoreGraphicsState()
        }

        // Faint top sheen — darker plate, quieter highlight.
        let sheen = NSBezierPath()
        sheen.move(to: CGPoint(x: rect.minX + corner, y: rect.maxY - 0.8))
        sheen.line(to: CGPoint(x: rect.maxX - corner, y: rect.maxY - 0.8))
        NSColor(calibratedWhite: 1.0, alpha: 0.12).setStroke()
        sheen.lineWidth = 0.7
        sheen.stroke()

        // Bottom settle trough — very light so it doesn't slice the plate in half.
        let trough = NSBezierPath()
        trough.move(to: CGPoint(x: rect.minX + corner, y: rect.minY + 0.9))
        trough.line(to: CGPoint(x: rect.maxX - corner, y: rect.minY + 0.9))
        NSColor(calibratedWhite: 0.0, alpha: 0.16).setStroke()
        trough.lineWidth = 0.45
        trough.stroke()

        // Machined edge — darker, less bright chrome.
        NSColor(calibratedRed: 0.38, green: 0.39, blue: 0.36, alpha: 0.42).setStroke()
        plate.lineWidth = 0.9
        plate.stroke()

        // Inner etch
        let inner = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.6, dy: 0.6),
            xRadius: max(1.5, corner - 0.4),
            yRadius: max(1.5, corner - 0.4)
        )
        NSColor(calibratedWhite: 1.0, alpha: 0.04).setStroke()
        inner.lineWidth = 0.5
        inner.stroke()

        // Square status mark (angular, matches the plate language).
        let markRect = CGRect(
            x: rect.minX + padX,
            y: rect.midY - markSize / 2,
            width: markSize,
            height: markSize
        )
        let mark = NSBezierPath(roundedRect: markRect, xRadius: 0.8, yRadius: 0.8)
        Self.brandCoral.withAlphaComponent(0.92).setFill()
        mark.fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
        mark.lineWidth = 0.4
        mark.stroke()

        let textOrigin = CGPoint(
            x: rect.minX + padX + markSize + gap,
            y: rect.midY - textSize.height / 2 - 0.5
        )
        (line as NSString).draw(at: textOrigin, withAttributes: attrs)
    }

    /// Thin mono / grotesque stack — JBM if installed, else SF Mono light, else system ultraLight.
    private static func labelFont(size: CGFloat) -> NSFont {
        let candidates = [
            "JetBrainsMono-Thin",
            "JetBrainsMono-ExtraLight",
            "JetBrainsMonoNL-Thin",
            "SpaceGrotesk-Light",
            "SpaceGrotesk-Regular",
            "SFMono-Light",
            "SFMono-Ultralight",
            "Menlo-Regular",
            "AvenirNext-UltraLight",
            "HelveticaNeue-UltraLight",
        ]
        for name in candidates {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        // System monospaced light is the reliable thin industrial fallback.
        return NSFont.monospacedSystemFont(ofSize: size, weight: .ultraLight)
    }
}
