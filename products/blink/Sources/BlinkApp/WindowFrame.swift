import AppKit
import SwiftUI

/// Native counterpart of HudsonKit's web `HudWindowFrame`: a side-nav window
/// with a transparent title bar (`fullSizeContentView`), where the traffic
/// lights sit over the content. Shaped for upstreaming into HudsonUI.
///
/// Open, the sidebar's top strip holds the lights and drags the window. Folded
/// to the icon rail, the rail is too narrow for them, so:
///
///   1. a title bar grows across the window (0 → `titleBarHeight`, on the
///      rail's curve) holding the lights;
///   2. the bar and the rail form an L in the chrome color;
///   3. the content becomes an inset sheet with one curved top-leading corner,
///      and the sheet's own edge is the only line.
///
/// The `brand` sits after the lights in both states — over the sidebar strip
/// open, over the title bar folded — so it never moves.
///
/// The window must be `.titled` + `.fullSizeContentView` with a transparent,
/// hidden title; `WindowFrameChrome.configure(_:)` sets that up.
struct WindowFrame<Navigation: View, Content: View, Brand: View>: View {
    @ObservedObject var rail: WindowFrameRail
    var chrome: Color
    var sheet: Color
    var edge: Color
    var radius: CGFloat = 10
    var titleBarHeight: CGFloat = WindowFrameChrome.titleBarHeight
    var sidebarInset: CGFloat = WindowFrameChrome.sidebarInset
    @ViewBuilder var brand: () -> Brand
    /// Receives whether the rail is folded, to drop labels.
    @ViewBuilder var navigation: (_ folded: Bool) -> Navigation
    @ViewBuilder var content: () -> Content

    @State private var resizing = false

    private var folded: Bool { rail.folded }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    WindowDragArea()
                        .frame(height: folded ? 0 : sidebarInset)
                    navigation(folded)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(width: rail.width)
                .clipped()

                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(sheet)
                    .clipShape(SheetShape(radius: folded ? radius : 0))
                    .overlay(SheetEdge(radius: folded ? radius : 0, top: folded ? 1 : 0).stroke(edge, lineWidth: 1))
            }
            .overlay(alignment: .topLeading) {
                RailResizeHandle(rail: rail, resizing: $resizing, line: edge)
                    .offset(x: rail.width - RailResizeHandle.hitWidth / 2)
            }
        }
        .overlay(alignment: .topLeading) {
            brand()
                .frame(height: WindowFrameChrome.lightsCenterY * 2)
                .padding(.leading, WindowFrameChrome.lightsReserve)
                .allowsHitTesting(false)
        }
        .background(chrome)
        .ignoresSafeArea()
        .animation(resizing || Woven.reduceMotion ? nil : WindowFrameRail.motion, value: rail.folded)
        .animation(resizing || Woven.reduceMotion ? nil : WindowFrameRail.motion, value: rail.expandedWidth)
    }

    private var titleBar: some View {
        WindowDragArea()
            .frame(height: folded ? titleBarHeight : 0, alignment: .top)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityHidden(true)
    }
}

enum WindowFrameChrome {
    /// Folded title bar height; tall enough for the lights with the brand beside them.
    static let titleBarHeight: CGFloat = 38
    /// Open-state strip at the top of the sidebar that holds the lights.
    static let sidebarInset: CGFloat = 44
    /// The lights row is centered this far down; the brand starts at `lightsReserve`.
    static let lightsCenterY: CGFloat = 16
    static let lightsReserve: CGFloat = 84

    /// Transparent, hidden title over full-size content, as the frame expects.
    @MainActor static func configure(_ window: NSWindow) {
        window.styleMask.insert([.titled, .fullSizeContentView])
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
    }
}

// MARK: - Rail state

