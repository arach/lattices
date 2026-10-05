import SwiftUI

/// What Ply, the Overview's mover, is doing during a desktop move.
enum OverviewPlyPose: Equatable {
    case idle, pickUp, carry, wait, setDown, snapBack

    var label: String {
        switch self {
        case .idle: return "Ply is resting"
        case .pickUp: return "Ply picked the window up"
        case .carry: return "Ply is carrying the window"
        case .wait: return "Ply is waiting for the desktop"
        case .setDown: return "Ply set the window down"
        case .snapBack: return "Ply couldn't move the window and brought it back"
        }
    }
}

/// Ply, drawn from shapes on a 64 × 48 grid so poses morph into each other:
/// the slab base splits into legs to walk, the card lifts, rides and lands.
struct OverviewPly: View {
    let pose: OverviewPlyPose
    var height: CGFloat = 24

    private static let body = Color(white: 0.95)
    private static let eye = Color(white: 0.07)
    private static let card = Color(white: 0.95)
    private static let cardBar = Color(white: 0.55)
    private static let cardBack = Color(white: 0.72)
    private static let edge = Color.black.opacity(0.35)

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.4, paused: pose != .carry)) { context in
            let step = pose == .carry ? Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 2 : -1
            figure(step: step)
                .animation(.easeInOut(duration: 0.3), value: step)
        }
        .frame(width: height * 64 / 48, height: height)
        .animation(.easeInOut(duration: 0.45), value: pose)
        .accessibilityElement()
        .accessibilityLabel(pose.label)
        .help(pose.label)
    }

    private var s: CGFloat { height / 48 }

    private func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> some View {
        Color.clear.frame(width: w * s, height: h * s).offset(x: x * s, y: y * s)
    }

    private func figure(step: Int) -> some View {
        let bodyY: CGFloat = pose == .pickUp ? 14 : pose == .carry ? 16 : 18
        let legs = pose == .carry || pose == .snapBack
        let eyeDY: CGFloat = pose == .snapBack ? 3 : pose == .wait ? -1 : 0
        let eyeDX: CGFloat = pose == .wait ? 2 : 0

        return ZStack(alignment: .topLeading) {
            // Base: one slab at rest, two legs to walk.
            piece(x: 18, y: 37 - (step == 0 ? 1 : 0), w: legs ? 8 : 14, h: 7, r: 1.5, fill: Self.body)
            piece(x: legs ? 38 : 32, y: 37 - (step == 1 ? 1 : 0), w: legs ? 8 : 14, h: 7, r: 1.5, fill: Self.body)

            // Head: off-white block under a green top edge, two pill eyes.
            piece(x: 12, y: bodyY, w: 40, h: 18, r: 3.5, fill: Self.body)
            UnevenRoundedRectangle(topLeadingRadius: 3.5 * s, topTrailingRadius: 3.5 * s)
                .fill(Palette.running)
                .frame(width: 40 * s, height: 4 * s)
                .offset(x: 12 * s, y: bodyY * s)
            Capsule().fill(Self.eye)
                .frame(width: 4 * s, height: 8 * s)
                .offset(x: (22 + eyeDX) * s, y: (bodyY + 7 + eyeDY) * s)
            Capsule().fill(Self.eye)
                .frame(width: 4 * s, height: 8 * s)
                .offset(x: (38 + eyeDX) * s, y: (bodyY + 7 + eyeDY) * s)

            card
            tick
        }
        .frame(width: 64 * s, height: 48 * s, alignment: .topLeading)
    }

    private func piece(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat, fill: Color) -> some View {
        RoundedRectangle(cornerRadius: r * s)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: r * s).strokeBorder(Self.edge, lineWidth: max(0.5, 0.6 * s)))
            .frame(width: w * s, height: h * s)
            .offset(x: x * s, y: y * s)
    }

    /// The window being moved: hidden at rest, lifted, carried, then set
    /// down beside Ply, or tipped back onto its head when the move fails.
    private var card: some View {
        let frame: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) = {
            switch pose {
            case .idle: return (23, 12, 18, 6)
            case .pickUp: return (23, 1, 18, 11)
            case .carry, .wait: return (22, 4, 20, 12)
            case .setDown: return (54, 33, 9, 11)
            case .snapBack: return (22, 8, 20, 8)
            }
        }()
        let back = pose == .snapBack
        return RoundedRectangle(cornerRadius: 1.5 * s)
            .fill(back ? Self.cardBack : Self.card)
            .overlay(alignment: .top) {
                Rectangle().fill(Self.cardBar).frame(height: 2 * s).padding(.horizontal, 2 * s).padding(.top, 1.5 * s)
            }
            .overlay(RoundedRectangle(cornerRadius: 1.5 * s).strokeBorder(Self.edge, lineWidth: max(0.5, 0.6 * s)))
            .frame(width: frame.w * s, height: frame.h * s)
            .rotationEffect(.degrees(back ? -9 : 0))
            .offset(x: frame.x * s, y: frame.y * s)
            .opacity(pose == .idle ? 0 : 1)
    }

    private var tick: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 4))
            p.addLine(to: CGPoint(x: 3, y: 7))
            p.addLine(to: CGPoint(x: 9, y: 0))
        }
        .trim(from: 0, to: pose == .setDown ? 1 : 0)
        .stroke(Palette.running, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        .frame(width: 9, height: 7)
        .scaleEffect(s, anchor: .topLeading)
        .offset(x: 54 * s, y: 22 * s)
        .animation(.easeOut(duration: 0.5).delay(pose == .setDown ? 0.3 : 0), value: pose)
    }
}
