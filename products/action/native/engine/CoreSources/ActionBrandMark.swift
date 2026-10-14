import CoreGraphics
import Foundation

/// Action's mark: a sharp capital A whose right foot is taken by a cursor.
///
/// The cursor's tip sits on the lower right corner of the counter and its tail
/// runs out through the leg. The letter is cut back from both arms by an even
/// gap, so the cursor reads as working inside the letter rather than lying on
/// top of it.
///
/// This is a port. The source of truth is `ActionMark` in
/// `apps/site/src/components/ActionMark.tsx` (STUDY 02), and the numbers below
/// are copied from it. `bun run brand` in `apps/site` renders the brand kit and
/// `Action.icns` from that component. The app draws the mark itself in two
/// places, the menu bar status item and the brand chip, and both use this.
///
/// Paths are authored in the component's coordinates, with **y pointing down**,
/// then mapped onto whatever rect the caller hands in, so the mark is
/// resolution-independent.
public enum ActionBrandMark {
    /// The square the brand kit crops from the component's 720 x 640
    /// construction drawing. The path functions map this box onto the rect they
    /// are given. y points down.
    public static let designBox = CGRect(x: 15, y: 35, width: 590, height: 590)

    /// Which way y runs in the space the caller is drawing into.
    ///
    /// CoreGraphics contexts and unflipped `NSImage` drawing put y at the
    /// bottom; SwiftUI and flipped AppKit views put it at the top. The mark is
    /// authored y-down, so getting this wrong renders it upside down rather
    /// than failing loudly — hence an explicit argument instead of a default
    /// that silently suits one caller.
    public enum YAxis: Sendable {
        case up
        case down
    }

    /// Clearance between the letter and the cursor, in design units: the
    /// construction drawing's "GAP 10 U". Drawn in one colour, the gap is all
    /// that separates the two, and at menu bar size ten units is a third of a
    /// point, so small single-colour drawings pass a wider one.
    public static let standardGap = 10.0

    /// The letter and the cursor as one path, for single-colour drawing.
    public static func markPath(
        in rect: CGRect,
        yAxis: YAxis = .up,
        gap: Double = standardGap
    ) -> CGPath {
        let path = CGMutablePath()
        path.addPath(letterPath(in: rect, yAxis: yAxis, gap: gap))
        path.addPath(cursorPath(in: rect, yAxis: yAxis))
        return path
    }

    /// The A, with its counter and the clearance around the cursor cut out.
    ///
    /// The component cuts them with an even-odd fill and a mask. Here both are
    /// real path subtractions, so the result is one plain path that fills
    /// identically in CoreGraphics, in an `NSImage`, and in a SwiftUI `Shape`.
    public static func letterPath(
        in rect: CGRect,
        yAxis: YAxis = .up,
        gap: Double = standardGap
    ) -> CGPath {
        place(rawLetter(gap: gap), in: rect, yAxis: yAxis)
    }

    /// The cursor on its own, so it can carry its own colour.
    public static func cursorPath(in rect: CGRect, yAxis: YAxis = .up) -> CGPath {
        place(rawCursor(), in: rect, yAxis: yAxis)
    }

    /// The drawn glyph's bounds in design space: the A's apex and left foot,
    /// and the cursor's tail, which overhangs the letter to the right and
    /// below.
    public static let glyphBounds: CGRect = {
        let glyph = CGMutablePath()
        glyph.addPath(rawLetter(gap: standardGap))
        glyph.addPath(rawCursor())
        return glyph.boundingBoxOfPath
    }()

    /// The rect to hand the path functions so that the glyph itself, not the
    /// design box's margins, is centred in `target` with its longer side
    /// filling it.
    public static func designRect(fittingGlyphIn target: CGRect, yAxis: YAxis = .up) -> CGRect {
        let scale = min(target.width, target.height) / max(glyphBounds.width, glyphBounds.height)
        let side = designBox.width * scale
        // In a y-up space the box is flipped, so the glyph's centre is measured
        // from the box's bottom edge rather than its top.
        let fromOrigin = yAxis == .down
            ? glyphBounds.midY - designBox.minY
            : designBox.maxY - glyphBounds.midY
        return CGRect(
            x: target.midX - (glyphBounds.midX - designBox.minX) * scale,
            y: target.midY - fromOrigin * scale,
            width: side,
            height: side
        )
    }

    // MARK: - Tile

    /// The rounded tile the mark sits on, as the app icon and the in-app brand
    /// chip both draw it: a rounded rect with continuous corners.
    public static func tilePath(in rect: CGRect, cornerRatio: Double = tileCornerRatio) -> CGPath {
        continuousRoundedRect(
            rect,
            radius: Double(min(rect.width, rect.height)) * cornerRatio,
            n: tileCornerExponent
        )
    }

