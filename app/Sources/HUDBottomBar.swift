import SwiftUI

// MARK: - HUDBottomBar (action playback tray)

struct HUDBottomBar: View {
    @ObservedObject var state: HUDState
    @ObservedObject private var handsOff = HandsOffSession.shared
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if !handsOff.recentActions.isEmpty {
                actionPlayback
            } else if state.voiceActive {
                voiceStatusView
            } else {
                shortcutsView
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(Palette.bg)
    }

    // MARK: - Action playback (what just happened)

    private var actionPlayback: some View {
        HStack(spacing: 8) {
            // Flash indicator
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(Palette.running)

            // Action chips showing what was executed
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(handsOff.recentActions.enumerated()), id: \.offset) { _, action in
                        executedChip(action)
                    }
                }
            }

            Spacer()

            // Dismiss playback
            Button {
                handsOff.recentActions = []
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Palette.textMuted)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Executed action chip

    private func executedChip(_ action: [String: Any]) -> some View {
        let intent = action["intent"] as? String ?? "action"
        let slots = action["slots"] as? [String: Any] ?? [:]
        let summary = actionSummary(intent: intent, slots: slots)

        return HStack(spacing: 5) {
            Image(systemName: iconForIntent(intent))
                .font(.system(size: 9))
                .foregroundColor(Palette.running)
            Text(summary)
                .font(Typo.mono(10))
                .foregroundColor(Palette.text)
                .lineLimit(1)
            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(Palette.running)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Palette.running.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Palette.running.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Voice active status

    private var voiceStatusView: some View {
        HStack(spacing: 8) {
            // Pulsing mic
            Image(systemName: "waveform")
                .font(.system(size: 11))
                .foregroundColor(voiceColor)

            Text(voiceLabel)
                .font(Typo.monoBold(10))
                .foregroundColor(voiceColor)

            if let transcript = handsOff.lastTranscript {
                Rectangle().fill(Palette.border).frame(width: 0.5, height: 20)
                Text(transcript)
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            if let response = handsOff.lastResponse {
                Text(response)
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textDim)
                    .lineLimit(1)
                    .frame(maxWidth: 250, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
    }

    private var voiceColor: Color {
        switch handsOff.state {
        case .idle:       return Palette.running
        case .connecting: return Palette.detach
        case .listening:  return Palette.running
        case .thinking:   return Palette.detach
        }
    }

    private var voiceLabel: String {
        switch handsOff.state {
        case .idle:       return "ready"
        case .connecting: return "connecting..."
        case .listening:  return "listening..."
        case .thinking:   return "thinking..."
        }
    }

    // MARK: - Shortcuts hint (default state)

    private var shortcutsView: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 10))
                .foregroundColor(Palette.textMuted.opacity(0.4))
            Text("V voice  / search  1-4 jump  ⇥ tab  ↵ go  ⎋ close")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted.opacity(0.5))
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private func actionSummary(intent: String, slots: [String: Any]) -> String {
        let target = slots["target"] as? String
            ?? slots["app"] as? String
            ?? slots["query"] as? String
            ?? ""
        let position = slots["position"] as? String ?? ""

        switch intent {
        case "tile_window":
            let parts = [target, position].filter { !$0.isEmpty }
            return "Tile \(parts.joined(separator: " "))"
        case "focus", "focus_app":
            return "Focus \(target)"
        case "launch", "launch_project":
            return "Launch \(target)"
        case "close_window":
            return "Close \(target)"
        case "maximize":
            return "Maximize \(target)"
        default:
            return target.isEmpty ? intent : "\(intent) \(target)"
        }
    }

    private func iconForIntent(_ intent: String) -> String {
        switch intent {
        case "tile_window":             return "rectangle.split.2x1"
        case "focus", "focus_app":      return "eye"
        case "launch", "launch_project": return "play.fill"
        case "close_window":            return "xmark.circle"
        case "maximize":               return "arrow.up.left.and.arrow.down.right"
        default:                        return "bolt"
        }
    }
}
