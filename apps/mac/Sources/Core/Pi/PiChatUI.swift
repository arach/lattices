import SwiftUI

// MARK: - Transcript

struct PiChatTranscript: View {
    @ObservedObject var session: PiChatSession
    var style: PiChatStyle = .workspace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    Spacer(minLength: 0)

                    LazyVStack(alignment: .leading, spacing: style.messageSpacing) {
                        ForEach(session.messages) { message in
                            PiChatMessageRow(
                                message: message,
                                isStreaming: isStreamingMessage(message),
                                style: style
                            )
                            .equatable()
                            .id(message.id)
                        }
                    }
                    .frame(maxWidth: style.maxContentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.vertical, style.verticalPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .scrollIndicators(.visible)
            .background(transcriptBackground)
            .onAppear { scrollToEnd(proxy: proxy, animated: false) }
            .onChange(of: session.messages.count) { _ in
                scrollToEnd(proxy: proxy, animated: true)
            }
            .onChange(of: session.messages.last?.text) { _ in
                if session.isSending {
                    scrollToEnd(proxy: proxy, animated: false)
                }
            }
            .onChange(of: session.isSending) { sending in
                if sending {
                    scrollToEnd(proxy: proxy, animated: true)
                }
            }
        }
    }

    private var transcriptBackground: some View {
        ZStack {
            Palette.bg

            LinearGradient(
                colors: [
                    Palette.running.opacity(0.04),
                    Color.clear,
                    Color.black.opacity(0.22),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Palette.running.opacity(0.06),
                    Color.clear,
                ],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 420
            )
        }
    }

    private func isStreamingMessage(_ message: PiChatMessage) -> Bool {
        guard session.isSending, message.role == .assistant else { return false }
        return message.id == session.messages.last?.id
    }

    private func scrollToEnd(proxy: ScrollViewProxy, animated: Bool) {
        guard let last = session.messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo(last, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }
}

// MARK: - Message row

struct PiChatMessageRow: View, Equatable {
    let message: PiChatMessage
    let isStreaming: Bool
    var style: PiChatStyle = .workspace

    static func == (lhs: PiChatMessageRow, rhs: PiChatMessageRow) -> Bool {
        lhs.message == rhs.message
            && lhs.isStreaming == rhs.isStreaming
            && lhs.style == rhs.style
    }

    var body: some View {
        switch message.role {
        case .system:
            systemRow
        case .user:
            userRow
        case .assistant:
            assistantRow
        }
    }

    private var systemRow: some View {
        HStack {
            Spacer(minLength: 0)
            Text(message.text)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textDim)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                )
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var userRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Spacer(minLength: style == .workspace ? 72 : 36)

            VStack(alignment: .trailing, spacing: 5) {
                Text(message.text)
                    .font(Typo.body(style.bodySize))
                    .foregroundColor(Palette.text)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)

