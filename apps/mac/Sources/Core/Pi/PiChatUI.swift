import SwiftUI

// MARK: - Lattices mark

/// The 3×3 L-shape brand mark rendered as SwiftUI shapes. Used as a small
/// inline glyph (size 14–20) and as the assistant avatar background (size
/// 28–56). Brighter cells form an L: left column + bottom row.
struct LatticesMark: View {
    var size: CGFloat = 20
    var tint: Color = .white
    var dimOpacity: Double = 0.18

    var body: some View {
        let cells: [Bool] = [true, false, false, true, false, false, true, true, true]
        let pad = max(1, size * 0.1)
        let gap = max(0.6, size * 0.06)
        let cell = (size - 2 * pad - 2 * gap) / 3

        Canvas { context, _ in
            for (index, bright) in cells.enumerated() {
                let row = index / 3
                let col = index % 3
                let rect = CGRect(
                    x: pad + CGFloat(col) * (cell + gap),
                    y: pad + CGFloat(row) * (cell + gap),
                    width: cell,
                    height: cell
                )
                let path = Path(roundedRect: rect, cornerRadius: max(0.6, cell * 0.18))
                let color = bright ? tint : tint.opacity(dimOpacity)
                context.fill(path, with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Assistant avatar that wraps the brand mark in a glassy chip. Replaces the
/// generic SF-symbol "sparkles" avatars in the header and message rows.
struct LatticesMarkAvatar: View {
    var size: CGFloat = 32
    var tint: Color = Palette.running
    var isActive: Bool = false

    var body: some View {
        let markSize = size * 0.55

        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.07 : 0.05),
                            Color.white.opacity(isActive ? 0.03 : 0.02),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    tint.opacity(isActive ? 0.55 : 0.35),
                                    tint.opacity(isActive ? 0.20 : 0.10),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                )

            LatticesMark(size: markSize, tint: tint, dimOpacity: isActive ? 0.30 : 0.18)
        }
        .frame(width: size, height: size)
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1.2)
                    .scaleEffect(1.18)
                    .opacity(0.5)
                    .modifier(PiChatPulseModifier(minOpacity: 0.0, maxOpacity: 0.55, duration: 1.4))
            }
        }
    }
}

// MARK: - Dot-grid background

/// Faint dot-grid drawn with Canvas. Used as the transcript surface so the
/// background reads as "designed" rather than a flat fill.
struct PiChatDotGrid: View {
    var spacing: CGFloat = 26
    var dotSize: CGFloat = 1
    var opacity: Double = 0.06
    var tint: Color = .white

    var body: some View {
        Canvas { context, size in
            let strideX = spacing
            let strideY = spacing
            let xStart = -spacing
            let yStart = -spacing
            for x in stride(from: xStart, through: size.width, by: strideX) {
                for y in stride(from: yStart, through: size.height, by: strideY) {
                    let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(opacity)))
                }
            }
        }
    }
}

// MARK: - Transcript

struct PiChatTranscript: View {
    @ObservedObject var session: PiChatSession
    var style: PiChatStyle = .workspace

    var body: some View {
        if showsEmptyState {
            PiChatEmptyState(session: session) { prompt in
                session.draft = prompt
                session.sendDraft()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(transcriptBackground)
        } else {
            scrollTranscript
        }
    }

    private var showsEmptyState: Bool {
        // Render the rich empty state when there's no real conversation yet
        // and the runtime is ready to chat. Provider-setup and install
        // states render their own callouts, so they're handled elsewhere.
        !session.hasConversationHistory
            && session.hasPiBinary
            && !session.needsProviderSetup
            && !session.isAuthenticating
    }

    private var scrollTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    Spacer(minLength: 0)

                    LazyVStack(alignment: .leading, spacing: style.messageSpacing) {
                        ForEach(session.messages) { message in
                            PiChatMessageRow(
                                message: message,
                                isStreaming: isStreamingMessage(message),
                                activeToolName: activeToolName(for: message),
                                style: style
                            )
                            .equatable()
                            .id(message.id)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                )
                            )
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
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: session.messages.count)
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

