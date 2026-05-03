import SwiftUI

struct OrphanRow: View {
    let session: TmuxSession
    var onAttach: () -> Void
    var onKill: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = false

    private var commandSummary: String {
        let commands = session.panes
            .map(\.currentCommand)
            .filter { !$0.isEmpty }
        let unique = commands.count <= 3 ? commands : Array(commands.prefix(3)) + ["..."]
        return "\(session.panes.count) pane\(session.panes.count == 1 ? "" : "s") \u{2014} \(unique.joined(separator: ", "))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 10) {
                // Status bar — amber for orphan
                RoundedRectangle(cornerRadius: 1)
                    .fill(Palette.detach)
                    .frame(width: 3, height: 32)

                // Expand chevron
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Palette.textMuted)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.name)
                            .font(Typo.heading(13))
                            .foregroundColor(Palette.text)
                            .lineLimit(1)

                        if session.attached {
                            Text("attached")
                                .font(Typo.mono(9))
                                .foregroundColor(Palette.detach)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Palette.detach.opacity(0.12))
                                )
                        }
                    }

                    Text(commandSummary)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                // Actions
                HStack(spacing: 4) {
                    Button(action: onKill) {
                        Text("Kill")
                            .angularButton(Palette.kill, filled: false)
                    }
                    .buttonStyle(.plain)

                    Button(action: onAttach) {
                        Text("Attach")
                            .angularButton(Palette.running)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassCard(hovered: isHovered)

            // Expanded pane list
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(session.panes) { pane in
                        paneRow(pane)
                    }
                }
                .padding(.leading, 36)
                .padding(.trailing, 10)
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Attach") { onAttach() }
            Divider()
            Button("Kill Session") { onKill() }
        }
    }

    private func paneRow(_ pane: TmuxPane) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(pane.isActive ? Palette.detach.opacity(0.7) : Palette.textMuted)
                .frame(width: 5, height: 5)

            Text(pane.title.isEmpty ? pane.currentCommand : pane.title)
                .font(Typo.mono(11))
                .foregroundColor(Palette.text)
                .lineLimit(1)

            Spacer()

            Text(pane.currentCommand)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textDim)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
