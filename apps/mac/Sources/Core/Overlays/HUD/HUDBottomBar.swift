import SwiftUI

// MARK: - HUDBottomBar (action playback tray)

struct HUDBottomBar: View {
    @ObservedObject var state: HUDState
    @ObservedObject private var handsOff = HandsOffSession.shared
    @ObservedObject private var liveTabs = LiveTabGroupStore.shared
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if state.tileMode {
                tileModeView
            } else if !handsOff.recentActions.isEmpty {
                actionPlayback
            } else if let feedback = state.feedbackMessage {
                feedbackView(feedback)
            } else if state.voiceActive {
                voiceStatusView
            } else {
                shortcutsView
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(HUDPanelBackground())
        .hudEdgeGlow()
        .overlay(alignment: .trailing) {
            if !liveTabs.groups.isEmpty {
                liveTabGroupingStrip
                    .padding(.trailing, 12)
            }
        }
    }

    private var liveTabGroupingStrip: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(HUDChrome.cyan)
                Text("GROUPINGS")
                    .font(Typo.monoBold(8))
                    .tracking(0.8)
                    .foregroundStyle(Palette.textDim)
            }

            ForEach(liveTabs.groups.prefix(3)) { group in
                liveTabGroupingMenu(group)
            }

            if liveTabs.groups.count > 3 {
                Text("+\(liveTabs.groups.count - 3)")
                    .font(Typo.monoBold(8))
                    .foregroundStyle(Palette.textDim)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.34))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(HUDChrome.glassStrokeSoft, lineWidth: 0.6)
                )
        )
    }

    private func liveTabGroupingMenu(_ group: LiveTabGroup) -> some View {
        Menu {
            Button {
                liveTabs.activate(id: group.id)
                liveTabs.setGuideVisible(true, id: group.id)
            } label: {
                Label("Show Floating Tab Tools", systemImage: "pin.fill")
            }

            Button {
                liveTabs.toggleLayout(id: group.id)
            } label: {
                Label(group.isExpanded ? "Return to Tabs" : "Split Inside Group Bounds",
                      systemImage: group.isExpanded ? "rectangle.stack.fill" : "rectangle.split.2x1")
            }

            Button {
                liveTabs.toggleGuideVisibility(id: group.id)
            } label: {
                Label(group.isGuideVisible ? "Hide Floating Tools" : "Keep Floating Tools Visible",
                      systemImage: group.isGuideVisible ? "pin.slash" : "pin.fill")
            }

            Divider()

            Button(role: .destructive) {
                liveTabs.delete(id: group.id)
            } label: {
                Label("Ungroup", systemImage: "minus.circle")
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(group.id == liveTabs.activeGroupID ? HUDChrome.cyan : Palette.textMuted)
                    .frame(width: 5, height: 5)
                Text(group.name)
                    .font(Typo.heading(10))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text("\(group.members.count)")
                    .font(Typo.monoBold(8))
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(group.id == liveTabs.activeGroupID ? HUDChrome.cyan.opacity(0.10) : Color.white.opacity(0.045))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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
            RoundedRectangle(cornerRadius: 8)
                .fill(Palette.running.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Palette.running.opacity(0.24), lineWidth: 0.5)
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

    // MARK: - Interaction feedback

    private func feedbackView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.running)
            Text(message)
                .font(Typo.monoBold(10))
                .foregroundColor(Palette.text)
                .lineLimit(1)
            Spacer()
            Text("working")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textDim)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Tile mode

    private var tileModeView: some View {
        HStack(spacing: 8) {
            // Mode indicator
            HStack(spacing: 4) {
                Image(systemName: "rectangle.split.2x2")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.running)
                Text("TILE")
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.running)
            }

            Rectangle().fill(Palette.border).frame(width: 0.5, height: 20)

            // Key hints
            HStack(spacing: 6) {
                tileKey("H", "←")
                tileKey("J", "↓")
                tileKey("K", "↑")
                tileKey("L", "→")
                tileKey("F", "max")
            }

            Rectangle().fill(Palette.border).frame(width: 0.5, height: 20)

            HStack(spacing: 6) {
                tileKey("Y", "◸")
                tileKey("U", "◹")
                tileKey("B", "◺")
                tileKey("N", "◿")
            }

            Spacer()

            Text("⎋ done")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
        .padding(.horizontal, 16)
    }

    private func tileKey(_ key: String, _ hint: String) -> some View {
        HStack(spacing: 2) {
            Text(key)
                .font(Typo.geistMonoBold(9))
                .foregroundColor(Palette.text)
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.055))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
            Text(hint)
                .font(Typo.mono(8))
                .foregroundColor(Palette.textDim)
        }
    }

    // MARK: - Shortcuts hint (default state)

    private var shortcutsView: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 10))
                .foregroundColor(Palette.textMuted.opacity(0.4))
            Text("V voice  / search  ⌥X theme  C chrome  ↵ go  ⎋ close")
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
