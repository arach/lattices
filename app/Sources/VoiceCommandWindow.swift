import AppKit
import Combine
import SwiftUI

// MARK: - Window Controller

final class VoiceCommandWindow {
    static let shared = VoiceCommandWindow()

    private(set) var panel: NSPanel?
    private var keyMonitor: Any?
    private var state: VoiceCommandState?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            dismiss()
            return
        }
        show()
    }

    func show() {
        // If panel exists but is hidden, just re-show it
        if let p = panel, let s = state {
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                p.animator().alphaValue = 1.0
            }
            installMonitors()
            // Re-show respects the user's last armed state
            if s.armed, s.phase == .idle || s.phase == .result {
                s.startListening()
            }
            return
        }

        let voiceState = VoiceCommandState()
        state = voiceState

        let view = VoiceCommandView(state: voiceState) { [weak self] in
            self?.dismiss()
        }
        .preferredColorScheme(.dark)

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame

        let panelWidth: CGFloat = min(720, visible.width - 80)
        let panelHeight: CGFloat = min(560, visible.height - 80)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = true
        p.contentView = NSHostingView(rootView: view)

        // Position: top-center of screen
        let x = visible.midX - panelWidth / 2
        let y = visible.maxY - panelHeight - 40
        p.setFrameOrigin(NSPoint(x: x, y: y))

        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1.0
        }

        self.panel = p
        installMonitors()

        // Auto-start listening immediately
        voiceState.startListening()
    }

    func dismiss() {
        guard let p = panel else { return }
        removeMonitors()

        if let s = state, s.phase == .listening {
            AudioLayer.shared.stopVoiceCommand()
        }

        // Hide panel but keep state — Hyper+3 will bring it back
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 0
        }) {
            p.orderOut(nil)
        }
    }

    private func installMonitors() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let state = self.state else { return }

            switch event.keyCode {
            case 53: // Escape
                if state.phase == .listening {
                    state.cancelListening()
                    state.armed = false
                } else {
                    self.dismiss()
                }

            case 48: // Tab — toggle armed
                state.toggleArmed()

            case 49: // Space — only when armed
                guard state.armed else { break }
                state.toggleListening()

            default:
                break
            }
        }
    }

    private func removeMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }
}

// MARK: - Transcript Entry

struct ResultItem: Identifiable {
    let id = UUID()
    let wid: UInt32
    let app: String
    let title: String
}

struct TranscriptEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let text: String
    let intent: String?
    let slots: [String: String]
    let result: String?
    let resultItems: [ResultItem]
    let logLines: [String]
}

// MARK: - State

