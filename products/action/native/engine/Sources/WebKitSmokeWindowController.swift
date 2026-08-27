import AppKit
import OSLog
import WebKit

final class WebKitSmokeAppRunner: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate {
    private static var retainedRunner: WebKitSmokeAppRunner?
    private let logger = Logger(subsystem: "dev.action.Action", category: "WebKitSmoke")
    private let url: URL

    private var window: NSWindow?
    private var webView: WKWebView?
    private var statusField: NSTextField?
    private var pendingRemoteURL: URL?
    private var observations: [NSKeyValueObservation] = []

    init(url: URL) {
        self.url = url
    }

    func run() {
        Self.retainedRunner = self
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = self
        logger.notice("Runner started for URL: \(self.url.absoluteString, privacy: .public)")
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.notice("Application did finish launching")
        showSmokeWindow()
        loadInlineSelfTest()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.notice("Application will terminate")
        Self.retainedRunner = nil
    }

    func windowWillClose(_ notification: Notification) {
        report("Smoke test window closed")
    }

    @objc
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        report("Connecting…")
    }

    @objc
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        report("Rendering…")
    }

    @objc
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let pendingRemoteURL {
            self.pendingRemoteURL = nil
            report("Inline self-test passed. Loading \(pendingRemoteURL.absoluteString)")
            logger.notice("Loading URL after self-test: \(pendingRemoteURL.absoluteString, privacy: .public)")
            webView.load(URLRequest(url: pendingRemoteURL))
            return
        }

        report("Loaded: \(webView.url?.absoluteString ?? url.absoluteString)")
    }

    @objc
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.error("Navigation failed: \(error.localizedDescription, privacy: .public)")
        report("Load failed: \(error.localizedDescription)")
    }

    @objc
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logger.error("Provisional navigation failed: \(error.localizedDescription, privacy: .public)")
        report("Load failed: \(error.localizedDescription)")
    }

    @objc
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.error("Web content process terminated")
        report("Web content process terminated")
    }

    private func showSmokeWindow() {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsMagnification = true
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        let statusField = NSTextField(labelWithString: "Ready")
        statusField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusField.textColor = NSColor.secondaryLabelColor
        statusField.lineBreakMode = .byTruncatingMiddle

        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        statusField.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(statusField)
        root.addSubview(webView)

        NSLayoutConstraint.activate([
            statusField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            statusField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            statusField.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.topAnchor.constraint(equalTo: statusField.bottomAnchor, constant: 8),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WebKit Smoke Test"
        window.collectionBehavior = [.managed, .fullScreenNone, .moveToActiveSpace]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.delegate = self
        placeWindowOnActiveScreen(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)

        self.webView = webView
        self.statusField = statusField
        self.window = window
        observeWebView(webView)
    }

    private func loadInlineSelfTest() {
        guard let webView else {
            report("Missing web view")
            return
        }

        pendingRemoteURL = url
        report("Self-test: loading inline HTML")
        logger.notice("Self-test load start before URL: \(self.url.absoluteString, privacy: .public)")
        webView.loadHTMLString(
            """
            <!doctype html>
            <html><head><meta charset="utf-8"><title>Smoke Inline OK</title></head>
            <body style="font-family: -apple-system; padding: 24px;">
            <h1>WKWebView Inline OK</h1><p>If you see this, delegate callbacks are alive.</p>
            </body></html>
            """,
            baseURL: nil
        )
    }

    private func placeWindowOnActiveScreen(_ window: NSWindow) {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return
        }

        let visible = screen.visibleFrame
        let width = min(1180.0, visible.width - 40)
        let height = min(820.0, visible.height - 40)
        let frame = CGRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
        window.setFrame(frame, display: false)
    }

    private func report(_ message: String) {
        statusField?.stringValue = message
        logger.notice("\(message, privacy: .public)")
    }

    private func observeWebView(_ webView: WKWebView) {
        observations.append(
            webView.observe(\.isLoading, options: [.new]) { [weak self] observed, _ in
                self?.logger.notice("KVO isLoading=\(observed.isLoading, privacy: .public)")
            }
        )
        observations.append(
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] observed, _ in
                self?.logger.notice("KVO progress=\(observed.estimatedProgress, privacy: .public)")
            }
        )
        observations.append(
            webView.observe(\.url, options: [.new]) { [weak self] observed, _ in
                let value = observed.url?.absoluteString ?? "nil"
                self?.logger.notice("KVO url=\(value, privacy: .public)")
            }
        )
    }
}
