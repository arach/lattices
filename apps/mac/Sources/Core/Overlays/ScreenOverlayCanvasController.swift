import AppKit

struct ScreenOverlayLayerID: Hashable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

enum ScreenOverlayOwner: String {
    case dragSnap
    case mouseGesture
    case hotkeyHints
    case focusHighlight
    case agentApi
}

enum ScreenOverlayScreenTarget: Equatable {
    case screen(id: String)
    case all
}

struct ScreenOverlayLayerSnapshot {
    let id: ScreenOverlayLayerID
    let owner: ScreenOverlayOwner
    let screen: ScreenOverlayScreenTarget
    let zIndex: Int
    let opacity: CGFloat
    let payload: ScreenOverlayPayload
    let expiresAt: Date?
}

enum ScreenOverlayPayload {
    case snapZones(ScreenOverlaySnapZonesPayload)
    case toast(ScreenOverlayTextPayload)
    case label(ScreenOverlayTextPayload)
    case highlight(ScreenOverlayHighlightPayload)
    case pet(ScreenOverlayPetPayload)
}

struct ScreenOverlaySnapZone {
    let id: String
    let label: String
    let rect: CGRect
    let isHovered: Bool
}

struct ScreenOverlaySnapZonesPayload {
    let zones: [ScreenOverlaySnapZone]
    let previewRect: CGRect?
    let previewLabel: String?
    let zoneOpacity: CGFloat
    let highlightOpacity: CGFloat
    let previewOpacity: CGFloat
    let cornerRadius: CGFloat
}

struct ScreenOverlayTextPayload {
    let text: String
    let detail: String?
    let point: CGPoint?
    let placement: ScreenOverlayPlacement
    let style: ScreenOverlayStyle
}

struct ScreenOverlayHighlightPayload {
    let rect: CGRect
    let label: String?
    let style: ScreenOverlayStyle
    let cornerRadius: CGFloat
}

struct ScreenOverlayPetPayload {
    let glyph: String
    let petID: String?
    let state: String?
    let name: String?
    let message: String?
    let point: CGPoint?
    let placement: ScreenOverlayPlacement
    let style: ScreenOverlayStyle
    let isDragging: Bool
    let dismissible: Bool

    func moved(to point: CGPoint, state nextState: String?, isDragging nextIsDragging: Bool? = nil) -> ScreenOverlayPetPayload {
        ScreenOverlayPetPayload(
            glyph: glyph,
            petID: petID,
            state: nextState ?? state,
            name: name,
            message: message,
            point: point,
            placement: .point,
            style: style,
            isDragging: nextIsDragging ?? isDragging,
            dismissible: dismissible
        )
    }
}

enum ScreenOverlayPlacement: String {
    case top
    case bottom
    case center
    case cursor
    case point
}

enum ScreenOverlayStyle: String {
    case info
    case success
    case warning
    case danger
    case playful
}

final class ScreenOverlayCanvasController {
    static let shared = ScreenOverlayCanvasController()

    private var windowsByScreenID: [String: ScreenOverlayWindow] = [:]
    private var layersByID: [ScreenOverlayLayerID: ScreenOverlayLayerSnapshot] = [:]
    private var motionsByLayerID: [ScreenOverlayLayerID: OverlayLayerMotion] = [:]
    private var animationTimer: Timer?
    private var globalDismissMonitor: Any?
    private var localDismissMonitor: Any?
    private var dragState: OverlayActorDragState?
    private var actorDragTimeoutTimer: Timer?
    private var agentActorsHidden = false
    private let maxActorDragDuration: TimeInterval = 8.0

    private init() {}

    func warmUp() {
        reconcileScreens()
        for window in windowsByScreenID.values {
            window.orderFrontRegardless()
            window.alphaValue = 0
        }
    }

    func reconcileScreens() {
        let currentScreenIDs = Set(NSScreen.screens.map(Self.screenID(for:)))
        for staleID in windowsByScreenID.keys where !currentScreenIDs.contains(staleID) {
            windowsByScreenID[staleID]?.orderOut(nil)
            windowsByScreenID.removeValue(forKey: staleID)
        }

        for screen in NSScreen.screens {
            let screenID = Self.screenID(for: screen)
            let window = windowsByScreenID[screenID] ?? makeWindow(for: screen)
            window.setFrame(screen.frame, display: false)
            window.overlayView.frame = NSRect(origin: .zero, size: screen.frame.size)
            windowsByScreenID[screenID] = window
        }
    }

    func publishLayer(_ layer: ScreenOverlayLayerSnapshot) {
        layersByID[layer.id] = layer
        scheduleExpiration(for: layer)
        render()
        updateLifecycleMonitors()
    }

    func replaceLayers(owner: ScreenOverlayOwner, with layers: [ScreenOverlayLayerSnapshot]) {
        layersByID = layersByID.filter { _, layer in layer.owner != owner }
        for layer in layers {
            layersByID[layer.id] = layer
            scheduleExpiration(for: layer)
        }
        render()
        updateLifecycleMonitors()
    }

