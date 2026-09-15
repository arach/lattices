import AppKit
import SwiftUI

enum SpeechHUDAction: Equatable {
    case show
    case showThenHide(TimeInterval)
    case hide
}

/// Presentation rules for the speech panel. Extracted so queue/HUD tests can
/// cover failed dismissal and voice-chrome clearance without opening a window.
enum SpeechHUDPresentation {
    static let panelSize = NSSize(width: 540, height: 108)
    static let screenMargin: CGFloat = 24
    static let completedHideDelay: TimeInterval = 1.2
    static let failedHideDelay: TimeInterval = 2.4

    static func action(for snapshot: SpeechSnapshot, openedFromMenu: Bool = false) -> SpeechHUDAction {
        if openedFromMenu && hasLiveWork(snapshot) { return .show }
        if snapshot.failure != nil { return .show }
        // Short UI confirmations already have voice chrome. Keep automatic
        // playback quiet; the menu can still open its controls explicitly.
        if let current = snapshot.current,
           current.source?.kind == "ui", current.state != .failed {
            return .hide
        }
        if hasLiveWork(snapshot) {
            return .show
        }
        if snapshot.current?.state == .failed {
            return .showThenHide(failedHideDelay)
        }
        if let last = snapshot.recent.last,
           last.state == .completed, last.source?.kind != "ui" {
            return .showThenHide(completedHideDelay)
        }
        return .hide
    }

    static func hasLiveWork(_ snapshot: SpeechSnapshot) -> Bool {
        if !snapshot.queued.isEmpty { return true }
        guard let current = snapshot.current else { return false }
        switch current.state {
        case .queued, .generating, .playing, .paused:
            return true
        case .failed, .completed, .cancelled:
            return false
        }
    }

    static func frame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let reserved = screenMargin
        return NSRect(
            x: visible.midX - panelSize.width / 2,
            y: visible.minY + reserved,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    static func placementScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

/// Non-activating playback HUD. Controls talk to `SpeechQueue` — the same
/// object RPC mutates. Never activates the app.
@MainActor
final class SpeechPlaybackHUD {
    static let shared = SpeechPlaybackHUD()

    private var panel: NSPanel?
    private var hosting: NSHostingView<SpeechPlaybackHUDView>?
    private var hideWork: DispatchWorkItem?
    private var hideGeneration: UInt64 = 0
    private var openedFromMenu = false
    private weak var queue: SpeechQueue?

    private init() {}

    func bind(_ queue: SpeechQueue) {
        if self.queue !== queue {
            self.queue = queue
            hosting?.rootView = SpeechPlaybackHUDView(queue: queue)
        }
        reflect(queue.snapshot)
    }

    func reflect(_ snapshot: SpeechSnapshot) {
        hideWork?.cancel()
        hideWork = nil
        switch SpeechHUDPresentation.action(for: snapshot, openedFromMenu: openedFromMenu) {
        case .show:
            show(snapshot)
        case .showThenHide(let delay):
            show(snapshot)
            scheduleHide(after: delay)
        case .hide:
            hide()
        }
    }

    /// Reopen from the menu bar without activating another app window.
    func showFromMenu() {
        guard let queue else { return }
        openedFromMenu = true
        hideWork?.cancel()
        hideWork = nil
        show(queue.snapshot)
        if !SpeechHUDPresentation.hasLiveWork(queue.snapshot) {
            scheduleHide(after: 8)
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        let token = hideGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hideGeneration == token else { return }
            self.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func show(_ snapshot: SpeechSnapshot) {
        hideGeneration &+= 1
        guard let screen = (panel?.isVisible == true ? panel?.screen : nil)
            ?? SpeechHUDPresentation.placementScreen() else { return }
        var frame = SpeechHUDPresentation.frame(on: screen)

        let view = SpeechPlaybackHUDView(queue: queue ?? SpeechQueue.shared)
        if panel == nil {
            let panel = SpeechHUDPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .statusBar
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovable = false
            panel.sharingType = .readOnly
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.becomesKeyOnlyIfNeeded = true
            panel.animationBehavior = .none
            panel.title = "Speech playback"
            panel.setAccessibilityRole(.window)
            panel.setAccessibilityLabel("Speech playback")
            panel.setAccessibilityIdentifier("speech-playback-hud")
            let hosting = SpeechHUDHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: SpeechHUDPresentation.panelSize)
            panel.contentView = hosting
            self.panel = panel
            self.hosting = hosting
        }

        guard let panel else { return }
        if let hosting {
            frame.size.height = max(frame.height, hosting.fittingSize.height)
        }
        panel.setFrame(frame, display: false)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func hide() {
        openedFromMenu = false
        hideGeneration &+= 1
        let token = hideGeneration
        guard let panel else { return }
        panel.ignoresMouseEvents = true
        guard panel.isVisible || panel.alphaValue > 0 else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.hideGeneration == token, let panel = self.panel else { return }
                panel.orderOut(nil)
                panel.ignoresMouseEvents = true
            }
        })
    }
}

private final class SpeechHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        orderFrontRegardless()
    }
}

private final class SpeechHUDHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var focusRingType: NSFocusRingType { get { .none } set {} }
}
