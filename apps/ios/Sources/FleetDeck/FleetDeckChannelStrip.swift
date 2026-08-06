import SwiftUI

// MARK: - Channel strip
//
// Compact, horizontally scrollable host rail. Selecting a Mac also makes it the
// route for commands and voice, so the deck does not need a second destination
// picker.

struct FleetChannelStrip: View {
    let channels: [FleetChannel]
    let order: [Int]
    let currentIndex: Int
    /// Retained for source compatibility; both layouts use the compact rail.
    let layout: FleetDeckLayout
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 6) {
                ForEach(order, id: \.self) { index in
                    if channels.indices.contains(index) {
                        FleetChannelColumn(
                            channel: channels[index],
                            isActive: index == currentIndex,
                            isRail: true,
                            onSelect: { onSelect(index) }
                        )
                        .frame(width: 210)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
        .frame(height: 44)
    }
}

private struct FleetChannelColumn: View {
    let channel: FleetChannel
    let isActive: Bool
    let isRail: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                head
                if !isRail {
                    body_
                    Spacer(minLength: 0)
                    foot
                }
            }
            .padding(.top, isRail ? 0 : 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isRail ? .leading : .topLeading)
            .background {
                if isActive {
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.05), location: 0),
                            .init(color: Color.white.opacity(0.012), location: 0.55),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The design makes the active column non-interactive with `cursor:default`,
        // not by dimming it — `.disabled` would fade the whole label.
        .allowsHitTesting(!isActive)
        .accessibilityLabel("\(channel.channelLabel), \(channel.deviceName)")
        .accessibilityValue("\(channel.agentName), \(channel.state.label)")
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    // `.chan-head`
    private var head: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(channel.channelLabel)
                    .font(FleetV6.mono(10, .medium))
                    .tracking(1.4)
                    .foregroundStyle(FleetV6.fg4)
                    .fixedSize()

                Image(systemName: channel.deviceIcon.symbol)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(FleetV6.fg3)
                    .frame(width: 20, alignment: .leading)

                Text(channel.deviceName)
                    .font(FleetV6.mono(12.5, .medium))
                    .foregroundStyle(FleetV6.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                FleetChannelStatus(state: channel.state, isActive: isActive)
            }
            .padding(.horizontal, 15)
            .padding(.bottom, isRail ? 0 : 9)

            if !isRail {
                FleetDottedRule(color: Color.white.opacity(0.09))
                    .padding(.horizontal, 15)
            }
        }
        .frame(maxHeight: isRail ? .infinity : nil)
    }

    // `.chan-body`
    private var body_: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(FleetV6.agentHue(channel.hue))
                    .frame(width: 5, height: 5)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(channel.agentName)
                    .font(FleetV6.mono(16, .medium))
                    .foregroundStyle(FleetV6.fg)
                Text(channel.appName)
                    .font(FleetV6.mono(10))
                    .tracking(1)
                    .foregroundStyle(FleetV6.fg4)
                    .lineLimit(1)
            }
            .padding(.top, 10)

            Text(channel.task)
                .font(FleetV6.mono(11))
                .foregroundStyle(FleetV6.fg3)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 4)

            HStack(spacing: 7) {
                FleetDot(color: FleetV6.fg3, size: 5)
                Text(channel.lastEventText)
                    .font(FleetV6.mono(10.5))
                    .foregroundStyle(FleetV6.fg3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(channel.lastEventTime)
                    .font(FleetV6.mono(9.5))
                    .monospacedDigit()
                    .foregroundStyle(FleetV6.fg4)
            }
            .padding(.top, 9)
        }
        .padding(.horizontal, 15)
    }

    // `.chan-foot`
    private var foot: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                FleetDot(color: isActive ? FleetV6.fg2 : FleetV6.fg4, size: 6)
                Text(isActive ? "ON DECK" : "TAP TO SWITCH")
                    .font(FleetV6.mono(9.5, .medium))
                    .tracking(1.1)
                    .foregroundStyle(isActive ? FleetV6.fg2 : FleetV6.fg4)
            }
            Spacer(minLength: 4)
            Text(channel.footerMetrics)
                .font(FleetV6.mono(9.5, .medium))
                .tracking(1.1)
                .monospacedDigit()
                .foregroundStyle(FleetV6.fg4)
                .lineLimit(1)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(FleetV6.brk2).frame(height: 1)
        }
    }
}

/// `.chan-st` — the state readout. The active channel's RUNNING dot is the only
/// place the phosphor green appears in the strip.
struct FleetChannelStatus: View {
    let state: FleetChannelState
    var isActive: Bool = false

    private var color: Color {
        switch state {
        case .run:  return FleetV6.fg3
        case .attn: return FleetV6.amber
        case .idle: return FleetV6.fg4
        case .down: return FleetV6.red
        }
    }

    private var dotColor: Color {
        switch state {
        case .run:  return isActive ? FleetV6.green : FleetV6.fg3
        case .attn: return FleetV6.amber
        case .idle: return FleetV6.fg4
        case .down: return FleetV6.red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            FleetDot(color: dotColor, size: 5, glow: state == .attn)
            Text(state.label)
                .font(FleetV6.mono(9, .medium))
                .tracking(1.26)
                .foregroundStyle(color)
                .fixedSize()
        }
    }
}