    func removeLayer(id: ScreenOverlayLayerID) {
        layersByID.removeValue(forKey: id)
        motionsByLayerID.removeValue(forKey: id)
        if dragState?.id == id {
            dragState = nil
            cancelActorDragTimeout()
            resetPointerCapture()
        }
        render()
        updateLifecycleMonitors()
    }

    func removeLayers(owner: ScreenOverlayOwner) {
        let removedIDs = Set(layersByID.values.filter { $0.owner == owner }.map(\.id))
        layersByID = layersByID.filter { _, layer in layer.owner != owner }
        motionsByLayerID = motionsByLayerID.filter { id, _ in layersByID[id] != nil }
        if let dragState, removedIDs.contains(dragState.id) {
            self.dragState = nil
            cancelActorDragTimeout()
            resetPointerCapture()
        }
        render()
        updateLifecycleMonitors()
    }

    func toggleAgentActorsVisibility() {
        agentActorsHidden.toggle()
        if agentActorsHidden {
            dragState = nil
            cancelActorDragTimeout()
            resetPointerCapture()
        }
        render()
        updateLifecycleMonitors()
    }

    func resetInputCapture(reason: String) {
        dragState = nil
        cancelActorDragTimeout()
        resetPointerCapture()
        DiagnosticLog.shared.warn("ScreenOverlay: input capture reset for \(reason)")
    }

    @discardableResult
    func moveLayer(id: ScreenOverlayLayerID, to target: CGPoint, durationMs: Int, easing: String?) -> Bool {
        guard let layer = layersByID[id],
              case .pet(let payload) = layer.payload else { return false }
        let now = Date()
        let currentPoint = motionsByLayerID[id]?.point(at: now) ?? payload.point ?? target
        let duration = max(0.08, min(Double(durationMs) / 1000.0, 8.0))
        let restingState = payload.state == "run_left" || payload.state == "run_right" ? "idle" : payload.state
        let movingState = target.x < currentPoint.x - 2 ? "run_left" : "run_right"

        motionsByLayerID[id] = OverlayLayerMotion(
            from: currentPoint,
            to: target,
            startedAt: now,
            duration: duration,
            easing: OverlayLayerMotion.Easing.parse(easing),
            restingState: restingState
        )
        layersByID[id] = layer.replacingPayload(.pet(payload.moved(to: currentPoint, state: movingState)))
        render()
        updateLifecycleMonitors()
        return true
    }

