import AppKit
import Combine
import SwiftUI

// MARK: - Window Controller

final class VoiceCommandWindow {
    static let shared = VoiceCommandWindow()

    private(set) var panel: OverlayPanel?
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
        if let p = panel, state != nil {
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                p.animator().alphaValue = 1.0
            }
            installMonitors()
            // Push-to-talk: user holds Option to start, no auto-listen
            return
        }

        let voiceState = VoiceCommandState()
        state = voiceState

        let view = VoiceCommandView(state: voiceState) { [weak self] in
            self?.dismiss()
        }
        .preferredColorScheme(.dark)

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let panelWidth: CGFloat = min(900, visible.width - 80)
        let panelHeight: CGFloat = min(560, visible.height - 80)

        let p = OverlayPanelShell.makePanel(
            config: .init(
                size: NSSize(width: panelWidth, height: panelHeight),
                styleMask: [.titled, .nonactivatingPanel],
                titleVisible: .hidden,
                titlebarAppearsTransparent: true,
                background: .clear,
                hidesOnDeactivate: false,
                isMovableByWindowBackground: true,
                activatesOnMouseDown: true,
                onKeyDown: { [weak self] event in self?.handleKey(event) },
                onFlagsChanged: { [weak self] event in self?.handleFlags(event) }
            ),
            rootView: view
        )
        OverlayPanelShell.position(p, placement: .topCenter(margin: 40))

        p.alphaValue = 0
        OverlayPanelShell.present(p, activate: true, makeKey: true, orderFrontRegardless: true)

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

        // Cancel any in-progress listening or processing
        state?.cancelProcessing()

        // Hide panel but keep state — Hyper+3 will bring it back
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 0
        }) {
            p.orderOut(nil)
        }
    }

    private func handleKey(_ event: NSEvent) {
        guard let state else { return }

        switch event.keyCode {
        case 53: // Escape
            if state.phase == .listening {
                state.cancelListening()
                state.armed = false
            } else {
                dismiss()
            }

        case 48: // Tab — toggle armed
            state.toggleArmed()

        default:
            break
        }
    }

    /// Push-to-talk: hold Option to record, release to stop. Only when panel is focused.
    private func handleFlags(_ event: NSEvent) {
        guard let state else { return }
        let optionDown = event.modifierFlags.contains(.option)

        if optionDown {
            // Option pressed — start recording
            if state.armed, state.phase == .idle || state.phase == .result {
                state.startListening()
            }
        } else {
            // Option released — stop recording
            if state.phase == .listening {
                state.stopListening()
            }
        }
    }

    private var focusObservers: [NSObjectProtocol] = []

    private var flagsMonitor: Any?

    private func installMonitors() {
        // Global monitor: Escape/Tab only (no recording keys globally)
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
        }

        // Local flagsChanged monitor: push-to-talk with Option key (only when panel is focused)
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            // Only handle when our panel is the key window
            guard let self, event.window === self.panel else { return event }
            self.handleFlags(event)
            return event
        }

        // Focus/blur: cancel recording if window loses focus
        let nc = NotificationCenter.default
        focusObservers.append(
            nc.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                guard let self, let state = self.state else { return }
                if state.phase == .listening {
                    state.cancelListening()
                }
            }
        )
    }

    private func removeMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        for obs in focusObservers { NotificationCenter.default.removeObserver(obs) }
        focusObservers.removeAll()
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
    private var cancelled = false

    func startListening() {
        let client = VoxClient.shared

        if client.connectionState == .connected {
            beginListening()
        } else {
            phase = .connecting
            client.connect()
            waitForConnection(attempts: 0)
        }
    }

    private func waitForConnection(attempts: Int) {
        let client = VoxClient.shared
        if client.connectionState == .connected {
            beginListening()
        } else if attempts < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.waitForConnection(attempts: attempts + 1)
            }
        } else {
            appendLog("Connection to Vox failed after 2s")
            phase = .idle
        }
    }

    private func beginListening() {
        cancelled = false
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
        cancelled = true
        phase = .idle
        AudioLayer.shared.stopVoiceCommand()
        appendLog("Cancelled")
    }

    /// Cancel any in-progress processing (polling loops will check this flag).
    func cancelProcessing() {
        cancelled = true
        if phase == .listening || phase == .transcribing || phase == .connecting {
            AudioLayer.shared.stopVoiceCommand()
            appendLog("Processing cancelled")
            phase = .idle
        }
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
        DiagnosticLog.shared.info(msg)
    }

    private func syncLogs() {
        // Logs are now updated reactively via logObserver.
        // This is kept as a manual trigger for the final commit.
        let entries = DiagnosticLog.shared.entries
        let start = min(logSnapshot, entries.count)
        let newLines = entries.suffix(from: start).map { $0.message }
        logLines = newLines
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

    func restoreFromHistory(_ entry: TranscriptEntry) {
        finalText = entry.text
        intentName = entry.intent
        intentSlots = entry.slots
        executionResult = entry.result
        resultItems = entry.resultItems
        resultSummary = entry.resultItems.isEmpty ? "" : "\(entry.resultItems.count) result\(entry.resultItems.count == 1 ? "" : "s")"
        logLines = entry.logLines
        agentResponse = nil
        phase = .result
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
        let maxChecks = 75  // 15 seconds at 0.2s intervals

        func syncState() {
            // Sync transcript immediately
            if let transcript = audio.lastTranscript, !transcript.isEmpty {
                self.finalText = transcript
            }

            // Sync intent/slots as they become available
            if let intent = audio.matchedIntent {
                self.intentName = intent
                self.intentSlots = audio.matchedSlots
            }

            // Sync agent advisor response
            if let resp = audio.agentResponse {
                self.agentResponse = resp
            }
        }

        func poll() {
            // Bail if cancelled (e.g. user dismissed or started a new command)
            guard !self.cancelled else { return }

            checks += 1
            syncState()

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

        // Sync immediately (no delay for transcript), then start polling
        syncState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() }
    }
}

