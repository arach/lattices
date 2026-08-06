import SwiftUI

// MARK: - Command bay
//
// `.deck-tiles-wrap` — sets as tabs, tiles as the hero. Eight big targets in a
// 4×2 grid, sized to be hit at arm's length.

struct FleetCommandBay: View {
    let sets: [FleetCommandSet]
    let setIndex: Int
    let onSelectSet: (Int) -> Void
    let onTile: (FleetCommandTile) -> Void

    private var tiles: [FleetCommandTile] {
        sets.indices.contains(setIndex) ? sets[setIndex].tiles : []
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: FleetV6.M.tileGap), count: 4)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabs
            grid
        }
        .background(FleetV6.tilesWrapBG)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                Rectangle().fill(FleetV6.seam).frame(height: 1)
                Rectangle().fill(Color.white.opacity(0.03)).frame(height: 1).offset(y: 1)
            }
        }
    }

    // `.set-tabs`
    private var tabs: some View {
        HStack(spacing: 8) {
            FleetLabel(text: "COMMANDS")
                .padding(.trailing, 4)

            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                Button { onSelectSet(index) } label: {
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .foregroundStyle(FleetV6.fg4)
                        Text(set.key)
                            .foregroundStyle(index == setIndex ? FleetV6.fg : FleetV6.fg4)
                    }
                    .font(FleetV6.mono(10, .medium))
                    .tracking(1.4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                index == setIndex
                                    ? AnyShapeStyle(Color.white.opacity(0.07))
                                    : AnyShapeStyle(
                                        LinearGradient(
                                            colors: [FleetV6.rgb(0x101113), FleetV6.rgb(0x0B0C0D)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        index == setIndex ? Color.white.opacity(0.16) : FleetV6.brk2,
                                        lineWidth: 1
                                    )
                            }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == setIndex ? [.isSelected, .isButton] : .isButton)
            }

            Spacer(minLength: 8)

            Text("SET \(setIndex + 1) / \(max(sets.count, 1))")
                .font(FleetV6.mono(9.5, .medium))
                .tracking(1.33)
                .monospacedDigit()
                .foregroundStyle(FleetV6.fg4)
        }
        .padding(.horizontal, 15)
        .padding(.top, 10)
    }

    // `.deck-tiles`
    private var grid: some View {
        LazyVGrid(columns: columns, spacing: FleetV6.M.tileGap) {
            ForEach(tiles) { tile in
                FleetCommandTileView(tile: tile) { onTile(tile) }
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(height: FleetV6.M.tilesHeight + 22)
    }
}

/// `.tile` — domed icon cap on the left, title and caption stacked to its right.
struct FleetCommandTileView: View {
    let tile: FleetCommandTile
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tile.symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(FleetV6.tileIcon)
                    .frame(width: 31, height: 31)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(FleetV6.dome)
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(tile.title)
                        .font(FleetV6.mono(13.5, .medium))
                        .foregroundStyle(FleetV6.fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(tile.meta.uppercased())
                        .font(FleetV6.mono(8.5, .medium))
                        .tracking(1.02)
                        .foregroundStyle(FleetV6.fg4)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(FleetV6.tileFace)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(FleetV6.brk2, lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [Color.white.opacity(0.03), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(FleetPressStyle())
        .accessibilityLabel(tile.title)
        .accessibilityHint(tile.meta)
    }
}

// MARK: - Key row
//
// `.deck-keys` — the machined strip along the bottom of the enclosure. Sends
// real keystrokes to whichever Mac is on deck.

struct FleetKeyRow: View {
    let onKey: (String, [String]) -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                key("esc") { onKey("escape", []) }
                key("⌘C") { onKey("c", ["command"]) }
                key("⌘V") { onKey("v", ["command"]) }
                key("⌘Z") { onKey("z", ["command"]) }
                key("space", wide: true) { onKey("space", []) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 7) {
                symbolKey("arrow.left") { onKey("left", []) }
                symbolKey("arrow.up") { onKey("up", []) }
                symbolKey("arrow.down") { onKey("down", []) }
                symbolKey("arrow.right") { onKey("right", []) }
            }

            HStack(spacing: 7) {
                key("⌃") { onKey("control", []) }
                key("⌥") { onKey("option", []) }
                key("⇧") { onKey("shift", []) }
                key("⌘") { onKey("command", []) }
                key("↵ enter", wide: true) { onKey("return", []) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(FleetV6.bezel)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                Rectangle().fill(FleetV6.seam).frame(height: 1)
                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1).offset(y: 1)
            }
        }
    }

    private func key(_ label: String, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(FleetV6.mono(12))
                .foregroundStyle(FleetV6.fg2)
                .padding(.horizontal, 12)
                .frame(minWidth: wide ? 84 : 42, minHeight: 30)
                .background { FleetKeycapBackground() }
                .contentShape(Rectangle())
        }
        .buttonStyle(FleetPressStyle())
        .accessibilityLabel(label)
    }

    private func symbolKey(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FleetV6.fg2)
                .frame(minWidth: 42, minHeight: 30)
                .background { FleetKeycapBackground() }
                .contentShape(Rectangle())
        }
        .buttonStyle(FleetPressStyle())
        .accessibilityLabel(symbol.replacingOccurrences(of: "arrow.", with: "") + " arrow")
    }
}

