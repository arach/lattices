import AppKit
import WebKit

/// All transport constants live here. This scheme serves bundled files only;
/// it neither opens a port nor starts the Companion bridge.
enum EditorTransport {
    static let scheme = "lattices-editor"
    static let host = "bundle"
    static let handler = "hudsonEditor"
    static let event = "hudson:host-event"
    static let indexURL = URL(string: "\(scheme)://\(host)/index.html")!
    static func isLocal(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == host && url.user == nil && url.password == nil && url.port == nil
    }
}

final class EditorBundleHandler: NSObject, WKURLSchemeHandler {
    let root: URL
    init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

    func file(for url: URL) throws -> URL {
        guard EditorTransport.isLocal(url), !url.path.contains("\0"), !url.path.contains("\\") else {
            throw EditorBridgeError("unavailable", "Editor resource origin is not allowed.")
        }
        let candidate = root.appendingPathComponent(url.path).standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw EditorBridgeError("unavailable", "Editor resource must be inside its bundle.")
        }
        return candidate
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        do {
            guard let url = task.request.url, task.request.httpMethod == "GET" else {
                throw EditorBridgeError("unavailable", "Only bundled Editor resources can be read.")
            }
            let file = try file(for: url)
            let data = try Data(contentsOf: file)
            let types = ["html": "text/html", "js": "text/javascript", "css": "text/css",
                         "json": "application/json", "svg": "image/svg+xml", "woff2": "font/woff2",
                         "png": "image/png", "ico": "image/x-icon"]
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [
                "Content-Type": types[file.pathExtension] ?? "application/octet-stream",
                "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'",
                "X-Content-Type-Options": "nosniff"
            ])!
            task.didReceive(response); task.didReceive(data); task.didFinish()
        } catch { task.didFailWithError(error) }
    }
    // Reads are synchronous; there is no queued task to cancel after return.
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class EditorWebHost: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    let web: WKWebView
    private let bridge: EditorBridge
    private var timer: Timer?
    private var failed = false

    init(bundleRoot: URL, bridge: EditorBridge = EditorBridge(capture: EditorBridge.liveSnapshot)) {
        self.bridge = bridge
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(EditorBundleHandler(root: bundleRoot), forURLScheme: EditorTransport.scheme)
        // Persistent default store retains subject-scoped layout across closing
        // and reopening. No workspace config is ever stored by this webview.
        configuration.websiteDataStore = .default()
        web = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: EditorTransport.handler)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = NSColor(calibratedWhite: 0.025, alpha: 1)
        bridge.onEvent = { [weak self] event in
            guard let self else { return }
            // callAsyncJavaScript passes structured arguments, never interpolates
            // source/config strings into executable JavaScript.
            self.web.callAsyncJavaScript(
                "window.dispatchEvent(new CustomEvent(eventName, {detail: envelope}));",
                arguments: ["eventName": EditorTransport.event, "envelope": event], in: nil,
                in: .page, completionHandler: nil)
        }
    }

    func start() {
        web.load(URLRequest(url: EditorTransport.indexURL))
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.bridge.poll() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        bridge.onEvent = nil
        web.configuration.userContentController.removeScriptMessageHandler(forName: EditorTransport.handler, contentWorld: .page)
        web.stopLoading()
        web.navigationDelegate = nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.name == EditorTransport.handler, message.frameInfo.isMainFrame,
              let url = message.frameInfo.request.url, EditorTransport.isLocal(url) else {
            replyHandler(nil, "Editor messages require the bundled main frame."); return
        }
        replyHandler(bridge.reply(to: message.body), nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              (EditorTransport.isLocal(url) && navigationAction.targetFrame?.isMainFrame == true)
                || (failed && url.absoluteString == "about:blank") else {
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { unavailable() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { unavailable() }
    private func unavailable() {
        guard !failed else { return }
        failed = true
        web.loadHTMLString("""
        <!doctype html><meta name="color-scheme" content="dark"><title>Lattices Editor</title>
        <body style="background:#060607;color:#d4d4d4;font:14px system-ui;padding:32px">
        <h1 style="font-size:18px">Editor unavailable in this Lattices version</h1>
        <p>The bundled Editor could not be loaded. Install a build that includes the Editor bundle.</p>
        </body>
        """, baseURL: nil)
    }
}

final class EditorWindowController: NSObject, NSWindowDelegate {
    static let shared = EditorWindowController()
    private var window: NSWindow?
    private var host: EditorWebHost?

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let root = Bundle.module.resourceURL!.appendingPathComponent("Editor", isDirectory: true)
        let host = EditorWebHost(bundleRoot: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Lattices Editor"
        window.minSize = NSSize(width: 480, height: 420)
        window.backgroundColor = NSColor(calibratedWhite: 0.025, alpha: 1)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = host.web
        window.center()
        window.setFrameAutosaveName("LatticesEditor")
        self.host = host; self.window = window
        AppActivationCoordinator.shared.registerSurface(id: "editor") { [weak self] in self?.window?.isVisible == true }
        host.start()
        window.makeKeyAndOrderFront(nil)
        AppActivationCoordinator.shared.refresh()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        host?.stop(); host = nil; window = nil
        AppActivationCoordinator.shared.refresh()
    }
}
