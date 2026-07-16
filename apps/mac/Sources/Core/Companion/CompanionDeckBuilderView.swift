import SwiftUI
import WebKit
import Foundation

/// Embeds the web deck builder (`design/studio` → `/embed/deck-builder`) inside
/// the Mac Settings companion card. In development it loads the studio dev
/// server; a bundled static export is the eventual production path.
///
/// Bridge: the builder posts every layout change to
/// `window.webkit.messageHandlers.deck` as `{ type: "deck-change", decks }`.
/// The coordinator forwards the raw `decks` JSON to `onChange`.
struct CompanionDeckBuilderView: NSViewRepresentable {
    /// Raw `decks` JSON (the builder's Deck[] shape) on every change.
    var onChange: (Data) -> Void = { _ in }
    var url = URL(string: "http://localhost:3050/embed/deck-builder")!

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "deck")
        config.userContentController = controller

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onChange: (Data) -> Void
        weak var web: WKWebView?

        init(onChange: @escaping (Data) -> Void) {
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
            onChange(data)
        }

        // If the dev server isn't running yet, show a small hint instead of a
        // blank white error page.
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
            deck builder dev server not reachable — run <code style="color:#a0a09b;\
            margin:0 4px">bun run dev</code> in design/studio (:3050)</body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

/// Persist the builder's raw layout JSON so edits survive reopening the pane and
/// can be inspected end-to-end. v1 stores it as a draft at
/// `~/.lattices/companion-deck-draft.json`; mapping it into the live cockpit
/// layout (+ the iPad span render) is the next Phase B step.
func persistCompanionDeckDraft(_ data: Data) {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".lattices", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? data.write(to: dir.appendingPathComponent("companion-deck-draft.json"), options: .atomic)
}
