import SwiftUI

// MARK: - Long

/// Long, Lattices' desktop character: the mark's tile on two feet. The lit L
/// of the grid is his body; the dim cells top right are his face, with two
/// tall eyes on them. Drawn on a 100-unit square, the way Fab draws Tuck.
///   · rest: still, a blink every few seconds.
///   · listen: leans in, eyes up.
///   · work: eyes scan side to side.
///   · done: one nod, then rest.
///   · oops: eyes squint down.
///   · away: you're visiting another machine; he looks across, the corner cell coral.
/// Reduce Motion: no blink, lean, scan or nod; the eyes still change for each mood.
struct Long: View {
    enum Mood: Equatable { case rest, listen, work, done, oops, away }
    var mood: Mood = .rest
    var size: CGFloat = 44
    /// Where he's looking, in grid units (up to 4 each way).
    var gaze: CGVector = .zero

    @Environment(\.accessibilityReduceMotion) private var still
    @State private var blink = false
    @State private var scan = false
    @State private var nod = false

    static let ink = Color(red: 0x10 / 255, green: 0x15 / 255, blue: 0x18 / 255)
    static let lit = Color(red: 0xf2 / 255, green: 0xf2 / 255, blue: 0xf2 / 255)
    static let coral = Color(red: 0xef / 255, green: 0x6a / 255, blue: 0x47 / 255)

    var body: some View {
        let u = size / 100
        let leaning = mood == .listen && !still
        let nodding = nod && !still
        ZStack {
            LongFeet().fill(Self.ink)
            LongFeet().stroke(Color.white.opacity(0.14), lineWidth: max(1, 2.4 * u))
            LongBody().fill(Self.ink)
            LongBody().stroke(Color.white.opacity(0.14), lineWidth: max(1, 2.4 * u))
            cells
            eyes(u)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(leaning ? -7 : nodding ? 4 : 0), anchor: UnitPoint(x: 0.5, y: 0.92))
        .offset(y: leaning ? -1 : nodding ? 3 * u : 0)
        .animation(still ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: leaning)
        .onChange(of: mood, initial: true) { _, now in moved(to: now) }
        .task(id: mood) { await blinking() }
        .accessibilityHidden(true)
    }

    /// The mark's grid: the L lit, the face dim, the corner coral while away.
    private var cells: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { i in
                let col = i % 3, row = i / 3
                LongCell(col: col, row: row).fill(fill(col: col, row: row))
            }
        }
        .animation(.easeOut(duration: 0.25), value: mood)
    }

    private func fill(col: Int, row: Int) -> Color {
        if col == 2, row == 2, mood == .away { return Self.coral }
        return col == 0 || row == 2 ? Self.lit : Color.white.opacity(0.18)
    }

    private func eyes(_ u: CGFloat) -> some View {
        let squint: CGFloat = mood == .oops ? 0.22 : blink ? 0.08 : 1
        let looking = mood == .rest || mood == .listen || mood == .away
        let dx: CGFloat = mood == .work && !still ? (scan ? 3 : -3) : looking ? gaze.dx : 0
        let dy: CGFloat = mood == .listen ? -2.5 + gaze.dy : mood == .oops ? 3 : looking ? gaze.dy : 0
        return ZStack {
            LongEye(cx: 50, cy: 34).fill(Self.lit).scaleEffect(x: 1, y: squint, anchor: UnitPoint(x: 0.5, y: 0.34))
            LongEye(cx: 73, cy: 34).fill(Self.lit).scaleEffect(x: 1, y: squint, anchor: UnitPoint(x: 0.73, y: 0.34))
        }
        .offset(x: dx * u, y: dy * u)
        .animation(still ? nil : .easeOut(duration: 0.18), value: gaze)
    }

    private func moved(to mood: Mood) {
        guard !still else { scan = false; nod = false; return }
        if mood == .work {
            scan = false
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { scan = true }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { scan = false }
        }
        if mood == .done {
            withAnimation(.easeOut(duration: 0.24)) { nod = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                withAnimation(.easeInOut(duration: 0.36)) { nod = false }
            }
        }
    }

    /// A blink every 5.2 s while he's looking; none under Reduce Motion.
    private func blinking() async {
        guard !still, mood == .rest || mood == .listen || mood == .away else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.08)) { blink = true }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: 0.1)) { blink = false }
        }
    }
}

// MARK: Long's pieces, on the 100-unit grid

private extension CGRect {
    func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: minX + x * width / 100, y: minY + y * height / 100)
    }
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(origin: at(x, y), size: CGSize(width: w * width / 100, height: h * height / 100))
    }
}

private struct LongBody: Shape {
    func path(in r: CGRect) -> Path {
        Path(roundedRect: r.box(10, 6, 80, 80), cornerRadius: 20 * r.width / 100, style: .continuous)
    }
}

/// Cell `col`, `row` of the mark's 3×3 grid: 19 units with a 5-unit gap.
private struct LongCell: Shape {
    var col: Int
    var row: Int
    func path(in r: CGRect) -> Path {
        let x = 19 + CGFloat(col) * 22, y = 15 + CGFloat(row) * 22
        return Path(roundedRect: r.box(x, y, 18, 18), cornerRadius: 4 * r.width / 100, style: .continuous)
    }
}

private struct LongFeet: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for x in [26, 62] as [CGFloat] {
            p.addRoundedRect(in: r.box(x, 80, 12, 12), cornerSize: CGSize(width: 4.5 * r.width / 100, height: 4.5 * r.width / 100))
        }
        return p
    }
}

private struct LongEye: Shape {
    var cx, cy: CGFloat
    func path(in r: CGRect) -> Path {
        Path(ellipseIn: r.box(cx - 4.6, cy - 11, 9.2, 22))
    }
}