    static func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }

    private func makeWindow(for screen: NSScreen) -> ScreenOverlayWindow {
        let window = ScreenOverlayWindow(frame: screen.frame)
        windowsByScreenID[Self.screenID(for: screen)] = window
        return window
    }

    private func render() {
        reconcileScreens()
        dropExpiredLayers()

        for screen in NSScreen.screens {
            let screenID = Self.screenID(for: screen)
            guard let window = windowsByScreenID[screenID] else { continue }
            let visibleLayers = layersByID.values
                .filter { layer in
                    if agentActorsHidden && layer.isParkableActor {
                        return false
                    }
                    switch layer.screen {
                    case .all:
                        return true
                    case .screen(let targetID):
                        return targetID == screenID
                    }
                }
                .sorted { left, right in
                    if left.zIndex != right.zIndex {
                        return left.zIndex < right.zIndex
                    }
                    return left.id.rawValue < right.id.rawValue
                }

            window.overlayView.layers = visibleLayers
            if visibleLayers.isEmpty {
                window.alphaValue = 0
            } else {
                window.alphaValue = 1
                window.orderFrontRegardless()
            }
        }
    }

    private func dropExpiredLayers() {
        let now = Date()
        layersByID = layersByID.filter { _, layer in
            guard let expiresAt = layer.expiresAt else { return true }
            return expiresAt > now
        }
        motionsByLayerID = motionsByLayerID.filter { id, _ in layersByID[id] != nil }
    }

    private func scheduleExpiration(for layer: ScreenOverlayLayerSnapshot) {
        guard let expiresAt = layer.expiresAt else { return }
        let delay = max(0, expiresAt.timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  let current = self.layersByID[layer.id],
                  current.expiresAt == expiresAt else { return }
            self.layersByID.removeValue(forKey: layer.id)
            self.motionsByLayerID.removeValue(forKey: layer.id)
            self.render()
            self.updateLifecycleMonitors()
        }
    }

    private func updateLifecycleMonitors() {
        updateAnimationTimer()
        updateDismissMonitors()
    }

    private func updateAnimationTimer() {
        let needsAnimation = !motionsByLayerID.isEmpty || layersByID.values.contains { layer in
            if case .pet = layer.payload { return true }
            return false
        }

        if needsAnimation, animationTimer == nil {
            animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.tickAnimation()
            }
        } else if !needsAnimation {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func tickAnimation() {
        let now = Date()
        var completedIDs: [ScreenOverlayLayerID] = []
        for (id, motion) in motionsByLayerID {
            guard let layer = layersByID[id],
                  case .pet(let payload) = layer.payload else {
                completedIDs.append(id)
                continue
            }

            let point = motion.point(at: now)
            let isComplete = motion.isComplete(at: now)
            let state: String?
            if isComplete {
                state = motion.restingState
                completedIDs.append(id)
            } else {
                state = motion.to.x < motion.from.x ? "run_left" : "run_right"
            }
            layersByID[id] = layer.replacingPayload(.pet(payload.moved(to: point, state: state)))
        }
        for id in completedIDs {
            motionsByLayerID.removeValue(forKey: id)
        }

        if !completedIDs.isEmpty {
            updateLifecycleMonitors()
        }
        render()
        for window in windowsByScreenID.values {
            window.overlayView.needsDisplay = true
        }
    }

    private func updateDismissMonitors() {
        let hasAgentLayer = layersByID.values.contains { $0.owner == .agentApi }
        if hasAgentLayer, globalDismissMonitor == nil {
            let mask: NSEvent.EventTypeMask = [
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
            ]
            globalDismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                DispatchQueue.main.async {
                    _ = self?.handlePointerEvent(event)
                }
            }
            localDismissMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    self?.dismissAgentOverlays()
                    return nil
                }
                return event
            }
        } else if !hasAgentLayer {
            if let globalDismissMonitor {
                NSEvent.removeMonitor(globalDismissMonitor)
                self.globalDismissMonitor = nil
            }
            if let localDismissMonitor {
                NSEvent.removeMonitor(localDismissMonitor)
                self.localDismissMonitor = nil
            }
            dragState = nil
            cancelActorDragTimeout()
            resetPointerCapture()
        }
    }

    @discardableResult
    private func handlePointerEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            dismissAgentOverlays()
            return false
        default:
            return false
        }
    }

    private func updatePointerCapture(at globalPoint: CGPoint) {
        resetPointerCapture()
    }

    private func beginActorDrag(at globalPoint: CGPoint) -> Bool {
        guard let hit = hitActor(at: globalPoint),
              let layer = layersByID[hit.id],
              case .pet(let payload) = layer.payload else { return false }
        let currentPoint = motionsByLayerID[hit.id]?.point(at: Date()) ?? payload.point ?? hit.localPoint
        motionsByLayerID.removeValue(forKey: hit.id)
        dragState = OverlayActorDragState(
            id: hit.id,
            screenID: hit.screenID,
            offset: CGPoint(x: hit.localPoint.x - currentPoint.x, y: hit.localPoint.y - currentPoint.y),
            lastPoint: currentPoint,
            startedAt: Date()
        )
        scheduleActorDragTimeout()
        layersByID[hit.id] = layer.replacingPayload(.pet(payload.moved(to: currentPoint, state: "idle", isDragging: true)))
        render()
        updateLifecycleMonitors()
        updatePointerCapture(at: globalPoint)
        return true
    }

    private func dragActor(to globalPoint: CGPoint) -> Bool {
        guard var dragState,
              let hit = screenLocalPoint(for: globalPoint),
              let layer = layersByID[dragState.id],
              case .pet(let payload) = layer.payload else { return false }
        clearStaleActorDragIfNeeded()
        guard self.dragState != nil else { return false }
        let nextPoint = CGPoint(
            x: hit.localPoint.x - dragState.offset.x,
            y: hit.localPoint.y - dragState.offset.y
        )
        let state = nextPoint.x < dragState.lastPoint.x - 1 ? "run_left" : "run_right"
        layersByID[dragState.id] = layer.replacingPayload(.pet(payload.moved(to: nextPoint, state: state, isDragging: true)))
        dragState.screenID = hit.screenID
        dragState.lastPoint = nextPoint
        self.dragState = dragState
        render()
        updatePointerCapture(at: globalPoint)
        return true
    }

    private func endActorDrag() {
        guard let dragState,
              let layer = layersByID[dragState.id],
              case .pet(let payload) = layer.payload else {
            self.dragState = nil
            cancelActorDragTimeout()
            resetPointerCapture()
            return
        }
        layersByID[dragState.id] = layer.replacingPayload(.pet(payload.moved(to: dragState.lastPoint, state: "idle", isDragging: false)))
        self.dragState = nil
        cancelActorDragTimeout()
        render()
        updateLifecycleMonitors()
        resetPointerCapture()
    }

    private func clearStaleActorDragIfNeeded() {
        guard let dragState,
              Date().timeIntervalSince(dragState.startedAt) > maxActorDragDuration else { return }
        DiagnosticLog.shared.warn("ScreenOverlay: stale actor drag cleared for \(dragState.id.rawValue)")
        endActorDrag()
    }

    private func scheduleActorDragTimeout() {
        cancelActorDragTimeout()
        actorDragTimeoutTimer = Timer.scheduledTimer(withTimeInterval: maxActorDragDuration, repeats: false) { [weak self] _ in
            guard let self, self.dragState != nil else { return }
            DiagnosticLog.shared.warn("ScreenOverlay: actor drag timed out; releasing pointer capture")
            self.endActorDrag()
        }
    }

    private func cancelActorDragTimeout() {
        actorDragTimeoutTimer?.invalidate()
        actorDragTimeoutTimer = nil
    }

    private func resetPointerCapture() {
        for window in windowsByScreenID.values {
            window.ignoresMouseEvents = true
        }
    }

    private func closeActor(at globalPoint: CGPoint) -> Bool {
        guard let hit = hitActor(at: globalPoint),
              let layer = layersByID[hit.id],
              layer.isParkableActor else { return false }
        layersByID.removeValue(forKey: hit.id)
        motionsByLayerID.removeValue(forKey: hit.id)
        if dragState?.id == hit.id {
            dragState = nil
            cancelActorDragTimeout()
        }
        render()
        updateLifecycleMonitors()
        resetPointerCapture()
        return true
    }

    private func hitActor(at globalPoint: CGPoint) -> (id: ScreenOverlayLayerID, window: ScreenOverlayWindow, screenID: String, localPoint: CGPoint)? {
        guard let hit = screenLocalPoint(for: globalPoint) else { return nil }
        guard let id = hit.window.overlayView.layerID(at: hit.localPoint) else { return nil }
        return (id, hit.window, hit.screenID, hit.localPoint)
    }

    private func screenLocalPoint(for globalPoint: CGPoint) -> (window: ScreenOverlayWindow, screenID: String, localPoint: CGPoint)? {
        for (screenID, window) in windowsByScreenID where window.frame.contains(globalPoint) {
            let localPoint = CGPoint(
                x: globalPoint.x - window.frame.minX,
                y: globalPoint.y - window.frame.minY
            )
            return (window, screenID, localPoint)
        }
        return nil
    }

    private func dismissAgentOverlays() {
        let before = layersByID.count
        layersByID = layersByID.filter { _, layer in
            guard layer.owner == .agentApi else { return true }
            return !layer.isDismissible
        }
        motionsByLayerID = motionsByLayerID.filter { id, _ in layersByID[id] != nil }
        if let dragState, layersByID[dragState.id] == nil {
            self.dragState = nil
            cancelActorDragTimeout()
            resetPointerCapture()
        }
        guard layersByID.count != before else { return }
        render()
        updateLifecycleMonitors()
    }
}

