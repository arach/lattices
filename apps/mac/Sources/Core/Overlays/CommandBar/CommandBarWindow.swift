import AppKit
import Combine
import SwiftUI

/// Non-activating command bar for acting on the frontmost window.
///
/// Like `GridPlacementWindow`, it captures the target window up front — before
/// presenting (which activates Lattices and would otherwise make us the
/// "frontmost" app) — then runs commands against it. Placement commands draw a
/// translucent ghost of the destination frame; all commands execute through the
/// shared `IntentEngine`, so the bar reflects the same vocabulary as voice/CLI.
final class CommandBarWindow {
    static let shared = CommandBarWindow()

    private var panel: OverlayPanel?
    private var ghost: NSPanel?
    private var keyMonitor: Any?
    private var state: CommandBarState?
    private var ghostObserver: AnyCancellable?

    private var capturedTarget: (wid: UInt32, pid: Int32)?
    private var capturedScreen: NSScreen?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { dismiss() } else { show() }
    }

    func show() {
        // Rebuild fresh; capture the target before presenting activates us.
        dismiss()

        guard let entry = DesktopModel.shared.frontmostWindow() else {
            DiagnosticLog.shared.info("CommandBar: no frontmost window to act on")
            return
        }
        capturedTarget = (wid: entry.wid, pid: entry.pid)
        let screen = screenForWindowFrame(entry.frame)
        capturedScreen = screen

        let st = CommandBarState()
        state = st

        let view = CommandBarView(
            state: st,
            appName: entry.app,
            onCommit: { [weak self] in self?.commit() },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        .preferredColorScheme(.dark)

        let p = OverlayPanelShell.makePanel(
            config: .init(
                size: NSSize(width: 560, height: 360),
                styleMask: [.nonactivatingPanel],
                background: .material(.popover),
                cornerRadius: 14,
                level: .popUpMenu,            // above the ghost (.floating) and the user's windows
                isMovableByWindowBackground: true,
                activatesOnMouseDown: true
            ),
            rootView: view
        )
        OverlayPanelShell.position(p, placement: .centered(yOffsetRatio: 0.125))
        OverlayPanelShell.present(p)
        panel = p

        // Ghost preview tracks the highlighted suggestion.
        ghostObserver = st.$selectedIndex
            .combineLatest(st.$suggestions)
            .sink { [weak self] _ in self?.updateGhost() }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.panel?.isKeyWindow == true else { return event }
            switch event.keyCode {
            case 53:        self?.dismiss(); return nil          // Escape
            case 125:       self?.state?.moveSelection(1); return nil   // ↓
            case 126:       self?.state?.moveSelection(-1); return nil  // ↑
            case 36, 76:    self?.commit(); return nil           // Return / Enter
            case 48:        self?.drillIn(); return nil          // Tab → into a command
            default:        return event
            }
        }

        AppDelegate.updateActivationPolicy()
    }

    func dismiss() {
        ghostObserver?.cancel()
        ghostObserver = nil
        ghost?.orderOut(nil)
        ghost = nil
        panel?.orderOut(nil)
        panel = nil
        state = nil
        capturedTarget = nil
        capturedScreen = nil
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        AppDelegate.updateActivationPolicy()
    }

    // MARK: - Commit / drill-in

    private func commit() {
        guard let st = state, let s = st.selected else { dismiss(); return }
        switch s.action {
        case .fillCommand(let cmd):
            st.beginCommand(cmd)                    // stay open, advance to the arg stage
        case .setQuery(let q):
            st.query = q                            // stay open, advance (e.g. display → position)
        case .placeCurrent(let spec):
            guard let t = capturedTarget else { dismiss(); return }
            let screen = capturedScreen
            dismiss()
            WindowTiler.tileWindowById(wid: t.wid, pid: t.pid, to: spec, on: screen)
        case .runCommand(let intent, let slots, let subject):
            runIntent(intent, slots: slots, subject: subject)
        }
    }

    /// Tab: drill into the highlighted command/value without executing.
    private func drillIn() {
        guard let s = state?.selected else { return }
        switch s.action {
        case .fillCommand(let cmd): state?.beginCommand(cmd)
        case .setQuery(let q):      state?.query = q
        default:                    break
        }
    }

    private func runIntent(_ intent: String, slots: [String: JSON], subject: CommandSubject) {
        var slots = slots
        if subject == .currentWindow, let t = capturedTarget {
            slots["wid"] = .int(Int(t.wid))
        }
        dismiss()
        do {
            let (name, normalized) = try IntentEngine.shared.normalizeResolved(intentName: intent, slots: slots)
            _ = try IntentEngine.shared.execute(IntentRequest(
                intent: name, slots: normalized, rawText: nil, confidence: 1.0, source: "command-bar"
            ))
        } catch {
            DiagnosticLog.shared.error("CommandBar: \(intent) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Ghost preview

    private func updateGhost() {
        guard let spec = state?.previewSpec,
              let screen = state?.previewScreen ?? capturedScreen else {
            ghost?.orderOut(nil)
            ghost = nil
            return
        }
        let g = ghost ?? makeGhost()
        g.setFrame(ghostFrame(for: spec, on: screen), display: true)
        g.orderFront(nil)
        ghost = g
    }

    /// Destination frame in Cocoa (bottom-left origin) screen coordinates.
    /// `PlacementSpec.fractions` measures `y` from the TOP (authored for AX),
    /// so flip it for NSPanel placement.
    private func ghostFrame(for spec: PlacementSpec, on screen: NSScreen) -> CGRect {
        let (fx, fy, fw, fh) = spec.fractions
        let vf = screen.visibleFrame
        return CGRect(
            x: vf.origin.x + vf.width * fx,
            y: vf.maxY - vf.height * (fy + fh),
            width: vf.width * fw,
            height: vf.height * fh
        )
    }

    private func makeGhost() -> NSPanel {
        let g = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        g.isOpaque = false
        g.backgroundColor = .clear
        g.level = .floating
        g.hasShadow = false
        g.ignoresMouseEvents = true
        g.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        g.sharingType = .readOnly

        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        v.layer?.borderWidth = 2
        v.layer?.cornerRadius = 6
        g.contentView = v
        return g
    }

    // MARK: - Screen resolution (mirrors GridPlacementWindow)

    private func screenForWindowFrame(_ f: WindowFrame) -> NSScreen {
        let primaryH = NSScreen.screens.first?.frame.height ?? 1080
        let cx = CGFloat(f.x + f.w / 2)
        let cyTop = CGFloat(f.y + f.h / 2)
        let pt = NSPoint(x: cx, y: primaryH - cyTop)
        return NSScreen.screens.first(where: { $0.frame.contains(pt) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
