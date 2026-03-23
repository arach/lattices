import SwiftUI

// MARK: - HUDTopBar

struct HUDTopBar: View {
    @ObservedObject var state: HUDState
    @ObservedObject private var handsOff = HandsOffSession.shared
    @ObservedObject private var workspace = WorkspaceManager.shared
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Logo
            logo
                .padding(.leading, 16)

            // Voice status (when active)
            if state.voiceActive {
                voiceStatus
                    .padding(.leading, 12)
            }

            Spacer()

            // Layer strip (Hyprland-style)
            if let layers = workspace.config?.layers, !layers.isEmpty {
                layerStrip(layers)
                    .padding(.trailing, 12)
            }

            // Quick actions
            HStack(spacing: 6) {
                quickAction(icon: "rectangle.3.group", label: "Map", shortcut: "⌃⌥⇧⌘1") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        ScreenMapWindowController.shared.toggle()
                    }
                }

                quickAction(icon: "magnifyingglass", label: "Search", shortcut: "⌃⌥⇧⌘5") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        OmniSearchWindow.shared.toggle()
                    }
                }

                quickAction(icon: "text.justify.left", label: "Palette", shortcut: "⇧⌘M") {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        CommandPaletteWindow.shared.toggle()
                    }
                }
            }
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(Palette.bg)
    }

    // MARK: - Layer strip (Hyprland-style workspace bar)

    private func layerStrip(_ layers: [Layer]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(layers.enumerated()), id: \.element.id) { idx, layer in
                let isActive = idx == workspace.activeLayerIndex

                Button {
                    workspace.focusLayer(index: idx)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isActive ? Palette.running : Palette.textMuted.opacity(0.3))
                            .frame(width: 5, height: 5)

                        Text(layer.label)
                            .font(Typo.monoBold(9))
                            .foregroundColor(isActive ? Palette.text : Palette.textMuted)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isActive ? Palette.surfaceHov : Palette.surface.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(isActive ? Palette.running.opacity(0.4) : Palette.border.opacity(0.5), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Logo

    private var logo: some View {
        HStack(spacing: 7) {
            latticesGrid
            Text("lattices")
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.textMuted.opacity(0.6))
        }
    }

    /// 3×3 grid matching the menu bar icon — L-shape bright, rest dim
    private var latticesGrid: some View {
        let cellSize: CGFloat = 3
        let gap: CGFloat = 1.5
        let solidCells: Set<Int> = [0, 3, 6, 7, 8]

        return Canvas { ctx, _ in
            for row in 0..<3 {
                for col in 0..<3 {
                    let idx = row * 3 + col
                    let x = CGFloat(col) * (cellSize + gap)
                    let y = CGFloat(row) * (cellSize + gap)
                    let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                    let opacity: Double = solidCells.contains(idx) ? 0.5 : 0.15
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: 0.5),
                        with: .color(.white.opacity(opacity))
                    )
                }
            }
        }
        .frame(width: 3 * 3 + 2 * 1.5, height: 3 * 3 + 2 * 1.5)
    }

    // MARK: - Voice status

    private var voiceStatus: some View {
        HStack(spacing: 8) {
            // Pulsing dot + state
            Circle()
                .fill(voiceColor)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(voiceColor.opacity(0.4), lineWidth: 1)
                        .scaleEffect(handsOff.state == .listening ? 2.0 : 1.0)
                        .opacity(handsOff.state == .listening ? 0 : 1)
                        .animation(
                            handsOff.state == .listening
                                ? .easeOut(duration: 1.0).repeatForever(autoreverses: false)
                                : .default,
                            value: handsOff.state
                        )
                )

            Text(voiceLabel)
                .font(Typo.monoBold(9))
                .foregroundColor(voiceColor)

            // Dialogue: last user message → last response
            if let transcript = handsOff.lastTranscript {
                Rectangle().fill(Palette.border).frame(width: 0.5, height: 16)

                // What user said
                HStack(spacing: 3) {
                    Text("you")
                        .font(Typo.monoBold(8))
                        .foregroundColor(Palette.textMuted)
                    Text(transcript)
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.text)
                        .lineLimit(1)
                }
                .frame(maxWidth: 300, alignment: .leading)
            }

            if let response = handsOff.lastResponse {
                // What Lattices said back
                HStack(spacing: 3) {
                    Text("→")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.running)
                    Text(response)
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: 350, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(voiceColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(voiceColor.opacity(0.2), lineWidth: 0.5)
                )
        )
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
        case .connecting: return "connecting"
        case .listening:  return "listening"
        case .thinking:   return "thinking"
        }
    }

    // MARK: - Quick action button

    private func quickAction(icon: String, label: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(Typo.mono(10))
            }
            .foregroundColor(Palette.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("\(label) (\(shortcut))")
    }
}
