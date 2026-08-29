import AppKit
import SwiftUI

/// Makes the title bar part of the app's surface instead of a system strip.
///
/// The default `NSWindow` paints `windowBackgroundColor` behind an opaque title
/// bar with a separator underneath. On a themed surface — Action's paper, or its
/// graphite — that reads as a stark strip pasted above the chrome, and no amount
/// of SwiftUI styling reaches it, because the title bar belongs to AppKit.
///
/// The fix is four settings that have to be made together: a transparent title
/// bar, a full-size content view so the app can draw under it, no separator, and
/// a window background in the app's own colour. Any one of them alone still
/// leaves a visible seam.
///
/// Borrowed from Linea's `HudWindowChrome` (`~/dev/hudson`), which solved this
/// first and states the same reasoning in its own comments.
enum ActionWindowChrome {
    /// The window ground. It is the rail colour, not the canvas: the title bar
    /// continues the sidebar's band across the top, so the two read as one piece
    /// of chrome rather than as a lid over the page.
    static var windowBackground: NSColor {
        ActionThemePalette.nsColor(.railBackground)
    }

    /// Height reserved at the top of the content for the title bar band.
    ///
    /// The traffic lights are laid out by AppKit and are ~16pt tall on a 28pt
    /// centre line; 38 gives them air without the band reading as a toolbar.
    static let titleBarHeight: CGFloat = 38

    /// Left inset that clears the traffic lights.
    ///
    /// Three 14pt buttons at 20pt centres from x=20 end at x=68; 78 leaves a
    /// deliberate gap rather than tucking content against the last light.
    static let trafficLightInset: CGFloat = 78

    static func apply(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = windowBackground
        window.isOpaque = true
        // The window is dragged by its title bar band, which is content now. The
        // rest of the surface is dense and clickable, so background dragging
        // would turn a mis-aimed click into a window move.
        window.isMovableByWindowBackground = false
        window.toolbar?.isVisible = false
    }
}
