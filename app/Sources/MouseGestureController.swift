import AppKit
import CoreGraphics

// MARK: - Gesture Direction

enum GestureDirection: String, Codable {
    case up, left, right, down, none

    var arrow: String {
        switch self {
        case .up:    return "↑"
        case .down:  return "↓"
        case .left:  return "←"
        case .right: return "→"
        case .none:  return ""
        }
    }
}

// MARK: - Action Types

/// Supported gesture actions — extend this enum as capabilities grow.
enum MouseGestureAction: String, Codable, CaseIterable {
    // Tile actions
    case tileMaximize   // 1×1 full cell
    case tileLeft
    case tileRight
    case tileTop
    case tileBottom
    case tileTopLeft
    case tileTopRight
    case tileBottomLeft
    case tileBottomRight

    // Grid distributions
    case grid2x2
    case grid3x3
    case grid4x4

    var label: String {
        switch self {
        case .tileMaximize:  return "Maximize"
        case .tileLeft:      return "Tile Left"
        case .tileRight:     return "Tile Right"
        case .tileTop:       return "Tile Top"
        case .tileBottom:    return "Tile Bottom"
        case .tileTopLeft:   return "Top Left"
        case .tileTopRight:  return "Top Right"
        case .tileBottomLeft:  return "Bottom Left"
        case .tileBottomRight: return "Bottom Right"
        case .grid2x2:       return "2×2 Grid"
        case .grid3x3:       return "3×3 Grid"
        case .grid4x4:       return "4×4 Grid"
        }
    }
}

// MARK: - Config Models

struct MouseShortcutConfig: Codable {
    var rules: [MouseShortcutRule]
    var tuning: GestureTuning?
    var version: Int?

    struct MouseShortcutRule: Codable {
        var id: String
        var device: String  // "any", "MX Master", specific device name
        var enabled: Bool?
        var trigger: Trigger
        var action: Action

        struct Trigger: Codable {
            var button: String       // "button3", "button4", "middle", etc.
            var direction: String    // "up", "down", "left", "right"
            var kind: String        // "drag", "hold", "tap"
        }

        struct Action: Codable {
            var type: String         // e.g. "tile.left", "grid.3x3", "resize.grow.left"
            var options: [String: String]?  // optional params
        }
    }

    struct GestureTuning: Codable {
        var dragThreshold: Double?
        var holdTolerance: Double?
        var axisBias: Double?
    }

    static func load() -> MouseShortcutConfig? {
        let path = NSHomeDirectory() + "/.lattices/mouse-shortcuts.json"
        guard let data = FileManager.default.contents(atPath: path) else {
            DiagnosticLog.shared.warn("MouseGestureController: no config at ~/.lattices/mouse-shortcuts.json")
            return nil
        }
        do {
            let config = try JSONDecoder().decode(MouseShortcutConfig.self, from: data)
            DiagnosticLog.shared.info("MouseGestureController: loaded \(config.rules.count) rules from config")
            return config
        } catch {
            DiagnosticLog.shared.error("MouseGestureController: failed to parse config: \(error)")
            return nil
        }
    }
}

// MARK: - Resolved Rule

struct ResolvedRule {
    let action: MouseGestureAction
    let direction: GestureDirection
    let buttonLabel: String
}

// MARK: - MouseGestureController

/// Listens for held mouse buttons + drag gestures, executes window actions.
/// Configuration comes from ~/.lattices/mouse-shortcuts.json — no hardcoded paths.
/// Falls back to built-in defaults only when the config is absent or missing rules.
final class MouseGestureController {
    static let shared = MouseGestureController()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Tracking state
    private var activeButtonLabel: String?
    private var startPoint: CGPoint = .zero
    private var accumulatedDelta: CGPoint = .zero
    private var committedDirection: GestureDirection = .none
    private var isTracking = false

    // Config
    private var rules: [String: ResolvedRule] = [:]  // "button3:up" → rule
    private var tuning: MouseShortcutConfig.GestureTuning = .init()
    private var defaultRules: [String: MouseGestureAction] = [:]  // fallbacks