final class VoiceCommandState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case connecting
        case listening
        case transcribing
        case result
    }

    @Published var phase: Phase = .idle
    @Published var armed: Bool = true   // When armed, Space controls the mic
    @Published var partialText: String = ""

    // Current command
    @Published var finalText: String = ""
    @Published var intentName: String?
    @Published var intentSlots: [String: String] = [:]
    @Published var executionResult: String?
    @Published var resultItems: [ResultItem] = []
    @Published var resultSummary: String = ""

    // Agent advisor response
    @Published var agentResponse: AgentResponse?

    // Listening timer
    @Published var listenStartTime: Date = Date()

    // History — all transcripts this session
    @Published var history: [TranscriptEntry] = []

    // Diagnostic log
    @Published var logLines: [String] = []

    private var logSnapshot = 0
    private var logObserver: AnyCancellable?

    func startListening() {
        let client = TalkieClient.shared

        if client.connectionState == .connected {
            beginListening()
        } else {
            phase = .connecting
            client.connect()
            waitForConnection(attempts: 0)
        }
    }

    private func waitForConnection(attempts: Int) {
        let client = TalkieClient.shared
        if client.connectionState == .connected {
            beginListening()
        } else if attempts < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.waitForConnection(attempts: attempts + 1)
            }
        } else {
            appendLog("Connection to Talkie failed after 2s")
            phase = .idle
        }
    }

    private func beginListening() {
        phase = .listening
        listenStartTime = Date()
        partialText = ""
        finalText = ""
        intentName = nil
        intentSlots = [:]
        executionResult = nil
        resultItems = []
        resultSummary = ""
        agentResponse = nil
        // Snapshot log position and observe changes reactively (no polling race)
        logSnapshot = DiagnosticLog.shared.entries.count
        logLines = []
        logObserver = DiagnosticLog.shared.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] entries in
                guard let self else { return }
                let start = min(self.logSnapshot, entries.count)
                let newLines = entries.suffix(from: start).map { $0.message }
                if !newLines.isEmpty {
                    self.logLines = newLines
                }
            }
        AudioLayer.shared.startVoiceCommand()
    }

    func stopListening() {
        phase = .transcribing
        AudioLayer.shared.stopVoiceCommand()
        observeResult()
    }

    func cancelListening() {
        phase = .idle
        AudioLayer.shared.stopVoiceCommand()
        appendLog("Cancelled")
    }

    func toggleArmed() {
        if phase == .listening {
            // Stop listening when disarming
            cancelListening()
        }
        armed.toggle()
    }

    func toggleListening() {
        switch phase {
        case .listening:
            stopListening()
        case .idle, .result:
            startListening()
        default:
            break
        }
    }

    func appendLog(_ msg: String) {
        logLines.append(msg)
    }

    private func syncLogs() {
        // Logs are now updated reactively via logObserver.
        // This is kept as a manual trigger for the final commit.
        let entries = DiagnosticLog.shared.entries
        let start = min(logSnapshot, entries.count)
        let newLines = entries.suffix(from: start).map { $0.message }
        if !newLines.isEmpty {
            logLines = newLines
        }
    }

    private func pollForAdvisor() {
        let audio = AudioLayer.shared
        var checks = 0

        func poll() {
            if let resp = audio.agentResponse {
                self.agentResponse = resp
                return
            }
            checks += 1
            if checks < 60 { // Up to 12 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() }
            }
        }

        // Only poll if we don't already have a response
        if agentResponse == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() }
        }
    }

    private func commitToHistory() {
        guard !finalText.isEmpty else { return }
        let entry = TranscriptEntry(
            timestamp: Date(),
            text: finalText,
            intent: intentName,
            slots: intentSlots,
            result: executionResult,
            resultItems: resultItems,
            logLines: logLines
        )
        history.append(entry)
        // logLines are NOT reset here — they stay visible until the next command starts
    }

    private func observeResult() {
        let audio = AudioLayer.shared
        var checks = 0
        let maxChecks = 150

        func poll() {
            checks += 1

            // Sync transcript
            if let transcript = audio.lastTranscript, !transcript.isEmpty {
                self.finalText = transcript
            }

            // Sync logs
            syncLogs()

            // Sync intent/slots
            self.intentName = audio.matchedIntent
            self.intentSlots = audio.matchedSlots

            // Sync agent advisor response
            if let resp = audio.agentResponse {
                self.agentResponse = resp
            }

            let result = audio.executionResult

            // Terminal errors — log them, go to idle (not a separate error phase)
            if result == "No speech detected" {
                appendLog("No speech detected")
                self.phase = .idle
                return
            }
            if result == "Transcription failed" {
                appendLog("Transcription failed")
                self.phase = .idle
                return
            }
            if let result, result.hasPrefix("Mic in use") {
                appendLog(result)
                self.phase = .idle
                return
            }

            // Still working
            let stillWorking = result == nil
                || result == "Transcribing..."
                || result == "thinking..."
                || result == "searching..."

            if stillWorking {
                if let result { self.executionResult = result }
                self.phase = .transcribing
                if checks < maxChecks {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() }
                } else {
                    appendLog("Timed out waiting for result")
                    self.phase = .idle
                }
                return
            }

            // Grace period for transcript
            if self.finalText.isEmpty && checks < 25 {
                self.phase = .transcribing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() }
                return
            }

            // Final result
            self.executionResult = result
            if let data = audio.executionData {
                switch data {
                case .array(let items):
                    self.resultItems = items.compactMap { item in
                        guard let wid = item["wid"]?.intValue,
                              let app = item["app"]?.stringValue,
                              let title = item["title"]?.stringValue else { return nil }
                        return ResultItem(wid: UInt32(wid), app: app, title: title)
                    }
                    self.resultSummary = "\(items.count) result\(items.count == 1 ? "" : "s")"
                case .object(let obj):
                    self.resultItems = []
                    self.resultSummary = obj.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                default:
                    self.resultItems = []
                    self.resultSummary = "\(data)"
                }
            } else {
                self.resultItems = []
                self.resultSummary = ""
            }

            syncLogs()  // Final sync before committing
            commitToHistory()
            self.phase = .result

            // Keep polling for agent advisor response (arrives later)
            self.pollForAdvisor()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { poll() }
    }
}