// MARK: - View

struct VoiceCommandView: View {
    @ObservedObject var state: VoiceCommandState
    @ObservedObject private var activeSelection = WindowSelectionStore.shared
    let onDismiss: () -> Void

    private let docsURL = "https://lattices.dev/docs/voice"

    @State private var historyColumnWidth: CGFloat?
    @State private var logColumnWidth: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            // Mic bar
            micBar
            Rectangle().fill(Palette.border).frame(height: 0.5)

            // Three-column layout — all widths computed explicitly
            GeometryReader { geo in
                let histW = historyColumnWidth ?? geo.size.width * 0.20
                let logW = logColumnWidth ?? geo.size.width * 0.28
                let dividerW: CGFloat = 1
                let voiceW = geo.size.width - histW - logW - (dividerW * 2)

                HStack(spacing: 0) {
                    // HISTORY column
                    VStack(spacing: 0) {
                        Text("HISTORY")
                            .font(Typo.geistMonoBold(9))
                            .foregroundColor(Palette.textMuted)
                            .tracking(1)
                            .padding(.leading, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        Rectangle().fill(Palette.border).frame(height: 0.5)
                        transcriptHistoryBody
                            .frame(width: histW, height: geo.size.height - 30)
                    }
                    .frame(width: histW, height: geo.size.height)

                    // Left divider — full height
                    columnDivider(
                        width: $historyColumnWidth,
                        defaultWidth: geo.size.width * 0.20,
                        min: 100, max: geo.size.width * 0.35
                    )
                    .frame(height: geo.size.height)

                    // VOICE COMMAND column — explicit width
                    VStack(spacing: 0) {
                        Text("VOICE COMMAND")
                            .font(Typo.geistMonoBold(9))
                            .foregroundColor(Palette.textMuted)
                            .tracking(1)
                            .padding(.leading, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        Rectangle().fill(Palette.border).frame(height: 0.5)
                        voiceCommandBody
                            .frame(width: voiceW, height: geo.size.height - 30, alignment: .topLeading)
                    }
                    .frame(width: voiceW, height: geo.size.height)

                    // Right divider — full height
                    columnDivider(
                        width: $logColumnWidth,
                        defaultWidth: geo.size.width * 0.28,
                        min: 140, max: geo.size.width * 0.40,
                        inverted: true
                    )
                    .frame(height: geo.size.height)

                    // LOG + AI column (split vertically)
                    VStack(spacing: 0) {
                        logHeader
                            .frame(width: logW, alignment: .leading)
                        Rectangle().fill(Palette.border).frame(height: 0.5)
                        logBody
                            .frame(width: logW, height: (geo.size.height - 30) * 0.55)
                        Rectangle().fill(Palette.border).frame(height: 0.5)
                        aiCorner
                            .frame(width: logW, height: (geo.size.height - 30) * 0.45)
                    }
                    .frame(width: logW, height: geo.size.height)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            Rectangle().fill(Palette.border).frame(height: 0.5)

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
                    Text("ready — hold ⌥ to speak")
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
                Text("done")
                    .foregroundColor(Palette.textMuted)
            }
        }
        .font(Typo.geistMono(10))
    }

    // MARK: - Transcript History (left pane)

    private var transcriptHistoryBody: some View {
        Group {
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
            } else {
                Color.clear
            }
        }
    }

