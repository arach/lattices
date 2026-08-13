import DeckKit
import SwiftUI

// MARK: - Voice bar
//
// `.vbar` — dictation is the steering wheel. Hold the pad to talk, then pick
// which Mac's agent the words land on.

struct FleetVoiceBar: View {
    let phase: DeckVoicePhase?
    let transcript: String
    let channels: [FleetChannel]
    let routeIndex: Int
    let isBusy: Bool
    let onPushToTalk: () -> Void
    let onRoute: (Int) -> Void

    private var isListening: Bool {
        phase == .listening || phase == .transcribing
    }

    private var promptLabel: String {
        switch phase {
        case .listening:    return "Listening · release to send"
        case .transcribing: return "Transcribing"
        case .reasoning:    return "Thinking"
        case .speaking:     return "Speaking"
        case .idle, .none:  return "Hold to talk"
        }
    }

    var body: some View {
        FleetWell {
            HStack(spacing: 16) {
                pushToTalk
                FleetVoiceWave(active: isListening)

                VStack(alignment: .leading, spacing: 3) {
                    FleetLabel(text: promptLabel, size: 8.5, color: FleetV6.fg4)
                    HStack(spacing: 6) {
                        Text("›")
                            .font(FleetV6.mono(13.5))
                            .foregroundStyle(FleetV6.fg4)
                        Text(transcript.isEmpty ? "—" : transcript)
                            .font(DeckTheme.saidSecondary)
                            .foregroundStyle(FleetV6.fg)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if isListening {
                            FleetCaret(width: 7, height: 13)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    FleetLabel(text: "Route to", size: 8.5, color: FleetV6.fg3)
                    routeChips
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: FleetV6.M.voiceBarHeight)
    }

    // `.ptt`
    private var pushToTalk: some View {
        Button(action: onPushToTalk) {
            Image(systemName: "mic")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isListening ? FleetV6.green : FleetV6.fg2)
                .frame(width: 38, height: 38)
                .background {
                    Circle()
                        .fill(FleetV6.dome)
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.11), lineWidth: 1) }
                        .shadow(color: FleetV6.green.opacity(0.35), radius: 8)
                        .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Push to talk")
    }

    // `.vroute-chips`
    private var routeChips: some View {
        HStack(spacing: 0) {
            ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                chip(
                    title: channel.channelLabel.replacingOccurrences(of: " 0", with: " "),
                    isOn: routeIndex == index,
                    showsDivider: index > 0
                ) { onRoute(index) }
            }
            chip(title: "ALL", isOn: routeIndex == channels.count, showsDivider: !channels.isEmpty) {
                onRoute(channels.count)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(FleetV6.brk, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func chip(title: String, isOn: Bool, showsDivider: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FleetV6.mono(10, .medium))
                .tracking(1)
                .foregroundStyle(isOn ? FleetV6.fg : FleetV6.fg4)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isOn ? Color.white.opacity(0.07) : .clear)
                .overlay(alignment: .leading) {
                    if showsDivider {
                        Rectangle().fill(FleetV6.brk2).frame(width: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

/// `.vwave` — nine bars at the design's fixed heights, breathing only while the
/// mic is open.
struct FleetVoiceWave: View {
    var active: Bool

    private let heights: [CGFloat] = [0.30, 0.60, 0.90, 0.45, 0.75, 0.35, 0.85, 0.50, 0.25]

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1 / 20 : nil, paused: !active)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(Array(heights.enumerated()), id: \.offset) { index, base in
                    let wobble = active
                        ? 0.5 + 0.5 * abs(sin(phase * 2.2 + Double(index) * 0.55))
                        : 1.0
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 2.5, height: max(2, 22 * base * wobble))
                }
            }
            .frame(height: 22)
        }
        .accessibilityHidden(true)
    }
}

/// The blinking block caret the design uses on the transcript and the log tail.
struct FleetCaret: View {
    var width: CGFloat = 6
    var height: CGFloat = 11
    var color: Color = Color.white.opacity(0.5)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { context in
            let on = Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
            Rectangle()
                .fill(color)
                .frame(width: width, height: height)
                .opacity(on ? 1 : 0)
        }
        .accessibilityHidden(true)
    }
}
