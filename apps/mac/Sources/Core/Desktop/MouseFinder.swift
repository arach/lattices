import AppKit
import CoreGraphics

private enum SpotlightConfig {
    static let overlayAlpha: CGFloat = 0.75
    static let dimAlpha: CGFloat = 0.85
    static let spotlightRadius: CGFloat = 200
    static let sonarDelay: TimeInterval = 1.0
    static let totalDuration: TimeInterval = 2.5
    static let fadeInDuration: TimeInterval = 0.15
    static let fadeOutDuration: TimeInterval = 0.4
    static let accentColor = NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
}

enum CursorAppearanceStyle: String {
    case spotlight
    case pulse
    case marker
}

enum CursorMarkerShape: String, CaseIterable, Identifiable {
    case arrow
    case chevron
    case facet
    case shard
    case wedge
    case prism
    case notch
    case needle
    case petal
    case kite

    static let `default`: CursorMarkerShape = .arrow
    static let settingsOptions: [CursorMarkerShape] = [
        .arrow, .needle, .petal, .shard, .chevron,
        .facet, .wedge, .prism, .notch, .kite,
    ]

    var id: String { rawValue }

    var label: String {
        switch self {
        case .arrow:
            return "Arrow"
        case .chevron:
            return "Chevron"
        case .facet:
            return "Facet"
        case .shard:
            return "Shard"
        case .wedge:
            return "Wedge"
        case .prism:
            return "Prism"
        case .notch:
            return "Notch"
        case .needle:
            return "Needle"
        case .petal:
            return "Petal"
        case .kite:
            return "Kite"
        }
    }

    static func resolve(_ raw: String?) -> CursorMarkerShape {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "arrow", "pointer", "cursor", "mac", "macos", "classic":
            return .arrow
        case "chevron", "chev":
            return .chevron
        case "facet", "faceted":
            return .facet
        case "shard", "diamond":
            return .shard
        case "wedge", "plate", "flat", "slab":
            return .wedge
        case "prism", "bevel", "fold":
            return .prism
        case "notch", "fork", "split":
            return .notch
        case "needle", "pin", "fine", "slim":
            return .needle
        case "petal", "leaf", "soft":
            return .petal
        case "kite", "delta", "paper":
            return .kite
        default:
            return .default
        }
    }
}

enum CursorMarkerSize: String, CaseIterable, Identifiable {
    case tiny
    case small
    case regular
    case large

    static let `default`: CursorMarkerSize = .tiny
    static let settingsOptions: [CursorMarkerSize] = [.tiny, .small, .regular, .large]

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tiny:
            return "Tiny"
        case .small:
            return "Small"
        case .regular:
            return "Regular"
        case .large:
            return "Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .tiny:
            return 0.54
        case .small:
            return 0.66
        case .regular:
            return 0.82
        case .large:
            return 1.00
        }
    }

    static func resolve(_ raw: String?) -> CursorMarkerSize {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "tiny", "micro", "xs":
            return .tiny
        case "small", "compact", "sm":
            return .small
        case "regular", "medium", "normal", "md":
            return .regular
        case "large", "big", "lg":
            return .large
        default:
            return .default
        }
    }

    static func closest(to scale: Double) -> CursorMarkerSize {
        let clamped = max(0.55, min(scale, 1.12))
        return settingsOptions.min {
            abs(Double($0.scale) - clamped) < abs(Double($1.scale) - clamped)
        } ?? .default
    }
}

enum CursorTrailStyle: String {
    case none
    case thread
    case ribbon
    case spark
    case comet
    case route

    static let `default`: CursorTrailStyle = .thread

    static func resolve(_ raw: String?) -> CursorTrailStyle {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "none", "off", "false":
            return .none
        case "ribbon", "path":
            return .ribbon
        case "spark", "sparkle", "dots":
            return .spark
        case "comet", "tail", "glow-path", "glowpath":
            return .comet
        case "route", "preview", "tether":
            return .route
        case "thread", "line", "hairline", "whisper":
            return .thread
        default:
            return .default
        }
    }
}

enum CursorMotionStyle: String {
    case glide
    case snap
    case float
    case rush
    case crawl
    case accelerate
    case teleport
    case spring
    case magnet
    case slingshot

    static let `default`: CursorMotionStyle = .glide

    var motionFraction: Double {
        switch self {
        case .glide:
            return 0.72
        case .snap:
            return 0.50
        case .float:
            return 0.86
        case .rush:
            return 0.34
        case .crawl:
            return 0.94
        case .accelerate:
            return 0.58
        case .teleport:
            return 0.42
        case .spring:
            return 0.64
        case .magnet:
            return 0.56
        case .slingshot:
            return 0.48
        }
    }

    var minimumDuration: CFTimeInterval {
        switch self {
        case .rush, .teleport:
            return 0.16
        case .snap:
            return 0.24
        case .spring, .magnet:
            return 0.30
        case .slingshot:
            return 0.26
        default:
            return 0.34
        }
    }

    var maximumDuration: CFTimeInterval {
        switch self {
        case .rush, .teleport:
            return 1.35
        case .crawl:
            return 6.5
        case .spring, .magnet:
            return 2.4
        case .slingshot:
            return 1.8
        default:
            return 2.8
        }
    }

    static func resolve(_ raw: String?) -> CursorMotionStyle {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "snap", "quick", "fast":
            return .snap
        case "rush", "zip", "very-fast", "veryfast":
            return .rush
        case "crawl", "linger", "very-slow", "veryslow":
            return .crawl
        case "accelerate", "accel", "speedup", "speed-up":
            return .accelerate
        case "teleport", "warp", "blink":
            return .teleport
        case "spring", "elastic", "bounce":
            return .spring
        case "magnet", "magnetic", "attract":
            return .magnet
        case "slingshot", "sling", "snapback-rush", "snapbackrush":
            return .slingshot
        case "float", "drift", "slow":
            return .float
        case "glide", "soft", "default":
            return .glide
        default:
            return .default
        }
    }
}

enum CursorTrajectoryStyle: String {
    case straight
    case soft
    case arc
    case swoop
    case overshoot

    static let `default`: CursorTrajectoryStyle = .arc

    var bendScale: CGFloat {
        switch self {
        case .straight:
            return 0
        case .soft:
            return 0.55
        case .arc:
            return 1.0
        case .swoop:
            return 1.45
        case .overshoot:
            return 0.85
        }
    }

    static func resolve(_ raw: String?) -> CursorTrajectoryStyle {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "straight", "line", "direct":
            return .straight
        case "soft", "slight":
            return .soft
        case "swoop", "big", "wide":
            return .swoop
        case "overshoot", "snapback", "snap-back", "past":
            return .overshoot
        case "arc", "curve", "curved":
            return .arc
        default:
            return .default
        }
    }
}

enum CursorGlowStyle: String {
    case none
    case soft
    case halo
    case comet

    static let `default`: CursorGlowStyle = .soft

    static func resolve(_ raw: String?) -> CursorGlowStyle {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "none", "off", "false":
            return .none
        case "halo", "aura", "bloom":
            return .halo
        case "comet", "tail":
            return .comet
        case "soft", "glow", "default":
            return .soft
        default:
            return .default
        }
    }
}

enum CursorIdleStyle: String {
    case still
    case breathe
    case wiggle
    case orbit
    case hover
    case nod
    case drift
    case shimmer
    case blink
    case tremble

    static let `default`: CursorIdleStyle = .breathe

    static func resolve(_ raw: String?) -> CursorIdleStyle {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "still", "none", "off", "false":
            return .still
        case "wiggle", "micro-rotate", "microrotate", "rotate":
            return .wiggle
        case "orbit", "alive":
            return .orbit
        case "hover", "floaty", "bob":
            return .hover
        case "nod", "dip", "tap":
            return .nod
        case "drift", "wander", "sway":
            return .drift
        case "shimmer", "glint", "shine":
            return .shimmer
        case "blink", "flash":
            return .blink
        case "tremble", "vibrate", "jitter":
            return .tremble
        case "breathe", "breath", "pulse", "default":
            return .breathe
        default:
            return .default
        }
    }
}

enum CursorEdgeStyle: String {
    case none
    case pulse
    case ripple
    case tick
    case reticle
    case blink
    case spark
    case underline
    case echo
    case scan
    case pin

    static let `default`: CursorEdgeStyle = .pulse

    static func resolve(_ raw: String?) -> CursorEdgeStyle {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "none", "off", "false":
            return .none
        case "ripple", "ring", "rings":
            return .ripple
        case "tick", "ticks", "snap":
            return .tick
        case "reticle", "bracket", "brackets", "frame", "target":
            return .reticle
        case "blink", "flash":
            return .blink
        case "spark", "sparkle", "burst":
            return .spark
        case "underline", "bar", "line":
            return .underline
        case "echo", "ghost":
            return .echo
        case "scan", "sweep":
            return .scan
        case "pin", "drop", "peg":
            return .pin
        case "pulse", "edge", "default":
            return .pulse
        default:
            return .default
        }
    }
}

enum CursorSoundStyle: String {
    case none
    case tick
    case click
    case engage
    case chime

    static let `default`: CursorSoundStyle = .none

    static func resolve(_ raw: String?) -> CursorSoundStyle {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "tick", "tap", "light":
            return .tick
        case "click", "press":
            return .click
        case "engage", "confirm", "modern", "cue":
            return .engage
        case "chime", "tone":
            return .chime
        case "none", "off", "false", "silent":
            return .none
        default:
            return .default
        }
    }
}

struct CursorCaption {
    let eyebrow: String
    let title: String
    let body: String?
    let tags: [String]
    let leadDuration: TimeInterval
    let soundStyle: CursorSoundStyle

    var json: JSON {
        var object: [String: JSON] = [
            "eyebrow": .string(eyebrow),
            "title": .string(title),
            "tags": .array(tags.map { .string($0) }),
            "leadMs": .int(Int((leadDuration * 1000).rounded())),
            "sound": .string(soundStyle.rawValue),
        ]
        if let body, !body.isEmpty {
            object["body"] = .string(body)
        }
        return .object(object)
    }

