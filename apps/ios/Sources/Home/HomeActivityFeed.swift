import SwiftUI

/// Combined activity log — folds three signal streams into a single card so
/// the user gets one place to look instead of three half-empty sections:
///   1. Attention (pending decisions)            → amber, pinned at top
///   2. Recent    (history: command/voice/agent) → per-kind dot + ago
///   3. Agent     (narration / tool log)         → violet glyph, dim text
///
/// Each block keeps its own visual prominence; they're stacked inside one
/// LatsCard rather than fully homogenized so the kind of each row is still
/// legible at a glance.
struct HomeActivityFeed: View {
    let recent: [HomeRecentEntry]
    let agentFeed: [HomeAgentFeedEntry]
    let attention: [HomeAttentionItem]
    var onReplay: ((HomeRecentEntry) -> Void)? = nil

    private var hasAny: Bool {
        !recent.isEmpty || !agentFeed.isEmpty || !attention.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LatsSectionLabel(text: "Activity")
                Spacer()
                Text(metaLine)
                    .font(LatsFont.mono(9))
                    .tracking(0.5)
                    .foregroundStyle(LatsPalette.textFaint)
            }

            LatsCard(padding: 0) {
                if !hasAny {
                    Text("no activity yet")
                        .font(LatsFont.mono(10))
                        .foregroundStyle(LatsPalette.textFaint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        if !attention.isEmpty {
                            block(of: attention) { item, isLast in
                                ActivityAttentionRow(item: item)
                                if !isLast { LatsHairlineDivider() }
                            }
                            if !recent.isEmpty || !agentFeed.isEmpty {
                                LatsHairlineDivider()
                            }
                        }

                        if !recent.isEmpty {
                            block(of: recent) { entry, isLast in
                                Button { onReplay?(entry) } label: {
                                    ActivityRecentRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .disabled(onReplay == nil)
                                if !isLast { LatsHairlineDivider() }
                            }
                            if !agentFeed.isEmpty {
                                LatsHairlineDivider()
                            }
                        }

                        if !agentFeed.isEmpty {
                            block(of: agentFeed) { entry, isLast in
                                ActivityAgentRow(entry: entry)
                                if !isLast { LatsHairlineDivider() }
                            }
                        }
                    }
                }
            }
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if !attention.isEmpty { parts.append("\(attention.count) pending") }
        if !recent.isEmpty    { parts.append("\(recent.count) recent") }
        if !agentFeed.isEmpty { parts.append("\(agentFeed.count) agent") }
        return parts.isEmpty ? "last 24h" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func block<Item: Identifiable, RowContent: View>(
        of items: [Item],
        @ViewBuilder row: @escaping (Item, Bool) -> RowContent
    ) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
            row(item, idx == items.count - 1)
        }
    }
}

// MARK: - Attention row (pinned, amber prominence)

private struct ActivityAttentionRow: View {
    let item: HomeAttentionItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.tint.color)
                .frame(width: 14)

            Text("ATTENTION")
                .font(LatsFont.mono(9, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(LatsPalette.amber.opacity(0.85))
                .frame(width: 64, alignment: .leading)

            Text(item.label)
                .font(LatsFont.ui(12, weight: .semibold))
                .foregroundStyle(LatsPalette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 38)
        .background(LatsPalette.amber.opacity(0.05))
        .contentShape(Rectangle())
    }
}

// MARK: - Recent row (history, kind-colored dot + ago)

private struct ActivityRecentRow: View {
    let entry: HomeRecentEntry

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(entry.kind.dotColor)
                .frame(width: 6, height: 6)
                .frame(width: 14)

            Text(entry.kind.label.uppercased())
                .font(LatsFont.mono(9, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(LatsPalette.textFaint)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(LatsFont.ui(12, weight: .medium))
                    .foregroundStyle(LatsPalette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(LatsFont.mono(10))
                        .foregroundStyle(LatsPalette.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let target = entry.target {
                LatsBadge(text: target, tint: LatsPalette.textDim)
            }

            Text(entry.agoLabel)
                .font(LatsFont.mono(10))
                .foregroundStyle(LatsPalette.textFaint)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 38)
        .contentShape(Rectangle())
    }
}

// MARK: - Agent narration row (violet glyph, dim text)

private struct ActivityAgentRow: View {
    let entry: HomeAgentFeedEntry

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.glyph)
                .font(LatsFont.mono(11, weight: .semibold))
                .foregroundStyle(entry.tint.color)
                .frame(width: 14)

            Text("AGENT")
                .font(LatsFont.mono(9, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(LatsPalette.violet.opacity(0.7))
                .frame(width: 64, alignment: .leading)

            Text(entry.text)
                .font(LatsFont.mono(11))
                .foregroundStyle(LatsPalette.textDim)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 38)
        .contentShape(Rectangle())
    }
}

// MARK: - Previews

#Preview("Activity · all sources") {
    LatsBackground {
        ScrollView {
            HomeActivityFeed(
                recent: HomeMock.recent,
                agentFeed: HomeMock.agentFeed,
                attention: HomeMock.attention
            )
            .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Activity · attention only") {
    LatsBackground {
        ScrollView {
            HomeActivityFeed(
                recent: [],
                agentFeed: [],
                attention: HomeMock.attention
            )
            .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Activity · empty") {
    LatsBackground {
        ScrollView {
            HomeActivityFeed(recent: [], agentFeed: [], attention: [])
                .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}
