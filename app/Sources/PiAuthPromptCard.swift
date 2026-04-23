import SwiftUI

struct PiAuthPromptCard: View {
    @ObservedObject var session: PiChatSession
    let prompt: PiAuthPrompt
    let compact: Bool
    var focus: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.detach)
                    .frame(width: compact ? 6 : 7, height: compact ? 6 : 7)

                Text("STEP 1")
                    .font(Typo.geistMonoBold(compact ? 9 : 10))
                    .foregroundColor(Palette.detach.opacity(0.95))
            }

            Text("One quick question")
                .font(Typo.geistMonoBold(compact ? 11 : 13))
                .foregroundColor(Palette.text)

            Text(prompt.message)
                .font(Typo.mono(compact ? 10 : 11))
                .foregroundColor(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField(prompt.placeholder ?? "Type your answer", text: $session.authPromptInput)
                    .textFieldStyle(.plain)
                    .font(Typo.mono(compact ? 11 : 12))
                    .foregroundColor(Palette.text)
                    .focused(focus)

                actionButton("CONTINUE", tint: Palette.detach, disabled: !session.canSubmitAuthPrompt) {
                    session.submitAuthPrompt()
                }
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 8 : 10)
            .background(
                RoundedRectangle(cornerRadius: compact ? 6 : 8)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: compact ? 6 : 8)
                            .strokeBorder(Palette.border.opacity(0.85), lineWidth: 0.5)
                    )
            )

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                actionButton("CANCEL", tint: Palette.textMuted) {
                    session.cancelAuthFlow()
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

    private func actionButton(_ label: String, tint: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(Typo.geistMonoBold(compact ? 9 : 10))
            .foregroundColor(disabled ? Palette.textMuted : tint)
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
            .opacity(disabled ? 0.65 : 1)
            .disabled(disabled)
    }
}