    /// How far the corner reaches along each edge, as a fraction of the tile's
    /// side. Larger than the circular equivalent because a superellipse corner
    /// starts bending later, so it needs more run to land in the same place.
    public static let tileCornerRatio = 0.345
    /// Squareness of the corner; 2 is a circle. With the ratio above it lands
    /// within a pixel of the mask macOS 26 draws around system icons, and every
    /// Lattices product icon uses the same pair (`export-brand.tsx`).
    public static let tileCornerExponent = 2.85

    /// The glyph's longer side as a share of the tile.
    public static let iconGlyphShare = 0.66
    /// How far the glyph is lifted, as a share of the tile's height. Its mass
    /// sits low — a wide base with the cursor's tail beneath it — so centring
    /// it on its bounds alone makes it look like it is sinking.
    public static let iconGlyphLift = 0.012

    /// Where the design box sits inside a tile: the glyph centred on its own
    /// bounds, scaled to `iconGlyphShare` and lifted by `iconGlyphLift`, as the
    /// app icon composes it. Every tile the app draws goes through here, so the
    /// chip in a header and the icon in the Dock cannot drift.
    public static func markRect(inTile tile: CGRect, yAxis: YAxis = .up) -> CGRect {
        let side = tile.width * CGFloat(iconGlyphShare)
        let lift = tile.height * CGFloat(iconGlyphLift)
        let glyph = CGRect(
            x: tile.midX - side / 2,
            // Raising the glyph subtracts in a y-down space and adds in a y-up one.
            y: tile.midY - side / 2 + (yAxis == .down ? -lift : lift),
            width: side,
            height: side
        )
        return designRect(fittingGlyphIn: glyph, yAxis: yAxis)
    }

    // MARK: - Colours

    /// The cursor's colour. The kit uses it on both its light and its dark
    /// paper, so it is baked in here while the chip's tile and letter follow
    /// the theme. sRGB, like the kit's hex values and the icon rendered from
    /// them.
    public static let cursor = CGColor(srgbRed: 0xC5 / 255, green: 0x8A / 255, blue: 0x70 / 255, alpha: 1)

    /// The `action` built-in theme's HUD coral (`ActionThemeBuiltin.swift`),
    /// which means "live" everywhere in the app. The status item turns this
    /// colour while a drive holds the machine. Generic RGB, the space the
    /// theme's colours are built in, so the two match.
    public static let coral = CGColor(red: 0.937, green: 0.416, blue: 0.278, alpha: 1)

    // MARK: - Geometry

    /// The cursor's tip: the counter's lower right corner, where the crossbar
    /// meets the right leg.
    private static let tip = CGPoint(x: 378.02667529115377, y: 404.9783920951129)

    /// Carries the cursor's own frame, with the tip at the origin and the tail
    /// along +x, onto the design box. The component's
    /// `translate(378.03 404.98) rotate(35)`.
    private static let cursorFrame = CGAffineTransform(translationX: tip.x, y: tip.y)
        .rotated(by: 35 * .pi / 180)

    /// The cursor's arms leave the tip 25° either side of its axis.
    private static let spread = 25 * Double.pi / 180

    private static func rawLetter(gap: Double) -> CGPath {
        let outer = CGMutablePath()
        outer.addLines(between: [
            CGPoint(x: 265, y: 100),
            CGPoint(x: 335, y: 100),
            CGPoint(x: 530.0930354263446, y: 500),
            CGPoint(x: 69.90696457365542, y: 500),
        ])
        outer.closeSubpath()

        let counter = CGMutablePath()
        counter.addLines(between: [
            CGPoint(x: 300, y: 245),
            CGPoint(x: 221.97332470884623, y: 404.9783920951129),
            tip,
        ])
        counter.closeSubpath()

        return outer.subtracting(counter).subtracting(clearance(gap: gap))
    }

    /// The wedge cut from the letter around the cursor: the cursor's arms,
    /// each pushed out by `gap` and run on well past the letter. Edges parallel
    /// to the arms at that distance meet `gap / sin(spread)` behind the tip.
    private static func clearance(gap: Double) -> CGPath {
        let apex = -gap / sin(spread)
        let reach = 500.0
        let half = (reach - apex) * tan(spread)
        let wedge = CGMutablePath()
        wedge.addLines(
            between: [CGPoint(x: apex, y: 0), CGPoint(x: reach, y: -half), CGPoint(x: reach, y: half)],
            transform: cursorFrame
        )
        wedge.closeSubpath()
        return wedge
    }

