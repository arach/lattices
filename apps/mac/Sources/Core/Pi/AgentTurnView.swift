import AppKit
import SwiftUI

// Agent-session turn rendering — a self-contained Swift component for drawing a
// single turn in an agent conversation (user prompt, assistant response, or a
// system note). It is deliberately transport-agnostic: it renders a plain
// `AgentTurn` value and knows nothing about PiChatSession, pi RPC, HudAIClient,
// or any broker. Feed it a value, get a rendered turn.
//
// This is the slice worth sharing across surfaces (and eventually lifting into
// HudsonUI, themed via hudTheme). For now it renders with Lattices' Palette/Typo
// and composes the existing markdown / streaming / indicator atoms.

// MARK: - Model

enum AgentTurnRole: Equatable {
    case user
    case assistant
    case system
}

/// One turn in an agent conversation. A pure value — the rendering unit's only
/// input. Adapters (e.g. `PiChatMessageRow`) map their own message types onto it.
struct AgentTurn: Identifiable, Equatable {
    let id: UUID
    var role: AgentTurnRole
    /// Display label for the speaker — "You", "Assistant", or an agent name.
    var author: String
    var timestamp: Date
    var text: String
    /// True while this turn is still being produced (drives streaming visuals).
    var isStreaming: Bool
    /// Name of a tool the agent is currently running, if any.
    var toolActivity: String?

    init(
        id: UUID,
        role: AgentTurnRole,
        author: String,
        timestamp: Date,
        text: String,
        isStreaming: Bool = false,
        toolActivity: String? = nil
    ) {
        self.id = id
        self.role = role
        self.author = author
        self.timestamp = timestamp
        self.text = text
        self.isStreaming = isStreaming
        self.toolActivity = toolActivity
    }
}

// MARK: - View

struct AgentTurnView: View, Equatable {
    let turn: AgentTurn
    var style: PiChatStyle = .workspace
    @State private var copied = false

    static func == (lhs: AgentTurnView, rhs: AgentTurnView) -> Bool {
        lhs.turn == rhs.turn && lhs.style == rhs.style
    }

    var body: some View {
        switch turn.role {
        case .system:    systemRow
        case .user:      speakerRow(isAssistant: false)
        case .assistant: speakerRow(isAssistant: true)
        }
    }

    // MARK: System

    private var systemRow: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(turn.text)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textDim)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                )
            copyButton(size: 22, iconSize: 9)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    // MARK: User / Assistant
    //
    // Flat editorial thread (ported from OpenScout's HUDAssistantView): a glyph
    // + label + timestamp header, then the body indented beneath it. No bubbles,
    // no glow — hierarchy comes from the label row and the hanging indent, the
    // way a printed transcript reads.

    private var streaming: Bool { turn.isStreaming }

    @ViewBuilder
    private func speakerRow(isAssistant: Bool) -> some View {
        VStack(alignment: .leading, spacing: isAssistant ? 6 : 4) {
            header(isAssistant: isAssistant)

            if isAssistant, streaming, let tool = turn.toolActivity {
                PiChatToolChip(name: tool, compact: true)
                    .padding(.leading, 23)
            }

            bodyContent(isAssistant: isAssistant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 23)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(threadCard(streaming: isAssistant && streaming))
    }

    @ViewBuilder
    private func header(isAssistant: Bool) -> some View {
        HStack(alignment: .center, spacing: 7) {
            if isAssistant {
                LatticesMarkAvatar(size: 16, tint: Palette.running, isActive: streaming)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Palette.bg)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Palette.text.opacity(0.55)))
            }

            Text(turn.author)
                .font(Typo.geistMonoBold(10))
                .tracking(0.3)
                .foregroundColor(authorColor(isAssistant: isAssistant))

            if isAssistant {
                if streaming {
                    PiChatStreamingBadge()
                } else if let tool = turn.toolActivity {
                    PiChatToolChip(name: tool)
                }
            }

            Spacer(minLength: 8)

            Text(PiChatFormat.time(turn.timestamp))
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted.opacity(isAssistant ? 0.75 : 0.8))

            copyButton(size: 23, iconSize: 10)
        }
    }

    @ViewBuilder
    private func bodyContent(isAssistant: Bool) -> some View {
        if isAssistant {
            if turn.text.isEmpty, streaming {
                PiChatWorkingIndicator(label: "Composing")
            } else {
                PiChatFormattedText(turn.text, style: style, isStreaming: streaming)
            }
        } else {
            Text(turn.text)
                .font(Typo.reading(style.bodySize))
                .foregroundColor(Palette.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func authorColor(isAssistant: Bool) -> Color {
        guard isAssistant else { return Palette.text }
        return streaming ? Palette.running.opacity(0.95) : Palette.textDim
    }

    // Full-width turn container — a little structure without heavy bubbles: a
    // faint fill + hairline, brightening slightly while the assistant streams.
    private func threadCard(streaming: Bool) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.white.opacity(streaming ? 0.032 : 0.020))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(streaming ? Palette.running.opacity(0.22) : Palette.border, lineWidth: 0.5)
            )
    }

    private var copyableText: String {
        turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyButton(size: CGFloat, iconSize: CGFloat) -> some View {
        Button {
            copyTurnText()
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(copied ? Palette.running : Palette.textMuted)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color.white.opacity(copied ? 0.055 : 0.025))
                        .overlay(
                            Circle()
                                .strokeBorder(copied ? Palette.running.opacity(0.32) : Palette.border, lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : "Copy message")
        .disabled(copyableText.isEmpty)
        .opacity(copyableText.isEmpty ? 0.4 : 1)
    }

    private func copyTurnText() {
        let text = copyableText
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        DiagnosticLog.shared.success("PiChat: copied \(copyLabel.lowercased()) message to clipboard (\(text.count) chars)")
        withAnimation(.easeOut(duration: 0.12)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeOut(duration: 0.16)) { copied = false }
        }
    }

    private var copyLabel: String {
        switch turn.role {
        case .system:
            return "System"
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        }
    }
}
