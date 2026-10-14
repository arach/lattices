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

// MARK: - Transcript

/// Scroll sample used to tell a user's upward scroll apart from content growth.
private struct ScrollProbe: Equatable {
    var offsetY: CGFloat
    var atBottom: Bool
}

/// The conversation as a document: every turn on one left edge, the user's
/// marked by a bar in the margin, exchanges split by one-pixel rules
/// (Hudson's `HudTranscriptTurn`). No bubbles, masks or scale animation, so
/// the text holds a hard edge at 1x.
struct WorkspaceAssistantTranscript: View {
    @ObservedObject var session: WorkspaceAssistantSession
    var style: WorkspaceAssistantStyle = .workspace

    /// True while the viewport is at (or near) the bottom. Auto-follow only
    /// happens while pinned; scrolling up detaches and stops the chase until
    /// the user returns to the bottom.
    @State private var isPinnedToBottom = true

    var body: some View {
        if showsEmptyState {
            WorkspaceAssistantEmptyState(session: session, style: style) { prompt in
                session.draft = prompt
                session.sendDraft()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            scrollTranscript
        }
    }

    private var showsEmptyState: Bool {
        // Show starters until the first real turn; credential setup is handled
        // when the user tries to send without a key.
        !session.hasConversationHistory
    }

    private var scrollTranscript: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    let messages = visibleMessages
                    let firstUser = messages.first(where: { $0.role == .user })?.id
                    LazyVStack(alignment: .leading, spacing: style.messageSpacing) {
                        ForEach(messages) { message in
                            WorkspaceAssistantMessageRow(
                                message: message,
                                ruled: message.role == .user && message.id != firstUser,
                                isStreaming: isStreamingMessage(message),
                                activeToolName: activeToolName(for: message),
                                style: style
                            )
                            .equatable()
                            .id(message.id)
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: style.maxContentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.vertical, style.verticalPadding)
                    .frame(minHeight: viewport.size.height, alignment: .bottom)
                }
                .scrollIndicators(.automatic)
                .animation(.easeOut(duration: 0.14), value: session.messages.count)
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

    /// The session seeds a welcome note; the empty state already covers it, so
    /// system lines before the first user turn stay out of the transcript.
    private var visibleMessages: [WorkspaceAssistantMessage] {
        guard let firstUser = session.messages.firstIndex(where: { $0.role == .user }) else {
            return session.messages
        }
        return session.messages.enumerated()
            .filter { $0.offset >= firstUser || $0.element.role != .system }
            .map(\.element)
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
    var style: WorkspaceAssistantStyle
    var onSelect: (String) -> Void

    private let starters: [WorkspaceAssistantStarterPrompt] = [
        WorkspaceAssistantStarterPrompt(
            title: "Inspect my gestures",
            subtitle: "~/.lattices/mouse-shortcuts.json",
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
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 0)

            LatticesMark(size: 24, tint: AssistantInk.prose, dimOpacity: 0.16)

            // A ruled list on the page's left edge, not a grid of tiles.
            VStack(alignment: .leading, spacing: 0) {
                HudRule(color: HudTheme.latticesAssistant.hairline.subtle)
                ForEach(starters) { starter in
                    WorkspaceAssistantStarterButton(starter: starter) {
                        onSelect(starter.text)
                    }
                    HudRule(color: HudTheme.latticesAssistant.hairline.subtle)
                }
            }

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: style.maxContentWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, style.horizontalPadding)
    }
}

private struct WorkspaceAssistantStarterButton: View {
    let starter: WorkspaceAssistantStarterPrompt
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: starter.icon)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(hovering ? AssistantInk.prose : AssistantInk.dim)
                    .frame(width: 14)
                Text(starter.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AssistantInk.prose)
                Text(starter.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AssistantInk.dim)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AssistantInk.dim)
                    .opacity(hovering ? 1 : 0)
            }
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct WorkspaceAssistantStarterPrompt: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let text: String
}

// MARK: - Message row

