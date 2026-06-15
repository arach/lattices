import AppKit
import Combine
import SwiftUI

// Reusable voice building blocks — the state machine and the small SwiftUI
// pieces that render it. Relocated out of the retired `VoiceCommandWindow.swift`
// (the standalone 3-column voice window) so the unified command bar can compose
// `VoiceCommandState` and reuse `WaveBar` / `ListeningTimer` / `ResultRow`
// without dragging the old window/view chrome along. The deadlock-safe
// DiagnosticLog observer inside `VoiceCommandState` is preserved byte-for-byte.

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
    @Published var executionError: String?   // Non-nil when the last intent failed to run
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
        // Capture runs through AudioLayer (HudsonVoice opens its own session). Here we
        // only gate on the daemon being discoverable so the overlay can show a
        // "connecting" phase while voxd spins up.
        if VoxDaemon.isRunning {
            beginListening()
        } else {
            phase = .connecting
            waitForDaemon(attempts: 0)
        }
    }

    private func waitForDaemon(attempts: Int) {
        if VoxDaemon.isRunning {
            beginListening()
        } else if attempts < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.waitForDaemon(attempts: attempts + 1)
            }
        } else {
            appendLog("Vox daemon not running")
            executionResult = "Vox daemon not running — open Vox and try again."
            resultSummary = executionResult ?? ""
            syncLogs()
            phase = .result
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
        executionError = nil
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
                guard !newLines.isEmpty, newLines != self.logLines else { return }
                // Defer the @Published mutation to a fresh run-loop turn. Writing it
                // synchronously here re-enters VoiceCommandState.objectWillChange while
                // DiagnosticLog's publish is still holding its os_unfair_lock, which
                // deadlocks the main thread (the lock is non-recursive).
                DispatchQueue.main.async {
                    guard newLines != self.logLines else { return }
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

            // Mirror any execution failure so the UI can flag it
            self.executionError = audio.executionError
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
                self.executionResult = result
                self.resultSummary = "No speech detected — try again."
                syncLogs()
                self.phase = .result
                return
            }
            if result == "Transcription failed" {
                appendLog("Transcription failed")
                self.executionResult = result
                self.resultSummary = "Transcription failed — try again."
                syncLogs()
                self.phase = .result
                return
            }
            if let result, result.hasPrefix("Mic in use") {
                appendLog(result)
                self.executionResult = result
                self.resultSummary = result
                syncLogs()
                self.phase = .result
                return
            }

            // Still working
            let stillWorking = result == nil
                || result == "Transcribing..."
                || result == "thinking..."
                || result == "searching..."
                || result == "fixing..."

            if stillWorking {
                if let result { self.executionResult = result }
                self.phase = .transcribing
                if checks < maxChecks {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() }
                } else {
                    let timeout = "Timed out waiting for a voice result — no action outcome was reported. Try again."
                    appendLog(timeout)
                    self.executionResult = timeout
                    self.resultSummary = timeout
                    syncLogs()
                    commitToHistory()
                    self.phase = .result
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
                if let result, result != "ok" {
                    self.resultSummary = result
                } else {
                    self.resultSummary = ""
                }
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
