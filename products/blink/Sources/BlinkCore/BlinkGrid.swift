import CoreGraphics
import Foundation

/// One placement primitive; slots and named zones are aliases over it.
///
/// A `GridPlacement` is a rectangular block in a `columns × rows` grid: the cells
/// from `(col, row)` spanning `colSpan × rowSpan`, with `(0, 0)` at the TOP-LEFT
/// (reading order). Blink's `slot 1…9` is sugar for a single cell in a 3×3 grid;
/// halves, thirds, quarters, and `center` are other `columns × rows` shapes. This
/// keeps every placement reproducible from a tiny description — the property that
/// lets agents *and* the user build spatial memory.
public struct GridPlacement: Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    public var col: Int
    public var row: Int
    public var colSpan: Int
    public var rowSpan: Int

    public init(columns: Int, rows: Int, col: Int, row: Int, colSpan: Int = 1, rowSpan: Int = 1) {
        self.columns = columns
        self.rows = rows
        self.col = col
        self.row = row
        self.colSpan = colSpan
        self.rowSpan = rowSpan
    }
}

/// Pure desk-grid geometry, shared by the visual `GridOverlay` and programmatic
/// placement so the two can never drift. All frames come back in the SAME
/// coordinate space as the `visibleFrame` passed in (pass a screen's global
/// `visibleFrame` to get global frames ready for `NotePanel.animateLock`).
///
/// Design credit: the "one primitive + aliases + spans, declarative & deterministic"
/// shape is adapted from Lattices' placement engine — the ideas, not the code.
public enum BlinkGrid {
    /// Outer breathing room and inter-cell gap, as fractions of the visible area.
    public static let marginFraction: CGFloat = 0.04
    public static let gapFraction: CGFloat = 0.02

    /// The global frame for a grid block. Column/row/spans are clamped into range
    /// so an out-of-bounds request still yields a valid on-grid frame.
    public static func frame(for placement: GridPlacement, in visibleFrame: CGRect) -> CGRect {
        let cols = max(1, placement.columns)
        let rows = max(1, placement.rows)
        let marginX = visibleFrame.width * marginFraction
        let marginY = visibleFrame.height * marginFraction
        let gapX = visibleFrame.width * gapFraction
        let gapY = visibleFrame.height * gapFraction
        let inner = visibleFrame.insetBy(dx: marginX, dy: marginY)
        let cellW = (inner.width - CGFloat(cols - 1) * gapX) / CGFloat(cols)
        let cellH = (inner.height - CGFloat(rows - 1) * gapY) / CGFloat(rows)

        let c = min(max(0, placement.col), cols - 1)
        let r = min(max(0, placement.row), rows - 1)
        let cs = min(max(1, placement.colSpan), cols - c)
        let rs = min(max(1, placement.rowSpan), rows - r)

        let x = inner.minX + CGFloat(c) * (cellW + gapX)
        let width = CGFloat(cs) * cellW + CGFloat(cs - 1) * gapX
        // AppKit y grows upward: row 0 is the TOP band, so count the block's
        // bottom edge down from the inner top.
        let y = inner.maxY - CGFloat(r + rs) * cellH - CGFloat(r + rs - 1) * gapY
        let height = CGFloat(rs) * cellH + CGFloat(rs - 1) * gapY
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - slot 1…9 sugar (a single cell in the 3×3 grid, row-major)

    public static let slotCount = 9

    public static func placement(forSlot slot: Int) -> GridPlacement? {
        guard (1...slotCount).contains(slot) else { return nil }
        let index = slot - 1
        return GridPlacement(columns: 3, rows: 3, col: index % 3, row: index / 3)
    }

    public static func frame(forSlot slot: Int, in visibleFrame: CGRect) -> CGRect? {
        guard let placement = placement(forSlot: slot) else { return nil }
        return frame(for: placement, in: visibleFrame)
    }

    /// The nine 3×3 cell frames, row-major (index 0 = top-left … 8 = bottom-right).
    public static func slotFrames(in visibleFrame: CGRect) -> [CGRect] {
        (1...slotCount).compactMap { frame(forSlot: $0, in: visibleFrame) }
    }

    // MARK: - Named aliases + raw specs (agent-friendly targets)

    /// Resolve an agent-facing placement string to a `GridPlacement`. Accepts:
    ///   - a slot number: `"1"…"9"`
    ///   - a named zone: `top-left`, `top`, `top-right`, `left`, `center`, `right`,
    ///     `bottom-left`, `bottom`, `bottom-right`
    ///   - a half: `left-half`, `right-half`, `top-half`, `bottom-half`
    ///   - a third: `left-third`, `center-third`, `right-third`, `top-third`,
    ///     `middle-third`, `bottom-third`
    ///   - a quarter: `top-left-quarter`, `top-right-quarter`,
    ///     `bottom-left-quarter`, `bottom-right-quarter`
    ///   - the whole area: `full` / `fill`
    ///   - a raw spec: `"CxR:c,r"` or `"CxR:c,r+SxT"` (0-indexed col,row; optional
    ///     colSpan×rowSpan), e.g. `3x3:2,1` or `3x3:0,0+2x1`.
    /// Returns nil for anything unrecognized (callers keep the note un-placed).
    public static func placement(for name: String) -> GridPlacement? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let slot = Int(key) { return placement(forSlot: slot) }
        if let named = namedPlacements[key] { return named }
        return parseSpec(key)
    }

