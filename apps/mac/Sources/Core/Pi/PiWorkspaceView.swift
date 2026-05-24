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
        .onAppear {
            session.prepareForDisplay()
            if session.hasPiBinary && !session.needsProviderSetup {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    composerFocused = true
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            PiChatAvatar(symbol: "sparkles", tint: Palette.running)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Workspace Assistant")
                        .font(Typo.heading(14))
                        .foregroundColor(Palette.text)

                    statusPill
                }

                Text(headerSubtitle)
                    .font(Typo.caption(11))
                    .foregroundColor(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(spacing: 6) {
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
        .padding(.vertical, 16)
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