    // HUD feedback
    private var feedbackWindow: NSWindow?
    private var feedbackTimer: Timer?

    // Self-healing circuit breaker
    private struct BreakerState {
        var trips: [Date] = []
        var cooldownUntil: Date?
        var permanentlyOpen: Bool = false
    }
    private var breaker = BreakerState()
    private let breakerLock = NSLock()

    private init() {
        loadConfig()
        setupEventTap()
    }

    deinit { stop() }

    // MARK: - Config Loading

    private func loadConfig() {
        // Build default fallback rules
        defaultRules = [
            "button3:up":   .tileMaximize,
            "button3:left": .grid2x2,
            "button3:right": .grid3x3,
            "button3:down": .grid4x4,
        ]

        guard let config = MouseShortcutConfig.load() else {
            // Use defaults
            buildRuleMap(from: defaultRules)
            return
        }

        // Tuning
        tuning = config.tuning ?? MouseShortcutConfig.GestureTuning()

        // Build rule map from config
        var resolved: [String: MouseGestureAction] = [:]
        for rule in config.rules {
            guard rule.enabled != false else { continue }

            let key = "\(rule.trigger.button):\(rule.trigger.direction)"
            let action = parseActionType(rule.action.type)
            if let action {
                resolved[key] = action
                DiagnosticLog.shared.info("MouseGestureController: config rule \(rule.id) → \(key) = \(rule.action.type)")
            }
        }

        buildRuleMap(from: resolved.isEmpty ? defaultRules : resolved)
    }

    private func buildRuleMap(from source: [String: MouseGestureAction]) {
        rules = source.mapValues { action in
            let parts = action.rawValue.split(separator: ".").map(String.init)
            let dir: GestureDirection
            switch parts.last ?? "" {
            case "up":    dir = .up
            case "down":  dir = .down
            case "left":  dir = .left
            case "right": dir = .right
            default:      dir = .none
            }
            let button = source.first { $0.value == action }?.key.components(separatedBy: ":").first ?? ""
            return ResolvedRule(action: action, direction: dir, buttonLabel: button)
        }

        // Simpler: store raw actions
        rawRules = source
    }

    private var rawRules: [String: MouseGestureAction] = [:]

    private func parseActionType(_ type: String) -> MouseGestureAction? {
        switch type {
        // Tile
        case "tile.maximize", "tile.max":    return .tileMaximize
        case "tile.left":                      return .tileLeft
        case "tile.right":                     return .tileRight
        case "tile.top":                       return .tileTop
        case "tile.bottom":                    return .tileBottom
        case "tile.top-left", "tile.topLeft":  return .tileTopLeft
        case "tile.top-right", "tile.topRight": return .tileTopRight
        case "tile.bottom-left", "tile.bottomLeft": return .tileBottomLeft
        case "tile.bottom-right", "tile.bottomRight": return .tileBottomRight
        // Grid
        case "grid.2x2", "grid2x2":           return .grid2x2
        case "grid.3x3", "grid3x3":           return .grid3x3
        case "grid.4x4", "grid4x4":           return .grid4x4
        default:
            return nil
        }
    }

    func reloadConfig() {
        rules.removeAll()
        rawRules.removeAll()
        loadConfig()
    }

    // MARK: - Event Tap

