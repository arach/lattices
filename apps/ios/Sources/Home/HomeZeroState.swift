import SwiftUI

/// Zero state — no Macs paired yet. Welcoming first-run surface that shows
/// what Lats will look like once connected. Pairing prompt + sample
/// preview. Not just an empty parking lot.
///
/// Three blocks, vertically stacked:
///   1. Hero    — large LATS mark, subtitle, "scanning network…" pulse
///   2. Preview — labeled mini fleet wireframe (HomeMock.fleetTwo)
///   3. CTA     — Pair button + Open settings link + faint hint
///
/// Size budget: full screen, fits iPad portrait without scrolling.
struct HomeZeroState: View {
    var onPair: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil

    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            hero
            Spacer(minLength: 36)
            preview
            Spacer(minLength: 36)
            cta
            Spacer(minLength: 24)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            Text("Lats Deck")
                .font(DeckTheme.title(.semibold))
                .foregroundStyle(LatsPalette.text)

            Text("Your iPad remote for paired Macs")
                .font(DeckTheme.secondary())
                .foregroundStyle(LatsPalette.textDim)

            HStack(spacing: 8) {
                Circle()
                    .fill(DeckTheme.accent)
                    .frame(width: 6, height: 6)
                    .opacity(pulse ? 1.0 : 0.25)
                Text("Looking for Macs on this network")
                    .font(DeckTheme.caption())
                    .foregroundStyle(LatsPalette.textFaint)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(LatsPalette.hairline2)
                    .frame(width: 18, height: 1)
                LatsSectionLabel(text: "Preview · once connected")
                Rectangle()
                    .fill(LatsPalette.hairline2)
                    .frame(height: 1)
            }

            HStack(spacing: 10) {
                ForEach(HomeMock.fleetTwo) { machine in
                    miniMachineCard(machine)
                }
                miniMachineCard(placeholderSlot)
                    .opacity(0.55)
            }
        }
        .frame(maxWidth: 520)
    }

    private var placeholderSlot: HomeMachine {
        HomeMachine(
            id: "slot",
            name: "—",
            host: "available",
            icon: "plus",
            status: .offline,
            isForeground: false,
            scene: nil,
            focusedApp: nil,
            focusedWindow: nil,
            lastAction: nil,
            lastActionAgo: nil,
            agentState: .idle,
            attentionCount: 0,
            latencyMs: nil
        )
    }

    private func miniMachineCard(_ m: HomeMachine) -> some View {
        LatsCard(padding: 12, radius: 7) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: m.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(m.status.tint)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(m.status.tint.opacity(0.14))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(m.status.tint.opacity(0.3), lineWidth: 1)
                        )
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(m.name)
                        .font(LatsFont.mono(11, weight: .semibold))
                        .foregroundStyle(LatsPalette.text)
                        .lineLimit(1)
                    Text(m.host)
                        .font(LatsFont.mono(9))
                        .foregroundStyle(LatsPalette.textFaint)
                        .lineLimit(1)
                }

                LatsBadge(text: m.status.label, tint: m.status.tint, dot: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - CTA

    private var cta: some View {
        VStack(spacing: 14) {
            LatsButton(
                title: "Add a host",
                icon: "plus.circle",
                style: .primary(.amber)
            ) {}
                onPair?()
            }

            Button(action: { onSettings?() }) {
                Text("Open settings")
                    .font(DeckTheme.secondary())
                    .foregroundStyle(LatsPalette.textDim)
                    .underline(false)
            }
            .buttonStyle(.plain)

            Text("No paired Macs yet")
                .font(DeckTheme.caption())
                .foregroundStyle(LatsPalette.textFaint)
                .padding(.top, 4)
        }
    }
}

#Preview("Zero state — portrait") {
    LatsBackground(grid: false) {
        HomeZeroState(onPair: {}, onSettings: {})
    }
    .preferredColorScheme(.dark)
}

#Preview("Zero state — no settings") {
    LatsBackground {
        HomeZeroState(onPair: {})
    }
    .preferredColorScheme(.dark)
}