// MARK: - Status bar
//
// `.fd-status` — the bottom rail. Left is where you are, right is what the
// fleet is doing; ATTN is a button, not a readout.

struct FleetStatusBar: View {
    let deviceName: String
    let routeLabel: String
    let attentionCount: Int
    let machineCount: Int
    let agentCount: Int
    let layout: FleetDeckLayout
    let isOnline: Bool
    let onAttention: () -> Void
    let onToggleLayout: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            group(showsDivider: false) {
                FleetDot(color: isOnline ? FleetV6.green : FleetV6.fg4, size: 6, glow: isOnline)
                Text(isOnline ? "ONLINE" : "OFFLINE")
                    .foregroundStyle(isOnline ? FleetV6.green : FleetV6.fg4)
            }

            group {
                Text(deviceName.uppercased()).foregroundStyle(FleetV6.fg2).lineLimit(1)
            }

            group {
                Text("ROUTE")
                Text(routeLabel).foregroundStyle(FleetV6.fg2)
            }

            Spacer(minLength: 0)

            Button(action: onAttention) {
                HStack(spacing: 7) {
                    Text(attentionCount > 0 ? "ATTN \(attentionCount)" : "ALL CLEAR")
                        .foregroundStyle(attentionCount > 0 ? FleetV6.amber : FleetV6.green)
                }
                .padding(.horizontal, 13)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) { Rectangle().fill(FleetV6.brk2).frame(width: 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(attentionCount == 0)

            group {
                Text("MACS")
                Text("\(machineCount)").foregroundStyle(FleetV6.fg2)
            }

            group {
                Text("AGENTS")
                Text("\(agentCount)").foregroundStyle(FleetV6.fg2)
            }

            Button(action: onToggleLayout) {
                HStack(spacing: 7) {
                    Text("VIEW ·")
                    Text(layout.rawValue.uppercased()).foregroundStyle(FleetV6.fg2)
                }
                .padding(.horizontal, 13)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) { Rectangle().fill(FleetV6.brk2).frame(width: 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle deck view")
            .accessibilityValue(layout.rawValue)
        }
        .font(FleetV6.mono(9.5, .medium))
        .tracking(1.14)
        .monospacedDigit()
        .foregroundStyle(FleetV6.fg3)
        .frame(height: FleetV6.M.statusHeight)
        .background(FleetV6.statusBG)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                Rectangle().fill(FleetV6.brk2).frame(height: 1)
                Rectangle().fill(Color.white.opacity(0.03)).frame(height: 1).offset(y: 1)
            }
        }
    }

    @ViewBuilder
    private func group<Content: View>(
        showsDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 7) { content() }
            .padding(.horizontal, 13)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .leading) {
                if showsDivider { Rectangle().fill(FleetV6.brk2).frame(width: 1) }
            }
    }
}
