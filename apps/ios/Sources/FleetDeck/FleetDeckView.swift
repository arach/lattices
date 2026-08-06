import DeckKit
import SwiftUI

// MARK: - Fleet Deck
//
// Native port of the design source `Lats Fleet Deck v6.html`
// (claude.ai/design project e010d8da-5dd8-4f3f-bb3e-a24dd4c75532).
//
// The premise: this deck steers *agents*, not cursors. Four Macs sit across the
// top as channels; whichever one needs a human decision sorts to the front and
// its question is answerable inline. Below it, one enclosure holds the console,
// the fleet feed, the command bay, and the key strip.

struct FleetDeckView: View {
    @ObservedObject var model: FleetDeckModel

    var voicePhase: DeckVoicePhase?
    var voiceTranscript: String = ""
    var isBusy: Bool = false
    var isOnline: Bool = true
    var showsTrackpadStrip: Bool = false
    /// Console buttons the Mac on deck can service; the rest render disabled.
    var enabledConsoleActions: Set<FleetConsoleAction> = []

    var onClose: (() -> Void)?
    var onPushToTalk: () -> Void = {}
    var onTile: (FleetCommandTile) -> Void = { _ in }
    var onKey: (String, [String]) -> Void = { _, _ in }
    var onChoose: (FleetDecisionOption) -> Void = { _ in }
    var onConsoleAction: (FleetConsoleAction) -> Void = { _ in }
    var onTrackpad: (DeckTrackpadEvent, Double, Double) -> Void = { _, _, _ in }

