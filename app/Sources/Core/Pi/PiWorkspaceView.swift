import SwiftUI

struct PiWorkspaceView: View {
    @StateObject private var session = PiChatSession.shared
    @FocusState private var composerFocused: Bool
    @FocusState private var authFieldFocused: Bool

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            transcript

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            if session.hasPiBinary && !session.needsProviderSetup {
                composer
            } else if session.needsProviderSetup {
                providerSettingsPrompt
            } else {
                PiInstallCallout(session: session, compact: false)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Palette.surface.opacity(0.22))
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.hasPiBinary ? Palette.running : Palette.kill)
                        .frame(width: 7, height: 7)

                    Text("WORKSPACE ASSISTANT")
                        .font(Typo.geistMonoBold(11))
                        .foregroundColor(Palette.text)

                    capsuleLabel(
                        session.statusText.uppercased(),
                        tint: session.statusText == "missing pi"
                            ? Palette.kill
                            : ((session.statusText == "setup ai" || session.statusText == "connecting...")
                                ? Palette.detach
                                : (session.isSending ? Palette.detach : Palette.running))
                    )
                }

                Text(session.hasPiBinary
                    ? (session.isAuthenticating
                        ? session.authStepDescription
                        : (session.needsProviderSetup
                            ? "Next step: connect a provider to unlock chat."
                            : "Full conversation surface for settings, longer prompts, planning, debugging, and second opinions."))
                    : "Settings chat is ready here. Install the provider runtime to unlock longer prompts and provider-backed chat.")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textDim)
            }

            Spacer()

            HStack(spacing: 6) {
                settingsGearButton

                if session.hasConversationHistory {
                    actionChip("RESET") {
                        session.clearConversation()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var settingsGearButton: some View {
        Button {
            SettingsWindowController.shared.showAssistant()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Palette.textMuted)
                .frame(width: 26, height: 24)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.03))
                        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
    }

    private var providerSettingsPrompt: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(Palette.detach)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 3) {
                Text("CONNECT A PROVIDER")
                    .font(Typo.geistMonoBold(10))
                    .foregroundColor(Palette.text)

                Text("Choose OpenAI, Groq, OpenRouter, or MiniMax in Settings to unlock provider-backed chat.")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            actionChip("SETTINGS", tint: Palette.running) {
                SettingsWindowController.shared.showAssistant()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.surface.opacity(0.22))
    }

    private var authPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.isAuthenticating {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Finish Setup")
                        .font(Typo.geistMonoBold(11))
                        .foregroundColor(Palette.text)

                    Text("Ignore the rest for a second and just do the next step below.")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    capsuleLabel(session.currentProvider.name.uppercased(), tint: Palette.text)
                    capsuleLabel("IN PROGRESS", tint: Palette.detach)
                    Spacer()
                }

                if let prompt = session.pendingAuthPrompt {
                    PiAuthPromptCard(session: session, prompt: prompt, compact: false, focus: $authFieldFocused)
                } else {
                    PiAuthNextStepCard(session: session, compact: false)
                }
            } else {
                if session.needsProviderSetup {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Set Up Your AI")
                            .font(Typo.geistMonoBold(11))
                            .foregroundColor(Palette.text)

                        Text("Choose a provider, connect it once, and the chat box unlocks automatically.")
                            .font(Typo.mono(10))
                            .foregroundColor(Palette.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    Text(session.needsProviderSetup ? "choose provider" : "provider")
                        .font(Typo.geistMonoBold(9))
                        .foregroundColor(Palette.textMuted)

                    Picker("Provider", selection: $session.authProviderID) {
                        ForEach(session.providerOptions) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(Typo.mono(10))

                    Spacer()

                    capsuleLabel(
                        session.currentProvider.authMode == .oauth ? "OAUTH" : "TOKEN",
                        tint: session.currentProvider.authMode == .oauth ? Palette.detach : Palette.running
                    )
                }

                Text(session.currentProvider.helpText)
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                if session.currentProvider.authMode == .apiKey {
                    if session.hasSelectedCredential && !session.isEditingStoredCredential {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Palette.running)
                                .frame(width: 6, height: 6)

                            Text("\(session.currentProvider.name) credential saved")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)

                            Spacer()

                            actionChip("REPLACE") {
                                session.beginReplacingSelectedCredential()
                            }

                            actionChip("CLEAR") {
                                session.removeSelectedCredential()
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(authCardBackground(tint: Palette.running))
                    } else {
                        HStack(spacing: 8) {
                            SecureField(session.currentProvider.tokenPlaceholder, text: $session.authToken)
                                .textFieldStyle(.plain)
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.text)
                                .focused($authFieldFocused)
                                .onSubmit {
                                    session.saveSelectedToken()
                                }

                            actionChip("SAVE KEY") {
                                session.saveSelectedToken()
                            }

                            if session.hasSelectedCredential {
                                actionChip("CANCEL") {
                                    session.cancelReplacingSelectedCredential()
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(authCardBackground(tint: Palette.running))
                    }
                } else {
                    HStack(spacing: 8) {
                        actionChip("CONNECT") {
                            session.startSelectedAuthFlow()
                        }

                        if session.hasSelectedCredential {
                            actionChip("CLEAR") {
                                session.removeSelectedCredential()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(authCardBackground(tint: Palette.running))
                }
            }

            if !session.isAuthenticating, let notice = session.authNoticeText, !notice.isEmpty {
                Text(notice)
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = session.authErrorText, !error.isEmpty {
                Text(error)
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.kill)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.surface.opacity(0.35))
        .onAppear {
            focusAuthFieldIfNeeded()
        }
        .onChange(of: session.authProviderID) { _ in
            focusAuthFieldIfNeeded()
        }
        .onChange(of: session.pendingAuthPrompt?.message) { prompt in
            if prompt != nil {
                focusAuthFieldIfNeeded()
            }
        }
    }

    private var setupLockedPanel: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(Palette.detach)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 3) {
                Text("SETUP IN PROGRESS")
                    .font(Typo.geistMonoBold(10))
                    .foregroundColor(Palette.text)

                Text(session.isAuthenticating
                    ? "Stay with the setup panel above for now. The chat box unlocks as soon as you finish that step."
                    : "Finish the setup panel above to unlock the chat box.")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.surface.opacity(0.22))
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(session.messages) { message in
                        row(message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onAppear {
                if let last = session.messages.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            .onChange(of: session.messages.count) { _ in
                if let last = session.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func row(_ message: PiChatMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                capsuleLabel(roleLabel(for: message.role).uppercased(), tint: roleColor(for: message.role))
                Text(Self.timeFormatter.string(from: message.timestamp))
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.textMuted)
            }
            .frame(width: 62, alignment: .leading)

            Text(message.text)
                .font(Typo.mono(12))
                .foregroundColor(Palette.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(roleColor(for: message.role).opacity(message.role == .assistant ? 0.10 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(roleColor(for: message.role).opacity(0.22), lineWidth: 0.5)
                )
        )
    }

    private var composer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(">")
                    .font(Typo.geistMonoBold(12))
                    .foregroundColor(Palette.running)

                TextField("Ask about settings or planning...", text: $session.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typo.mono(12))
                    .foregroundColor(Palette.text)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .onSubmit {
                        session.sendDraft()
                    }

                actionChip(session.isSending ? "..." : "SEND") {
                    session.sendDraft()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Palette.running.opacity(0.18), lineWidth: 0.5)
                    )
            )

            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.hasPiBinary ? Palette.running : Palette.kill)
                        .frame(width: 6, height: 6)

                    Text(session.currentProvider.name)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                }

                Spacer()

                Text("Return to send")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.surface.opacity(0.22))
    }

    private func roleLabel(for role: PiChatMessage.Role) -> String {
        switch role {
        case .system: return "system"
        case .user: return "you"
        case .assistant: return "assistant"
        }
    }

    private func focusAuthFieldIfNeeded() {
        if session.currentProvider.authMode == .apiKey || session.pendingAuthPrompt != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                authFieldFocused = true
            }
        }
    }

    private func roleColor(for role: PiChatMessage.Role) -> Color {
        switch role {
        case .system: return Palette.detach
        case .user: return Palette.textDim
        case .assistant: return Palette.running
        }
    }

    private func capsuleLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Typo.geistMonoBold(9))
            .foregroundColor(tint.opacity(0.95))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tint.opacity(0.10))
                    .overlay(
                        Capsule()
                            .strokeBorder(tint.opacity(0.28), lineWidth: 0.5)
                    )
            )
    }

    private func actionChip(_ label: String, tint: Color = Palette.textMuted, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(Typo.geistMonoBold(9))
            .foregroundColor(disabled ? Palette.textMuted : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        Capsule()
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
            .opacity(disabled ? 0.65 : 1)
            .disabled(disabled)
    }

    private func authCardBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(tint.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
            )
    }
}
