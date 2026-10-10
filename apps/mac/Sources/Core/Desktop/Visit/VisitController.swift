import AppKit
import DeckKit

/// Visiting a paired host with this Mac's mouse and keyboard (docs/visit.md).
///
/// Armed, a listen-only tap watches mouse moves for a deliberate push past an
/// edge that faces a paired host. Crossing parks the cursor where it is
/// (`CGAssociateMouseAndMouseCursorPosition(0)`), and a session tap swallows
/// mouse and key events and forwards them over the visit channel. Nothing is
/// tapped unless armed.
final class VisitController {
    static let shared = VisitController()

    /// Points of push past the edge that start a visit.
    static let push: Double = 60
    /// A push older than this starts over.
    static let pushWindow: TimeInterval = 0.4
    /// After a visit ends, crossing waits this long.
    static let cooldown: TimeInterval = 0.6
    /// A visit with no `ready` by then ends.
    static let readyWait: TimeInterval = 3

    private static let armedKey = "visit.armed"

    struct Status {
        var armed: Bool
        var visiting: String?
        var hosts: [VisitTrust.Host]
    }

    private struct Visit {
        var host: VisitTrust.Host
        var channel: VisitChannel
        var parked: CGPoint
        var display: CGRect
        var ready = false
    }

    // Main thread.
    private(set) var armed = false
    private var visit: Visit?
    private var edgeTap: CFMachPort?
    private var edgeSource: CFRunLoopSource?
    private var captureTap: CFMachPort?
    private var captureSource: CFRunLoopSource?
    private var screensObserver: NSObjectProtocol?

    // Read on the tap thread, under `lock`.
    private let lock = NSLock()
    private var displays: [CGRect] = []
    private var sides: Set<VisitTrust.Side> = []
    private var pushed: Double = 0
    private var pushedAt: TimeInterval = 0
    private var quietUntil: TimeInterval = 0
    private var crossing = false
    private var forward: VisitChannel?

    // MARK: Arming

    /// Arms again on launch if it was armed when the app quit.
    func restore() {
        if UserDefaults.standard.bool(forKey: Self.armedKey) { arm(true) }
    }

