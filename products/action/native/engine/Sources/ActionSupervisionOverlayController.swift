import AppKit
import SwiftUI

// The panel window is grown by a transparent margin on every side so the card's
// soft drop shadow has room to render. The AppKit window shadow (which follows
// the rectangular window bounds, not the rounded card) stays off; this margin
// keeps the shape-aware SwiftUI shadow from being clipped to a hard rectangle.
private let actionSupervisionShadowMargin: CGFloat = 20

// The card sizes live here rather than at each use site because the SwiftUI frame and the
// panel window have to agree exactly: a window smaller than its card clips the card, and a
// larger one leaves dead transparent space that still swallows clicks.
// The expanded card is a fixed console: header chrome, a taller log well, and a
// footer of session actions. Growing with each note made the window jump.
private let actionSupervisionExpandedCard = CGSize(width: 340, height: 276)
private let actionSupervisionMinimizedCard = CGSize(width: 278, height: 50)
private let actionSupervisionNoteLimit = 6

@MainActor
final class ActionSupervisionViewModel: ObservableObject {
    @Published var title: String = "Action Supervision"
    @Published var detail: String = "Supervising active work"
    @Published var countLabel: String = "No active sessions"
    @Published var stopButtonTitle: String = "Stop"
    @Published var isStopPending: Bool = false
    @Published var isMinimized: Bool = false
    @Published var lines: [String] = []

    var onStop: (() -> Void)?
    var onToggleMinimized: (() -> Void)?
    var onClose: (() -> Void)?
}

struct ActionSupervisionView: View {
    @ObservedObject var model: ActionSupervisionViewModel

