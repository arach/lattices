import AppKit
import Combine

/// Blink's effective light/dark decision. The config's `appearance` axis is a
/// string ("auto" | "light" | "dark"); this resolves it — against the live OS
/// setting when "auto" — into a concrete `AppScheme` the surfaces paint by.
enum AppScheme: Equatable {
    case light, dark

    /// The window/appearance name a surface adopts so its system materials
    /// (glass, blur) and standard controls render in the right mode.
    var nsAppearanceName: NSAppearance.Name {
        self == .dark ? .darkAqua : .aqua
    }

    var isDark: Bool { self == .dark }
}

/// Owns the app-wide light/dark decision and keeps every surface in sync.
///
/// `config.appearance` is the source of truth: "light"/"dark" pin `NSApp`'s
/// appearance; "auto" clears it so windows inherit the OS — and we KVO the OS's
/// effective appearance so a system light/dark flip re-themes Blink live.
///
/// Two notification paths, on purpose:
/// - `@Published scheme` drives SwiftUI surfaces (the popover) automatically.
/// - `onChange` re-themes the AppKit surfaces (panels, overlays) that pick
///   colors by scheme and can't observe an ObservableObject. It fires ONLY on a
///   system-driven flip; the config-driven path re-themes explicitly via its own
///   `applyTheme`, so an override change never double-applies.
@MainActor
final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    /// The resolved scheme every surface paints by. Published for SwiftUI.
    @Published private(set) var scheme: AppScheme = .dark

    /// Fired after a *system-driven* flip changes `scheme` (auto mode only), so
    /// AppKit surfaces can re-apply. SwiftUI observes `scheme` instead.
    var onChange: ((AppScheme) -> Void)?

    /// Normalized config value: "auto" | "light" | "dark".
    private var mode = "auto"
    private var systemObserver: NSKeyValueObservation?

    private init() {}

    /// Apply the config's `appearance` axis. Pins or clears `NSApp.appearance`,
    /// arms system observation only in auto, and recomputes `scheme`. Does NOT
    /// fire `onChange` — the config path re-themes explicitly right after.
    func apply(_ appearance: String) {
        mode = Self.normalize(appearance)
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil  // "auto": inherit the OS
        }
        observeSystem(mode == "auto")
        scheme = resolvedScheme()  // @Published — SwiftUI picks it up
    }

    /// KVO `NSApp.effectiveAppearance` so an OS light/dark flip re-themes live.
    /// Armed only in auto; pinned light/dark ignore the system entirely.
    private func observeSystem(_ on: Bool) {
        systemObserver?.invalidate()
        systemObserver = nil
        guard on else { return }
        systemObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.systemDidChange() }
        }
    }

    private func systemDidChange() {
        let next = resolvedScheme()
        guard next != scheme else { return }
        scheme = next        // @Published → SwiftUI surfaces
        onChange?(next)      // AppKit surfaces re-theme
    }

    private func resolvedScheme() -> AppScheme {
        switch mode {
        case "light": return .light
        case "dark":  return .dark
        default:
            let matched = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return matched == .darkAqua ? .dark : .light
        }
    }

    private static func normalize(_ raw: String) -> String {
        switch raw.lowercased() {
        case "light": return "light"
        case "dark": return "dark"
        // "system" is an accepted alias for "auto".
        default: return "auto"
        }
    }
}
