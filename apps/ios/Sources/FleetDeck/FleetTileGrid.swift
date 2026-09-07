import DeckKit
import SwiftUI

// MARK: - Tile grid
//
// The command bay compressed to its working form: a 6×2 grid of compact
// shortcut buttons for the Mac on deck. Sets (COMMAND / DEV / MEDIA / …) still
// switch above the grid when the Mac advertises more than one.

struct FleetTileGrid: View {
    let sets: [FleetCommandSet]
    let setIndex: Int
    let onSelectSet: (Int) -> Void
    let onTile: (FleetCommandTile) -> Void

    private let columns = 6
    private let rows = 2

    private var activeSet: FleetCommandSet? {
        sets.indices.contains(setIndex) ? sets[setIndex] : nil
    }

    var body: some View {
        VStack(spacing: 6) {
            if sets.count > 1 {
                setSwitcher
            }

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if let tile = activeSet?.tiles[safe: index] {
                                FleetGridTileButton(tile: tile) { onTile(tile) }
                            } else {
                                // Empty cells hold the grid's rhythm instead of
                                // collapsing the row under the last tile.
                                Color.clear.frame(maxWidth: .infinity).frame(height: 52)
                            }
                        }
                    }
                }
            }
        }
    }

    private var setSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                Button {
                    DeckTactileFeedback.shared.buttonPop()
                    onSelectSet(index)
                } label: {
                    Text(set.key)
                        .font(DeckTheme.caption(.medium))
                        .tracking(1.0)
                        .foregroundStyle(index == setIndex ? FleetV6.fg : FleetV6.fg3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(index == setIndex ? FleetV6.selectedFill : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

/// One compact shortcut button: icon chip, title, meta caption.
private struct FleetGridTileButton: View {
    let tile: FleetCommandTile
    let action: () -> Void

    var body: some View {
        Button(action: {
            DeckTactileFeedback.shared.buttonPop()
            action()
        }) {
            HStack(spacing: 10) {
                Image(systemName: tile.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FleetV6.tileIcon)
                    .frame(width: 28, height: 28)
                    .background(FleetV6.keycap)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(tile.title)
                        .font(DeckTheme.secondary(.medium))
                        .foregroundStyle(FleetV6.fg)
                        .lineLimit(1)
                    Text(tile.meta)
                        .font(DeckTheme.caption())
                        .tracking(0.6)
                        .foregroundStyle(FleetV6.fg3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(FleetV6.tileFace)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(DeckTheme.hairline, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(FleetPressStyle())
        .disabled(!tile.isEnabled)
        .opacity(tile.isEnabled ? 1 : 0.45)
        .accessibilityLabel(tile.title)
        .accessibilityHint(tile.meta)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
