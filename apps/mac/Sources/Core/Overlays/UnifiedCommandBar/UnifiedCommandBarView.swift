import AppKit
import Combine
import SwiftUI

/// The unified command bar UI: a slim bar (state-indicator left · input · the
/// mic+send action cluster right) with a detail panel that expands below it
/// only when there's something to show. Mirrors the design-studio mock.
///
/// Texture is borrowed from the hands-off HUD chrome (`HUDChrome`): a layered
/// carbon substrate, a luminous top-edge rim, gradient hairlines and the
/// electric-cyan signal accent — crisp instrument-panel geometry, not a round
/// popover.
///
/// Phase A renders the search and command detail; the mic button is a stub
/// until the voice leg lands in Phase B.
struct UnifiedCommandBarView: View {
    @ObservedObject var state: UnifiedCommandBarState
    var onCommit: () -> Void
    var onMic: () -> Void
    var onSettings: () -> Void
    var onDismiss: () -> Void

    @FocusState private var focused: Bool

    /// Tight radius — instrument panel, not a pill. (Studio mock is 0; a hair of
    /// rounding keeps a floating overlay from looking knife-edged.)
    private let radius: CGFloat = 5

    var body: some View {
        VStack(spacing: 0) {
            card
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Focus must be asserted once the panel is *key* — setting it in onAppear
        // (before key) makes SwiftUI's makeFirstResponder fail silently and never
        // retry, so the field stays unfocused even though the window has focus.
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            focused = true
        }
    }