/// Fold state and remembered open width, persisted per device.
@MainActor
final class WindowFrameRail: ObservableObject {
    static let motion = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.18)
    /// Dragging this far inside the minimum width folds the rail.
    static let collapseMargin: CGFloat = 40
    /// Dragging a folded rail this far out opens it.
    static let expandTravel: CGFloat = 24

    @Published var folded: Bool { didSet { persist() } }
    @Published var expandedWidth: CGFloat { didSet { persist() } }

    let collapsedWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let defaultWidth: CGFloat
    private let persistKey: String?

    init(
        defaultWidth: CGFloat = 196,
        minWidth: CGFloat = 160,
        maxWidth: CGFloat = 300,
        collapsedWidth: CGFloat = 52,
        persistKey: String? = nil
    ) {
        self.defaultWidth = defaultWidth
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.collapsedWidth = collapsedWidth
        self.persistKey = persistKey
        let defaults = UserDefaults.standard
        let stored = persistKey.map { defaults.double(forKey: "\($0).width") } ?? 0
        expandedWidth = stored > 0 ? min(max(CGFloat(stored), minWidth), maxWidth) : defaultWidth
        folded = persistKey.map { defaults.bool(forKey: "\($0).folded") } ?? false
    }

    var width: CGFloat { folded ? collapsedWidth : expandedWidth }

    func toggle() { folded.toggle() }

    func clamp(_ width: CGFloat) -> CGFloat { min(max(width, minWidth), maxWidth) }

    private func persist() {
        guard let persistKey else { return }
        UserDefaults.standard.set(folded, forKey: "\(persistKey).folded")
        UserDefaults.standard.set(Double(expandedWidth), forKey: "\(persistKey).width")
    }
}

// MARK: - Pieces

/// The sidebar's edge: drag to resize, drag past the minimum to fold, drag a
/// folded rail out to open it, double-click to toggle. The sheet's edge is
/// already the line, so the handle only draws one on hover.
private struct RailResizeHandle: View {
    static let hitWidth: CGFloat = 8

    @ObservedObject var rail: WindowFrameRail
    @Binding var resizing: Bool
    var line: Color

    @State private var hovering = false
    @State private var startWidth: CGFloat?
    @State private var startedFolded = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: Self.hitWidth)
            .frame(maxHeight: .infinity)
            .overlay {
                Rectangle()
                    .fill(line)
                    .frame(width: 2)
                    .opacity(hovering || resizing ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: hovering || resizing)
            }
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .onTapGesture(count: 2) { rail.toggle() }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if startWidth == nil {
                            startedFolded = rail.folded
                            startWidth = rail.width
                            resizing = true
                        }
                        track(to: (startWidth ?? rail.width) + value.translation.width)
                    }
                    .onEnded { _ in
                        startWidth = nil
                        resizing = false
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Resize sidebar")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { rail.toggle() }
    }

    private func track(to raw: CGFloat) {
        if startedFolded, rail.folded {
            guard raw >= rail.collapsedWidth + WindowFrameRail.expandTravel else { return }
            rail.expandedWidth = rail.clamp(raw)
            rail.folded = false
            return
        }
        if raw <= rail.minWidth - WindowFrameRail.collapseMargin {
            if !rail.folded { withAnimation(WindowFrameRail.motion) { rail.folded = true } }
            return
        }
        if rail.folded { withAnimation(WindowFrameRail.motion) { rail.folded = false } }
        rail.expandedWidth = rail.clamp(raw)
    }
}

/// A strip that moves the window, and zooms it on double-click, like a title bar.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

/// The sheet's clip: only the top-leading corner curves.
private struct SheetShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(topLeading: radius))
    }
}

/// The sheet's left edge and, when `top` is 1, its top edge, joined by the
/// curved corner. Open, the left edge alone is the sidebar's rule.
private struct SheetEdge: Shape {
    var radius: CGFloat
    var top: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, top) }
        set { radius = newValue.first; top = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + 0.5
        let y = rect.minY + 0.5
        path.move(to: CGPoint(x: x, y: rect.maxY))
        path.addLine(to: CGPoint(x: x, y: y + radius))
        if radius > 0 {
            path.addArc(
                center: CGPoint(x: x + radius, y: y + radius),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }
        // The top edge draws out from the corner as the bar grows.
        if top > 0 {
            path.addLine(to: CGPoint(x: x + radius + (rect.width - radius) * top, y: y))
        }
        return path
    }
}