    var body: some View {
        Group {
            if model.isMinimized {
                minimizedBody
            } else {
                expandedBody
            }
        }
        .help("Action supervision. Drag to reposition or right-click for more options.")
        .contextMenu {
            Button(model.isMinimized ? "Show Details" : "Show Less") {
                model.onToggleMinimized?()
            }

            Button("Close HUD") {
                model.onClose?()
            }

            Divider()

            Button(model.stopButtonTitle, role: .destructive) {
                model.onStop?()
            }
            .disabled(model.isStopPending)
        }
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            expandedHeader
            expandedLog
            expandedFooter
        }
        .frame(
            width: actionSupervisionExpandedCard.width,
            height: actionSupervisionExpandedCard.height,
            alignment: .top
        )
        .background(ActionSupervisionGlass(cornerRadius: 14))
        .padding(actionSupervisionShadowMargin)
        .preferredColorScheme(.dark)
    }

    private var expandedHeader: some View {
        HStack(spacing: 9) {
            ActionBrandTile(size: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text("Action")
                    .font(ActionType.uiCaptionStrong)
                    .foregroundStyle(StageHUDTheme.hudPaper)

                Text(model.countLabel)
                    .font(ActionType.uiMicro)
                    .foregroundStyle(StageHUDTheme.hudMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                model.onToggleMinimized?()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(ActionSupervisionIconButtonStyle())
            .help("Show less")
            .accessibilityLabel("Show less supervision detail")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 42)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(StageHUDTheme.hudPaper.opacity(0.10))
                .frame(height: 1)
        }
    }

    private var expandedLog: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .font(ActionType.uiBodyStrong)
                    .foregroundStyle(StageHUDTheme.hudPaper.opacity(0.94))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(model.detail)
                    .font(ActionType.uiCaption)
                    .foregroundStyle(StageHUDTheme.hudMuted)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 4) {
                if model.lines.isEmpty {
                    Text("Waiting for the next beat.")
                        .font(ActionType.uiCaption)
                        .foregroundStyle(StageHUDTheme.hudPaper.opacity(0.38))
                } else {
                    ForEach(Array(model.lines.enumerated()), id: \.offset) { index, line in
                        let isLatest = index == model.lines.count - 1
                        Text(line)
                            .font(.system(
                                size: 11,
                                weight: isLatest ? .medium : .regular,
                                design: .default
                            ))
                            .foregroundStyle(
                                StageHUDTheme.hudPaper.opacity(isLatest ? 0.92 : 0.46)
                            )
                            .lineLimit(isLatest ? 2 : 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 13)
        .padding(.top, 10)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StageHUDTheme.hudRecess.opacity(0.48))
    }

    private var expandedFooter: some View {
        HStack(spacing: 8) {
            Button {
                model.onClose?()
            } label: {
                Text("Quit")
            }
            .buttonStyle(ActionSupervisionSecondaryButtonStyle())
            .help("Hide the supervision HUD. Active sessions keep running.")
            .accessibilityLabel("Hide the supervision HUD")

            Spacer(minLength: 8)

            Button {
                model.onStop?()
            } label: {
                ActionSupervisionStopLabel(title: model.stopButtonTitle)
            }
            .buttonStyle(ActionSupervisionButtonStyle())
            .disabled(model.isStopPending)
            .help(stopButtonHelp)
            .accessibilityLabel(stopButtonHelp)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(StageHUDTheme.hudPaper.opacity(0.10))
                .frame(height: 1)
        }
    }

    private var minimizedBody: some View {
        HStack(spacing: 8) {
            ActionBrandTile(size: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("Action")
                    .font(ActionType.uiMicro)
                    .foregroundStyle(StageHUDTheme.hudPaper)

                Text(model.countLabel)
                    .font(ActionType.uiCaption)
                    .foregroundStyle(StageHUDTheme.hudMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                model.onToggleMinimized?()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(ActionSupervisionIconButtonStyle())
            .help("Show details")
            .accessibilityLabel("Show supervision details")

            Button {
                model.onStop?()
            } label: {
                ActionSupervisionStopLabel(title: model.stopButtonTitle)
            }
            .buttonStyle(ActionSupervisionButtonStyle())
            .disabled(model.isStopPending)
            .help(stopButtonHelp)
            .accessibilityLabel(stopButtonHelp)
        }
        .padding(.horizontal, 10)
        .frame(
            width: actionSupervisionMinimizedCard.width,
            height: actionSupervisionMinimizedCard.height,
            alignment: .leading
        )
        .background(ActionSupervisionGlass(cornerRadius: 12))
        .padding(actionSupervisionShadowMargin)
        .preferredColorScheme(.dark)
    }

    private var stopButtonHelp: String {
        switch model.stopButtonTitle {
        case "Stop All":
            return "Stop all active Action sessions"
        case "Stopping…":
            return "Stop request in progress"
        default:
            return "Stop the active Action session"
        }
    }
}

private struct ActionSupervisionGlass: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(StageHUDTheme.hudCanvas.opacity(0.38))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(StageHUDTheme.hudPaper.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: StageHUDTheme.hudShadow.opacity(0.34), radius: 16, x: 0, y: 8)
    }
}

