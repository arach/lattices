import AppKit
import CoreGraphics

final class WindowDragSnapController {
    static let shared = WindowDragSnapController()

    private struct DragWindowCandidate {
        let pid: pid_t
        let wid: UInt32?
        let axWindow: AXUIElement
        let initialAXFrame: CGRect
    }

    private struct ResolvedSnapZone {
        let id: String
        let label: String
        let placement: PlacementSpec
        let screen: NSScreen
        let screenID: String
        let triggerRect: CGRect
        let visibleRect: CGRect
        let previewRect: CGRect
        let priority: Int
    }

    private struct DragSession {
        let pid: pid_t
        let wid: UInt32?
        let zones: [ResolvedSnapZone]
    }

    private var mouseDownMonitor: Any?
    private var mouseDragMonitor: Any?
    private var mouseUpMonitor: Any?
    private var flagsChangedMonitor: Any?

    private var dragCandidate: DragWindowCandidate?
    private var activeSession: DragSession?
    private var overlayPanels: [String: WindowSnapOverlayPanel] = [:]
    private var modifierModeEnabled = false
    private var windowHasMoved = false

    private init() {}

    func start() {
        guard mouseDownMonitor == nil,
              mouseDragMonitor == nil,
              mouseUpMonitor == nil,
              flagsChangedMonitor == nil else { return }

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseDown(event)
        }
        mouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleMouseDragged(event)
        }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp(event)
        }
        flagsChangedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        DiagnosticLog.shared.info("WindowDragSnap: global drag monitors started")
    }

    func stop() {
        if let monitor = mouseDownMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = mouseDragMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = mouseUpMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = flagsChangedMonitor { NSEvent.removeMonitor(monitor) }
        mouseDownMonitor = nil
        mouseDragMonitor = nil
        mouseUpMonitor = nil
        flagsChangedMonitor = nil
        clearTracking()
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard Preferences.shared.dragSnapEnabled else {
            clearTracking()
            return
        }
        guard PermissionChecker.shared.accessibility else {
            clearTracking()
            return
        }

        WorkspaceManager.shared.loadGridConfig()
        modifierModeEnabled = Self.snapModifierPressed()
        windowHasMoved = false
        activeSession = nil
        hideOverlays()
        dragCandidate = captureFocusedWindow(at: NSEvent.mouseLocation)
    }

    private func handleMouseDragged(_ event: NSEvent) {
        guard Preferences.shared.dragSnapEnabled else {
            clearTracking()
            return
        }
        guard PermissionChecker.shared.accessibility else {
            clearTracking()
            return
        }

        guard let candidate = dragCandidate else { return }
        modifierModeEnabled = Self.snapModifierPressed()
        updateDragProgress(for: candidate)
        updateSnapInteraction(at: NSEvent.mouseLocation)
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard dragCandidate != nil else { return }
        modifierModeEnabled = Self.snapModifierPressed()
        updateSnapInteraction(at: NSEvent.mouseLocation)
    }

    private func updateDragProgress(for candidate: DragWindowCandidate) {
        guard let currentFrame = WindowTiler.readAXFrame(candidate.axWindow) else { return }

        let moved = hypot(
            currentFrame.origin.x - candidate.initialAXFrame.origin.x,
            currentFrame.origin.y - candidate.initialAXFrame.origin.y
        )
        if moved >= 12 {
            windowHasMoved = true
        }
    }

    private func updateSnapInteraction(at mouseLocation: NSPoint) {
        guard windowHasMoved else {
            if activeSession != nil {
                activeSession = nil
                hideOverlays()
            }
            return
        }

        guard modifierModeEnabled else {
            if activeSession != nil {
                activeSession = nil
                hideOverlays()
            }
            return
        }

        guard let candidate = dragCandidate else { return }
        if activeSession == nil {
            beginDragSession(with: candidate, mouseLocation: mouseLocation)
        } else {
            updateActiveSession(at: mouseLocation)
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        defer { clearTracking() }
        modifierModeEnabled = Self.snapModifierPressed()
        guard modifierModeEnabled, let activeSession else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard let zone = bestZone(at: mouseLocation, in: activeSession.zones) else { return }

        DiagnosticLog.shared.info("WindowDragSnap: drop → \(zone.label) (\(zone.id)) on \(zone.screen.localizedName)")
        if let wid = activeSession.wid {
            WindowTiler.tileWindowById(wid: wid, pid: activeSession.pid, to: zone.placement, on: zone.screen)
            WindowTiler.highlightWindowById(wid: wid)
        } else {
            WindowTiler.tileFrontmostViaAX(to: zone.placement)
        }
    }

    private func beginDragSession(with candidate: DragWindowCandidate, mouseLocation: NSPoint) {
        WorkspaceManager.shared.loadGridConfig()
        let config = WorkspaceManager.shared.snapZonesConfig
        guard config.enabled ?? false else { return }

        let zones = resolveZones(using: config)
        guard !zones.isEmpty else { return }

        activeSession = DragSession(
            pid: candidate.pid,
            wid: candidate.wid,
            zones: zones
        )

        DiagnosticLog.shared.info("WindowDragSnap: tracking drag for pid=\(candidate.pid) wid=\(candidate.wid ?? 0)")
        updateActiveSession(at: mouseLocation)
    }

    private func updateActiveSession(at mouseLocation: NSPoint) {
        guard let activeSession else { return }
        let hoveredZone = bestZone(at: mouseLocation, in: activeSession.zones)
        render(zones: activeSession.zones, hoveredZone: hoveredZone)
    }

    private func clearTracking() {
        dragCandidate = nil
        activeSession = nil
        modifierModeEnabled = false
        windowHasMoved = false
        hideOverlays()
    }

    private func hideOverlays() {
        for panel in overlayPanels.values {
            panel.orderOut(nil)
        }
    }

    private func captureFocusedWindow(at mouseLocation: NSPoint) -> DragWindowCandidate? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }

        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
              let focusedRef else {
            return nil
        }
        let axWindow = focusedRef as! AXUIElement
        guard let axFrame = WindowTiler.readAXFrame(axWindow) else { return nil }

        let windowRect = Self.screenRect(fromAX: axFrame)
        guard windowRect.insetBy(dx: -8, dy: -8).contains(mouseLocation) else {
            return nil
        }

        var widValue: CGWindowID = 0
        let wid = _AXUIElementGetWindow(axWindow, &widValue) == .success ? widValue : nil

        return DragWindowCandidate(
            pid: frontApp.processIdentifier,
            wid: wid,
            axWindow: axWindow,
            initialAXFrame: axFrame
        )
    }

    private func resolveZones(using config: SnapZonesConfig) -> [ResolvedSnapZone] {
        let wm = WorkspaceManager.shared
        let baseZones = (config.rules ?? []).compactMap { zone -> (SnapZoneDefinition, PlacementSpec, (CGFloat, CGFloat, CGFloat, CGFloat), Int)? in
            let placement: PlacementSpec
            switch zone.placement {
            case .named(let name):
                guard let resolved = wm.resolvePlacement(name) else {
                    DiagnosticLog.shared.warn("WindowDragSnap: ignoring snap zone \(zone.id) — unknown placement \(name)")
                    return nil
                }
                placement = resolved
            case .fractions(let fractionalPlacement):
                placement = .fractions(fractionalPlacement)
            }

            let triggerFractions: (CGFloat, CGFloat, CGFloat, CGFloat)
            switch zone.trigger {
            case .named(let name):
                guard let triggerPlacement = wm.resolvePlacement(name) else {
                    DiagnosticLog.shared.warn("WindowDragSnap: ignoring snap zone \(zone.id) — unknown trigger \(name)")
                    return nil
                }
                triggerFractions = triggerPlacement.fractions
            case .fractions(let placement):
                triggerFractions = placement.fractions
            }

            return (zone, placement, triggerFractions, zone.priority ?? 0)
        }

        var resolved: [ResolvedSnapZone] = []
        for screen in NSScreen.screens {
            let screenID = Self.screenID(for: screen)
            for (zone, placement, triggerFractions, priority) in baseZones {
                let triggerRect = Self.screenRect(for: triggerFractions, on: screen)
                let previewRect = Self.screenRect(fromAX: WindowTiler.tileFrame(for: placement, on: screen))
                let visibleRect = Self.visibleRect(forTriggerRect: triggerRect, previewRect: previewRect, on: screen)
                resolved.append(
                    ResolvedSnapZone(
                        id: zone.id,
                        label: zone.label ?? zone.id,
                        placement: placement,
                        screen: screen,
                        screenID: screenID,
                        triggerRect: triggerRect,
                        visibleRect: visibleRect,
                        previewRect: previewRect,
                        priority: priority
                    )
                )
            }
        }

        return resolved.sorted {
            if $0.priority != $1.priority {
                return $0.priority > $1.priority
            }
            let leftArea = $0.triggerRect.width * $0.triggerRect.height
            let rightArea = $1.triggerRect.width * $1.triggerRect.height
            if leftArea != rightArea {
                return leftArea < rightArea
            }
            return $0.id < $1.id
        }
    }

    private func bestZone(at mouseLocation: NSPoint, in zones: [ResolvedSnapZone]) -> ResolvedSnapZone? {
        zones.first(where: { $0.triggerRect.contains(mouseLocation) })
    }

    private func render(zones: [ResolvedSnapZone], hoveredZone: ResolvedSnapZone?) {
        let config = WorkspaceManager.shared.snapZonesConfig
        let grouped = Dictionary(grouping: zones, by: \.screenID)
        let activeScreenIDs = Set(grouped.keys)

        for screen in NSScreen.screens {
            let screenID = Self.screenID(for: screen)
            guard let screenZones = grouped[screenID], !screenZones.isEmpty else { continue }

            let panel = overlayPanels[screenID] ?? makeOverlayPanel(for: screen)
            panel.setFrame(screen.frame, display: false)

            let localZones = screenZones.map {
                WindowSnapOverlayView.Zone(
                    id: $0.id,
                    label: $0.label,
                    rect: $0.visibleRect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY),
                    isHovered: hoveredZone?.id == $0.id && hoveredZone?.screenID == screenID
                )
            }

            let previewRect = hoveredZone?.screenID == screenID
                ? hoveredZone?.previewRect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                : nil

            panel.overlayView.model = WindowSnapOverlayView.Model(
                zones: localZones,
                previewRect: previewRect,
                previewLabel: nil,
                zoneOpacity: CGFloat(config.zoneOpacity ?? SnapZonesConfig.defaults.zoneOpacity ?? 0.10),
                highlightOpacity: CGFloat(config.highlightOpacity ?? SnapZonesConfig.defaults.highlightOpacity ?? 0.22),
                previewOpacity: CGFloat(config.previewOpacity ?? SnapZonesConfig.defaults.previewOpacity ?? 0.18),
                cornerRadius: config.cornerRadius ?? SnapZonesConfig.defaults.cornerRadius ?? 18
            )

            panel.orderFrontRegardless()
        }

        for (screenID, panel) in overlayPanels where !activeScreenIDs.contains(screenID) {
            panel.orderOut(nil)
        }
    }

    private func makeOverlayPanel(for screen: NSScreen) -> WindowSnapOverlayPanel {
        let panel = WindowSnapOverlayPanel(frame: screen.frame)
        overlayPanels[Self.screenID(for: screen)] = panel
        return panel
    }

    private static func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }

    private static func screenRect(for fractions: (CGFloat, CGFloat, CGFloat, CGFloat), on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let (fx, fy, fw, fh) = fractions
        return CGRect(
            x: visible.minX + visible.width * fx,
            y: visible.maxY - visible.height * (fy + fh),
            width: visible.width * fw,
            height: visible.height * fh
        )
    }

    private static func screenRect(fromAX rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func snapModifierPressed() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(Self.snapModifier().cgEventFlags)
    }

    private static func snapModifier() -> SnapModifierKey {
        WorkspaceManager.shared.snapZonesConfig.modifier ?? .command
    }

    private static func visibleRect(forTriggerRect triggerRect: CGRect, previewRect: CGRect, on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let inset: CGFloat = 18
        let nearLeft = abs(triggerRect.minX - visible.minX) < 8
        let nearRight = abs(triggerRect.maxX - visible.maxX) < 8
        let nearTop = abs(triggerRect.maxY - visible.maxY) < 8
        let nearBottom = abs(triggerRect.minY - visible.minY) < 8

        if (nearLeft || nearRight) && (nearTop || nearBottom) {
            let width: CGFloat = 94
            let height: CGFloat = 56
            let x = nearLeft ? visible.minX + inset : visible.maxX - inset - width
            let y = nearBottom ? visible.minY + inset : visible.maxY - inset - height
            return CGRect(x: x, y: y, width: width, height: height)
        }

        if nearLeft || nearRight {
            let width: CGFloat = 110
            let height: CGFloat = 38
            let x = nearLeft ? visible.minX + inset : visible.maxX - inset - width
            let y = clamp(previewRect.midY - height / 2, min: visible.minY + 54, max: visible.maxY - 54 - height)
            return CGRect(x: x, y: y, width: width, height: height)
        }

        if nearTop || nearBottom {
            let width = min(max(triggerRect.width * 0.34, 132), 240)
            let height: CGFloat = 38
            let x = clamp(previewRect.midX - width / 2, min: visible.minX + 54, max: visible.maxX - 54 - width)
            let y = nearBottom ? visible.minY + inset : visible.maxY - inset - height
            return CGRect(x: x, y: y, width: width, height: height)
        }

        let width = min(max(previewRect.width * 0.28, 132), 220)
        let height: CGFloat = 38
        let x = clamp(previewRect.midX - width / 2, min: visible.minX + 54, max: visible.maxX - 54 - width)
        let y = clamp(previewRect.maxY - height - 16, min: visible.minY + 40, max: visible.maxY - 40 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.max(lower, Swift.min(upper, value))
    }
}