    static func resolve(
        params: JSON?,
        style: CursorAppearanceStyle,
        shape: CursorMarkerShape,
        markerSize: CursorMarkerSize,
        trailStyle: CursorTrailStyle,
        motionStyle: CursorMotionStyle,
        trajectoryStyle: CursorTrajectoryStyle,
        glowStyle: CursorGlowStyle,
        idleStyle: CursorIdleStyle,
        edgeStyle: CursorEdgeStyle
    ) -> CursorCaption? {
        let rawCaption = stringParam(params, ["caption", "treatmentLabel", "variant"])
        let rawTitle = stringParam(params, ["captionTitle", "caption-title"])
        let rawBody = stringParam(params, ["captionBody", "caption-body", "captionDetail", "caption-detail", "subtitle"])
        let showCaption = params?["showCaption"]?.boolValue == true
            || params?["captionPanel"]?.boolValue == true
        let disabled = rawCaption.map { value in
            ["false", "none", "off", "silent"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        } ?? false
        guard !disabled else { return nil }

        let rawMode = stringParam(params, ["captionMode", "caption-mode"])
        let normalizedCaption = rawCaption?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wantsAuto = showCaption
            || rawMode == "auto"
            || rawMode == "selection"
            || normalizedCaption == "auto"
            || normalizedCaption == "selection"
            || normalizedCaption == "selections"
            || normalizedCaption == "current"
        guard wantsAuto || rawCaption?.isEmpty == false || rawTitle?.isEmpty == false || rawBody?.isEmpty == false else {
            return nil
        }

        let title = rawTitle
            ?? (wantsAuto ? "Cursor treatment" : rawCaption)
            ?? "Lattices cue"
        let body = rawBody
            ?? (wantsAuto ? "Current selections are shown before the action runs." : nil)
        let explicitTags = splitTags(stringParam(params, ["captionTags", "caption-tags", "tags"]))
        let includeSelections = params?["captionSelections"]?.boolValue ?? true
        let tags = explicitTags.isEmpty && includeSelections
            ? selectionTags(
                style: style,
                shape: shape,
                markerSize: markerSize,
                trailStyle: trailStyle,
                motionStyle: motionStyle,
                trajectoryStyle: trajectoryStyle,
                glowStyle: glowStyle,
                idleStyle: idleStyle,
                edgeStyle: edgeStyle
            )
            : explicitTags
        let leadMs = params?["captionLeadMs"]?.numericDouble
            ?? params?["caption-lead-ms"]?.numericDouble
            ?? params?["leadMs"]?.numericDouble
        let leadDuration = max(0, min((leadMs ?? 650) / 1000, 2.5))
        let sound = CursorSoundStyle.resolve(
            stringParam(params, ["captionSound", "caption-sound", "sound", "sfx"])
        )

        return CursorCaption(
            eyebrow: stringParam(params, ["captionEyebrow", "caption-eyebrow"]) ?? "LATTICES",
            title: title,
            body: body,
            tags: tags,
            leadDuration: leadDuration,
            soundStyle: sound
        )
    }

    private static func stringParam(_ params: JSON?, _ keys: [String]) -> String? {
        for key in keys {
            guard let value = params?[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            return value
        }
        return nil
    }

    private static func splitTags(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        let tags = raw
            .split { $0 == "," || $0 == "|" || $0 == ";" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(tags.prefix(6))
    }

    private static func selectionTags(
        style: CursorAppearanceStyle,
        shape: CursorMarkerShape,
        markerSize: CursorMarkerSize,
        trailStyle: CursorTrailStyle,
        motionStyle: CursorMotionStyle,
        trajectoryStyle: CursorTrajectoryStyle,
        glowStyle: CursorGlowStyle,
        idleStyle: CursorIdleStyle,
        edgeStyle: CursorEdgeStyle
    ) -> [String] {
        if style != .marker {
            return ["style \(style.rawValue)"]
        }
        return [
            "shape \(shape.rawValue)",
            "motion \(motionStyle.rawValue)",
            "trail \(trailStyle.rawValue)",
            "snap \(edgeStyle.rawValue)",
        ]
    }
}

struct CursorAppearance {
    let style: CursorAppearanceStyle
    let color: NSColor
    let duration: TimeInterval
    let label: String?
    let caption: String?
    let captionPanel: CursorCaption?
    let soundStyle: CursorSoundStyle
    let shape: CursorMarkerShape
    let angleDeg: CGFloat
    let markerSize: CursorMarkerSize
    let trailStyle: CursorTrailStyle
    let motionStyle: CursorMotionStyle
    let trajectoryStyle: CursorTrajectoryStyle
    let glowStyle: CursorGlowStyle
    let idleStyle: CursorIdleStyle
    let edgeStyle: CursorEdgeStyle

    static let `default` = CursorAppearance(
        style: .spotlight,
        color: SpotlightConfig.accentColor,
        duration: SpotlightConfig.totalDuration,
        label: nil,
        caption: nil,
        captionPanel: nil,
        soundStyle: .default,
        shape: .default,
        angleDeg: 0,
        markerSize: .default,
        trailStyle: .default,
        motionStyle: .default,
        trajectoryStyle: .default,
        glowStyle: .default,
        idleStyle: .default,
        edgeStyle: .default
    )

    static func resolve(params: JSON?) -> CursorAppearance {
        let rawStyle = params?["appearance"]?.stringValue
            ?? params?["style"]?.stringValue
            ?? params?["cursorStyle"]?.stringValue
        let style: CursorAppearanceStyle
        switch rawStyle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pulse", "sonar":
            style = .pulse
        case "marker", "pointer", "cursor":
            style = .marker
        default:
            style = .spotlight
        }

        let color = Self.color(
            named: params?["color"]?.stringValue
                ?? params?["accent"]?.stringValue,
            style: style
        )
        let durationMs = params?["durationMs"]?.numericDouble
            ?? params?["ttlMs"]?.numericDouble
        let duration = durationMs.map { max(250, min($0, 10_000)) / 1000 }
            ?? SpotlightConfig.totalDuration
        let rawAngleDeg: Double?
        if let value = params?["angleDeg"]?.numericDouble {
            rawAngleDeg = value
        } else if let value = params?["angle-deg"]?.numericDouble {
            rawAngleDeg = value
        } else if let value = params?["rotationDeg"]?.numericDouble {
            rawAngleDeg = value
        } else if let value = params?["rotation-deg"]?.numericDouble {
            rawAngleDeg = value
        } else if let value = params?["rotation"]?.numericDouble {
            rawAngleDeg = value
        } else {
            rawAngleDeg = params?["angle"]?.numericDouble
        }
        let angleDeg = rawAngleDeg.map { max(-28, min($0, 28)) }
            ?? (style == .marker ? Double(Preferences.shared.cursorMarkerAngleDeg) : 0)
        let rawShape = params?["shape"]?.stringValue
            ?? params?["markerShape"]?.stringValue
            ?? params?["cursorShape"]?.stringValue
        let shape = rawShape == nil
            ? (style == .marker ? Preferences.shared.cursorMarkerShape : .default)
            : CursorMarkerShape.resolve(rawShape)
        let rawSize = params?["size"]?.stringValue
            ?? params?["markerSize"]?.stringValue
            ?? params?["cursorSize"]?.stringValue
        let markerSize: CursorMarkerSize
        if let rawSize, !rawSize.isEmpty {
            markerSize = CursorMarkerSize.resolve(rawSize)
        } else if let rawScale = params?["scale"]?.numericDouble
                    ?? params?["markerScale"]?.numericDouble
                    ?? params?["cursorScale"]?.numericDouble {
            markerSize = CursorMarkerSize.closest(to: rawScale)
        } else {
            markerSize = style == .marker ? Preferences.shared.cursorMarkerSize : .default
        }

        let trailStyle = CursorTrailStyle.resolve(
            params?["trail"]?.stringValue
                ?? params?["pathStyle"]?.stringValue
                ?? params?["effect"]?.stringValue
        )
        let motionStyle = CursorMotionStyle.resolve(
            params?["motion"]?.stringValue
                ?? params?["easing"]?.stringValue
                ?? params?["velocity"]?.stringValue
        )
        let trajectoryStyle = CursorTrajectoryStyle.resolve(
            params?["trajectory"]?.stringValue
                ?? params?["curve"]?.stringValue
                ?? params?["arc"]?.stringValue
        )
        let glowStyle = CursorGlowStyle.resolve(
            params?["glow"]?.stringValue
                ?? params?["bloom"]?.stringValue
        )
        let idleStyle = CursorIdleStyle.resolve(
            params?["idle"]?.stringValue
                ?? params?["settle"]?.stringValue
                ?? params?["presence"]?.stringValue
        )
        let edgeStyle = CursorEdgeStyle.resolve(
            params?["edge"]?.stringValue
                ?? params?["edgeEffect"]?.stringValue
                ?? params?["arrival"]?.stringValue
        )
        let captionText = params?["caption"]?.stringValue
            ?? params?["treatmentLabel"]?.stringValue
            ?? params?["variant"]?.stringValue
        let captionPanel = CursorCaption.resolve(
            params: params,
            style: style,
            shape: shape,
            markerSize: markerSize,
            trailStyle: trailStyle,
            motionStyle: motionStyle,
            trajectoryStyle: trajectoryStyle,
            glowStyle: glowStyle,
            idleStyle: idleStyle,
            edgeStyle: edgeStyle
        )

        return CursorAppearance(
            style: style,
            color: color,
            duration: duration,
            label: params?["label"]?.stringValue,
            caption: captionText,
            captionPanel: captionPanel,
            soundStyle: CursorSoundStyle.resolve(
                params?["sound"]?.stringValue
                    ?? params?["sfx"]?.stringValue
            ),
            shape: shape,
            angleDeg: CGFloat(angleDeg),
            markerSize: markerSize,
            trailStyle: trailStyle,
            motionStyle: motionStyle,
            trajectoryStyle: trajectoryStyle,
            glowStyle: glowStyle,
            idleStyle: idleStyle,
            edgeStyle: edgeStyle
        )
    }

    var json: JSON {
        var object: [String: JSON] = [
            "style": .string(style.rawValue),
            "durationMs": .int(Int((duration * 1000).rounded())),
            "color": .string(color.hexString),
        ]
        if style == .marker {
            object["shape"] = .string(shape.rawValue)
            object["angleDeg"] = .double(Double(angleDeg))
            object["size"] = .string(markerSize.rawValue)
            object["scale"] = .double(Double(markerSize.scale))
            object["trail"] = .string(trailStyle.rawValue)
            object["motion"] = .string(motionStyle.rawValue)
            object["trajectory"] = .string(trajectoryStyle.rawValue)
            object["glow"] = .string(glowStyle.rawValue)
            object["idle"] = .string(idleStyle.rawValue)
            object["edge"] = .string(edgeStyle.rawValue)
        }
        if let label, !label.isEmpty {
            object["label"] = .string(label)
        }
        if let caption, !caption.isEmpty {
            object["caption"] = .string(caption)
        }
        if let captionPanel {
            object["captionPanel"] = captionPanel.json
        }
        if soundStyle != .none {
            object["sound"] = .string(soundStyle.rawValue)
        }
        return .object(object)
    }

    private static func color(named raw: String?, style: CursorAppearanceStyle) -> NSColor {
        let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let parsed = colorFromHex(normalized) {
            return parsed
        }

        switch normalized {
        case "green", "success":
            return NSColor(calibratedRed: 0.25, green: 0.90, blue: 0.55, alpha: 1.0)
        case "pearl", "ivory", "warm-white":
            return NSColor(calibratedRed: 0.92, green: 0.90, blue: 0.84, alpha: 1.0)
        case "mist", "off-white", "offwhite":
            return NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.90, alpha: 1.0)
        case "ash", "gray", "grey":
            return NSColor(calibratedRed: 0.68, green: 0.70, blue: 0.72, alpha: 1.0)
        case "graphite":
            return NSColor(calibratedRed: 0.46, green: 0.48, blue: 0.50, alpha: 1.0)
        case "amber", "yellow":
            return NSColor(calibratedRed: 1.00, green: 0.75, blue: 0.22, alpha: 1.0)
        case "pink", "magenta":
            return NSColor(calibratedRed: 1.00, green: 0.35, blue: 0.70, alpha: 1.0)
        case "red", "danger":
            return NSColor(calibratedRed: 1.00, green: 0.32, blue: 0.26, alpha: 1.0)
        case "white":
            return NSColor.white
        default:
            if style == .marker {
                return NSColor(calibratedRed: 0.92, green: 0.90, blue: 0.84, alpha: 1.0)
            }
            return SpotlightConfig.accentColor
        }
    }

    private static func colorFromHex(_ raw: String?) -> NSColor? {
        guard var raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6, let value = Int(raw, radix: 16) else { return nil }
        return NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1.0
        )
    }
}

