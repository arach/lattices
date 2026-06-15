import SwiftUI

/// One cell in the placement grid, 0-indexed from the top-left.
struct GridCell: Equatable { let col: Int; let row: Int }

/// Selection shared between the overlay view (mouse drag) and the window
/// (keyboard ⇧-anchor). `anchor` is the first corner of an in-progress span and
/// `focus` the moving corner; both nil means nothing is selected yet.
final class GridPlacementSelection: ObservableObject {
    @Published var anchor: GridCell?
    @Published var focus: GridCell?
    var hasAnchor: Bool { anchor != nil }
    func reset() { anchor = nil; focus = nil }
}

/// A 4x4 placement target. The grid fills the active screen's visible frame, so
/// each cell sits exactly where the window will land. Hint keys mirror the
/// keyboard's own bottom-left 4x4 block (1234 / QWER / ASDF / ZXCV) for muscle
/// memory. A single key/click places one cell; dragging across cells (or ⇧ + a
/// second key) spans the window across a rectangular block.
struct GridPlacementView: View {
    static let cols = 4
    static let rows = 4
    static let spacing: CGFloat = 8

    let appName: String
    @ObservedObject var selection: GridPlacementSelection
    /// Inclusive span corners `(c0,r0)-(c1,r1)`. A single cell repeats the corner.
    let onSelect: (_ c0: Int, _ r0: Int, _ c1: Int, _ r1: Int) -> Void
    let onCancel: () -> Void

    /// Hint labels laid out [row][col]. Matches `GridPlacementWindow.keyMap`.
    static let keyLabels: [[String]] = [
        ["1", "2", "3", "4"],
        ["Q", "W", "E", "R"],
        ["A", "S", "D", "F"],
        ["Z", "X", "C", "V"],
    ]

    @State private var hover: GridCell?

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
            Text(hint)
                .font(Typo.mono(11))
                .foregroundColor(Palette.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.5)))
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
    }

    private var hint: String {
        if let r = selectedRect {
            let cols = r.maxCol - r.minCol + 1, rows = r.maxRow - r.minRow + 1
            return "span \(cols)×\(rows) · press end cell · Esc to cancel"
        }
        return "press a key · drag or ⇧ for a span · Esc to cancel"
    }

    private var grid: some View {
        GeometryReader { geo in
            let cw = (geo.size.width - Self.spacing * CGFloat(Self.cols - 1)) / CGFloat(Self.cols)
            let ch = (geo.size.height - Self.spacing * CGFloat(Self.rows - 1)) / CGFloat(Self.rows)
            ZStack(alignment: .topLeading) {
                ForEach(0..<(Self.cols * Self.rows), id: \.self) { idx in
                    let col = idx % Self.cols, row = idx / Self.cols
                    cell(col: col, row: row)
                        .frame(width: cw, height: ch)
                        .offset(x: CGFloat(col) * (cw + Self.spacing),
                                y: CGFloat(row) * (ch + Self.spacing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hover = cellAt(p, cw: cw, ch: ch)
                case .ended:         hover = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        selection.anchor = cellAt(g.startLocation, cw: cw, ch: ch)
                        selection.focus = cellAt(g.location, cw: cw, ch: ch)
                    }
                    .onEnded { g in
                        let a = selection.anchor ?? cellAt(g.startLocation, cw: cw, ch: ch)
                        let f = selection.focus ?? a
                        onSelect(a.col, a.row, f.col, f.row)
                        selection.reset()
                        hover = nil
                    }
            )
        }
    }

    private func cellAt(_ p: CGPoint, cw: CGFloat, ch: CGFloat) -> GridCell {
        let col = min(Self.cols - 1, max(0, Int(p.x / (cw + Self.spacing))))
        let row = min(Self.rows - 1, max(0, Int(p.y / (ch + Self.spacing))))
        return GridCell(col: col, row: row)
    }

    /// The rect currently being selected (drag/keyboard anchor), if any.
    private var selectedRect: (minCol: Int, minRow: Int, maxCol: Int, maxRow: Int)? {
        guard let a = selection.anchor, let f = selection.focus else { return nil }
        return (min(a.col, f.col), min(a.row, f.row), max(a.col, f.col), max(a.row, f.row))
    }

    private func isLit(col: Int, row: Int) -> Bool {
        if let r = selectedRect {
            return col >= r.minCol && col <= r.maxCol && row >= r.minRow && row <= r.maxRow
        }
        return hover == GridCell(col: col, row: row)
    }

    private func cell(col: Int, row: Int) -> some View {
        let lit = isLit(col: col, row: row)
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(lit ? Palette.running.opacity(0.22) : Color.white.opacity(0.05))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    lit ? Palette.running : Color.white.opacity(0.16),
                    lineWidth: lit ? 2 : 1
                )
            Text(Self.keyLabels[row][col])
                .font(Typo.monoBold(22))
                .foregroundColor(lit ? Palette.running : Palette.textDim)
        }
    }
}
