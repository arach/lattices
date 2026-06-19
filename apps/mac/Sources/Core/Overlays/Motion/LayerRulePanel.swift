import AppKit
import SwiftUI

// MARK: - LayerRulePanel

final class LayerRulePanel: NSPanel {
    private let onSave: (StudioLayerClause) -> Void
    private let onCancel: () -> Void

    init(
        layerName: String,
        clauseIndex: Int?,
        clause: StudioLayerClause,
        onSave: @escaping (StudioLayerClause) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
        super.init(contentRect: NSRect(x: 0, y: 0, width: 720, height: 360),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false

        let form = LayerRuleForm(
            layerName: layerName,
            clauseIndex: clauseIndex,
            clause: clause,
            onSave: { [weak self] saved in self?.onSave(saved); self?.close() },
            onCancel: { [weak self] in self?.onCancel(); self?.close() }
        )
        let host = NSHostingView(rootView: form)
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var canBecomeKey: Bool { true }

    func present(on screen: NSScreen) {
        setFrame(screen.frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

// MARK: - LayerRuleForm

private struct LayerRuleForm: View {
    private struct Draft {
        enum NameMatchMode: String, CaseIterable, Identifiable {
            case direct = "Text"
            case regex = "Regex"

            var id: String { rawValue }
        }

        var app = ""
        var name = ""
        var nameMode: NameMatchMode = .direct

        init(_ clause: StudioLayerClause) {
            app = clause.appEquals ?? clause.app ?? clause.appRegex ?? ""
            if let titleRegex = clause.titleRegex {
                name = titleRegex
                nameMode = .regex
            } else {
                name = clause.titleContains ?? clause.titleEquals ?? ""
                nameMode = .direct
            }
        }

        var clause: StudioLayerClause {
            switch nameMode {
            case .direct:
                StudioLayerClause(appEquals: clean(app), titleContains: clean(name))
            case .regex:
                StudioLayerClause(appEquals: clean(app), titleRegex: clean(name))
            }
        }

        var canSave: Bool {
            (clean(app) != nil || clean(name) != nil) && nameIsValid
        }

        var nameIsValid: Bool {
            guard nameMode == .regex, let value = clean(name) else { return true }
            return (try? NSRegularExpression(pattern: value, options: [.caseInsensitive])) != nil
        }

        var statusText: String {
            if !nameIsValid { return "invalid regex" }
            if !canSave { return "add app or name" }
            return "ready"
        }

        private func clean(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    let layerName: String
    let clauseIndex: Int?
    let onSave: (StudioLayerClause) -> Void
    let onCancel: () -> Void

    @State private var draft: Draft
    @FocusState private var appFocused: Bool

    init(
        layerName: String,
        clauseIndex: Int?,
        clause: StudioLayerClause,
        onSave: @escaping (StudioLayerClause) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.layerName = layerName
        self.clauseIndex = clauseIndex
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: Draft(clause))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.66)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }
            vessel
        }
    }

    private var vessel: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            fields
            preview
            footer
        }
        .padding(22)
        .frame(width: 480)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.06, green: 0.07, blue: 0.09))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.62), radius: 44, y: 20)
        )
        .onAppear { appFocused = true }
        .onSubmit { saveIfReady() }
        .onExitCommand(perform: onCancel)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.running)
            VStack(alignment: .leading, spacing: 1) {
                Text(clauseIndex == nil ? "New Rule" : "Edit Rule")
                    .font(Typo.monoBold(14))
                    .foregroundColor(.white)
                Text(layerName)
                    .font(Typo.mono(9))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
            }
            Spacer()
            Text("esc").font(Typo.mono(9)).foregroundColor(.white.opacity(0.4))
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("App", text: $draft.app, placeholder: "Google Chrome", focused: true)
            nameField
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5))
        )
    }

    private var nameField: some View {
        HStack(spacing: 10) {
            Text("Name")
                .font(Typo.mono(10))
                .foregroundColor(.white.opacity(0.46))
                .frame(width: 82, alignment: .leading)
            textInput($draft.name, placeholder: draft.nameMode == .regex ? "GitHub|Pull Request" : "Pull Request")
            Picker("", selection: $draft.nameMode) {
                ForEach(Draft.NameMatchMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 132)
        }
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, placeholder: String, focused: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Typo.mono(10))
                .foregroundColor(.white.opacity(0.46))
                .frame(width: 82, alignment: .leading)
            if focused {
                textInput(text, placeholder: placeholder)
                    .focused($appFocused)
            } else {
                textInput(text, placeholder: placeholder)
            }
        }
    }

    private func textInput(_ text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(Typo.mono(11))
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5))
            )
    }

    private var preview: some View {
        HStack(spacing: 8) {
            Text("RULE")
                .font(Typo.monoBold(8.5))
                .foregroundColor(.white.opacity(0.4))
            Text(draft.nameIsValid ? (draft.canSave ? draft.clause.summary : "no rule") : "invalid regex")
                .font(Typo.mono(10))
                .foregroundColor(draft.canSave ? .white.opacity(0.78) : Palette.detach.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5))
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(draft.statusText)
                .font(Typo.mono(9))
                .foregroundColor(draft.canSave ? .white.opacity(0.42) : Palette.detach.opacity(0.75))
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Text("Cancel")
                    .font(Typo.monoBold(11))
                    .foregroundColor(.white.opacity(0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            Button(action: saveIfReady) {
                Text("Save")
                    .font(Typo.monoBold(11))
                    .foregroundColor(draft.canSave ? Palette.bg : .white.opacity(0.4))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(draft.canSave ? Palette.running : Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(!draft.canSave)
        }
    }

    private func saveIfReady() {
        guard draft.canSave else { return }
        onSave(draft.clause)
    }
}
