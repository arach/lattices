import AppKit
import Foundation

// Persists per-screen positions for each HUD panel in freeform mode.
// When freeformWidgets is active and a panel is dragged, its new position is saved here.
// On next show, panels go to their saved positions instead of snapping to screen edges.

final class WidgetPositionStore {
    static let shared = WidgetPositionStore()

    enum Widget: String, CaseIterable { case top, bottom, left, right }

    private static let defaultsKey = "hud.widget.positions"
    private var data: [String: NSRect] = [:]

    init() { load() }

    func position(for widget: Widget, on screen: NSScreen) -> NSRect? {
        data[key(widget, screen)]
    }

    func save(position rect: NSRect, for widget: Widget, on screen: NSScreen) {
        data[key(widget, screen)] = rect
        persist()
    }

    func clearAll() {
        data = [:]
        persist()
    }

    // MARK: - Private

    private func key(_ widget: Widget, _ screen: NSScreen) -> String {
        let sid = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int)
            .map { "\($0)" } ?? "main"
        return "\(sid).\(widget.rawValue)"
    }

    private func persist() {
        let encoded = data.mapValues { NSStringFromRect($0) }
        UserDefaults.standard.set(encoded, forKey: Self.defaultsKey)
    }

    private func load() {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] else { return }
        data = raw.compactMapValues {
            let r = NSRectFromString($0)
            return r == .zero ? nil : r
        }
    }
}
