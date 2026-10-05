import AppKit
import SwiftUI

/// What the dot board near the cursor says while a window is dragged:
/// which way the hovered desktop lies from the window's own, and its number.
struct OverviewDotSign: Equatable {
    enum Direction: Equatable { case left, right, here }
    let direction: Direction
    let desktop: Int

    /// Reads the hovered drop target ("kind:displayId:spaceId") against the
    /// first dragged window. Displays order left to right, then desktops.
    static func sign(targetId: String?, windows: [UInt32], projection: OverviewProjection) -> OverviewDotSign? {
        guard let targetId, let wid = windows.first, let row = projection.all[wid] else { return nil }
        let parts = targetId.split(separator: ":")
        guard parts.count >= 3, let displayId = UInt32(parts[parts.count - 2]), let spaceId = Int(parts[parts.count - 1]),
              let display = projection.displays.first(where: { $0.displayId == displayId }),
              let desktop = display.desktopNumber(of: spaceId) else { return nil }
        let target = (display.index, desktop)
        guard let sourceSpace = row.spaceId,
              let source = projection.displays.first(where: { $0.owns(sourceSpace) }),
              let sourceDesktop = source.desktopNumber(of: sourceSpace) else {
            return OverviewDotSign(direction: .here, desktop: desktop)
        }
        let from = (source.index, sourceDesktop)
        let direction: Direction = target == from ? .here : target < from ? .left : .right
        return OverviewDotSign(direction: direction, desktop: desktop)
    }
}

/// A dot-matrix board, like an airport departures sign: chevrons march
/// toward the desktop and the number sits at the end they point to.
/// New messages flip in column by column, left to right.
struct OverviewDotBoard: View {
    let sign: OverviewDotSign?

    static let columns = 19
    static let rows = 7
    static let pitch: CGFloat = 4.5
    static let dot: CGFloat = 3
    static let size = CGSize(width: CGFloat(columns) * pitch + 12, height: CGFloat(rows) * pitch + 10)

    /// One column every 140 ms: steady, not busy.
    static let march: TimeInterval = 0.14
    /// The flip wave crosses the board in about 0.4 s.
    static let flip: TimeInterval = 0.022

    @State private var shown: OverviewDotSign?
    @State private var previous: OverviewDotSign?
    @State private var changed = Date.distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: shown == nil && previous == nil)) { context in
            Canvas { gc, _ in
                let t = context.date.timeIntervalSinceReferenceDate
                let since = context.date.timeIntervalSince(changed)
                let now = Self.grid(shown, time: t)
                let before = Self.grid(previous, time: t)
                for c in 0..<Self.columns {
                    let column = since >= Double(c) * Self.flip ? now : before
                    for r in 0..<Self.rows {
                        let cell = column[r][c]
                        let rect = CGRect(x: 6 + CGFloat(c) * Self.pitch + (Self.pitch - Self.dot) / 2,
                                          y: 5 + CGFloat(r) * Self.pitch + (Self.pitch - Self.dot) / 2,
                                          width: Self.dot, height: Self.dot)
                        let color: Color = switch cell {
                        case .off: Color.white.opacity(0.07)
                        case .arrow: Palette.running
                        case .digit: Color(white: 0.95)
                        }
                        gc.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .opacity(sign == nil ? 0 : 1)
        .animation(.easeOut(duration: 0.18), value: sign == nil)
        .onAppear { shown = sign }
        .onChange(of: sign) { _, next in
            // An empty board keeps the last message so the fade-out shows it.
            guard let next else { return }
            previous = shown; shown = next; changed = Date()
        }
        .accessibilityElement()
        .accessibilityLabel(sign.map { s in
            switch s.direction {
            case .left: return "Desktop \(s.desktop), to the left"
            case .right: return "Desktop \(s.desktop), to the right"
            case .here: return "Desktop \(s.desktop), where it is now"
            }
        } ?? "")
    }

    enum Cell { case off, arrow, digit }

    /// The board's cells for one message at time `t`.
    static func grid(_ sign: OverviewDotSign?, time t: TimeInterval) -> [[Cell]] {
        var cells = Array(repeating: Array(repeating: Cell.off, count: columns), count: rows)
        guard let sign else { return cells }
        let digits = Array(String(sign.desktop)).compactMap { glyphs[$0] }
        let digitWidth = digits.count * 4 - 1
        func stamp(_ glyph: [String], at x: Int) {
            for (r, line) in glyph.enumerated() {
                for (c, ch) in line.enumerated() where ch == "#" && (0..<columns).contains(x + c) {
                    cells[r + 1][x + c] = .digit
                }
            }
        }
        let digitX: Int
        switch sign.direction {
        case .here: digitX = (columns - digitWidth) / 2
        case .right: digitX = columns - digitWidth
        case .left: digitX = 0
        }
        for (i, glyph) in digits.enumerated() { stamp(glyph, at: digitX + i * 4) }

        guard sign.direction != .here else { return cells }
        // Chevrons fill the rest, marching toward the number.
        let field = sign.direction == .right ? 0..<(columns - digitWidth - 2) : (digitWidth + 2)..<columns
        let step = Int(t / march)
        for c in field {
            let phase = sign.direction == .right ? (c - step) : (c + step)
            let k = ((phase % 4) + 4) % 4
            // ">" over five rows: tips at k == 2 for right, k == 0 for left.
            let rowsLit: [Int]
            switch sign.direction == .right ? k : 2 - k {
            case 0: rowsLit = [0, 4]
            case 1: rowsLit = [1, 3]
            case 2: rowsLit = [2]
            default: rowsLit = []
            }
            for r in rowsLit { cells[r + 1][c] = .arrow }
        }
        return cells
    }

    private static let glyphs: [Character: [String]] = [
        "0": ["###", "#.#", "#.#", "#.#", "###"],
        "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["###", "..#", "###", "#..", "###"],
        "3": ["###", "..#", ".##", "..#", "###"],
        "4": ["#.#", "#.#", "###", "..#", "..#"],
        "5": ["###", "#..", "###", "..#", "###"],
        "6": ["###", "#..", "###", "#.#", "###"],
        "7": ["###", "..#", ".#.", ".#.", ".#."],
        "8": ["###", "#.#", "###", "#.#", "###"],
        "9": ["###", "#.#", "###", "..#", "###"],
    ]
}

/// Feeds the floating board from the pointer drag.
final class OverviewDotBoardState: ObservableObject {
    @Published var sign: OverviewDotSign?
}

struct OverviewDotBoardHost: View {
    @ObservedObject var state: OverviewDotBoardState
    var body: some View { OverviewDotBoard(sign: state.sign) }
}
