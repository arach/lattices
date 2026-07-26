import SwiftUI
import WebKit
import AppKit
import Foundation

/// Embeds the bundled web deck builder served by the companion bridge process.
/// Next/Bun are build-time tools only; the shipped editor is static content on
/// the same local server as the companion API.
///
/// Bridge: the builder posts every layout change to
/// `window.webkit.messageHandlers.deck` as `{ type: "deck-change", decks }`.
/// The coordinator maps the builder model into the persisted Mac cockpit
/// layout, which is then published to connected iPad companions.
struct CompanionDeckBuilderView: NSViewRepresentable {
    var layout: LatticesCompanionCockpitLayout
    var onChange: (LatticesCompanionCockpitLayout) -> Void = { _ in }
    var url = URL(string: "http://127.0.0.1:\(LatticesCompanionBridgeServer.defaultPort)/deck-builder")!

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "deck")
        if let json = Self.builderJSON(for: layout) {
            controller.addUserScript(WKUserScript(
                source: "window.__DECK_INIT__ = \(json);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        config.userContentController = controller

        let web = WKWebView(frame: .zero, configuration: config)
        // Dark, non-white background so entering the page doesn't flash white
        // before the (dark) editor paints. `drawsBackground` is transparent so
        // the surrounding panel shows through; underPageBackgroundColor kills the
        // white overscroll/rubber-band edge on macOS 12+.
        web.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) {
            web.underPageBackgroundColor = NSColor(red: 6.0 / 255, green: 6.0 / 255, blue: 7.0 / 255, alpha: 1)
        }
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onChange: (LatticesCompanionCockpitLayout) -> Void
        weak var web: WKWebView?

        init(onChange: @escaping (LatticesCompanionCockpitLayout) -> Void) {
            self.onChange = onChange
        }

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "deck" else { return }
            guard
                let dict = message.body as? [String: Any],
                dict["type"] as? String == "deck-change",
                let decks = dict["decks"],
                let data = try? JSONSerialization.data(withJSONObject: decks)
            else { return }
            persistCompanionDeckDraft(data)
            guard let layout = CompanionDeckBuilderView.liveLayout(from: data) else { return }
            onChange(layout)
        }

        // If the bridge is disabled or the bundle is incomplete, show a useful
        // local hint instead of WebKit's blank error page.
        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) { showUnavailable(in: webView) }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) { showUnavailable(in: webView) }

        private func showUnavailable(in webView: WKWebView) {
            let html = """
            <html><body style="margin:0;background:#060607;color:#71716c;\
            font-family:ui-monospace,Menlo,monospace;font-size:12px;\
            display:flex;align-items:center;justify-content:center;height:100vh">\
            embedded deck builder unavailable — enable the Companion Bridge and restart Lattices</body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    static func importedLayout(fromBuilderDraft data: Data) -> LatticesCompanionCockpitLayout? {
        liveLayout(from: data)
    }
}

private extension CompanionDeckBuilderView {
    struct BuilderDeck: Codable {
        var id: String
        var name: String
        var tint: String
        var columns: Int
        var rows: Int
        var keys: [BuilderKey]
    }

    struct BuilderKey: Codable {
        var id: String
        var label: String
        var icon: String
        var tint: String
        var category: String
        var actionID: String
        var col: Int
        var row: Int
        var colSpan: Int
        var rowSpan: Int
    }

    static func builderJSON(for layout: LatticesCompanionCockpitLayout) -> String? {
        let normalized = LatticesCompanionCockpitCatalog.normalized(layout)
        let decks = normalized.pages.map { page -> BuilderDeck in
            let slots: [LatticesCompanionCockpitLayout.Slot]
            if let positioned = page.slots {
                slots = positioned
            } else {
                slots = page.slotIDs.enumerated().compactMap { index, shortcutID in
                    guard !shortcutID.isEmpty else { return nil }
                    return .init(
                        shortcutID: shortcutID,
                        col: index % max(1, page.columns),
                        row: index / max(1, page.columns)
                    )
                }
            }

            let keys = slots.enumerated().compactMap { index, slot -> BuilderKey? in
                guard let definition = LatticesCompanionCockpitCatalog.definition(for: slot.shortcutID),
                      !slot.shortcutID.isEmpty else { return nil }
                return BuilderKey(
                    id: "\(page.id)-\(index)",
                    label: definition.title,
                    icon: builderIcon(for: slot.shortcutID),
                    tint: definition.category.tintToken,
                    category: definition.category.rawValue,
                    actionID: slot.shortcutID,
                    col: slot.col,
                    row: slot.row,
                    colSpan: slot.colSpan,
                    rowSpan: slot.rowSpan
                )
            }
            return BuilderDeck(
                id: page.id,
                name: page.title,
                tint: keys.first?.tint ?? "blue",
                columns: page.columns,
                rows: page.rows ?? max(1, Int(ceil(Double(max(1, page.slotIDs.count)) / Double(max(1, page.columns))))),
                keys: keys
            )
        }
        guard let data = try? JSONEncoder().encode(decks) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func liveLayout(from data: Data) -> LatticesCompanionCockpitLayout? {
        guard let decks = try? JSONDecoder().decode([BuilderDeck].self, from: data) else { return nil }
        let pages = decks.map { deck in
            LatticesCompanionCockpitLayout.Page(
                id: deck.id,
                title: deck.name,
                columns: min(5, max(2, deck.columns)),
                rows: min(4, max(1, deck.rows)),
                slots: deck.keys.prefix(LatticesCompanionCockpitCatalog.slotCount).compactMap { key in
                    let shortcutID = canonicalShortcutID(key.actionID)
                    guard LatticesCompanionCockpitCatalog.definition(for: shortcutID) != nil else { return nil }
                    return .init(
                        shortcutID: shortcutID,
                        col: key.col,
                        row: key.row,
                        colSpan: max(1, key.colSpan),
                        rowSpan: max(1, key.rowSpan)
                    )
                }
            )
        }
        return LatticesCompanionCockpitCatalog.normalized(.init(pages: pages))
    }

    static func canonicalShortcutID(_ builderID: String) -> String {
        let legacy: [String: String] = [
            "voice.toggle": "voice-toggle", "voice.cancel": "voice-cancel",
            "key.escape": "key-escape", "key.enter": "key-enter", "key.space": "key-space",
            "switch.appPrev": "switch-app-prev", "switch.appNext": "switch-app-next",
            "switch.winPrev": "switch-window-prev", "switch.winNext": "switch-window-next",
            "layout.optimize": "layout-optimize", "layout.left": "place-left",
            "layout.right": "place-right", "layout.center": "place-center",
            "layout.maximize": "place-maximize", "mouse.find": "mouse-find",
            "mouse.summon": "mouse-summon", "mouse.joystick": "mouse-joystick",
        ]
        return legacy[builderID] ?? builderID
    }

    static func builderIcon(for shortcutID: String) -> String {
        let icons: [String: String] = [
            "voice-toggle": "Mic", "voice-cancel": "X", "key-escape": "CornerDownLeft",
            "key-enter": "CornerDownLeft", "key-space": "SpaceIcon",
            "switch-app-prev": "ChevronLeft", "switch-app-next": "ChevronRight",
            "switch-window-prev": "ArrowLeft", "switch-window-next": "ArrowRight",
            "layout-optimize": "LayoutGrid", "place-left": "PanelLeft", "place-right": "PanelRight",
            "place-center": "SquareDashed", "place-maximize": "Maximize2",
            "mouse-find": "Crosshair", "mouse-summon": "MousePointer2", "mouse-joystick": "Joystick",
            "paste-device": "ClipboardPaste",
        ]
        return icons[shortcutID] ?? "SquareDashed"
    }
}

/// Keep the builder's raw payload as a diagnostic draft alongside the canonical
/// UserDefaults-backed cockpit layout.
func persistCompanionDeckDraft(_ data: Data) {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".lattices", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? data.write(to: dir.appendingPathComponent("companion-deck-draft.json"), options: .atomic)
}