private extension NSColor {
    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

private struct DotMatrixConfig {
    var dotRadius: CGFloat = 2.2
    var dotSpacing: CGFloat = 6.0
    var arrowCols: Int = 13
    var arrowRows: Int = 7   // must be odd

    static let shared: DotMatrixConfig = {
        let path = NSHomeDirectory() + "/.lattices/mouse-finder.json"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return DotMatrixConfig() }

        var config = DotMatrixConfig()
        if let v = json["dotRadius"] as? Double { config.dotRadius = CGFloat(v) }
        if let v = json["dotSpacing"] as? Double { config.dotSpacing = CGFloat(v) }
        if let v = json["arrowCols"] as? Int { config.arrowCols = max(3, v) }
        if let v = json["arrowRows"] as? Int { config.arrowRows = max(3, v | 1) }
        return config
    }()

    func generatePattern() -> [(col: Int, row: Int)] {
        let center = arrowRows / 2
        let shaftHalf = center / 2
        var dots: [(Int, Int)] = []

        for r in 0..<arrowRows {
            let d = abs(r - center)
            if d <= shaftHalf {
                for c in 0...(arrowCols - 1 - d) { dots.append((c, r)) }
            } else {
                let headTip = arrowCols - 1 - d
                let headStart = max(0, headTip - 1)
                for c in headStart...headTip { dots.append((c, r)) }
            }
        }
        return dots
    }
}

/// Locates the mouse cursor with a spotlight + sonar pulse effect.
/// Dims all screens, spotlights the cursor area, shows directional arrows on off-screens,
/// then plays sonar rings on top.
final class MouseFinder {
    static let shared = MouseFinder()

    private var overlayWindows: [NSWindow] = []
    private var sonarWindows: [NSWindow] = []
    private var markerWindows: [NSWindow] = []
    private var captionWindows: [NSWindow] = []
    private var dismissTimer: Timer?
    private var animationTimer: Timer?
    private var sonarDelayTimer: Timer?
    private var animationStart: CFTimeInterval = 0
    private let animationDuration: CFTimeInterval = 1.5
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    // MARK: - Find (highlight current position)

    func find(appearance: CursorAppearance = .default) {
        let pos = NSEvent.mouseLocation
        showAppearance(at: pos, mode: .find, appearance: appearance)
    }

    func showCursor(at point: CGPoint? = nil, appearance: CursorAppearance = .default) {
        showAppearance(at: point ?? NSEvent.mouseLocation, mode: .find, appearance: appearance)
    }

