import AppKit
import SwiftUI

// MARK: - Static tokens

enum HUDChrome {
    static let baseTop           = Color(red: 0.055, green: 0.060, blue: 0.070)
    static let baseBottom        = Color(red: 0.025, green: 0.027, blue: 0.034)
    static let glassFill         = Color.white.opacity(0.045)
    static let glassFillStrong   = Color.white.opacity(0.075)
    static let glassStroke       = Color.white.opacity(0.13)
    static let glassStrokeSoft   = Color.white.opacity(0.07)
    static let cyan              = Color(red: 0.34, green: 0.78, blue: 0.96)
    static let rose              = Color(red: 1.0,  green: 0.42, blue: 0.58)
    static let amber             = Palette.detach

    static var activeGradient: LinearGradient {
        LinearGradient(
            colors: [Palette.running.opacity(0.95), cyan.opacity(0.90)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: - Mesh colours

    /// 3×3 grid colours for the MeshGradient light source.
    /// mouseNorm: cursor position normalised to screen (x: 0=left, y: 0=bottom — screen space).
    static func meshColors(mouseNorm: CGPoint) -> [Color] {
        let mx = Float(mouseNorm.x)
        let my = Float(mouseNorm.y)       // 0 = bottom of screen, 1 = top

        func node(_ nx: Float, _ ny: Float) -> Color {
            // Distance from cursor in normalised space
            let dx = mx - nx
            let dy = my - ny              // both in screen-y (0=bottom)
            let dist = (dx * dx + dy * dy).squareRoot()

            // Soft light falloff — subtle, not dramatic
            let light = Double(max(0, 1.0 - dist * 2.0)) * 0.06

            // Ambient: gentle gradient from top-left (environmental light)
            let ambient = Double(max(0, (1 - nx * 0.5) * (1 - ny * 0.4))) * 0.03

            let r = min(1.0, 0.055 + ambient + light * 0.60)
            let g = min(1.0, 0.062 + ambient + light * 0.72)
            let b = min(1.0, 0.095 + ambient + light * 0.95)  // slight cool cast
            return Color(red: r, green: g, blue: b)
        }

        // SwiftUI MeshGradient: (0,0) = top-left, (1,1) = bottom-right.
        // Screen-y is flipped vs SwiftUI-y, so we invert ny below.
        return [
            node(0,   1), node(0.5, 1), node(1,   1),  // top row    (screen top = my≈1)
            node(0, 0.5), node(0.5, 0.5), node(1, 0.5), // mid row
            node(0,   0), node(0.5, 0), node(1,   0),  // bottom row (screen bottom = my≈0)
        ]
    }
}

// MARK: - Panel background

struct HUDPanelBackground: View {
    @ObservedObject private var xp = HUDExperienceStore.shared

    private func classicBase(opacity: Double) -> some View {
        LinearGradient(
            colors: [
                HUDChrome.baseTop.opacity(opacity),
                HUDChrome.baseBottom.opacity(min(1, opacity + 0.02)),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var mouse: CGPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        return xp.normalizedMouse(on: screen)
    }

    var body: some View {
        ZStack {
            // ── 0. substrate ─────────────────────────────────────────
            if xp.has(.liveCapture), let bg = xp.capturedBackground {
                Image(nsImage: bg)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }

            // ── 1. colour base ────────────────────────────────────────
            if xp.has(.meshLight) {
                if #available(macOS 15.0, *) {
                    MeshGradient(
                        width: 3, height: 3,
                        points: [
                            [0, 0], [0.5, 0], [1, 0],
                            [0, 0.5], [0.5, 0.5], [1, 0.5],
                            [0, 1], [0.5, 1], [1, 1]
                        ],
                        colors: HUDChrome.meshColors(mouseNorm: mouse)
                    )
                    .opacity(xp.currentPreset.overlayOpacity)
                } else {
                    classicBase(opacity: xp.currentPreset.overlayOpacity)
                }
            } else {
                classicBase(opacity: xp.currentPreset.overlayOpacity)
            }

            // ── 2. accent tint (always present, subtle) ───────────────
            LinearGradient(
                colors: [
                    HUDChrome.cyan.opacity(0.10),
                    Color.clear,
                    HUDChrome.rose.opacity(0.06),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // ── 3. top-edge ambient wash ──────────────────────────────
            LinearGradient(
                colors: [Color.white.opacity(0.07), Color.clear],
                startPoint: .top, endPoint: .center
            )

            // ── 4. mouse specular ─────────────────────────────────────
            if xp.has(.mouseSpecular) {
                GeometryReader { geo in
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.11),
                            Color.white.opacity(0.03),
                            Color.clear,
                        ]),
                        center: UnitPoint(x: mouse.x, y: 1.0 - mouse.y),
                        startRadius: 0,
                        endRadius: max(geo.size.width, geo.size.height) * 0.60
                    )
                }
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Edge glow

/// Canvas-drawn luminous rim: bright centre-top, corner halos, optional side bar.
struct HUDEdgeGlow: ViewModifier {
    @ObservedObject private var xp = HUDExperienceStore.shared
    var intensity: Double = 1.0

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if xp.has(.edgeGlow) {
                Canvas { ctx, size in
                    // Top-edge specular line
                    let edgeRect  = CGRect(x: 0, y: 0, width: size.width, height: 1.5)
                    let edgeGrad  = Gradient(stops: [
                        .init(color: .clear,                                      location: 0.00),
                        .init(color: Color.white.opacity(0.28 * intensity),       location: 0.30),
                        .init(color: HUDChrome.cyan.opacity(0.18 * intensity),    location: 0.50),
                        .init(color: Color.white.opacity(0.28 * intensity),       location: 0.70),
                        .init(color: .clear,                                      location: 1.00),
                    ])
                    ctx.fill(
                        Path(edgeRect),
                        with: .linearGradient(
                            edgeGrad,
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint:   CGPoint(x: size.width, y: 0)
                        )
                    )

                    // Corner halos
                    let r: CGFloat = 72
                    for cx in [CGFloat(0), size.width] {
                        let haloRect = CGRect(x: cx - r, y: -r * 0.4, width: r * 2, height: r)
                        ctx.fill(
                            Path(ellipseIn: haloRect),
                            with: .color(Color.white.opacity(0.045 * intensity))
                        )
                    }
                }
                .frame(height: 72)
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func hudEdgeGlow(intensity: Double = 1.0) -> some View {
        modifier(HUDEdgeGlow(intensity: intensity))
    }
}

// MARK: - Hairline

struct HUDHairline: View {
    enum Axis { case horizontal, vertical }
    var axis: Axis = .horizontal
    var opacity: Double = 1

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.03 * opacity),
                        Color.white.opacity(0.18 * opacity),
                        HUDChrome.cyan.opacity(0.16 * opacity),
                        Color.white.opacity(0.04 * opacity),
                    ],
                    startPoint: axis == .horizontal ? .leading : .top,
                    endPoint:   axis == .horizontal ? .trailing : .bottom
                )
            )
            .frame(
                width:  axis == .vertical   ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
    }
}

// MARK: - Glass surface

struct HUDGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 10
    var active: Bool  = false
    var hovered: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        active  ? HUDChrome.glassFillStrong
                                : (hovered ? Color.white.opacity(0.06) : HUDChrome.glassFill)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        active  ? HUDChrome.cyan.opacity(0.28)
                                : (hovered ? HUDChrome.glassStroke : HUDChrome.glassStrokeSoft),
                        lineWidth: 0.75
                    )
            )
            .shadow(
                color: Color.black.opacity(active ? 0.32 : 0.18),
                radius: active ? 14 : 8,
                y: active ? 7 : 3
            )
    }
}

extension View {
    func hudGlass(cornerRadius: CGFloat = 10, active: Bool = false, hovered: Bool = false) -> some View {
        modifier(HUDGlassSurface(cornerRadius: cornerRadius, active: active, hovered: hovered))
    }
}
