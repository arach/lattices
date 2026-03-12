import AppKit
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
            // Auto-start listening on re-show
            s.armed = true
            if s.phase == .idle || s.phase == .result {
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

    // History — all transcripts this session
    @Published var history: [TranscriptEntry] = []

    // Diagnostic log
    @Published var logLines: [String] = []

    private var logSnapshot = 0

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
        partialText = ""
        finalText = ""
        intentName = nil
        intentSlots = [:]
        executionResult = nil
        resultItems = []
        resultSummary = ""
        logSnapshot = DiagnosticLog.shared.entries.count
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

    private func appendLog(_ msg: String) {
        logLines.append(msg)
    }

    private func syncLogs() {
        let entries = DiagnosticLog.shared.entries
        if entries.count > logSnapshot {
            logLines = entries.suffix(from: min(logSnapshot, entries.count)).map { $0.message }
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
            resultItems: resultItems
        )
        history.append(entry)
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

            commitToHistory()
            self.phase = .result
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { poll() }
    }
}

// MARK: - View

struct VoiceCommandView: View {
    @ObservedObject var state: VoiceCommandState
    let onDismiss: () -> Void

    private let docsURL = "https://lattices.dev/docs/voice"

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            titleBar

            Rectangle().fill(Palette.border).frame(height: 0.5)

