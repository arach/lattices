import SwiftUI

enum HUDChrome {
    static let baseTop = Color(red: 0.055, green: 0.060, blue: 0.070)
    static let baseBottom = Color(red: 0.025, green: 0.027, blue: 0.034)
    static let glassFill = Color.white.opacity(0.045)
    static let glassFillStrong = Color.white.opacity(0.075)
    static let glassStroke = Color.white.opacity(0.13)
    static let glassStrokeSoft = Color.white.opacity(0.07)
    static let cyan = Color(red: 0.34, green: 0.78, blue: 0.96)
    static let rose = Color(red: 1.0, green: 0.42, blue: 0.58)
    static let amber = Palette.detach

    static var activeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Palette.running.opacity(0.95),
                cyan.opacity(0.90),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct HUDPanelBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    HUDChrome.baseTop.opacity(0.94),
                    HUDChrome.baseBottom.opacity(0.96),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    HUDChrome.cyan.opacity(0.12),
                    Color.clear,
                    HUDChrome.rose.opacity(0.07),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.07),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
    }
}

struct HUDHairline: View {
    enum Axis {
        case horizontal
        case vertical
    }

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
                    endPoint: axis == .horizontal ? .trailing : .bottom
                )
            )
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
    }
}

struct HUDGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 10
    var active: Bool = false
    var hovered: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        active
                            ? HUDChrome.glassFillStrong
                            : (hovered ? Color.white.opacity(0.06) : HUDChrome.glassFill)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        active
                            ? HUDChrome.cyan.opacity(0.28)
                            : (hovered ? HUDChrome.glassStroke : HUDChrome.glassStrokeSoft),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: Color.black.opacity(active ? 0.32 : 0.18), radius: active ? 14 : 8, y: active ? 7 : 3)
    }
}

extension View {
    func hudGlass(cornerRadius: CGFloat = 10, active: Bool = false, hovered: Bool = false) -> some View {
        modifier(HUDGlassSurface(cornerRadius: cornerRadius, active: active, hovered: hovered))
    }
}