    var body: some View {
        VStack(spacing: FleetV6.M.stackGap) {
            topBar

            FleetChannelStrip(
                channels: model.channels,
                order: model.channelOrder,
                currentIndex: model.currentIndex,
                layout: model.layout,
                onSelect: { index in withAnimation(.easeOut(duration: 0.18)) { model.select(index) } }
            )

            FleetVoiceBar(
                phase: voicePhase,
                transcript: voiceTranscript,
                channels: model.channels,
                routeIndex: model.routeIndex,
                isBusy: isBusy,
                onPushToTalk: onPushToTalk,
                onRoute: { model.routeIndex = $0 }
            )

            deckPanel

            statusBar
        }
        .padding(.horizontal, FleetV6.M.padH)
        .padding(.top, FleetV6.M.padTop)
        .padding(.bottom, FleetV6.M.padBottom)
        .background(FleetV6.padBG)
        .overlay(alignment: .top) {
            // `#pad.bloom-on` — a soft wash off the top bezel.
            LinearGradient(colors: [Color.white.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
                .allowsHitTesting(false)
                .blendMode(.plusLighter)
        }
        .animation(.easeOut(duration: 0.25), value: model.layout)
    }

    // MARK: Top bar — `.fd-top`

    private var topBar: some View {
        HStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("LATS").font(FleetV6.mono(11, .bold)).foregroundStyle(FleetV6.fg)
                Text("·").font(FleetV6.mono(11)).foregroundStyle(FleetV6.fg4)
                Text("OPS").font(FleetV6.mono(11, .medium)).foregroundStyle(FleetV6.fg3)
            }
            .tracking(1.76)

            HStack(spacing: 6) {
                FleetDot(color: FleetV6.green, size: 4)
                Text(model.layout.label)
                    .font(FleetV6.mono(9, .medium))
                    .tracking(1.26)
                    .foregroundStyle(FleetV6.fg3)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(FleetV6.brk, lineWidth: 1)
                    }
            }

            Spacer(minLength: 8)

            Text("\(model.channels.count) MACS · \(agentCount) AGENTS")
                .font(FleetV6.mono(9, .medium))
                .tracking(1.08)
                .monospacedDigit()
                .foregroundStyle(FleetV6.fg3)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FleetV6.fg3)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close deck")
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .frame(height: FleetV6.M.topBarHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
        }
    }

    private var agentCount: Int {
        model.channels.filter { $0.state != .idle }.count
    }

    // MARK: Deck panel — `.deck-panel`

    private var deckPanel: some View {
        VStack(spacing: 0) {
            panelHead
            panelBody
            if showsTrackpadStrip {
                FleetTrackpadStrip(onTrackpad: onTrackpad)
                    .frame(height: FleetV6.M.trackpadHeight)
            }
            FleetCommandBay(
                sets: model.sets,
                setIndex: model.setIndex,
                onSelectSet: { model.setIndex = $0 },
                onTile: onTile
            )
            FleetKeyRow(onKey: onKey)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                FleetV6.deckPanelBG
                FleetPanelGrid()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FleetV6.M.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FleetV6.M.panelRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.85), radius: 30, y: 26)
    }

    // `.panel-head`
    private var panelHead: some View {
        HStack(spacing: 8) {
            FleetDot(color: FleetV6.agentHue(model.current?.hue ?? 0), size: 6)
            Text(model.current?.deviceName ?? "No Mac on deck")
                .font(FleetV6.mono(11.5))
                .foregroundStyle(FleetV6.fg)
                .lineLimit(1)

            Spacer(minLength: 12)

            if let channel = model.current {
                (
                    Text("\(channel.appName) · ").foregroundColor(FleetV6.fg3)
                        + Text(channel.fileName).foregroundColor(FleetV6.fg2)
                )
                .font(FleetV6.mono(11.5))
                .lineLimit(1)
                .truncationMode(.head)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .background(FleetV6.bezel)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(FleetV6.seam).frame(height: 1)
        }
    }

    // `.panel-body`
    private var panelBody: some View {
        GeometryReader { proxy in
            Group {
                if let channel = model.current {
                    switch model.layout {
                    case .ops:
                        HStack(spacing: FleetV6.M.bodyGap) {
                            console(channel, isRecent: model.lastResolvedIndex == model.currentIndex)
                                .frame(width: consoleWidth(for: proxy.size.width, target: FleetV6.M.consoleWidth))
                            FleetFeedPanel(
                                events: model.visibleFeed,
                                channels: model.channels,
                                currentIndex: model.currentIndex,
                                filter: model.feedFilter,
                                attentionCount: model.attentionIndices.count,
                                onFilter: { model.feedFilter = $0 },
                                onSelect: { index in withAnimation(.easeOut(duration: 0.18)) { model.select(index) } }
                            )
                        }
                    case .focus:
                        HStack(spacing: FleetV6.M.bodyGap) {
                            FleetFocusPane(channel: channel)
                            console(channel, isRecent: false)
                                .frame(width: consoleWidth(for: proxy.size.width, target: FleetV6.M.focusConsoleWidth))
                        }
                    }
                } else {
                    Text("No reachable Macs")
                        .font(FleetV6.mono(12))
                        .foregroundStyle(FleetV6.fg3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(.horizontal, FleetV6.M.panelBodyPadH)
        .padding(.vertical, FleetV6.M.panelBodyPadV)
        .frame(maxHeight: .infinity)
    }

    /// The design's fixed column widths, held as a share on narrower iPads so
    /// neither column collapses.
    private func consoleWidth(for available: CGFloat, target: CGFloat) -> CGFloat {
        guard available > 0 else { return target }
        return min(target, max(260, available * 0.36))
    }

    private func console(_ channel: FleetChannel, isRecent: Bool) -> some View {
        let queue = model.attentionIndices
        let position = queue.firstIndex(of: model.currentIndex).map { $0 + 1 }
        let nextBlocker = model.nextBlocker(from: model.currentIndex)

        return FleetAgentConsole(
            channel: channel,
            queuePosition: position,
            queueCount: queue.count,
            nextBlockerLabel: nextBlocker.flatMap { index in
                model.channels.indices.contains(index) ? model.channels[index].channelLabel : nil
            },
            justResolved: model.lastResolvedIndex == model.currentIndex,
            isRecent: isRecent && channel.decision == nil,
            enabledActions: enabledConsoleActions,
            onChoose: { optionIndex in
                withAnimation(.easeOut(duration: 0.2)) {
                    model.resolve(channelIndex: model.currentIndex, optionIndex: optionIndex, dispatch: onChoose)
                }
            },
            onDefer: { withAnimation(.easeOut(duration: 0.18)) { model.deferDecision() } },
            onApprove: { onConsoleAction(.approve) },
            onSteer: { onConsoleAction(.steer) },
            onRecap: { onConsoleAction(.recap) }
        )
    }

    // MARK: Status bar

    private var statusBar: some View {
        FleetStatusBar(
            deviceName: model.current?.deviceName ?? "—",
            routeLabel: model.routeLabel,
            attentionCount: model.attentionIndices.count,
            machineCount: model.channels.count,
            agentCount: agentCount,
            layout: model.layout,
            isOnline: isOnline,
            onAttention: { withAnimation(.easeOut(duration: 0.18)) { model.focusAttention() } },
            onToggleLayout: {
                withAnimation(.easeOut(duration: 0.25)) {
                    model.layout = model.layout == .ops ? .focus : .ops
                }
            }
        )
        .padding(.horizontal, -FleetV6.M.padH)
        .padding(.bottom, -FleetV6.M.padBottom)
    }
}

/// The three console buttons that are not a decision — they act on the agent
/// that is currently on deck.
enum FleetConsoleAction: Hashable {
    case approve, steer, recap
}

// MARK: - Trackpad strip
//
// `.deck-tp` — the optional pointer strip between the body and the command bay.
// Corner brackets, a centred label, and a crosshair that tracks the finger.

struct FleetTrackpadStrip: View {
    let onTrackpad: (DeckTrackpadEvent, Double, Double) -> Void

    @State private var crosshair: CGPoint?
    @State private var lastPoint: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [FleetV6.rgb(0x111316), FleetV6.rgb(0x0E1013)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ForEach(Array(brackets.enumerated()), id: \.offset) { _, alignment in
                    Color.clear.overlay(alignment: alignment) {
                        FleetBracket(alignment: alignment)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }

                Text("TRACKPAD")
                    .font(FleetV6.mono(10))
                    .tracking(4.2)
                    .foregroundStyle(FleetV6.fg4)
                    .opacity(0.45)

                if let crosshair {
                    Rectangle().fill(Color.white.opacity(0.14))
                        .frame(width: 1)
                        .position(x: crosshair.x, y: proxy.size.height / 2)
                    Rectangle().fill(Color.white.opacity(0.14))
                        .frame(height: 1)
                        .position(x: proxy.size.width / 2, y: crosshair.y)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        crosshair = value.location
                        if let lastPoint {
                            onTrackpad(.move, value.location.x - lastPoint.x, value.location.y - lastPoint.y)
                        }
                        lastPoint = value.location
                    }
                    .onEnded { _ in
                        crosshair = nil
                        lastPoint = nil
                    }
            )
        }
        .overlay(alignment: .top) { Rectangle().fill(FleetV6.seam).frame(height: 1) }
        .clipped()
        .accessibilityLabel("Trackpad")
    }

    private var brackets: [Alignment] { [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing] }
}

/// `.tp-bk` — a 13pt corner bracket, open toward the middle of the strip.
private struct FleetBracket: View {
    let alignment: Alignment

    private let size: CGFloat = 13
    private let weight: CGFloat = 1.5

    var body: some View {
        ZStack(alignment: alignment) {
            Color.clear.frame(width: size, height: size)
            Rectangle().fill(Color.white.opacity(0.09)).frame(width: size, height: weight)
            Rectangle().fill(Color.white.opacity(0.09)).frame(width: weight, height: size)
        }
        .frame(width: size, height: size)
    }
}
