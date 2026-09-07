import DeckKit
import SwiftUI

// MARK: - Chat rail
//
// The remote-first deck's right column: one conversation with the Mac on deck.
// The agent's questions land as serif bubbles with their reply chips inline,
// your voice and typed turns sit right, and action outcomes run through as
// quiet system lines. This rail is what the agent console and the fleet feed
// were both circling.

/// One row in the rail, oldest at top.
enum FleetChatRow: Identifiable {
    /// An agent utterance — serif, left, unbubbled. Someone is talking to you.
    case agent(id: String, text: String, time: String)
    /// Your own sent turn — right-aligned bubble with a provenance caption.
    case user(id: String, text: String, via: String)
    /// An action outcome — small, quiet, full-width.
    case system(id: String, text: String, time: String)
    /// The open decision: agent bubble plus inline reply chips.
    case decision(id: String, decision: FleetDecision)
    /// The voice transcript while the Mac is still listening.
    case liveTranscript(id: String, text: String)

    var id: String {
        switch self {
        case .agent(let id, _, _), .user(let id, _, _), .system(let id, _, _),
             .decision(let id, _), .liveTranscript(let id, _):
            return id
        }
    }
}

/// A typed turn the user sent from the rail, kept per channel so the
/// conversation doesn't lose your half of it.
struct FleetUserMessage: Identifiable, Equatable {
    let id: String
    var text: String
    var via: String
    var time: String
}

extension FleetChannel {

    /// Activity-log tags that are watcher churn, not conversation. They stay
    /// on the Mac's own activity page; the rail only carries what a human
    /// would say out loud.
    private static let chatterlessTags: Set<String> = ["WIN", "PROC", "OCR", "TMUX"]

    /// Assemble the rail: outcomes from the activity log, then your sent
    /// turns, then the open decision, then the live voice transcript.
    func chatRows(userMessages: [FleetUserMessage], voicePhase: DeckVoicePhase?, voiceTranscript: String) -> [FleetChatRow] {
        var rows: [FleetChatRow] = []

        // Log lines are already chronological (the adapter reverses the log's
        // newest-first order); the rail shows the most recent few.
        let outcomes = logLines
            .filter { !Self.chatterlessTags.contains($0.tag.uppercased()) }
            .suffix(10)
        rows.append(contentsOf: outcomes.map {
            .system(id: $0.id, text: $0.message, time: $0.time)
        })

        if rows.isEmpty {
            rows.append(.agent(id: "task-\(id)", text: task, time: ""))
        }

        rows.append(contentsOf: userMessages.map {
            .user(id: $0.id, text: $0.text, via: $0.via)
        })

        if let decision {
            rows.append(.decision(id: "decision-\(id)", decision: decision))
        }

        if (voicePhase == .listening || voicePhase == .transcribing), !voiceTranscript.isEmpty {
            rows.append(.liveTranscript(id: "live-\(id)", text: voiceTranscript))
        }

        return rows
    }
}

struct FleetChatRail: View {
    let channel: FleetChannel
    var voicePhase: DeckVoicePhase?
    var voiceTranscript: String = ""
    var userMessages: [FleetUserMessage] = []
    var isBusy: Bool = false

    var onChoose: (Int) -> Void = { _ in }
    var onDefer: () -> Void = {}
    var onSendText: (String) -> Void = { _ in }
    var onPushToTalk: () -> Void = {}

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var isListening: Bool {
        voicePhase == .listening || voicePhase == .transcribing
    }

    var body: some View {
        VStack(spacing: 0) {
            head
            Divider().overlay(DeckTheme.hairline)
            log
            Divider().overlay(DeckTheme.hairline)
            inputBar
        }
        .background(FleetV6.wellBG)
        .clipShape(RoundedRectangle(cornerRadius: FleetV6.M.panelRadius, style: .continuous))
    }

    // MARK: Head

