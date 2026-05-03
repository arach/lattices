import SwiftUI

struct PiAuthNextStepCard: View {
    @ObservedObject var session: PiChatSession
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.running)
                    .frame(width: compact ? 6 : 7, height: compact ? 6 : 7)

                Text(session.authStepLabel)
                    .font(Typo.geistMonoBold(compact ? 9 : 10))
                    .foregroundColor(Palette.running.opacity(0.95))
            }

            Text(session.authStepTitle)
                .font(Typo.geistMonoBold(compact ? 11 : 13))
                .foregroundColor(Palette.text)

            Text(session.authStepDescription)
                .font(Typo.mono(compact ? 10 : 11))
                .foregroundColor(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            if let code = session.authVerificationCode {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("CODE READY")
                            .font(Typo.geistMonoBold(compact ? 8 : 9))
                            .foregroundColor(Palette.textMuted)

                        if session.authVerificationCodeCopied {
                            statusCapsule("COPIED")
                        }
                    }

                    Text(code)
                        .font(Typo.geistMonoBold(compact ? 14 : 16))
                        .foregroundColor(Palette.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, compact ? 10 : 12)
                        .padding(.vertical, compact ? 9 : 10)
                        .background(
                            RoundedRectangle(cornerRadius: compact ? 6 : 8)
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: compact ? 6 : 8)
                                        .strokeBorder(Palette.borderLit.opacity(0.5), lineWidth: 0.5)
                                )
                        )
                }
            }

            primaryActionButton(
                session.latestAuthURL == nil
                    ? "OPENING BROWSER..."
                    : (session.authVerificationCode != nil ? "OPEN PAGE AGAIN" : "OPEN BROWSER AGAIN"),
                tint: Palette.running,
                disabled: session.latestAuthURL == nil
            ) {
                session.reopenLatestAuthURL()
            }

            HStack(spacing: 8) {
                if session.authVerificationCode != nil {
                    secondaryActionButton("COPY AGAIN", tint: Palette.text) {
                        session.copyAuthVerificationCode()
                    }
                }

                Spacer(minLength: 0)

                secondaryActionButton("CANCEL", tint: Palette.textMuted) {
                    session.cancelAuthFlow()
                }
            }
        }
        .padding(.horizontal, compact ? 10 : 16)
        .padding(.vertical, compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: compact ? 6 : 8)
                .fill(Palette.running.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 6 : 8)
                        .strokeBorder(Palette.running.opacity(0.22), lineWidth: 0.5)
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
        .opacity(disabled ? 0.7 : 1)
        .disabled(disabled)
    }

    private func secondaryActionButton(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(Typo.geistMonoBold(compact ? 9 : 10))
            .foregroundColor(tint)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 5 : 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        Capsule()
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
    }

    private func statusCapsule(_ text: String) -> some View {
        Text(text)
            .font(Typo.geistMonoBold(compact ? 8 : 9))
            .foregroundColor(Palette.running.opacity(0.95))
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, compact ? 3 : 4)
            .background(
                Capsule()
                    .fill(Palette.running.opacity(0.12))
                    .overlay(
                        Capsule()
                            .strokeBorder(Palette.running.opacity(0.28), lineWidth: 0.5)
                    )
            )
    }
}
