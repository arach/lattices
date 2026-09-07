import SwiftUI

/// Live screen thumbnails, one per reachable host. The roster says what a Mac
/// is; this strip says what it's *doing* — the glanceable layer between the
/// machine cards and entering a deck blind.
///
/// A host joins the row only once it has produced a frame: a Mac without the
/// screen-preview capability never gets an empty frame to apologise with.
/// Tap → enter that machine's deck.
struct HomeScreensRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let machines: [HomeMachine]
    let previews: [String: UIImage]
    var onEnterDeck: ((HomeMachine) -> Void)? = nil

    private var visibleMachines: [HomeMachine] {
        machines.filter { previews[$0.id] != nil }
    }

    var body: some View {
        if !visibleMachines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    LatsSectionLabel(text: "Screens")
                    Spacer(minLength: 0)
                    LatsBadge(text: "\(visibleMachines.count)", tint: LatsPalette.textDim)
                }

                // Cards share the row up to a cap — one frame alone should not
                // stretch into a full-width wallpaper strip.
                HStack(spacing: 12) {
                    ForEach(visibleMachines) { machine in
                        screenCard(machine)
                            .frame(maxWidth: 520)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func screenCard(_ machine: HomeMachine) -> some View {
        Button {
            DeckTactileFeedback.shared.tilePress(isAccent: false)
            onEnterDeck?(machine)
        } label: {
            ZStack {
                if let image = previews[machine.id] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: horizontalSizeClass == .compact ? 104 : 148)
            .clipShape(RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous))
            // Material chip reads over whatever the Mac is showing — a hard
            // dark capsule vanishes over a dark terminal frame. Overlaid after
            // the clip so it pins to the visible frame, not the image's bounds.
            .overlay(alignment: .bottomLeading) {
                Text(machine.name)
                    .font(DeckTheme.caption(.medium))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(.thinMaterial))
                    .padding(8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                    .stroke(DeckTheme.hairlineStrong, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open deck for \(machine.name)")
    }
}
