import SwiftUI
import Carbon

// MARK: - Shortcut map row

/// Compact cheat-sheet row. Click the binding to recapture; hover for clear/reset.
struct ShortcutMapRow: View {
    let action: HotkeyAction
    @ObservedObject var store: HotkeyStore

    @State private var isCapturing = false
    @State private var isHovering = false
    @State private var conflictAction: HotkeyAction?
    @State private var pendingBinding: KeyBinding?
    @State private var showConflict = false

    private var binding: KeyBinding? { store.bindings[action] }
    private var isModified: Bool { binding != HotkeyStore.defaultBindings[action] }

    var body: some View {
        HStack(spacing: 8) {
            Text(action.label)
                .font(Typo.body(12))
                .foregroundColor(binding == nil ? Palette.textMuted : Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            bindingField

            if isHovering && !isCapturing {
                if binding != nil {
                    mapIconButton("minus", help: "Clear") {
                        store.clearBinding(for: action)
                    }
                }
                if isModified {
                    mapIconButton("arrow.counterclockwise", help: "Reset") {
                        store.resetBinding(for: action)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .background {
            if isCapturing {
                KeyCaptureOverlay(onCapture: handleCapture, onCancel: { isCapturing = false })
            }
        }
        .alert("Shortcut Conflict", isPresented: $showConflict) {
            Button("Replace") {
                if let pending = pendingBinding, let conflict = conflictAction {
                    store.clearBinding(for: conflict)
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
                Text("Already assigned to \"\(conflict.label)\". Replace it?")
            }
        }
    }

    private var bindingField: some View {
        Button {
            isCapturing.toggle()
        } label: {
            HStack(spacing: 5) {
                if isCapturing {
                    Text("Press keys")
                        .font(Typo.caption(11))
                        .foregroundColor(Palette.text)
                        .fixedSize()
                } else if let binding {
                    HStack(spacing: 3) {
                        ForEach(binding.compactDisplayParts, id: \.self) { part in
                            Text(part)
                                .font(Typo.geistMonoBold(10))
                                .foregroundColor(Palette.text)
                        }
                    }
                    .fixedSize()
                } else {
                    Text("Set")
                        .font(Typo.caption(11))
                        .foregroundColor(Palette.textMuted)
                        .fixedSize()
                }

                Image(systemName: isCapturing ? "xmark" : "pencil")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(isCapturing ? Palette.textDim : Palette.textMuted.opacity(isHovering || isCapturing ? 0.9 : 0.45))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isCapturing ? Palette.surfaceHov : Palette.surface.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(
                                isCapturing ? Palette.borderLit : (isHovering ? Palette.borderLit : Palette.border),
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .help(isCapturing ? "Cancel" : "Click to change this shortcut")
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func mapIconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Palette.textMuted)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help(help)
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
}

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
        GeometryReader { geo in
            let compact = geo.size.width < 360
            let labelWidth: CGFloat = compact ? 110 : 136
            let controlsWidth: CGFloat = binding == nil && !isModified ? 28 : 78
            let shortcutWidth = max(84, geo.size.width - labelWidth - controlsWidth - 24)

            HStack(spacing: 8) {
                Text(action.label)
                    .font(Typo.caption(11))
                    .foregroundColor(Palette.textDim)
                    .frame(width: labelWidth, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)

                shortcutDisplay
                    .frame(width: shortcutWidth, alignment: .leading)

                Spacer(minLength: 0)

                HStack(spacing: 2) {
                    recorderControlButton(
                        systemName: isCapturing ? "xmark" : "pencil",
                        help: isCapturing ? "Cancel capture" : "Edit shortcut",
                        color: isCapturing ? Palette.kill : Palette.textMuted
                    ) {
                        isCapturing.toggle()
                    }

                    if binding != nil {
                        recorderControlButton(
                            systemName: "minus.circle",
                            help: "Clear shortcut",
                            color: Palette.textMuted
                        ) {
                            store.clearBinding(for: action)
                            isCapturing = false
                        }
                    }

                    if isModified {
                        recorderControlButton(
                            systemName: "arrow.counterclockwise",
                            help: "Reset to default",
                            color: Palette.textMuted
                        ) {
                            store.resetBinding(for: action)
                            isCapturing = false
                        }
                    }
                }
                .frame(width: controlsWidth, alignment: .trailing)
            }
        }
        .frame(height: 24)
        .background {
            if isCapturing {
                KeyCaptureOverlay(onCapture: handleCapture, onCancel: { isCapturing = false })
            }
        }
        .alert("Shortcut Conflict", isPresented: $showConflict) {
            Button("Replace") {
                if let pending = pendingBinding, let conflict = conflictAction {
                    store.clearBinding(for: conflict)
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

    @ViewBuilder
    private var shortcutDisplay: some View {
        if isCapturing {
            Text("Press shortcut...")
                .font(Typo.mono(11))
                .foregroundColor(Palette.running)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        } else if let binding = binding {
            HStack(spacing: 4) {
                ForEach(binding.compactDisplayParts, id: \.self) { part in
                    keyBadge(part)
                }
            }
            .lineLimit(1)
        } else {
            Text("Not set")
                .font(Typo.mono(10.5))
                .foregroundColor(Palette.textMuted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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

    private func recorderControlButton(
        systemName: String,
        help: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func keyBadge(_ key: String) -> some View {
        Text(key)
            .font(Typo.geistMonoBold(10))
            .foregroundColor(Palette.text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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