struct WorkspaceAssistantMessageRow: View, Equatable {
    let message: WorkspaceAssistantMessage
    /// A rule above this turn: set on each user turn after the first, so the
    /// transcript reads as numbered exchanges without numbers.
    var ruled = false
    let isStreaming: Bool
    var activeToolName: String? = nil
    var style: WorkspaceAssistantStyle = .workspace

    static func == (lhs: WorkspaceAssistantMessageRow, rhs: WorkspaceAssistantMessageRow) -> Bool {
        lhs.message == rhs.message
            && lhs.ruled == rhs.ruled
            && lhs.isStreaming == rhs.isStreaming
            && lhs.activeToolName == rhs.activeToolName
            && lhs.style == rhs.style
    }

    var body: some View {
        switch message.role {
        case .system:    systemRow
        case .user:      userRow
        case .assistant: assistantRow
        }
    }

    private var markdown: WorkspaceAssistantMarkdown {
        WorkspaceAssistantMarkdown(size: style.bodySize)
    }

    private var systemRow: some View {
        HudTranscriptTurn(role: .system, style: style.transcript) {
            Text(message.text)
                .font(.system(size: style.bodySize - 1.5))
                .foregroundColor(AssistantInk.dim)
                .textSelection(.enabled)
        }
    }

    private var userRow: some View {
        HudTranscriptTurn(
            role: .user,
            ruled: ruled,
            timestamp: message.timestamp,
            copyText: message.text,
            style: style.transcript
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HudSelectableText(markdown.plain(message.text), ink: AssistantInk.set, opaque: style.opaqueText)
                if !message.attachments.isEmpty { attachments }
            }
        }
    }

    @ViewBuilder
    private var assistantRow: some View {
        if isStreaming {
            HudTranscriptTurn(role: .assistant, style: style.transcript) {
                assistantText
            } status: {
                HudActivityIndicator(activityLabel, color: Palette.running)
            }
        } else {
            HudTranscriptTurn(
                role: .assistant,
                timestamp: message.timestamp,
                copyText: message.text,
                style: style.transcript
            ) {
                assistantText
            }
        }
    }

    @ViewBuilder
    private var assistantText: some View {
        if !message.text.isEmpty {
            HudSelectableText(markdown.render(message.text), ink: AssistantInk.set, opaque: style.opaqueText)
        }
    }

    private var activityLabel: String {
        if let tool = activeToolName { return WorkspaceAssistantActivity.label(forTool: tool) }
        return message.text.isEmpty ? "Thinking" : "Writing"
    }

    private var attachments: some View {
        HStack(spacing: 6) {
            ForEach(message.attachments) { attachment in
                HStack(spacing: 5) {
                    Image(systemName: attachment.systemImage)
                        .font(.system(size: 9))
                    Text(attachment.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundColor(AssistantInk.dim)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .hudPixelBorder(radius: 3)
            }
        }
    }
}

// MARK: - Composer

struct WorkspaceAssistantComposer: View {
    @ObservedObject var session: WorkspaceAssistantSession
    var style: WorkspaceAssistantStyle = .workspace
    var focus: FocusState<Bool>.Binding
    /// The runtime picker's presentation, owned by the page that hosts
    /// `.hudRuntimePicker`. Nil where there is no picker: the chip opens
    /// Settings instead.
    var runtimePicking: Binding<Bool>? = nil

    @ObservedObject private var catalog = AssistantRuntimeCatalog.shared

    #if LATTICES_VOICE && canImport(HudsonVoice)
    @ObservedObject private var voice = WorkspaceVoiceInput.shared
    #endif

    var body: some View {
        VStack(spacing: 0) {
            #if LATTICES_VOICE && canImport(HudsonVoice)
            // Keep the idle composer footprint identical to pre-voice chrome.
            // Grow only while recording/transcribing, or for a brief outcome note.
            if voice.state.isCaptureActive || voice.state.isProcessing {
                dictationStrip
            } else if voice.lastOutcome != nil {
                if let outcome = voice.lastOutcome {
                    voiceOutcomeStrip(outcome)
                }
            }
            #endif

            // Turn lifecycle + layout live in HudsonKit's HudComposer (.stacked):
            // the field spans the top; a control row sits beneath with a `+`
            // attach affordance on the left and the bespoke mic grouped with the
            // morphing send/stop on the right. Scout owns model selection. Queued messages
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
                model: modelInfo,
                onTapModel: {
                    if let runtimePicking {
                        catalog.refresh()
                        runtimePicking.wrappedValue.toggle()
                    } else {
                        SettingsWindowController.shared.showAssistant()
                    }
                }
            )
            .hudRuntimeLane()
        }
        .frame(maxWidth: style.maxContentWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, style.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, style.verticalPadding)
        .environment(\.hudTheme, .latticesAssistant)
    }

    /// What answers the next message. With Scout's catalog: the picked
    /// harness / model / effort, where a harness left on its own default shows
    /// the model it last reported. Without it: the local harness and its
    /// reported model, or the API provider's model. Nil (no chip) until one is
    /// known.
    private var modelInfo: HudComposerModelInfo? {
        if !catalog.harnesses.isEmpty, !session.hasSelectedCredential || session.preferredAgentHarness != nil {
            let selection = session.runtimeSelection
            var info = HudComposerModelInfo(
                selection: selection,
                harnesses: catalog.harnesses,
                efforts: catalog.efforts
            )
            if catalog.launchModel(for: selection) == nil {
                info.model = session.agentRuntimeHarnessLabel == selection.harnessId
                    ? session.agentRuntimeModel.map(Self.displayModel) ?? ""
                    : ""
            }
            if info.effort == HudRuntimeEffort.auto.label { info.effort = nil }
            return info
        }
        if let harness = session.agentRuntimeHarnessLabel ?? session.preferredAgentHarness,
           !harness.isEmpty {
            return HudComposerModelInfo(
                model: session.agentRuntimeModel.map(Self.displayModel) ?? "",
                harness: harness
            )
        }
        if session.hasSelectedCredential {
            return HudComposerModelInfo(model: Self.displayModel(session.currentProvider.modelID))
        }
        return nil
    }

    /// `claude-opus-5-5` → `Opus 5.5`; other ids pass through unchanged.
    static func displayModel(_ id: String) -> String {
        var name = id
        if let bracket = name.firstIndex(of: "[") { name = String(name[..<bracket]) }
        guard name.hasPrefix("claude-") else { return name }
        var parts = name.dropFirst("claude-".count).split(separator: "-").map(String.init)
        if let last = parts.last, last.count == 8, Int(last) != nil { parts.removeLast() }
        guard let family = parts.first else { return name }
        let version = parts.dropFirst().joined(separator: ".")
        return family.prefix(1).uppercased() + family.dropFirst() + (version.isEmpty ? "" : " " + version)
    }

    private var queuedItems: [HudComposerQueuedItem] {
        session.queuedPrompts.map { HudComposerQueuedItem(id: $0.id, text: $0.text) }
    }

    private var hudStyle: HudComposerStyle {
        .hairline(
            placeholder: style.placeholder,
            fontSize: style.composerSize,
            face: .system,
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

    /// Scout owns model/effort selection, so Lattices only supplies the bespoke
    /// mic here. Attachments stay hidden until the chat path wires them.
    @ViewBuilder
    private var micAccessory: some View {
        #if LATTICES_VOICE && canImport(HudsonVoice)
        micButton
        #else
        EmptyView()
        #endif
    }

    #if LATTICES_VOICE && canImport(HudsonVoice)
    /// HudsonVoice-powered mic. Tap to dictate into the draft; tap again to
    /// commit. A bare glyph like Send beside it: live states tint the glyph,
    /// and nothing breathes or scales.
    private var micButton: some View {
        HudSquareIconButton(
            symbol: micSymbol,
            help: micTooltip,
            size: 26,
            iconSize: 12,
            tint: micLiveTint
        ) {
            voice.toggle()
        }
        // Mic stays live during a turn — dictate to queue or steer mid-stream.
    }

    /// Compact live strip while the mic is hot. Sits inside the same chrome as
    /// HudComposer — no extra horizontal pad (parent already applies it).
    private var dictationStrip: some View {
        HStack(spacing: 8) {
            WorkspaceAssistantWaveform(tint: micAccent)
            Group {
                if voice.state.isProcessing {
                    Text("Transcribing…")
                        .foregroundColor(Palette.detach)
                } else if !voice.partial.isEmpty {
                    Text(voice.partial)
                        .foregroundColor(Palette.textDim)
                        .lineLimit(1)
                } else {
                    Text(voice.state == .starting ? "Starting…" : "Listening…")
                        .foregroundColor(Palette.textMuted)
                }
            }
            .font(Typo.caption(11))
            Spacer(minLength: 0)
        }
        .padding(.bottom, 6)
        .transition(.opacity)
    }

    /// Soft note for empty/fail only — keeps the idle input box uncluttered.
    private func voiceOutcomeStrip(_ outcome: WorkspaceVoiceOutcome) -> some View {
        let tint: Color = outcome.kind == .failed ? Palette.kill : Palette.detach
        return HStack(spacing: 6) {
            Image(systemName: outcome.kind == .failed ? "exclamationmark.circle" : "waveform")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tint.opacity(0.9))
            Text(outcome.message)
                .font(Typo.caption(10.5))
                .foregroundColor(Palette.textMuted)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                voice.dismissOutcome()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Palette.textMuted.opacity(0.7))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.bottom, 6)
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

    /// Red while recording, amber while transcribing; idle takes the
    /// button's own muted-to-ink hover.
    private var micLiveTint: Color? {
        switch voice.state {
        case .recording, .starting: return Palette.kill
        case .processing: return Palette.detach
        case .unavailable: return HudTheme.latticesAssistant.palette.dim
        case .idle: return nil
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
        HStack(alignment: .center, spacing: 2) {
            ForEach(lows.indices, id: \.self) { i in
                Rectangle()
                    .fill(tint)
                    .frame(width: 2, height: animate ? highs[i] : lows[i])
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

// MARK: - Status line (header)

/// Who the assistant is and where it runs. The mark is a square: green and
/// blinking while a turn runs, red when the runtime is down, otherwise dim.
struct WorkspaceAssistantStatusLine: View {
    @ObservedObject var session: WorkspaceAssistantSession

    var body: some View {
        HStack(spacing: 8) {
            HudBlinkMark(color: markColor, size: 5, still: !session.isSending)
            Text(harness)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AssistantInk.prose)
            Text(session.workingDirectoryName)
                .font(.system(size: 12))
                .foregroundColor(AssistantInk.dim)
        }
        .lineLimit(1)
        .frame(height: 18)
        .help(session.chatTransportSummary)
    }

    private var harness: String {
        guard let label = session.agentRuntimeHarnessLabel, !label.isEmpty else { return "Assistant" }
        return label
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private var markColor: Color {
        if session.isSending { return Palette.running }
        if session.isScoutAvailable == false || session.statusText == "error" { return Palette.kill }
        return AssistantInk.muted
    }
}

enum WorkspaceAssistantActivity {
    static func label(forTool tool: String) -> String {
        let name = tool.replacingOccurrences(of: "_", with: " ")
        return name.isEmpty ? "Working" : name
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
        case .workspace: return 720
        case .dock: return .infinity
        }
    }

    /// The page is opaque, so its text views paint the page colour under the
    /// glyphs for crisp 1x rendering. The dock floats translucent, so it can't.
    var opaqueText: Bool { self == .workspace }

    var transcript: HudTranscriptStyle {
        switch self {
        case .workspace: return HudTranscriptStyle(barGap: 12, ruleSpacing: 20, metaSpacing: 6)
        case .dock: return .compact
        }
    }

    var messageSpacing: CGFloat {
        switch self {
        case .workspace: return 14
        case .dock: return 8
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
        case .workspace: return 13
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
