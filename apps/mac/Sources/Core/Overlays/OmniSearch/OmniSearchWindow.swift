import AppKit
import Combine
import SwiftUI

/// The unified bar. Bare text searches windows/sessions/OCR; a leading "/"
/// switches to command mode (placement + window actions on the frontmost window,
/// with a ghost preview). Opened search-primed (Hyper+5) or command-primed
/// (Ctrl+Opt+Space, prefills "/").
final class OmniSearchWindow {
    static let shared = OmniSearchWindow()

    private var panel: NSPanel?
    private var ghost: NSPanel?
    private var keyMonitor: Any?
    private var state: OmniSearchState?
    private var ghostObserver: AnyCancellable?
    private var queryObserver: AnyCancellable?

    private var capturedTarget: (wid: UInt32, pid: Int32)?
    private var capturedScreen: NSScreen?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(commandPrimed: Bool = false) {
        if isVisible { dismiss() } else { show(commandPrimed: commandPrimed) }
    }

    func show(commandPrimed: Bool = false) {
        if let p = panel, p.isVisible {
            p.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Capture the frontmost window before presenting (command mode acts on it).
        if let entry = DesktopModel.shared.frontmostWindow() {
            capturedTarget = (wid: entry.wid, pid: entry.pid)
            capturedScreen = screenForWindowFrame(entry.frame)
        }

        let searchState = OmniSearchState()
        state = searchState
        if commandPrimed { searchState.query = "/" }

        let view = OmniSearchView(
            state: searchState,
            onDismiss: { [weak self] in self?.dismiss() },
            onCommitCommand: { [weak self] in self?.commitCommand() }
        )
        .preferredColorScheme(.dark)

        let p = OverlayPanelShell.makePanel(
            config: .init(
                size: NSSize(width: 520, height: 480),
                styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                title: "Search",
                titleVisible: .hidden,
                titlebarAppearsTransparent: true,
                background: .material(.popover),
                cornerRadius: 14,
                hidesOnDeactivate: false,
                isMovableByWindowBackground: true,
                minSize: NSSize(width: 400, height: 300),
                maxSize: NSSize(width: 700, height: 700),
                activatesOnMouseDown: true,
                appearance: NSAppearance(named: .darkAqua)
            ),
            rootView: view
        )
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        OverlayPanelShell.position(p, placement: .centered(yOffsetRatio: 0.125))
        OverlayPanelShell.present(p)
        panel = p

        // Ghost preview tracks the highlighted command suggestion; the query
        // observer hides it when leaving command mode.
        ghostObserver = searchState.command.$selectedIndex
            .combineLatest(searchState.command.$suggestions)
            .sink { [weak self] _ in self?.updateGhost() }
        queryObserver = searchState.$query
            .sink { [weak self] _ in self?.updateGhost() }

        // Key monitor: Escape → dismiss, arrows → navigate, Enter → activate/commit,
        // Tab → drill into a command.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }
            let cmd = self.state?.commandMode == true
            switch event.keyCode {
            case 53: // Escape
                self.dismiss()
                return nil
            case 125: // ↓
                self.state?.moveSelection(1)
                return nil
            case 126: // ↑
                self.state?.moveSelection(-1)
                return nil
            case 36, 76: // Return / Enter
                if cmd {
                    self.commitCommand()
                } else {
                    self.state?.activateSelected()
                    self.dismiss()
                }
                return nil
            case 48: // Tab
                if cmd { self.drillIn(); return nil }
                return event
            default:
                return event
            }
        }
    }

    func dismiss() {
        ghostObserver?.cancel(); ghostObserver = nil
        queryObserver?.cancel(); queryObserver = nil
        ghost?.orderOut(nil); ghost = nil
        panel?.orderOut(nil)
        panel = nil
        state = nil
        capturedTarget = nil
        capturedScreen = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Command commit / drill-in

    private func commitCommand() {
        guard let st = state, let s = st.command.selected else { dismiss(); return }
        switch s.action {
        case .fillCommand(let c):
            st.query = "/" + (c.hint.aliases.first ?? c.name) + " "   // stay open, advance
        case .setQuery(let q):
            st.query = "/" + q                                         // stay open, advance
        case .placeCurrent(let spec):
            guard let t = capturedTarget else { dismiss(); return }
            let screen = capturedScreen
            dismiss()
            WindowTiler.tileWindowById(wid: t.wid, pid: t.pid, to: spec, on: screen)
        case .runCommand(let intent, let slots, let subject):
            runIntent(intent, slots: slots, subject: subject)
        }
    }

    private func drillIn() {
        guard let st = state, let s = st.command.selected else { return }
        switch s.action {
        case .fillCommand(let c): st.query = "/" + (c.hint.aliases.first ?? c.name) + " "
        case .setQuery(let q):    st.query = "/" + q
        default:                  break
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
            DiagnosticLog.shared.error("OmniSearch command \(intent) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Ghost preview

    private func updateGhost() {
        guard state?.commandMode == true,
              let spec = state?.command.previewSpec,
              let screen = state?.command.previewScreen ?? capturedScreen else {
            ghost?.orderOut(nil); ghost = nil
            return
        }
        let g = ghost ?? makeGhost()
        g.setFrame(ghostFrame(for: spec, on: screen), display: true)
        g.orderFront(nil)
        panel?.orderFront(nil)   // keep the bar above the ghost (same window level)
        ghost = g
    }

    /// Destination frame in Cocoa (bottom-left origin) screen coordinates.
    /// `PlacementSpec.fractions` measures y from the TOP (authored for AX),
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
