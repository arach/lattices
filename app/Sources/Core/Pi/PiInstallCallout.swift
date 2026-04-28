import SwiftUI

struct PiInstallCallout: View {
    @ObservedObject var session: PiChatSession
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.kill)
                    .frame(width: compact ? 6 : 7, height: compact ? 6 : 7)

                Text("PI REQUIRED")
                    .font(Typo.geistMonoBold(compact ? 9 : 10))
                    .foregroundColor(Palette.kill.opacity(0.95))

                Text("assistant unavailable")
                    .font(Typo.mono(compact ? 9 : 10))
                    .foregroundColor(Palette.textMuted)
            }

            Text("Install the official Pi coding agent CLI to use the in-app assistant. Lattices can copy the command or run it in \(Preferences.shared.terminal.rawValue).")
                .font(Typo.mono(compact ? 10 : 11))
                .foregroundColor(Palette.textDim)
                .fixedSize(horizontal: false, vertical: true)

            Text(session.piInstallCommand)
                .font(Typo.mono(compact ? 10 : 11))
                .foregroundColor(Palette.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 8 : 10)
                .background(
                    RoundedRectangle(cornerRadius: compact ? 6 : 8)
                        .fill(Color.black.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: compact ? 6 : 8)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                )

            HStack(spacing: 8) {
                actionButton(compact ? "COPY" : "COPY CMD", tint: Palette.running) {
                    session.copyPiInstallCommand()
                }

                actionButton(compact ? "INSTALL" : "INSTALL IN TERMINAL", tint: Palette.detach) {
                    session.installPiInTerminal()
                }

                actionButton("REFRESH", tint: Palette.textMuted) {
                    session.refreshBinaryAvailability()
                }
            }
        }
        .padding(.horizontal, compact ? 10 : 16)
        .padding(.vertical, compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: compact ? 6 : 8)
                .fill(Palette.kill.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 6 : 8)
                        .strokeBorder(Palette.kill.opacity(0.22), lineWidth: 0.5)
                )
        )
    }

    private func actionButton(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
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
}