    /// Straight arms from a softened tip, rounded ends, and a notched tail.
    private static func rawCursor() -> CGPath {
        let local = CGMutablePath()
        local.move(to: .zero)
        local.addCurve(
            to: CGPoint(x: 8, y: -3.730461265239989),
            control1: CGPoint(x: 0, y: -2),
            control2: CGPoint(x: 3, y: -3)
        )
        local.addLine(to: CGPoint(x: 170, y: -79.27230188634977))
        local.addQuadCurve(
            to: CGPoint(x: 175, y: -73.93537846789975),
            control: CGPoint(x: 180, y: -83.93537846789975)
        )
        local.addLine(to: CGPoint(x: 140, y: -26))
        local.addQuadCurve(to: CGPoint(x: 140, y: 26), control: CGPoint(x: 124, y: 0))
        local.addLine(to: CGPoint(x: 175, y: 73.93537846789975))
        local.addQuadCurve(
            to: CGPoint(x: 170, y: 79.27230188634977),
            control: CGPoint(x: 180, y: 83.93537846789975)
        )
        local.addLine(to: CGPoint(x: 8, y: 3.730461265239989))
        local.addCurve(to: .zero, control1: CGPoint(x: 3, y: 3), control2: CGPoint(x: 0, y: 2))
        local.closeSubpath()

        let cursor = CGMutablePath()
        cursor.addPath(local, transform: cursorFrame)
        return cursor
    }

    private static func place(_ path: CGPath, in rect: CGRect, yAxis: YAxis) -> CGPath {
        var transform = designTransform(into: rect, yAxis: yAxis)
        return path.copy(using: &transform) ?? path
    }

    /// Maps the design box (y down) onto `rect` in the caller's space, fitting
    /// the shorter side and centring.
    private static func designTransform(into rect: CGRect, yAxis: YAxis) -> CGAffineTransform {
        let scale = min(rect.width, rect.height) / designBox.width
        let originX = rect.minX + (rect.width - designBox.width * scale) / 2
        let originY = rect.minY + (rect.height - designBox.height * scale) / 2
        switch yAxis {
        case .down:
            return CGAffineTransform(
                a: scale, b: 0, c: 0, d: scale,
                tx: originX - designBox.minX * scale,
                ty: originY - designBox.minY * scale
            )
        case .up:
            return CGAffineTransform(
                a: scale, b: 0, c: 0, d: -scale,
                tx: originX - designBox.minX * scale,
                ty: originY + designBox.maxY * scale
            )
        }
    }

    /// A rounded rect whose corners are superellipse quadrants rather than
    /// circular arcs — the continuous curvature macOS uses, where the corner
    /// eases into the straight edge instead of meeting it at a curvature jump.
    ///
    /// `radius` is how far the corner reaches along each edge, not a circle's
    /// radius; with `n` above 2 the corner is fuller than a circle of the same
    /// reach. Sampled rather than fitted with béziers: at icon sizes the
    /// difference is invisible and the arithmetic stays honest.
    private static func continuousRoundedRect(
        _ rect: CGRect,
        radius: Double,
        n: Double,
        samples: Int = 48
    ) -> CGPath {
        let path = CGMutablePath()
        let x0 = Double(rect.minX), y0 = Double(rect.minY)
        let x1 = Double(rect.maxX), y1 = Double(rect.maxY)
        let r = min(radius, min(x1 - x0, y1 - y0) / 2)
        let exponent = 2 / n

        func corner(_ cx: Double, _ cy: Double, _ sx: Double, _ sy: Double, reversed: Bool) {
            for i in 0...samples {
                let k = reversed ? samples - i : i
                let t = Double.pi / 2 * Double(k) / Double(samples)
                path.addLine(to: CGPoint(
                    x: cx + sx * r * pow(cos(t), exponent),
                    y: cy + sy * r * pow(sin(t), exponent)
                ))
            }
        }

        path.move(to: CGPoint(x: x0 + r, y: y0))
        path.addLine(to: CGPoint(x: x1 - r, y: y0))
        corner(x1 - r, y0 + r, 1, -1, reversed: true)
        path.addLine(to: CGPoint(x: x1, y: y1 - r))
        corner(x1 - r, y1 - r, 1, 1, reversed: false)
        path.addLine(to: CGPoint(x: x0 + r, y: y1))
        corner(x0 + r, y1 - r, -1, 1, reversed: true)
        path.addLine(to: CGPoint(x: x0, y: y0 + r))
        corner(x0 + r, y0 + r, -1, -1, reversed: false)
        path.closeSubpath()
        return path
    }
}
