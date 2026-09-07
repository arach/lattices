import DeckKit
import SwiftUI

// MARK: - Fleet Deck
//
// Remote-first anatomy, one layout: channel strip up top, then the trackpad
// you drive beside a conversation with the Mac on deck, a 6×2 grid of
// shortcuts, and one clustered key row. The ops console and fleet feed this
// replaces were both circling the same two things — a question from the
// agent, a command from you, an outcome — so that's what the deck is now.

struct FleetDeckView: View {
    @ObservedObject var model: FleetDeckModel

    var voicePhase: DeckVoicePhase?
    var voiceTranscript: String = ""
    var isBusy: Bool = false
    var isOnline: Bool = true

    var onClose: (() -> Void)?
    var onPushToTalk: () -> Void = {}
    var onTile: (FleetCommandTile) -> Void = { _ in }
    var onKey: (String, [String]) -> Void = { _, _ in }
    var onChoose: (FleetDecisionOption) -> Void = { _ in }
    var onSendText: (String) -> Void = { _ in }
    var onTrackpad: (DeckTrackpadEvent, Double, Double) -> Void = { _, _, _ in }
    var onWindowDrag: (Double, Double) -> Void = { _, _ in }

    var body: some View {
        VStack(spacing: FleetV6.M.stackGap) {
            topBar
            bodyRow
            FleetTileGrid(
                sets: model.sets,
                setIndex: model.setIndex,
                onSelectSet: { model.setIndex = $0 },
                onTile: onTile
            )
            FleetKeyRow(onKey: onKey)
        }
        .padding(.horizontal, FleetV6.M.padH)
        .padding(.top, FleetV6.M.padTop)
        .padding(.bottom, FleetV6.M.padBottom)
        .background(FleetV6.padBG)
    }

    // MARK: Host navigation

    private var topBar: some View {
        HStack(spacing: 8) {
            brandLockup

            Rectangle()
                .fill(DeckTheme.hairline)
                .frame(width: 1, height: 20)

            FleetChannelStrip(
                channels: model.channels,
                order: model.channelOrder,
                currentIndex: model.currentIndex,
                onSelect: { index in
                    withAnimation(.easeOut(duration: 0.18)) { model.select(index) }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.attentionIndices.count > 0 {
                attentionChip
            }

            closeButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: FleetV6.M.channelsRailHeight)
        .background {
            RoundedRectangle(cornerRadius: DeckTheme.radiusWell, style: .continuous)
                .fill(DeckTheme.well)
        }
        .clipShape(RoundedRectangle(cornerRadius: DeckTheme.radiusWell, style: .continuous))
    }

    private var brandLockup: some View {
        HStack(spacing: 7) {
            FleetDot(
                color: isOnline ? DeckTheme.textTertiary : DeckTheme.textDisabled,
                size: 6,
                glow: false
            )
            Text("Lats Deck")
                .font(DeckTheme.secondary(.semibold))
                .foregroundStyle(DeckTheme.textSecondary)
        }
        .padding(.leading, 8)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isOnline ? "Lats Deck, online" : "Lats Deck, offline")
    }

    private var attentionChip: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { model.focusAttention() }
        } label: {
            Text("Needs you · \(model.attentionIndices.count)")
                .font(DeckTheme.caption(.semibold))
                .foregroundStyle(DeckTheme.accent)
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .background(DeckTheme.accentFill)
                .clipShape(RoundedRectangle(cornerRadius: DeckTheme.radiusSmall, style: .continuous))
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(FleetHostTabStyle())
        .accessibilityLabel("Needs you, \(model.attentionIndices.count)")
        .accessibilityHint("Jump to the next Mac waiting on a decision")
    }

    private var closeButton: some View {
        Button {
            onClose?()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DeckTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(DeckTheme.control)
                .clipShape(RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .disabled(onClose == nil)
        .opacity(onClose == nil ? 0.35 : 1)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Close deck")
        .accessibilityHint("Return to Home")
    }

    // MARK: Body — trackpad you drive, conversation with the Mac

    private var bodyRow: some View {
        HStack(spacing: FleetV6.M.bodyGap) {
            FleetTrackpadHero(
                channel: model.current,
                onTrackpad: onTrackpad,
                onWindowDrag: onWindowDrag
            )

            if let channel = model.current {
                FleetChatRail(
                    channel: channel,
                    voicePhase: voicePhase,
                    voiceTranscript: voiceTranscript,
                    userMessages: model.userMessages[channel.id] ?? [],
                    isBusy: isBusy,
                    onChoose: { optionIndex in
                        withAnimation(.easeOut(duration: 0.2)) {
                            model.resolve(channelIndex: model.currentIndex, optionIndex: optionIndex, dispatch: onChoose)
                        }
                    },
                    onDefer: { withAnimation(.easeOut(duration: 0.18)) { model.deferDecision() } },
                    onSendText: { text in
                        model.recordUserMessage(text, via: "typed")
                        onSendText(text)
                    },
                    onPushToTalk: onPushToTalk
                )
                .frame(width: 380)
            } else {
                Text("No reachable Macs")
                    .font(FleetV6.mono(12))
                    .foregroundStyle(FleetV6.fg3)
                    .frame(width: 380)
                    .frame(maxHeight: .infinity)
                    .background(FleetV6.wellBG)
                    .clipShape(RoundedRectangle(cornerRadius: FleetV6.M.panelRadius, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }
}