    func animateCursor(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        appearance: CursorAppearance = .default,
        captionTopLeft: CGPoint? = nil
    ) {
        dismiss()
        installEventMonitors()

        let markerWindow = makeMarkerWindow(at: startPoint, appearance: appearance)
        let markerSide = markerWindow?.frame.width ?? (112 * appearance.markerSize.scale)
        let padding = max(180, markerSide * 1.35)
        let pathFrame = CGRect(
            x: min(startPoint.x, endPoint.x) - padding,
            y: min(startPoint.y, endPoint.y) - padding,
            width: abs(endPoint.x - startPoint.x) + padding * 2,
            height: abs(endPoint.y - startPoint.y) + padding * 2
        )
        let captionLead = appearance.captionPanel?.leadDuration ?? 0
        presentCaptionIfNeeded(
            appearance: appearance,
            near: startPoint,
            topLeft: captionTopLeft
        )
        let trailLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        let trailWindow = makeOverlayWindow(frame: pathFrame, level: trailLevel)
        let trailView = GhostCursorPathView(
            frame: NSRect(origin: .zero, size: pathFrame.size),
            start: CGPoint(x: startPoint.x - pathFrame.origin.x, y: startPoint.y - pathFrame.origin.y),
            end: CGPoint(x: endPoint.x - pathFrame.origin.x, y: endPoint.y - pathFrame.origin.y),
            color: appearance.color,
            trailStyle: appearance.trailStyle,
            trajectoryStyle: appearance.trajectoryStyle,
            glowStyle: appearance.glowStyle,
            caption: nil
        )
        trailWindow.contentView = trailView
        trailWindow.alphaValue = 0
        trailWindow.orderFrontRegardless()
        overlayWindows.append(trailWindow)

        if let markerWindow {
            markerWindow.alphaValue = 0
            markerWindow.orderFrontRegardless()
            markerWindows.append(markerWindow)
        }

        let motionDuration = max(
            appearance.motionStyle.minimumDuration,
            min(appearance.motionStyle.maximumDuration, appearance.duration * appearance.motionStyle.motionFraction)
        )
        var motionVisible = false
        var arrivalSoundPlayed = false
        animationStart = CACurrentMediaTime()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak markerWindow, weak trailView] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let elapsedSinceStart = CACurrentMediaTime() - self.animationStart
            let elapsed = max(0, elapsedSinceStart - captionLead)
            if !motionVisible, elapsedSinceStart >= captionLead {
                motionVisible = true
                CursorSoundPlayer.shared.play(appearance.soundStyle)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.10
                    trailWindow.animator().alphaValue = 1.0
                    markerWindow?.animator().alphaValue = 1.0
                }
            }
            let linearProgress = CGFloat(min(elapsed / motionDuration, 1.0))
            let eased = Self.ease(linearProgress, style: appearance.motionStyle)
            let current = GhostCursorCurve.point(
                t: eased,
                start: startPoint,
                end: endPoint,
                trajectoryStyle: appearance.trajectoryStyle
            )

            if let markerWindow {
                markerWindow.setFrame(
                    CGRect(
                        x: current.x - markerSide / 2,
                        y: current.y - markerSide / 2,
                        width: markerSide,
                        height: markerSide
                    ),
                    display: true
                )
            }

            if let markerView = markerWindow?.contentView as? CursorMarkerView {
                markerView.phase = CGFloat(elapsed)
                markerView.motionProgress = linearProgress
                markerView.edgeEnergy = Self.edgeEnergy(
                    elapsed: elapsed,
                    linearProgress: linearProgress,
                    motionDuration: motionDuration,
                    edgeStyle: appearance.edgeStyle
                )
                markerView.needsDisplay = true
            }

            trailView?.progress = eased
            trailView?.needsDisplay = true

            if !arrivalSoundPlayed, linearProgress >= 1.0 {
                arrivalSoundPlayed = true
                if appearance.soundStyle == .engage {
                    CursorSoundPlayer.shared.play(.tick)
                }
            }

            if elapsed >= appearance.duration {
                timer.invalidate()
                self.animationTimer = nil
            }
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: appearance.duration + captionLead, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
    }

    // MARK: - Summon (warp to center of the screen the mouse is on, or a specific point)

    func summon(to point: CGPoint? = nil, appearance: CursorAppearance = .default) {
        let target: NSPoint
        if let point {
            target = point
        } else {
            let screen = mouseScreen()
            let frame = screen.frame
            target = NSPoint(x: frame.midX, y: frame.midY)
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = CGPoint(x: target.x, y: primaryHeight - target.y)
        CGWarpMouseCursorPosition(cgPoint)
        CGAssociateMouseAndMouseCursorPosition(1)

        showAppearance(at: target, mode: .summon, appearance: appearance)
    }

    // MARK: - Spotlight Effect

    private func showAppearance(at nsPoint: NSPoint, mode: SpotlightMode, appearance: CursorAppearance) {
        switch appearance.style {
        case .spotlight:
            showSpotlight(at: nsPoint, mode: mode, appearance: appearance)
            presentCaptionIfNeeded(appearance: appearance, near: nsPoint, topLeft: nil)
        case .pulse:
            dismiss()
            installEventMonitors()
            showSonar(at: nsPoint, appearance: appearance)
            presentCaptionIfNeeded(appearance: appearance, near: nsPoint, topLeft: nil)
            dismissTimer = Timer.scheduledTimer(withTimeInterval: appearance.duration, repeats: false) { [weak self] _ in
                self?.fadeOut()
            }
        case .marker:
            dismiss()
            installEventMonitors()
            showMarker(at: nsPoint, appearance: appearance)
            presentCaptionIfNeeded(appearance: appearance, near: nsPoint, topLeft: nil)
            dismissTimer = Timer.scheduledTimer(withTimeInterval: appearance.duration, repeats: false) { [weak self] _ in
                self?.fadeOut()
            }
        }
    }

    private func showSpotlight(at nsPoint: NSPoint, mode: SpotlightMode = .find, appearance: CursorAppearance) {
        dismiss()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let cursorScreen = screens.first(where: { $0.frame.contains(nsPoint) }) ?? screens[0]
        let otherScreens = screens.filter { $0 !== cursorScreen }
        let windowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))

        // Spotlight overlay on cursor screen
        let localCursor = NSPoint(
            x: nsPoint.x - cursorScreen.frame.origin.x,
            y: nsPoint.y - cursorScreen.frame.origin.y
        )
        let spotlightWindow = makeOverlayWindow(frame: cursorScreen.frame, level: windowLevel)
        spotlightWindow.contentView = SpotlightView(
            frame: NSRect(origin: .zero, size: cursorScreen.frame.size),
            cursorPoint: localCursor,
            mode: mode,
            appearance: appearance
        )
        overlayWindows.append(spotlightWindow)

        // Dim overlays with directional arrows on other screens
        for screen in otherScreens {
            let screenCenter = NSPoint(
                x: screen.frame.midX,
                y: screen.frame.midY
            )
            let angle = atan2(nsPoint.y - screenCenter.y, nsPoint.x - screenCenter.x)

            let dimWindow = makeOverlayWindow(frame: screen.frame, level: windowLevel)
            dimWindow.contentView = DimOverlayView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                cursorAngle: angle,
                appearance: appearance
            )
            overlayWindows.append(dimWindow)
        }

        // Fade all in
        for window in overlayWindows {
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = SpotlightConfig.fadeInDuration
                window.animator().alphaValue = 1.0
            }
        }

        installEventMonitors()

        // Start sonar after delay
        sonarDelayTimer = Timer.scheduledTimer(withTimeInterval: SpotlightConfig.sonarDelay, repeats: false) { [weak self] _ in
            self?.showSonar(at: nsPoint, appearance: appearance)
        }

        // Auto-dismiss
        dismissTimer = Timer.scheduledTimer(withTimeInterval: appearance.duration, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
    }

    // MARK: - Sonar Animation (plays on top of spotlight)

    private func showSonar(at nsPoint: NSPoint, appearance: CursorAppearance) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let ringCount = 3
        let maxRadius: CGFloat = 120
        let totalSize = maxRadius * 2 + 20
        let sonarLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)

        for screen in screens {
            let extendedBounds = screen.frame.insetBy(dx: -maxRadius, dy: -maxRadius)
            guard extendedBounds.contains(nsPoint) else { continue }

            let windowFrame = NSRect(
                x: nsPoint.x - totalSize / 2,
                y: nsPoint.y - totalSize / 2,
                width: totalSize,
                height: totalSize
            )

            let window = NSWindow(
                contentRect: windowFrame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = sonarLevel
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]

            let sonarView = SonarView(
                frame: NSRect(origin: .zero, size: windowFrame.size),
                ringCount: ringCount,
                maxRadius: maxRadius,
                color: appearance.color
            )
            window.contentView = sonarView

            window.alphaValue = 0
            window.orderFrontRegardless()
            sonarWindows.append(window)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                window.animator().alphaValue = 1.0
            }
        }

        animationStart = CACurrentMediaTime()
        let interval = 1.0 / 60.0

        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let elapsed = CACurrentMediaTime() - self.animationStart
            let progress = CGFloat(min(elapsed / self.animationDuration, 1.0))

            for window in self.sonarWindows {
                (window.contentView as? SonarView)?.progress = progress
                window.contentView?.needsDisplay = true
            }

            if progress >= 1.0 {
                timer.invalidate()
                self.animationTimer = nil
            }
        }
    }

    private func showMarker(at nsPoint: NSPoint, appearance: CursorAppearance) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        for screen in screens {
            let markerSide = 112 * appearance.markerSize.scale
            let markerSize = CGSize(width: markerSide, height: markerSide)
            let extendedBounds = screen.frame.insetBy(dx: -markerSize.width, dy: -markerSize.height)
            guard extendedBounds.contains(nsPoint) else { continue }

            guard let window = makeMarkerWindow(at: nsPoint, appearance: appearance) else { continue }
            window.alphaValue = 0
            window.orderFrontRegardless()
            markerWindows.append(window)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                window.animator().alphaValue = 1.0
            }
        }

        startMarkerIdleAnimation(appearance: appearance)
    }

    private func startMarkerIdleAnimation(appearance: CursorAppearance) {
        guard !markerWindows.isEmpty else { return }

        animationStart = CACurrentMediaTime()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let elapsed = CACurrentMediaTime() - self.animationStart
            for window in self.markerWindows {
                guard let markerView = window.contentView as? CursorMarkerView else { continue }
                markerView.phase = CGFloat(elapsed)
                markerView.motionProgress = 1
                markerView.edgeEnergy = Self.edgeEnergy(
                    elapsed: elapsed,
                    linearProgress: 1,
                    motionDuration: 0,
                    edgeStyle: appearance.edgeStyle
                )
                markerView.needsDisplay = true
            }

            if elapsed >= appearance.duration {
                timer.invalidate()
                self.animationTimer = nil
            }
        }
    }

    private func makeMarkerWindow(at nsPoint: NSPoint, appearance: CursorAppearance) -> NSWindow? {
        let markerLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 2)
        let markerSide = 112 * appearance.markerSize.scale
        let markerSize = CGSize(width: markerSide, height: markerSide)
        let windowFrame = NSRect(
            x: nsPoint.x - markerSize.width / 2,
            y: nsPoint.y - markerSize.height / 2,
            width: markerSize.width,
            height: markerSize.height
        )
        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = markerLevel
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = CursorMarkerView(
            frame: NSRect(origin: .zero, size: markerSize),
            color: appearance.color,
            label: appearance.label,
            shape: appearance.shape,
            angleDeg: appearance.angleDeg,
            markerScale: appearance.markerSize.scale,
            glowStyle: appearance.glowStyle,
            idleStyle: appearance.idleStyle,
            edgeStyle: appearance.edgeStyle
        )
        return window
    }

    private func presentCaptionIfNeeded(
        appearance: CursorAppearance,
        near point: CGPoint,
        topLeft: CGPoint?
    ) {
        guard let caption = appearance.captionPanel,
              let window = makeCaptionWindow(caption: caption, topLeft: topLeft, near: point, color: appearance.color)
        else { return }

        captionWindows.append(window)
        window.alphaValue = 0
        window.orderFrontRegardless()
        CursorSoundPlayer.shared.play(caption.soundStyle)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            window.animator().alphaValue = 1.0
        }
    }

    private func makeCaptionWindow(
        caption: CursorCaption,
        topLeft: CGPoint?,
        near point: CGPoint,
        color: NSColor
    ) -> NSWindow? {
        let size = DemoCaptionView.preferredSize(for: caption)
        let clampedTopLeft = captionTopLeft(topLeft, near: point, size: size)
        let frame = CGRect(
            x: clampedTopLeft.x,
            y: clampedTopLeft.y - size.height,
            width: size.width,
            height: size.height
        )
        let captionLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 4)
        let window = makeOverlayWindow(frame: frame, level: captionLevel)
        window.hasShadow = true
        window.contentView = DemoCaptionView(
            frame: NSRect(origin: .zero, size: size),
            caption: caption,
            accentColor: color
        )
        return window
    }

    private func captionTopLeft(_ requested: CGPoint?, near point: CGPoint, size: CGSize) -> CGPoint {
        let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -80, dy: -80).contains(point) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 24
        let preferred = requested ?? CGPoint(
            x: visibleFrame.minX + margin,
            y: visibleFrame.maxY - margin
        )
        return CGPoint(
            x: max(visibleFrame.minX + margin, min(preferred.x, visibleFrame.maxX - size.width - margin)),
            y: max(visibleFrame.minY + size.height + margin, min(preferred.y, visibleFrame.maxY - margin))
        )
    }

    // MARK: - Lifecycle

    private func fadeOut() {
        let allWindows = overlayWindows + sonarWindows + markerWindows + captionWindows
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = SpotlightConfig.fadeOutDuration
            for window in allWindows {
                window.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            self?.dismiss()
        })
    }

    func dismiss() {
        removeEventMonitors()
        animationTimer?.invalidate()
        animationTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        sonarDelayTimer?.invalidate()
        sonarDelayTimer = nil
        for window in overlayWindows + sonarWindows + markerWindows + captionWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        sonarWindows.removeAll()
        markerWindows.removeAll()
        captionWindows.removeAll()
    }

    // MARK: - Event Monitors

    private func installEventMonitors() {
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] _ in
            self?.dismiss()
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            self?.dismiss()
            return event
        }
    }

    private func removeEventMonitors() {
        if let m = globalEventMonitor { NSEvent.removeMonitor(m); globalEventMonitor = nil }
        if let m = localEventMonitor { NSEvent.removeMonitor(m); localEventMonitor = nil }
    }

    // MARK: - Helpers

    private func makeOverlayWindow(frame: NSRect, level: NSWindow.Level) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = level
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        return window
    }

    private static func ease(_ t: CGFloat, style: CursorMotionStyle) -> CGFloat {
        switch style {
        case .glide:
            return easeInOutCubic(t)
        case .snap:
            return 1 - pow(1 - t, 3)
        case .float:
            return 0.5 - cos(t * .pi) / 2
        case .rush:
            return 1 - pow(1 - t, 5)
        case .crawl:
            return t < 0.5
                ? 2 * t * t
                : 1 - pow(-2 * t + 2, 2) / 2
        case .accelerate:
            return pow(t, 2.35)
        case .teleport:
            if t < 0.46 {
                return (1 - pow(1 - t / 0.46, 3)) * 0.22
            }
            if t < 0.54 {
                return 0.78
            }
            let tail = (t - 0.54) / 0.46
            return 0.78 + (1 - pow(1 - tail, 3)) * 0.22
        case .spring:
            let base = 1 - pow(1 - t, 3)
            let bounce = sin(t * .pi * 4.0) * pow(1 - t, 2.2) * 0.18
            return base + bounce
        case .magnet:
            if t < 0.68 {
                let crawl = t / 0.68
                return pow(crawl, 1.75) * 0.58
            }
            let tail = (t - 0.68) / 0.32
            return 0.58 + (1 - pow(1 - tail, 4)) * 0.42
        case .slingshot:
            if t < 0.18 {
                return -0.055 * sin(t / 0.18 * .pi)
            }
            let tail = (t - 0.18) / 0.82
            return 1 - pow(1 - tail, 3.4)
        }
    }

    private static func edgeEnergy(
        elapsed: CFTimeInterval,
        linearProgress: CGFloat,
        motionDuration: CFTimeInterval,
        edgeStyle: CursorEdgeStyle
    ) -> CGFloat {
        guard edgeStyle != .none else { return 0 }

        let startEnergy = max(0, 1 - linearProgress / 0.12)
        let arrivalElapsed = CGFloat(max(0, elapsed - motionDuration))
        let arrivalEnergy = max(0, 1 - arrivalElapsed / 0.52)
        return max(startEnergy, linearProgress >= 1 ? arrivalEnergy : 0)
    }

    private static func easeInOutCubic(_ t: CGFloat) -> CGFloat {
        if t < 0.5 {
            return 4 * t * t * t
        }
        return 1 - pow(-2 * t + 2, 3) / 2
    }

    private func mouseScreen() -> NSScreen {
        let pos = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pos) }) ?? NSScreen.screens[0]
    }
}

// MARK: - Spotlight View (radial gradient cutout on cursor screen)

enum SpotlightMode {
    case find    // single arrow at screen center pointing TO the cursor
    case summon  // four arrows around the cursor pointing INWARD ("conjured here")
}

private class SpotlightView: NSView {
    let cursorPoint: CGPoint
    let mode: SpotlightMode
    let cursorAppearance: CursorAppearance
    private let config = DotMatrixConfig.shared
    private lazy var dotPattern = config.generatePattern()