                Text(PiChatFormat.time(message.timestamp))
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textMuted.opacity(0.85))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(userBubbleBackground)

            PiChatAvatar(symbol: "person.fill", tint: Color.white.opacity(0.55))
        }
    }

    private var userBubbleBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.09),
                        Color.white.opacity(0.05),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
    }

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 10) {
            PiChatAvatar(
                symbol: "sparkles",
                tint: Palette.running,
                isActive: isStreaming
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Assistant")
                        .font(Typo.geistMonoBold(10))
                        .tracking(0.4)
                        .foregroundColor(isStreaming ? Palette.running.opacity(0.92) : Palette.textDim)

                    if isStreaming {
                        PiChatStreamingBadge()
                    }

                    Spacer(minLength: 0)

                    Text(PiChatFormat.time(message.timestamp))
                        .font(Typo.caption(9))
                        .foregroundColor(Palette.textMuted.opacity(0.75))
                }

                Group {
                    if message.text.isEmpty, isStreaming {
                        PiChatWorkingIndicator(label: workingLabel)
                    } else {
                        PiChatFormattedText(
                            message.text,
                            style: style,
                            isStreaming: isStreaming
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(assistantBubbleBackground)

            Spacer(minLength: style == .workspace ? 40 : 20)
        }
    }

    private var workingLabel: String {
        isStreaming ? "Composing" : "Working"
    }

    private var assistantBubbleBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(isStreaming ? 0.045 : 0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isStreaming
                                ? [Palette.running.opacity(0.10), Color.white.opacity(0.02), Color.clear]
                                : [Color.white.opacity(0.025), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(alignment: .leading) {
                if isStreaming {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Palette.running.opacity(0.55), Palette.running.opacity(0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2)
                        .padding(.vertical, 6)
                        .clipShape(Capsule())
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isStreaming ? Palette.running.opacity(0.30) : Palette.border,
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: isStreaming ? Palette.running.opacity(0.14) : .clear,
                radius: 14,
                y: 2
            )
            .animation(.easeInOut(duration: 0.28), value: isStreaming)
    }
}

// MARK: - Formatted text

struct PiChatFormattedText: View, Equatable {
    let text: String
    var style: PiChatStyle = .workspace
    var isStreaming: Bool = false

    init(_ text: String, style: PiChatStyle = .workspace, isStreaming: Bool = false) {
        self.text = text
        self.style = style
        self.isStreaming = isStreaming
    }

    static func == (lhs: PiChatFormattedText, rhs: PiChatFormattedText) -> Bool {
        lhs.text == rhs.text && lhs.isStreaming == rhs.isStreaming && lhs.style == rhs.style
    }

    var body: some View {
        if isStreaming {
            streamingText
        } else if let rendered = PiChatFormat.markdownText(text, size: style.bodySize) {
            rendered
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
                .font(Typo.body(style.bodySize))
                .foregroundColor(Palette.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var streamingText: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(text)
                .font(Typo.body(style.bodySize))
                .foregroundColor(Palette.text)
                .textSelection(.enabled)

            PiChatStreamCursor()
                .padding(.leading, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Composer

struct PiChatComposer: View {
    @ObservedObject var session: PiChatSession
    var style: PiChatStyle = .workspace
    var focus: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    style.placeholder,
                    text: $session.draft,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(Typo.body(style.composerSize))
                .foregroundColor(Palette.text)
                .lineLimit(1...style.composerLineLimit)
                .focused(focus)
                .onSubmit {
                    if canSend {
                        session.sendDraft()
                    }
                }

                Button {
                    session.sendDraft()
                } label: {
                    Group {
                        if session.isSending {
                            PiChatSendSpinner()
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(canSend ? Palette.running : Palette.surfaceHov)
                    )
                    .foregroundColor(canSend ? Palette.bg : Palette.textMuted)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(composerFieldBackground)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    if session.isSending {
                        PiChatStatusPulse(color: statusColor)
                    } else {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                    }
                    Text(statusLabel)
                        .font(Typo.caption(10))
                        .foregroundColor(Palette.textMuted)
                }

                Spacer()

                Text("↩ send")
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textMuted.opacity(0.7))
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(composerChrome)
    }

    private var composerFieldBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black.opacity(0.28))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.04), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        focus.wrappedValue ? Palette.running.opacity(0.38) : Palette.border,
                        lineWidth: focus.wrappedValue ? 1 : 0.5
                    )
            )
    }

    private var composerChrome: some View {
        Palette.surface.opacity(0.22)
            .overlay(Rectangle().fill(Palette.border).frame(height: 0.5), alignment: .top)
    }

    private var canSend: Bool {
        !session.isSending && !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusColor: Color {
        if session.isSending { return Palette.detach }
        if session.needsProviderSetup || !session.hasPiBinary { return Palette.kill }
        return Palette.running
    }

    private var statusLabel: String {
        if session.isSending {
            switch session.statusText {
            case "streaming...": return "Streaming · \(session.currentProvider.name)"
            case "tool:": return session.statusText + " · \(session.currentProvider.name)"
            default:
                if session.statusText.hasPrefix("tool:") {
                    return "\(session.statusText) · \(session.currentProvider.name)"
                }
                return "Working · \(session.currentProvider.name)"
            }
        }
        return session.currentProvider.name
    }
}

// MARK: - Chrome

struct PiChatAvatar: View {
    let symbol: String
    let tint: Color
    var isActive: Bool = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(tint.opacity(isActive ? 0.16 : 0.10))
                    .overlay(Circle().strokeBorder(tint.opacity(isActive ? 0.32 : 0.20), lineWidth: 0.5))
            )
            .overlay {
                if isActive {
                    Circle()
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1.5)
                        .scaleEffect(1.12)
                        .opacity(0.55)
                        .modifier(PiChatPulseModifier())
                }
            }
    }
}

