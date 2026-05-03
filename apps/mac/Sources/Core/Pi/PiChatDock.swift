import SwiftUI

struct PiChatDock: View {
    @ObservedObject var session: PiChatSession
    @FocusState private var composerFocused: Bool
    @FocusState private var authFieldFocused: Bool
    @State private var resizeStartHeight: CGFloat?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            topHandle

            transcript

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            if session.hasPiBinary && !session.needsProviderSetup {
                composer
            } else if session.needsProviderSetup {
                providerSettingsBar
            } else {
                PiInstallCallout(session: session, compact: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.62))
            }

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            footerBar
        }
        .frame(maxWidth: .infinity)
        .frame(height: session.dockHeight)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.96),
                    Color(red: 0.02, green: 0.05, blue: 0.03),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .onAppear {
            session.prepareForDisplay()
            if session.hasPiBinary && !session.needsProviderSetup {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    composerFocused = true
                }
            }
        }
    }

    private var topHandle: some View {
        HStack {
            Spacer()

            Capsule()
                .fill(Palette.borderLit)
                .frame(width: 64, height: 4)

            Spacer()

            Button {
                session.isVisible = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Palette.textMuted)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.03))
                            .overlay(
                                Circle()
                                    .strokeBorder(Palette.border, lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if resizeStartHeight == nil {
                        resizeStartHeight = session.dockHeight
                    }
                    let start = resizeStartHeight ?? session.dockHeight
                    session.dockHeight = start - value.translation.height
                }
                .onEnded { _ in
                    resizeStartHeight = nil
                }
        )
    }

    private var authPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.isAuthenticating {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Finish Setup")
                        .font(Typo.geistMonoBold(10))
                        .foregroundColor(Palette.text)

                    Text("Ignore the rest for a second and just do the next step below.")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    capsuleLabel(session.currentProvider.name.uppercased(), tint: Palette.text)
                    capsuleLabel("IN PROGRESS", tint: Palette.detach)
                    Spacer()
                }

                if let prompt = session.pendingAuthPrompt {
                    PiAuthPromptCard(session: session, prompt: prompt, compact: true, focus: $authFieldFocused)
                } else {
                    PiAuthNextStepCard(session: session, compact: true)
                }
            } else {
                if session.needsProviderSetup {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Set Up Your AI")
                            .font(Typo.geistMonoBold(10))
                            .foregroundColor(Palette.text)

                        Text("Choose a provider, connect it once, and the chat box unlocks automatically.")
                            .font(Typo.mono(9))
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

                            Text("credential saved")
                                .font(Typo.mono(9))
                                .foregroundColor(Palette.textDim)

                            Spacer()

                            footerButton("replace") {
                                session.beginReplacingSelectedCredential()
                            }

                            footerButton("clear") {
                                session.removeSelectedCredential()
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
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

                            footerButton("save key") {
                                session.saveSelectedToken()
                            }

                            if session.hasSelectedCredential {
                                footerButton("cancel") {
                                    session.cancelReplacingSelectedCredential()
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(authCardBackground(tint: Palette.running))
                    }
                } else {
                    HStack(spacing: 8) {
                        footerButton("connect") {
                            session.startSelectedAuthFlow()
                        }

                        if session.hasSelectedCredential {
                            footerButton("clear") {
                                session.removeSelectedCredential()
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    Palette.running.opacity(0.07),
                    Color.black.opacity(0.26),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(session.messages) { message in
                        row(message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .background(Color.black.opacity(0.35))
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
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                capsuleLabel(roleLabel(for: message.role).uppercased(), tint: roleColor(for: message.role))

                Text(timestamp(for: message.timestamp))
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.textMuted)
            }
            .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(roleColor(for: message.role).opacity(0.9))
                    .frame(width: 14, height: 1.5)

                Text(message.text)
                    .font(Typo.mono(11))
                    .foregroundColor(Palette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(roleColor(for: message.role).opacity(message.role == .assistant ? 0.11 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(roleColor(for: message.role).opacity(0.22), lineWidth: 0.5)
                )
        )
    }

    private var composer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(">")
                    .font(Typo.geistMonoBold(11))
                    .foregroundColor(Palette.running)

                TextField("Ask about settings...", text: $session.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typo.mono(11))
                    .foregroundColor(Palette.text)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .onSubmit {
                        session.sendDraft()
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.38))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Palette.running.opacity(0.16), lineWidth: 0.5)
                    )
            )

            footerButton("send", tint: Palette.running) {
                session.sendDraft()
            }
            .disabled(session.isSending)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.62))
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.hasPiBinary ? Palette.running : Palette.kill)
                .frame(width: 6, height: 6)

            Text("ASSISTANT")
                .font(Typo.geistMonoBold(9))
                .foregroundColor(Palette.text)

            Text(footerStatusText)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
                .lineLimit(1)

            Spacer()

            footerIconButton(systemName: "gearshape") {
                SettingsWindowController.shared.showAssistant()
            }

            footerButton("reset") {
                session.clearConversation()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.015))
    }

    private var providerSettingsBar: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(Palette.detach)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("CONNECT A PROVIDER")
                    .font(Typo.geistMonoBold(9))
                    .foregroundColor(Palette.text)

                Text("Choose a chat provider in Settings.")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            footerButton("settings", tint: Palette.running) {
                SettingsWindowController.shared.showAssistant()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.62))
    }

    private var footerStatusText: String {
        if session.statusText == "idle" || session.needsProviderSetup || session.isAuthenticating || !session.hasPiBinary {
            return session.setupStatusSummary
        }
        return "\(session.currentProvider.name) · \(session.statusText)"
    }

    private func focusAuthFieldIfNeeded() {
        if session.currentProvider.authMode == .apiKey || session.pendingAuthPrompt != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                authFieldFocused = true
            }
        }
    }

    private var setupLockedBar: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(Palette.detach)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("SETUP IN PROGRESS")
                    .font(Typo.geistMonoBold(9))
                    .foregroundColor(Palette.text)

                Text(session.isAuthenticating
                    ? "Stay with the setup panel above for now. The chat box unlocks as soon as you finish that step."
                    : "Finish the setup panel above to unlock the chat box.")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.62))
    }

    private func roleLabel(for role: PiChatMessage.Role) -> String {
        switch role {
        case .system: return "system"
        case .user: return "you"
        case .assistant: return "assistant"
        }
    }

    private func roleColor(for role: PiChatMessage.Role) -> Color {
        switch role {
        case .system: return Palette.detach
        case .user: return Palette.textDim
        case .assistant: return Palette.running
        }
    }

    private func timestamp(for date: Date) -> String {
        Self.timeFormatter.string(from: date)
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

    private func footerButton(_ label: String, tint: Color = Palette.textMuted, disabled: Bool = false, action: @escaping () -> Void) -> some View {
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

    private func footerIconButton(systemName: String, tint: Color = Palette.textMuted, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 24, height: 22)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.03))
                        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
    }

    private func authCardBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(tint.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(tint.opacity(0.24), lineWidth: 0.5)
            )
    }
}
