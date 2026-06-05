import AppKit
import SwiftUI

struct PiWorkspaceView: View {
    @StateObject private var session = PiChatSession.shared
    @FocusState private var composerFocused: Bool
    @FocusState private var authFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            if session.hasPiBinary && !session.needsProviderSetup {
                PiChatTranscript(session: session, style: .workspace)
            } else if session.needsProviderSetup {
                setupPlaceholder
            } else {
                PiInstallCallout(session: session, compact: false)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            if session.hasPiBinary && !session.needsProviderSetup {
                PiChatComposer(session: session, style: .workspace, focus: $composerFocused)
            } else if session.needsProviderSetup {
                providerSettingsPrompt
            }
        }
        .background(Palette.bg)
        .background(WorkspaceFocusActivator())
        .onReceive(NotificationCenter.default.publisher(for: .workspaceComposerFocus)) { _ in
            // Fired exactly when the hosting window becomes key, so setting the
            // caret here actually renders it — no timed guessing.
            if session.hasPiBinary && !session.needsProviderSetup {
                composerFocused = true
            }
        }
        .onAppear {
            session.prepareForDisplay()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace Assistant")
                    .font(Typo.title(14))
                    .foregroundColor(Palette.text)

                Text(headerSubtitle)
                    .font(Typo.caption(11))
                    .foregroundColor(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(spacing: 8) {
                PiChatModelChip(session: session)

                headerIconButton(symbol: "gearshape") {
                    SettingsWindowController.shared.showAssistant()
                }

                if session.hasConversationHistory {
                    headerTextButton("Clear") {
                        session.clearConversation()
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var headerSubtitle: String {
        if !session.hasPiBinary {
            return "Install the Pi runtime to unlock provider-backed chat."
        }
        if session.isAuthenticating {
            return session.authStepDescription
        }
        if session.needsProviderSetup {
            return "Connect a provider in Settings to start chatting."
        }
        return "Settings, layout help, planning, and debugging in one thread."
    }

    private var statusPill: some View {
        let tint: Color = {
            switch session.statusText {
            case "missing pi", "error": return Palette.kill
            case "setup ai", "connecting...", "streaming...": return Palette.detach
            default:
                if session.statusText.hasPrefix("tool:") { return Palette.detach }
                return session.isSending ? Palette.detach : Palette.running
            }
        }()

        let label: String = {
            if session.isSending {
                if session.statusText == "streaming..." { return "Streaming" }
                if session.statusText.hasPrefix("tool:") {
                    return session.statusText.replacingOccurrences(of: "tool: ", with: "Tool · ")
                }
                return "Thinking"
            }
            if session.statusText == "idle" { return "Ready" }
            return session.statusText.capitalized
        }()

        return Text(label)
            .font(Typo.geistMonoBold(9))
            .foregroundColor(tint.opacity(0.95))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
                    .overlay(Capsule().strokeBorder(tint.opacity(0.24), lineWidth: 0.5))
            )
    }

    private var setupPlaceholder: some View {
        VStack {
            Spacer()
            PiInstallCallout(session: session, compact: false)
                .padding(.horizontal, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var providerSettingsPrompt: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(Palette.detach)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 3) {
                Text("Connect a provider")
                    .font(Typo.heading(12))
                    .foregroundColor(Palette.text)

                Text("Open Settings to add OpenAI, Anthropic, Groq, or another provider.")
                    .font(Typo.caption(11))
                    .foregroundColor(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            headerTextButton("Settings", tint: Palette.running) {
                SettingsWindowController.shared.showAssistant()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Palette.surface.opacity(0.22))
    }

    private func headerIconButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.textMuted)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
    }

    private func headerTextButton(_ title: String, tint: Color = Palette.textMuted, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(Typo.caption(11))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.04))
                    .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
            )
    }
}

extension Notification.Name {
    /// Posted when the assistant's hosting window becomes key, so the composer
    /// can take the caret at the exact moment it can actually render one.
    static let workspaceComposerFocus = Notification.Name("dev.lattices.workspaceComposerFocus")
}

/// Zero-size bridge that activates the app + makes the hosting window key on
/// attach, and re-signals focus every time the window becomes key.
private struct WorkspaceFocusActivator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FocusTrackerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class FocusTrackerView: NSView {
        private var observer: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    NotificationCenter.default.post(name: .workspaceComposerFocus, object: nil)
                }
            }
            // If it's already key (tab switch within a focused window), signal now.
            if window.isKeyWindow {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .workspaceComposerFocus, object: nil)
                }
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