private struct OverlayActorDragState {
    let id: ScreenOverlayLayerID
    var screenID: String
    let offset: CGPoint
    var lastPoint: CGPoint
    let startedAt: Date
}

private extension ScreenOverlayLayerSnapshot {
    var isDismissible: Bool {
        switch payload {
        case .pet(let payload):
            return payload.dismissible
        default:
            return true
        }
    }

    var isParkableActor: Bool {
        owner == .agentApi && !isDismissible
    }

    func replacingPayload(_ payload: ScreenOverlayPayload) -> ScreenOverlayLayerSnapshot {
        ScreenOverlayLayerSnapshot(
            id: id,
            owner: owner,
            screen: screen,
            zIndex: zIndex,
            opacity: opacity,
            payload: payload,
            expiresAt: expiresAt
        )
    }
}

private struct OverlayLayerMotion {
    enum Easing: String {
        case linear
        case easeInOut
        case spring

        static func parse(_ value: String?) -> Easing {
            switch value?.lowercased() {
            case "linear":
                return .linear
            case "easeinout", "ease-in-out", "ease_in_out":
                return .easeInOut
            case "spring", nil:
                return .spring
            default:
                return .spring
            }
        }
    }

    let from: CGPoint
    let to: CGPoint
    let startedAt: Date
    let duration: TimeInterval
    let easing: Easing
    let restingState: String?

    func isComplete(at date: Date) -> Bool {
        date.timeIntervalSince(startedAt) >= duration
    }

    func point(at date: Date) -> CGPoint {
        let rawProgress = duration <= 0 ? 1 : min(max(date.timeIntervalSince(startedAt) / duration, 0), 1)
        let progress = eased(rawProgress)
        return CGPoint(
            x: from.x + (to.x - from.x) * progress,
            y: from.y + (to.y - from.y) * progress
        )
    }

    private func eased(_ progress: Double) -> Double {
        switch easing {
        case .linear:
            return progress
        case .easeInOut:
            return progress * progress * (3 - 2 * progress)
        case .spring:
            let damping = exp(-6.8 * progress)
            let oscillation = cos(10.5 * progress)
            return min(max(1 - damping * oscillation, 0), 1)
        }
    }
}

