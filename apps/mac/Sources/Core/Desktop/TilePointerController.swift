import AppKit
import CoreGraphics

/// Hold Ctrl+Option and move the mouse to aim. Dead-center is cancel;
/// the rest of the center cell is maximize; outer cells are sectors.
/// Release Ctrl+Option to apply the current aim, or stay in the dead
/// zone to do nothing. A key chord during the hold cancels the picker.
final class TilePointerController {
    static let shared = TilePointerController()

    private var flagsMonitor: Any?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localMouseMonitor: Any?
    private var localKeyMonitor: Any?

    private var armed = false
    private var origin: NSPoint?
    private var aimPoint: NSPoint?
    private var currentPosition: TilePosition?
    private var currentScreen: NSScreen?
    private var pollTimer: Timer?
    private var pendingArm: DispatchWorkItem?
    private var pendingDisarm: DispatchWorkItem?

    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// Loop `MouseInteractionObserver`: inner dead zone, then maximize
    /// until the ring, then 8 wedges.
    static let noActionDistance: CGFloat = 10
    static let directionalDistance: CGFloat = 50
    private static let edgePin: CGFloat = 1
    static let wedges: [TilePosition] = [
        .top, .topRight, .right, .bottomRight,
        .bottom, .bottomLeft, .left, .topLeft,
    ]

    private init() {}

