import AppKit
import Combine
import HudsonObservability
import HudsonUI
import SwiftUI

// MARK: - Log Store (HudLogStore facade)

final class DiagnosticLog: ObservableObject {
    static let shared = DiagnosticLog()

    struct Entry: Identifiable {
        let id: UUID
        let time: Date
        let message: String
        let level: Level

        enum Level: String { case info, success, warning, error }

        var icon: String {
            switch level {
            case .info:    return "›"
            case .success: return "✓"
            case .warning: return "⚠"
            case .error:   return "✗"
            }
        }

        init(hud: HudLogEntry) {
            id = hud.id
            time = hud.timestamp
            message = hud.message
            level = Level(hud: hud)
        }
    }

    @Published private(set) var entries: [Entry] = []

    private let store = HudLogStore.shared
    private let logger = HudLogger(subsystem: "dev.lattices.app", category: "diagnostic")
    private var cancellables = Set<AnyCancellable>()

    private init() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.store.$entries
                .receive(on: DispatchQueue.main)
                .map { $0.map(Entry.init(hud:)) }
                .sink { [weak self] mapped in
                    self?.entries = mapped
                }
                .store(in: &self.cancellables)
        }
    }

    func log(_ message: String, level: Entry.Level = .info) {
        logger.log(level.hudLevel, message, metadata: level.hudMetadata)
    }

    func info(_ msg: String)    { log(msg, level: .info) }
    func success(_ msg: String) { log(msg, level: .success) }
    func warn(_ msg: String)    { log(msg, level: .warning) }
    func error(_ msg: String)   { log(msg, level: .error) }
    func clear() {
        Task { @MainActor in
            store.clear()
        }
    }

    // MARK: - Per-Action Timing

    struct TimedAction {
        let label: String
        let start: Date
    }

    func startTimed(_ label: String) -> TimedAction {
        info("▸ \(label)")
        return TimedAction(label: label, start: Date())
    }

    func finish(_ action: TimedAction) {
        let ms = Date().timeIntervalSince(action.start) * 1000
        success("▸ \(action.label) — \(String(format: "%.0f", ms))ms")
    }

    func fail(_ action: TimedAction, message: String? = nil) {
        let ms = Date().timeIntervalSince(action.start) * 1000
        let detail = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suffix = detail.isEmpty ? "" : "\n\(detail)"
        error("▸ \(action.label) failed — \(String(format: "%.0f", ms))ms\(suffix)")
    }
}

private extension DiagnosticLog.Entry.Level {
    init(hud: HudLogEntry) {
        if hud.metadata["outcome"] == "success" {
            self = .success
            return
        }
        switch hud.level {
        case .warning:
            self = .warning
        case .error, .fault:
            self = .error
        default:
            self = .info
        }
    }

    var hudLevel: HudLogLevel {
        switch self {
        case .info: return .info
        case .success: return .notice
        case .warning: return .warning
        case .error: return .error
        }
    }

    var hudMetadata: [String: String] {
        switch self {
        case .success: return ["outcome": "success"]
        default: return [:]
        }
    }
}

// MARK: - Interaction Feedback

final class AppFeedback {
    static let shared = AppFeedback()

    private lazy var tapSound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "tap", withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }()
    private var didWarmTapSound = false

    private init() {}

    @discardableResult
    func beginTimed(_ label: String, state: HUDState? = nil, feedback: String? = nil, playSound: Bool = true) -> DiagnosticLog.TimedAction {
        if playSound {
            playTap()
        }
        if let feedback, let state {
            state.showFeedback(feedback)
        }
        return DiagnosticLog.shared.startTimed(label)
    }

    func finish(_ action: DiagnosticLog.TimedAction, state: HUDState? = nil, feedback: String? = nil) {
        if let feedback, let state {
            state.showFeedback(feedback)
        }
        DiagnosticLog.shared.finish(action)
    }

    func acknowledge(_ label: String, state: HUDState? = nil, feedback: String? = nil, playSound: Bool = true) {
        if playSound {
            playTap()
        }
        if let feedback, let state {
            state.showFeedback(feedback)
        }
        DiagnosticLog.shared.info(label)
    }

    func playTapSound() {
        playTap()
    }

    func warmUp() {
        runOnMain { self.warmUpTapSoundOnMain() }
    }

    func warmUpTapSound() {
        warmUp()
    }

    func commitTactile() {
        runOnMain {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            self.playPreparedTapOnMain()
        }
    }

    private func playTap() {
        DispatchQueue.main.async {
            self.tapSound?.stop()
            self.tapSound?.play()
        }
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func warmUpTapSoundOnMain() {
        guard !didWarmTapSound, let sound = tapSound else { return }
        didWarmTapSound = true
        let volume = sound.volume
        sound.volume = 0
        sound.currentTime = 0
        sound.play()
        sound.stop()
        sound.currentTime = 0
        sound.volume = volume
    }

    private func playPreparedTapOnMain() {
        guard let sound = tapSound else { return }
        sound.currentTime = 0
        sound.play()
    }
}

// MARK: - Diagnostic Window

final class DiagnosticWindow {
    static let shared = DiagnosticWindow()

    private var window: NSWindow?
    private var keyMonitor: Any?

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        if let w = window, w.isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func dismiss() {
        window?.orderOut(nil)
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        AppDelegate.updateActivationPolicy()
    }

    func show() {
        if let w = window {
            AppWindowShell.present(w)
            return
        }

        let view = DiagnosticWindowRootView(onClose: { [weak self] in
            self?.dismiss()
        })

        let screen = NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = max(600, floor(screenFrame.height * 0.55))

        let w = AppWindowShell.makeWindow(
            config: .init(
                title: "Lattices Activity Log",
                initialSize: NSSize(width: panelWidth, height: panelHeight),
                minSize: NSSize(width: 420, height: 360)
            ),
            rootView: view
        )

        let x = screenFrame.maxX - panelWidth - 12
        let y = screenFrame.minY + floor((screenFrame.height - panelHeight) / 2)
        w.setFrameOrigin(NSPoint(x: x, y: y))

        AppWindowShell.present(w)
        window = w

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53,
                  let win = self?.window,
                  event.window === win || win.isKeyWindow else { return event }
            self?.dismiss()
            return nil
        }

        let diag = DiagnosticLog.shared
        diag.info("Activity Log opened")
        diag.info("Terminal: \(Preferences.shared.terminal.rawValue) (\(Preferences.shared.terminal.bundleId))")
        diag.info("Installed: \(Terminal.installed.map(\.rawValue).joined(separator: ", "))")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: TmuxQuery.resolvedPath ?? "/opt/homebrew/bin/tmux")
        task.arguments = ["list-sessions", "-F", "#{session_name}"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        let sessions = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "none"
        diag.info("tmux sessions: \(sessions)")
    }
}

private struct DiagnosticWindowRootView: View {
    let onClose: () -> Void

    var body: some View {
        HudLoggerPanel(title: "Activity Log", onClose: onClose)
    }
}

// MARK: - SwiftUI Overlay

struct ActivityPageView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.textMuted)

                Text("Activity")
                    .font(Typo.heading(13))
                    .foregroundColor(Palette.text)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            HudLoggerView(store: .shared, title: "Activity", showHeader: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelBackground())
        .onAppear {
            DiagnosticLog.shared.info("Activity page opened")
        }
    }
}