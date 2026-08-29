import AppKit
import BlinkCore
import Foundation
import HudsonObservability
import UniformTypeIdentifiers
import WebKit

/// A WKWebView that lets its host rewrite the right-click menu before it opens.
/// WebKit's stock note-surface menu is just "Reload"; the panel swaps in
/// Blink-relevant items (change style, hide, close) via `onWillOpenContextMenu`.
final class BlinkEditorWebView: WKWebView {
    var onWillOpenContextMenu: ((NSMenu) -> Void)?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        // Let WebKit finish contributing context-dependent entries (including
        // AutoFill) before Blink curates the final menu. Calling the hook first
        // left late WebKit additions stranded below Blink's closing actions.
        onWillOpenContextMenu?(menu)
    }
}

/// Hosts the CodeMirror editor bundle in a WKWebView and speaks the bridge
/// contract (see web/editor/README.md):
///   JS → native:  ready · contentChanged(text) · saveRequested
///   native → JS:  setContent · typeOn · focus · mode/theme/sheet/entrance
///
/// Designed to be generic enough to upstream to HudsonKit once proven.
@MainActor
final class EditorWebView: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView

    var onReady: (() -> Void)?
    var onContentChanged: ((String) -> Void)?
    var onSaveRequested: (() -> Void)?
    var onModeChanged: ((String) -> Void)?
    /// A rendered `[[wiki-link]]` was clicked (`blink://open/<id>`): open or focus
    /// that note. Wired by PanelManager to the NoteStore.
    var onOpenNote: ((String) -> Void)?

    /// Rewrite the WKWebView context menu before it opens — the panel drops
    /// WebKit's stock "Reload" and appends Blink's own items (style, hide, close).
    var onWillOpenContextMenu: ((NSMenu) -> Void)? {
        get { (webView as? BlinkEditorWebView)?.onWillOpenContextMenu }
        set { (webView as? BlinkEditorWebView)?.onWillOpenContextMenu = newValue }
    }

    /// Serves `blink://attachments/…` from the Blink home. Held so its lifetime
    /// matches the webview; the configuration copy retains it too.
    private let assetSchemeHandler: BlinkAssetSchemeHandler

    /// The editor bundle URL once loaded — the ONLY document allowed to navigate
    /// in the main frame (plus its own `#fragment` jumps). Everything else is
    /// denied so nothing can replace the editor.
    private var editorURL: URL?

    private var isReady = false
    private var pendingContent: String?
    private var pendingMode: String?
    private var pendingTheme: [String: String]?
    private var pendingSheet: String?
    private var pendingEnter: (kind: String, durationMs: Double)?
    private var pendingTypeOn: (base: String, suffix: String, source: String?)?
    private let log = HudLogger(category: "blink.bridge")

    override init() {
        let configuration = WKWebViewConfiguration()
        // Register the asset scheme on the configuration BEFORE the webview
        // copies it — scheme handlers cannot be added to a live webview.
        let handler = BlinkAssetSchemeHandler()
        configuration.setURLSchemeHandler(handler, forURLScheme: "blink")
        webView = BlinkEditorWebView(frame: .zero, configuration: configuration)
        assetSchemeHandler = handler
        super.init()

        configuration.userContentController.add(self, name: "blink")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")  // transparent over glass
    }

    /// Break the userContentController → handler retain cycle. Must be called
    /// when the hosting panel closes (PanelManager does this).
    func teardown() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "blink")
        onReady = nil
        onContentChanged = nil
        onSaveRequested = nil
        onModeChanged = nil
        onOpenNote = nil
    }

    /// Locate the built editor bundle: app Resources first (run-app.sh copies it),
    /// then the repo-relative dev path for `swift run`.
    static func editorHTMLURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "editor", withExtension: "html") {
            return bundled
        }
        // Dev fallback: <repo>/web/editor/dist/editor.html relative to the executable
        // (.build/debug/BlinkApp → repo root is three levels up).
        let executable = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let repoRoot = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dev = repoRoot.appendingPathComponent("web/editor/dist/editor.html")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    func load() {
        guard let url = Self.editorHTMLURL() else {
            log.error("[BLINK] editor.html not found — build web/editor first")
            return
        }
        editorURL = url
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // MARK: - WKNavigationDelegate

    /// Deny-by-default navigation for the MAIN frame: the editor document (its
    /// initial load, a reload, and its own `#fragment` jumps) is the ONLY thing
    /// allowed to load there — anything else would replace `editor.html` and
    /// destroy the editor. Beyond that, only a genuine user click may hand off:
    /// a `blink://open/<id>` wiki-link opens that note; an allowlisted external
    /// scheme opens in the user's default app.
    ///
    /// Subframes (iframes) are allowed to load remote `http(s)` — a cross-origin
    /// frame is sandboxed from `window.blink`, so a note may embed one (opt-in
    /// per the owner's high-trust call). `file:`/`about:`/`data:`/`javascript:`
    /// subframes (which could reach the native bridge or run same-origin script,
    /// incl. `srcdoc`) stay denied.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        // 1. The editor document itself (load/reload) + same-document fragments.
        if url.isFileURL, let editor = editorURL, url.path == editor.path {
            decisionHandler(.allow)
            return
        }
        // 1b. Subframes: remote http(s) embeds only; the bridge stays unreachable.
        if navigationAction.targetFrame?.isMainFrame == false {
            let scheme = url.scheme?.lowercased()
            decisionHandler(scheme == "http" || scheme == "https" ? .allow : .cancel)
            return
        }
        // Main frame: nothing loads in place. Only a real user click hands off.
        guard navigationAction.navigationType == .linkActivated else {
            decisionHandler(.cancel)
            return
        }
        // 2. blink://open/<id> — internal link to another note. Route, never load.
        //    (blink://attachments/… never reaches here — it's a subresource,
        //    served by BlinkAssetSchemeHandler, not a navigation.) lastPathComponent
        //    is already percent-decoded; do not decode a second time.
        if url.scheme == "blink" {
            if url.host == "open" {
                let id = url.lastPathComponent
                if !id.isEmpty, id != "/" { onOpenNote?(id) }
            }
            decisionHandler(.cancel)
            return
        }
        // 3. External links open in the user's default app — allowlisted schemes
        //    only, so a clicked `javascript:`/`data:` link can't be handed to the OS.
        if let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto", "tel", "file"].contains(scheme) {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func setContent(_ text: String) {
        guard isReady else {
            pendingContent = text
            // Last programmatic content operation wins while the page loads.
            // A non-append replacement supersedes a queued reveal.
            pendingTypeOn = nil
            return
        }
        evaluate("window.blink.setContent(\(Self.jsString(text)))")
    }

    func focus() {
        guard isReady else { return }
        evaluate("window.blink.focus()")
    }

    /// Programmatic mode switch (edit/read) — never echoes modeChanged.
    func setMode(_ mode: String) {
        guard isReady else {
            pendingMode = mode
            return
        }
        evaluate("window.blink.setMode(\(Self.jsString(mode)))")
    }

    /// Select the sheet template (the note's whole visual identity, drawn by
    /// the web layer). Never echoes contentChanged. Guarded so an older bundle
    /// without setSheet is a no-op rather than an error.
    func setSheet(_ name: String) {
        guard isReady else {
            pendingSheet = name
            return
        }
        evaluate("window.blink.setSheet && window.blink.setSheet(\(Self.jsString(name)))")
    }

    /// Play a content entrance effect (Arrival): the web layer choreographs the
    /// content while the native panel animates its window. Guarded so an older
    /// bundle without `enter` is a no-op rather than an error. `none` still calls
    /// through (a harmless no-op web-side) so a stale bundle never animates.
    func enter(_ kind: String, durationMs: Double) {
        guard isReady else {
            pendingEnter = (kind, durationMs)
            return
        }
        evaluate("window.blink.enter && window.blink.enter(\(Self.jsString(kind)), \(durationMs))")
    }

    /// Reveal an externally appended suffix without ever echoing
    /// `contentChanged`. Like theme/sheet/entrance this queues until `ready`
    /// and is guarded for a stale editor bundle; unlike those cosmetic calls,
    /// the fallback MUST install the complete content so no update is lost.
    func typeOn(base: String, suffix: String, source: String?) {
        guard isReady else {
            pendingContent = nil
            pendingTypeOn = (base, suffix, source)
            return
        }
        let full = base + suffix
        let encodedSource = source.map(Self.jsString) ?? "null"
        evaluate(
            "window.blink.typeOn "
                + "? window.blink.typeOn(\(Self.jsString(base)), \(Self.jsString(suffix)), "
                + "\(encodedSource)) "
                + ": window.blink.setContent(\(Self.jsString(full)))"
        )
    }

    /// Snap an in-flight reveal to its already-installed full document. Before
    /// `ready`, collapse the queued reveal into a full pending set instead.
    func finishTypeOn() {
        guard isReady else {
            // The native reveal clock can elapse before a newly created
            // WKWebView reaches `ready`. Collapse the queued reveal to a plain
            // full-content set — never discard the only copy of the update.
            if let pending = pendingTypeOn {
                pendingContent = pending.base + pending.suffix
                pendingTypeOn = nil
            }
            return
        }
        evaluate("window.blink.finishTypeOn && window.blink.finishTypeOn()")
    }

    /// Push CSS variables to the bundle (theming). Guarded so an older bundle
    /// without setTheme is a no-op rather than an error.
    func setTheme(_ vars: [String: String]) {
        guard isReady else {
            pendingTheme = vars
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: vars),
              let json = String(data: data, encoding: .utf8)
        else { return }
        evaluate("window.blink.setTheme && window.blink.setTheme(\(json))")
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "blink",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else { return }

        switch type {
        case "ready":
            isReady = true
            if let pending = pendingContent {
                pendingContent = nil
                setContent(pending)
            }
            if let mode = pendingMode {
                pendingMode = nil
                setMode(mode)
            }
            if let theme = pendingTheme {
                pendingTheme = nil
                setTheme(theme)
            }
            if let sheet = pendingSheet {
                pendingSheet = nil
                setSheet(sheet)
            }
            // Entrance last: content + sheet are in place, so the effect plays
            // against the final surface rather than an empty page.
            if let enter = pendingEnter {
                pendingEnter = nil
                self.enter(enter.kind, durationMs: enter.durationMs)
            }
            // Reveal last: content, mode, sheet, and any panel entrance are all
            // established before the append begins typing.
            if let typeOn = pendingTypeOn {
                pendingTypeOn = nil
                self.typeOn(base: typeOn.base, suffix: typeOn.suffix, source: typeOn.source)
            }
            onReady?()
        case "contentChanged":
            if let text = body["text"] as? String {
                onContentChanged?(text)
            }
        case "saveRequested":
            onSaveRequested?()
        case "modeChanged":
            if let mode = body["mode"] as? String {
                onModeChanged?(mode)
            }
        default:
            log.info("[BLINK] unknown bridge message", metadata: ["type": type])
        }
    }

    // MARK: - Helpers

    private func evaluate(_ js: String) {
        webView.evaluateJavaScript(js) { [log] _, error in
            if let error {
                log.error("[BLINK] bridge evaluate failed", metadata: ["error": "\(error)"])
            }
        }
    }

    /// Encode a Swift string as a JS string literal (JSON is a subset of JS).
    static func jsString(_ text: String) -> String {
        guard let data = try? JSONEncoder().encode(text),
              let encoded = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return encoded
    }
}

