import SwiftUI
import AppKit

// MARK: - Onboarding Flow

/// A step-by-step welcome screen shown on first launch.
/// Walks the user through granting Accessibility, Screen Recording,
/// choosing a project root, and optionally installing tmux.
struct OnboardingView: View {
    @ObservedObject private var permChecker = PermissionChecker.shared
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var tmux = TmuxModel.shared
    @State private var step: Step = .welcome
    var onComplete: () -> Void

    enum Step: Int, CaseIterable {
        case welcome
        case accessibility
        case screenRecording
        case projectRoot
        case tmux
        case done
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Color.white : Color.white.opacity(0.20))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            // Step content
            Group {
                switch step {
                case .welcome:      welcomeStep
                case .accessibility: accessibilityStep
                case .screenRecording: screenRecordingStep
                case .projectRoot:  projectRootStep
                case .tmux:         tmuxStep
                case .done:         doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)

            Spacer(minLength: 0)

            // Navigation
            HStack {
                if step != .welcome {
                    Button("Back") { withAnimation(.easeInOut(duration: 0.2)) { goBack() } }
                        .buttonStyle(.plain)
                        .font(Typo.mono(11))
                        .foregroundColor(Palette.textMuted)
                }
                Spacer()
                if step == .done {
                    Button(action: { onComplete() }) {
                        Text("Get started")
                            .angularButton(Palette.running)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { advance() } }) {
                        Text(nextLabel)
                            .angularButton(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 28)
        }
        .frame(width: 480, height: 420)
        .background(Palette.bg)
        .preferredColorScheme(.dark)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            latticesIcon
            Text("Welcome to Lattices")
                .font(Typo.title(18))
                .foregroundColor(Palette.text)
            Text("Workspace control plane for macOS.\nLet's get you set up in under a minute.")
                .font(Typo.body(12))
                .foregroundColor(Palette.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    private var accessibilityStep: some View {
        permissionStep(
            icon: "hand.raised.fill",
            title: "Accessibility",
            description: "Lattices needs Accessibility access to read window titles, move and resize windows, and tile your workspace.",
            granted: permChecker.accessibility,
            action: { permChecker.requestAccessibility() }
        )
    }

    private var screenRecordingStep: some View {
        permissionStep(
            icon: "rectangle.dashed.badge.record",
            title: "Screen Recording",
            description: "Allows Lattices to index on-screen text with OCR so you can search across all your windows.",
            granted: permChecker.screenRecording,
            action: { permChecker.requestScreenRecording() }
        )
    }

    private var projectRootStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.fill")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.7))

            Text("Project directory")
                .font(Typo.title(16))
                .foregroundColor(Palette.text)

            Text("Where do your projects live? Lattices scans this folder to find workspaces.")
                .font(Typo.body(12))
                .foregroundColor(Palette.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            HStack(spacing: 8) {
                Text(prefs.scanRoot.isEmpty ? "Not set" : abbreviatePath(prefs.scanRoot))
                    .font(Typo.mono(11))
                    .foregroundColor(prefs.scanRoot.isEmpty ? Palette.textMuted : Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Palette.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Palette.border, lineWidth: 0.5)
                            )
                    )

                Button("Browse") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.directoryURL = URL(fileURLWithPath: prefs.scanRoot.isEmpty ? NSHomeDirectory() : prefs.scanRoot)
                    if panel.runModal() == .OK, let url = panel.url {
                        prefs.scanRoot = url.path
                    }
                }
                .buttonStyle(.plain)
                .font(Typo.monoBold(10))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Palette.borderLit, lineWidth: 0.5)
                        )
                )
            }

            if !prefs.scanRoot.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Palette.running)
                    Text(abbreviatePath(prefs.scanRoot))
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.running)
                }
            }
        }
    }

    private var tmuxStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.7))

            Text("Terminal sessions")
                .font(Typo.title(16))
                .foregroundColor(Palette.text)

            if tmux.isAvailable {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Palette.running)
                    Text("tmux is installed")
                        .font(Typo.mono(12))
                        .foregroundColor(Palette.running)
                }
                Text("Lattices can manage tmux sessions, pane layouts, and terminal workspaces for you.")
                    .font(Typo.body(12))
                    .foregroundColor(Palette.textDim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            } else {
                Text("tmux is optional but recommended. It enables managed terminal sessions with persistent pane layouts.")
                    .font(Typo.body(12))
                    .foregroundColor(Palette.textDim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                Button(action: {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    task.arguments = ["-lc", "brew install tmux"]
                    task.standardOutput = FileHandle.nullDevice
                    task.standardError = FileHandle.nullDevice
                    try? task.run()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11))
                        Text("brew install tmux")
                            .font(Typo.monoBold(11))
                    }
                    .angularButton(.white, filled: false)
                }
                .buttonStyle(.plain)

                Text("You can always install it later. Window tiling, search, and OCR work without tmux.")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(Palette.running)

            Text("You're all set")
                .font(Typo.title(18))
                .foregroundColor(Palette.text)

            VStack(alignment: .leading, spacing: 8) {
                statusRow("Accessibility", granted: permChecker.accessibility)
                statusRow("Screen Recording", granted: permChecker.screenRecording)
                statusRow("Project root", granted: !prefs.scanRoot.isEmpty,
                          detail: prefs.scanRoot.isEmpty ? "not set" : abbreviatePath(prefs.scanRoot))
                statusRow("tmux", granted: tmux.isAvailable,
                          detail: tmux.isAvailable ? "installed" : "skipped")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
        }
    }

    // MARK: - Shared helpers

    private func permissionStep(icon: String, title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.7))

            Text(title)
                .font(Typo.title(16))
                .foregroundColor(Palette.text)

            Text(description)
                .font(Typo.body(12))
                .foregroundColor(Palette.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            if granted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Palette.running)
                    Text("Granted")
                        .font(Typo.monoBold(11))
                        .foregroundColor(Palette.running)
                }
            } else {
                Button(action: action) {
                    Text("Grant \(title)")
                        .angularButton(.white, filled: false)
                }
                .buttonStyle(.plain)

                Text("macOS will ask you to toggle this on in System Settings.")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func statusRow(_ label: String, granted: Bool, detail: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundColor(granted ? Palette.running : Palette.detach)
            Text(label)
                .font(Typo.mono(11))
                .foregroundColor(Palette.text)
            Spacer()
            if let detail {
                Text(detail)
                    .font(Typo.mono(10))
                    .foregroundColor(granted ? Palette.textDim : Palette.detach)
            } else {
                Text(granted ? "granted" : "not set")
                    .font(Typo.mono(10))
                    .foregroundColor(granted ? Palette.running : Palette.detach)
            }
        }
    }

    private var latticesIcon: some View {
        // 3x3 grid — L-shape pattern
        let cells = [true, false, false, true, false, false, true, true, true]
        let size: CGFloat = 40
        let pad: CGFloat = 4
        let gap: CGFloat = 2.5
        let cell = (size - 2 * pad - 2 * gap) / 3
        return Canvas { context, _ in
            for (i, bright) in cells.enumerated() {
                let row = i / 3
                let col = i % 3
                let rect = CGRect(
                    x: pad + CGFloat(col) * (cell + gap),
                    y: pad + CGFloat(row) * (cell + gap),
                    width: cell, height: cell
                )
                context.fill(
                    RoundedRectangle(cornerRadius: 2).path(in: rect),
                    with: .color(bright ? .white : .white.opacity(0.18))
                )
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Navigation

    private var nextLabel: String {
        switch step {
        case .accessibility where !permChecker.accessibility: return "Continue anyway"
        case .screenRecording where !permChecker.screenRecording: return "Continue anyway"
        case .projectRoot where prefs.scanRoot.isEmpty: return "Skip for now"
        case .tmux where !tmux.isAvailable: return "Skip"
        default: return "Continue"
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Window Controller

final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private static let completedKey = "onboarding.completed"

    var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: Self.completedKey)
    }

    /// Show the onboarding window if not yet completed.
    /// Returns true if onboarding was shown.
    @discardableResult
    func showIfNeeded() -> Bool {
        guard !hasCompleted else { return false }
        show()
        return true
    }

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView {
            self.complete()
        }

        let w = AppWindowShell.makeWindow(
            config: .init(
                title: "Welcome to Lattices",
                titleVisible: false,
                initialSize: NSSize(width: 480, height: 420),
                minSize: NSSize(width: 480, height: 420),
                maxSize: NSSize(width: 480, height: 420),
                miniaturizable: false
            ),
            rootView: view
        )
        w.styleMask.remove(.resizable)
        AppWindowShell.positionCentered(w)
        AppWindowShell.present(w)
        self.window = w
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        window?.orderOut(nil)
        window = nil
        AppDelegate.updateActivationPolicy()
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: Self.completedKey)
    }
}
