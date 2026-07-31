import SwiftUI

// MARK: - Fleet feed
//
// `.ffeed` — what the agents did, newest first, across every Mac. Filterable
// down to just the things blocked on you; when that list empties the panel says
// so rather than showing an empty box.

struct FleetFeedPanel: View {
    let events: [FleetFeedEvent]
    let channels: [FleetChannel]
    let currentIndex: Int
    let filter: FleetFeedFilter
    let attentionCount: Int
    let onFilter: (FleetFeedFilter) -> Void
    let onSelect: (Int) -> Void

    var body: some View {
        FleetCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
            VStack(spacing: 0) {
                FleetCardHead(title: "fleet feed") {
                    Text("\(events.count) EVENTS")
                        .font(FleetV6.mono(10, .medium))
                        .tracking(1)
                        .monospacedDigit()
                        .foregroundStyle(FleetV6.fg4)
                    filterChips
                }

                if events.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // `.ff-filter`
    private var filterChips: some View {
        HStack(spacing: 0) {
            chip(title: "ALL", isOn: filter == .all, showsDivider: false) { onFilter(.all) }
            chip(title: "NEEDS YOU · \(attentionCount)", isOn: filter == .attention, showsDivider: true) {
                onFilter(.attention)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(FleetV6.brk, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func chip(title: String, isOn: Bool, showsDivider: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FleetV6.mono(9, .medium))
                .tracking(1.08)
                .foregroundStyle(isOn ? FleetV6.fg : FleetV6.fg4)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(isOn ? Color.white.opacity(0.07) : .clear)
                .overlay(alignment: .leading) {
                    if showsDivider { Rectangle().fill(FleetV6.brk2).frame(width: 1) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }

    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    FleetFeedRow(
                        event: event,
                        channelLabel: channels.indices.contains(event.channelIndex)
                            ? channels[event.channelIndex].channelLabel
                            : "—",
                        agentHue: channels.indices.contains(event.channelIndex)
                            ? channels[event.channelIndex].hue
                            : 0,
                        isOnCurrent: event.channelIndex == currentIndex,
                        showsRule: index < events.count - 1,
                        onTap: { onSelect(event.channelIndex) }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -4)
        .modifier(FleetWellFill(radius: 4))
        // The design fades the last 14px of the list so it reads as continuing
        // past the card edge.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.93),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // `.ff-empty`
    private var emptyState: some View {
        VStack(spacing: 9) {
            Text("QUEUE EMPTY")
                .font(FleetV6.mono(12.5, .medium))
                .tracking(2)
                .foregroundStyle(FleetV6.green)
            Text("nothing is waiting on you")
                .font(FleetV6.mono(11))
                .tracking(0.66)
                .foregroundStyle(FleetV6.fg4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// `.ff-row` — time, channel, agent, what happened.
private struct FleetFeedRow: View {
    let event: FleetFeedEvent
    let channelLabel: String
    let agentHue: Int
    let isOnCurrent: Bool
    let showsRule: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(event.time)
                    .font(FleetV6.mono(9.5))
                    .monospacedDigit()
                    .foregroundStyle(FleetV6.fg4)
                    .frame(width: 34, alignment: .leading)

                Text(channelLabel)
                    .font(FleetV6.mono(9.5, .medium))
                    .tracking(0.95)
                    .foregroundStyle(channelColor)
                    .frame(width: 46, alignment: .leading)

                HStack(spacing: 7) {
                    Circle()
                        .fill(FleetV6.agentHue(agentHue))
                        .frame(width: 5, height: 5)
                    Text(event.agent)
                        .font(FleetV6.mono(11, .medium))
                        .tracking(0.66)
                        .foregroundStyle(FleetV6.fg2)
                }
                .frame(width: 70, alignment: .leading)

                Text(event.text)
                    .font(FleetV6.mono(11))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if showsRule { FleetDottedRule(color: Color.white.opacity(0.06)) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(channelLabel), \(event.agent), \(event.text), \(event.time) ago")
    }

    private var channelColor: Color {
        if event.kind == .attn { return FleetV6.fg3 }
        if isOnCurrent { return FleetV6.fg2 }
        return FleetV6.fg4
    }

    private var textColor: Color {
        switch event.kind {
        case .hot, .attn: return FleetV6.fg2
        case .normal:     return FleetV6.fg3
        }
    }
}