/// Serves `blink://attachments/<path>` from `$BLINK_HOME/attachments`, so a note
/// can embed an image it owns (`![](blink://attachments/pic.png)`) without the
/// webview being granted broad file-system read access. Requests that resolve
/// outside the attachments directory, or to a missing file, fail cleanly (a
/// broken image, never an escape). Everything is handled synchronously inside
/// `start`, so a `stop` can never interleave and touch a finished task.
final class BlinkAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    /// Cap served bytes so a huge (or malicious) file can't exhaust memory —
    /// `Data(contentsOf:)` reads the whole file. Generous for note images.
    private static let maxBytes = 64 * 1024 * 1024

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.host == "attachments" else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let root = BlinkPaths.attachments().standardizedFileURL
        // url.path is "/sub/pic.png"; resolve it under the attachments root and
        // refuse anything that standardizes to outside that root (../ traversal).
        let requested = root.appendingPathComponent(url.path).standardizedFileURL
        guard requested.path == root.path || requested.path.hasPrefix(root.path + "/") else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        // Standardizing does NOT follow symlinks — an `attachments/jump -> /etc`
        // symlink would pass the lexical guard above and read outside the root.
        // Resolve links on both sides and re-check containment. (Canonicalize
        // compromise; a descriptor-relative openat(O_NOFOLLOW) is the TOCTOU-proof
        // hardening if the trust posture tightens.)
        let resolvedRoot = root.resolvingSymlinksInPath().path
        let resolved = requested.resolvingSymlinksInPath()
        guard resolved.path == resolvedRoot || resolved.path.hasPrefix(resolvedRoot + "/") else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        // Regular files only (never a FIFO that would block, a directory, or a
        // device), within the byte cap.
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              let size = attrs[.size] as? Int, size <= Self.maxBytes else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        guard let data = try? Data(contentsOf: resolved) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = URLResponse(
            url: url,
            mimeType: Self.mimeType(forExtension: resolved.pathExtension),
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func mimeType(forExtension ext: String) -> String {
        if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
