import AppKit
import SwiftUI

// MARK: - Window Controller

final class VoiceCommandWindow {
    static let shared = VoiceCommandWindow()

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var state: VoiceCommandState?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        if let p = panel, p.isVisible {
            // Already showing — toggle listening
            state?.toggleListening()
            return
        }

        let voiceState = VoiceCommandState()
        state = voiceState

        let view = VoiceCommandView(state: voiceState) { [weak self] in
            self?.dismiss()
        }
        .preferredColorScheme(.dark)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
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
        p.isMovableByWindowBackground = false
        p.contentView = NSHostingView(rootView: view)

        // Position: bottom-center of screen, above the dock
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let x = visible.midX - 180
        let y = visible.origin.y + 80
        p.setFrameOrigin(NSPoint(x: x, y: y))

        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1.0
        }

        self.panel = p

        // Pre-connect to Talkie so Space → listen is instant
        let client = TalkieClient.shared
        if client.connectionState != .connected {
            client.connect()
        }

        installMonitors()
    }

    func dismiss() {
        guard let p = panel else { return }
        removeMonitors()

        // Cancel any in-flight dictation
        if let s = state, s.phase == .listening {
            AudioLayer.shared.stopVoiceCommand()
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 0
        }) { [weak self] in
            p.orderOut(nil)
            self?.panel = nil
            self?.state = nil
        }
    }

    private func installMonitors() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let state = self.state else { return }

            switch event.keyCode {
            case 53: // Escape
                if state.phase == .listening {
                    state.cancelListening()
                } else {
                    self.dismiss()
                }

            case 49: // Space — toggle listening
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

// MARK: - State

final class VoiceCommandState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case connecting
        case listening
        case transcribing
        case result
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var partialText: String = ""
    @Published var finalText: String = ""
    @Published var intentName: String?
    @Published var intentSlots: [String: String] = [:]
    @Published var executionResult: String?
    @Published var resultItems: [(app: String, title: String)] = []
    @Published var resultSummary: String = ""
    @Published var logLines: [String] = []

    private var audioObserver: NSKeyValueObservation?

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
        } else if attempts < 20 { // 2 seconds max (20 × 100ms)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.waitForConnection(attempts: attempts + 1)
            }
        } else {
            phase = .error("Couldn't connect to Talkie")
        }
    }

    private var logSnapshot = 0

    private func beginListening() {
        phase = .listening
        partialText = ""
        finalText = ""
        intentName = nil
        intentSlots = [:]
        executionResult = nil
        resultItems = []
        logLines = []
        logSnapshot = DiagnosticLog.shared.entries.count
        AudioLayer.shared.startVoiceCommand()
    }

    func stopListening() {
        phase = .transcribing
        AudioLayer.shared.stopVoiceCommand()

        // Watch AudioLayer for result
        observeResult()
    }

    func cancelListening() {
        phase = .idle
        AudioLayer.shared.stopVoiceCommand()
    }

    func toggleListening() {
        switch phase {
        case .listening:
            stopListening()
        case .idle, .result, .error:
            startListening()
        default:
            break
        }
    }

    private func observeResult() {
        let audio = AudioLayer.shared
        var checks = 0
        let maxChecks = 150  // 30 seconds max (150 × 0.2s)

        func poll() {
            checks += 1

            // 1. Always sync transcript from AudioLayer
            if let transcript = audio.lastTranscript, !transcript.isEmpty {
                self.finalText = transcript
            }

            // 2. Always sync log entries
            let entries = DiagnosticLog.shared.entries
            if entries.count > self.logSnapshot {
                self.logLines = entries.suffix(from: min(self.logSnapshot, entries.count)).map { $0.message }
            }

            // 3. Always sync intent/slots
            self.intentName = audio.matchedIntent
            self.intentSlots = audio.matchedSlots

            let result = audio.executionResult

            // 4. Terminal error states — stop polling
            if result == "No speech detected" || result == "Transcription failed" {
                self.phase = .error(result!)
                return
            }
            if let result, result.hasPrefix("Mic in use") {
                self.phase = .error(result)
                return
            }

            // 5. Still waiting for transcription/processing — keep polling
            let stillWorking = result == nil
                || result == "Transcribing..."
                || result == "thinking..."
                || result == "searching..."

            if stillWorking {
                // Show intermediate status
                if let result {
                    self.executionResult = result
                }
                self.phase = .transcribing
                if checks < maxChecks {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() }
                } else {
                    self.phase = .error("Timed out")
                }
                return
            }

            // 6. We have a real result — but do we have a transcript?
            //    If not, keep polling briefly (transcript might arrive next tick)
            if self.finalText.isEmpty && checks < 25 {
                // 5 seconds grace period for transcript to arrive
                self.phase = .transcribing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() }
                return
            }

            // 7. Final result — show it
            self.executionResult = result
            if let data = audio.executionData {
                switch data {
                case .array(let items):
                    self.resultItems = items.compactMap { item in
                        guard let app = item["app"]?.stringValue,
                              let title = item["title"]?.stringValue else { return nil }
                        return (app: app, title: title)
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

            self.phase = .result
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { poll() }
    }
}

// MARK: - View

struct VoiceCommandView: View {
    @ObservedObject var state: VoiceCommandState
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            VStack(spacing: 12) {
                micIcon
                statusText
                transcriptArea
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            // Live log
            if !state.logLines.isEmpty {
                Rectangle().fill(Palette.border).frame(height: 0.5)
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(state.logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Palette.textMuted)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 120)
            }

            // Footer
            Rectangle().fill(Palette.border).frame(height: 0.5)
            footerBar
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Mic Icon

    private var micIcon: some View {
        ZStack {
            // Pulsing ring when listening
            if state.phase == .listening {
                Circle()
                    .stroke(Palette.running.opacity(0.3), lineWidth: 2)
                    .frame(width: 52, height: 52)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: state.phase)
            }

            Circle()
                .fill(micBackground)
                .frame(width: 44, height: 44)

            Image(systemName: micIconName)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(micIconColor)
        }
    }

    private var pulseScale: CGFloat { state.phase == .listening ? 1.3 : 1.0 }
    private var pulseOpacity: Double { state.phase == .listening ? 0.0 : 0.5 }

    private var micIconName: String {
        switch state.phase {
        case .listening: return "mic.fill"
        case .transcribing: return "waveform"
        case .result: return "checkmark"
        case .error: return "exclamationmark.triangle"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .idle: return "mic"
        }
    }

    private var micIconColor: Color {
        switch state.phase {
        case .listening: return .white
        case .result: return Palette.running
        case .error: return Palette.kill
        default: return Palette.text
        }
    }

    private var micBackground: Color {
        switch state.phase {
        case .listening: return Palette.running.opacity(0.8)
        case .error: return Palette.kill.opacity(0.15)
        default: return Palette.surface
        }
    }

    // MARK: - Status Text

    private var statusText: some View {
        Group {
            switch state.phase {
            case .idle:
                Text("Press Space to speak")
                    .font(Typo.geistMono(13))
                    .foregroundColor(Palette.textDim)

            case .connecting:
                Text("Connecting to Talkie...")
                    .font(Typo.geistMono(13))
                    .foregroundColor(Palette.detach)

            case .listening:
                Text("Listening...")
                    .font(Typo.geistMono(13))
                    .foregroundColor(Palette.running)

            case .transcribing:
                if let r = state.executionResult, r == "thinking..." || r == "searching..." {
                    Text(r)
                        .font(Typo.geistMono(13))
                        .foregroundColor(Palette.detach)
                } else {
                    Text("Processing...")
                        .font(Typo.geistMono(13))
                        .foregroundColor(Palette.textDim)
                }

            case .result:
                EmptyView()

            case .error(let msg):
                Text(msg)
                    .font(Typo.geistMono(12))
                    .foregroundColor(Palette.kill)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Transcript Area

    private var transcriptArea: some View {
        Group {
            if state.phase == .result {
                VStack(alignment: .leading, spacing: 6) {
                    // Row 1: Transcript
                    resultRow(label: "heard", value: state.finalText, color: Palette.text)

                    // Row 2: Matched intent
                    if let intent = state.intentName {
                        resultRow(label: "intent", value: intent, color: Palette.running)
                    }

                    // Row 3: Extracted slots
                    if !state.intentSlots.isEmpty {
                        let slotText = state.intentSlots
                            .map { "\($0.key) = \($0.value)" }
                            .joined(separator: "  ")
                        resultRow(label: "params", value: slotText, color: Palette.detach)
                    }

                    // Row 4: Execution result
                    if let result = state.executionResult {
                        if !state.resultItems.isEmpty {
                            resultRow(label: "result", value: "\(state.resultItems.count) match\(state.resultItems.count == 1 ? "" : "es")", color: Palette.running)

                            // Window list
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(state.resultItems.prefix(6).enumerated()), id: \.offset) { _, item in
                                    HStack(spacing: 6) {
                                        Text(item.app)
                                            .font(Typo.geistMonoBold(10))
                                            .foregroundColor(Palette.textDim)
                                            .frame(width: 80, alignment: .trailing)
                                        Text(item.title.isEmpty ? "(untitled)" : item.title)
                                            .font(Typo.geistMono(10))
                                            .foregroundColor(Palette.text)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                                if state.resultItems.count > 6 {
                                    Text("+ \(state.resultItems.count - 6) more")
                                        .font(Typo.caption(9))
                                        .foregroundColor(Palette.textMuted)
                                        .padding(.leading, 86)
                                }
                            }
                            .padding(.top, 2)
                        } else if !state.resultSummary.isEmpty {
                            resultRow(label: "result", value: state.resultSummary, color: Palette.running)
                        } else if result == "ok" {
                            resultRow(label: "result", value: "done", color: Palette.running)
                        } else {
                            // Error — show once as error, not as both "result" and "error"
                            resultRow(label: "error", value: result, color: Palette.kill)
                        }
                    }
                }
            } else if state.phase == .transcribing, !state.finalText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    resultRow(label: "heard", value: state.finalText, color: Palette.text)
                    if let intent = state.intentName {
                        resultRow(label: "intent", value: intent, color: Palette.running)
                    }
                }
            } else if state.phase == .listening, !state.partialText.isEmpty {
                HStack {
                    Text(state.partialText)
                        .font(Typo.geistMono(12))
                        .foregroundColor(Palette.textDim)
                        .lineLimit(2)
                    Spacer()
                }
            }
        }
    }

    private func resultRow(label: String, value: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(Typo.geistMono(10))
                .foregroundColor(Palette.textMuted)
                .frame(width: 46, alignment: .trailing)
            Text(value)
                .font(Typo.geistMono(11))
                .foregroundColor(color)
                .lineLimit(2)
            Spacer()
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 16) {
            Spacer()

            if state.phase == .listening {
                footerHint("Space", "Stop")
                footerHint("ESC", "Cancel")
            } else if state.phase == .result {
                footerHint("Space", "Again")
                footerHint("ESC", "Dismiss")
            } else if case .error = state.phase {
                footerHint("Space", "Retry")
                footerHint("ESC", "Dismiss")
            } else {
                footerHint("Space", "Speak")
                footerHint("ESC", "Dismiss")
            }

            // Connection indicator
            connectionDot

            Spacer()
        }
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