    func start() {
        guard flagsMonitor == nil else { return }

        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event.modifierFlags)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event.modifierFlags)
            return event
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouseMoved(event)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouseMoved(event)
            return event
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }

        DiagnosticLog.shared.info("TilePointer: Ctrl+Option mouse aiming started")
    }

    func stop() {
        for monitor in [flagsMonitor, mouseMonitor, keyMonitor, localFlagsMonitor, localMouseMonitor, localKeyMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        flagsMonitor = nil
        mouseMonitor = nil
        keyMonitor = nil
        localFlagsMonitor = nil
        localMouseMonitor = nil
        localKeyMonitor = nil
        pendingArm?.cancel()
        pendingArm = nil
        pendingDisarm?.cancel()
        pendingDisarm = nil
        dismiss(apply: false)
    }

    /// Keyboard chords and other Ctrl+Option hotkeys own the hold.
    func cancelApply() {
        dismiss(apply: false)
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard !Self.modifierKeyCodes.contains(event.keyCode) else { return }
        cancelApply()
    }

    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let mods = flags.intersection(.deviceIndependentFlagsMask)
        // If Command or Shift is held (e.g. Hyper key chord or transition),
        // immediately abort aiming so the Hyper key is never intercepted.
        if !mods.intersection([.command, .shift]).isEmpty {
            pendingArm?.cancel()
            pendingArm = nil
            pendingDisarm?.cancel()
            pendingDisarm = nil
            if armed {
                dismiss(apply: false)
            }
            return
        }

        if Self.ctrlOptionHeld(flags) {
            pendingDisarm?.cancel()
            pendingDisarm = nil
            guard !armed, pendingArm == nil else { return }
            // Debounce arming briefly (30ms) so rapid modifier transitions (e.g. Hyper press)
            // do not transiently arm before Command and Shift register.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingArm = nil
                guard Self.ctrlOptionHeld(NSEvent.modifierFlags), !self.armed else { return }
                DiagnosticLog.shared.info("TilePointer: arm flags=\(NSEvent.modifierFlags.rawValue)")
                self.arm()
            }
            pendingArm = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
            return
        }

        pendingArm?.cancel()
        pendingArm = nil
        guard armed else { return }
        scheduleDisarm()
    }

    private func scheduleDisarm() {
        guard pendingDisarm == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingDisarm = nil
            guard self.armed, !Self.ctrlOptionHeld(NSEvent.modifierFlags) else { return }
            let currentMods = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasDisallowedModifiers = !currentMods.intersection([.command, .shift]).isEmpty
            let shouldApply = !hasDisallowedModifiers && self.currentPosition != nil && !WindowDragSnapController.shared.isSnapping
            DiagnosticLog.shared.info("TilePointer: disarm apply=\(shouldApply) pos=\(self.currentPosition?.rawValue ?? "nil")")
            self.dismiss(apply: shouldApply)
        }
        pendingDisarm = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func handleMouseMoved(_ event: NSEvent? = nil) {
        guard armed, !WindowDragSnapController.shared.isSnapping else { return }
        if origin == nil {
            origin = NSEvent.mouseLocation
        }
        guard let origin else { return }
        let location = resolveAimPoint(event, origin: origin)

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) })
                ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main else { return }
        currentScreen = screen
        let position = Self.position(at: location, origin: origin)
        showHUD(at: origin, position: position)
        guard position != currentPosition else { return }
        currentPosition = position
        DiagnosticLog.shared.info("TilePointer: aim \(position?.rawValue ?? "idle") on \(screen.localizedName)")
        // Move detent: tick when the aim enters a new cell. Returning to
        // dead-center stays silent so cancel reads as "null".
        if position != nil, Preferences.shared.tilePointerSoundEffectsEnabled {
            AppFeedback.shared.aimTick()
        }
        if let position {
            TileZoneOverlay.shared.show(position: position, on: screen)
        } else {
            TileZoneOverlay.shared.dismiss()
        }
    }

    /// When the origin sits against a display edge, macOS pins the cursor.
    /// Keep integrating event deltas past that pin so outward cells stay reachable
    /// — the same absolute-mouse compensation Loop uses on its radial menu.
    private func resolveAimPoint(_ event: NSEvent?, origin: NSPoint) -> NSPoint {
        let current = NSEvent.mouseLocation
        guard let bounds = NSScreen.screens.first(where: { $0.frame.contains(origin) })?.frame else {
            aimPoint = current
            return current
        }

        let nearEdge = abs(origin.x - bounds.minX) < Self.directionalDistance
            || abs(origin.x - bounds.maxX) < Self.directionalDistance
            || abs(origin.y - bounds.minY) < Self.directionalDistance
            || abs(origin.y - bounds.maxY) < Self.directionalDistance
        guard nearEdge else {
            aimPoint = current
            return current
        }

        guard let event else {
            return aimPoint ?? current
        }

        let atMinX = abs(current.x - bounds.minX) < Self.edgePin
        let atMaxX = abs(current.x - bounds.maxX) < Self.edgePin
        let atMinY = abs(current.y - bounds.minY) < Self.edgePin
        let atMaxY = abs(current.y - bounds.maxY) < Self.edgePin
        var resolved = current
        let last = aimPoint ?? current
        let maxOffset = Self.directionalDistance
        if atMinX || atMaxX {
            resolved.x = min(max(last.x + event.deltaX, bounds.minX - maxOffset), bounds.maxX + maxOffset)
        }
        if atMinY || atMaxY {
            resolved.y = min(max(last.y + event.deltaY, bounds.minY - maxOffset), bounds.maxY + maxOffset)
        }
        aimPoint = resolved
        return resolved
    }

    private func arm() {
        armed = true
        origin = NSEvent.mouseLocation
        aimPoint = origin
        currentPosition = nil
        currentScreen = NSScreen.screens.first(where: { $0.frame.contains(origin ?? .zero) }) ?? NSScreen.main
        startPolling()
        if let origin {
            showHUD(at: origin, position: nil)
        }
        handleMouseMoved(nil)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard self?.armed == true else { return }
            self?.handleMouseMoved(nil)
        }
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func dismiss(apply: Bool) {
        pendingArm?.cancel()
        pendingArm = nil
        pendingDisarm?.cancel()
        pendingDisarm = nil
        pollTimer?.invalidate()
        pollTimer = nil
        let position = currentPosition
        let screen = currentScreen
        armed = false
        origin = nil
        aimPoint = nil
        currentPosition = nil
        currentScreen = nil

        hideHUD()
        if apply, let position {
            // Land: same tactile commit the other window-placement paths use.
            if Preferences.shared.tilePointerSoundEffectsEnabled {
                AppFeedback.shared.commitTactile()
            }
            if WindowMotionMode.shared.tileCurrentTarget(to: position) {
                return
            }
            TileZoneOverlay.shared.show(position: position, on: screen, autoHideAfter: 0.28)
            WindowTiler.tileFrontmostViaAX(to: position)
            return
        }
        TileZoneOverlay.shared.dismiss()
    }

    private var hudStyle: TilePointerHUDStyle {
        Preferences.shared.tilePointerHUDStyle
    }

    private func showHUD(at origin: NSPoint, position: TilePosition?) {
        switch hudStyle {
        case .loop:
            TilePointerMatrixHUD.shared.hide()
            TilePointerRadialHUD.shared.show(at: origin, position: position)
        case .matrix:
            TilePointerRadialHUD.shared.hide()
            TilePointerMatrixHUD.shared.show(at: origin, position: position)
        }
    }

    private func hideHUD() {
        TilePointerRadialHUD.shared.hide()
        TilePointerMatrixHUD.shared.hide()
    }

    private static func ctrlOptionHeld(_ flags: NSEvent.ModifierFlags) -> Bool {
        let mods = flags.intersection(.deviceIndependentFlagsMask)
        return mods.contains(.control)
            && mods.contains(.option)
            && mods.intersection([.command, .shift]).isEmpty
    }

    static func wedgeIndex(for position: TilePosition) -> Int? {
        wedges.firstIndex(of: position)
    }

    static func position(at point: NSPoint, origin: NSPoint) -> TilePosition? {
        switch Preferences.shared.tilePointerHUDStyle {
        case .loop:
            return loopPosition(at: point, origin: origin)
        case .matrix:
            return matrixPosition(at: point, origin: origin)
        }
    }

    /// Loop `MouseInteractionObserver.processNewMouseLocation`:
    /// `-atan2(dy, dx) + π/2` so 0° is up, then 8 wedges clockwise.
    static func loopPosition(at point: NSPoint, origin: NSPoint) -> TilePosition? {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let distance = hypot(dx, dy)
        if distance < noActionDistance { return nil }
        let ringThreshold = directionalDistance - TilePointerRadialHUD.thickness
        if distance <= ringThreshold {
            return .maximize
        }

        var degrees = (-atan2(dy, dx) + .pi / 2) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let span = 360.0 / CGFloat(wedges.count)
        let index = Int((degrees + span / 2) / span) % wedges.count
        return wedges[index]
    }

    /// Same three bands as Loop, mapped onto the matrix: inner dead zone,
    /// rest of the center cell = maximize, then unbounded 3×3 sectors.
    static func matrixPosition(at point: NSPoint, origin: NSPoint) -> TilePosition? {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let cell = TilePointerMatrixHUD.cellSize
        let half = cell / 2
        let inCenter = abs(dx) <= half && abs(dy) <= half
        if inCenter {
            if hypot(dx, dy) < cell * 0.34 { return nil }
            return .maximize
        }
        let col = dx < 0 ? 0 : 2
        let row = dy > 0 ? 0 : 2
        let onVertical = abs(dx) <= half
        let onHorizontal = abs(dy) <= half
        if onVertical { return dy > 0 ? .top : .bottom }
        if onHorizontal { return dx < 0 ? .left : .right }
        return TilePointerMatrixHUD.cells.first { $0.col == col && $0.row == row }?.position
    }
}