    func arm(_ on: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        UserDefaults.standard.set(on, forKey: Self.armedKey)
        if !on {
            end(because: "disarmed")
            removeEdgeTap()
            armed = false
            if let screensObserver { NotificationCenter.default.removeObserver(screensObserver) }
            screensObserver = nil
            DiagnosticLog.shared.info("Visit: off")
            return
        }
        guard !armed else { return }
        armed = true
        refreshLayout()
        screensObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshLayout() }
        installEdgeTap()
        let hosts = VisitTrust.shared.list()
        DiagnosticLog.shared.info("Visit: armed for \(hosts.map { "\($0.name) (\($0.side.rawValue))" }.joined(separator: ", "))")
        // lan-mouse would cross the same edge; turn it off.
        DispatchQueue.global(qos: .utility).async {
            if PointerShare.status().sharing { DispatchQueue.main.async { PointerHome.bringHome() } }
        }
    }

    func status() -> Status {
        Status(armed: armed, visiting: visit?.host.name, hosts: VisitTrust.shared.list())
    }

    /// Re-reads displays and paired sides, after pairing or a display change.
    func refreshLayout() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let rects = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
        let paired = Set(VisitTrust.shared.list().map(\.side))
        lock.lock()
        displays = rects
        sides = paired
        lock.unlock()
    }

    // MARK: Visiting

    /// Starts a visit to the host on `side`, the cursor parked at `point`.
    func start(side: VisitTrust.Side, at point: CGPoint) {
        dispatchPrecondition(condition: .onQueue(.main))
        defer { lock.lock(); crossing = false; lock.unlock() }
        guard armed, visit == nil, let host = VisitTrust.shared.host(on: side) else { return }
        lock.lock()
        let rects = displays
        lock.unlock()
        guard let display = rects.first(where: { $0.insetBy(dx: -1, dy: -1).contains(point) }) else { return }
        let channel: VisitChannel
        do {
            channel = try VisitChannel(host: host, crypto: VisitTrust.shared.crypto(for: host))
        } catch {
            DiagnosticLog.shared.warn("Visit: \(host.name): \(error)")
            return
        }
        channel.onMessage = { [weak self] message in DispatchQueue.main.async { self?.received(message, on: channel) } }
        channel.onClose = { [weak self] reason in DispatchQueue.main.async { self?.closed(channel, because: reason) } }

        guard installCaptureTap() else {
            DiagnosticLog.shared.warn("Visit: couldn't tap input")
            return
        }
        CGAssociateMouseAndMouseCursorPosition(0)
        visit = Visit(host: host, channel: channel, parked: point, display: display)
        lock.lock(); forward = channel; lock.unlock()

        let along: Double = (side == .left || side == .right)
            ? (point.y - display.minY) / max(display.height, 1)
            : (point.x - display.minX) / max(display.width, 1)
        channel.open()
        channel.send(["t": "enter", "name": VisitTrust.Host.localName, "edge": side.opposite.rawValue, "at": min(max(along, 0), 1)])
        DiagnosticLog.shared.info("Visit: on \(host.name)")

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.readyWait) { [weak self] in
            guard let self, let visit = self.visit, visit.channel === channel, !visit.ready else { return }
            self.end(because: "\(host.name) didn't answer")
        }
    }

    /// Ends a visit, if there is one. `at` (0–1) places the cursor along the
    /// edge it left by; otherwise it stays where it was parked.
    func end(because reason: String, at: Double? = nil) {
        let work = { [self] in
            guard let visit else { return }
            self.visit = nil
            lock.lock()
            forward = nil
            quietUntil = ProcessInfo.processInfo.systemUptime + Self.cooldown
            pushed = 0
            lock.unlock()
            removeCaptureTap()
            if let at {
                CGWarpMouseCursorPosition(Self.point(on: visit.host.side, of: visit.display, at: at))
            }
            CGAssociateMouseAndMouseCursorPosition(1)
            visit.channel.close(leaving: true)
            DiagnosticLog.shared.info("Visit: back from \(visit.host.name) (\(reason))")
        }
        Thread.isMainThread ? work() : DispatchQueue.main.async(execute: work)
    }

    /// A point just inside `display`'s edge on `side`, `at` along it.
    static func point(on side: VisitTrust.Side, of display: CGRect, at: Double) -> CGPoint {
        let at = min(max(at, 0), 1)
        switch side {
        case .right: return CGPoint(x: display.maxX - 3, y: display.minY + at * (display.height - 1))
        case .left: return CGPoint(x: display.minX + 2, y: display.minY + at * (display.height - 1))
        case .top: return CGPoint(x: display.minX + at * (display.width - 1), y: display.minY + 2)
        case .bottom: return CGPoint(x: display.minX + at * (display.width - 1), y: display.maxY - 3)
        }
    }

    private func received(_ message: [String: Any], on channel: VisitChannel) {
        guard let visit, visit.channel === channel else { return }
        switch message["t"] as? String {
        case "ready":
            self.visit?.ready = true
            DiagnosticLog.shared.success("Visit: \(visit.host.name) ready")
        case "exit":
            end(because: "left \(visit.host.name)", at: message["at"] as? Double)
        case "error":
            DiagnosticLog.shared.warn("Visit: \(visit.host.name): \(message["message"] as? String ?? "error")")
        default:
            break
        }
    }

    private func closed(_ channel: VisitChannel, because reason: String) {
        guard let visit, visit.channel === channel else { return }
        end(because: reason)
    }

    // MARK: Edge tap (armed)

    private func installEdgeTap() {
        guard edgeTap == nil else { return }
        let mask = Self.mask([.mouseMoved])
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: Self.edgeCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DiagnosticLog.shared.warn("Visit: couldn't watch the edge (Accessibility?)")
            return
        }
        edgeTap = tap
        edgeSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let edgeSource { EventTapThread.mouse.add(source: edgeSource) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeEdgeTap() {
        if let edgeSource { EventTapThread.mouse.remove(source: edgeSource) }
        if let edgeTap { CFMachPortInvalidate(edgeTap) }
        edgeTap = nil
        edgeSource = nil
    }

    private static let edgeCallback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<VisitController>.fromOpaque(info).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { if let tap = controller.edgeTap { CGEvent.tapEnable(tap: tap, enable: true) } }
        } else if type == .mouseMoved {
            controller.watchEdge(event)
        }
        return Unmanaged.passUnretained(event)
    }

    /// Tap thread. Adds up push against an edge that faces a paired host.
    private func watchEdge(_ event: CGEvent) {
        let p = event.location
        let dx = event.getDoubleValueField(.mouseEventDeltaX)
        let dy = event.getDoubleValueField(.mouseEventDeltaY)
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        defer { lock.unlock() }
        guard !crossing, forward == nil, now >= quietUntil else { return }
        guard let display = displays.first(where: { $0.insetBy(dx: -1, dy: -1).contains(p) }) else { return }
        let free = { (q: CGPoint) in !self.displays.contains { $0.contains(q) } }
        var side: VisitTrust.Side?
        var into: Double = 0
        if sides.contains(.right), p.x >= display.maxX - 1.5, free(CGPoint(x: display.maxX + 1, y: p.y)) { side = .right; into = dx }
        else if sides.contains(.left), p.x <= display.minX + 0.5, free(CGPoint(x: display.minX - 1, y: p.y)) { side = .left; into = -dx }
        else if sides.contains(.bottom), p.y >= display.maxY - 1.5, free(CGPoint(x: p.x, y: display.maxY + 1)) { side = .bottom; into = dy }
        else if sides.contains(.top), p.y <= display.minY + 0.5, free(CGPoint(x: p.x, y: display.minY - 1)) { side = .top; into = -dy }
        guard let side, into > 0 else { pushed = 0; return }
        if now - pushedAt > Self.pushWindow { pushed = 0 }
        pushed += into
        pushedAt = now
        guard pushed >= Self.push else { return }
        pushed = 0
        crossing = true
        DispatchQueue.main.async { self.start(side: side, at: p) }
    }

    // MARK: Capture tap (visiting)

    private func installCaptureTap() -> Bool {
        let mask = Self.mask([
            .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .scrollWheel, .keyDown, .keyUp, .flagsChanged,
        ])
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: Self.captureCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        captureTap = tap
        captureSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let captureSource { EventTapThread.mouse.add(source: captureSource) }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeCaptureTap() {
        if let captureSource { EventTapThread.mouse.remove(source: captureSource) }
        if let captureTap { CFMachPortInvalidate(captureTap) }
        captureTap = nil
        captureSource = nil
    }

    private static let captureCallback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<VisitController>.fromOpaque(info).takeUnretainedValue()
        return controller.capture(type, event)
    }

    /// Tap thread. Forwards and swallows; ⌃⌥⌘ Home ends the visit here, so it
    /// works whatever the channel is doing.
    private func capture(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { if let tap = self.captureTap { CGEvent.tapEnable(tap: tap, enable: true) } }
            return Unmanaged.passUnretained(event)
        }
        lock.lock()
        let channel = forward
        lock.unlock()
        guard let channel else { return Unmanaged.passUnretained(event) }

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            channel.move(dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY))
        case .leftMouseDown, .leftMouseUp:
            channel.send(["t": "button", "button": "left", "down": type == .leftMouseDown])
        case .rightMouseDown, .rightMouseUp:
            channel.send(["t": "button", "button": "right", "down": type == .rightMouseDown])
        case .otherMouseDown, .otherMouseUp:
            if event.getIntegerValueField(.mouseEventButtonNumber) == 2 {
                channel.send(["t": "button", "button": "middle", "down": type == .otherMouseDown])
            }
        case .scrollWheel:
            let dy = -event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let dx = -event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            if dx != 0 || dy != 0 { channel.send(["t": "scroll", "dx": dx, "dy": dy]) }
        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if VisitKeys.isSummon(keyCode: code, flags: event.flags) {
                DispatchQueue.main.async { self.end(because: "summoned") }
                return nil
            }
            var length = 0
            var chars = [UniChar](repeating: 0, count: 8)
            event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
            let typed = String(utf16CodeUnits: chars, count: length)
            if let message = VisitKeys.message(keyCode: code, flags: event.flags, typed: typed) { channel.send(message) }
        default:
            break
        }
        return nil
    }

    private static func mask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    }
}