struct PiChatWorkingIndicator: View {
    var label: String = "Working"

    var body: some View {
        HStack(spacing: 10) {
            PiChatWaveDots()

            Text(label)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textDim)
        }
        .padding(.vertical, 2)
        .accessibilityLabel(label)
    }
}

struct PiChatWaveDots: View {
    var dotSize: CGFloat = 6
    var spacing: CGFloat = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = sin(time * 3.6 + Double(index) * 0.85)
                    let phase = (wave + 1) / 2
                    let scale = 0.68 + 0.34 * phase
                    let opacity = 0.32 + 0.68 * phase

                    Circle()
                        .fill(Palette.running.opacity(opacity))
                        .frame(width: dotSize * scale, height: dotSize * scale)
                }
            }
            .frame(height: dotSize, alignment: .center)
        }
    }
}

struct PiChatStreamCursor: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Palette.running.opacity(0.85))
            .frame(width: 2, height: 14)
            .modifier(PiChatPulseModifier(minOpacity: 0.35, maxOpacity: 1.0, duration: 0.85))
    }
}

struct PiChatStreamingBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Palette.running)
                .frame(width: 5, height: 5)
                .modifier(PiChatPulseModifier(minOpacity: 0.45, maxOpacity: 1.0, duration: 1.1))

            Text("LIVE")
                .font(Typo.geistMonoBold(9))
                .tracking(0.6)
                .foregroundColor(Palette.running)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.running.opacity(0.12))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Palette.running.opacity(0.24), lineWidth: 0.5)
                )
        )
    }
}

struct PiChatStatusPulse: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: 10, height: 10)
                .modifier(PiChatPulseModifier(minOpacity: 0.15, maxOpacity: 0.55, duration: 1.2))

            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
    }
}

struct PiChatSendSpinner: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
            Circle()
                .trim(from: 0.08, to: 0.62)
                .stroke(Palette.bg.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(angle))
                .frame(width: 14, height: 14)
        }
    }
}

private struct PiChatPulseModifier: ViewModifier {
    var minOpacity: Double = 0.25
    var maxOpacity: Double = 0.9
    var duration: Double = 1.0

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = sin(timeline.date.timeIntervalSinceReferenceDate * (.pi * 2 / duration))
            let opacity = minOpacity + (maxOpacity - minOpacity) * ((phase + 1) / 2)
            content.opacity(opacity)
        }
    }
}

// MARK: - Style & formatting

enum PiChatStyle: Equatable {
    case workspace
    case dock

    var maxContentWidth: CGFloat {
        switch self {
        case .workspace: return 720
        case .dock: return .infinity
        }
    }

    var messageSpacing: CGFloat {
        switch self {
        case .workspace: return 16
        case .dock: return 10
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .workspace: return 24
        case .dock: return 12
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .workspace: return 20
        case .dock: return 10
        }
    }

    var bodySize: CGFloat {
        switch self {
        case .workspace: return 13.5
        case .dock: return 12
        }
    }

    var composerSize: CGFloat {
        switch self {
        case .workspace: return 13
        case .dock: return 12
        }
    }

    var composerLineLimit: Int {
        switch self {
        case .workspace: return 8
        case .dock: return 4
        }
    }

    var placeholder: String {
        "Message the assistant…"
    }
}

enum PiChatFormat {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func markdownText(_ source: String, size: CGFloat) -> Text? {
        let normalized = normalizeMarkdownTables(source)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        guard let attributed = try? AttributedString(markdown: normalized, options: options) else {
            return nil
        }
        return Text(attributed)
            .font(Typo.body(size))
            .foregroundColor(Palette.text)
    }

    /// Pipe tables from the model render more reliably with a blank line before them.
    private static func normalizeMarkdownTables(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return text }

        var output: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let isTableRow = line.contains("|") && line.filter({ $0 != "|" && !$0.isWhitespace }).count > 0
            let prev = output.last
            let prevIsBlank = prev?.trimmingCharacters(in: .whitespaces).isEmpty ?? true

            if isTableRow, let prev, !prevIsBlank, !prev.contains("|") {
                output.append("")
            }

            output.append(line)
            index += 1
        }
        return output.joined(separator: "\n")
    }
}
