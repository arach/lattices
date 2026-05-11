import AppKit
import Combine
import Foundation

// MARK: - Effects

struct HUDEffects: OptionSet, Hashable {
    let rawValue: Int

    static let liveCapture     = HUDEffects(rawValue: 1 << 0) // sample desktop under panels
    static let meshLight       = HUDEffects(rawValue: 1 << 1) // MeshGradient light source
    static let mouseSpecular   = HUDEffects(rawValue: 1 << 2) // specular highlight tracks cursor
    static let edgeGlow        = HUDEffects(rawValue: 1 << 3) // canvas-drawn panel edge glow
    static let freeformWidgets = HUDEffects(rawValue: 1 << 4) // panels are draggable + persist position
    static let ambientPresence = HUDEffects(rawValue: 1 << 5) // rest at low opacity, light up on invoke
}

// MARK: - Preset

struct HUDPreset {
    let name: String
    let effects: HUDEffects
    // How opaque the dark colour overlay is — lower lets material/capture bleed through
    let overlayOpacity: Double
    // Alpha when not invoked (0 = fully hidden between uses)
    let ambientOpacity: Double
}

// MARK: - Store

final class HUDExperienceStore: ObservableObject {
    static let shared = HUDExperienceStore()

    static let presets: [HUDPreset] = [
        HUDPreset(
            name: "Classic",
            effects: [],
            overlayOpacity: 0.94,
            ambientOpacity: 0.0
        ),
        HUDPreset(
            name: "Glass",
            effects: [.liveCapture, .meshLight],
            overlayOpacity: 0.60,
            ambientOpacity: 0.0
        ),
        HUDPreset(
            name: "Alive",
            effects: [.meshLight, .mouseSpecular, .edgeGlow],
            overlayOpacity: 0.80,
            ambientOpacity: 0.0
        ),
        HUDPreset(
            name: "Scattered",
            effects: [.freeformWidgets, .ambientPresence, .meshLight, .edgeGlow],
            overlayOpacity: 0.82,
            ambientOpacity: 0.09
        ),
        HUDPreset(
            name: "Full",
            effects: [.liveCapture, .meshLight, .mouseSpecular, .edgeGlow, .freeformWidgets, .ambientPresence],
            overlayOpacity: 0.56,
            ambientOpacity: 0.07
        ),
    ]

    @Published private(set) var presetIndex: Int = 0

    /// Whether top + bottom chrome bars are visible. Off by default — sidebar-first.
    @Published var showChrome: Bool = false

    /// Raw screen-space mouse position, updated by HUDController when any mesh/specular effect is active.
    @Published var mousePosition: CGPoint = .zero

    /// Blurred, desaturated snapshot of what was under the panels at last show.
    @Published var capturedBackground: NSImage?

    private static let presetKey   = "hud.experience.presetIndex"
    private static let chromeKey   = "hud.experience.showChrome"

    init() {
        let saved = UserDefaults.standard.integer(forKey: Self.presetKey)
        presetIndex = min(max(0, saved), Self.presets.count - 1)
        showChrome = UserDefaults.standard.bool(forKey: Self.chromeKey)
    }

    func toggleChrome() {
        showChrome.toggle()
        UserDefaults.standard.set(showChrome, forKey: Self.chromeKey)
    }

    var currentPreset: HUDPreset { Self.presets[presetIndex] }
    var activeEffects: HUDEffects { currentPreset.effects }

    func has(_ effect: HUDEffects) -> Bool {
        activeEffects.contains(effect)
    }

    @discardableResult
    func cyclePreset() -> String {
        presetIndex = (presetIndex + 1) % Self.presets.count
        UserDefaults.standard.set(presetIndex, forKey: Self.presetKey)
        return currentPreset.name
    }

    /// Cursor position normalised to 0–1 within the given screen (x: left→right, y: bottom→top).
    func normalizedMouse(on screen: NSScreen) -> CGPoint {
        let f = screen.frame
        guard f.width > 0, f.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: max(0, min(1, (mousePosition.x - f.minX) / f.width)),
            y: max(0, min(1, (mousePosition.y - f.minY) / f.height))
        )
    }
}
