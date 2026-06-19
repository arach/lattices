import SwiftUI
import HudsonUI

enum HudComposerPhase: Equatable {
    case idle
    case streaming
}

enum HudComposerLayout: Equatable {
    case stacked
}

enum HudComposerAction: Equatable {
    case submit
    case queue
    case steer
    case stop
}

struct HudComposerQueuedItem: Identifiable, Equatable {
    let id: UUID
    var text: String
}

struct HudComposerModelInfo: Equatable {
    var model: String
    var effort: String?
}

struct HudComposerStyle: Equatable {
    var placeholder: String
    var fontSize: CGFloat
    var lineLimit: ClosedRange<Int>

    init(
        placeholder: String = "Message",
        fontSize: CGFloat = 12,
        lineLimit: ClosedRange<Int> = 1...4
    ) {
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.lineLimit = lineLimit
    }
}

struct HudComposer<TrailingAccessory: View>: View {
    @Binding var text: String
    var phase: HudComposerPhase
    var queued: [HudComposerQueuedItem]
    var style: HudComposerStyle
    var layout: HudComposerLayout
    var focus: FocusState<Bool>.Binding
    @ViewBuilder var trailingAccessory: () -> TrailingAccessory
    var onAction: (HudComposerAction) -> Void
    var onRemoveQueued: (HudComposerQueuedItem) -> Void
    var onEditQueued: (HudComposerQueuedItem) -> Void
    var model: HudComposerModelInfo?
    var onAddAttachment: () -> Void

    @Environment(\.hudTheme) private var theme

    init(
        text: Binding<String>,
        phase: HudComposerPhase = .idle,
        queued: [HudComposerQueuedItem] = [],
        style: HudComposerStyle = HudComposerStyle(),
        layout: HudComposerLayout = .stacked,
        focus: FocusState<Bool>.Binding,
        @ViewBuilder trailingAccessory: @escaping () -> TrailingAccessory,
        onAction: @escaping (HudComposerAction) -> Void,
        onRemoveQueued: @escaping (HudComposerQueuedItem) -> Void,
        onEditQueued: @escaping (HudComposerQueuedItem) -> Void,
        model: HudComposerModelInfo? = nil,
        onAddAttachment: @escaping () -> Void = {}
    ) {
        self._text = text
        self.phase = phase
        self.queued = queued
        self.style = style
        self.layout = layout
        self.focus = focus
        self.trailingAccessory = trailingAccessory
        self.onAction = onAction
        self.onRemoveQueued = onRemoveQueued
        self.onEditQueued = onEditQueued
        self.model = model
        self.onAddAttachment = onAddAttachment
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !queued.isEmpty {
                queuedRows
            }

            VStack(alignment: .leading, spacing: 9) {
                TextField(style.placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typo.body(style.fontSize))
                    .foregroundColor(Palette.text)
                    .lineLimit(style.lineLimit)
                    .focused(focus)
                    .onSubmit { submitFromKeyboard() }

                controlRow
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(fieldBackground)
        }
    }

    private var controlRow: some View {
        HStack(alignment: .center, spacing: 8) {
            iconButton(
                systemName: "plus",
                foreground: Palette.textMuted,
                background: Color.white.opacity(0.04),
                border: Palette.border,
                help: "Add attachment",
                action: onAddAttachment
            )

            if let model {
                modelChip(model)
            }

            Spacer(minLength: 0)

            trailingAccessory()

            if phase == .streaming && hasText {
                iconButton(
                    systemName: "arrow.triangle.2.circlepath",
                    foreground: Palette.detach,
                    background: Palette.detach.opacity(0.10),
                    border: Palette.detach.opacity(0.25),
                    help: "Steer with draft"
                ) {
                    onAction(.steer)
                }
            }

            primaryActionButton
        }
    }

    private var primaryActionButton: some View {
        Button {
            onAction(primaryAction)
        } label: {
            Image(systemName: primaryIcon)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(primaryForeground)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(primaryBackground)
                        .overlay(Circle().strokeBorder(primaryBorder, lineWidth: 0.5))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(primaryDisabled)
        .help(primaryHelp)
        .animation(.easeInOut(duration: 0.15), value: phase)
        .animation(.easeInOut(duration: 0.15), value: hasText)
    }

    private var queuedRows: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(queued) { item in
                HStack(spacing: 7) {
                    Image(systemName: "clock")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(Palette.detach.opacity(0.86))

                    Text(item.text)
                        .font(Typo.caption(10))
                        .foregroundColor(Palette.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    Button {
                        onEditQueued(item)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Palette.textMuted)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit queued draft")

                    Button {
                        onRemoveQueued(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Palette.textMuted)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove queued draft")
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                )
            }
        }
        .padding(.horizontal, 14)
    }

    private func modelChip(_ model: HudComposerModelInfo) -> some View {
        HStack(spacing: 5) {
            Text(model.model)
                .lineLimit(1)
                .truncationMode(.tail)
            if let effort = model.effort, !effort.isEmpty {
                Text("/")
                    .foregroundColor(Palette.textMuted.opacity(0.7))
                Text(effort)
                    .lineLimit(1)
            }
        }
        .font(Typo.mono(9.5))
        .foregroundColor(Palette.textMuted)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(Capsule(style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
        )
    }

    private func iconButton(
        systemName: String,
        foreground: Color,
        background: Color,
        border: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(foreground)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(background)
                        .overlay(Circle().strokeBorder(border, lineWidth: 0.5))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func submitFromKeyboard() {
        guard hasText else { return }
        onAction(phase == .streaming ? .queue : .submit)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.025))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        focus.wrappedValue ? Palette.borderLit : Palette.border,
                        lineWidth: 0.5
                    )
            )
    }

    private var primaryAction: HudComposerAction {
        if phase == .streaming {
            return hasText ? .queue : .stop
        }
        return .submit
    }

    private var primaryIcon: String {
        switch primaryAction {
        case .submit, .queue: return "arrow.up"
        case .steer:          return "arrow.triangle.2.circlepath"
        case .stop:           return "stop.fill"
        }
    }

    private var primaryHelp: String {
        switch primaryAction {
        case .submit: return hasText ? "Send" : ""
        case .queue:  return "Queue draft"
        case .steer:  return "Steer with draft"
        case .stop:   return "Stop"
        }
    }

    private var primaryDisabled: Bool {
        phase == .idle && !hasText
    }

    private var primaryForeground: Color {
        if primaryDisabled {
            return Palette.textMuted.opacity(0.7)
        }
        return primaryAction == .stop ? .white : Palette.bg
    }

    private var primaryBackground: Color {
        if primaryDisabled {
            return Color.white.opacity(0.05)
        }
        switch primaryAction {
        case .submit, .queue:
            return Palette.running
        case .steer:
            return Palette.detach
        case .stop:
            return Palette.kill.opacity(0.9)
        }
    }

    private var primaryBorder: Color {
        primaryDisabled ? Palette.border : Color.clear
    }

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
