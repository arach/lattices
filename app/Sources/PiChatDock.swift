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

            if session.isAuthPanelVisible {
                Rectangle()
                    .fill(Palette.border)
                    .frame(height: 0.5)

                authPanel

                Rectangle()
                    .fill(Palette.border)
                    .frame(height: 0.5)
            }

            transcript

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            composer

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                composerFocused = true
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
            HStack(spacing: 8) {
                Text("provider")
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
                HStack(spacing: 8) {
                    SecureField(session.currentProvider.tokenPlaceholder, text: $session.authToken)
                        .textFieldStyle(.plain)
                        .font(Typo.mono(11))
                        .foregroundColor(Palette.text)
                        .focused($authFieldFocused)
                        .onSubmit {
                            session.saveSelectedToken()
                        }

                    footerButton("save") {
                        session.saveSelectedToken()
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
            } else {
                HStack(spacing: 8) {
                    footerButton(session.isAuthenticating ? "cancel" : "login") {
                        if session.isAuthenticating {
                            session.cancelAuthFlow()
                        } else {
                            session.startSelectedAuthFlow()
                        }
                    }

                    if session.hasSelectedCredential {
                        footerButton("clear") {
                            session.removeSelectedCredential()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(authCardBackground(tint: session.isAuthenticating ? Palette.detach : Palette.running))

                if let prompt = session.pendingAuthPrompt {
                    HStack(spacing: 8) {
                        TextField(prompt.placeholder ?? prompt.message, text: $session.authPromptInput)
                            .textFieldStyle(.plain)
                            .font(Typo.mono(11))
                            .foregroundColor(Palette.text)
                            .focused($authFieldFocused)
                            .onSubmit {
                                session.submitAuthPrompt()
                            }

                        footerButton("continue") {
                            session.submitAuthPrompt()
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(authCardBackground(tint: Palette.detach))
                }
            }

            if let notice = session.authNoticeText, !notice.isEmpty {
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

                TextField("Ask Pi something lightweight...", text: $session.draft, axis: .vertical)
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

            Text("PI DOCK")
                .font(Typo.geistMonoBold(9))
                .foregroundColor(Palette.text)

            Text(footerStatusText)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
                .lineLimit(1)

            Spacer()

            footerButton(session.isAuthPanelVisible ? "auth -" : "auth +") {
                session.toggleAuthPanel()
            }

            footerButton("reset") {
                session.clearConversation()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.015))
    }

    private var footerStatusText: String {
        if session.statusText == "idle" {
            return session.currentProvider.name
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

    private func roleLabel(for role: PiChatMessage.Role) -> String {
        switch role {
        case .system: return "system"
        case .user: return "you"
        case .assistant: return "pi"
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

    private func footerButton(_ label: String, tint: Color = Palette.textMuted, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(Typo.geistMonoBold(9))
            .foregroundColor(tint)
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
