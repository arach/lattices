import AppKit
import SwiftUI

final class CommandPaletteWindow {
    static let shared = CommandPaletteWindow()

    private var panel: NSPanel?
    private var scanner: ProjectScanner?

    func configure(scanner: ProjectScanner) {
        self.scanner = scanner
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if let p = panel, p.isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        // Always rebuild for fresh command state
        dismiss()

        guard let scanner = scanner else { return }

        // Ensure projects are up to date (full scan if list is empty,
        // e.g. palette opened via hotkey before main popover appeared)
        if scanner.projects.isEmpty {
            scanner.scan()
        } else {
            scanner.refreshStatus()
        }

        let commands = CommandBuilder.build(scanner: scanner)
        let view = CommandPaletteView(commands: commands) { [weak self] in
            self?.dismiss()
        }
        .preferredColorScheme(.dark)

        let panel = OverlayPanelShell.makePanel(
            config: .init(
                size: NSSize(width: 540, height: 440),
                styleMask: [.nonactivatingPanel],
                background: .material(.popover),
                cornerRadius: 14,
                hidesOnDeactivate: true,
                isMovableByWindowBackground: true
            ),
            rootView: view
        )
        OverlayPanelShell.position(panel, placement: .centered(yOffsetRatio: 0.1))
        OverlayPanelShell.present(panel)

        self.panel = panel
        AppDelegate.updateActivationPolicy()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        AppDelegate.updateActivationPolicy()
    }
}
