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

final class ScreenOverlayCanvasController {
    static let shared = ScreenOverlayCanvasController()

    private var windowsByScreenID: [String: ScreenOverlayWindow] = [:]
    private var layersByID: [ScreenOverlayLayerID: ScreenOverlayLayerSnapshot] = [:]

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
        render()
    }

    func replaceLayers(owner: ScreenOverlayOwner, with layers: [ScreenOverlayLayerSnapshot]) {
        layersByID = layersByID.filter { _, layer in layer.owner != owner }
        for layer in layers {
            layersByID[layer.id] = layer
        }
        render()
    }

    func removeLayer(id: ScreenOverlayLayerID) {
        layersByID.removeValue(forKey: id)
        render()
    }

    func removeLayers(owner: ScreenOverlayOwner) {
        layersByID = layersByID.filter { _, layer in layer.owner != owner }
        render()
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

        for layer in layers {
            NSGraphicsContext.saveGraphicsState()
            NSColor.black.withAlphaComponent(0).set()
            switch layer.payload {
            case .snapZones(let payload):
                drawSnapZones(payload, opacity: layer.opacity)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
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
}