// MARK: - View

struct VoiceCommandView: View {
    @ObservedObject var state: VoiceCommandState
    let onDismiss: () -> Void

    private let docsURL = "https://lattices.dev/docs/voice"

    private var hasHistory: Bool { !state.history.isEmpty || !state.logLines.isEmpty || state.phase != .idle }

    var body: some View {
        VStack(spacing: 0) {
            // Mic bar
            micBar

            // Main content
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 0) {
                    // Left: history + log — only shown when there's content
                    if hasHistory {
                        VStack(spacing: 0) {
                            transcriptHistory
                            logPane
                        }
                        .frame(width: geo.size.width * 0.4, height: geo.size.height, alignment: .top)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                        Rectangle().fill(Palette.border).frame(width: 0.5)
                    }

                    // Right: voice command — full height
                    voiceCommandPane
                        .frame(height: geo.size.height, alignment: .top)
                }
                .animation(.easeInOut(duration: 0.25), value: hasHistory)
            }

            // Footer
            footerBar
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Palette.borderLit, lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Mic Bar

    private var micBar: some View {
        HStack(spacing: 0) {
            // Mic button
            Button(action: { state.toggleListening() }) {
                HStack(spacing: 8) {
                    Image(systemName: state.phase == .listening ? "mic.fill" : state.armed ? "mic" : "mic.slash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(state.phase == .listening ? .white : state.armed ? Palette.textMuted : Palette.textMuted.opacity(0.4))

                    if state.phase == .listening {
                        WaveBar()
                        ListeningTimer(startTime: state.listenStartTime)
                    } else {
                        statusLabel
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(height: 36)
        .background(Color.black)
    }

    private var statusLabel: some View {
        Group {
            switch state.phase {
            case .idle:
                if state.armed {
                    Text("ready — Space to speak")
                        .foregroundColor(Palette.textMuted)
                } else {
                    Text("paused — Tab to activate")
                        .foregroundColor(Palette.textMuted.opacity(0.5))
                }
            case .connecting:
                Text("connecting...")
                    .foregroundColor(Palette.detach)
            case .listening:
                ListeningTimer(startTime: state.listenStartTime)
            case .transcribing:
                if let r = state.executionResult, r == "thinking..." || r == "searching..." {
                    Text(r)
                        .foregroundColor(Palette.detach)
                } else {
                    Text("processing...")
                        .foregroundColor(Palette.textDim)
                }
            case .result:
                if state.armed {
                    Text("done — Space for next")
                        .foregroundColor(Palette.textMuted)
                } else {
                    Text("done — paused")
                        .foregroundColor(Palette.textMuted.opacity(0.5))
                }
            }
        }
        .font(Typo.geistMono(10))
    }

    // MARK: - Transcript History (left pane)

    private var transcriptHistory: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HISTORY")
                    .font(Typo.geistMonoBold(9))
                    .foregroundColor(Palette.textMuted)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            if !state.history.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(state.history) { entry in
                                historyRow(entry)
                                    .id(entry.id)
                                Rectangle().fill(Palette.border).frame(height: 0.5)
                            }
                        }
                    }
                    .onChange(of: state.history.count) { _ in
                        if let last = state.history.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .background(Palette.bg.opacity(0.5))
    }

    @State private var expandedEntries: Set<UUID> = []

    private func historyRow(_ entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Timestamp + transcript
            HStack(alignment: .top, spacing: 6) {
                Text(entry.timestamp, style: .time)
                    .font(Typo.geistMono(9))
                    .foregroundColor(Palette.textMuted)
                Text(entry.text)
                    .font(Typo.geistMono(11))
                    .foregroundColor(Palette.text)
                    .lineLimit(3)
                Spacer()
            }

            // Intent tag
            if let intent = entry.intent {
                HStack(spacing: 4) {
                    Text(intent)
                        .font(Typo.geistMonoBold(9))
                        .foregroundColor(Palette.running)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.running.opacity(0.1))
                        )

                    if !entry.slots.isEmpty {
                        let slotText = entry.slots.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
                        Text(slotText)
                            .font(Typo.geistMono(9))
                            .foregroundColor(Palette.textDim)
                    }
                }
            }

            // Result items (clickable)
            if !entry.resultItems.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(entry.resultItems.prefix(5).enumerated()), id: \.1.id) { idx, item in
                        ResultRow(index: idx, item: item, onFocus: focusWindow, onTile: tileWindow)
                    }
                    if entry.resultItems.count > 5 {
                        Text("+ \(entry.resultItems.count - 5) more")
                            .font(Typo.geistMono(9))
                            .foregroundColor(Palette.textMuted)
                    }
                }
            } else if let result = entry.result, result != "ok" {
                Text(result)
                    .font(Typo.geistMono(9))
                    .foregroundColor(Palette.detach)
            }

            // Expandable log lines
            if expandedEntries.contains(entry.id), !entry.logLines.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(entry.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(Palette.textMuted.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.logLines.isEmpty { return }
            if expandedEntries.contains(entry.id) {
                expandedEntries.remove(entry.id)
            } else {
                expandedEntries.insert(entry.id)
            }
        }
    }

    // MARK: - Voice Command (right pane, full height)

    private var voiceCommandPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("VOICE COMMAND")
                    .font(Typo.geistMonoBold(9))
                    .foregroundColor(Palette.textMuted)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // Partial transcript (while listening)
                    if state.phase == .listening, !state.partialText.isEmpty {
                        commandSection("hearing...") {
                            Text(state.partialText)
                                .font(Typo.geistMono(13))
                                .foregroundColor(Palette.textDim)
                        }
                    }

                    // What was heard
                    if !state.finalText.isEmpty {
                        commandSection("heard") {
                            Text(state.finalText)
                                .font(Typo.geistMono(13))
                                .foregroundColor(Palette.text)
                                .textSelection(.enabled)
                        }
                    }

                    // Matched intent + slots
                    if let intent = state.intentName {
                        commandSection("intent") {
                            HStack(spacing: 6) {
                                Text(intent)
                                    .font(Typo.geistMonoBold(11))
                                    .foregroundColor(Palette.running)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Palette.running.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .strokeBorder(Palette.running.opacity(0.2), lineWidth: 0.5)
                                            )
                                    )

                                if !state.intentSlots.isEmpty {
                                    ForEach(Array(state.intentSlots.keys.sorted()), id: \.self) { key in
                                        if let val = state.intentSlots[key] {
                                            Text("\(key): \(val)")
                                                .font(Typo.geistMono(10))
                                                .foregroundColor(Palette.detach)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 3)
                                                        .fill(Palette.detach.opacity(0.08))
                                                )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Results
                    if !state.resultItems.isEmpty {
                        commandSection("\(state.resultItems.count) match\(state.resultItems.count == 1 ? "" : "es")") {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(state.resultItems.prefix(25).enumerated()), id: \.1.id) { idx, item in
                                    ResultRow(index: idx, item: item, onFocus: focusWindow, onTile: tileWindow)
                                }
                                if state.resultItems.count > 25 {
                                    Text("+ \(state.resultItems.count - 25) more")
                                        .font(Typo.geistMono(9))
                                        .foregroundColor(Palette.textMuted)
                                }
                            }
                        }
                    } else if !state.resultSummary.isEmpty {
                        commandSection("result") {
                            Text(state.resultSummary)
                                .font(Typo.geistMono(11))
                                .foregroundColor(Palette.text)
                        }
                    } else if state.executionResult == "ok" {
                        commandSection("result") {
                            Text("done")
                                .font(Typo.geistMono(11))
                                .foregroundColor(Palette.running)
                        }
                    }

                    // Claude advisor section
                    if let agent = state.agentResponse {
                        advisorSection(agent)
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: - Advisor (Claude says)

    private func advisorSection(_ response: AgentResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLAUDE")
                .font(Typo.geistMono(9))
                .foregroundColor(Palette.textMuted)
                .tracking(1)

            if let commentary = response.commentary {
                Text(commentary)
                    .font(Typo.geistMono(11))
                    .foregroundColor(Palette.text)
                    .lineLimit(3)
            }

            if let suggestion = response.suggestion {
                Button(action: {
                    executeSuggestion(suggestion)
                }) {
                    HStack(spacing: 6) {
                        Text(suggestion.label)
                            .font(Typo.geistMono(10))
                            .foregroundColor(Palette.text)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundColor(Palette.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Palette.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Palette.border, lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.surface.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.border.opacity(0.5), lineWidth: 0.5)
                )
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeInOut(duration: 0.3), value: response.raw)
    }

    private func executeSuggestion(_ suggestion: AgentResponse.AgentSuggestion) {
        let slots: [String: JSON] = suggestion.slots.reduce(into: [:]) { dict, pair in
            dict[pair.key] = .string(pair.value)
        }
        let match = IntentMatch(
            intentName: suggestion.intent,
            slots: slots,
            confidence: 0.9,
            matchedPhrase: "advisor-suggestion"
        )
        do {
            let result = try PhraseMatcher.shared.execute(match)
            state.appendLog("Advisor: executed \(suggestion.intent) → ok")
            DiagnosticLog.shared.info("Advisor suggestion executed: \(suggestion.intent) → \(result)")
        } catch {
            state.appendLog("Advisor: \(suggestion.intent) failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Log (left pane, bottom)

    private var logPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LOG")
                    .font(Typo.geistMonoBold(9))
                    .foregroundColor(Palette.textMuted)
                    .tracking(1)
                Spacer()
                if !state.logLines.isEmpty {
                    Button(action: {
                        let text = state.logLines.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }) {
                        Text("copy")
                            .font(Typo.geistMono(9))
                            .foregroundColor(Palette.textMuted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Palette.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .strokeBorder(Palette.border, lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(state.logLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Palette.textMuted)
                                .lineLimit(1)
                                .id(idx)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
                .onChange(of: state.logLines.count) { _ in
                    let last = state.logLines.count - 1
                    if last >= 0 {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: 100)
            .background(Palette.bg.opacity(0.3))
        }
    }

    // MARK: - Section Helper

    private func commandSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Typo.geistMono(9))
                .foregroundColor(Palette.textMuted)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.surface.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Footer

    private var footerBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.border).frame(height: 0.5)
            HStack(spacing: 12) {
                footerHint("ESC", "Dismiss", dimmed: false)
                footerHint("Tab", state.armed ? "Pause" : "Activate", dimmed: false)
                footerHint("Space", state.phase == .listening ? "Stop" : "Speak", dimmed: !state.armed && state.phase != .listening)

                Spacer()

                Text("find · show · open · tile · kill · scan")
                    .font(Typo.geistMono(9))
                    .foregroundColor(Palette.textMuted.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Palette.surface.opacity(0.6))
        }
    }

    private func footerHint(_ key: String, _ label: String, dimmed: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(Typo.geistMonoBold(9))
                .foregroundColor(dimmed ? Palette.textMuted.opacity(0.3) : Palette.text)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.surface.opacity(dimmed ? 0.3 : 1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Palette.border.opacity(dimmed ? 0.3 : 1), lineWidth: 0.5)
                        )
                )
            Text(label)
                .font(Typo.caption(9))
                .foregroundColor(dimmed ? Palette.textMuted.opacity(0.3) : Palette.textMuted)
        }
    }

    private func focusWindow(wid: UInt32) {
        guard let entry = DesktopModel.shared.windows[wid] else { return }
        DispatchQueue.main.async {
            WindowTiler.focusWindow(wid: wid, pid: entry.pid)
            WindowTiler.highlightWindowById(wid: wid)
        }
    }

    private func tileWindow(wid: UInt32, position: String) {
        guard let entry = DesktopModel.shared.windows[wid],
              let pos = TilePosition(rawValue: position) else { return }
        DispatchQueue.main.async {
            WindowTiler.focusWindow(wid: wid, pid: entry.pid)
            WindowTiler.tileWindowById(wid: wid, pid: entry.pid, to: pos)
            WindowTiler.highlightWindowById(wid: wid)
        }
    }

}

// MARK: - Result Row (hover actions)

// MARK: - Wave Bar Animation

struct WaveBar: View {
    @State private var animating = false
    private let barCount = 4
    private let barWidth: CGFloat = 2
    private let barSpacing: CGFloat = 1.5

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Palette.text.opacity(0.7))
                    .frame(width: barWidth, height: animating ? barHeight(for: i) : 3)
                    .animation(
                        .easeInOut(duration: duration(for: i))
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.1),
                        value: animating
                    )
            }
        }
        .frame(height: 12)
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }

    private func barHeight(for index: Int) -> CGFloat {
        [10, 6, 12, 8][index % 4]
    }

    private func duration(for index: Int) -> Double {
        [0.4, 0.35, 0.45, 0.3][index % 4]
    }
}