    private func setupEventTap() {
        let downMask: CGEventMask = (
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)
        )
        let upMask: CGEventMask = (
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)
        )
        let dragMask: CGEventMask = (
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)
        )
        let eventMask = downMask | upMask | dragMask

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<MouseGestureController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            DiagnosticLog.shared.error("MouseGestureController: failed to create event tap — needs Accessibility permission?")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        DiagnosticLog.shared.info("MouseGestureController: event tap installed")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            // OS detected our callback was too slow — let the breaker decide whether to back off.
            tripBreaker(reason: "tap disabled by OS timeout")
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            handleButtonDown(buttonNumber: buttonNumber, event: event)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            handleButtonUp(buttonNumber: buttonNumber, event: event)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            handleMouseDragged(event: event)
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Event Handlers

    private func handleButtonDown(buttonNumber: Int, event: CGEvent) {
        let label = buttonLabel(for: buttonNumber)
        guard rawRules.keys.contains(where: { $0.hasPrefix(label) }) else { return }

        activeButtonLabel = label
        startPoint = event.location
        accumulatedDelta = .zero
        committedDirection = .none
        isTracking = true

        DiagnosticLog.shared.info("MouseGestureController: tracking button=\(label)")
    }

    private func handleMouseDragged(event: CGEvent) {
        guard isTracking, let button = activeButtonLabel else { return }

        let currentPoint = event.location
        let delta = CGPoint(
            x: currentPoint.x - startPoint.x,
            y: currentPoint.y - startPoint.y
        )
        accumulatedDelta = delta

        let threshold = CGFloat(tuning.dragThreshold ?? 30)

        if committedDirection == .none {
            let dx = abs(delta.x)
            let dy = abs(delta.y)

            if max(dx, dy) > threshold {
                committedDirection = dx > dy
                    ? (delta.x > 0 ? .right : .left)
                    : (delta.y > 0 ? .down : .up)

                let key = "\(button):\(committedDirection.rawValue)"
                let action = rawRules[key]
                showFeedback(action: action, direction: committedDirection)
                DiagnosticLog.shared.info("MouseGestureController: committed \(key) → \(action?.label ?? "nil")")
            }
        }
    }

    private func handleButtonUp(buttonNumber: Int, event: CGEvent) {
        guard isTracking, let button = activeButtonLabel else { return }

        hideFeedback()

        if let direction = commitDirection() {
            let key = "\(button):\(direction.rawValue)"
            if let action = rawRules[key], !breakerTripped {
                dispatchAction(action, direction: direction)
            }
        }

        resetTracking()
    }

    /// Run an action off the event tap callback. Tap callback returns immediately;
    /// AX/window work runs on the main queue. Duration is measured — if it exceeds
    /// the budget, the circuit breaker trips and gestures pause.
    private func dispatchAction(_ action: MouseGestureAction, direction: GestureDirection) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.breakerTripped else { return }
            let start = Date()
            self.executeAction(action, direction: direction)
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            if elapsedMs > 500 {
                self.tripBreaker(reason: "slow action \(action.label) (\(elapsedMs)ms)")
            }
        }
    }

    // MARK: - Direction Logic

    private func commitDirection() -> GestureDirection? {
        guard committedDirection != .none else { return nil }

        let dx = abs(accumulatedDelta.x)
        let dy = abs(accumulatedDelta.y)

        // Confirm dominant axis
        let bias = tuning.axisBias ?? 1.0
        if dx > dy * bias || dy > dx * bias {
            return committedDirection
        }

        // Too short = cancel
        let threshold = CGFloat(tuning.dragThreshold ?? 30)
        if max(dx, dy) < threshold * 0.5 {
            return nil
        }

        return committedDirection
    }

    // MARK: - Action Execution

    private func executeAction(_ action: MouseGestureAction, direction: GestureDirection) {
        DiagnosticLog.shared.info("MouseGestureController: executing \(action.label)")

        switch action {
        // Tile actions
        case .tileMaximize:
            WindowTiler.tileFrontmostViaAX(to: .maximize)
        case .tileLeft:
            WindowTiler.tileFrontmostViaAX(to: .left)
        case .tileRight:
            WindowTiler.tileFrontmostViaAX(to: .right)
        case .tileTop:
            WindowTiler.tileFrontmostViaAX(to: .top)
        case .tileBottom:
            WindowTiler.tileFrontmostViaAX(to: .bottom)
        case .tileTopLeft:
            WindowTiler.tileFrontmostViaAX(to: .topLeft)
        case .tileTopRight:
            WindowTiler.tileFrontmostViaAX(to: .topRight)
        case .tileBottomLeft:
            WindowTiler.tileFrontmostViaAX(to: .bottomLeft)
        case .tileBottomRight:
            WindowTiler.tileFrontmostViaAX(to: .bottomRight)

        // Grid distributions
        case .grid2x2:
            applyGrid(columns: 2, rows: 2)
        case .grid3x3:
            applyGrid(columns: 3, rows: 3)
        case .grid4x4:
            applyGrid(columns: 4, rows: 4)
        }
    }

    private func applyGrid(columns: Int, rows: Int) {
        let windows = DesktopModel.shared.allWindows()
            .filter { $0.isOnScreen && $0.app != "Lattices" && !$0.title.isEmpty }
            .prefix(columns * rows)
            .map { (wid: $0.wid, pid: $0.pid) }

        guard !windows.isEmpty else { return }

        let screen = mouseScreen()
        let sf = screen.visibleFrame
        let primaryH = NSScreen.screens.first?.frame.height ?? 900
        let screenCGX = sf.origin.x
        let screenCGY = primaryH - sf.origin.y - sf.height

        let cellW = sf.width / CGFloat(columns)
        let cellH = sf.height / CGFloat(rows)
        let gap: CGFloat = 2

        var moves: [(wid: UInt32, pid: Int32, frame: CGRect)] = []
        for (i, win) in windows.enumerated() {
            let col = i % columns
            let row = i / columns
            let frame = CGRect(
                x: screenCGX + CGFloat(col) * cellW + gap,
                y: screenCGY + CGFloat(row) * cellH + gap,
                width: cellW - gap * 2,
                height: cellH - gap * 2
            )
            moves.append((win.wid, win.pid, frame))
        }

        WindowTiler.batchMoveAndRaiseWindows(moves)
    }

    // MARK: - Feedback HUD

    private func showFeedback(action: MouseGestureAction?, direction: GestureDirection) {
        DispatchQueue.main.async { [weak self] in
            self?.displayFeedbackBadge(action: action, direction: direction)
        }
    }

    private func displayFeedbackBadge(action: MouseGestureAction?, direction: GestureDirection) {
        hideFeedback()

        let badge = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 50),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        badge.isOpaque = false
        badge.backgroundColor = .clear
        badge.level = .floating
        badge.hasShadow = true
        badge.ignoresMouseEvents = true
        badge.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 50))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        contentView.layer?.cornerRadius = 12

        let arrowLabel = NSTextField(labelWithString: direction.arrow)
        arrowLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        arrowLabel.textColor = .white
        arrowLabel.frame = NSRect(x: 12, y: 8, width: 30, height: 34)
        arrowLabel.alignment = .center

        let actionLabel = NSTextField(labelWithString: action?.label ?? "—")
        actionLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        actionLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        actionLabel.frame = NSRect(x: 42, y: 8, width: 90, height: 34)
        actionLabel.lineBreakMode = .byTruncatingTail

        contentView.addSubview(arrowLabel)
        contentView.addSubview(actionLabel)
        badge.contentView = contentView

        let mouseLoc = NSEvent.mouseLocation
        let badgeFrame = NSRect(x: mouseLoc.x + 20, y: mouseLoc.y - 25, width: 140, height: 50)
        badge.setFrame(badgeFrame, display: false)
        badge.alphaValue = 0
        badge.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            badge.animator().alphaValue = 1
        }

        feedbackWindow = badge

        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.hideFeedback()
        }
    }

    private func hideFeedback() {
        feedbackTimer?.invalidate()
        feedbackTimer = nil

        guard let window = feedbackWindow else { return }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
        }

        feedbackWindow = nil
    }

    private func resetTracking() {
        activeButtonLabel = nil
        startPoint = .zero
        accumulatedDelta = .zero
        committedDirection = .none
        isTracking = false
    }

    // MARK: - Utilities

    private func buttonLabel(for number: Int) -> String {
        switch number {
        case 2:  return "middle"
        case 3:  return "button3"
        case 4:  return "button4"
        default: return "button\(number)"
        }
    }

    private func mouseScreen() -> NSScreen {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(loc) })
            ?? NSScreen.main ?? NSScreen.screens.first!
    }

    // MARK: - Self-healing Circuit Breaker

    /// True when the breaker has tripped — actions should not be dispatched.
    private var breakerTripped: Bool {
        breakerLock.lock()
        defer { breakerLock.unlock() }
        if breaker.permanentlyOpen { return true }
        if let until = breaker.cooldownUntil, Date() < until { return true }
        return false
    }

    /// Trip the breaker. Disables the tap, shows a status badge, schedules recovery.
    /// Cooldown grows with repeated trips: 30s → 2min → permanent (until reload/restart).
    private func tripBreaker(reason: String) {
        breakerLock.lock()
        let now = Date()
        breaker.trips = breaker.trips.filter { now.timeIntervalSince($0) < 600 }
        breaker.trips.append(now)
        let count = breaker.trips.count

        let cooldown: TimeInterval
        let isPermanent: Bool
        if count >= 3 {
            cooldown = 0
            isPermanent = true
            breaker.permanentlyOpen = true
        } else if count >= 2 {
            cooldown = 120
            isPermanent = false
            breaker.cooldownUntil = now.addingTimeInterval(cooldown)
        } else {
            cooldown = 30
            isPermanent = false
            breaker.cooldownUntil = now.addingTimeInterval(cooldown)
        }
        breakerLock.unlock()

        DiagnosticLog.shared.warn("MouseGestureController: breaker tripped (\(reason)) — trips=\(count), \(isPermanent ? "permanent" : "cooldown=\(Int(cooldown))s")")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: false)
            }
            let message = isPermanent
                ? "Mouse gestures disabled — too many stalls"
                : "Mouse gestures paused — resuming in \(Int(cooldown))s"
            self.showStatusBadge(message: message)

            if !isPermanent {
                DispatchQueue.main.asyncAfter(deadline: .now() + cooldown) { [weak self] in
                    self?.recoverBreaker()
                }
            }
        }
    }

    /// Re-enable the tap after cooldown, unless the breaker has been permanently opened.
    private func recoverBreaker() {
        breakerLock.lock()
        let stillPermanent = breaker.permanentlyOpen
        if !stillPermanent {
            breaker.cooldownUntil = nil
        }
        breakerLock.unlock()

        guard !stillPermanent else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        DiagnosticLog.shared.info("MouseGestureController: breaker recovered — tap re-enabled")
        showStatusBadge(message: "Mouse gestures resumed")
    }

    private func showStatusBadge(message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.hideFeedback()

            let width: CGFloat = 280
            let height: CGFloat = 44
            let badge = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            badge.isOpaque = false
            badge.backgroundColor = .clear
            badge.level = .floating
            badge.hasShadow = true
            badge.ignoresMouseEvents = true
            badge.collectionBehavior = [.canJoinAllSpaces, .stationary]

            let contentView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
            contentView.layer?.cornerRadius = 12

            let label = NSTextField(labelWithString: message)
            label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            label.textColor = .white
            label.frame = NSRect(x: 14, y: 0, width: width - 28, height: height)
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            contentView.addSubview(label)
            badge.contentView = contentView

            let screen = self.mouseScreen()
            let sf = screen.visibleFrame
            let badgeFrame = NSRect(
                x: sf.midX - width / 2,
                y: sf.midY - height / 2,
                width: width,
                height: height
            )
            badge.setFrame(badgeFrame, display: false)
            badge.alphaValue = 0
            badge.orderFront(nil)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                badge.animator().alphaValue = 1
            }

            self.feedbackWindow = badge
            self.feedbackTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
                self?.hideFeedback()
            }
        }
    }

    // MARK: - Start/Stop

    func start() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        DiagnosticLog.shared.info("MouseGestureController: started")
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        hideFeedback()
        DiagnosticLog.shared.info("MouseGestureController: stopped")
    }
}