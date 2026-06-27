import SwiftUI
import HudsonUI
#if LATTICES_VOICE && canImport(HudsonVoice)
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
                    .modifier(WorkspaceAssistantPulseModifier(minOpacity: 0.0, maxOpacity: 0.55, duration: 1.4))
            }
        }
    }
}

// MARK: - Dot-grid background

/// Faint dot-grid drawn with Canvas. Used as the transcript surface so the
/// background reads as "designed" rather than a flat fill.
struct WorkspaceAssistantDotGrid: View {
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

struct WorkspaceAssistantTranscript: View {
    @ObservedObject var session: WorkspaceAssistantSession
    var style: WorkspaceAssistantStyle = .workspace

    /// True while the viewport is at (or near) the bottom. Auto-follow only
    /// happens while pinned; scrolling up detaches and stops the chase until
    /// the user returns to the bottom.
    @State private var isPinnedToBottom = true

    var body: some View {
        if showsEmptyState {
            WorkspaceAssistantEmptyState(session: session) { prompt in
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
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: style.messageSpacing) {
                        ForEach(session.messages) { message in
                            WorkspaceAssistantMessageRow(
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
                    .frame(minHeight: viewport.size.height, alignment: .bottom)
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
                .onChange(of: session.messages.count) { _, _ in
                    // New message: follow only if the user is still pinned to the end.
                    if isPinnedToBottom { scrollToEnd(proxy: proxy, animated: true) }
                }
                .onChange(of: session.messages.last?.text) { _, _ in
                    // Chase the live edge while pinned. Not gated on isSending: the
                    // closing drain reveals the tail *after* isSending flips false.
                    if isPinnedToBottom { scrollToEnd(proxy: proxy, animated: false) }
                }
                .onChange(of: session.isSending) { _, sending in
                    // Sending re-pins: a fresh turn always snaps you back to the end.
                    if sending {
                        isPinnedToBottom = true
                        scrollToEnd(proxy: proxy, animated: true)
                    }
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

            WorkspaceAssistantDotGrid(spacing: 26, dotSize: 1, opacity: 0.035, tint: Palette.textMuted)
                .blendMode(.plusLighter)
        }
    }

    private func isStreamingMessage(_ message: WorkspaceAssistantMessage) -> Bool {
        guard session.isSending, message.role == .assistant else { return false }
        return message.id == session.messages.last?.id
    }

    private func activeToolName(for message: WorkspaceAssistantMessage) -> String? {
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

private struct WorkspaceAssistantEmptyState: View {
    @ObservedObject var session: WorkspaceAssistantSession
    var onSelect: (String) -> Void

    private let starters: [WorkspaceAssistantStarterPrompt] = [
        WorkspaceAssistantStarterPrompt(
            title: "Inspect my gestures",
            subtitle: "Read ~/.lattices/mouse-shortcuts.json",
            icon: "hand.draw",
            text: "Read my current mouse gesture configuration and tell me what's set up."
        ),
        WorkspaceAssistantStarterPrompt(
            title: "What's on my screen?",
            subtitle: "Snapshot the current desktop",
            icon: "rectangle.on.rectangle",
            text: "List the windows I have open right now."
        ),
        WorkspaceAssistantStarterPrompt(
            title: "Tidy my terminals",
            subtitle: "Distribute iTerm windows to a grid",
            icon: "square.grid.2x2",
            text: "Organize my terminal windows across the displays I have."
        ),
        WorkspaceAssistantStarterPrompt(
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
                        .buttonStyle(WorkspaceAssistantStarterButtonStyle())
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

    private func starterRow(_ starter: WorkspaceAssistantStarterPrompt) -> some View {
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

struct WorkspaceAssistantStarterPrompt: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let text: String
}

private struct WorkspaceAssistantStarterButtonStyle: ButtonStyle {
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

struct WorkspaceAssistantMessageRow: View, Equatable {
    let message: WorkspaceAssistantMessage
    let isStreaming: Bool
    var activeToolName: String? = nil
    var style: WorkspaceAssistantStyle = .workspace

    static func == (lhs: WorkspaceAssistantMessageRow, rhs: WorkspaceAssistantMessageRow) -> Bool {
        lhs.message == rhs.message
            && lhs.isStreaming == rhs.isStreaming
            && lhs.activeToolName == rhs.activeToolName
            && lhs.style == rhs.style
    }

    var body: some View {
        HudAgentTurnView(
            turn: turn,
            style: agentStyle,
            assistantAvatar: { active, size, tint in
                AnyView(LatticesMarkAvatar(size: size, tint: tint, isActive: active))
            }
        )
    }

    /// Map this transport-specific message onto the transport-agnostic turn
    /// model the renderer consumes.
    private var turn: HudAgentTurn {
        HudAgentTurn(
            id: message.id,
            role: agentRole,
            author: agentAuthor,
            timestamp: message.timestamp,
            text: message.text,
            attachments: message.attachments.map {
                HudAgentTurnAttachment(
                    id: $0.id,
                    name: $0.name,
                    mediaType: $0.mediaType,
                    systemImage: $0.systemImage
                )
            },
            isStreaming: isStreaming,
            toolActivity: activeToolName
        )
    }

    private var agentStyle: HudAgentTurnStyle {
        HudAgentTurnStyle(bodySize: style.bodySize)
    }

    private var agentRole: HudAgentTurnRole {
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

// MARK: - Composer

struct WorkspaceAssistantComposer: View {
    @ObservedObject var session: WorkspaceAssistantSession
    var style: WorkspaceAssistantStyle = .workspace
    var focus: FocusState<Bool>.Binding

    #if LATTICES_VOICE && canImport(HudsonVoice)
    @ObservedObject private var voice = WorkspaceVoiceInput.shared
    @State private var micPulse = false
    #endif

    var body: some View {
        VStack(spacing: 7) {
            #if LATTICES_VOICE && canImport(HudsonVoice)
            if voice.state.isCaptureActive || voice.state.isProcessing {
                dictationStrip
            }
            #endif

            // Turn lifecycle + layout live in HudsonKit's HudComposer (.stacked):
            // the field spans the top; a control row sits beneath with a `+`
            // attach affordance on the left and model · effort + the bespoke mic
            // grouped with the morphing send/stop on the right. Queued messages
            // stack as full-width rows above the field.
            HudComposer(
                text: $session.draft,
                phase: session.isSending ? .streaming : .idle,
                queued: queuedItems,
                style: hudStyle,
                layout: .stacked,
                focus: focus,
                trailingAccessory: { micAccessory },
                onAction: handle(_:),
                onRemoveQueued: { session.removeQueuedPrompt(id: $0.id) },
                onEditQueued: { session.editQueuedPrompt(id: $0.id) },
                model: HudComposerModelInfo(model: session.currentProvider.name.lowercased(), effort: "auto")
            )
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(composerChrome)
        .environment(\.hudTheme, .lattices)
    }

    private var queuedItems: [HudComposerQueuedItem] {
        session.queuedPrompts.map { HudComposerQueuedItem(id: $0.id, text: $0.text) }
    }

    private var hudStyle: HudComposerStyle {
        HudComposerStyle(
            placeholder: style.placeholder,
            fontSize: style.composerSize,
            lineLimit: 1...style.composerLineLimit
        )
    }

    /// `sendDraft()` already submits-or-queues based on `isSending`, so both map to
    /// it; steer/stop hit the dedicated session primitives.
    private func handle(_ action: HudComposerAction) {
        switch action {
        case .submit, .queue: session.sendDraft()
        case .steer:          session.interruptAndSteer()
        case .stop:           session.stop()
        }
    }

    // MARK: Control-row accessories

    /// The model · effort label is first-class in HudComposer, so Lattices only
    /// supplies the bespoke mic here. Effort is a placeholder until a real setting
    /// exists; attachments stay hidden until the chat path wires them.
    @ViewBuilder
    private var micAccessory: some View {
        #if LATTICES_VOICE && canImport(HudsonVoice)
        micButton
        #else
        EmptyView()
        #endif
    }

    #if LATTICES_VOICE && canImport(HudsonVoice)
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
        // Mic stays live during a turn — dictate to queue or steer mid-stream.
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
            WorkspaceAssistantWaveform(tint: micAccent)
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

    #endif

    private var composerChrome: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.12)
            Palette.surface.opacity(0.18)
        }
            .overlay(Rectangle().fill(Palette.border).frame(height: 0.5), alignment: .top)
    }
}

/// A small synthetic 5-bar equalizer shown while dictating. Decorative, not
/// amplitude-driven — each bar breathes on its own cadence so the cluster never
/// reads as a flat loop. Ported from OpenScout's ScoutWaveform.
private struct WorkspaceAssistantWaveform: View {
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
struct WorkspaceAssistantModelChip: View {
    @ObservedObject var session: WorkspaceAssistantSession

    var body: some View {
        HStack(spacing: 6) {
            if session.isSending {
                WorkspaceAssistantStatusPulse(color: statusColor)
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

struct WorkspaceAssistantStatusPulse: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: 10, height: 10)
                .modifier(WorkspaceAssistantPulseModifier(minOpacity: 0.15, maxOpacity: 0.55, duration: 1.2))

            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
    }
}

private struct WorkspaceAssistantPulseModifier: ViewModifier {
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

enum WorkspaceAssistantStyle: Equatable {
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