    /// Named zones, each an alias over the primitive.
    public static let namedPlacements: [String: GridPlacement] = {
        var table: [String: GridPlacement] = [
            // 3×3 zones (mirror slot 1…9)
            "top-left": .init(columns: 3, rows: 3, col: 0, row: 0),
            "top": .init(columns: 3, rows: 3, col: 1, row: 0),
            "top-right": .init(columns: 3, rows: 3, col: 2, row: 0),
            "left": .init(columns: 3, rows: 3, col: 0, row: 1),
            "center": .init(columns: 3, rows: 3, col: 1, row: 1),
            "right": .init(columns: 3, rows: 3, col: 2, row: 1),
            "bottom-left": .init(columns: 3, rows: 3, col: 0, row: 2),
            "bottom": .init(columns: 3, rows: 3, col: 1, row: 2),
            "bottom-right": .init(columns: 3, rows: 3, col: 2, row: 2),
            // halves
            "left-half": .init(columns: 2, rows: 1, col: 0, row: 0),
            "right-half": .init(columns: 2, rows: 1, col: 1, row: 0),
            "top-half": .init(columns: 1, rows: 2, col: 0, row: 0),
            "bottom-half": .init(columns: 1, rows: 2, col: 0, row: 1),
            // thirds
            "left-third": .init(columns: 3, rows: 1, col: 0, row: 0),
            "center-third": .init(columns: 3, rows: 1, col: 1, row: 0),
            "right-third": .init(columns: 3, rows: 1, col: 2, row: 0),
            "top-third": .init(columns: 1, rows: 3, col: 0, row: 0),
            "middle-third": .init(columns: 1, rows: 3, col: 0, row: 1),
            "bottom-third": .init(columns: 1, rows: 3, col: 0, row: 2),
            // quarters
            "top-left-quarter": .init(columns: 2, rows: 2, col: 0, row: 0),
            "top-right-quarter": .init(columns: 2, rows: 2, col: 1, row: 0),
            "bottom-left-quarter": .init(columns: 2, rows: 2, col: 0, row: 1),
            "bottom-right-quarter": .init(columns: 2, rows: 2, col: 1, row: 1),
            // whole visible area
            "full": .init(columns: 1, rows: 1, col: 0, row: 0),
            "fill": .init(columns: 1, rows: 1, col: 0, row: 0),
        ]
        return table
    }()

    /// Parse `"CxR:c,r"` or `"CxR:c,r+SxT"`. Lenient: returns nil on any malformed
    /// piece rather than guessing.
    private static func parseSpec(_ spec: String) -> GridPlacement? {
        let sides = spec.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard sides.count == 2 else { return nil }
        guard let dims = twoInts(String(sides[0]), separator: "x") else { return nil }

        var cellPart = String(sides[1])
        var colSpan = 1
        var rowSpan = 1
        if let plus = cellPart.firstIndex(of: "+") {
            let spanStr = String(cellPart[cellPart.index(after: plus)...])
            guard let spans = twoInts(spanStr, separator: "x") else { return nil }
            colSpan = spans.0
            rowSpan = spans.1
            cellPart = String(cellPart[..<plus])
        }
        guard let cell = twoInts(cellPart, separator: ",") else { return nil }
        return GridPlacement(
            columns: dims.0, rows: dims.1,
            col: cell.0, row: cell.1,
            colSpan: colSpan, rowSpan: rowSpan
        )
    }

    private static func twoInts(_ s: String, separator: Character) -> (Int, Int)? {
        let parts = s.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let a = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let b = Int(parts[1].trimmingCharacters(in: .whitespaces))
        else { return nil }
        return (a, b)
    }
}
