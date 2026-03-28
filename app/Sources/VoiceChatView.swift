import SwiftUI

/// A scrolling chat log for voice mode. Shows the running conversation between
/// user (transcripts), assistant (spoken responses), and system (silent info like
/// executed actions or search results).
///
/// Embeddable in both the standalone voice bar and the full HUD.
struct VoiceChatView: View {
    @ObservedObject var session: HandsOffSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(session.chatLog) { entry in
                        chatBubble(entry)
                            .id(entry.id)
                    }

                    // Live state indicator
                    if session.state == .listening {
                        listeningIndicator
                    } else if session.state == .thinking {
                        thinkingIndicator
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: session.chatLog.count) { _ in
                // Auto-scroll to bottom
                if let last = session.chatLog.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Chat bubble

    @ViewBuilder
    private func chatBubble(_ entry: VoiceChatEntry) -> some View {
        switch entry.role {
        case .user:
            HStack(alignment: .top, spacing: 6) {
                Text("you")
                    .font(Typo.monoBold(9))
                    .foregroundColor(Palette.text)
                    .frame(width: 28, alignment: .trailing)
                Text(entry.text)
                    .font(Typo.mono(11))
                    .foregroundColor(Palette.text)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }

        case .assistant:
            HStack(alignment: .top, spacing: 6) {
                Text("lat")
                    .font(Typo.monoBold(9))
                    .foregroundColor(Palette.running)
                    .frame(width: 28, alignment: .trailing)
                Text(entry.text)
                    .font(Typo.mono(11))
                    .foregroundColor(Palette.textMuted)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }

        case .system:
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7))
                    .foregroundColor(Palette.running.opacity(0.6))
                    .frame(width: 28, alignment: .trailing)
                Text(entry.text)
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textDim)
                    .textSelection(.enabled)
                if let detail = entry.detail {
                    Text(detail)
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            .opacity(0.7)
        }
    }

    // MARK: - Live indicators

    private var listeningIndicator: some View {
        HStack(spacing: 6) {
            Text("you")
                .font(Typo.monoBold(9))
                .foregroundColor(Palette.text)
                .frame(width: 28, alignment: .trailing)

            if let partial = session.lastTranscript, session.state == .listening {
                Text(partial)
                    .font(Typo.mono(11))
                    .foregroundColor(Palette.text.opacity(0.5))
            } else {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Palette.text)
                            .frame(width: 4, height: 4)
                            .opacity(0.4)
                            .animation(
                                .easeInOut(duration: 0.5)
                                    .repeatForever()
                                    .delay(Double(i) * 0.15),
                                value: session.state
                            )
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            Text("lat")
                .font(Typo.monoBold(9))
                .foregroundColor(Palette.running)
                .frame(width: 28, alignment: .trailing)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Palette.running)
                        .frame(width: 4, height: 4)
                        .opacity(0.4)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(i) * 0.15),
                            value: session.state
                        )
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Compact variant (for top/bottom bar embedding)

struct VoiceChatCompact: View {
    @ObservedObject var session: HandsOffSession
    /// How many recent entries to show
    var maxEntries: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(session.chatLog.suffix(maxEntries))) { entry in
                HStack(spacing: 4) {
                    switch entry.role {
                    case .user:
                        Text("you")
                            .font(Typo.monoBold(8))
                            .foregroundColor(Palette.text)
                        Text(entry.text)
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.text)
                            .lineLimit(1)
                    case .assistant:
                        Text("→")
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.running)
                        Text(entry.text)
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.textMuted)
                            .lineLimit(1)
                    case .system:
                        Text("⚡")
                            .font(.system(size: 7))
                        Text(entry.text)
                            .font(Typo.mono(8))
                            .foregroundColor(Palette.textDim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