private struct ActionSupervisionStopLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "stop.fill")
                .font(ActionIcon.micro)
            Text(title.uppercased())
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct ActionSupervisionSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ActionType.uiMicro)
            .foregroundStyle(StageHUDTheme.hudPaper.opacity(configuration.isPressed ? 0.62 : 0.86))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? StageHUDTheme.hudPanel : StageHUDTheme.hudPanelRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(StageHUDTheme.hudStrokeStrong, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ActionSupervisionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(StageHUDTheme.hudInk.opacity(isEnabled ? 1 : 0.52))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(buttonColor(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func buttonColor(isPressed: Bool) -> Color {
        guard isEnabled else {
            return StageHUDTheme.hudCoral.opacity(0.42)
        }
        return isPressed ? StageHUDTheme.hudCoral.opacity(0.76) : StageHUDTheme.hudCoral
    }
}

struct ActionSupervisionIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ActionType.uiMicro)
            .foregroundStyle(StageHUDTheme.hudPaper.opacity(configuration.isPressed ? 0.66 : 0.82))
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(configuration.isPressed ? StageHUDTheme.hudPanel : StageHUDTheme.hudPanelRaised)
            )
            .overlay(
                Circle()
                    .stroke(StageHUDTheme.hudStrokeStrong, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

@MainActor
final class ActionSupervisionOverlayController: NSObject {
    private struct StopRequest {
        let registrationIDs: Set<String>
        let requestedAt: Date
    }

    private enum OverlayLayout {
        // Window sizes include the transparent shadow margin on every side; the
        // visible card is inset by `margin` and reads at its card size.
        static let margin = actionSupervisionShadowMargin
        static let expandedSize = CGSize(
            width: actionSupervisionExpandedCard.width + margin * 2,
            height: actionSupervisionExpandedCard.height + margin * 2
        )
        static let minimizedSize = CGSize(
            width: actionSupervisionMinimizedCard.width + margin * 2,
            height: actionSupervisionMinimizedCard.height + margin * 2
        )
        static let edgeInset: CGFloat = 16
        static let frameDefaultsKey = "Action.SupervisionOverlay.Frame"
        static let minimizedDefaultsKey = "Action.SupervisionOverlay.Minimized"
    }

    private let writer: ResponseWriter
    private let logger: DebugLogger
    private let model = ActionSupervisionViewModel()
    private var window: StageHUDPanel?
    private var pollTimer: Timer?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var windowMoveObserver: NSObjectProtocol?
    private var lastEscapeTimestamp: Date?
    private var hasPositionedWindow = false
    private var isWindowPresented = false
    private var isDismissed = false
    private var dismissedRegistrationIDs: Set<String> = []
    private var stopRequest: StopRequest?
    private var positioningFingerprint = ""

    init(replyFile: String?, debugLogPath: String?) {
        self.writer = ResponseWriter(replyFile: replyFile)
        self.logger = DebugLogger(path: debugLogPath)
    }

    func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        ActionSupervisionRegistry.recordOverlayPID(ProcessInfo.processInfo.processIdentifier)
        model.isMinimized = UserDefaults.standard.bool(forKey: OverlayLayout.minimizedDefaultsKey)
        model.onStop = { [weak self] in
            self?.triggerStopAll(reason: "button")
        }
        model.onToggleMinimized = { [weak self] in
            self?.toggleMinimized()
        }
        model.onClose = { [weak self] in
            self?.dismissOverlay(reason: "quit")
        }
        createWindow()
        startPolling()
        startKeyboardMonitoring()
        refresh()
        try writer.write(
            ActionHostResponse(
                status: "supervision-overlay-running",
                outputPath: nil,
                detail: String(ProcessInfo.processInfo.processIdentifier)
            )
        )
        app.run()
    }

    private func createWindow() {
        guard window == nil else {
            return
        }

        let size = currentWindowSize
        let window = StageHUDPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = actionHUDPanelLevel()
        window.isOpaque = false
        window.backgroundColor = .clear
        // The card draws its own shape-aware shadow. Leaving the AppKit window
        // shadow on would stack a hard rectangle behind the rounded silhouette.
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        window.isReleasedWhenClosed = false
        let rootView = NSHostingView(rootView: ActionSupervisionView(model: model))
        rootView.frame = CGRect(origin: .zero, size: size)
        rootView.autoresizingMask = [.width, .height]
        window.contentView = rootView
        self.window = window
        windowMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.persistWindowFrame()
            }
        }
        positionWindow(registrations: ActionSupervisionRegistry.activeRegistrations())
    }

    private func startPolling() {
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startKeyboardMonitoring() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    private func tick() {
        if FileManager.default.fileExists(atPath: ActionSupervisionRegistry.overlayStopSignalURL.path) {
            shutdown()
            return
        }

        refresh()
    }

    private func refresh() {
        let registrations = ActionSupervisionRegistry.activeRegistrations()
        guard !registrations.isEmpty else {
            shutdown()
            return
        }

        // Only publish when a value actually changes. The poll runs several
        // times a second; assigning unconditionally would fire objectWillChange
        // on every tick and churn the view — the source of the visible flicker.
        // Prefer the newest registration title so drive leases can show
        // `{agent} · {task}` instead of a fixed product label.
        let primary = registrations.last
        let title = primary?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle: String
        if let title, !title.isEmpty, title != "Action Supervision" {
            resolvedTitle = title
        } else {
            resolvedTitle = registrations.count == 1
                ? "Supervising one session"
                : "Supervising \(registrations.count) sessions"
        }
        let activeIDs = Set(registrations.map(\.id))
        let stopPresentation = stopPresentation(activeIDs: activeIDs)
        let detail = stopPresentation.detail
            ?? primary?.detail
            ?? "Use Stop to end the active session safely"
        let countLabel = registrations.count == 1
            ? "1 active session"
            : "\(registrations.count) active sessions"
        let stopButtonTitle = stopPresentation.isPending
            ? "Stopping…"
            : (registrations.count == 1 ? "Stop" : "Stop All")
        if model.title != resolvedTitle {
            model.title = resolvedTitle
        }
        if model.detail != detail {
            model.detail = detail
        }
        if model.countLabel != countLabel {
            model.countLabel = countLabel
        }
        if model.stopButtonTitle != stopButtonTitle {
            model.stopButtonTitle = stopButtonTitle
        }
        if model.isStopPending != stopPresentation.isPending {
            model.isStopPending = stopPresentation.isPending
        }
        let notes = ActionSupervisionRegistry.recentHudLines(limit: actionSupervisionNoteLimit)
        if model.lines != notes {
            model.lines = notes
        }
        let nextPositioningFingerprint = registrations
            .compactMap(\.avoidedDisplayID)
            .sorted()
            .map(String.init)
            .joined(separator: ",")
        if positioningFingerprint != nextPositioningFingerprint {
            positioningFingerprint = nextPositioningFingerprint
            hasPositionedWindow = false
        }
        if !hasPositionedWindow {
            positionWindow(registrations: registrations)
        }

        if isDismissed, !activeIDs.isSubset(of: dismissedRegistrationIDs) {
            isDismissed = false
            dismissedRegistrationIDs.removeAll()
        }

        let ownsVisibleControls = registrations.contains { $0.ownsVisibleControls == true }
        if ownsVisibleControls || isDismissed {
            if isWindowPresented {
                window?.orderOut(nil)
                isWindowPresented = false
            }
        } else if !isWindowPresented {
            window?.orderFrontRegardless()
            isWindowPresented = true
        }
    }

    private func positionWindow(registrations: [ActionSupervisionRegistration]) {
        guard let window else {
            return
        }

        let avoidedDisplayIDs = Set(registrations.compactMap(\.avoidedDisplayID))
        let availableScreens = NSScreen.screens.filter { screen in
            guard let displayID = displayID(for: screen) else {
                return true
            }
            return !avoidedDisplayIDs.contains(displayID)
        }
        let screen = availableScreens.first(where: { $0 == NSScreen.main })
            ?? availableScreens.first
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = currentWindowSize

        if let savedFrame = savedWindowFrame(size: size),
           visibleFrame.intersects(savedFrame.insetBy(dx: min(savedFrame.width - 24, 0), dy: min(savedFrame.height - 24, 0))) {
            window.setFrame(clamped(frame: savedFrame, to: visibleFrame), display: true)
            hasPositionedWindow = true
            return
        }

        // Offset by the transparent margin so the visible card — not the padded
        // window — sits `edgeInset` from the top-right corner.
        let cornerInset = OverlayLayout.edgeInset - OverlayLayout.margin
        let x = visibleFrame.maxX - size.width - cornerInset
        let y = visibleFrame.maxY - size.height - cornerInset
        window.setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: true)
        hasPositionedWindow = true
        persistWindowFrame()
    }

    private func displayID(for screen: NSScreen) -> UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    private var currentWindowSize: CGSize {
        model.isMinimized ? OverlayLayout.minimizedSize : OverlayLayout.expandedSize
    }

    private func toggleMinimized() {
        model.isMinimized.toggle()
        UserDefaults.standard.set(model.isMinimized, forKey: OverlayLayout.minimizedDefaultsKey)
        resizeWindowForCurrentPresentation()
    }

    private func dismissOverlay(reason: String) {
        let registrations = ActionSupervisionRegistry.activeRegistrations()
        guard !registrations.isEmpty else {
            shutdown()
            return
        }

        dismissedRegistrationIDs = Set(registrations.map(\.id))
        isDismissed = true
        window?.orderOut(nil)
        isWindowPresented = false
        logger.log("supervision-overlay: dismissed HUD reason=\(reason) registrations=\(registrations.count)")
    }

    private func resizeWindowForCurrentPresentation() {
        guard let window else {
            return
        }

        let oldFrame = window.frame
        let size = currentWindowSize
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let resizedFrame = CGRect(
            x: oldFrame.minX,
            y: oldFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        window.setFrame(clamped(frame: resizedFrame, to: visibleFrame), display: true, animate: true)
        persistWindowFrame()
    }

    private func persistWindowFrame() {
        guard let window else {
            return
        }

        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: OverlayLayout.frameDefaultsKey)
    }

    private func savedWindowFrame(size: CGSize) -> CGRect? {
        guard let raw = UserDefaults.standard.string(forKey: OverlayLayout.frameDefaultsKey), !raw.isEmpty else {
            return nil
        }

        let saved = NSRectFromString(raw)
        guard saved.width > 0, saved.height > 0 else {
            return nil
        }

        return CGRect(origin: saved.origin, size: size)
    }

    private func clamped(frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let x = min(max(frame.minX, visibleFrame.minX + 8), visibleFrame.maxX - frame.width - 8)
        let y = min(max(frame.minY, visibleFrame.minY + 8), visibleFrame.maxY - frame.height - 8)
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if isSupervisorShortcut(event) {
            triggerStopAll(reason: "shortcut")
        }
    }

    private func isSupervisorShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers ?? ""
        if flags.contains([.command, .control]), characters == "." {
            return true
        }

        if event.keyCode == 53 {
            let timestamp = Date()
            if let lastEscapeTimestamp,
               timestamp.timeIntervalSince(lastEscapeTimestamp) < 0.45 {
                self.lastEscapeTimestamp = nil
                return true
            }
            self.lastEscapeTimestamp = timestamp
            return false
        }

        lastEscapeTimestamp = nil
        return false
    }

    private func triggerStopAll(reason: String) {
        let registrations = ActionSupervisionRegistry.activeRegistrations()
        let count = ActionSupervisionRegistry.triggerStopAll()
        logger.log("supervision-overlay: triggered stop count=\(count) reason=\(reason)")
        guard count > 0 else {
            model.detail = "No active Action sessions were found."
            return
        }

        stopRequest = StopRequest(
            registrationIDs: Set(registrations.map(\.id)),
            requestedAt: Date()
        )
        model.isStopPending = true
        model.stopButtonTitle = "Stopping…"
        model.detail = count == 1
            ? "Stop requested for the active session."
            : "Stop requested for \(count) active sessions."
    }

    private func stopPresentation(activeIDs: Set<String>) -> (detail: String?, isPending: Bool) {
        guard let stopRequest else {
            return (nil, false)
        }

        let remainingIDs = stopRequest.registrationIDs.intersection(activeIDs)
        guard !remainingIDs.isEmpty else {
            self.stopRequest = nil
            return (nil, false)
        }

        let elapsed = Date().timeIntervalSince(stopRequest.requestedAt)
        if elapsed < 2 {
            let count = stopRequest.registrationIDs.count
            let detail = count == 1
                ? "Stop requested for the active session."
                : "Stop requested for \(count) active sessions."
            return (detail, true)
        }

        if elapsed < 5 {
            let count = remainingIDs.count
            let detail = count == 1
                ? "1 session is still active. You can try Stop again."
                : "\(count) sessions are still active. You can try Stop All again."
            return (detail, false)
        }

        self.stopRequest = nil
        return (nil, false)
    }

    private func shutdown() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let windowMoveObserver {
            NotificationCenter.default.removeObserver(windowMoveObserver)
            self.windowMoveObserver = nil
        }
        window?.orderOut(nil)
        isWindowPresented = false
        ActionSupervisionRegistry.clearOverlayPID(ifOwnedBy: ProcessInfo.processInfo.processIdentifier)
        try? FileManager.default.removeItem(at: ActionSupervisionRegistry.overlayStopSignalURL)
        NSApplication.shared.terminate(nil)
    }
}
