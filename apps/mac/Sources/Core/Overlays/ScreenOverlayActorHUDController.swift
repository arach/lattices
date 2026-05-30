import AppKit
import WebKit

final class ScreenOverlayActorHUDController {
    static let shared = ScreenOverlayActorHUDController()

    private var panel: NSPanel?
    private var webView: WKWebView?
    private var currentContentKey: String?

    private init() {}

    func show(actorID: ScreenOverlayLayerID, hud: ScreenOverlayActorHUD, near actorRect: CGRect) {
        guard hud.hasContent else {
            hide()
            return
        }

        let size = CGSize(width: hud.width, height: hud.height)
        let panel = ensurePanel(size: size)
        let frame = positionedFrame(near: actorRect, size: size)
        panel.setFrame(frame, display: true)
        panel.title = hud.title ?? "Actor HUD"

        let contentKey = "\(actorID.rawValue)|\(hud.contentKey)"
        if currentContentKey != contentKey {
            currentContentKey = contentKey
            load(hud)
        }

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            panel.animator().alphaValue = 0
        } completionHandler: {
            if panel.alphaValue <= 0.05 {
                panel.orderOut(nil)
            }
        }
    }

    private func ensurePanel(size: CGSize) -> NSPanel {
        if let panel {
            if panel.frame.size != size {
                panel.setContentSize(size)
                panel.contentView?.frame = CGRect(origin: .zero, size: size)
            }
            return panel
        }

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let effectView = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0.8
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        effectView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor

        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: effectView.bounds.insetBy(dx: 1, dy: 1), configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 15
        webView.layer?.masksToBounds = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.setValue(false, forKey: "drawsBackground")

        effectView.addSubview(webView)
        panel.contentView = effectView

        self.panel = panel
        self.webView = webView
        return panel
    }

    private func load(_ hud: ScreenOverlayActorHUD) {
        guard let webView else { return }
        if let html = hud.html, !html.isEmpty {
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        guard let urlString = hud.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else { return }

        let url: URL?
        if urlString.hasPrefix("/") {
            url = URL(fileURLWithPath: urlString)
        } else {
            url = URL(string: urlString)
        }

        guard let url else {
            DiagnosticLog.shared.warn("ActorHUD: invalid HUD URL \(urlString)")
            return
        }

        if url.isFileURL {
            let readAccessURL = hud.readAccessPath
                .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                ?? url.deletingLastPathComponent()
            webView.loadFileURL(url, allowingReadAccessTo: readAccessURL)
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    private func positionedFrame(near actorRect: CGRect, size: CGSize) -> CGRect {
        let visibleFrame = screenVisibleFrame(containing: actorRect)
        let margin: CGFloat = 12
        let gap: CGFloat = 14
        var x = actorRect.maxX + gap
        if x + size.width > visibleFrame.maxX - margin {
            x = actorRect.minX - size.width - gap
        }
        if x < visibleFrame.minX + margin {
            x = min(max(actorRect.midX - size.width / 2, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        }

        let y = min(
            max(actorRect.midY - size.height / 2, visibleFrame.minY + margin),
            visibleFrame.maxY - size.height - margin
        )
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func screenVisibleFrame(containing rect: CGRect) -> CGRect {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return screen.visibleFrame
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
    }
}