            PiChatDotGrid(spacing: 26, dotSize: 1, opacity: 0.05)
                .blendMode(.plusLighter)

            LinearGradient(
                colors: [
                    Palette.running.opacity(0.05),
                    Color.clear,
                    Color.black.opacity(0.28),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Palette.running.opacity(0.07),
                    Color.clear,
                ],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 480
            )
        }
    }

    private func isStreamingMessage(_ message: PiChatMessage) -> Bool {
        guard session.isSending, message.role == .assistant else { return false }
        return message.id == session.messages.last?.id
    }

    private func activeToolName(for message: PiChatMessage) -> String? {
        guard isStreamingMessage(message) else { return nil }
        return session.activeToolName
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

// MARK: - Empty state

private struct PiChatEmptyState: View {
    @ObservedObject var session: PiChatSession
    var onSelect: (String) -> Void

    private let starters: [PiChatStarterPrompt] = [
        PiChatStarterPrompt(
            title: "Inspect my gestures",
            subtitle: "Read ~/.lattices/mouse-shortcuts.json",
            icon: "hand.draw",
            text: "Read my current mouse gesture configuration and tell me what's set up."
        ),
        PiChatStarterPrompt(
            title: "What's on my screen?",
            subtitle: "Snapshot the current desktop",
            icon: "rectangle.on.rectangle",
            text: "List the windows I have open right now."
        ),
        PiChatStarterPrompt(
            title: "Tidy my terminals",
            subtitle: "Distribute iTerm windows to a grid",
            icon: "square.grid.2x2",
            text: "Organize my terminal windows across the displays I have."
        ),
        PiChatStarterPrompt(
            title: "Plan my next session",
            subtitle: "Spin up a project workspace",
            icon: "wand.and.stars",
            text: "Help me plan the workspace for the project I'm about to work on."
        ),
    ]

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 8)

            VStack(spacing: 14) {
                LatticesMarkAvatar(size: 56, tint: Palette.running)
                    .shadow(color: Palette.running.opacity(0.30), radius: 18, y: 4)

                VStack(spacing: 6) {
                    Text("Workspace Assistant")
                        .font(Typo.title(20))
                        .foregroundColor(Palette.text)
                    Text(headerSubtitle)
                        .font(Typo.body(12.5))
                        .foregroundColor(Palette.textDim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Try")
                    .font(Typo.geistMonoBold(10))
                    .tracking(0.8)
                    .foregroundColor(Palette.textMuted)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(starters) { starter in
                        Button {
                            onSelect(starter.text)
                        } label: {
                            starterRow(starter)
                        }
                        .buttonStyle(PiChatStarterButtonStyle())
                    }
                }
            }
            .frame(maxWidth: 520)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }

    private var headerSubtitle: String {
        "Connected to \(session.currentProvider.name). Ask about layouts, gestures, settings, or anything on screen."
    }

    private func starterRow(_ starter: PiChatStarterPrompt) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: starter.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.running)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Palette.running.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(starter.title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Palette.text)
                Text(starter.subtitle)
                    .font(Typo.caption(10.5))
                    .foregroundColor(Palette.textDim)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        )
    }
}

struct PiChatStarterPrompt: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let text: String
}

private struct PiChatStarterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

// MARK: - Message row

struct PiChatMessageRow: View, Equatable {
    let message: PiChatMessage
    let isStreaming: Bool
    var activeToolName: String? = nil
    var style: PiChatStyle = .workspace