    private var head: some View {
        HStack(spacing: 8) {
            Text(channel.deviceName)
                .font(DeckTheme.secondary(.semibold))
                .foregroundStyle(FleetV6.fg)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(channel.state == .attn ? "needs you" : channel.agentName.lowercased())
                .font(DeckTheme.caption())
                .foregroundStyle(channel.state == .attn ? FleetV6.amber : FleetV6.fg3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Log

    private var log: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(channel.chatRows(userMessages: userMessages, voicePhase: voicePhase, voiceTranscript: voiceTranscript)) { row in
                        chatRow(row)
                            .id(row.id)
                    }
                }
                .padding(14)
            }
            .onChange(of: channel.chatRows(userMessages: userMessages, voicePhase: voicePhase, voiceTranscript: voiceTranscript).count) { _, _ in
                if let last = channel.chatRows(userMessages: userMessages, voicePhase: voicePhase, voiceTranscript: voiceTranscript).last {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func chatRow(_ row: FleetChatRow) -> some View {
        switch row {
        case .agent(_, let text, let time):
            VStack(alignment: .leading, spacing: 6) {
                whoLabel("Agent", time: time)
                Text(text)
                    .font(FleetV6.serif(14.5))
                    .foregroundStyle(FleetV6.fg)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .user(_, let text, let via):
            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .font(DeckTheme.body())
                    .foregroundStyle(FleetV6.fg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(FleetV6.keycap)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(via)
                    .font(DeckTheme.caption())
                    .foregroundStyle(FleetV6.fg3)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .system(_, let text, let time):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(FleetV6.fg4).frame(width: 4, height: 4)
                Text(text)
                    .font(DeckTheme.caption())
                    .foregroundStyle(FleetV6.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                if !time.isEmpty {
                    Text(time)
                        .font(DeckTheme.caption())
                        .foregroundStyle(FleetV6.fg3)
                }
            }

        case .decision(_, let decision):
            VStack(alignment: .leading, spacing: 8) {
                whoLabel("Agent · needs you", time: "", accent: true)
                Text(decision.question)
                    .font(FleetV6.serif(14.5))
                    .foregroundStyle(FleetV6.fg)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 6) {
                    ForEach(Array(decision.options.enumerated()), id: \.element.id) { index, option in
                        Button {
                            playDecisionTactile(for: option, at: index)
                            onChoose(index)
                        } label: {
                            Text(option.title)
                                .font(DeckTheme.caption(.semibold))
                                .foregroundStyle(index == 0 ? FleetV6.amber : FleetV6.fg)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(index == 0 ? DeckTheme.accent.opacity(0.14) : FleetV6.keycap)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(index == 0 ? FleetV6.amber : DeckTheme.hairline, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.title). \(option.detail)")
                    }
                    Button(action: {
                        DeckTactileFeedback.shared.decisionDeferred()
                        onDefer()
                    }) {
                        Text("Dismiss")
                            .font(DeckTheme.caption(.semibold))
                            .foregroundStyle(FleetV6.fg2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(FleetV6.keycap)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ask me later")
                }
            }

        case .liveTranscript(_, let text):
            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .font(DeckTheme.body())
                    .foregroundStyle(FleetV6.fg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DeckTheme.accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("listening…")
                    .font(DeckTheme.caption())
                    .foregroundStyle(FleetV6.amber)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func whoLabel(_ who: String, time: String, accent: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(who.uppercased())
                .font(DeckTheme.caption(.medium))
                .tracking(1.0)
                .foregroundStyle(accent ? FleetV6.amber : FleetV6.fg2)
            if !time.isEmpty {
                Text("· \(time)")
                    .font(DeckTheme.caption())
                    .foregroundStyle(FleetV6.fg3)
            }
        }
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button(action: onPushToTalk) {
                Image(systemName: isListening ? "mic.fill" : "mic")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isListening ? FleetV6.amber : FleetV6.fg2)
                    .frame(width: 34, height: 34)
                    .background(FleetV6.keycap)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(DeckTheme.hairline, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel("Toggle voice on \(channel.deviceName)")

            TextField("Type to \(channel.deviceName)…", text: $draft)
                .textFieldStyle(.plain)
                .font(DeckTheme.secondary())
                .foregroundStyle(FleetV6.fg)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(FleetV6.cardBG)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DeckTheme.hairline, lineWidth: 1)
                }
                .focused($fieldFocused)
                .onSubmit(send)

            Button(action: send) {
                Text("Send")
                    .font(DeckTheme.caption(.semibold))
                    .foregroundStyle(FleetV6.amber)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DeckTheme.accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        onSendText(text)
    }

    /// Primary picks get the approval chime; deferrals and secondary paths use the micro button pop.
    private func playDecisionTactile(for option: FleetDecisionOption, at index: Int) {
        let verb = option.verb.uppercased()
        let title = option.title.lowercased()
        if title.contains("reject") || title.contains("deny") || verb == "HOLD" {
            DeckTactileFeedback.shared.buttonPop()
        } else if index == 0 {
            DeckTactileFeedback.shared.decisionApproved()
        } else {
            DeckTactileFeedback.shared.buttonPop()
        }
    }
}

/// Chips wrap when a decision offers more than the rail is wide. SwiftUI has
/// no flow box; this is the smallest one that measures honestly.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

