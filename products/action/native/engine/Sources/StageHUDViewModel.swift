import Foundation

@MainActor
final class StageHUDViewModel: ObservableObject {
    enum ButtonTone {
        case primary
        case secondary
        case destructive
    }

    struct ButtonModel: Identifiable {
        let id: String
        let title: String
        let enabled: Bool
        let tone: ButtonTone
        let hint: String
    }

    @Published var phase: String = "staging"
    @Published var targetApp: String = "Action"
    @Published var summary: String = "Guided capture session"
    @Published var detail: String?
    @Published var stepLabel: String?
    @Published var countdownRemaining: Int?
    @Published var recentLogs: [String] = []
    @Published var elapsedMs: Double?

    var onCommand: ((String) -> Void)?

    var phaseLabel: String {
        phase.replacingOccurrences(of: "-", with: " ").uppercased()
    }

    var phaseAccent: StageHUDThemePhaseAccent {
        switch phase {
        case "recording", "acting":
            return .recording
        case "paused":
            return .paused
        default:
            return .neutral
        }
    }

    var detailText: String {
        if let stepLabel, !stepLabel.isEmpty {
            return stepLabel
        }
        if let detail, !detail.isEmpty {
            return detail
        }
        return "Guided capture session"
    }

    var elapsedText: String? {
        guard let elapsedMs else {
            return nil
        }
        let totalSeconds = Int(max(0, elapsedMs) / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var countdownText: String? {
        guard phase == "countdown", let countdownRemaining else {
            return nil
        }

        return "\(countdownRemaining)"
    }

    var captureStatusTitle: String {
        switch phase {
        case "observing":
            return "Live Surface"
        case "analyzing":
            return "Reflecting"
        case "awaiting-decision":
            return "Decision Gate"
        case "acting":
            return "Applying Action"
        case "countdown":
            return countdownText.map { "T-\($0)" } ?? "Count In"
        case "recording":
            return "Live Capture"
        case "completing":
            return "Finalizing"
        case "completed":
            return "Take Saved"
        case "cancelled":
            return "Take Cancelled"
        case "failed":
            return "Capture Failed"
        default:
            return "Recorder Ready"
        }
    }

    var captureStatusDetail: String {
        switch phase {
        case "observing":
            return "The runtime is staged on a live surface and ready to inspect or act."
        case "analyzing":
            return "Reflection is in progress. Keep stop available so inspection never becomes a dead end."
        case "awaiting-decision":
            return "Findings are ready. Choose whether to act, record, or dismiss the session."
        case "acting":
            return "The runtime is applying a follow-up action from the current inspection context."
        case "countdown":
            return "Start now to skip the countdown, or cancel before capture begins."
        case "recording":
            return "Interrupt ends the take immediately so you can reset and try again."
        case "completing":
            return "Writing the movie and marker files."
        case "completed":
            return "Replay the last run or dismiss the panel."
        case "cancelled":
            return "The take ended before a completed session was saved."
        case "failed":
            return "Inspect the recent events for the native failure."
        default:
            return "Stage the app, then arm the capture."
        }
    }

    var stepProgressText: String? {
        guard let detail, !detail.isEmpty else {
            return nil
        }

        return detail
    }

    var buttons: [ButtonModel] {
        [
            ButtonModel(id: "start", title: startButtonTitle, enabled: isEnabled("start"), tone: .primary, hint: startButtonHint),
            ButtonModel(id: "stop", title: stopButtonTitle, enabled: isEnabled("stop"), tone: .destructive, hint: stopButtonHint),
            ButtonModel(id: "replay", title: "Replay Take", enabled: isEnabled("replay"), tone: .secondary, hint: "Replay the saved capture."),
            ButtonModel(id: "clear", title: clearButtonTitle, enabled: isEnabled("clear"), tone: .secondary, hint: clearButtonHint),
            ButtonModel(id: "quit", title: "Quit", enabled: isEnabled("quit"), tone: .secondary, hint: "Close Action and leave the current app untouched."),
        ]
    }

    func send(_ id: String) {
        guard isEnabled(id) else {
            return
        }
        onCommand?(id)
    }

    private func isEnabled(_ id: String) -> Bool {
        switch id {
        case "start":
            return phase == "staging"
                || phase == "observing"
                || phase == "awaiting-decision"
                || phase == "completed"
                || phase == "failed"
                || phase == "paused"
                || phase == "created"
                || phase == "countdown"
        case "stop":
            return phase == "countdown"
                || phase == "observing"
                || phase == "analyzing"
                || phase == "awaiting-decision"
                || phase == "acting"
                || phase == "recording"
                || phase == "paused"
        case "replay":
            return phase == "completed"
        case "clear", "quit":
            return true
        default:
            return false
        }
    }

    private var startButtonTitle: String {
        switch phase {
        case "observing":
            return "Inspect"
        case "awaiting-decision":
            return "Apply"
        case "countdown":
            return "Start Now"
        case "paused":
            return "Resume"
        case "failed":
            return "Try Again"
        case "cancelled":
            return "New Take"
        default:
            return "Start"
        }
    }

    private var stopButtonTitle: String {
        switch phase {
        case "observing", "analyzing", "awaiting-decision":
            return "Cancel"
        case "acting":
            return "Interrupt"
        case "countdown":
            return "Cancel"
        case "paused", "recording":
            return "End Take"
        default:
            return "Stop"
        }
    }

    private var clearButtonTitle: String {
        switch phase {
        case "completed", "failed", "cancelled":
            return "Dismiss"
        default:
            return "Clear"
        }
    }

    private var startButtonHint: String {
        switch phase {
        case "observing":
            return "Inspect the current surface before acting."
        case "awaiting-decision":
            return "Apply the prepared action."
        case "countdown":
            return "Skip the remaining countdown and begin capture."
        case "paused":
            return "Resume the paused capture."
        case "failed":
            return "Start a fresh attempt after the failed run."
        case "cancelled":
            return "Create a new take."
        default:
            return "Begin the staged run."
        }
    }

    private var stopButtonHint: String {
        switch phase {
        case "recording", "paused":
            return "Stop capture cleanly and package the take."
        case "acting":
            return "Interrupt the current action and stop the run."
        case "countdown":
            return "Cancel before capture begins."
        default:
            return "Cancel the current operation."
        }
    }

    private var clearButtonHint: String {
        switch phase {
        case "completed", "failed", "cancelled":
            return "Dismiss this session from the HUD."
        default:
            return "Clear the staged session."
        }
    }
}

enum StageHUDThemePhaseAccent {
    case neutral
    case paused
    case recording
}