private final class ScreenOverlayWindow: NSPanel {
    let overlayView = ScreenOverlayCanvasView(frame: .zero)

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
        alphaValue = 0
        overlayView.frame = NSRect(origin: .zero, size: frame.size)
        overlayView.autoresizingMask = [.width, .height]
        contentView = overlayView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ScreenOverlayCanvasView: NSView {
    var layers: [ScreenOverlayLayerSnapshot] = [] {
        didSet { needsDisplay = true }
    }
    private var interactiveRectsByLayerID: [ScreenOverlayLayerID: CGRect] = [:]

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
        interactiveRectsByLayerID.removeAll()

        for layer in layers {
            NSGraphicsContext.saveGraphicsState()
            NSColor.black.withAlphaComponent(0).set()
            switch layer.payload {
            case .snapZones(let payload):
                drawSnapZones(payload, opacity: layer.opacity)
            case .toast(let payload):
                drawTextPill(payload, opacity: layer.opacity, isToast: true)
            case .label(let payload):
                drawTextPill(payload, opacity: layer.opacity, isToast: false)
            case .highlight(let payload):
                drawHighlight(payload, opacity: layer.opacity)
            case .pet(let payload):
                drawPet(payload, id: layer.id, opacity: layer.opacity)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    func layerID(at point: CGPoint) -> ScreenOverlayLayerID? {
        interactiveRectsByLayerID
            .first { _, rect in rect.contains(point) }
            .map(\.key)
    }

    private func drawTextPill(_ payload: ScreenOverlayTextPayload, opacity: CGFloat, isToast: Bool) {
        let titleFont = NSFont.monospacedSystemFont(ofSize: isToast ? 13 : 11, weight: .semibold)
        let detailFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let maxWidth = min(bounds.width - 64, isToast ? 460 : 320)
        let title = attributed(payload.text, font: titleFont, color: NSColor.white.withAlphaComponent(0.94 * opacity))
        let detail = payload.detail.map {
            attributed($0, font: detailFont, color: NSColor.white.withAlphaComponent(0.66 * opacity))
        }
        let detailSize = detail?.boundingRect(
            with: CGSize(width: maxWidth - 28, height: 120),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size ?? .zero
        let titleSize = title.boundingRect(
            with: CGSize(width: maxWidth - 28, height: 80),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size
        let width = min(maxWidth, max(110, max(titleSize.width, detailSize.width) + 28))
        let height = max(30, titleSize.height + (detail == nil ? 12 : detailSize.height + 18))
        let origin = overlayOrigin(
            placement: payload.placement,
            point: payload.point,
            size: CGSize(width: width, height: height),
            margin: isToast ? 42 : 18
        )
        let rect = CGRect(origin: origin, size: CGSize(width: width, height: height))

        drawPanel(rect, style: payload.style, opacity: opacity, radius: min(16, height / 2))
        title.draw(with: CGRect(x: rect.minX + 14, y: rect.maxY - titleSize.height - (detail == nil ? 8 : 10), width: width - 28, height: titleSize.height), options: [.usesLineFragmentOrigin])
        if let detail {
            detail.draw(with: CGRect(x: rect.minX + 14, y: rect.minY + 8, width: width - 28, height: detailSize.height + 2), options: [.usesLineFragmentOrigin])
        }
    }

    private func drawHighlight(_ payload: ScreenOverlayHighlightPayload, opacity: CGFloat) {
        let rect = payload.rect.insetBy(dx: -3, dy: -3)
        let radius = min(payload.cornerRadius, min(rect.width, rect.height) * 0.2)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let tint = color(for: payload.style)

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = .zero
        shadow.shadowColor = tint.withAlphaComponent(0.25 * opacity)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        tint.withAlphaComponent(0.08 * opacity).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        path.lineWidth = 2
        tint.withAlphaComponent(0.82 * opacity).setStroke()
        path.stroke()

        if let label = payload.label, !label.isEmpty {
            let textPayload = ScreenOverlayTextPayload(
                text: label,
                detail: nil,
                point: CGPoint(x: rect.minX + 14, y: rect.maxY + 18),
                placement: .point,
                style: payload.style
            )
            drawTextPill(textPayload, opacity: opacity, isToast: false)
        }
    }

    private func drawPet(_ payload: ScreenOverlayPetPayload, id: ScreenOverlayLayerID, opacity: CGFloat) {
        let glyphFont = NSFont.systemFont(ofSize: 44, weight: .regular)
        let nameFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let messageFont = NSFont.systemFont(ofSize: 12, weight: .regular)
        let glyph = attributed(payload.glyph, font: glyphFont, color: NSColor.white.withAlphaComponent(0.96 * opacity))
        let name = payload.name.map { attributed($0, font: nameFont, color: NSColor.white.withAlphaComponent(0.96 * opacity)) }
        let message = payload.message.map {
            attributed($0, font: messageFont, color: NSColor.white.withAlphaComponent(0.86 * opacity))
        }
        let artSize = CGSize(width: 96, height: 104)
        let textWidth: CGFloat = (name == nil && message == nil) ? 0 : 228
        let textHeight = textPlateHeight(name: name, message: message, width: textWidth)
        let bubbleWidth = artSize.width + (textWidth > 0 ? textWidth + 10 : 0)
        let bubbleHeight = max(artSize.height, textHeight)
        let origin = overlayOrigin(
            placement: payload.placement,
            point: payload.point,
            size: CGSize(width: bubbleWidth, height: bubbleHeight),
            margin: 30
        )
        let rect = CGRect(origin: origin, size: CGSize(width: bubbleWidth, height: bubbleHeight))
        let artRect = CGRect(
            x: rect.minX,
            y: rect.midY - artSize.height / 2,
            width: artSize.width,
            height: artSize.height
        )
        let dragPhase = Date().timeIntervalSinceReferenceDate * 11
        let dragLift: CGFloat = payload.isDragging ? 8 + CGFloat(sin(dragPhase)) * 2.5 : 0
        let dragTilt: CGFloat = payload.isDragging
            ? (payload.state == "run_left" ? 7 : -7) + CGFloat(sin(dragPhase * 0.72)) * 2.5
            : 0
        let dragScaleX: CGFloat = payload.isDragging ? 1.05 + CGFloat(sin(dragPhase * 0.9)) * 0.018 : 1
        let dragScaleY: CGFloat = payload.isDragging ? 0.98 + CGFloat(cos(dragPhase * 0.9)) * 0.018 : 1
        let bodyRect = artRect.offsetBy(dx: 0, dy: dragLift)

        NSGraphicsContext.saveGraphicsState()
        if payload.isDragging {
            let transform = NSAffineTransform()
            transform.translateX(by: bodyRect.midX, yBy: bodyRect.midY)
            transform.rotate(byDegrees: dragTilt)
            transform.scaleX(by: dragScaleX, yBy: dragScaleY)
            transform.translateX(by: -bodyRect.midX, yBy: -bodyRect.midY)
            transform.concat()
        }
        if let petID = payload.petID,
           let frame = CodexPetAssetCache.shared.frame(for: petID, state: payload.state) {
            frame.image.draw(
                in: bodyRect,
                from: frame.sourceRect,
                operation: .sourceOver,
                fraction: opacity,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        } else {
            glyph.draw(
                with: CGRect(x: bodyRect.midX - 26, y: bodyRect.midY - 26, width: 52, height: 52),
                options: [.usesLineFragmentOrigin]
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        guard textWidth > 0 else {
            interactiveRectsByLayerID[id] = artRect.insetBy(dx: -8, dy: -8)
            return
        }
        let textRect = CGRect(
            x: artRect.maxX + 10,
            y: rect.midY - textHeight / 2,
            width: textWidth,
            height: textHeight
        )
        interactiveRectsByLayerID[id] = artRect.union(textRect).insetBy(dx: -8, dy: -8)
        drawTranslucentTextWash(textRect, opacity: opacity)

        var cursorY = textRect.maxY - 10
        if let name {
            let nameRect = CGRect(x: textRect.minX + 12, y: cursorY - 16, width: textRect.width - 24, height: 16)
            drawCrispOverlayText(name, in: nameRect, opacity: opacity)
            cursorY = nameRect.minY - 4
        }
        if let message {
            let messageRect = CGRect(x: textRect.minX + 12, y: textRect.minY + 10, width: textRect.width - 24, height: max(18, cursorY - textRect.minY - 10))
            drawCrispOverlayText(message, in: messageRect, opacity: opacity)
        }
    }

    private func textPlateHeight(name: NSAttributedString?, message: NSAttributedString?, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        let messageSize = message?.boundingRect(
            with: CGSize(width: width - 24, height: 72),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size ?? .zero
        return max(38, (name == nil ? 0 : 20) + (message == nil ? 0 : ceil(messageSize.height) + 10) + 18)
    }

    private func drawTranslucentTextWash(_ rect: CGRect, opacity: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor(calibratedWhite: 0.02, alpha: 0.34 * opacity).setFill()
        path.fill()

        path.lineWidth = 0.5
        NSColor.white.withAlphaComponent(0.10 * opacity).setStroke()
        path.stroke()
    }

    private func drawCrispOverlayText(_ text: NSAttributedString, in rect: CGRect, opacity: CGFloat) {
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.72 * opacity)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        text.draw(with: rect.offsetBy(dx: 0, dy: -0.5), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        NSGraphicsContext.restoreGraphicsState()

        let halo = NSMutableAttributedString(attributedString: text)
        halo.addAttribute(.foregroundColor, value: NSColor.black.withAlphaComponent(0.36 * opacity), range: NSRange(location: 0, length: halo.length))
        halo.draw(with: rect.offsetBy(dx: 0.5, dy: -0.5), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        halo.draw(with: rect.offsetBy(dx: -0.5, dy: -0.5), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        text.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func drawSnapZones(_ payload: ScreenOverlaySnapZonesPayload, opacity: CGFloat) {
        for zone in payload.zones {
            drawSnapZone(zone, payload: payload, opacity: opacity)
        }

        if let previewRect = payload.previewRect {
            drawSnapPreview(previewRect, label: payload.previewLabel, payload: payload, opacity: opacity)
        }
    }

    private func drawSnapZone(
        _ zone: ScreenOverlaySnapZone,
        payload: ScreenOverlaySnapZonesPayload,
        opacity: CGFloat
    ) {
        let rect = zone.rect.insetBy(dx: 1.5, dy: 1.5)
        let radius = min(payload.cornerRadius, min(rect.width, rect.height) * 0.34)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let idleStrength = max(0.35, min(payload.zoneOpacity / 0.10, 1.4))
        let hoverStrength = max(0.35, min(payload.highlightOpacity / 0.22, 1.4))

        let shadow = NSShadow()
        shadow.shadowBlurRadius = zone.isHovered ? 18 : 10
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = NSColor.black.withAlphaComponent((zone.isHovered ? 0.20 : 0.10) * opacity)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        let baseTop = NSColor(
            calibratedWhite: 0.13,
            alpha: (zone.isHovered ? 0.42 * hoverStrength : 0.22 * idleStrength) * opacity
        )
        let baseBottom = NSColor(
            calibratedWhite: 0.07,
            alpha: (zone.isHovered ? 0.34 * hoverStrength : 0.15 * idleStrength) * opacity
        )
        NSGradient(starting: baseTop, ending: baseBottom)?.draw(in: path, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        if zone.isHovered {
            let glowPath = path.copy() as! NSBezierPath
            glowPath.lineWidth = 6
            NSColor(
                calibratedRed: 0.25,
                green: 0.84,
                blue: 0.58,
                alpha: payload.highlightOpacity * 0.28 * opacity
            ).setStroke()
            glowPath.stroke()
        }

        path.lineWidth = zone.isHovered ? 1.6 : 1.0
        NSColor(
            calibratedRed: 0.52,
            green: 0.94,
            blue: 0.72,
            alpha: (zone.isHovered ? 0.54 * hoverStrength : 0.10 * idleStrength) * opacity
        ).setStroke()
        path.stroke()

        let lipRect = CGRect(x: rect.minX + 1.5, y: rect.maxY - 2.5, width: rect.width - 3, height: 2)
        if lipRect.width > 0 {
            let lipPath = NSBezierPath(roundedRect: lipRect, xRadius: 1, yRadius: 1)
            NSColor.white.withAlphaComponent((zone.isHovered ? 0.18 : 0.08) * opacity).setFill()
            lipPath.fill()
        }

        drawLabel(zone.label, in: rect, emphasized: zone.isHovered, opacity: opacity)
    }

    private func drawSnapPreview(
        _ rect: CGRect,
        label: String?,
        payload: ScreenOverlaySnapZonesPayload,
        opacity: CGFloat
    ) {
        let previewRect = rect.insetBy(dx: 10, dy: 10)
        let radius = min(payload.cornerRadius, min(previewRect.width, previewRect.height) * 0.14)
        let path = NSBezierPath(roundedRect: previewRect, xRadius: radius, yRadius: radius)

        NSColor(calibratedWhite: 1.0, alpha: payload.previewOpacity * 0.22 * opacity).setFill()
        path.fill()

        path.lineWidth = 1.6
        path.setLineDash([10, 8], count: 2, phase: 0)
        NSColor(
            calibratedRed: 0.44,
            green: 0.90,
            blue: 0.68,
            alpha: max(0.34, payload.previewOpacity * 3.2) * opacity
        ).setStroke()
        path.stroke()
        path.setLineDash([], count: 0, phase: 0)

        let innerPath = NSBezierPath(
            roundedRect: previewRect.insetBy(dx: 7, dy: 7),
            xRadius: max(radius - 4, 8),
            yRadius: max(radius - 4, 8)
        )
        innerPath.lineWidth = 1
        NSColor.white.withAlphaComponent(max(0.08, payload.previewOpacity * 1.2) * opacity).setStroke()
        innerPath.stroke()

        if let label {
            let tagRect = CGRect(x: previewRect.minX + 14, y: previewRect.maxY - 34, width: 110, height: 24)
            let tagPath = NSBezierPath(roundedRect: tagRect, xRadius: 12, yRadius: 12)
            NSColor(calibratedWhite: 0.08, alpha: 0.62 * opacity).setFill()
            tagPath.fill()
            NSColor.white.withAlphaComponent(0.10 * opacity).setStroke()
            tagPath.lineWidth = 1
            tagPath.stroke()
            drawLabel(label, in: tagRect, emphasized: true, opacity: opacity)
        }
    }

    private func drawLabel(_ label: String, in rect: CGRect, emphasized: Bool, opacity: CGFloat) {
        let font = NSFont.monospacedSystemFont(ofSize: emphasized ? 11 : 10, weight: emphasized ? .semibold : .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent((emphasized ? 0.92 : 0.72) * opacity),
        ]
        let attributed = NSAttributedString(string: label.uppercased(), attributes: attributes)
        let size = attributed.size()
        let drawPoint = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        attributed.draw(at: drawPoint)
    }

    private func attributed(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
    }

    private func overlayOrigin(
        placement: ScreenOverlayPlacement,
        point: CGPoint?,
        size: CGSize,
        margin: CGFloat
    ) -> CGPoint {
        let cursor = convertGlobalPointToLocal(NSEvent.mouseLocation)
        let anchor: CGPoint
        switch placement {
        case .top:
            anchor = CGPoint(x: bounds.midX, y: bounds.maxY - margin - size.height / 2)
        case .bottom:
            anchor = CGPoint(x: bounds.midX, y: bounds.minY + margin + size.height / 2)
        case .center:
            anchor = CGPoint(x: bounds.midX, y: bounds.midY)
        case .cursor:
            anchor = cursor
        case .point:
            anchor = point ?? cursor
        }

        return CGPoint(
            x: min(max(anchor.x - size.width / 2, 16), bounds.maxX - size.width - 16),
            y: min(max(anchor.y - size.height / 2, 16), bounds.maxY - size.height - 16)
        )
    }

    private func convertGlobalPointToLocal(_ point: CGPoint) -> CGPoint {
        guard let window else { return point }
        return CGPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
    }

    private func drawPanel(_ rect: CGRect, style: ScreenOverlayStyle, opacity: CGFloat, radius: CGFloat) {
        let tint = color(for: style)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.26 * opacity)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSGradient(
            starting: NSColor(calibratedWhite: 0.12, alpha: 0.90 * opacity),
            ending: NSColor(calibratedWhite: 0.06, alpha: 0.90 * opacity)
        )?.draw(in: path, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        path.lineWidth = 1
        tint.withAlphaComponent(0.34 * opacity).setStroke()
        path.stroke()

        let lipRect = CGRect(x: rect.minX + 10, y: rect.maxY - 2, width: rect.width - 20, height: 1)
        NSColor.white.withAlphaComponent(0.10 * opacity).setFill()
        NSBezierPath(roundedRect: lipRect, xRadius: 0.5, yRadius: 0.5).fill()
    }

    private func color(for style: ScreenOverlayStyle) -> NSColor {
        switch style {
        case .info:
            return NSColor(calibratedRed: 0.36, green: 0.72, blue: 1.0, alpha: 1)
        case .success:
            return NSColor(calibratedRed: 0.38, green: 0.92, blue: 0.62, alpha: 1)
        case .warning:
            return NSColor(calibratedRed: 1.0, green: 0.66, blue: 0.24, alpha: 1)
        case .danger:
            return NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.38, alpha: 1)
        case .playful:
            return NSColor(calibratedRed: 0.95, green: 0.66, blue: 1.0, alpha: 1)
        }
    }
}

private final class CodexPetAssetCache {
    static let shared = CodexPetAssetCache()

    struct Frame {
        let image: NSImage
        let sourceRect: CGRect
    }

    private struct Metadata: Decodable {
        struct State: Decodable {
            let row: Int
            let frames: Int
            let frameWidth: CGFloat
            let frameHeight: CGFloat
        }

        let spritesheetPath: String?
        let states: [String: State]?
    }

    private var cache: [String: (image: NSImage, metadata: Metadata?)] = [:]

    private init() {}

    func frame(for petID: String, state requestedState: String?) -> Frame? {
        guard let asset = load(petID: petID),
              let size = asset.image.representations.first.map({ CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) }) else {
            return nil
        }

        let state = requestedState.flatMap { asset.metadata?.states?[$0] }
            ?? asset.metadata?.states?["idle"]
            ?? Metadata.State(row: 0, frames: 1, frameWidth: 192, frameHeight: 208)
        let frameWidth = max(1, state.frameWidth)
        let frameHeight = max(1, state.frameHeight)
        let frameCount = max(1, state.frames)
        let frameIndex = Int(Date().timeIntervalSinceReferenceDate * 8) % frameCount
        let row = max(0, state.row)
        let maxX = max(0, size.width - frameWidth)
        let y = max(0, size.height - CGFloat(row + 1) * frameHeight)
        return Frame(
            image: asset.image,
            sourceRect: CGRect(x: min(CGFloat(frameIndex) * frameWidth, maxX), y: y, width: frameWidth, height: frameHeight)
        )
    }

    private func load(petID: String) -> (image: NSImage, metadata: Metadata?)? {
        if let cached = cache[petID] {
            return cached
        }

        guard petID.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }

        let root = bundledPetRoot(petID: petID) ?? codexPetRoot(petID: petID)
        let metadataURL = root.appendingPathComponent("pet.json")
        let metadata = try? JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL))
        let spritesheetURL = root.appendingPathComponent(metadata?.spritesheetPath ?? "spritesheet.webp")
        guard let image = NSImage(contentsOf: spritesheetURL) else {
            return nil
        }

        let asset = (image, metadata)
        cache[petID] = asset
        return asset
    }

    private func bundledPetRoot(petID: String) -> URL? {
        let candidateRoots = [
            Bundle.main.resourceURL?.appendingPathComponent("Pets"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Pets"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("apps/mac/Resources/Pets"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/Pets"),
        ].compactMap { $0 }

        for petsRoot in candidateRoots {
            let root = petsRoot.appendingPathComponent(petID)
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("spritesheet.webp").path) {
                return root
            }
        }

        return nil
    }

    private func codexPetRoot(petID: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex")
            .appendingPathComponent("pets")
            .appendingPathComponent(petID)
    }
}