// MARK: - Listening Timer

struct ListeningTimer: View {
    let startTime: Date
    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatTime(elapsed))
            .font(Typo.geistMono(10))
            .foregroundColor(Palette.text.opacity(0.7))
            .monospacedDigit()
            .onReceive(timer) { _ in
                elapsed = Date().timeIntervalSince(startTime)
            }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let secs = Int(t)
        let tenths = Int((t - Double(secs)) * 10)
        return String(format: "%d.%d", secs, tenths)
    }
}

// MARK: - Result Row

struct ResultRow: View {
    let index: Int
    let item: ResultItem
    let onFocus: (UInt32) -> Void
    let onTile: (UInt32, String) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text("\(index + 1)")
                .font(Typo.geistMono(9))
                .foregroundColor(Palette.textMuted)
                .frame(width: 14, alignment: .leading)
            Text(item.app)
                .font(Typo.geistMonoBold(10))
                .foregroundColor(Palette.textDim)
                .frame(width: 60, alignment: .leading)
            Text(item.title.isEmpty ? "(untitled)" : item.title)
                .font(Typo.geistMono(10))
                .foregroundColor(Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if isHovered {
                HStack(spacing: 4) {
                    actionButton("Focus", systemImage: "eye") {
                        onFocus(item.wid)
                    }
                    actionButton("Tile Left", systemImage: "rectangle.lefthalf.filled") {
                        onTile(item.wid, "left")
                    }
                    actionButton("Tile Right", systemImage: "rectangle.righthalf.filled") {
                        onTile(item.wid, "right")
                    }
                    actionButton("Maximize", systemImage: "rectangle.fill") {
                        onTile(item.wid, "maximize")
                    }
                    actionButton("Inspect in Map", systemImage: "map") {
                        ScreenMapWindowController.shared.showWindow(wid: item.wid)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Palette.surface : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onFocus(item.wid)
        }
    }

    private func actionButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9))
                .foregroundColor(Palette.text)
                .frame(width: 22, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Palette.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

