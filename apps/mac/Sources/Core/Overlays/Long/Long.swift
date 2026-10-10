import SwiftUI

// MARK: - Long

/// Long, Lattices' desktop character: one tile on two feet, with two tall eyes
/// and a mouth that is the tile again in miniature. Drawn on a 100-unit square,
/// the way Fab draws Tuck.
///   · rest: still, a blink every few seconds.
///   · listen: leans in, eyes up.
///   · work: eyes scan side to side.
///   · done: one nod, then rest.
///   · oops: eyes squint down.
///   · talk: the mouth opens and closes.
///   · away: you're visiting another machine; he looks across, a coral cell in his corner.
/// Reduce Motion: no blink, lean, scan or nod; the eyes still change for each mood.
struct Long: View {
    enum Mood: Equatable { case rest, listen, work, done, oops, away, talk }
    var mood: Mood = .rest
    var size: CGFloat = 44
    /// Where he's looking, in grid units (up to 4 each way).
    var gaze: CGVector = .zero

    @Environment(\.accessibilityReduceMotion) private var still
    @State private var blink = false
    @State private var scan = false
    @State private var nod = false
    @State private var mouthFrame = 0

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
            if mood == .away { LongCorner().fill(Self.coral) }
            Group {
                eyes(u)
                LongMouth(shape: mouthShape).fill(Self.lit)
                    .animation(still ? nil : .easeOut(duration: 0.1), value: mouthShape)
            }
            .offset(x: mood == .away ? 4 * u : 0)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(leaning ? -7 : nodding ? 4 : 0), anchor: UnitPoint(x: 0.5, y: 0.92))
        .offset(y: leaning ? -1 : nodding ? 3 * u : 0)
        .animation(still ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: leaning)
        .onChange(of: mood, initial: true) { _, now in moved(to: now) }
        .task(id: mood) { await blinking() }
        .task(id: mood) { await talking() }
        .accessibilityHidden(true)
    }

    /// Closed at rest; a small round "ooh" while listening; low and flat for
    /// oops; while talking it cycles closed, open, half.
    private var mouthShape: LongMouth.Form {
        switch mood {
        case .listen: .ooh
        case .oops: .oops
        case .talk: still ? .half : [.closed, .open, .half][mouthFrame % 3]
        default: .closed
        }
    }

    private func eyes(_ u: CGFloat) -> some View {
        let squint: CGFloat = mood == .oops ? 0.22 : blink ? 0.08 : 1
        let looking = mood == .rest || mood == .listen || mood == .away || mood == .talk
        let dx: CGFloat = mood == .work && !still ? (scan ? 3 : -3) : looking ? gaze.dx : 0
        let dy: CGFloat = mood == .listen ? -2.5 + gaze.dy : mood == .oops ? 3 : looking ? gaze.dy : 0
        return ZStack {
            LongEye(cx: 38, cy: 32).fill(Self.lit).scaleEffect(x: 1, y: squint, anchor: UnitPoint(x: 0.38, y: 0.32))
            LongEye(cx: 62, cy: 32).fill(Self.lit).scaleEffect(x: 1, y: squint, anchor: UnitPoint(x: 0.62, y: 0.32))
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

    private func talking() async {
        mouthFrame = 0
        guard !still, mood == .talk else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(140))
            mouthFrame += 1
        }
    }

    /// A blink every 5.2 s while he's looking; none under Reduce Motion.
    private func blinking() async {
        guard !still, mood == .rest || mood == .listen || mood == .away || mood == .talk else { return }
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

/// The mouth: a solid tile with the body's corners, a quarter of its width.
/// Closing squashes it to a bar and the corners stay round.
private struct LongMouth: Shape {
    enum Form: Equatable { case closed, half, open, ooh, oops }
    var shape: Form
    func path(in r: CGRect) -> Path {
        let (w, h, dy): (CGFloat, CGFloat, CGFloat) = switch shape {
        case .closed: (22, 6, 0)
        case .half: (22, 13, 0)
        case .open: (22, 20, 0)
        case .ooh: (13, 12, 0)
        case .oops: (16, 5, 4)
        }
        let radius = min(w * 0.25, h / 2) * r.width / 100
        return Path(roundedRect: r.box(50 - w / 2, 64 + dy - h / 2, w, h), cornerRadius: radius, style: .continuous)
    }
}

/// The coral cell in his top-right corner while you're away.
private struct LongCorner: Shape {
    func path(in r: CGRect) -> Path {
        Path(roundedRect: r.box(74.5, 14.5, 7, 7), cornerRadius: 1.75 * r.width / 100, style: .continuous)
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
        Path(roundedRect: r.box(cx - 4.6, cy - 10, 9.2, 20), cornerRadius: 4.6 * r.width / 100, style: .continuous)
    }
}