    static func == (lhs: PiChatMessageRow, rhs: PiChatMessageRow) -> Bool {
        lhs.message == rhs.message
            && lhs.isStreaming == rhs.isStreaming
            && lhs.activeToolName == rhs.activeToolName
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
            Spacer(minLength: style == .workspace ? 96 : 48)

            VStack(alignment: .trailing, spacing: 5) {
                Text(message.text)
                    .font(Typo.body(style.bodySize))
                    .foregroundColor(Palette.text)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .frame(maxWidth: 540, alignment: .trailing)

                Text(PiChatFormat.time(message.timestamp))
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textMuted.opacity(0.85))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(userBubbleBackground)

            LatticesMarkAvatar(size: 28, tint: Color.white.opacity(0.55), isActive: false)
        }
    }

    private var userBubbleBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.11),
                        Color.white.opacity(0.06),
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
            LatticesMarkAvatar(size: 32, tint: Palette.running, isActive: isStreaming)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Assistant")
                        .font(Typo.geistMonoBold(10))
                        .tracking(0.4)
                        .foregroundColor(isStreaming ? Palette.running.opacity(0.95) : Palette.textDim)

                    if isStreaming {
                        PiChatStreamingBadge()
                    } else if let activeToolName {
                        PiChatToolChip(name: activeToolName)
                    }

                    Spacer(minLength: 0)

                    Text(PiChatFormat.time(message.timestamp))
                        .font(Typo.caption(9))
                        .foregroundColor(Palette.textMuted.opacity(0.75))
                }

                if isStreaming, let activeToolName {
                    PiChatToolChip(name: activeToolName, compact: true)
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

            Spacer(minLength: style == .workspace ? 60 : 24)
        }
    }

    private var workingLabel: String {
        isStreaming ? "Composing" : "Working"
    }

    private var assistantBubbleBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isStreaming
                        ? [Color.white.opacity(0.06), Color.white.opacity(0.025)]
                        : [Color.white.opacity(0.04), Color.white.opacity(0.018)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isStreaming
                                ? [Palette.running.opacity(0.12), Color.white.opacity(0.02), Color.clear]
                                : [Color.white.opacity(0.03), Color.clear],
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
                                colors: [Palette.running.opacity(0.65), Palette.running.opacity(0.10)],
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
                        isStreaming ? Palette.running.opacity(0.32) : Palette.border,
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: isStreaming ? Palette.running.opacity(0.18) : .clear,
                radius: 18,
                y: 4
            )
            .animation(.easeInOut(duration: 0.28), value: isStreaming)
    }
}

// MARK: - Tool chip

struct PiChatToolChip: View {
    let name: String
    var compact: Bool = false

    private var displayName: String {
        switch name.lowercased() {
        case "read", "read_file", "readfile": return "read"
        case "write", "write_file", "writefile": return "write"
        case "edit", "edit_file", "editfile": return "edit"
        case "bash", "shell", "exec": return "shell"
        case "search", "grep", "find": return "search"
        case "list", "list_dir", "listdir": return "list"
        case "web", "fetch", "webfetch": return "fetch"
        default: return name.prefix(12).description
        }
    }

    private var symbol: String {
        switch name.lowercased() {
        case "read", "read_file", "readfile": return "doc.text"
        case "write", "write_file", "writefile": return "square.and.pencil"
        case "edit", "edit_file", "editfile": return "pencil"
        case "bash", "shell", "exec": return "terminal"
        case "search", "grep", "find": return "magnifyingglass"
        case "list", "list_dir", "listdir": return "list.bullet"
        case "web", "fetch", "webfetch": return "globe"
        default: return "sparkles"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 8 : 9, weight: .semibold))