    init(frame: NSRect, cursorPoint: CGPoint, mode: SpotlightMode = .find, appearance: CursorAppearance) {
        self.cursorPoint = cursorPoint
        self.mode = mode
        self.cursorAppearance = appearance
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.black.withAlphaComponent(SpotlightConfig.overlayAlpha).cgColor)
        ctx.fill(bounds)

        // Punch a radial gradient hole using destinationOut blend mode
        ctx.setBlendMode(.destinationOut)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let components: [CGFloat] = [
            1, 1, 1, 1.0,
            1, 1, 1, 0.8,
            1, 1, 1, 0.0,
        ]
        let locations: [CGFloat] = [0.0, 0.3, 1.0]

        guard let gradient = CGGradient(
            colorSpace: colorSpace,
            colorComponents: components,
            locations: locations,
            count: 3
        ) else { return }

        ctx.drawRadialGradient(
            gradient,
            startCenter: cursorPoint,
            startRadius: 0,
            endCenter: cursorPoint,
            endRadius: SpotlightConfig.spotlightRadius,
            options: []
        )

        ctx.setBlendMode(.normal)

        switch mode {
        case .find:
            // Single arrow at screen center pointing toward the cursor.
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let angle = atan2(cursorPoint.y - center.y, cursorPoint.x - center.x)
            drawDotMatrixArrow(in: ctx, at: center, angle: angle)

        case .summon:
            // Four arrows around the cursor, all heads pointing inward toward it —
            // the visual joke is that the mouse was just summoned here, so everything
            // is converging on the new cursor position.
            let arrowLen = CGFloat(config.arrowCols - 1) * config.dotSpacing
            let offset = arrowLen / 2 + SpotlightConfig.spotlightRadius * 0.55
            let placements: [(CGPoint, CGFloat)] = [
                (CGPoint(x: cursorPoint.x, y: cursorPoint.y + offset), -.pi / 2), // above → points down
                (CGPoint(x: cursorPoint.x, y: cursorPoint.y - offset),  .pi / 2), // below → points up
                (CGPoint(x: cursorPoint.x - offset, y: cursorPoint.y),  0),       // left  → points right
                (CGPoint(x: cursorPoint.x + offset, y: cursorPoint.y),  .pi),     // right → points left
            ]
            for (origin, angle) in placements {
                drawDotMatrixArrow(in: ctx, at: origin, angle: angle)
            }
        }
    }

    private func drawDotMatrixArrow(in ctx: CGContext, at point: CGPoint, angle: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: point.x, y: point.y)
        ctx.rotate(by: angle)

        let originX = -CGFloat(config.arrowCols - 1) * config.dotSpacing / 2
        let originY = -CGFloat(config.arrowRows - 1) * config.dotSpacing / 2

        for (col, row) in dotPattern {
            let x = originX + CGFloat(col) * config.dotSpacing
            let y = originY + CGFloat(row) * config.dotSpacing

            let t = CGFloat(col) / CGFloat(max(1, config.arrowCols - 1))
            let alpha = 0.35 + t * 0.5

            ctx.setFillColor(cursorAppearance.color.withAlphaComponent(alpha).cgColor)
            ctx.fillEllipse(in: CGRect(
                x: x - config.dotRadius,
                y: y - config.dotRadius,
                width: config.dotRadius * 2,
                height: config.dotRadius * 2
            ))
        }

        ctx.restoreGState()
    }
}

// MARK: - Dim Overlay View (dark fill + dot matrix arrow centered on off-screens)

private class DimOverlayView: NSView {
    let cursorAngle: CGFloat
    let cursorAppearance: CursorAppearance
    private let config = DotMatrixConfig.shared
    private lazy var dotPattern = config.generatePattern()

    init(frame: NSRect, cursorAngle: CGFloat, appearance: CursorAppearance) {
        self.cursorAngle = cursorAngle
        self.cursorAppearance = appearance
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.black.withAlphaComponent(SpotlightConfig.dimAlpha).cgColor)
        ctx.fill(bounds)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: cursorAngle)

        let originX = -CGFloat(config.arrowCols - 1) * config.dotSpacing / 2
        let originY = -CGFloat(config.arrowRows - 1) * config.dotSpacing / 2

        for (col, row) in dotPattern {
            let x = originX + CGFloat(col) * config.dotSpacing
            let y = originY + CGFloat(row) * config.dotSpacing

            let t = CGFloat(col) / CGFloat(max(1, config.arrowCols - 1))
            let alpha = 0.35 + t * 0.5

            ctx.setFillColor(cursorAppearance.color.withAlphaComponent(alpha).cgColor)
            ctx.fillEllipse(in: CGRect(
                x: x - config.dotRadius,
                y: y - config.dotRadius,
                width: config.dotRadius * 2,
                height: config.dotRadius * 2
            ))
        }

        ctx.restoreGState()
    }
}

// MARK: - Sonar Ring View

private class SonarView: NSView {
    let ringCount: Int
    let maxRadius: CGFloat
    let color: NSColor
    var progress: CGFloat = 0

    init(frame: NSRect, ringCount: Int, maxRadius: CGFloat, color: NSColor) {
        self.ringCount = ringCount
        self.maxRadius = maxRadius
        self.color = color
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        for i in 0..<ringCount {
            let ringDelay = CGFloat(i) * 0.15
            let denom = 1.0 - ringDelay * CGFloat(ringCount - 1) / CGFloat(ringCount)
            let ringProgress = max(0, min(1, (progress - ringDelay) / denom))

            guard ringProgress > 0 else { continue }

            let eased = 1.0 - pow(1.0 - ringProgress, 3)
            let radius = maxRadius * eased
            let alpha = (1.0 - eased) * 0.8

            ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(2.5 - CGFloat(i) * 0.5)
            ctx.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            ctx.strokePath()
        }

        let dotRadius: CGFloat = 6
        let dotAlpha = max(0.3, 1.0 - progress * 0.5)
        ctx.setFillColor(color.withAlphaComponent(dotAlpha).cgColor)
        ctx.fillEllipse(in: CGRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))

        ctx.setFillColor(color.withAlphaComponent(dotAlpha * 0.2).cgColor)
        let glowRadius: CGFloat = 12
        ctx.fillEllipse(in: CGRect(
            x: center.x - glowRadius,
            y: center.y - glowRadius,
            width: glowRadius * 2,
            height: glowRadius * 2
        ))
    }
}

private enum GhostCursorCurve {
    static func sampledPoints(
        count: Int,
        start: CGPoint,
        end: CGPoint,
        trajectoryStyle: CursorTrajectoryStyle
    ) -> [CGPoint] {
        (0..<count).map { idx in
            let t = CGFloat(idx) / CGFloat(max(1, count - 1))
            return point(t: t, start: start, end: end, trajectoryStyle: trajectoryStyle)
        }
    }

    static func point(
        t: CGFloat,
        start: CGPoint,
        end: CGPoint,
        trajectoryStyle: CursorTrajectoryStyle
    ) -> CGPoint {
        if trajectoryStyle == .overshoot {
            return overshootPoint(t: t, start: start, end: end)
        }

        let controls = controlPoints(start: start, end: end, trajectoryStyle: trajectoryStyle)
        return cubicPoint(t: t, p0: start, p1: controls.c1, p2: controls.c2, p3: end)
    }

    private static func overshootPoint(t: CGFloat, start: CGPoint, end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = max(1, hypot(dx, dy))
        let overshootDistance = min(92, max(28, distance * 0.10))
        let beyond = CGPoint(
            x: end.x + dx / distance * overshootDistance,
            y: end.y + dy / distance * overshootDistance
        )

        if t < 0.78 {
            let outboundT = t / 0.78
            let controls = controlPoints(start: start, end: beyond, trajectoryStyle: .arc)
            return cubicPoint(t: outboundT, p0: start, p1: controls.c1, p2: controls.c2, p3: beyond)
        }

        let settleT = min(1, (t - 0.78) / 0.22)
        let eased = 1 - pow(1 - settleT, 4)
        return CGPoint(
            x: beyond.x + (end.x - beyond.x) * eased,
            y: beyond.y + (end.y - beyond.y) * eased
        )
    }

    private static func controlPoints(
        start: CGPoint,
        end: CGPoint,
        trajectoryStyle: CursorTrajectoryStyle
    ) -> (c1: CGPoint, c2: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        let bend = max(52, min(160, distance * 0.18)) * trajectoryStyle.bendScale
        let normal = CGPoint(x: -dy, y: dx)
        let normalLength = max(1, hypot(normal.x, normal.y))
        let offset = CGPoint(x: normal.x / normalLength * bend, y: normal.y / normalLength * bend)
        return (
            CGPoint(x: start.x + dx * 0.30 + offset.x, y: start.y + dy * 0.16 + offset.y),
            CGPoint(x: start.x + dx * 0.74 + offset.x * 0.34, y: start.y + dy * 0.86 + offset.y * 0.34)
        )
    }

    private static func cubicPoint(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
        let mt = 1 - t
        let mt2 = mt * mt
        let t2 = t * t
        let a = mt2 * mt
        let b = 3 * mt2 * t
        let c = 3 * mt * t2
        let d = t2 * t
        return CGPoint(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }
}

private final class DemoCaptionView: NSView {
    private let caption: CursorCaption
    private let accentColor: NSColor
    private let inset: CGFloat = 15

    init(frame: NSRect, caption: CursorCaption, accentColor: NSColor) {
        self.caption = caption
        self.accentColor = accentColor
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func preferredSize(for caption: CursorCaption) -> CGSize {
        let width: CGFloat = 388
        let bodyHeight = caption.body?.isEmpty == false ? CGFloat(32) : 0
        let tagRows = caption.tags.isEmpty ? 0 : max(1, Int(ceil(Double(min(caption.tags.count, 6)) / 3.0)))
        let tagsHeight = CGFloat(tagRows) * 24
        return CGSize(width: width, height: 72 + bodyHeight + tagsHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let panel = bounds.insetBy(dx: 1, dy: 1)

        ctx.saveGState()
        let shadowColor = NSColor.black.withAlphaComponent(0.22).cgColor
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: shadowColor)
        NSColor(calibratedWhite: 0.045, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 10, yRadius: 10).fill()
        ctx.restoreGState()

        NSColor(calibratedWhite: 1.0, alpha: 0.08).setStroke()
        let border = NSBezierPath(roundedRect: panel.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        border.lineWidth = 1
        border.stroke()

        drawText(
            caption.eyebrow.uppercased(),
            rect: CGRect(x: inset, y: panel.maxY - 23, width: panel.width - inset * 2, height: 13),
            font: .monospacedSystemFont(ofSize: 8.5, weight: .medium),
            color: NSColor(calibratedWhite: 0.74, alpha: 0.92),
            kern: 1.2
        )
        drawText(
            caption.title,
            rect: CGRect(x: inset, y: panel.maxY - 47, width: panel.width - inset * 2, height: 22),
            font: .systemFont(ofSize: 16, weight: .medium),
            color: NSColor(calibratedWhite: 0.96, alpha: 0.98),
            kern: 0
        )

        var tagTop = panel.maxY - 63
        if let body = caption.body, !body.isEmpty {
            drawText(
                body,
                rect: CGRect(x: inset, y: panel.maxY - 79, width: panel.width - inset * 2, height: 28),
                font: .systemFont(ofSize: 11.5, weight: .regular),
                color: NSColor(calibratedWhite: 0.80, alpha: 0.94),
                kern: 0,
                lineBreakMode: .byWordWrapping
            )
            tagTop = panel.maxY - 96
        }

        drawTags(topY: tagTop)
    }

    private func drawText(
        _ string: String,
        rect: CGRect,
        font: NSFont,
        color: NSColor,
        kern: CGFloat,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineBreakMode
        let text = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .kern: kern,
        ])
        text.draw(in: rect)
    }

