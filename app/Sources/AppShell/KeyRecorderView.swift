import SwiftUI
import Carbon

// MARK: - KeyRecorderView

struct KeyRecorderView: View {
    let action: HotkeyAction
    @ObservedObject var store: HotkeyStore

    @State private var isCapturing = false
    @State private var conflictAction: HotkeyAction?
    @State private var pendingBinding: KeyBinding?
    @State private var showConflict = false

    private var binding: KeyBinding? { store.bindings[action] }
    private var isModified: Bool {
        binding != HotkeyStore.defaultBindings[action]
    }

    var body: some View {
        HStack(spacing: 8) {
            // Action label
            Text(action.label)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textDim)
                .frame(minWidth: 60, idealWidth: 90, alignment: .trailing)
                .lineLimit(1)

            // Key badges or capture prompt
            if isCapturing {
                Text("Press shortcut...")
                    .font(Typo.mono(11))
                    .foregroundColor(Palette.running)
                    .frame(minWidth: 80, alignment: .leading)
            } else if let binding = binding {
                HStack(spacing: 4) {
                    ForEach(binding.compactDisplayParts, id: \.self) { part in
                        keyBadge(part)
                    }
                }
                .frame(minWidth: 80, alignment: .leading)
            }

            Spacer()

            // Edit button
            Button {
                if isCapturing {
                    isCapturing = false
                } else {
                    isCapturing = true
                }
            } label: {
                Text(isCapturing ? "Cancel" : "Edit")
                    .font(Typo.caption(10))
                    .foregroundColor(isCapturing ? Palette.kill : Palette.textDim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Palette.border, lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)

            // Reset link (only when modified)
            if isModified {
                Button {
                    store.resetBinding(for: action)
                } label: {
                    Text("Reset")
                        .font(Typo.caption(10))
                        .foregroundColor(Palette.detach)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .background(
            isCapturing
                ? KeyCaptureOverlay(onCapture: handleCapture, onCancel: { isCapturing = false })
                : nil
        )
        .alert("Shortcut Conflict", isPresented: $showConflict) {
            Button("Replace") {
                if let pending = pendingBinding, let conflict = conflictAction {
                    // Remove conflicting binding by resetting it
                    store.resetBinding(for: conflict)
                    store.updateBinding(for: action, to: pending)
                }
                pendingBinding = nil
                conflictAction = nil
                isCapturing = false
            }
            Button("Cancel", role: .cancel) {
                pendingBinding = nil
                conflictAction = nil
            }
        } message: {
            if let conflict = conflictAction {
                Text("This shortcut is already assigned to \"\(conflict.label)\". Replace it?")
            }
        }
    }

    private func handleCapture(_ binding: KeyBinding) {
        if let conflict = store.conflicts(for: action, with: binding) {
            pendingBinding = binding
            conflictAction = conflict
            showConflict = true
        } else {
            store.updateBinding(for: action, to: binding)
            isCapturing = false
        }
    }

    private func keyBadge(_ key: String) -> some View {
        Text(key)
            .font(Typo.geistMonoBold(10))
            .foregroundColor(Palette.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - KeyCaptureOverlay (NSViewRepresentable bridge)

struct KeyCaptureOverlay: NSViewRepresentable {
    let onCapture: (KeyBinding) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
    }
}

class KeyCaptureNSView: NSView {
    var onCapture: ((KeyBinding) -> Void)?
    var onCancel: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        stopMonitoring()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Escape cancels
            if event.keyCode == 53 {
                self.onCancel?()
                return nil
            }

            // Require at least one modifier
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !mods.isEmpty else { return nil }

            let keyCode = UInt32(event.keyCode)
            let carbonMods = KeyBinding.carbonModifiers(from: mods)
            let parts = KeyBinding.displayParts(keyCode: keyCode, carbonModifiers: carbonMods)

            let binding = KeyBinding(
                keyCode: keyCode,
                carbonModifiers: carbonMods,
                displayParts: parts
            )
            self.onCapture?(binding)
            return nil // swallow the event
        }
    }

    private func stopMonitoring() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}
