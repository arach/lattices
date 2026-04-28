import AppKit
import SwiftUI

final class OmniSearchWindow {
    static let shared = OmniSearchWindow()

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var state: OmniSearchState?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        if let p = panel, p.isVisible {
            p.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Fresh state each time
        let searchState = OmniSearchState()
        state = searchState

        let view = OmniSearchView(state: searchState) { [weak self] in
            self?.dismiss()
        }
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

        // Key monitor: Escape → dismiss, arrow keys → navigate, Enter → activate
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.panel?.isKeyWindow == true else { return event }

            switch event.keyCode {
            case 53: // Escape
                self?.dismiss()
                return nil
            case 125: // ↓
                self?.state?.moveSelection(1)
                return nil
            case 126: // ↑
                self?.state?.moveSelection(-1)
                return nil
            case 36: // Enter
                self?.state?.activateSelected()
                self?.dismiss()
                return nil
            default:
                return event
            }
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        state = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
