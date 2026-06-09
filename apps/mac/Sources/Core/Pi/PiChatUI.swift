import SwiftUI
import HudsonUI
#if canImport(HudsonVoice)
import HudsonVoice
#endif

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

/// Scroll sample used to tell a user's upward scroll apart from content growth.
private struct ScrollProbe: Equatable {
    var offsetY: CGFloat
    var atBottom: Bool
}

struct PiChatTranscript: View {
    @ObservedObject var session: PiChatSession
    var style: PiChatStyle = .workspace

    /// True while the viewport is at (or near) the bottom. Auto-follow only
    /// happens while pinned; scrolling up detaches and stops the chase until
    /// the user returns to the bottom.
    @State private var isPinnedToBottom = true

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
            // Detach only on a genuine *upward* scroll — never because content
            // grew underneath us (that would un-pin us mid-stream and stop the
            // follow). Re-pin when the user lands back near the bottom.
            .onScrollGeometryChange(for: ScrollProbe.self) { geo in
                let maxOffset = geo.contentSize.height - geo.containerSize.height + geo.contentInsets.bottom
                return ScrollProbe(offsetY: geo.contentOffset.y, atBottom: geo.contentOffset.y >= maxOffset - 48)
            } action: { old, new in
                if new.offsetY < old.offsetY - 2 {
                    isPinnedToBottom = false          // user scrolled up
                } else if new.atBottom {
                    isPinnedToBottom = true            // user returned to the end
                }
            }
            .onAppear { scrollToEnd(proxy: proxy, animated: false) }
            .onChange(of: session.messages.count) { _ in
                // New message: follow only if the user is still pinned to the end.
                if isPinnedToBottom { scrollToEnd(proxy: proxy, animated: true) }
            }
            .onChange(of: session.messages.last?.text) { _ in
                // Chase the live edge while pinned. Not gated on isSending: the
                // closing drain reveals the tail *after* isSending flips false.
                if isPinnedToBottom { scrollToEnd(proxy: proxy, animated: false) }
            }
            .onChange(of: session.isSending) { sending in
                // Sending re-pins: a fresh turn always snaps you back to the end.
                if sending {
                    isPinnedToBottom = true
                    scrollToEnd(proxy: proxy, animated: true)
                }
            }
        }
    }

    private var transcriptBackground: some View {
        ZStack {
            Palette.bg

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.14)

            Rectangle()
                .fill(Color.white.opacity(0.010))

            Rectangle()
                .fill(Color.black.opacity(0.18))

            PiChatDotGrid(spacing: 26, dotSize: 1, opacity: 0.035, tint: Palette.textMuted)
                .blendMode(.plusLighter)
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
            VStack(spacing: 14) {
                LatticesMarkAvatar(size: 56, tint: Palette.running)
                    .shadow(color: Palette.running.opacity(0.30), radius: 18, y: 4)

                VStack(spacing: 6) {
                    Text("Workspace Assistant")
                        .font(Typo.title(20))
                        .foregroundColor(Palette.text)
                    Text(headerSubtitle)
                        .font(Typo.body(12))
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
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Palette.text)
                Text(starter.subtitle)
                    .font(Typo.caption(10))
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
                .fill(.ultraThinMaterial)
                .opacity(0.34)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.025))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
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
        AgentTurnView(turn: turn, style: style)
    }

    /// Map this transport-specific message onto the transport-agnostic turn
    /// model the renderer consumes.
    private var turn: AgentTurn {
        AgentTurn(
            id: message.id,
            role: agentRole,
            author: agentAuthor,
            timestamp: message.timestamp,
            text: message.text,
            isStreaming: isStreaming,
            toolActivity: activeToolName
        )
    }

    private var agentRole: AgentTurnRole {
        switch message.role {
        case .system:    return .system
        case .user:      return .user
        case .assistant: return .assistant
        }
    }

    private var agentAuthor: String {
        switch message.role {
        case .system:    return ""
        case .user:      return "You"
        case .assistant: return "Assistant"
        }
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        } else {
            PiChatMarkdownView(text: text, style: style)
        }
    }

    private var fallbackText: some View {
        Text(text)
            .font(Typo.reading(style.bodySize))
            .foregroundColor(Palette.text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streamingText: some View {
        // Split the (drained) text into stanzas. Word-level growth happens within
        // the trailing stanza — that just updates its Text, no transition. A new
        // stanza appearing is an insertion, so it fades + slides up as a unit:
        // the "settle" motion. The cursor rides the last stanza.
        let stanzas = text.components(separatedBy: "\n\n")
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(stanzas.enumerated()), id: \.offset) { index, stanza in
                Group {
                    if index == stanzas.count - 1 {
                        // The live, growing paragraph: words materialize in + caret.
                        PiChatRevealParagraph(text: stanza, size: style.bodySize)
                    } else {
                        // Settled paragraphs read as plain copy.
                        Text(stanza)
                            .font(Typo.reading(style.bodySize))
                            .foregroundColor(Palette.text)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity
                            .combined(with: .move(edge: .bottom))
                            .combined(with: .scale(scale: 0.97, anchor: .leading)),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Animate only on stanza-count changes, so per-word growth stays smooth
        // (no layout jitter) while a landing stanza settles with a soft spring.
        .animation(
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82),
            value: stanzas.count
        )
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

    // Renders through HudsonUI's shared `HudCodeBlock` — the tokenizer that
    // lived here was donated upstream (as `HudCodeSyntax`) so highlighting is
    // maintained once, in the kit. Thin adapter; call sites stay stable.
    var body: some View {
        HudCodeBlock(language: language, source: source)
    }
}
// MARK: - Composer

struct PiChatComposer: View {
    @ObservedObject var session: PiChatSession
    var style: PiChatStyle = .workspace
    var focus: FocusState<Bool>.Binding

    #if canImport(HudsonVoice)
    @ObservedObject private var voice = WorkspaceVoiceInput.shared
    @State private var micPulse = false
    #endif

    var body: some View {
        VStack(spacing: 7) {
            #if canImport(HudsonVoice)
            if voice.state.isCaptureActive || voice.state.isProcessing {
                dictationStrip
            }
            #endif

            HStack(alignment: .center, spacing: 10) {
                #if canImport(HudsonVoice)
                micButton
                #endif

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

                sendButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(composerFieldBackground)

            #if canImport(HudsonVoice)
            statusLine
            #endif
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(composerChrome)
    }

    #if canImport(HudsonVoice)
    /// HudsonVoice-powered mic. Tap to dictate into the draft; tap again to commit.
    /// Filled-circle states (after OpenScout's ScoutMicButton): a soft halo breathes
    /// while recording; the glyph, fill, and ring track idle/recording/processing.
    private var micButton: some View {
        Button {
            voice.toggle()
        } label: {
            ZStack {
                if voice.state.isCaptureActive {
                    Circle()
                        .fill(micAccent.opacity(micPulse ? 0.24 : 0.10))
                        .frame(width: 34, height: 34)
                }
                Circle()
                    .fill(micFill)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle().strokeBorder(micStroke, lineWidth: voice.state.isCaptureActive ? 1.2 : 0.5)
                    )
                Image(systemName: micSymbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(micTint)
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .help(micTooltip)
        .disabled(session.isSending)
        .animation(.easeInOut(duration: 0.18), value: voice.state)
        .onChange(of: voice.state.isCaptureActive) {
            if voice.state.isCaptureActive {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    micPulse = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { micPulse = false }
            }
        }
    }

    /// Live dictation strip above the field: a 5-bar waveform with the running
    /// partial transcript beside it. Shown only while the mic is hot.
    private var dictationStrip: some View {
        HStack(spacing: 9) {
            PiChatWaveform(tint: micAccent)
            if !voice.partial.isEmpty {
                Text(voice.partial)
                    .font(Typo.body(style.composerSize))
                    .foregroundColor(Palette.textDim)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .transition(.opacity)
    }

    /// One quiet mono line under the field: dictation state while the mic is hot,
    /// a faint affordance hint when idle.
    private var statusLine: some View {
        HStack(spacing: 0) {
            Text(statusText)
                .font(Typo.mono(9.5))
                .tracking(0.3)
                .foregroundColor(statusTint)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.18), value: voice.state)
    }

    private var micSymbol: String {
        switch voice.state {
        case .recording, .starting: return "mic.fill"
        case .processing: return "waveform"
        case .unavailable: return "mic.slash"
        case .idle: return "mic"
        }
    }

    /// Accent for the hot mic — red while recording (matches the "mic goes red"
    /// affordance), amber while transcribing.
    private var micAccent: Color {
        switch voice.state {
        case .processing: return Palette.detach
        default: return Palette.kill
        }
    }

    private var micFill: Color {
        switch voice.state {
        case .recording, .starting: return Palette.kill.opacity(0.16)
        case .processing: return Palette.detach.opacity(0.14)
        case .unavailable: return Color.white.opacity(0.02)
        case .idle: return Color.white.opacity(0.04)
        }
    }

    private var micStroke: Color {
        switch voice.state {
        case .recording, .starting: return Palette.kill.opacity(0.5)
        case .processing: return Palette.detach.opacity(0.45)
        case .unavailable: return Palette.border.opacity(0.6)
        case .idle: return Palette.border
        }
    }

    private var micTint: Color {
        switch voice.state {
        case .recording, .starting: return Palette.kill
        case .processing: return Palette.detach
        case .unavailable: return Palette.textMuted.opacity(0.6)
        case .idle: return Palette.textMuted
        }
    }

    private var micTooltip: String {
        switch voice.state {
        case .idle: return "Tap to dictate"
        case .starting: return "Starting…"
        case .recording: return "Recording — tap to commit"
        case .processing: return "Transcribing…"
        case .unavailable(let reason): return reason
        }
    }

    private var statusText: String {
        switch voice.state {
        case .idle: return "Tap mic to dictate · ↵ to send"
        case .starting: return "Starting…"
        case .recording: return "Listening — tap mic to commit"
        case .processing: return "Transcribing…"
        case .unavailable(let reason): return reason
        }
    }

    private var statusTint: Color {
        switch voice.state {
        case .recording, .starting: return Palette.kill.opacity(0.85)
        case .processing, .unavailable: return Palette.detach.opacity(0.85)
        case .idle: return Palette.textMuted.opacity(0.7)
        }
    }
    #endif

    /// Calm filled-circle send (after OpenScout's ScoutSendButton): a solid accent
    /// disc with an up-arrow when there's something to send, a quiet hollow ring
    /// otherwise. No glow, no keycap clutter.
    private var sendButton: some View {
        Button {
            session.sendDraft()
        } label: {
            Image(systemName: session.isSending ? "ellipsis" : "arrow.up")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(canSend ? Palette.bg : Palette.textMuted.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(canSend ? Palette.running : Color.white.opacity(0.05))
                        .overlay(
                            Circle().strokeBorder(canSend ? Color.clear : Palette.border, lineWidth: 0.5)
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help(canSend ? "Send (↵)" : "")
        .animation(.easeInOut(duration: 0.15), value: canSend)
    }

    // Flat composer field — hairline border, no focus glow, no running-tinted
    // halo. The "glowy" look the operator flagged is gone; affordance comes
    // from a single 0.5pt border that brightens slightly on focus.
    private var composerFieldBackground: some View {
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

    private var composerChrome: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.12)
            Palette.surface.opacity(0.18)
        }
            .overlay(Rectangle().fill(Palette.border).frame(height: 0.5), alignment: .top)
    }

    private var canSend: Bool {
        !session.isSending && !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A small synthetic 5-bar equalizer shown while dictating. Decorative, not
/// amplitude-driven — each bar breathes on its own cadence so the cluster never
/// reads as a flat loop. Ported from OpenScout's ScoutWaveform.
private struct PiChatWaveform: View {
    var tint: Color
    @State private var animate = false

    private let lows: [CGFloat]  = [4, 6, 5, 7, 4]
    private let highs: [CGFloat] = [11, 16, 13, 17, 10]
    private let durations: [Double] = [0.50, 0.62, 0.44, 0.70, 0.54]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(lows.indices, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.85))
                    .frame(width: 2.5, height: animate ? highs[i] : lows[i])
                    .animation(
                        .easeInOut(duration: durations[i]).repeatForever(autoreverses: true),
                        value: animate
                    )
            }
        }
        .frame(height: 18)
        .onAppear { animate = true }
    }
}

// MARK: - Model chip (header)

/// Compact provider/status indicator, now living in the header next to the
/// gear instead of under the composer. A live status dot + provider name;
/// shows the streaming/tool phase while a turn is in flight.
struct PiChatModelChip: View {
    @ObservedObject var session: PiChatSession

    var body: some View {
        HStack(spacing: 6) {
            if session.isSending {
                PiChatStatusPulse(color: statusColor)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
            }
            Text(session.currentProvider.name)
                .font(Typo.mono(10))
                .foregroundColor(Palette.textDim)
            if let detail = providerStatusDetail {
                Text("· " + detail)
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .help("Provider: \(session.currentProvider.name)")
    }

    private var statusColor: Color {
        if session.isSending { return Palette.detach }
        if session.needsProviderSetup || !session.hasPiBinary { return Palette.kill }
        return Palette.running
    }

    private var providerStatusDetail: String? {
        guard session.isSending else { return nil }
        if session.statusText == "streaming..." { return "streaming" }
        if session.statusText.hasPrefix("tool:") {
            return session.statusText.replacingOccurrences(of: "tool: ", with: "tool · ")
        }
        return "working"
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
                    // Opacity-only: dots never change size or position, so the
                    // label beside them can't be shoved around. A soft highlight
                    // travels across the three dots — calm, no motion artifacts.
                    let wave = sin(time * 2.6 - Double(index) * 0.9)
                    let opacity = 0.30 + 0.45 * (wave + 1) / 2

                    Circle()
                        .fill(Palette.running.opacity(opacity))
                        .frame(width: dotSize, height: dotSize)
                }
            }
            .frame(height: dotSize, alignment: .center)
        }
    }
}

/// A glowing bar caret that occupies a full text line-box with the bar seated
/// near the baseline — so it sits right when flow-laid after words (which pack
/// from the row top), instead of floating above the line.
struct PiChatStreamCursor: View {
    var size: CGFloat = 13

    var body: some View {
        let lineH = (size * 1.34).rounded()
        let barH  = (size * 1.04).rounded()
        let seat  = (size * 0.20).rounded()
        return ZStack(alignment: .bottom) {
            Color.clear.frame(width: 3, height: lineH)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Palette.running.opacity(0.95))
                .frame(width: 2, height: barH)
                .shadow(color: Palette.running.opacity(0.55), radius: 5)
                .padding(.bottom, seat)
                .modifier(PiChatPulseModifier(minOpacity: 0.45, maxOpacity: 1.0, duration: 0.85))
        }
    }
}

/// The actively-streaming paragraph, revealed word-by-word: each new word
/// materializes out of a soft blur with a small upward drift and a brief emerald
/// glow, and a glowing caret rides the end. Multi-line in-progress text and
/// reduce-motion fall back to a plain reveal; settled paragraphs + the finished
/// message render as normal selectable copy.
struct PiChatRevealParagraph: View {
    let text: String
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Token: Identifiable { let id: Int; let text: String }

    private var tokens: [Token] {
        let words = text.components(separatedBy: " ")
        return words.enumerated().map { i, w in
            Token(id: i, text: i < words.count - 1 ? w + " " : w)
        }
    }

    var body: some View {
        if reduceMotion || text.contains("\n") {
            HStack(alignment: .bottom, spacing: 0) {
                Text(text).font(Typo.reading(size)).foregroundColor(Palette.text)
                PiChatStreamCursor(size: size)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            FlowLayout(spacing: 0, lineSpacing: (size * 0.42).rounded(), alignment: .leading) {
                ForEach(tokens) { tok in
                    Text(tok.text)
                        .font(Typo.reading(size))
                        .foregroundColor(Palette.text)
                        .transition(.materialize)
                }
                PiChatStreamCursor(size: size)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.3), value: tokens.count)
        }
    }
}

private struct RevealModifier: ViewModifier {
    var blur: CGFloat
    var opacity: Double
    var dy: CGFloat
    var glow: CGFloat
    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .offset(y: dy)
            .shadow(color: Palette.running.opacity(glow > 0.1 ? 0.55 : 0), radius: glow)
    }
}

private extension AnyTransition {
    /// Words condense into being: blur→sharp, fade in, drift up, with a brief glow.
    static var materialize: AnyTransition {
        .modifier(
            active: RevealModifier(blur: 5, opacity: 0, dy: 3, glow: 7),
            identity: RevealModifier(blur: 0, opacity: 1, dy: 0, glow: 0)
        )
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
        case .workspace: return .infinity
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
        case .workspace: return 12
        case .dock: return 11
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
        // .full flattens block structure — SwiftUI's Text(AttributedString)
        // ignores paragraph/list presentation intents, so multi-line and
        // bulleted replies collapse into one run-on blob. Preserving the
        // source whitespace keeps newlines/lists intact while still rendering
        // inline bold/italic/code.
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
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
