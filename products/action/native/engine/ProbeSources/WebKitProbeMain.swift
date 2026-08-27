import AppKit
import WebKit

final class ProbeAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var statusLabel: NSTextField?
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        let statusLabel = NSTextField(labelWithString: "Loading \(url.absoluteString)")
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle

        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(statusLabel)
        root.addSubview(webView)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            statusLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WebKit Probe"
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.managed, .fullScreenNone, .moveToActiveSpace]
        window.contentView = root
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)

        self.window = window
        self.webView = webView
        self.statusLabel = statusLabel

        webView.load(URLRequest(url: url))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        statusLabel?.stringValue = "Window closed"
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        statusLabel?.stringValue = "Connecting..."
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        statusLabel?.stringValue = "Rendering..."
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        statusLabel?.stringValue = "Loaded: \(webView.url?.absoluteString ?? url.absoluteString)"
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        statusLabel?.stringValue = "Load failed: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        statusLabel?.stringValue = "Load failed: \(error.localizedDescription)"
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        statusLabel?.stringValue = "Web content process terminated"
    }
}

@main
struct WebKitProbeMain {
    static func main() {
        let args = CommandLine.arguments
        let urlString: String
        if let idx = args.firstIndex(of: "--url"), args.indices.contains(idx + 1) {
            urlString = args[idx + 1]
        } else {
            urlString = "https://www.apple.com"
        }
        let url = URL(string: urlString) ?? URL(string: "https://www.apple.com")!

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = ProbeAppDelegate(url: url)
        app.delegate = delegate
        app.run()
    }
}
