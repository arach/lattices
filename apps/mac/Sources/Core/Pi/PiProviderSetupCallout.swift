import SwiftUI

struct PiProviderSetupCallout: View {
    @ObservedObject var session: PiChatSession
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.detach)
                    .frame(width: compact ? 6 : 7, height: compact ? 6 : 7)

                Text("SET UP YOUR AI")
                    .font(Typo.geistMonoBold(compact ? 9 : 10))
                    .foregroundColor(Palette.detach.opacity(0.95))
            }

            Text(session.isAuthenticating
                ? "Finish the setup above. As soon as that one step is done, the chat box unlocks."
                : "Chat is optional. Connect \(session.currentProvider.name) when you want the in-app assistant.")
                .font(Typo.mono(compact ? 10 : 11))
                .foregroundColor(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                capsuleLabel(session.currentProvider.name.uppercased(), tint: Palette.text)
                capsuleLabel(session.currentProvider.authMode == .oauth ? "SIGN IN" : "API KEY", tint: Palette.running)
            }

            if session.isAuthenticating {
                PiAuthNextStepCard(session: session, compact: compact)
            } else {
                Text(session.currentProvider.authMode == .oauth
                    ? "This opens the provider flow in your browser."
                    : "Open setup when you are ready to paste and save a key.")
                    .font(Typo.mono(compact ? 9 : 10))
                    .foregroundColor(Palette.textMuted)
            }

            if session.currentProvider.authMode == .oauth && !session.isAuthenticating {
                primaryActionButton(
                    "SET UP \(session.currentProvider.name.uppercased())",
                    tint: Palette.running
                ) {
                    session.toggleAuthPanel()
                }
            }
        }
        .padding(.horizontal, compact ? 10 : 16)
        .padding(.vertical, compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: compact ? 6 : 8)
                .fill(Palette.detach.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 6 : 8)
                        .strokeBorder(Palette.detach.opacity(0.22), lineWidth: 0.5)
                )
        )
    }

    private func primaryActionButton(_ label: String, tint: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Typo.geistMonoBold(compact ? 10 : 11))
                .foregroundColor(disabled ? Palette.textMuted : tint)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 8 : 10)
                .background(
                    RoundedRectangle(cornerRadius: compact ? 6 : 8)
                        .fill(tint.opacity(disabled ? 0.05 : 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: compact ? 6 : 8)
                                .strokeBorder((disabled ? Palette.border : tint.opacity(0.35)), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.65 : 1)
        .disabled(disabled)
    }

    private func capsuleLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Typo.geistMonoBold(compact ? 9 : 10))
            .foregroundColor(tint.opacity(0.95))
            .padding(.horizontal, compact ? 7 : 8)
            .padding(.vertical, compact ? 4 : 5)
            .background(
                Capsule()
                    .fill(tint.opacity(0.10))
                    .overlay(
                        Capsule()
                            .strokeBorder(tint.opacity(0.28), lineWidth: 0.5)
                    )
            )
    }
}
