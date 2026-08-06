import SwiftUI

/// What the deck looks like in the moment before it is the deck.
///
/// Two jobs, and the second one is the reason this exists rather than a spinner.
///
/// **Presenting and loading are separate costs, and the user should never pay
/// both at once.** The real deck is a large view tree; building it on the same
/// frame the cover is animating is what makes the transition drag. So the
/// transition renders this instead — a handful of rounded rectangles in the
/// deck's own geometry — and the expensive tree is built once the animation has
/// somewhere quiet to land.
///
/// **A wait should only announce itself once it is a wait.** Nothing here says
/// "loading" for the first fraction of a second. If the deck arrives quickly the
/// skeleton is never really perceived and the whole thing simply feels instant;
/// if it takes longer, a single line fades in saying what is actually happening.
/// Fast feels fast, slow becomes informative — rather than slow feeling slow.
struct DeckSkeleton: View {

    /// What to say if this ends up being a real wait. Nil says nothing.
    var narration: String?
    /// Set once the wait has gone on long enough to be worth explaining.
    var showsNarration: Bool = false

    @State private var breathe = false

    private var blockFill: Color {
        // Barely there. A skeleton that reads as strongly as content invites
        // people to try to read it.
        DeckTheme.card.opacity(breathe ? 0.85 : 0.55)
    }

    var body: some View {
        ZStack {
            DeckTheme.canvas.ignoresSafeArea()

            VStack(spacing: DeckTheme.Space.x12) {
                topBar
                console
                tiles
                bottomBar
            }
            .padding(DeckTheme.Space.margin)

            if showsNarration, let narration {
                VStack {
                    Spacer()
                    Text(narration)
                        .font(DeckTheme.secondary())
                        .foregroundStyle(DeckTheme.textSecondary)
                        .padding(.bottom, DeckTheme.Space.x32)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showsNarration)
        .onAppear {
            // A skeleton is allowed to promise imminent change, because that
            // promise is true. Slow and shallow, so it reads as breathing
            // rather than as something demanding attention.
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: DeckTheme.Space.x8) {
            block(width: 120, height: 18)
            Spacer(minLength: 0)
            block(width: 64, height: 18)
        }
        .frame(height: 26)
    }

    private var console: some View {
        RoundedRectangle(cornerRadius: DeckTheme.radiusWell, style: .continuous)
            .fill(blockFill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tiles: some View {
        HStack(spacing: DeckTheme.Space.cardGap) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                    .fill(blockFill)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 96)
    }

    private var bottomBar: some View {
        HStack(spacing: DeckTheme.Space.x8) {
            block(width: 90, height: 14)
            Spacer(minLength: 0)
            block(width: 140, height: 14)
        }
        .frame(height: 22)
    }

    private func block(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: DeckTheme.radiusSmall, style: .continuous)
            .fill(blockFill)
            .frame(width: width, height: height)
    }
}

/// Something went wrong on the way in, and saying so beats a skeleton that
/// never resolves. Escapable by construction — see the lifecycle review; a
/// state you cannot leave from the iPad is the bug class that started all this.
struct DeckUnavailable: View {
    let title: String
    let detail: String
    var onRetry: () -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack {
            DeckTheme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DeckTheme.Space.x16) {
                Text(title)
                    .font(DeckTheme.title())
                    .foregroundStyle(DeckTheme.text)
                Text(detail)
                    .font(DeckTheme.secondary())
                    .foregroundStyle(DeckTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DeckTheme.Space.x12) {
                    Button(action: onRetry) {
                        Text("Try again")
                            .font(DeckTheme.body(.semibold))
                            .foregroundStyle(DeckTheme.canvas)
                            .padding(.horizontal, DeckTheme.Space.x24)
                            .padding(.vertical, DeckTheme.Space.x12)
                            .background(
                                RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                                    .fill(DeckTheme.accent)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onClose) {
                        Text("Back")
                            .font(DeckTheme.body())
                            .foregroundStyle(DeckTheme.textSecondary)
                            .padding(.vertical, DeckTheme.Space.x12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 420)
            .padding(DeckTheme.Space.x32)
        }
    }
}
