import SwiftUI

// MARK: - Host tabs
//
// Compact chips for the Macs on the network. The name is the tab; status is
// only written when it changes a decision — needs you, or unreachable.
// Running and idle stay quiet so attention can actually read.

struct FleetChannelStrip: View {
    let channels: [FleetChannel]
    let order: [Int]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(order, id: \.self) { index in
                        if channels.indices.contains(index) {
                            FleetHostTab(
                                channel: channels[index],
                                isActive: index == currentIndex,
                                onSelect: { onSelect(index) }
                            )
                            .id(index)
                        }
                    }
                }
                .frame(minHeight: 44)
                .padding(.trailing, 4)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .onAppear { proxy.scrollTo(currentIndex, anchor: .center) }
            .onChange(of: currentIndex) { _, index in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Macs")
    }
}

private struct FleetHostTab: View {
    let channel: FleetChannel
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            DeckTactileFeedback.shared.rotaryTick()
            onSelect()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: channel.deviceIcon.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? DeckTheme.text : DeckTheme.textTertiary)
                    .frame(width: 16, alignment: .center)
                    .accessibilityHidden(true)

                Text(channel.deviceName)
                    .font(DeckTheme.secondary(.medium))
                    .foregroundStyle(isActive ? DeckTheme.text : DeckTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let status = statusCopy {
                    Text(status)
                        .font(DeckTheme.caption(.medium))
                        .foregroundStyle(statusColor)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                    .fill(isActive ? DeckTheme.card : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                    .strokeBorder(
                        isActive ? DeckTheme.hairlineStrong : Color.clear,
                        lineWidth: 1
                    )
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(FleetHostTabStyle())
        .accessibilityLabel(channel.deviceName)
        .accessibilityValue(channel.state.label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityHint(isActive ? "On deck" : "Switch to this Mac")
    }

    /// Only the states that ask the user to do something different.
    private var statusCopy: String? {
        switch channel.state {
        case .attn: return "Needs you"
        case .down: return "Unreachable"
        case .run, .idle: return nil
        }
    }

    private var statusColor: Color {
        switch channel.state {
        case .attn: return DeckTheme.accent
        case .down: return DeckTheme.error
        case .run, .idle: return DeckTheme.textTertiary
        }
    }
}

struct FleetHostTabStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