    private func drawTags(topY: CGFloat) {
        guard !caption.tags.isEmpty else { return }
        let font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
        let rowHeight: CGFloat = 20
        let gap: CGFloat = 6
        let maxX = bounds.maxX - inset
        var x = inset
        var y = topY - rowHeight

        for tag in caption.tags.prefix(6) {
            let text = NSAttributedString(string: tag, attributes: [
                .font: font,
                .foregroundColor: NSColor(calibratedWhite: 0.86, alpha: 0.92),
            ])
            let width = min(max(52, text.size().width + 16), bounds.width - inset * 2)
            if x + width > maxX {
                x = inset
                y -= rowHeight + 4
            }
            let pill = CGRect(x: x, y: y, width: width, height: rowHeight)
            NSColor(calibratedWhite: 1.0, alpha: 0.055).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
            NSColor(calibratedWhite: 1.0, alpha: 0.055).setStroke()
            let border = NSBezierPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            border.lineWidth = 1
            border.stroke()
            text.draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 4))
            x += width + gap
        }
    }
}

private final class CursorSoundPlayer {
    static let shared = CursorSoundPlayer()

    private var activeSounds: [NSSound] = []
    private let sampleRate = 44_100

    func play(_ style: CursorSoundStyle) {
        guard style != .none else { return }
        let data = wavData(for: style)
        guard let sound = NSSound(data: data) else { return }
        sound.volume = volume(for: style)
        activeSounds.append(sound)
        sound.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak sound] in
            guard let sound else { return }
            self?.activeSounds.removeAll { $0 === sound }
        }
    }

    private func volume(for style: CursorSoundStyle) -> Float {
        switch style {
        case .none:
            return 0
        case .tick:
            return 0.22
        case .click:
            return 0.26
        case .engage:
            return 0.32
        case .chime:
            return 0.30
        }
    }

    private func wavData(for style: CursorSoundStyle) -> Data {
        let tones: [(frequency: Double, start: Double, duration: Double, amplitude: Double)]
        let duration: Double
        switch style {
        case .none:
            tones = []
            duration = 0.01
        case .tick:
            tones = [(920, 0.00, 0.055, 0.28)]
            duration = 0.08
        case .click:
            tones = [(1240, 0.00, 0.032, 0.34), (540, 0.018, 0.055, 0.18)]
            duration = 0.09
        case .engage:
            tones = [(420, 0.00, 0.11, 0.20), (760, 0.055, 0.13, 0.24), (1160, 0.12, 0.06, 0.12)]
            duration = 0.22
        case .chime:
            tones = [(620, 0.00, 0.18, 0.18), (930, 0.03, 0.20, 0.16)]
            duration = 0.25
        }

        let sampleCount = max(1, Int(duration * Double(sampleRate)))
        var samples: [Int16] = []
        samples.reserveCapacity(sampleCount)

        for index in 0..<sampleCount {
            let t = Double(index) / Double(sampleRate)
            var value = 0.0
            for tone in tones {
                guard t >= tone.start, t <= tone.start + tone.duration else { continue }
                let local = (t - tone.start) / tone.duration
                let attack = min(1.0, local / 0.16)
                let decay = pow(max(0.0, 1.0 - local), 1.8)
                let envelope = attack * decay
                value += sin(2 * Double.pi * tone.frequency * t) * tone.amplitude * envelope
                value += sin(2 * Double.pi * tone.frequency * 2.01 * t) * tone.amplitude * envelope * 0.12
            }
            let clipped = max(-1.0, min(1.0, value))
            samples.append(Int16(clipped * Double(Int16.max)))
        }

        return wavData(samples: samples)
    }

    private func wavData(samples: [Int16]) -> Data {
        var data = Data()
        let dataSize = UInt32(samples.count * MemoryLayout<Int16>.size)
        let byteRate = UInt32(sampleRate * MemoryLayout<Int16>.size)
        let blockAlign = UInt16(MemoryLayout<Int16>.size)

        data.appendASCII("RIFF")
        data.appendUInt32LE(36 + dataSize)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(1)
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(byteRate)
        data.appendUInt16LE(blockAlign)
        data.appendUInt16LE(16)
        data.appendASCII("data")
        data.appendUInt32LE(dataSize)
        for sample in samples {
            data.appendInt16LE(sample)
        }
        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendInt16LE(_ value: Int16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private class GhostCursorPathView: NSView {
    let start: CGPoint
    let end: CGPoint
    let color: NSColor
    let trailStyle: CursorTrailStyle
    let trajectoryStyle: CursorTrajectoryStyle
    let glowStyle: CursorGlowStyle
    let caption: String?
    let captionTopLeft: CGPoint?
    var progress: CGFloat = 0

    init(
        frame: NSRect,
        start: CGPoint,
        end: CGPoint,
        color: NSColor,
        trailStyle: CursorTrailStyle,
        trajectoryStyle: CursorTrajectoryStyle,
        glowStyle: CursorGlowStyle,
        caption: String?,
        captionTopLeft: CGPoint? = nil
    ) {
        self.start = start
        self.end = end
        self.color = color
        self.trailStyle = trailStyle
        self.trajectoryStyle = trajectoryStyle
        self.glowStyle = glowStyle
        self.caption = caption
        self.captionTopLeft = captionTopLeft
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawCaption()
        guard trailStyle != .none else { return }

        let points = GhostCursorCurve.sampledPoints(
            count: trailStyle == .spark ? 34 : 52,
            start: start,
            end: end,
            trajectoryStyle: trajectoryStyle
        )
        guard points.count > 1 else { return }
        let visibleCount = max(2, min(points.count, Int(CGFloat(points.count - 1) * progress) + 1))

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if trailStyle == .route {
            drawRoutePreview(in: ctx, points: points)
        }

        if visibleCount > 2, trailStyle != .spark {
            if glowStyle != .none || trailStyle == .comet {
                let pathGlow = trailStyle == .comet ? max(1.25, glowMultiplier) : glowMultiplier
                for idx in 1..<visibleCount {
                    let local = CGFloat(idx) / CGFloat(max(1, visibleCount - 1))
                    let alphaBase: CGFloat = trailStyle == .comet ? 0.18 : 0.09
                    let widthBase: CGFloat = trailStyle == .comet ? 9.0 : 6.4
                    ctx.setStrokeColor(color.withAlphaComponent((0.02 + local * alphaBase) * pathGlow).cgColor)
                    ctx.setLineWidth(widthBase - local * 2.2)
                    ctx.beginPath()
                    ctx.move(to: points[idx - 1])
                    ctx.addLine(to: points[idx])
                    ctx.strokePath()
                }
            }

            for idx in 1..<visibleCount {
                let local = CGFloat(idx) / CGFloat(max(1, visibleCount - 1))
                let alpha: CGFloat
                let lineWidth: CGFloat
                switch trailStyle {
                case .none, .spark:
                    alpha = 0
                    lineWidth = 0
                case .thread:
                    alpha = 0.05 + local * 0.20
                    lineWidth = 2.0 - local * 0.55
                case .ribbon:
                    alpha = 0.07 + local * 0.28
                    lineWidth = 4.0 - local * 1.9
                case .comet:
                    alpha = 0.08 + local * 0.40
                    lineWidth = 3.6 - local * 1.4
                case .route:
                    alpha = 0.10 + local * 0.30
                    lineWidth = 2.7 - local * 0.85
                }
                ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(lineWidth)
                ctx.beginPath()
                ctx.move(to: points[idx - 1])
                ctx.addLine(to: points[idx])
                ctx.strokePath()
            }
        }

        if trailStyle == .spark {
            for idx in 0..<visibleCount where idx % 3 == 0 {
                let local = CGFloat(idx) / CGFloat(max(1, points.count - 1))
                let radius = 1.2 + local * 1.4
                let alpha = 0.08 + local * 0.34
                ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
                ctx.fillEllipse(in: CGRect(
                    x: points[idx].x - radius,
                    y: points[idx].y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
            }
        }

        let current = points[min(visibleCount - 1, points.count - 1)]
        let haloProgress = max(0, min(1, (progress - 0.72) / 0.28))
        if haloProgress > 0, trailStyle != .thread {
            let haloRadius = 14 + haloProgress * 24
            let haloAlpha = (1 - haloProgress) * 0.22
            ctx.setStrokeColor(color.withAlphaComponent(haloAlpha).cgColor)
            ctx.setLineWidth(1.4)
            ctx.strokeEllipse(in: CGRect(
                x: current.x - haloRadius,
                y: current.y - haloRadius,
                width: haloRadius * 2,
                height: haloRadius * 2
            ))
        }

        let dotAlpha = 0.22 + progress * 0.34
        let dotRadius: CGFloat = trailStyle == .spark ? 2.2 : 2.6
        ctx.setFillColor(color.withAlphaComponent(dotAlpha).cgColor)
        ctx.fillEllipse(in: CGRect(
            x: current.x - dotRadius,
            y: current.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))
    }

    private func drawRoutePreview(in ctx: CGContext, points: [CGPoint]) {
        guard points.count > 1 else { return }
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [6, 7])
        ctx.setStrokeColor(color.withAlphaComponent(0.14).cgColor)
        ctx.setLineWidth(1.2)
        ctx.beginPath()
        ctx.move(to: points[0])
        for point in points.dropFirst() {
            ctx.addLine(to: point)
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawCaption() {
        guard let caption, !caption.isEmpty else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.94, alpha: 0.92),
            .paragraphStyle: paragraph,
        ]
        let text = NSAttributedString(string: caption, attributes: attributes)
        let inset: CGFloat = 14
        let textSize = text.size()
        let bubbleWidth = min(bounds.width - inset * 2, textSize.width + 22)
        let bubbleHeight = textSize.height + 12
        let preferredX = captionTopLeft?.x ?? inset
        let preferredY = captionTopLeft.map { $0.y - bubbleHeight }
            ?? (bounds.height - bubbleHeight - inset)
        let x = max(inset, min(preferredX, bounds.width - inset - bubbleWidth))
        let y = max(inset, min(preferredY, bounds.height - inset - bubbleHeight))
        let bubble = CGRect(
            x: x,
            y: y,
            width: bubbleWidth,
            height: bubbleHeight
        )
        NSColor.black.withAlphaComponent(0.42).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 7, yRadius: 7).fill()
        color.withAlphaComponent(0.20).setStroke()
        let border = NSBezierPath(roundedRect: bubble.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        border.lineWidth = 1
        border.stroke()
        text.draw(at: CGPoint(x: bubble.minX + 11, y: bubble.minY + 6))
    }

    private var glowMultiplier: CGFloat {
        switch glowStyle {
        case .none:
            return 0
        case .soft:
            return 1
        case .halo:
            return 1.55
        case .comet:
            return 1.85
        }
    }
}

private class CursorMarkerView: NSView {
    let color: NSColor
    let label: String?
    let shape: CursorMarkerShape
    let angleDeg: CGFloat
    let markerScale: CGFloat
    let glowStyle: CursorGlowStyle
    let idleStyle: CursorIdleStyle
    let edgeStyle: CursorEdgeStyle
    var phase: CGFloat = 0
    var motionProgress: CGFloat = 0
    var edgeEnergy: CGFloat = 0

    init(
        frame: NSRect,
        color: NSColor,
        label: String?,
        shape: CursorMarkerShape,
        angleDeg: CGFloat,
        markerScale: CGFloat,
        glowStyle: CursorGlowStyle,
        idleStyle: CursorIdleStyle,
        edgeStyle: CursorEdgeStyle
    ) {
        self.color = color
        self.label = label
        self.shape = shape
        self.angleDeg = angleDeg
        self.markerScale = markerScale
        self.glowStyle = glowStyle
        self.idleStyle = idleStyle
        self.edgeStyle = edgeStyle
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let idleWave = wave(rate: 0.72)
        let fastWave = wave(rate: 2.35)
        let edgeWave = wave(rate: 4.8)
        let idleAngle = idleRotation(wave: idleWave)
        let edgeAngle = edgeEnergy * edgeWave * 4.2
        let totalAngle = angleDeg + idleAngle + edgeAngle
        let microScale = idleScale(wave: idleWave) + edgeEnergy * 0.018
        let offset = idleOffset()
        let markerCenter = CGPoint(
            x: center.x + offset.x,
            y: center.y + offset.y
        )

        let cursor = transformedPath(
            makeCursorPath(shape: shape, center: markerCenter, scale: markerScale),
            around: markerCenter,
            angleDeg: totalAngle,
            scale: microScale
        )

        drawGlow(for: cursor, wave: fastWave)
        drawEdgeAccent(in: ctx, center: markerCenter)

        if let shadow = cursor.copy() as? NSBezierPath {
            var transform = AffineTransform()
            transform.translate(x: 1.6 * markerScale, y: -1.4 * markerScale)
            shadow.transform(using: transform)
            NSColor.black.withAlphaComponent(0.18).setFill()
            shadow.fill()
        }

        NSColor.black.withAlphaComponent(0.48).setStroke()
        cursor.lineWidth = 2.25 * max(0.74, min(markerScale, 1.0))
        cursor.stroke()

        color.withAlphaComponent(0.94).setFill()
        cursor.fill()

        NSColor.black.withAlphaComponent(0.52).setStroke()
        cursor.lineWidth = 0.78 * max(0.80, min(markerScale, 1.0))
        cursor.stroke()

        NSColor.white.withAlphaComponent(0.38).setStroke()
        cursor.lineWidth = 0.55 * max(0.82, min(markerScale, 1.0))
        cursor.stroke()

        drawIdleAccent(in: ctx, center: markerCenter)

        if let label, !label.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 8.5 * max(0.92, min(markerScale, 1.04)), weight: .medium),
                .foregroundColor: color.withAlphaComponent(0.86),
                .backgroundColor: NSColor.black.withAlphaComponent(0.34),
            ]
            let attributed = NSAttributedString(string: " \(label) ", attributes: attributes)
            let size = attributed.size()
            attributed.draw(at: CGPoint(x: markerCenter.x - size.width / 2, y: markerCenter.y - 50 * markerScale))
        }
    }

    private func transformedPath(_ path: NSBezierPath, around pivot: CGPoint, angleDeg: CGFloat, scale: CGFloat) -> NSBezierPath {
        guard (abs(angleDeg) > 0.01 || abs(scale - 1) > 0.001),
              let copy = path.copy() as? NSBezierPath
        else { return path }

        var transform = AffineTransform()
        transform.translate(x: pivot.x, y: pivot.y)
        transform.scale(scale)
        // Treat positive degrees as visual clockwise rotation to match SVG/CSS previews.
        transform.rotate(byDegrees: -angleDeg)
        transform.translate(x: -pivot.x, y: -pivot.y)
        copy.transform(using: transform)
        return copy
    }

    private func wave(rate: Double) -> CGFloat {
        CGFloat(sin(Double(phase) * Double.pi * 2.0 * rate))
    }

    private func idleRotation(wave: CGFloat) -> CGFloat {
        switch idleStyle {
        case .still, .breathe, .hover, .drift, .shimmer, .blink:
            return 0
        case .wiggle:
            return wave * 2.6
        case .orbit:
            return wave * 1.2
        case .nod:
            return wave * 1.6
        case .tremble:
            return self.wave(rate: 8.5) * 1.1
        }
    }

    private func idleScale(wave: CGFloat) -> CGFloat {
        switch idleStyle {
        case .still, .wiggle, .hover, .nod, .drift, .orbit:
            return 1
        case .breathe:
            return 1 + wave * 0.014
        case .shimmer:
            return 1 + max(0, self.wave(rate: 1.4)) * 0.012
        case .blink:
            return 1 + blinkPulse() * 0.018
        case .tremble:
            return 1 + self.wave(rate: 10.0) * 0.004
        }
    }

    private func idleOffset() -> CGPoint {
        switch idleStyle {
        case .still, .breathe, .wiggle, .orbit, .shimmer, .blink:
            return .zero
        case .hover:
            return CGPoint(x: 0, y: wave(rate: 0.55) * 1.8 * markerScale)
        case .nod:
            return CGPoint(x: 0, y: -max(0, wave(rate: 0.95)) * 2.0 * markerScale)
        case .drift:
            return CGPoint(
                x: cos(phase * 1.15) * 1.4 * markerScale,
                y: sin(phase * 0.86) * 1.2 * markerScale
            )
        case .tremble:
            return CGPoint(
                x: wave(rate: 9.0) * 0.75 * markerScale,
                y: wave(rate: 11.0) * 0.55 * markerScale
            )
        }
    }

    private func blinkPulse() -> CGFloat {
        let cycle = phase.truncatingRemainder(dividingBy: 1.8)
        guard cycle < 0.18 else { return 0 }
        let t = cycle / 0.18
        return sin(t * .pi)
    }

    private func drawGlow(for cursor: NSBezierPath, wave: CGFloat) {
        guard glowStyle != .none else { return }

        let base = max(0.72, min(markerScale, 1.0))
        let pulse = 1 + max(0, wave) * 0.16 + edgeEnergy * 0.22
        let layers: [(width: CGFloat, alpha: CGFloat)]
        switch glowStyle {
        case .none:
            layers = []
        case .soft:
            layers = [(5.0 * base * pulse, 0.13)]
        case .halo:
            layers = [
                (10.0 * base * pulse, 0.08),
                (5.4 * base * pulse, 0.17),
            ]
        case .comet:
            layers = [
                (13.0 * base * pulse, 0.07),
                (7.0 * base * pulse, 0.18),
            ]
        }

        for layer in layers {
            let glow = cursor.copy() as? NSBezierPath
            glow?.lineWidth = layer.width
            color.withAlphaComponent(layer.alpha).setStroke()
            glow?.stroke()
        }
    }

    private func drawEdgeAccent(in ctx: CGContext, center: CGPoint) {
        guard edgeEnergy > 0.01, edgeStyle != .none else { return }

        switch edgeStyle {
        case .none:
            return
        case .pulse:
            let radius = (17 + edgeEnergy * 18) * markerScale
            ctx.setStrokeColor(color.withAlphaComponent(0.16 * edgeEnergy).cgColor)
            ctx.setLineWidth(1.2 * markerScale)
            ctx.strokeEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        case .ripple:
            for index in 0..<2 {
                let offset = CGFloat(index) * 10
                let radius = (15 + offset + edgeEnergy * 20) * markerScale
                ctx.setStrokeColor(color.withAlphaComponent((0.13 - CGFloat(index) * 0.04) * edgeEnergy).cgColor)
                ctx.setLineWidth((1.0 - CGFloat(index) * 0.2) * markerScale)
                ctx.strokeEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
            }
        case .tick:
            let tickCount = 6
            let inner = (28 + edgeEnergy * 4) * markerScale
            let outer = (37 + edgeEnergy * 7) * markerScale
            ctx.setStrokeColor(color.withAlphaComponent(0.18 * edgeEnergy).cgColor)
            ctx.setLineWidth(1.1 * markerScale)
            for index in 0..<tickCount {
                let angle = CGFloat(index) / CGFloat(tickCount) * CGFloat.pi * 2 + phase * 0.9
                ctx.beginPath()
                ctx.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                ctx.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                ctx.strokePath()
            }
        case .reticle:
            let alpha = 0.16 + 0.26 * edgeEnergy
            let inset = (21 + 6 * (1 - edgeEnergy)) * markerScale
            let length = 11 * markerScale
            let radius = 2.5 * markerScale
            let left = center.x - inset
            let right = center.x + inset
            let top = center.y + inset
            let bottom = center.y - inset
            ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(1.25 * markerScale)
            ctx.setLineCap(.round)
            for (xSign, ySign) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
                let x = xSign < 0 ? left : right
                let y = ySign < 0 ? bottom : top
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: y + CGFloat(ySign) * radius))
                ctx.addLine(to: CGPoint(x: x, y: y + CGFloat(ySign) * (radius + length)))
                ctx.move(to: CGPoint(x: x + CGFloat(xSign) * radius, y: y))
                ctx.addLine(to: CGPoint(x: x + CGFloat(xSign) * (radius + length), y: y))
                ctx.strokePath()
            }
        case .blink:
            let radius = (8 + 16 * (1 - edgeEnergy)) * markerScale
            ctx.setFillColor(color.withAlphaComponent(0.18 * edgeEnergy).cgColor)
            ctx.fillEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        case .spark:
            let count = 8
            let radius = (22 + 8 * (1 - edgeEnergy)) * markerScale
            ctx.setFillColor(color.withAlphaComponent(0.32 * edgeEnergy).cgColor)
            for index in 0..<count {
                let angle = CGFloat(index) / CGFloat(count) * CGFloat.pi * 2 + phase * 0.45
                let dot = 1.35 * markerScale * (0.65 + edgeEnergy)
                ctx.fillEllipse(in: CGRect(
                    x: center.x + cos(angle) * radius - dot,
                    y: center.y + sin(angle) * radius - dot,
                    width: dot * 2,
                    height: dot * 2
                ))
            }
        case .underline:
            let y = center.y - 21 * markerScale
            let width = (18 + edgeEnergy * 20) * markerScale
            ctx.setStrokeColor(color.withAlphaComponent(0.32 * edgeEnergy).cgColor)
            ctx.setLineWidth(1.65 * markerScale)
            ctx.setLineCap(.round)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: center.x - width / 2, y: y))
            ctx.addLine(to: CGPoint(x: center.x + width / 2, y: y))
            ctx.strokePath()
        case .echo:
            for index in 0..<3 {
                let local = max(0, edgeEnergy - CGFloat(index) * 0.18)
                guard local > 0 else { continue }
                let radius = (12 + CGFloat(index) * 9 + (1 - local) * 12) * markerScale
                ctx.setStrokeColor(color.withAlphaComponent((0.16 - CGFloat(index) * 0.035) * local).cgColor)
                ctx.setLineWidth((1.25 - CGFloat(index) * 0.18) * markerScale)
                ctx.strokeEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
            }
        case .scan:
            let height = (28 - edgeEnergy * 8) * markerScale
            let width = 42 * markerScale
            let x = center.x - width / 2 + (1 - edgeEnergy) * width
            ctx.setStrokeColor(color.withAlphaComponent(0.30 * edgeEnergy).cgColor)
            ctx.setLineWidth(1.35 * markerScale)
            ctx.setLineCap(.round)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: center.y - height / 2))
            ctx.addLine(to: CGPoint(x: x, y: center.y + height / 2))
            ctx.strokePath()
        case .pin:
            let top = center.y + (30 - 12 * edgeEnergy) * markerScale
            let bottom = center.y + 12 * markerScale
            ctx.setStrokeColor(color.withAlphaComponent(0.30 * edgeEnergy).cgColor)
            ctx.setLineWidth(1.25 * markerScale)
            ctx.setLineCap(.round)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: center.x, y: top))
            ctx.addLine(to: CGPoint(x: center.x, y: bottom))
            ctx.strokePath()

            let dot = (2.2 + edgeEnergy * 1.6) * markerScale
            ctx.setFillColor(color.withAlphaComponent(0.36 * edgeEnergy).cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - dot, y: bottom - dot, width: dot * 2, height: dot * 2))
        }
    }

    private func drawIdleAccent(in ctx: CGContext, center: CGPoint) {
        switch idleStyle {
        case .orbit:
            let radius = 19 * markerScale
            let angle = phase * 2.2
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            let dotRadius = 1.8 * markerScale
            ctx.setFillColor(color.withAlphaComponent(0.42).cgColor)
            ctx.fillEllipse(in: CGRect(
                x: point.x - dotRadius,
                y: point.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
        case .shimmer:
            let t = max(0, wave(rate: 1.4))
            let x = center.x - 11 * markerScale + t * 22 * markerScale
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.16 + t * 0.18).cgColor)
            ctx.setLineWidth(1.1 * markerScale)
            ctx.setLineCap(.round)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x - 4 * markerScale, y: center.y + 10 * markerScale))
            ctx.addLine(to: CGPoint(x: x + 4 * markerScale, y: center.y + 18 * markerScale))
            ctx.strokePath()
        case .blink:
            let pulse = blinkPulse()
            guard pulse > 0 else { return }
            let radius = (13 + pulse * 6) * markerScale
            ctx.setStrokeColor(color.withAlphaComponent(0.18 * pulse).cgColor)
            ctx.setLineWidth(1.0 * markerScale)
            ctx.strokeEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        default:
            return
        }
    }

    private struct MarkerVertex {
        let point: CGPoint
        let radius: CGFloat
    }

    private struct MarkerCorner {
        let incoming: CGPoint
        let outgoing: CGPoint
        let control: CGPoint
    }

    private func makeCursorPath(shape: CursorMarkerShape, center: CGPoint, scale: CGFloat) -> NSBezierPath {
        roundedPolygon(vertices: markerVertices(shape: shape, center: center, scale: scale))
    }

    private func markerVertices(shape: CursorMarkerShape, center: CGPoint, scale: CGFloat) -> [MarkerVertex] {
        switch shape {
        case .arrow:
            return pointerVertices(
                center: center,
                points: [
                    (0, 0, 0.9),
                    (34, 31, 3.6),
                    (22, 33, 2.2),
                    (33, 54, 3.4),
                    (24, 58, 3.6),
                    (14, 37, 2.4),
                    (4, 47, 3.2),
                ],
                scale: scale
            )
        case .chevron:
            return pointerVertices(
                center: center,
                points: [
                    (0, 0, 0.9),
                    (31, 27, 4.2),
                    (20, 31, 2.6),
                    (30, 50, 3.8),
                    (22, 54, 4.0),
                    (12, 34, 2.6),
                    (3, 43, 4.0),
                ],
                scale: scale
            )
        case .facet:
            return symmetricVertices(
                center: center,
                left: [(-32, 42, 7), (-16, 54, 7)],
                bottom: (48, 5),
                scale: scale
            )
        case .shard:
            return pointerVertices(
                center: center,
                points: [
                    (0, 0, 0.8),
                    (34, 25, 2.4),
                    (22, 30, 1.8),
                    (31, 48, 2.8),
                    (24, 51, 2.4),
                    (13, 33, 1.8),
                    (4, 39, 2.4),
                ],
                scale: scale
            )
        case .wedge:
            return symmetricVertices(
                center: center,
                left: [(-38, 43, 7), (-14, 56, 7)],
                bottom: nil,
                scale: scale
            )
        case .prism:
            return symmetricVertices(
                center: center,
                left: [(-33, 47, 7), (-14, 56, 6)],
                bottom: (48, 4.5),
                scale: scale
            )
        case .notch:
            return symmetricVertices(
                center: center,
                left: [(-33, 50, 7), (-10, 45, 4.5)],
                bottom: (53, 5),
                scale: scale
            )
        case .needle:
            return pointerVertices(
                center: center,
                points: [
                    (0, 0, 0.7),
                    (27, 27, 2.4),
                    (18, 30, 1.7),
                    (27, 51, 2.4),
                    (20, 54, 2.4),
                    (11, 33, 1.7),
                    (3, 42, 2.3),
                ],
                scale: scale
            )
        case .petal:
            return pointerVertices(
                center: center,
                points: [
                    (0, 0, 1.4),
                    (31, 28, 5.6),
                    (21, 32, 4.2),
                    (31, 51, 5.0),
                    (23, 55, 5.0),
                    (13, 36, 4.2),
                    (3, 45, 5.2),
                ],
                scale: scale
            )
        case .kite:
            return pointerVertices(
                center: center,
                points: [
                    (0, 0, 0.7),
                    (37, 23, 2.0),
                    (23, 29, 1.6),
                    (36, 46, 2.2),
                    (29, 51, 2.2),
                    (14, 34, 1.8),
                    (5, 38, 2.0),
                ],
                scale: scale
            )
        }
    }

    private func pointerVertices(
        center: CGPoint,
        points: [(x: CGFloat, y: CGFloat, radius: CGFloat)],
        scale: CGFloat
    ) -> [MarkerVertex] {
        points.map { vertex($0.x, $0.y, $0.radius, center: center, scale: scale) }
    }

    private func symmetricVertices(
        center: CGPoint,
        left: [(x: CGFloat, y: CGFloat, radius: CGFloat)],
        bottom: (y: CGFloat, radius: CGFloat)?,
        scale: CGFloat
    ) -> [MarkerVertex] {
        var vertices: [MarkerVertex] = [vertex(0, 0, 1.5, center: center, scale: scale)]
        vertices.append(contentsOf: left.map { vertex($0.x, $0.y, $0.radius, center: center, scale: scale) })
        if let bottom {
            vertices.append(vertex(0, bottom.y, bottom.radius, center: center, scale: scale))
        }
        vertices.append(contentsOf: left.reversed().map { vertex(-$0.x, $0.y, $0.radius, center: center, scale: scale) })
        return vertices
    }

    private func vertex(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, center: CGPoint, scale: CGFloat) -> MarkerVertex {
        MarkerVertex(point: CGPoint(x: center.x + x * scale, y: center.y - y * scale), radius: radius * scale)
    }

    private func roundedPolygon(vertices: [MarkerVertex]) -> NSBezierPath {
        let path = NSBezierPath()
        guard vertices.count > 2 else { return path }

        let corners = vertices.indices.map { corner(at: $0, vertices: vertices) }
        guard let first = corners.first else { return path }

        path.move(to: first.outgoing)
        for corner in corners.dropFirst() {
            path.line(to: corner.incoming)
            addQuadraticCurve(to: corner.outgoing, control: corner.control, path: path)
        }
        path.line(to: first.incoming)
        addQuadraticCurve(to: first.outgoing, control: first.control, path: path)
        path.close()
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        return path
    }

    private func corner(at index: Int, vertices: [MarkerVertex]) -> MarkerCorner {
        let current = vertices[index]
        let previous = vertices[(index - 1 + vertices.count) % vertices.count]
        let next = vertices[(index + 1) % vertices.count]
        let inset = min(
            current.radius,
            distance(current.point, previous.point) * 0.44,
            distance(current.point, next.point) * 0.44
        )

        return MarkerCorner(
            incoming: point(from: current.point, toward: previous.point, amount: inset),
            outgoing: point(from: current.point, toward: next.point, amount: inset),
            control: current.point
        )
    }

    private func addQuadraticCurve(to end: CGPoint, control: CGPoint, path: NSBezierPath) {
        let start = path.currentPoint
        let controlPoint1 = CGPoint(
            x: start.x + (control.x - start.x) * 2 / 3,
            y: start.y + (control.y - start.y) * 2 / 3
        )
        let controlPoint2 = CGPoint(
            x: end.x + (control.x - end.x) * 2 / 3,
            y: end.y + (control.y - end.y) * 2 / 3
        )
        path.curve(to: end, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
    }

    private func point(from start: CGPoint, toward end: CGPoint, amount: CGFloat) -> CGPoint {
        let length = distance(start, end)
        guard length > 0.001, amount > 0 else { return start }
        return CGPoint(
            x: start.x + (end.x - start.x) / length * amount,
            y: start.y + (end.y - start.y) / length * amount
        )
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
