import SwiftUI

/// Quick scene chips/cards (Deep Work, Code Review, Research, Meeting,
/// Stream, Wind Down). Tap to broadcast/apply. Visual treatment: tint dot,
/// name, summary, target hint chips. Distinct from routines (faster,
/// deterministic, no agent).
///
/// Size budget: ~200-260pt for 6 cards in 2-3 columns.
struct HomeScenesGrid: View {
    let scenes: [HomeScene]
    var onScene: ((HomeScene) -> Void)? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 10)
    ]

    private var subtitle: String {
        scenes.isEmpty
            ? "no scenes saved · summon on air"
            : "\(scenes.count) saved · ⌘1-⌘\(scenes.count) · summon on air"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                LatsSectionLabel(text: "Scenes")
                Spacer()
                Text(subtitle)
                    .font(LatsFont.mono(9))
                    .tracking(0.6)
                    .foregroundStyle(LatsPalette.textFaint)
            }

            if scenes.isEmpty {
                LatsCard(padding: 14) {
                    Text("no scenes saved yet")
                        .font(LatsFont.mono(10))
                        .foregroundStyle(LatsPalette.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(scenes) { scene in
                        SceneCard(scene: scene) {
                            onScene?(scene)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Card

private struct SceneCard: View {
    let scene: HomeScene
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            cardBody
        }
        .buttonStyle(.plain)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(scene.tint.color)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle().stroke(scene.tint.color.opacity(0.5), lineWidth: 1)
                    )
                    .padding(.top, 5)

                Text(scene.name)
                    .font(LatsFont.ui(13, weight: .semibold))
                    .foregroundStyle(LatsPalette.text)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let hotkey = scene.hotkey {
                    HotkeyPill(text: hotkey, tint: scene.tint.color)
                }
            }

            Text(scene.summary)
                .font(LatsFont.mono(10))
                .tracking(0.4)
                .foregroundStyle(LatsPalette.textDim)

            if !scene.targetHints.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(scene.targetHints.prefix(3)), id: \.self) { hint in
                        LatsBadge(text: hint, tint: LatsPalette.textDim)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(LatsPalette.surface)
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(scene.tint.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(scene.tint.color.opacity(0.32), lineWidth: 1)
        )
    }
}

// MARK: - Hotkey pill

private struct HotkeyPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(LatsFont.mono(10, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(tint.opacity(0.95))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3).fill(tint.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3).stroke(tint.opacity(0.38), lineWidth: 1)
            )
    }
}

#Preview("Scenes — full") {
    LatsBackground {
        ScrollView {
            HomeScenesGrid(scenes: HomeMock.scenes) { scene in
                print("scene tap: \(scene.name)")
            }
            .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Scenes — narrow") {
    LatsBackground {
        ScrollView {
            HomeScenesGrid(scenes: HomeMock.scenes)
                .padding(14)
                .frame(width: 420)
        }
    }
    .preferredColorScheme(.dark)
}