private final class WindowSnapOverlayPanel: NSPanel {
    let overlayView = WindowSnapOverlayView(frame: .zero)

    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
        overlayView.frame = NSRect(origin: .zero, size: frame.size)
        overlayView.autoresizingMask = [.width, .height]
        contentView = overlayView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class WindowSnapOverlayView: NSView {
    struct Zone {
        let id: String
        let label: String
        let rect: CGRect
        let isHovered: Bool
    }

    struct Model {
        let zones: [Zone]
        let previewRect: CGRect?
        let previewLabel: String?
        let zoneOpacity: CGFloat
        let highlightOpacity: CGFloat
        let previewOpacity: CGFloat
        let cornerRadius: CGFloat

        static let empty = Model(
            zones: [],
            previewRect: nil,
            previewLabel: nil,
            zoneOpacity: 0.10,
            highlightOpacity: 0.22,
            previewOpacity: 0.18,
            cornerRadius: 18
        )
    }

    var model: Model = .empty {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        for zone in model.zones {
            drawZone(zone)
        }

        if let previewRect = model.previewRect {
            drawPreview(previewRect, label: model.previewLabel)
        }
    }

    private func drawZone(_ zone: Zone) {
        let rect = zone.rect.insetBy(dx: 1.5, dy: 1.5)
        let radius = min(model.cornerRadius, min(rect.width, rect.height) * 0.34)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let idleStrength = max(0.35, min(model.zoneOpacity / 0.10, 1.4))
        let hoverStrength = max(0.35, min(model.highlightOpacity / 0.22, 1.4))

        let shadow = NSShadow()
        shadow.shadowBlurRadius = zone.isHovered ? 18 : 10
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = NSColor.black.withAlphaComponent(zone.isHovered ? 0.20 : 0.10)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        let baseTop = NSColor(
            calibratedWhite: 0.13,
            alpha: zone.isHovered ? 0.42 * hoverStrength : 0.22 * idleStrength
        )
        let baseBottom = NSColor(
            calibratedWhite: 0.07,
            alpha: zone.isHovered ? 0.34 * hoverStrength : 0.15 * idleStrength
        )
        NSGradient(starting: baseTop, ending: baseBottom)?.draw(in: path, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        if zone.isHovered {
            let glowPath = path.copy() as! NSBezierPath
            glowPath.lineWidth = 6
            NSColor(calibratedRed: 0.25, green: 0.84, blue: 0.58, alpha: model.highlightOpacity * 0.28).setStroke()
            glowPath.stroke()
        }

        path.lineWidth = zone.isHovered ? 1.6 : 1.0
        NSColor(
            calibratedRed: 0.52,
            green: 0.94,
            blue: 0.72,
            alpha: zone.isHovered ? 0.54 * hoverStrength : 0.10 * idleStrength
        ).setStroke()
        path.stroke()

        let lipRect = CGRect(x: rect.minX + 1.5, y: rect.maxY - 2.5, width: rect.width - 3, height: 2)
        if lipRect.width > 0 {
            let lipPath = NSBezierPath(roundedRect: lipRect, xRadius: 1, yRadius: 1)
            NSColor.white.withAlphaComponent(zone.isHovered ? 0.18 : 0.08).setFill()
            lipPath.fill()
        }

        drawLabel(zone.label, in: rect, emphasized: zone.isHovered)
    }

    private func drawPreview(_ rect: CGRect, label: String?) {
        let previewRect = rect.insetBy(dx: 10, dy: 10)
        let radius = min(model.cornerRadius, min(previewRect.width, previewRect.height) * 0.14)
        let path = NSBezierPath(roundedRect: previewRect, xRadius: radius, yRadius: radius)

        NSColor(calibratedWhite: 1.0, alpha: model.previewOpacity * 0.22).setFill()
        path.fill()

        path.lineWidth = 1.6
        path.setLineDash([10, 8], count: 2, phase: 0)
        NSColor(
            calibratedRed: 0.44,
            green: 0.90,
            blue: 0.68,
            alpha: max(0.34, model.previewOpacity * 3.2)
        ).setStroke()
        path.stroke()
        path.setLineDash([], count: 0, phase: 0)

        let innerPath = NSBezierPath(roundedRect: previewRect.insetBy(dx: 7, dy: 7), xRadius: max(radius - 4, 8), yRadius: max(radius - 4, 8))
        innerPath.lineWidth = 1
        NSColor.white.withAlphaComponent(max(0.08, model.previewOpacity * 1.2)).setStroke()
        innerPath.stroke()

        if let label {
            let tagRect = CGRect(x: previewRect.minX + 14, y: previewRect.maxY - 34, width: 110, height: 24)
            let tagPath = NSBezierPath(roundedRect: tagRect, xRadius: 12, yRadius: 12)
            NSColor(calibratedWhite: 0.08, alpha: 0.62).setFill()
            tagPath.fill()
            NSColor.white.withAlphaComponent(0.10).setStroke()
            tagPath.lineWidth = 1
            tagPath.stroke()
            drawLabel(label, in: tagRect, emphasized: true)
        }
    }

    private func drawLabel(_ label: String, in rect: CGRect, emphasized: Bool) {
        let font = NSFont.monospacedSystemFont(ofSize: emphasized ? 11 : 10, weight: emphasized ? .semibold : .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(emphasized ? 0.92 : 0.72),
        ]
        let attr = NSAttributedString(string: label.uppercased(), attributes: attributes)
        let size = attr.size()
        let drawPoint = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        attr.draw(at: drawPoint)
    }
}