            // Main 3-pane layout
            HStack(spacing: 0) {
                // Left: transcript history
                transcriptHistory
                    .frame(minWidth: 200, idealWidth: 260)

                Rectangle().fill(Palette.border).frame(width: 0.5)

                // Right: current command + results
                VStack(spacing: 0) {
                    currentCommand
                    Spacer(minLength: 0)
                    Rectangle().fill(Palette.border).frame(height: 0.5)
                    diagnosticLog
                }
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

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            // Mic status indicator
            micDot

            Text("Voice")
                .font(Typo.geistMonoBold(12))
                .foregroundColor(Palette.text)

            statusLabel

            // Armed badge — clickable to toggle
            Button(action: { state.toggleArmed() }) {
                Text(state.armed ? "ON" : "OFF")
                    .font(Typo.geistMonoBold(8))
                    .tracking(0.5)
                    .foregroundColor(state.armed ? Palette.running : Palette.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(state.armed ? Palette.running.opacity(0.12) : Palette.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(state.armed ? Palette.running.opacity(0.3) : Palette.border, lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            connectionDot

            if let url = URL(string: docsURL) {
                Link(destination: url) {
                    Text("docs")
                        .font(Typo.geistMono(10))
                        .foregroundColor(Palette.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(Palette.border, lineWidth: 0.5)
                                )
                        )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var micDot: some View {
        Circle()
            .fill(micDotColor)
            .frame(width: 8, height: 8)
            .overlay(
                state.phase == .listening
                    ? Circle().stroke(Palette.running.opacity(0.4), lineWidth: 1.5)
                        .scaleEffect(1.8)
                        .opacity(0.6)
                    : nil
            )
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: state.phase)
    }

    private var micDotColor: Color {
        switch state.phase {
        case .listening: return Palette.running
        case .transcribing: return Palette.detach
        case .connecting: return Palette.detach
        default: return Palette.textMuted
        }
    }

    private var statusLabel: some View {
        Group {
            switch state.phase {
            case .idle:
                Text("ready")
                    .foregroundColor(Palette.textMuted)
            case .connecting:
                Text("connecting...")
                    .foregroundColor(Palette.detach)
            case .listening:
                Text("listening")
                    .foregroundColor(Palette.running)
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
                    .foregroundColor(Palette.running)
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
                Text("\(state.history.count)")
                    .font(Typo.geistMono(9))
                    .foregroundColor(Palette.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            if state.history.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(Palette.textMuted.opacity(0.5))
                    Text("Transcripts appear here")
                        .font(Typo.geistMono(11))
                        .foregroundColor(Palette.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
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

            // Result summary
            if !entry.resultItems.isEmpty {
                Text("\(entry.resultItems.count) match\(entry.resultItems.count == 1 ? "" : "es")")
                    .font(Typo.geistMono(9))
                    .foregroundColor(Palette.textDim)
            } else if let result = entry.result, result != "ok" {
                Text(result)
                    .font(Typo.geistMono(9))
                    .foregroundColor(Palette.detach)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Current Command (right pane, top)

    private var currentCommand: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CURRENT")
                    .font(Typo.geistMonoBold(9))
                    .foregroundColor(Palette.textMuted)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // What was heard
                    if !state.finalText.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("heard")
                                .font(Typo.geistMono(9))
                                .foregroundColor(Palette.textMuted)
                            Text(state.finalText)
                                .font(Typo.geistMono(13))
                                .foregroundColor(Palette.text)
                                .textSelection(.enabled)
                        }
                    } else if state.phase == .listening, !state.partialText.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("hearing...")
                                .font(Typo.geistMono(9))
                                .foregroundColor(Palette.textMuted)
                            Text(state.partialText)
                                .font(Typo.geistMono(13))
                                .foregroundColor(Palette.textDim)
                        }
                    } else if state.phase == .idle || state.phase == .listening {
                        VStack(spacing: 12) {
                            Image(systemName: "mic")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(state.phase == .listening ? Palette.running : Palette.textMuted.opacity(0.4))
                            Text(state.phase == .listening ? "Listening..." : "Press Space to speak")
                                .font(Typo.geistMono(12))
                                .foregroundColor(state.phase == .listening ? Palette.running : Palette.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                    }

                    // Matched intent + slots
                    if let intent = state.intentName {
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

                    // Results
                    if !state.resultItems.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(state.resultItems.count) match\(state.resultItems.count == 1 ? "" : "es")")
                                .font(Typo.geistMono(9))
                                .foregroundColor(Palette.textMuted)
                                .padding(.bottom, 2)

                            ForEach(Array(state.resultItems.prefix(25).enumerated()), id: \.1.id) { idx, item in
                                ResultRow(index: idx, item: item, onFocus: focusWindow, onTile: tileWindow)
                            }
                            if state.resultItems.count > 25 {
                                Text("+ \(state.resultItems.count - 25) more")
                                    .font(Typo.geistMono(9))
                                    .foregroundColor(Palette.textMuted)
                                    .padding(.leading, 108)
                            }
                        }
                    } else if !state.resultSummary.isEmpty {
                        Text(state.resultSummary)
                            .font(Typo.geistMono(11))
                            .foregroundColor(Palette.text)
                    } else if state.executionResult == "ok" {
                        Text("done")
                            .font(Typo.geistMono(11))
                            .foregroundColor(Palette.running)
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: - Diagnostic Log (right pane, bottom)

    private var diagnosticLog: some View {
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .onChange(of: state.logLines.count) { _ in
                    let last = state.logLines.count - 1
                    if last >= 0 {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .frame(height: 100)
            .background(Palette.bg.opacity(0.3))
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 16) {
            if state.phase == .listening {
                footerHint("Space", "Stop")
                footerHint("ESC", "Cancel")
            } else {
                footerHint("Space", "Speak")
                footerHint("Tab", state.armed ? "Off" : "On")
                footerHint("ESC", "Dismiss")
            }

            Spacer()

            Text("find · show · open · tile · kill · scan")
                .font(Typo.geistMono(9))
                .foregroundColor(Palette.textMuted.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(Typo.geistMonoBold(9))
                .foregroundColor(Palette.text)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                )
            Text(label)
                .font(Typo.caption(9))
                .foregroundColor(Palette.textMuted)
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

    private var connectionDot: some View {
        let client = TalkieClient.shared
        let color: Color = {
            switch client.connectionState {
            case .connected: return Palette.running
            case .connecting: return Palette.detach
            default: return Palette.kill
            }
        }()

        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }
}

// MARK: - Result Row (hover actions)

struct ResultRow: View {
    let index: Int
    let item: ResultItem
    let onFocus: (UInt32) -> Void
    let onTile: (UInt32, String) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(Typo.geistMono(9))
                .foregroundColor(Palette.textMuted)
                .frame(width: 18, alignment: .trailing)
            Text(item.app)
                .font(Typo.geistMonoBold(10))
                .foregroundColor(Palette.textDim)
                .frame(width: 70, alignment: .trailing)
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