    // The visible surface — bar plus optional expansion. Everything below it in
    // the panel is transparent, so at rest you just see the bar.
    private var card: some View {
        VStack(spacing: 0) {
            bar
            if state.detail != .none {
                HUDHairline()
                expansion
                if state.detail != .welcome { footer }   // welcome carries its own row
            }
        }
        .background(cardTexture)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(borderGradient, lineWidth: 0.75)
        )
        .overlay(alignment: .top) { topRim }
        .shadow(color: Color.black.opacity(0.38), radius: 14, y: 6)
        .animation(.easeOut(duration: 0.16), value: state.detail)
    }

    // MARK: - Texture

    /// Layered carbon substrate — base gradient + a faint cyan/rose accent wash
    /// + a top ambient highlight. Lifted in spirit from `HUDPanelBackground`.
    private var cardTexture: some View {
        ZStack {
            LinearGradient(
                colors: [HUDChrome.baseTop, HUDChrome.baseBottom],
                startPoint: .top, endPoint: .bottom
            )
            LinearGradient(
                colors: [HUDChrome.cyan.opacity(0.06), .clear, HUDChrome.rose.opacity(0.035)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [Color.white.opacity(0.06), .clear],
                startPoint: .top, endPoint: .center
            )
        }
    }

    /// Top-bright → bottom-dark border for depth (LiquidGlass feel).
    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Luminous specular rim across the very top edge — white centre, cyan core.
    private var topRim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: Color.white.opacity(0.5), location: 0.28),
                .init(color: HUDChrome.cyan.opacity(0.38), location: 0.5),
                .init(color: Color.white.opacity(0.5), location: 0.72),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
        .blur(radius: 0.4)
    }

    private var placeholder: String {
        if state.commandMode { return "Type a command or placement…" }
        return "Search, or type / for commands…"
    }

    // MARK: - Bar

    private var bar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                leftIndicator
                centerInput
                if !state.query.isEmpty && !state.voiceActive {
                    clearButton
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right action cluster — mic flush against send.
            micButton
            sendButton
            dismissButton
        }
        .frame(height: 46)
        // Bar reads as a raised surface over the darker expansion.
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.05), Color.white.opacity(0.012)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// Left state-aware slot: a live waveform while listening, otherwise a
    /// compact mode badge so the bar never opens in an unlabeled state.
    @ViewBuilder private var leftIndicator: some View {
        if state.voice.phase == .listening {
            HStack(spacing: 7) {
                WaveBar()
                modeText("LISTENING", tone: HUDChrome.cyan)
                ListeningTimer(startTime: state.voice.listenStartTime)
            }
        } else {
            HStack(spacing: 7) {
                Image(systemName: leftGlyph)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(modeTone)
                    .frame(width: 15)
                modeText(modeLabel, tone: modeTone)
            }
        }
    }

    private var leftGlyph: String {
        if state.voiceActive { return "mic" }
        if state.wantsAssistant { return "sparkles" }
        return state.commandMode ? "command" : "magnifyingglass"
    }

    private var modeLabel: String {
        if state.voiceActive {
            switch state.voice.phase {
            case .connecting: return "VOICE"
            case .listening: return "LISTENING"
            case .transcribing: return "HEARING"
            case .result: return voiceRetryable ? "VOICE · RETRY" : "VOICE RESULT"
            case .idle: return "VOICE"
            }
        }
        if state.wantsAssistant { return "ASK" }
        return state.commandMode ? "COMMAND" : "SEARCH"
    }

    private var modeTone: Color {
        if state.voice.phase == .result && voiceRetryable { return HUDChrome.cyan }
        if state.voiceActive || state.wantsAssistant || state.commandMode { return HUDChrome.cyan }
        return Palette.textMuted
    }

    private func modeText(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(Typo.caption(9))
            .tracking(0.9)
            .foregroundColor(tone)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Editable field normally; a read-only transcript line while voice is active.
    @ViewBuilder private var centerInput: some View {
        if state.voiceActive {
            Text(voiceTranscript)
                .font(Typo.mono(14))
                .foregroundColor(state.voice.finalText.isEmpty && state.voice.partialText.isEmpty
                                 ? Palette.textMuted : Palette.text)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField(placeholder, text: $state.query)
                .textFieldStyle(.plain)
                .font(Typo.mono(14))
                .foregroundColor(Palette.text)
                .focused($focused)
                .onSubmit { onCommit() }
        }
    }

    private var voiceTranscript: String {
        if !state.voice.finalText.isEmpty { return state.voice.finalText }
        if !state.voice.partialText.isEmpty { return state.voice.partialText }
        switch state.voice.phase {
        case .connecting:   return "Connecting…"
        case .listening:    return "Listening…"
        case .transcribing: return "Transcribing…"
        case .result:
            if !state.voice.resultSummary.isEmpty { return state.voice.resultSummary }
            if let result = state.voice.executionResult, !result.isEmpty { return result }
            return "Voice result"
        default:            return ""
        }
    }

    private var clearButton: some View {
        Button { state.query = "" } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(Palette.textMuted)
        }
        .buttonStyle(.plain)
    }

    /// Send reflects routing: solid cyan when there's something to act on, a
    /// softer cyan "ask" tint (sparkle) when the text reads as a question.
    @ViewBuilder private var sendButton: some View {
        if state.voice.phase == .listening || state.voice.phase == .connecting {
            actionButton(system: "stop.fill", primary: true, action: onCommit)
                .help("Stop recording · ↵")
        } else if state.voice.phase == .transcribing {
            actionButton(system: "hourglass", primary: false, action: {})
                .help("Transcribing")
        } else if state.voice.phase == .result && voiceRetryable {
            actionButton(system: "mic.fill", primary: true, action: onCommit)
                .help("Try voice again · ↵")
        } else if state.wantsAssistant {
            Button(action: onCommit) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(HUDChrome.cyan)
                    .frame(width: 44, height: 46)
                    .background(HUDChrome.cyan.opacity(0.14))
                    .overlay(HUDHairline(axis: .vertical), alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Ask the assistant · ⌘↵")
        } else {
            actionButton(system: "return", primary: state.detail != .none, action: onCommit)
        }
    }

    /// Mic lights cyan and fills while listening.
    private var micButton: some View {
        let listening = state.voice.phase == .listening
        return Button(action: onMic) {
            Image(systemName: listening ? "stop.circle.fill" : "mic")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(listening ? HUDChrome.onSignal : Palette.textMuted)
                .frame(width: 44, height: 46)
                .background(listening ? HUDChrome.cyan.opacity(0.95) : Color.clear)
                .overlay(HUDHairline(axis: .vertical), alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(listening ? "Stop recording" : "Start recording")
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Palette.textMuted)
                .frame(width: 34, height: 46)
                .overlay(HUDHairline(axis: .vertical), alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("Dismiss · Esc")
    }

    private func actionButton(system: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(primary ? HUDChrome.onSignal : Palette.textMuted)
                .frame(width: 44, height: 46)
                .background(primary ? HUDChrome.cyan : Color.clear)
                .overlay(HUDHairline(axis: .vertical), alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expansion

    @ViewBuilder private var expansion: some View {
        switch state.detail {
        case .command:   commandList
        case .search:    searchList
        case .voice:     voiceList
        case .welcome:   welcome
        case .nlCommand: nlCommandPanel
        case .none:      EmptyView()
        }
    }

    // MARK: - NL command (typed natural language → an interpreted, runnable intent)

    /// A single row previewing the intent the NL resolver inferred from the typed
    /// text. Acts as autocomplete for "full intents": you type "tile chrome left"
    /// and see exactly what ↵ will run.
    @ViewBuilder private var nlCommandPanel: some View {
        if let m = state.nlMatch {
            let s = nlSummary(m)
            Button(action: onCommit) {
                HStack(spacing: 11) {
                    Image(systemName: s.glyph)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(HUDChrome.cyan)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.label)
                            .font(Typo.mono(12))
                            .foregroundColor(Palette.text)
                            .lineLimit(1)
                        Text("interpreted as a command")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted)
                    }
                    Spacer()
                    helpHint("↵", "run")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(rowSelection(true))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        }
    }

    /// Humanize an inferred intent + slots into a glyph and a one-line label.
    private func nlSummary(_ m: IntentMatch) -> (glyph: String, label: String) {
        func slot(_ k: String) -> String? {
            if let s = m.slots[k]?.stringValue, !s.isEmpty { return s }
            if let i = m.slots[k]?.intValue { return String(i) }
            return nil
        }
        switch m.intentName {
        case "tile_window":
            if let pos = slot("position"), let spec = PlacementSpec(string: pos) {
                if case .tile(let p) = spec { return (p.arrowGlyph, "Tile · \(p.label)") }
                return ("rectangle.split.2x2", "Tile · \(spec.wireValue)")
            }
            return ("rectangle.center.inset.filled", "Tile window")
        case "move_to_display":
            let d = slot("display").map { "display \((Int($0) ?? 0) + 1)" } ?? "another display"
            return ("display", "Move to \(d)")
        case "focus":
            return ("scope", "Focus \(slot("app") ?? slot("session") ?? "window")")
        case "launch":
            return ("arrow.up.forward.app", "Open \(slot("project") ?? slot("app") ?? "app")")
        case "distribute":
            let what = slot("app").map { "\($0) windows" } ?? "windows"
            return ("rectangle.split.3x3", "Arrange \(what)" + (slot("region").map { " · \($0)" } ?? ""))
        case "scan":
            return ("sparkle.magnifyingglass", "Scan workspace")
        default:
            return ("command", m.intentName.replacingOccurrences(of: "_", with: " ").capitalized)
        }
    }

    // MARK: - Welcome (the empty open state)

    /// Two compact rows: things to try, then how to invoke voice / the assistant.
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("TRY")
                    .font(Typo.caption(9)).tracking(1.1)
                    .foregroundColor(Palette.textMuted)
                welcomeChip("/tile right")
                welcomeChip("4x4:1,2", fill: "/tile 4x4:1,2", placement: PlacementSpec(string: "4x4:1,2"))
                welcomeChip("4x4 span", fill: "/tile 4x4:1,1-2,2", placement: PlacementSpec(string: "4x4:1,1-2,2"))
            }
            HStack(spacing: 16) {
                helpHint("/", "commands")
                helpHint("⌥", "hold to speak")
                helpHint("⌘↵", "ask the assistant")
                Spacer(minLength: 0)
                settingsButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func welcomeChip(_ label: String, fill: String? = nil, placement: PlacementSpec? = nil) -> some View {
        Button { state.query = fill ?? label } label: {
            HStack(spacing: 6) {
                if let placement {
                    MiniPlacementGlyph(spec: placement, selected: false)
                        .frame(width: 18, height: 12)
                }
                Text(label)
                    .font(Typo.mono(11))
                    .lineLimit(1)
            }
            .foregroundColor(Palette.textDim)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.border, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer (gesture hints · settings)

    /// Persistent footer under any expansion: command-key hints on the left, a
    /// Settings link pinned bottom-right.
    private var footer: some View {
        HStack(spacing: 16) {
            if state.detail == .command {
                helpHint("⇥", "complete")
                helpHint("↵", "run")
                helpHint("⌥", "speak")
            } else if state.detail == .nlCommand {
                helpHint("↵", "run command")
                helpHint("⌘↵", "ask instead")
            } else if state.detail == .voice {
                voiceFooterHints
            }
            Spacer(minLength: 0)
            settingsButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(Rectangle().fill(Palette.border).frame(height: 0.5), alignment: .top)
    }

    @ViewBuilder private var voiceFooterHints: some View {
        switch state.voice.phase {
        case .connecting:
            helpHint("↵", "cancel")
            helpHint("Esc", "cancel")
        case .listening:
            helpHint("↵", "finish")
            helpHint("Esc", "finish")
            helpHint("⌥", "release")
        case .transcribing:
            helpHint("Esc", "cancel")
        case .result:
            if voiceRetryable {
                helpHint("↵", "try again")
            } else {
                helpHint("↵", "close")
            }
            helpHint("Esc", "close")
        case .idle:
            helpHint("⌥", "hold to speak")
        }
    }

    private var voiceRetryable: Bool {
        let result = state.voice.executionResult ?? ""
        return VoiceCommandState.isRetryableFailure(result)
    }

    private var settingsButton: some View {
        Button(action: onSettings) {
            HStack(spacing: 5) {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .medium))
                Text("Settings")
                    .font(Typo.caption(9))
                    .tracking(0.6)
            }
            .foregroundColor(Palette.textMuted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Lattices settings")
    }

    private func helpHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textDim)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.border, lineWidth: 0.5))
                )
            Text(label)
                .font(Typo.caption(9))
                .tracking(0.6)
                .foregroundColor(Palette.textMuted)
        }
    }

    private var commandList: some View {
        let cmds = state.search.command.suggestions
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if let ctx = state.search.command.contextLabel {
                    sectionLabel(ctx)
                }
                ForEach(Array(cmds.enumerated()), id: \.element.id) { idx, s in
                    if let sec = s.section, idx == 0 || cmds[idx - 1].section != sec {
                        sectionLabel(sec)
                    }
                    commandRow(s, idx: idx)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 400)
    }

    private func commandRow(_ s: CommandSuggestion, idx: Int) -> some View {
        let sel = idx == state.search.command.selectedIndex
        return Button {
            state.search.command.selectedIndex = idx
            onCommit()
        } label: {
            HStack(spacing: 11) {
                suggestionGlyph(s, selected: sel)
                Text(s.label)
                    .font(Typo.mono(12))
                    .foregroundColor(sel ? HUDChrome.cyan : Palette.textDim)
                    .lineLimit(1)
                Spacer()
                if s.isFill {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Palette.textMuted)
                } else {
                    Text(s.detail)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(rowSelection(sel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func suggestionGlyph(_ suggestion: CommandSuggestion, selected: Bool) -> some View {
        if let spec = suggestion.previewSpec {
            MiniPlacementGlyph(spec: spec, selected: selected)
                .frame(width: 16, height: 12)
                .frame(width: 16)
        } else {
            Image(systemName: suggestion.glyph)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(selected ? HUDChrome.cyan : Palette.textDim)
                .frame(width: 16)
        }
    }

    private var searchList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                var flat = 0
                ForEach(state.search.groupedResults, id: \.0) { group, items in
                    sectionLabel(group)
                    ForEach(items) { item in
                        let idx = flat
                        let _ = { flat += 1 }()
                        searchRow(item, idx: idx)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 400)
    }

    private func searchRow(_ item: OmniResult, idx: Int) -> some View {
        let sel = idx == state.search.selectedIndex
        return Button {
            state.search.selectedIndex = idx
            onCommit()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: item.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(sel ? HUDChrome.cyan : Palette.textDim)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(Typo.mono(12))
                        .foregroundColor(sel ? HUDChrome.cyan : Palette.textDim)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Text(item.kind.rawValue)
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(rowSelection(sel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Selected-row treatment from the mock: cyan-soft wash + an inset cyan rail.
    @ViewBuilder private func rowSelection(_ sel: Bool) -> some View {
        if sel {
            HUDChrome.cyan.opacity(0.12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(HUDChrome.cyan).frame(width: 2)
                }
        } else {
            Color.clear
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t.uppercased())
            .font(Typo.caption(9))
            .tracking(1.1)
            .foregroundColor(Palette.textMuted)
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Voice expansion

    /// Heard · Intent · Result — the slim voice readout (the heavy 3-column
    /// HISTORY/LOG/AI layout from the standalone window is intentionally dropped).
    private var voiceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !state.voice.finalText.isEmpty {
                    voiceSection("Heard") {
                        Text(state.voice.finalText)
                            .font(Typo.mono(13))
                            .foregroundColor(Palette.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !state.voice.partialText.isEmpty {
                    voiceSection("Hearing…") {
                        Text(state.voice.partialText)
                            .font(Typo.mono(13))
                            .foregroundColor(Palette.textDim)
                    }
                }

                if let intent = state.voice.intentName {
                    voiceSection("Intent") { intentChips(intent) }
                }

                if let failure = state.voice.executionError {
                    voiceSection("Couldn't run") {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Palette.kill)
                            Text(failure)
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !state.voice.resultItems.isEmpty {
                    let n = state.voice.resultItems.count
                    voiceSection("\(n) match\(n == 1 ? "" : "es")") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(state.voice.resultItems.prefix(20).enumerated()), id: \.1.id) { idx, item in
                                ResultRow(index: idx, item: item, onFocus: focusWindow, onTile: tileWindow)
                            }
                        }
                    }
                } else if !state.voice.resultSummary.isEmpty {
                    voiceSection("Result") { resultLine(state.voice.resultSummary) }
                } else if state.voice.executionResult == "ok" {
                    voiceSection("Result") { resultLine("done") }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 400)
    }

    private func voiceSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(label)
            content()
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 8)
    }

    /// The resolved intent + its slots as the mock's chip row.
    private func intentChips(_ intent: String) -> some View {
        let slots = state.voice.intentSlots
        return HStack(spacing: 6) {
            chip(intent, signal: true)
            ForEach(slots.keys.sorted(), id: \.self) { key in
                if let val = slots[key] { chip("\(key): \(val)", signal: false) }
            }
        }
    }

    private func chip(_ text: String, signal: Bool) -> some View {
        Text(text)
            .font(Typo.mono(10))
            .foregroundColor(signal ? HUDChrome.cyan : Palette.textDim)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(signal ? HUDChrome.cyan.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(signal ? HUDChrome.cyan.opacity(0.5) : Palette.border, lineWidth: 0.5)
            )
    }

    private func resultLine(_ text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(HUDChrome.cyan).frame(width: 6, height: 6)
            Text(text)
                .font(Typo.mono(12))
                .foregroundColor(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func focusWindow(_ wid: UInt32) {
        guard let entry = DesktopModel.shared.windows[wid] else { return }
        WindowTiler.focusWindow(wid: wid, pid: entry.pid)
        WindowTiler.highlightWindowById(wid: wid)
    }

    private func tileWindow(_ wid: UInt32, _ position: String) {
        guard let entry = DesktopModel.shared.windows[wid],
              let placement = PlacementSpec(string: position) else { return }
        WindowTiler.focusWindow(wid: wid, pid: entry.pid)
        WindowTiler.tileWindowById(wid: wid, pid: entry.pid, to: placement)
        WindowTiler.highlightWindowById(wid: wid)
    }
}

private struct MiniPlacementGlyph: View {
    let spec: PlacementSpec
    let selected: Bool

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let (fx, fy, fw, fh) = spec.fractions
            let accent = selected ? HUDChrome.cyan : Palette.textDim

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.07 : 0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(accent.opacity(selected ? 0.65 : 0.32), lineWidth: 0.6)
                    )

                ForEach(1..<4, id: \.self) { index in
                    Rectangle()
                        .fill(Palette.border.opacity(selected ? 0.8 : 0.55))
                        .frame(width: 0.5)
                        .offset(x: size.width * CGFloat(index) / 4)
                    Rectangle()
                        .fill(Palette.border.opacity(selected ? 0.8 : 0.55))
                        .frame(height: 0.5)
                        .offset(y: size.height * CGFloat(index) / 4)
                }

                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                    .fill(accent.opacity(selected ? 0.9 : 0.58))
                    .frame(
                        width: max(2, size.width * fw),
                        height: max(2, size.height * fh)
                    )
                    .offset(x: size.width * fx, y: size.height * fy)
            }
        }
    }
}