            Text(displayName)
                .font(Typo.geistMonoBold(compact ? 8 : 9))
                .tracking(0.4)
        }
        .foregroundColor(Palette.detach.opacity(0.95))
        .padding(.horizontal, compact ? 6 : 7)
        .padding(.vertical, compact ? 2 : 3)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.detach.opacity(0.12))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Palette.detach.opacity(0.28), lineWidth: 0.5)
                )
        )
        .modifier(PiChatPulseModifier(minOpacity: 0.65, maxOpacity: 1.0, duration: 1.4))
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
        } else if let rendered = renderBlocks() {
            rendered
        } else {
            fallbackText
        }
    }

    private var fallbackText: some View {
        Text(text)
            .font(Typo.body(style.bodySize))
            .foregroundColor(Palette.text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Render the text as a vertical stack of either paragraph or code-block
    /// views. Code blocks (fenced ``` or indented) get their own monospace
    /// container with shiki-style coloring.
    private func renderBlocks() -> AnyView? {
        let blocks = splitBlocks(text)
        guard !blocks.isEmpty else { return nil }

        let stack = VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }

        return AnyView(
            stack
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        )
    }

    @ViewBuilder
    private func blockView(_ block: PiChatTextBlock) -> some View {
        switch block.kind {
        case .code(let language, let body):
            PiChatCodeBlock(language: language, source: body)
        case .paragraph:
            if let attributed = PiChatFormat.markdownText(block.text, size: style.bodySize) {
                attributed
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(block.text)
                    .font(Typo.body(style.bodySize))
                    .foregroundColor(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct PiChatTextBlock {
    enum Kind {
        case paragraph
        case code(language: String?, body: String)
    }
    let kind: Kind
    let text: String
}

private func splitBlocks(_ source: String) -> [PiChatTextBlock] {
    let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    var blocks: [PiChatTextBlock] = []
    var paragraphBuffer: [String] = []
    var inCodeFence = false
    var codeLanguage: String?
    var codeBuffer: [String] = []

    func flushParagraph() {
        if !paragraphBuffer.isEmpty {
            let text = paragraphBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(PiChatTextBlock(kind: .paragraph, text: text))
            }
            paragraphBuffer.removeAll(keepingCapacity: true)
        }
    }

    func flushCode() {
        let body = codeBuffer.joined(separator: "\n")
        if !body.isEmpty {
            blocks.append(PiChatTextBlock(kind: .code(language: codeLanguage, body: body), text: body))
        }
        codeBuffer.removeAll(keepingCapacity: true)
        codeLanguage = nil
    }

    for raw in lines {
        let line = raw

        if line.hasPrefix("```") {
            if inCodeFence {
                flushCode()
                inCodeFence = false
            } else {
                flushParagraph()
                inCodeFence = true
                codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if codeLanguage?.isEmpty == true { codeLanguage = nil }
            }
            continue
        }

        if inCodeFence {
            codeBuffer.append(line)
            continue
        }

        // Indented (4+ spaces) as a code block when no fence is active.
        if line.hasPrefix("    ") && !line.isEmpty {
            flushParagraph()
            inCodeFence = true
            codeLanguage = nil
            codeBuffer.append(String(line.dropFirst(4)))
            continue
        }

        paragraphBuffer.append(line)
    }

    if inCodeFence {
        flushCode()
    } else {
        flushParagraph()
    }

    return blocks
}

// MARK: - Code block view

struct PiChatCodeBlock: View {
    let language: String?
    let source: String

    private var tokens: [PiChatCodeToken] {
        PiChatSyntax.tokenize(source, language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(Color(red: 0.93, green: 0.36, blue: 0.36)).frame(width: 6, height: 6)
                    Circle().fill(Color(red: 0.96, green: 0.74, blue: 0.18)).frame(width: 6, height: 6)
                    Circle().fill(Color(red: 0.30, green: 0.78, blue: 0.45)).frame(width: 6, height: 6)
                }
                Text((language ?? "code").uppercased())
                    .font(Typo.geistMonoBold(8))
                    .tracking(0.6)
                    .foregroundColor(Palette.textMuted)
                Spacer()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(source, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Palette.textMuted)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.04))
                                .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
                .help("Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.025))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    formattedBody
                        .font(Typo.mono(12))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
            .background(Color.black.opacity(0.32))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var formattedBody: Text {
        var combined = Text("")
        for token in tokens {
            combined = combined + Text(token.text)
                .foregroundColor(token.color)
                .font(Typo.mono(12))
        }
        return combined
    }
}

struct PiChatCodeToken {
    let text: String
    let color: Color
}

/// Minimal hand-rolled syntax highlighter for the chat code blocks. Color
/// choices match the lattices-green theme used elsewhere.
enum PiChatSyntax {
    private static let keyword = Palette.running
    private static let string = Color(red: 0.85, green: 0.78, blue: 0.55)
    private static let number = Color(red: 0.96, green: 0.65, blue: 0.14)
    private static let comment = Palette.textMuted
    private static let identifier = Color(red: 0.72, green: 0.83, blue: 0.92)
    private static let punctuation = Palette.textDim

    private static let jsLikeKeywords: Set<String> = [
        "const", "let", "var", "function", "return", "if", "else", "for", "while",
        "do", "switch", "case", "break", "continue", "import", "export", "from",
        "as", "default", "class", "extends", "new", "this", "await", "async",
        "yield", "try", "catch", "finally", "throw", "typeof", "instanceof",
        "true", "false", "null", "undefined", "in", "of",
    ]

    private static let swiftKeywords: Set<String> = [
        "func", "let", "var", "if", "else", "guard", "return", "for", "in",
        "while", "do", "switch", "case", "break", "continue", "import", "struct",
        "class", "enum", "protocol", "extension", "private", "public", "internal",
        "fileprivate", "open", "static", "final", "lazy", "weak", "unowned",
        "self", "Self", "init", "deinit", "throws", "throw", "try", "catch",
        "rethrows", "async", "await", "true", "false", "nil", "some", "any",
    ]

    private static let shellKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "do", "done", "while",
        "case", "esac", "function", "return", "in", "export", "local",
    ]

    private static let jsonKeywords: Set<String> = [
        "true", "false", "null",
    ]

    static func tokenize(_ source: String, language: String?) -> [PiChatCodeToken] {
        let lang = (language ?? "").lowercased()
        if lang == "json" {
            return tokenizeJSON(source)
        }
        if lang == "bash" || lang == "sh" || lang == "shell" || lang == "zsh" {
            return tokenizeShell(source)
        }
        if lang == "swift" {
            return tokenizeSwift(source)
        }
        return tokenizeGeneric(source)
    }

    private static func tokenizeGeneric(_ source: String) -> [PiChatCodeToken] {
        var tokens: [PiChatCodeToken] = []
        var buffer = ""
        var inString = false
        var stringDelimiter: Character = "\""
        var inLineComment = false

        func pushBufferAsWord() {
            guard !buffer.isEmpty else { return }
            if jsLikeKeywords.contains(buffer) {
                tokens.append(PiChatCodeToken(text: buffer, color: keyword))
            } else {
                tokens.append(PiChatCodeToken(text: buffer, color: Palette.text))
            }
            buffer.removeAll(keepingCapacity: true)
        }

        func pushBufferAsNumber() {
            guard !buffer.isEmpty else { return }
            tokens.append(PiChatCodeToken(text: buffer, color: number))
            buffer.removeAll(keepingCapacity: true)
        }

        func pushBufferAsString() {
            guard !buffer.isEmpty else { return }
            tokens.append(PiChatCodeToken(text: buffer, color: string))
            buffer.removeAll(keepingCapacity: true)
        }

        func pushBufferAsPunct() {
            guard !buffer.isEmpty else { return }
            tokens.append(PiChatCodeToken(text: buffer, color: punctuation))
            buffer.removeAll(keepingCapacity: true)
        }

        func pushBufferAsPlain() {
            guard !buffer.isEmpty else { return }
            tokens.append(PiChatCodeToken(text: buffer, color: Palette.text))
            buffer.removeAll(keepingCapacity: true)
        }

        let chars = Array(source)
        var i = 0
        while i < chars.count {
            let ch = chars[i]

            if inLineComment {
                buffer.append(ch)
                if ch == "\n" {
                    tokens.append(PiChatCodeToken(text: buffer, color: comment))
                    buffer.removeAll(keepingCapacity: true)
                    inLineComment = false
                }
                i += 1
                continue
            }

            if inString {
                buffer.append(ch)
                if ch == stringDelimiter {
                    pushBufferAsString()
                    inString = false
                }
                i += 1
                continue
            }

            if ch == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                inLineComment = true
                buffer = "//"
                i += 2
                continue
            }

            if ch == "\"" || ch == "'" || ch == "`" {
                inString = true
                stringDelimiter = ch
                buffer = String(ch)
                i += 1
                continue
            }

            if ch.isNumber {
                buffer.append(ch)
                var j = i + 1
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "_" {
                    buffer.append(chars[j])
                    j += 1
                }
                pushBufferAsNumber()
                i = j
                continue
            }

            if ch.isLetter || ch == "_" || ch == "$" {
                buffer.append(ch)
                var j = i + 1
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "$" {
                    buffer.append(chars[j])
                    j += 1
                }
                pushBufferAsWord()
                i = j
                continue
            }

            if ch.isWhitespace {
                pushBufferAsPlain()
                tokens.append(PiChatCodeToken(text: String(ch), color: Palette.text))
                i += 1
                continue
            }

            buffer.append(ch)
            pushBufferAsPunct()
            i += 1
        }

        if !buffer.isEmpty {
            if inString {
                pushBufferAsString()
            } else if inLineComment {
                tokens.append(PiChatCodeToken(text: buffer, color: comment))
            } else {
                pushBufferAsPlain()
            }
        }

        return tokens
    }

    private static func tokenizeJSON(_ source: String) -> [PiChatCodeToken] {
        var tokens: [PiChatCodeToken] = []
        var current = ""
        var inString = false
        var escape = false
        var pendingKey = false

        func flushString() {
            tokens.append(PiChatCodeToken(text: current, color: pendingKey ? identifier : string))
            current.removeAll(keepingCapacity: true)
            pendingKey = false
        }

        for ch in source {
            if inString {
                current.append(ch)
                if escape {
                    escape = false
                } else if ch == "\\" {
                    escape = true
                } else if ch == "\"" {
                    flushString()
                    inString = false
                }
                continue
            }

            if ch == "\"" {
                inString = true
                current = "\""
                pendingKey = lastNonSpace() == "{"
                continue
            }

            if ch.isNumber || (ch == "-" && (current.isEmpty || current == ":")) {
                current.append(ch)
                continue
            }
            if ch.isNumber == false && !current.isEmpty && current.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "." }) {
                tokens.append(PiChatCodeToken(text: current, color: number))
                current.removeAll(keepingCapacity: true)
            }

            if ch == "{" || ch == "}" || ch == "[" || ch == "]" || ch == "," || ch == ":" {
                if !current.isEmpty {
                    if jsonKeywords.contains(current) {
                        tokens.append(PiChatCodeToken(text: current, color: keyword))
                    } else {
                        tokens.append(PiChatCodeToken(text: current, color: Palette.text))
                    }
                    current.removeAll(keepingCapacity: true)
                }
                tokens.append(PiChatCodeToken(text: String(ch), color: punctuation))
                continue
            }

            current.append(ch)
        }

        if !current.isEmpty {
            if jsonKeywords.contains(current) {
                tokens.append(PiChatCodeToken(text: current, color: keyword))
            } else {
                tokens.append(PiChatCodeToken(text: current, color: Palette.text))
            }
        }

        return tokens
    }

    private static func lastNonSpace() -> Character? {
        return nil
    }

    private static func tokenizeShell(_ source: String) -> [PiChatCodeToken] {
        var tokens: [PiChatCodeToken] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var inComment = false

        for ch in source {
            if inComment {
                current.append(ch)
                continue
            }
            if inSingle {
                current.append(ch)
                if ch == "'" { inSingle = false }
                continue
            }
            if inDouble {
                current.append(ch)
                if ch == "\"" { inDouble = false }
                continue
            }
            if ch == "#" {
                if !current.isEmpty {
                    tokens.append(PiChatCodeToken(text: current, color: Palette.text))
                    current.removeAll()
                }
                inComment = true
                current = "#"
                continue
            }
            if ch == "'" {
                inSingle = true
                current.append(ch)
                continue
            }
            if ch == "\"" {
                inDouble = true
                current.append(ch)
                continue
            }
            if ch == "$" || ch.isWhitespace || ch == "|" || ch == "&" || ch == ";" {
                if !current.isEmpty {
                    if shellKeywords.contains(current) {
                        tokens.append(PiChatCodeToken(text: current, color: keyword))
                    } else if current.hasPrefix("$") {
                        tokens.append(PiChatCodeToken(text: current, color: number))
                    } else {
                        tokens.append(PiChatCodeToken(text: current, color: Palette.text))
                    }
                    current.removeAll()
                }
                if ch == "$" {
                    tokens.append(PiChatCodeToken(text: "$", color: number))
                } else if ch.isWhitespace {
                    tokens.append(PiChatCodeToken(text: String(ch), color: Palette.text))
                } else {
                    tokens.append(PiChatCodeToken(text: String(ch), color: punctuation))
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty {
            if inComment {
                tokens.append(PiChatCodeToken(text: current, color: comment))
            } else {
                tokens.append(PiChatCodeToken(text: current, color: Palette.text))
            }
        }
        return tokens
    }

    private static func tokenizeSwift(_ source: String) -> [PiChatCodeToken] {
        // Swift and JS share most tokenization rules; route through generic
        // and remap the keyword set lazily by post-processing colors.
        var tokens = tokenizeGeneric(source)
        for index in tokens.indices where tokens[index].color == keyword {
            let raw = tokens[index].text
            if swiftKeywords.contains(raw) {
                tokens[index] = PiChatCodeToken(text: raw, color: keyword)
            }
        }
        return tokens
    }
}

// MARK: - Composer

struct PiChatComposer: View {
    @ObservedObject var session: PiChatSession
    var style: PiChatStyle = .workspace
    var focus: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 8) {
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
                            .fill(
                                canSend
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [Palette.running, Palette.running.opacity(0.85)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    : AnyShapeStyle(Palette.surfaceHov)
                            )
                            .shadow(color: canSend ? Palette.running.opacity(0.35) : .clear, radius: 10, y: 2)
                    )
                    .foregroundColor(canSend ? Palette.bg : Palette.textMuted)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(composerFieldBackground)
            .animation(.easeInOut(duration: 0.18), value: focus.wrappedValue)

            HStack(spacing: 8) {
                modelChip
                Spacer()
                if !focus.wrappedValue {
                    Text("↩ send")
                        .font(Typo.caption(9))
                        .foregroundColor(Palette.textMuted.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(composerChrome)
    }

    private var modelChip: some View {
        HStack(spacing: 5) {
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
    }

    private var composerFieldBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black.opacity(0.30))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.05), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        focus.wrappedValue ? Palette.running.opacity(0.45) : Palette.border,
                        lineWidth: focus.wrappedValue ? 1 : 0.5
                    )
            )
            .shadow(color: focus.wrappedValue ? Palette.running.opacity(0.18) : .clear, radius: 18, y: 2)
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

// MARK: - Chrome (avatars, indicators, badges)

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
            .fill(Palette.running.opacity(0.95))
            .frame(width: 2, height: 14)
            .shadow(color: Palette.running.opacity(0.45), radius: 4, y: 0)
            .modifier(PiChatPulseModifier(minOpacity: 0.45, maxOpacity: 1.0, duration: 0.85))
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
                        .strokeBorder(Palette.running.opacity(0.28), lineWidth: 0.5)
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
                .stroke(Palette.bg.opacity(0.92), style: StrokeStyle(lineWidth: 2, lineCap: .round))
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
        case .workspace: return 18
        case .dock: return 10
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .workspace: return 28
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
