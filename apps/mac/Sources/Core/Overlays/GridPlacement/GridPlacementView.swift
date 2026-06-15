import SwiftUI

/// A 4x4 placement target. The grid fills the active screen's visible frame, so
/// each cell sits exactly where the window will land. Hint keys mirror the
/// keyboard's own bottom-left 4x4 block (1234 / QWER / ASDF / ZXCV) for muscle
/// memory; clicking a cell works too.
struct GridPlacementView: View {
    let appName: String
    /// (column, row), both 0-indexed from the top-left.
    let onSelect: (Int, Int) -> Void
    let onCancel: () -> Void

    /// Hint labels laid out [row][col]. Matches `GridPlacementWindow.keyMap`.
    static let keyLabels: [[String]] = [
        ["1", "2", "3", "4"],
        ["Q", "W", "E", "R"],
        ["A", "S", "D", "F"],
        ["Z", "X", "C", "V"],
    ]

    @State private var hoverIndex: Int? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()

            VStack(spacing: 10) {
                header
                grid
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "rectangle.split.3x3")
                .foregroundColor(Palette.running)
            Text("Place \(appName)")
                .font(Typo.monoBold(12))
                .foregroundColor(Palette.text)
                .lineLimit(1)
            Text("press a key · Esc to cancel")
                .font(Typo.mono(11))
                .foregroundColor(Palette.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.5)))
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
    }

    private var grid: some View {
        VStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { col in
                        cell(col: col, row: row)
                    }
                }
            }
        }
    }

    private func cell(col: Int, row: Int) -> some View {
        let idx = row * 4 + col
        let isHover = hoverIndex == idx
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(isHover ? Palette.running.opacity(0.22) : Color.white.opacity(0.05))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isHover ? Palette.running : Color.white.opacity(0.16),
                    lineWidth: isHover ? 2 : 1
                )
            Text(Self.keyLabels[row][col])
                .font(Typo.monoBold(22))
                .foregroundColor(isHover ? Palette.running : Palette.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoverIndex = idx
            } else if hoverIndex == idx {
                hoverIndex = nil
            }
        }
        .onTapGesture { onSelect(col, row) }
    }
}