    @State private var expandedEntries: Set<UUID> = []

    private func historyRow(_ entry: TranscriptEntry) -> some View {
        let isExpanded = expandedEntries.contains(entry.id)

        return VStack(alignment: .leading, spacing: 4) {
            // Always visible: compact row
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 7))
                    .foregroundColor(Palette.textMuted)
                    .frame(width: 8)

                Text(entry.timestamp, style: .time)
                    .font(Typo.geistMono(9))
                    .foregroundColor(Palette.textMuted)

                if let intent = entry.intent {
                    Text(intent)
                        .font(Typo.geistMonoBold(9))
                        .foregroundColor(Palette.running)
                } else {
                    Text(entry.text)
                        .font(Typo.geistMono(9))
                        .foregroundColor(Palette.text)
                        .lineLimit(1)
                }

                Spacer()

                if !entry.resultItems.isEmpty {
                    Text("\(entry.resultItems.count)")
                        .font(Typo.geistMono(8))
                        .foregroundColor(Palette.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.surface)
                        )
                }
            }

            // Expanded: full details
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    // Transcript
                    Text(entry.text)
                        .font(Typo.geistMono(11))
                        .foregroundColor(Palette.text)
                        .lineLimit(3)
                        .padding(.leading, 14)

                    // Intent + slots
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
                        .padding(.leading, 14)
                    }

                    // Result items
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
                        .padding(.leading, 14)
                    } else if let result = entry.result, result != "ok" {
                        Text(result)
                            .font(Typo.geistMono(9))
                            .foregroundColor(Palette.detach)
                            .padding(.leading, 14)
                    }

                    // Log lines
                    if !entry.logLines.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(entry.logLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(Palette.textMuted.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.leading, 14)
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isExpanded ? 10 : 6)
        .background(isExpanded ? Palette.surface.opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isExpanded {
                    expandedEntries.remove(entry.id)
                } else {
                    expandedEntries.insert(entry.id)
                }
            }
        }
    }

    // MARK: - Voice Command (center pane)

    private var voiceCommandBody: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                    // Zero-height spacer forces VStack to fill ScrollView width
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    if activeSelection.isActive {
                        commandSection("selection") {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text("\(activeSelection.count) window\(activeSelection.count == 1 ? "" : "s")")
                                        .font(Typo.geistMonoBold(11))
                                        .foregroundColor(Palette.running)
                                    if let source = activeSelection.sourceLabel {
                                        Text(source)
                                            .font(Typo.geistMono(10))
                                            .foregroundColor(Palette.textMuted)
                                    }
                                }
                                Text(activeSelection.summary(maxItems: 4))
                                    .font(Typo.geistMono(11))
                                    .foregroundColor(Palette.textDim)
                                    .lineLimit(3)
                                Text("Try: grid that in the bottom half")
                                    .font(Typo.geistMono(10))
                                    .foregroundColor(Palette.textMuted)
                            }
                        }
                    }

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

                    // Advisor now lives in the AI corner (bottom-right)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
    }

    private func copyAIResponse() {
        guard let response = state.agentResponse else { return }
        var text = ""
        if let commentary = response.commentary { text += commentary }
        if let suggestion = response.suggestion {
            if !text.isEmpty { text += "\n" }
            text += "\(suggestion.label) → \(suggestion.intent)"
            if !suggestion.slots.isEmpty {
                text += " " + suggestion.slots.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func manuallyAskAdvisor() {
        let transcript = state.finalText
        let matched = state.intentName ?? "none"
        let slots = state.intentSlots.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        let matchStr = slots.isEmpty ? matched : "\(matched)(\(slots))"

        let assistant = PiChatSession.shared
        guard assistant.isProviderInferenceReady else {
            state.appendLog("Assistant provider not ready")
            return
        }

        state.appendLog("Asking Assistant...")
        assistant.askVoiceAdvisor(transcript: transcript, matched: matchStr) { [weak state] response in
            guard let state = state, let response = response else { return }
            state.agentResponse = response
        }
    }

    private func executeSuggestion(_ suggestion: AgentResponse.AgentSuggestion) {
        var slotsDict = suggestion.slots

        // If the intent needs a query slot and the assistant did not include one,
        // try to extract it from the label or fall back to the original query
        if suggestion.intent == "search" && slotsDict["query"] == nil {
            // Try extracting from label: "Deep search Vox" → "Vox"
            let label = suggestion.label
            let prefixes = ["Deep search ", "Search ", "Find ", "deep search ", "search ", "find "]
            var extracted: String?
            for prefix in prefixes {
                if label.hasPrefix(prefix) {
                    extracted = String(label.dropFirst(prefix.count))
                    break
                }
            }
            // Fall back to the original query slot from the local match
            let query = extracted ?? state.intentSlots["query"] ?? state.finalText
            slotsDict["query"] = query
            DiagnosticLog.shared.info("Advisor: inferred query='\(query)' for search suggestion")
        }

        let slots: [String: JSON] = slotsDict.reduce(into: [:]) { dict, pair in
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

            // Capture the learning signal: advisor saved us, user engaged
            AdvisorLearningStore.shared.record(
                transcript: state.finalText,
                localIntent: state.intentName,
                localSlots: state.intentSlots,
                localResultCount: state.resultItems.count,
                advisorIntent: suggestion.intent,
                advisorSlots: suggestion.slots,
                advisorLabel: suggestion.label
            )
        } catch {
            state.appendLog("Advisor: \(suggestion.intent) failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Log (right pane)

    private var logHeader: some View {
        HStack(spacing: 6) {
            Text("LOG")
                .font(Typo.geistMonoBold(9))
                .foregroundColor(Palette.textMuted)
                .tracking(1)
            Spacer()
            if !DiagnosticLog.shared.entries.isEmpty {
                Button(action: {
                    let fmt = DateFormatter()
                    fmt.dateFormat = "HH:mm:ss.SSS"
                    let text = DiagnosticLog.shared.entries.map { entry in
                        "\(fmt.string(from: entry.time)) \(entry.icon) \(entry.message)"
                    }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }) {
                    Text("copy")
                        .font(Typo.geistMono(9))
                        .foregroundColor(Palette.textMuted)
                }
                .buttonStyle(.plain)
            }
            Button(action: {
                DiagnosticWindow.shared.toggle()
            }) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 9))
                    .foregroundColor(Palette.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @StateObject private var diagnosticLog = DiagnosticLog.shared

    /// Rolling window: only show the tail of the log
    private var visibleLogEntries: [DiagnosticLog.Entry] {
        let entries = diagnosticLog.entries
        let tail = 12
        if entries.count <= tail { return entries }
        return Array(entries.suffix(tail))
    }

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleLogEntries) { entry in
                        HStack(spacing: 3) {
                            Text(entry.icon)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(logColor(entry.level))
                                .frame(width: 8)
                            Text(entry.message)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(logColor(entry.level))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 1)
                        .id(entry.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .onChange(of: diagnosticLog.entries.count) { _ in
                if let last = visibleLogEntries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func logColor(_ level: DiagnosticLog.Entry.Level) -> Color {
        switch level {
        case .info:    return Palette.textDim
        case .success: return Palette.running
        case .warning: return Palette.detach
        case .error:   return Palette.kill
        }
    }

    // MARK: - AI Corner (bottom-right)

    @ObservedObject private var assistantSession = PiChatSession.shared

    private var aiCorner: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Palette.running)
                Text("AI")
                    .font(Typo.geistMonoBold(9))
                    .foregroundColor(Palette.textMuted)
                    .tracking(1)
                Spacer()

                Text(assistantSession.currentProvider.name)
                    .font(Typo.geistMono(8))
                    .foregroundColor(Palette.textMuted.opacity(0.65))

                if state.agentResponse != nil {
                    Button(action: { copyAIResponse() }) {
                        Text("copy")
                            .font(Typo.geistMono(9))
                            .foregroundColor(Palette.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                if assistantSession.isProviderInferenceReady {
                    Circle()
                        .fill(Palette.running.opacity(0.6))
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Rectangle().fill(Palette.border).frame(height: 0.5)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let agent = state.agentResponse {
                        // Commentary
                        if let commentary = agent.commentary {
                            Text(commentary)
                                .font(Typo.geistMono(10))
                                .foregroundColor(Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Suggestion button
                        if let suggestion = agent.suggestion {
                            Button(action: { executeSuggestion(suggestion) }) {
                                HStack(spacing: 5) {
                                    Text(suggestion.label)
                                        .font(Typo.geistMonoBold(9))
                                        .foregroundColor(Palette.text)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(Palette.running)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Palette.running.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(Palette.running.opacity(0.2), lineWidth: 0.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } else if state.phase == .transcribing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.6)
                            Text("thinking...")
                                .font(Typo.geistMono(9))
                                .foregroundColor(Palette.textMuted)
                        }
                    } else if state.phase == .result, !state.finalText.isEmpty {
                        // No AI response yet — offer to ask
                        HStack(spacing: 6) {
                            Text("no AI needed")
                                .font(Typo.geistMono(9))
                                .foregroundColor(Palette.textMuted)
                            Button(action: { manuallyAskAdvisor() }) {
                                Text("ask AI")
                                    .font(Typo.geistMonoBold(9))
                                    .foregroundColor(Palette.text)
                                    .padding(.horizontal, 8)
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
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text("ready")
                            .font(Typo.geistMono(9))
                            .foregroundColor(Palette.textMuted.opacity(0.5))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Section Helper

    private func commandSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Typo.geistMono(9))
                .foregroundColor(Palette.textDim)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.surface.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.borderLit, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            footerHint("ESC", "Dismiss", dimmed: false)
            footerHint("Tab", state.armed ? "Pause" : "Activate", dimmed: false)
            if state.phase == .listening {
                footerHint("⌥", "Release to stop", dimmed: false)
            } else {
                footerHint("⌥", "Hold to speak", dimmed: !state.armed || state.phase == .result)
            }

            Spacer()

            Text("find · show · open · tile · kill · scan")
                .font(Typo.geistMono(9))
                .foregroundColor(Palette.textDim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Palette.surface.opacity(0.6))
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

    // MARK: - Resizable Column Divider

    private func columnDivider(
        width: Binding<CGFloat?>,
        defaultWidth: CGFloat,
        min minW: CGFloat,
        max maxW: CGFloat,
        inverted: Bool = false
    ) -> some View {
        DragDivider(
            width: width,
            defaultWidth: defaultWidth,
            minWidth: minW,
            maxWidth: maxW,
            inverted: inverted
        )
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
              let placement = PlacementSpec(string: position) else { return }
        DispatchQueue.main.async {
            WindowTiler.focusWindow(wid: wid, pid: entry.pid)
            WindowTiler.tileWindowById(wid: wid, pid: entry.pid, to: placement)
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
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(Typo.geistMono(9))
                .foregroundColor(Palette.textMuted)
                .frame(width: 14, alignment: .leading)
            Text(item.app)
                .font(Typo.geistMonoBold(10))
                .foregroundColor(Palette.textDim)
                .frame(minWidth: 60, alignment: .leading)
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
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
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

// MARK: - Drag Divider (NSView-backed to prevent window drag)

struct DragDivider: NSViewRepresentable {
    @Binding var width: CGFloat?
    let defaultWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    var inverted: Bool = false

    func makeNSView(context: Context) -> DragDividerNSView {
        let view = DragDividerNSView()
        view.onDrag = { delta in
            let current = width ?? defaultWidth
            let d = inverted ? -delta : delta
            width = Swift.max(minWidth, Swift.min(maxWidth, current + d))
        }
        return view
    }

    func updateNSView(_ nsView: DragDividerNSView, context: Context) {
        nsView.onDrag = { delta in
            let current = width ?? defaultWidth
            let d = inverted ? -delta : delta
            width = Swift.max(minWidth, Swift.min(maxWidth, current + d))
        }
    }
}

final class DragDividerNSView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private var lastX: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        NSSize(width: 1, height: NSView.noIntrinsicMetric)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let area = NSTrackingArea(
            rect: bounds.insetBy(dx: -3, dy: 0),
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        let lineX = bounds.midX
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSRect(x: lineX - 0.25, y: 0, width: 0.5, height: bounds.height).fill()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.push()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }

    override func mouseDown(with event: NSEvent) {
        lastX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        let x = event.locationInWindow.x
        let delta = x - lastX
        lastX = x
        onDrag?(delta)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Expand hit area to 7pt wide
        let expanded = frame.insetBy(dx: -3, dy: 0)
        return expanded.contains(point) ? self : nil
    }
}
