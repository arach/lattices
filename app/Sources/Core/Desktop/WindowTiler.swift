import AppKit
import CoreGraphics

// Private API: get CGWindowID from an AXUIElement
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - SkyLight Private APIs (instant window moves, no animation)
// Loaded at runtime via dlsym — graceful fallback if unavailable.

private let skyLight: UnsafeMutableRawPointer? = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

private typealias SLSMainConnectionIDFunc = @convention(c) () -> Int32
private typealias SLSMoveWindowFunc = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGPoint>) -> CGError
private typealias SLSDisableUpdateFunc = @convention(c) (Int32) -> Int32
private typealias SLSReenableUpdateFunc = @convention(c) (Int32) -> Int32

private let _SLSMainConnectionID: SLSMainConnectionIDFunc? = {
    guard let sl = skyLight, let sym = dlsym(sl, "SLSMainConnectionID") else { return nil }
    return unsafeBitCast(sym, to: SLSMainConnectionIDFunc.self)
}()

private let _SLSMoveWindow: SLSMoveWindowFunc? = {
    guard let sl = skyLight, let sym = dlsym(sl, "SLSMoveWindow") else { return nil }
    return unsafeBitCast(sym, to: SLSMoveWindowFunc.self)
}()

private typealias SLSOrderWindowFunc = @convention(c) (Int32, UInt32, Int32, UInt32) -> CGError

private let _SLSOrderWindow: SLSOrderWindowFunc? = {
    guard let sl = skyLight, let sym = dlsym(sl, "SLSOrderWindow") ?? dlsym(sl, "CGSOrderWindow") else { return nil }
    return unsafeBitCast(sym, to: SLSOrderWindowFunc.self)
}()

private let _SLSDisableUpdate: SLSDisableUpdateFunc? = {
    guard let sl = skyLight, let sym = dlsym(sl, "SLSDisableUpdate") else { return nil }
    return unsafeBitCast(sym, to: SLSDisableUpdateFunc.self)
}()

private let _SLSReenableUpdate: SLSReenableUpdateFunc? = {
    guard let sl = skyLight, let sym = dlsym(sl, "SLSReenableUpdate") else { return nil }
    return unsafeBitCast(sym, to: SLSReenableUpdateFunc.self)
}()

// MARK: - Window Highlight Overlay

final class WindowHighlight {
    static let shared = WindowHighlight()

    private var overlayWindow: NSWindow?
    private var fadeTimer: Timer?

    /// Flash a green border overlay at the given screen frame
    func flash(frame: NSRect, duration: TimeInterval = 0.9) {
        dismiss()

        let inset: CGFloat = -6  // slightly larger than the window
        let expandedFrame = frame.insetBy(dx: inset, dy: inset)

        let window = NSWindow(
            contentRect: expandedFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let borderView = HighlightBorderView(frame: NSRect(origin: .zero, size: expandedFrame.size))
        window.contentView = borderView

        window.alphaValue = 0
        window.orderFrontRegardless()

        overlayWindow = window

        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 1.0
        }

        // Schedule fade out
        fadeTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
    }

    func dismiss() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }

    private func fadeOut() {
        guard let window = overlayWindow else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.dismiss()
        })
    }
}

private class HighlightBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let borderWidth: CGFloat = 3
        let cornerRadius: CGFloat = 12

        // Outer glow
        let glowRect = bounds.insetBy(dx: 1, dy: 1)
        let glowPath = NSBezierPath(roundedRect: glowRect, xRadius: cornerRadius + 2, yRadius: cornerRadius + 2)
        glowPath.lineWidth = borderWidth + 2
        NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.4, alpha: 0.07).setStroke()
        glowPath.stroke()

        // Main border
        let rect = bounds.insetBy(dx: borderWidth / 2 + 2, dy: borderWidth / 2 + 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = borderWidth
        NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.4, alpha: 0.58).setStroke()
        path.stroke()

        let innerRect = rect.insetBy(dx: 3, dy: 3)
        let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: max(cornerRadius - 3, 6), yRadius: max(cornerRadius - 3, 6))
        innerPath.lineWidth = 1
        NSColor.white.withAlphaComponent(0.10).setStroke()
        innerPath.stroke()
    }
}

// MARK: - Grid Tiling

/// Compute fractional (x, y, w, h) for a cell in a cols×rows grid.
func tileGrid(cols: Int, rows: Int, col: Int, row: Int) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    let w = 1.0 / CGFloat(cols)
    let h = 1.0 / CGFloat(rows)
    return (CGFloat(col) * w, CGFloat(row) * h, w, h)
}

/// Parse a grid string like "grid:3x2:0,0" → fractional (x, y, w, h).
func parseGridString(_ str: String) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
    GridPlacement.parse(str)?.fractions
}

enum TilePosition: String, CaseIterable, Identifiable {
    // 1x1
    case maximize    = "maximize"
    case center      = "center"
    // 2x1 (halves, full height)
    case left        = "left"
    case right       = "right"
    // 1x2 (halves, full width)
    case top         = "top"
    case bottom      = "bottom"
    // 2x2 (quarters)
    case topLeft     = "top-left"
    case topRight    = "top-right"
    case bottomLeft  = "bottom-left"
    case bottomRight = "bottom-right"
    // 3x1 (thirds, full height)
    case leftThird   = "left-third"
    case centerThird = "center-third"
    case rightThird  = "right-third"
    // 3x2 (sixths)
    case topLeftThird      = "top-left-third"
    case topCenterThird    = "top-center-third"
    case topRightThird     = "top-right-third"
    case bottomLeftThird   = "bottom-left-third"
    case bottomCenterThird = "bottom-center-third"
    case bottomRightThird  = "bottom-right-third"
    // 4x1 (fourths, full height)
    case firstFourth  = "first-fourth"
    case secondFourth = "second-fourth"
    case thirdFourth  = "third-fourth"
    case lastFourth   = "last-fourth"
    // 4x2 (eighths)
    case topFirstFourth    = "top-first-fourth"
    case topSecondFourth   = "top-second-fourth"
    case topThirdFourth    = "top-third-fourth"
    case topLastFourth     = "top-last-fourth"
    case bottomFirstFourth  = "bottom-first-fourth"
    case bottomSecondFourth = "bottom-second-fourth"
    case bottomThirdFourth  = "bottom-third-fourth"
    case bottomLastFourth   = "bottom-last-fourth"
    // Horizontal thirds / quarters
    case topThird    = "top-third"
    case middleThird = "middle-third"
    case bottomThird = "bottom-third"
    case leftQuarter   = "left-quarter"
    case rightQuarter  = "right-quarter"
    case topQuarter    = "top-quarter"
    case bottomQuarter = "bottom-quarter"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .maximize:    return "Max"
        case .center:      return "Center"
        case .left:        return "Left"
        case .right:       return "Right"
        case .top:         return "Top"
        case .bottom:      return "Bottom"
        case .topLeft:     return "Top Left"
        case .topRight:    return "Top Right"
        case .bottomLeft:  return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .leftThird:   return "Left ⅓"
        case .centerThird: return "Center ⅓"
        case .rightThird:  return "Right ⅓"
        case .topLeftThird:      return "Top Left ⅓"
        case .topCenterThird:    return "Top Center ⅓"
        case .topRightThird:     return "Top Right ⅓"
        case .bottomLeftThird:   return "Bottom Left ⅓"
        case .bottomCenterThird: return "Bottom Center ⅓"
        case .bottomRightThird:  return "Bottom Right ⅓"
        case .firstFourth:  return "1st ¼"
        case .secondFourth: return "2nd ¼"
        case .thirdFourth:  return "3rd ¼"
        case .lastFourth:   return "4th ¼"
        case .topFirstFourth:    return "Top 1st ¼"
        case .topSecondFourth:   return "Top 2nd ¼"
        case .topThirdFourth:    return "Top 3rd ¼"
        case .topLastFourth:     return "Top 4th ¼"
        case .bottomFirstFourth:  return "Bottom 1st ¼"
        case .bottomSecondFourth: return "Bottom 2nd ¼"
        case .bottomThirdFourth:  return "Bottom 3rd ¼"
        case .bottomLastFourth:   return "Bottom 4th ¼"
        case .topThird:    return "Top ⅓"
        case .middleThird: return "Middle ⅓"
        case .bottomThird: return "Bottom ⅓"
        case .leftQuarter:   return "Left ¼"
        case .rightQuarter:  return "Right ¼"
        case .topQuarter:    return "Top ¼"
        case .bottomQuarter: return "Bottom ¼"
        }
    }

    var icon: String {
        switch self {
        case .left:        return "rectangle.lefthalf.filled"
        case .right:       return "rectangle.righthalf.filled"
        case .top:         return "rectangle.tophalf.filled"
        case .bottom:      return "rectangle.bottomhalf.filled"
        case .topLeft:     return "rectangle.inset.topleft.filled"
        case .topRight:    return "rectangle.inset.topright.filled"
        case .bottomLeft:  return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .maximize:    return "rectangle.fill"
        case .center:      return "rectangle.center.inset.filled"
        case .leftThird:   return "rectangle.leadingthird.inset.filled"
        case .centerThird: return "rectangle.center.inset.filled"
        case .rightThird:  return "rectangle.trailingthird.inset.filled"
        case .topThird:    return "rectangle.topthird.inset.filled"
        case .middleThird: return "rectangle.center.inset.filled"
        case .bottomThird: return "rectangle.bottomthird.inset.filled"
        case .leftQuarter: return "rectangle.leadinghalf.inset.filled"
        case .rightQuarter:return "rectangle.trailinghalf.inset.filled"
        case .topQuarter:  return "rectangle.tophalf.inset.filled"
        case .bottomQuarter:return "rectangle.bottomhalf.inset.filled"
        default:           return "rectangle.split.3x3.fill"
        }
    }

    /// Returns (x, y, w, h) as fractions of screen
    var rect: (CGFloat, CGFloat, CGFloat, CGFloat) {
        switch self {
        // 1x1
        case .maximize:    return (0,     0,   1.0,   1.0)
        case .center:      return (0.15,  0.1, 0.7,   0.8)
        // 2x1
        case .left:        return tileGrid(cols: 2, rows: 1, col: 0, row: 0)
        case .right:       return tileGrid(cols: 2, rows: 1, col: 1, row: 0)
        // 1x2
        case .top:         return tileGrid(cols: 1, rows: 2, col: 0, row: 0)
        case .bottom:      return tileGrid(cols: 1, rows: 2, col: 0, row: 1)
        // 2x2
        case .topLeft:     return tileGrid(cols: 2, rows: 2, col: 0, row: 0)
        case .topRight:    return tileGrid(cols: 2, rows: 2, col: 1, row: 0)
        case .bottomLeft:  return tileGrid(cols: 2, rows: 2, col: 0, row: 1)
        case .bottomRight: return tileGrid(cols: 2, rows: 2, col: 1, row: 1)
        // 3x1
        case .leftThird:   return tileGrid(cols: 3, rows: 1, col: 0, row: 0)
        case .centerThird: return tileGrid(cols: 3, rows: 1, col: 1, row: 0)
        case .rightThird:  return tileGrid(cols: 3, rows: 1, col: 2, row: 0)
        // 3x2
        case .topLeftThird:      return tileGrid(cols: 3, rows: 2, col: 0, row: 0)
        case .topCenterThird:    return tileGrid(cols: 3, rows: 2, col: 1, row: 0)
        case .topRightThird:     return tileGrid(cols: 3, rows: 2, col: 2, row: 0)
        case .bottomLeftThird:   return tileGrid(cols: 3, rows: 2, col: 0, row: 1)
        case .bottomCenterThird: return tileGrid(cols: 3, rows: 2, col: 1, row: 1)
        case .bottomRightThird:  return tileGrid(cols: 3, rows: 2, col: 2, row: 1)
        // 4x1
        case .firstFourth:  return tileGrid(cols: 4, rows: 1, col: 0, row: 0)
        case .secondFourth: return tileGrid(cols: 4, rows: 1, col: 1, row: 0)
        case .thirdFourth:  return tileGrid(cols: 4, rows: 1, col: 2, row: 0)
        case .lastFourth:   return tileGrid(cols: 4, rows: 1, col: 3, row: 0)
        // 4x2
        case .topFirstFourth:    return tileGrid(cols: 4, rows: 2, col: 0, row: 0)
        case .topSecondFourth:   return tileGrid(cols: 4, rows: 2, col: 1, row: 0)
        case .topThirdFourth:    return tileGrid(cols: 4, rows: 2, col: 2, row: 0)
        case .topLastFourth:     return tileGrid(cols: 4, rows: 2, col: 3, row: 0)
        case .bottomFirstFourth:  return tileGrid(cols: 4, rows: 2, col: 0, row: 1)
        case .bottomSecondFourth: return tileGrid(cols: 4, rows: 2, col: 1, row: 1)
        case .bottomThirdFourth:  return tileGrid(cols: 4, rows: 2, col: 2, row: 1)
        case .bottomLastFourth:   return tileGrid(cols: 4, rows: 2, col: 3, row: 1)
        case .topThird:    return tileGrid(cols: 1, rows: 3, col: 0, row: 0)
        case .middleThird: return tileGrid(cols: 1, rows: 3, col: 0, row: 1)
        case .bottomThird: return tileGrid(cols: 1, rows: 3, col: 0, row: 2)
        case .leftQuarter:   return tileGrid(cols: 4, rows: 1, col: 0, row: 0)
        case .rightQuarter:  return tileGrid(cols: 4, rows: 1, col: 3, row: 0)
        case .topQuarter:    return tileGrid(cols: 1, rows: 4, col: 0, row: 0)
        case .bottomQuarter: return tileGrid(cols: 1, rows: 4, col: 0, row: 3)
        }
    }
}

// MARK: - Private CGS API for Spaces (loaded dynamically from SkyLight)

struct SpaceInfo: Identifiable {
    let id: Int      // CGS space ID
    let index: Int   // 1-based index within its display
    let display: Int // 0-based display index
    let isCurrent: Bool
}

struct DisplaySpaces {
    let displayIndex: Int
    let displayId: String
    let spaces: [SpaceInfo]
    let currentSpaceId: Int
}

private enum CGS {
    // Use Int32 for CGS connection IDs (C `int`), UInt64 for space IDs
    typealias MainConnectionIDFunc = @convention(c) () -> Int32
    typealias GetActiveSpaceFunc = @convention(c) (Int32) -> UInt64
    typealias CopyManagedDisplaySpacesFunc = @convention(c) (Int32) -> CFArray
    typealias CopySpacesForWindowsFunc = @convention(c) (Int32, Int32, CFArray) -> CFArray
    typealias SetCurrentSpaceFunc = @convention(c) (Int32, CFString, UInt64) -> Void

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    static let mainConnectionID: MainConnectionIDFunc? = {
        guard let h = handle, let sym = dlsym(h, "CGSMainConnectionID") else { return nil }
        return unsafeBitCast(sym, to: MainConnectionIDFunc.self)
    }()

    static let getActiveSpace: GetActiveSpaceFunc? = {
        guard let h = handle, let sym = dlsym(h, "CGSGetActiveSpace") else { return nil }
        return unsafeBitCast(sym, to: GetActiveSpaceFunc.self)
    }()

    static let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFunc? = {
        guard let h = handle, let sym = dlsym(h, "CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(sym, to: CopyManagedDisplaySpacesFunc.self)
    }()

    static let copySpacesForWindows: CopySpacesForWindowsFunc? = {
        guard let h = handle, let sym = dlsym(h, "SLSCopySpacesForWindows") else { return nil }
        return unsafeBitCast(sym, to: CopySpacesForWindowsFunc.self)
    }()

    static let setCurrentSpace: SetCurrentSpaceFunc? = {
        guard let h = handle, let sym = dlsym(h, "SLSManagedDisplaySetCurrentSpace") else { return nil }
        return unsafeBitCast(sym, to: SetCurrentSpaceFunc.self)
    }()

    // Move windows between spaces
    typealias AddWindowsToSpacesFunc = @convention(c) (Int32, CFArray, CFArray) -> Void
    typealias RemoveWindowsFromSpacesFunc = @convention(c) (Int32, CFArray, CFArray) -> Void

    static let addWindowsToSpaces: AddWindowsToSpacesFunc? = {
        guard let h = handle else { return nil }
        guard let sym = dlsym(h, "CGSAddWindowsToSpaces") ?? dlsym(h, "SLSAddWindowsToSpaces") else { return nil }
        return unsafeBitCast(sym, to: AddWindowsToSpacesFunc.self)
    }()

    static let removeWindowsFromSpaces: RemoveWindowsFromSpacesFunc? = {
        guard let h = handle else { return nil }
        guard let sym = dlsym(h, "CGSRemoveWindowsFromSpaces") ?? dlsym(h, "SLSRemoveWindowsFromSpaces") else { return nil }
        return unsafeBitCast(sym, to: RemoveWindowsFromSpacesFunc.self)
    }()
}

enum WindowTiler {
    /// Whether CGS move-between-spaces APIs are available
    static var canMoveWindowsBetweenSpaces: Bool {
        CGS.addWindowsToSpaces != nil && CGS.removeWindowsFromSpaces != nil
    }

    /// Convert fractional rect to AppleScript bounds {left, top, right, bottom}
    /// AppleScript uses top-left origin; NSScreen uses bottom-left origin
    private static func appleScriptBounds(for position: TilePosition, screen: NSScreen? = nil) -> (Int, Int, Int, Int) {
        appleScriptBounds(for: position.rect, screen: screen)
    }

    private static func appleScriptBounds(for fractions: (CGFloat, CGFloat, CGFloat, CGFloat), screen: NSScreen? = nil) -> (Int, Int, Int, Int) {
        let targetScreen = screen ?? NSScreen.main
        guard let targetScreen else { return (0, 0, 960, 540) }
        let full = targetScreen.frame
        let visible = targetScreen.visibleFrame

        let visTop = Int(full.height - visible.maxY)
        let visLeft = Int(visible.minX)
        let visW = Int(visible.width)
        let visH = Int(visible.height)

        let (fx, fy, fw, fh) = fractions
        let x1 = visLeft + Int(CGFloat(visW) * fx)
        let y1 = visTop + Int(CGFloat(visH) * fy)
        let x2 = x1 + Int(CGFloat(visW) * fw)
        let y2 = y1 + Int(CGFloat(visH) * fh)
        return (x1, y1, x2, y2)
    }

    /// Get the main screen's frame (safe to call from main thread only).
    static func mainScreenFrame() -> CGRect {
        return NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    /// Compute AX-coordinate frame for a tile position on a given screen
    static func tileFrame(for position: TilePosition, on screen: NSScreen) -> CGRect {
        tileFrame(fractions: position.rect, on: screen)
    }

    /// Compute AX-coordinate frame for arbitrary fractional placement on a given screen.
    static func tileFrame(fractions: (CGFloat, CGFloat, CGFloat, CGFloat), on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        guard let primary = NSScreen.screens.first else { return .zero }
        let primaryH = primary.frame.height
        let axTop = primaryH - visible.maxY
        let (fx, fy, fw, fh) = fractions
        return CGRect(
            x: visible.origin.x + visible.width * fx,
            y: axTop + visible.height * fy,
            width: visible.width * fw,
            height: visible.height * fh
        )
    }

    static func tileFrame(for placement: PlacementSpec, on screen: NSScreen) -> CGRect {
        tileFrame(fractions: placement.fractions, on: screen)
    }

    /// Compute AX-coordinate frame for a tile position within a raw display CGRect (CG/AX coords)
    static func tileFrame(for position: TilePosition, inDisplay displayRect: CGRect) -> CGRect {
        let (fx, fy, fw, fh) = position.rect
        return CGRect(
            x: displayRect.origin.x + displayRect.width * fx,
            y: displayRect.origin.y + displayRect.height * fy,
            width: displayRect.width * fw,
            height: displayRect.height * fh
        )
    }

    /// Compute AX-coordinate frame from fractional (x, y, w, h) within a raw display CGRect
    static func tileFrame(fractions: (CGFloat, CGFloat, CGFloat, CGFloat), inDisplay displayRect: CGRect) -> CGRect {
        let (fx, fy, fw, fh) = fractions
        return CGRect(
            x: displayRect.origin.x + displayRect.width * fx,
            y: displayRect.origin.y + displayRect.height * fy,
            width: displayRect.width * fw,
            height: displayRect.height * fh
        )
    }

    /// Tile a specific terminal window on a given screen.
    /// Fast path: DesktopModel → AX. Fallback: AX search → AppleScript last resort.
    static func tile(session: String, terminal: Terminal, to position: TilePosition, on screen: NSScreen) {
        tile(session: session, terminal: terminal, to: .tile(position), on: screen)
    }

    static func tile(session: String, terminal: Terminal, to placement: PlacementSpec, on screen: NSScreen) {
        let diag = DiagnosticLog.shared
        let t = diag.startTimed("tile: \(session) → \(placement.wireValue)")

        // Fast path: use DesktopModel cache → single AX move
        if let entry = DesktopModel.shared.windowForSession(session) {
            let frame = tileFrame(for: placement, on: screen)
            batchMoveAndRaiseWindows([(wid: entry.wid, pid: entry.pid, frame: frame)])
            diag.success("tile fast path (DesktopModel): \(session)")
            diag.finish(t)
            return
        }

        // AX fallback: search terminal windows by title tag
        let tag = Terminal.windowTag(for: session)
        if let (pid, axWindow) = findWindowViaAX(terminal: terminal, tag: tag) {
            let targetFrame = tileFrame(for: placement, on: screen)
            var newPos = CGPoint(x: targetFrame.origin.x, y: targetFrame.origin.y)
            var newSize = CGSize(width: targetFrame.width, height: targetFrame.height)
            let win = axWindow
            if let sv = AXValueCreate(.cgSize, &newSize) {
                AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sv)
            }
            if let pv = AXValueCreate(.cgPoint, &newPos) {
                AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pv)
            }
            if let sv = AXValueCreate(.cgSize, &newSize) {
                AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sv)
            }
            if let pv = AXValueCreate(.cgPoint, &newPos) {
                AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pv)
            }
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
            if let app = NSRunningApplication(processIdentifier: pid) { app.activate() }
            diag.success("tile AX fallback: \(session)")
            diag.finish(t)
            return
        }

        // AppleScript last resort (slow, single-monitor)
        diag.warn("tile AppleScript last resort: \(session)")
        let bounds = appleScriptBounds(for: placement.fractions, screen: screen)
        switch terminal {
        case .terminal:
            tileAppleScript(app: "Terminal", tag: tag, bounds: bounds)
        case .iterm2:
            tileAppleScript(app: "iTerm2", tag: tag, bounds: bounds)
        default:
            tileFrontmost(bounds: bounds)
        }
        diag.finish(t)
    }

    /// Tile a specific terminal window (found by lattices session tag) to a position.
    /// Uses the same fast path strategy as tile(session:terminal:to:on:) with main screen.
    static func tile(session: String, terminal: Terminal, to position: TilePosition) {
        tile(session: session, terminal: terminal, to: .tile(position))
    }

    static func tile(session: String, terminal: Terminal, to placement: PlacementSpec) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        tile(session: session, terminal: terminal, to: placement, on: screen)
    }

    /// Tile the frontmost window (works for any terminal)
    static func tileFrontmost(to position: TilePosition) {
        tileFrontmost(bounds: appleScriptBounds(for: position))
    }

    // MARK: - Spaces

    /// Get spaces organized by display
    static func getDisplaySpaces() -> [DisplaySpaces] {
        guard let mainConn = CGS.mainConnectionID,
              let copyManaged = CGS.copyManagedDisplaySpaces else { return [] }

        let cid = mainConn()
        guard let managed = copyManaged(cid) as? [[String: Any]] else { return [] }

        var result: [DisplaySpaces] = []
        for (displayIdx, display) in managed.enumerated() {
            let displayId = display["Display Identifier"] as? String ?? ""
            let rawSpaces = display["Spaces"] as? [[String: Any]] ?? []
            let currentDict = display["Current Space"] as? [String: Any]
            let currentId = currentDict?["id64"] as? Int ?? currentDict?["ManagedSpaceID"] as? Int ?? 0

            var spaces: [SpaceInfo] = []
            for (spaceIdx, space) in rawSpaces.enumerated() {
                let sid = space["id64"] as? Int ?? space["ManagedSpaceID"] as? Int ?? 0
                let type = space["type"] as? Int ?? 0
                if type == 0 {
                    spaces.append(SpaceInfo(
                        id: sid,
                        index: spaceIdx + 1,
                        display: displayIdx,
                        isCurrent: sid == currentId
                    ))
                }
            }

            result.append(DisplaySpaces(
                displayIndex: displayIdx,
                displayId: displayId,
                spaces: spaces,
                currentSpaceId: currentId
            ))
        }
        return result
    }

    /// Get the current active Space ID
    static func getCurrentSpace() -> Int {
        guard let mainConn = CGS.mainConnectionID, let getActive = CGS.getActiveSpace else { return 0 }
        return Int(getActive(mainConn()))
    }

    /// Find a window by its title tag and return its CGWindowID and owner PID
    static func findWindow(tag: String) -> (wid: UInt32, pid: pid_t)? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in windowList {
            if let name = info[kCGWindowName as String] as? String,
               name.contains(tag),
               let wid = info[kCGWindowNumber as String] as? UInt32,
               let pid = info[kCGWindowOwnerPID as String] as? pid_t {
                return (wid, pid)
            }
        }
        return nil
    }

    /// Get the space ID(s) a window is on
    static func getSpacesForWindow(_ wid: UInt32) -> [Int] {
        guard let mainConn = CGS.mainConnectionID,
              let copySpaces = CGS.copySpacesForWindows else { return [] }
        let cid = mainConn()
        let arr = [NSNumber(value: wid)] as CFArray
        guard let result = copySpaces(cid, 0x7, arr) as? [NSNumber] else { return [] }
        return result.map { $0.intValue }
    }

    /// Switch a display to a specific Space
    static func switchToSpace(spaceId: Int) {
        guard let mainConn = CGS.mainConnectionID,
              let setSpace = CGS.setCurrentSpace else { return }

        let cid = mainConn()

        // Find which display this space belongs to
        let allDisplays = getDisplaySpaces()
        for display in allDisplays {
            if display.spaces.contains(where: { $0.id == spaceId }) {
                setSpace(cid, display.displayId as CFString, UInt64(spaceId))
                return
            }
        }
    }

    // MARK: - Move Window Between Spaces

    enum MoveResult {
        case success(method: String)
        case alreadyOnSpace
        case windowNotFound
        case failed(reason: String)
    }

    /// Move a session's terminal window to a different Space.
    /// Note: On macOS 14.5+ the CGS move APIs are silently denied.
    /// When that happens we fall back to just switching the user's view.
    static func moveWindowToSpace(session: String, terminal: Terminal, spaceId: Int) -> MoveResult {
        let diag = DiagnosticLog.shared
        let tag = Terminal.windowTag(for: session)
        diag.info("moveWindowToSpace: session=\(session) tag=\(tag) targetSpace=\(spaceId)")

        // Find the window — CG first, then AX→CG fallback
        let wid: UInt32
        if let (w, _) = findWindow(tag: tag) {
            wid = w
            diag.info("moveWindowToSpace: found via CG wid=\(w)")
        } else if let (pid, axWindow) = findWindowViaAX(terminal: terminal, tag: tag),
                  let w = matchCGWindow(pid: pid, axWindow: axWindow) {
            wid = w
            diag.info("moveWindowToSpace: found via AX→CG wid=\(w)")
        } else {
            diag.warn("moveWindowToSpace: window not found for tag \(tag) — switching view only")
            switchToSpace(spaceId: spaceId)
            return .windowNotFound
        }

        // Check current spaces
        let currentSpaces = getSpacesForWindow(wid)
        diag.info("moveWindowToSpace: wid=\(wid) currentSpaces=\(currentSpaces)")
        if currentSpaces.contains(spaceId) {
            diag.info("moveWindowToSpace: already on target space — switching view")
            switchToSpace(spaceId: spaceId)
            return .alreadyOnSpace
        }

        // Try CGS direct move (works on older macOS, silently denied on 14.5+)
        if let result = moveViaCGS(wid: wid, fromSpaces: currentSpaces, toSpace: spaceId) {
            return result
        }

        // CGS unavailable — just switch the user's view
        diag.info("moveWindowToSpace: CGS unavailable, switching view to space")
        switchToSpace(spaceId: spaceId)
        return .success(method: "switch-view")
    }

    /// Attempt CGS-based window move. Returns nil if APIs are unavailable.
    /// Move a window between spaces via CGS private APIs. Internal — used by present() and moveWindowToSpace().
    internal static func moveViaCGS(wid: UInt32, fromSpaces: [Int], toSpace: Int) -> MoveResult? {
        let diag = DiagnosticLog.shared
        guard let mainConn = CGS.mainConnectionID,
              let addToSpaces = CGS.addWindowsToSpaces,
              let removeFromSpaces = CGS.removeWindowsFromSpaces else {
            return nil
        }

        let cid = mainConn()
        let windowArray = [NSNumber(value: wid)] as CFArray
        let targetArray = [NSNumber(value: toSpace)] as CFArray

        addToSpaces(cid, windowArray, targetArray)
        if !fromSpaces.isEmpty {
            let sourceArray = fromSpaces.map { NSNumber(value: $0) } as CFArray
            removeFromSpaces(cid, windowArray, sourceArray)
        }

        // Verify the move took effect (macOS 14.5+ silently denies)
        let newSpaces = getSpacesForWindow(wid)
        if newSpaces.contains(toSpace) && !fromSpaces.allSatisfy({ newSpaces.contains($0) }) {
            diag.success("moveViaCGS: successfully moved wid=\(wid) to space \(toSpace)")
            return .success(method: "CGS")
        }

        // CGS was silently denied — switch the view instead
        diag.warn("moveViaCGS: silently denied (macOS 14.5+ restriction) — switching view")
        switchToSpace(spaceId: toSpace)
        return .success(method: "switch-view")
    }

    /// Navigate to a session's window: switch to its Space, raise it, highlight it
    /// Falls back through CG → AX → AppleScript depending on available permissions
    static func navigateToWindow(session: String, terminal: Terminal) {
        let diag = DiagnosticLog.shared
        let t = diag.startTimed("navigateToWindow: \(session)")
        let tag = Terminal.windowTag(for: session)

        // Path 1: CG window lookup (needs Screen Recording permission for window names)
        if let (wid, pid) = findWindow(tag: tag) {
            diag.success("Path 1 (CG): found wid=\(wid) pid=\(pid)")
            navigateToKnownWindow(wid: wid, pid: pid, tag: tag, session: session, terminal: terminal)
            diag.finish(t)
            return
        }
        diag.warn("Path 1 (CG): findWindow failed — no Screen Recording?")

        // Path 2: AX API fallback (needs Accessibility permission)
        if let (pid, axWindow) = findWindowViaAX(terminal: terminal, tag: tag) {
            diag.success("Path 2 (AX): found window for \(terminal.rawValue) pid=\(pid)")
            // Try to match AX window → CG window for space switching
            if let wid = matchCGWindow(pid: pid, axWindow: axWindow) {
                diag.success("Path 2 (AX→CG): matched CG wid=\(wid)")
                navigateToKnownWindow(wid: wid, pid: pid, tag: tag, session: session, terminal: terminal)
            } else {
                diag.warn("Path 2 (AX): no CG match — raising without space switch")
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate()
                }
                if let frame = axWindowFrame(axWindow) {
                    diag.info("Highlighting via AX frame: \(frame)")
                    DispatchQueue.main.async { WindowHighlight.shared.flash(frame: frame) }
                } else {
                    diag.error("axWindowFrame returned nil — no highlight")
                }
            }
            diag.finish(t)
            return
        }
        diag.warn("Path 2 (AX): findWindowViaAX failed — no Accessibility?")

        // Path 3: AppleScript / bare activate fallback
        diag.warn("Path 3: falling back to AppleScript/activate")
        activateViaAppleScript(session: session, tag: tag, terminal: terminal)
        diag.finish(t)
    }

    private static func navigateToKnownWindow(wid: UInt32, pid: pid_t, tag: String, session: String, terminal: Terminal) {
        let diag = DiagnosticLog.shared
        let windowSpaces = getSpacesForWindow(wid)
        let currentSpace = getCurrentSpace()
        diag.info("navigateToKnown: wid=\(wid) spaces=\(windowSpaces) current=\(currentSpace)")

        if let windowSpace = windowSpaces.first, windowSpace != currentSpace {
            diag.info("Switching from space \(currentSpace) → \(windowSpace)")
            switchToSpace(spaceId: windowSpace)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                raiseWindow(pid: pid, tag: tag, terminal: terminal)
                highlightWindow(session: session)
            }
        } else {
            diag.info("Window on current space — raising + highlighting")
            raiseWindow(pid: pid, tag: tag, terminal: terminal)
            highlightWindow(session: session)
        }
    }

    /// Find a terminal window by title tag using AX API (requires Accessibility permission)
    private static func findWindowViaAX(terminal: Terminal, tag: String) -> (pid: pid_t, window: AXUIElement)? {
        let diag = DiagnosticLog.shared
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == terminal.bundleId
        }) else {
            diag.error("findWindowViaAX: \(terminal.rawValue) (\(terminal.bundleId)) not running")
            return nil
        }

        let pid = app.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement] else {
            diag.error("findWindowViaAX: AX error \(err.rawValue) — Accessibility not granted?")
            return nil
        }

        diag.info("findWindowViaAX: \(windows.count) windows for \(terminal.rawValue), searching for \(tag)")
        for win in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? "<no title>"
            if title.contains(tag) {
                diag.success("findWindowViaAX: matched \"\(title)\"")
                return (pid, win)
            } else {
                diag.info("  skip: \"\(title)\"")
            }
        }
        diag.warn("findWindowViaAX: no window matched tag \(tag)")
        return nil
    }

    /// Match an AX window to its CG window ID using PID + bounds comparison
    private static func matchCGWindow(pid: pid_t, axWindow: AXUIElement) -> UInt32? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
        guard let pv = posRef, let sv = sizeRef else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)

        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }

        for info in windowList {
            guard let wPid = info[kCGWindowOwnerPID as String] as? pid_t,
                  wPid == pid,
                  let wid = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else { continue }
            var rect = CGRect.zero
            if CGRectMakeWithDictionaryRepresentation(boundsDict, &rect) {
                if abs(rect.origin.x - pos.x) < 2 && abs(rect.origin.y - pos.y) < 2 &&
                   abs(rect.width - size.width) < 2 && abs(rect.height - size.height) < 2 {
                    return wid
                }
            }
        }
        return nil
    }

    /// Get NSRect from an AX window element (AX uses top-left origin, convert to NS bottom-left)
    private static func axWindowFrame(_ window: AXUIElement) -> NSRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        guard let pv = posRef, let sv = sizeRef else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)

        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let primaryHeight = primaryScreen.frame.height
        return NSRect(x: pos.x, y: primaryHeight - pos.y - size.height, width: size.width, height: size.height)
    }

    /// Last-resort: use AppleScript for Terminal/iTerm2, or bare activate for others
    private static func activateViaAppleScript(session: String, tag: String, terminal: Terminal) {
        switch terminal {
        case .terminal:
            runScript("""
            tell application "Terminal"
                activate
                repeat with w in windows
                    if name of w contains "\(tag)" then
                        set index of w to 1
                        exit repeat
                    end if
                end repeat
            end tell
            """)
        case .iterm2:
            runScript("""
            tell application "iTerm2"
                activate
                repeat with w in windows
                    if name of w contains "\(tag)" then
                        select w
                        exit repeat
                    end if
                end repeat
            end tell
            """)
        default:
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == terminal.bundleId
            }) {
                app.activate()
            }
        }
    }

    /// Raise a specific window using AX API + AppleScript
    private static func raiseWindow(pid: pid_t, tag: String, terminal: Terminal) {
        let diag = DiagnosticLog.shared
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        var raised = false
        if err == .success, let windows = windowsRef as? [AXUIElement] {
            for win in windows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
                if let title = titleRef as? String, title.contains(tag) {
                    AXUIElementPerformAction(win, kAXRaiseAction as CFString)
                    AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
                    diag.success("raiseWindow: raised \"\(title)\"")
                    raised = true
                    break
                }
            }
        }
        if !raised {
            diag.warn("raiseWindow: could not find window with tag \(tag) via AX (err=\(err.rawValue))")
        }

        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
            diag.info("raiseWindow: activated \(app.localizedName ?? "pid:\(pid)")")
        }
    }

    // MARK: - Highlight

    /// Flash a highlight border around a session's terminal window
    static func highlightWindow(session: String) {
        let diag = DiagnosticLog.shared
        let tag = Terminal.windowTag(for: session)
        diag.info("highlightWindow: tag=\(tag)")

        // Path 1: CG approach (needs Screen Recording)
        if let (wid, _) = findWindow(tag: tag) {
            diag.info("highlight via CG: wid=\(wid)")
            guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
            for info in windowList {
                if let num = info[kCGWindowNumber as String] as? UInt32, num == wid,
                   let dict = info[kCGWindowBounds as String] as? NSDictionary {
                    var rect = CGRect.zero
                    if CGRectMakeWithDictionaryRepresentation(dict, &rect) {
                        guard let primaryScreen = NSScreen.screens.first else { return }
                        let primaryHeight = primaryScreen.frame.height
                        let nsRect = NSRect(
                            x: rect.origin.x,
                            y: primaryHeight - rect.origin.y - rect.height,
                            width: rect.width,
                            height: rect.height
                        )
                        diag.success("highlight CG flash at \(Int(nsRect.origin.x)),\(Int(nsRect.origin.y)) \(Int(nsRect.width))×\(Int(nsRect.height))")
                        DispatchQueue.main.async { WindowHighlight.shared.flash(frame: nsRect) }
                    }
                    return
                }
            }
            diag.warn("highlight CG: wid \(wid) not in window list")
            return
        }

        // Path 2: AX fallback — search installed terminals for the tagged window
        diag.info("highlight: CG failed, trying AX fallback across \(Terminal.installed.count) terminals")
        for terminal in Terminal.installed {
            if let (_, axWindow) = findWindowViaAX(terminal: terminal, tag: tag),
               let frame = axWindowFrame(axWindow) {
                diag.success("highlight AX flash at \(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))×\(Int(frame.height))")
                DispatchQueue.main.async { WindowHighlight.shared.flash(frame: frame) }
                return
            }
        }
        diag.error("highlight: no method found window — no highlight shown")
    }

    // MARK: - Window Info

    struct WindowInfo {
        let spaceIndex: Int           // 1-based space number
        let displayIndex: Int         // 0-based display index
        let tilePosition: TilePosition?  // inferred from bounds, nil if free-form
        let wid: UInt32
    }

    /// Get spatial info for a session's terminal window (space, display, tile position)
    static func getWindowInfo(session: String, terminal: Terminal) -> WindowInfo? {
        let tag = Terminal.windowTag(for: session)

        // Find the window
        let wid: UInt32
        if let (w, _) = findWindow(tag: tag) {
            wid = w
        } else if let (pid, axWindow) = findWindowViaAX(terminal: terminal, tag: tag),
                  let w = matchCGWindow(pid: pid, axWindow: axWindow) {
            wid = w
        } else {
            return nil
        }

        // Determine which space/display the window is on
        let windowSpaces = getSpacesForWindow(wid)
        let allDisplays = getDisplaySpaces()

        var spaceIndex = 1
        var displayIndex = 0

        if let windowSpaceId = windowSpaces.first {
            for display in allDisplays {
                if let space = display.spaces.first(where: { $0.id == windowSpaceId }) {
                    spaceIndex = space.index
                    displayIndex = display.displayIndex
                    break
                }
            }
        }

        let tile = inferTilePosition(wid: wid)

        return WindowInfo(
            spaceIndex: spaceIndex,
            displayIndex: displayIndex,
            tilePosition: tile,
            wid: wid
        )
    }

    /// Infer tile position from a window frame + screen without re-querying CGWindowList
    static func inferTilePosition(frame: WindowFrame, screen: NSScreen) -> TilePosition? {
        let visible = screen.visibleFrame
        let full = screen.frame

        // CG top-left origin → visible frame top-left origin
        let primaryHeight = NSScreen.screens.first?.frame.height ?? full.height
        let visTop = primaryHeight - visible.maxY
        let fx = (frame.x - visible.origin.x) / visible.width
        let fy = (frame.y - visTop) / visible.height
        let fw = frame.w / visible.width
        let fh = frame.h / visible.height

        let tolerance: CGFloat = 0.05

        for position in TilePosition.allCases {
            let (px, py, pw, ph) = position.rect
            if abs(fx - CGFloat(px)) < tolerance && abs(fy - CGFloat(py)) < tolerance &&
               abs(fw - CGFloat(pw)) < tolerance && abs(fh - CGFloat(ph)) < tolerance {
                return position
            }
        }
        return nil
    }

    /// Infer tile position from a window's current bounds relative to its screen
    private static func inferTilePosition(wid: UInt32) -> TilePosition? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // Find the window's bounds
        var windowRect = CGRect.zero
        for info in windowList {
            if let num = info[kCGWindowNumber as String] as? UInt32, num == wid,
               let dict = info[kCGWindowBounds as String] as? NSDictionary {
                CGRectMakeWithDictionaryRepresentation(dict, &windowRect)
                break
            }
        }
        guard windowRect.width > 0 else { return nil }

        // Find which screen contains the window center
        let centerX = windowRect.midX
        let centerY = windowRect.midY
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let primaryHeight = primaryScreen.frame.height

        // CG uses top-left origin; convert to NS bottom-left for screen matching
        let nsCenterY = primaryHeight - centerY

        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSPoint(x: centerX, y: nsCenterY))
        }) ?? NSScreen.main ?? primaryScreen

        let visible = screen.visibleFrame
        let full = screen.frame

        // Convert CG rect to fractional coordinates relative to visible frame
        // CG top-left origin → visible frame top-left origin
        let visTop = full.height - visible.maxY + full.origin.y
        let fx = (windowRect.origin.x - visible.origin.x) / visible.width
        let fy = (windowRect.origin.y - visTop) / visible.height
        let fw = windowRect.width / visible.width
        let fh = windowRect.height / visible.height

        let tolerance: CGFloat = 0.05

        for position in TilePosition.allCases {
            let (px, py, pw, ph) = position.rect
            if abs(fx - px) < tolerance && abs(fy - py) < tolerance &&
               abs(fw - pw) < tolerance && abs(fh - ph) < tolerance {
                return position
            }
        }

        return nil
    }

    // MARK: - By-ID Window Operations (Desktop Inventory)

    /// Navigate to an arbitrary window by its CG window ID: switch space, raise, highlight
    static func navigateToWindowById(wid: UInt32, pid: Int32) {
        let diag = DiagnosticLog.shared
        diag.info("navigateToWindowById: wid=\(wid) pid=\(pid)")

        // Switch to window's space if needed
        let windowSpaces = getSpacesForWindow(wid)
        let currentSpace = getCurrentSpace()

        if let windowSpace = windowSpaces.first, windowSpace != currentSpace {
            diag.info("Switching from space \(currentSpace) → \(windowSpace)")
            switchToSpace(spaceId: windowSpace)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                raiseWindowById(wid: wid, pid: pid)
                highlightWindowById(wid: wid)
            }
        } else {
            raiseWindowById(wid: wid, pid: pid)
            highlightWindowById(wid: wid)
        }
    }

    /// Flash a highlight border on any window by its CG window ID
    static func highlightWindowById(wid: UInt32) {
        guard let frame = cgWindowFrame(wid: wid) else {
            DiagnosticLog.shared.warn("highlightWindowById: no frame for wid=\(wid)")
            return
        }
        DispatchQueue.main.async { WindowHighlight.shared.flash(frame: frame) }
    }

    /// Tile any window by its CG window ID to a position.
    /// Delegates to `batchMoveAndRaiseWindows` which is the battle-tested path:
    /// uses `_AXUIElementGetWindow` for direct wid→AX mapping, disables enhanced UI,
    /// freezes screen rendering, and verifies+retries drifted windows.
    /// Tile a window using raw fractional coordinates.
    static func tileWindowById(wid: UInt32, pid: Int32, fractions: (CGFloat, CGFloat, CGFloat, CGFloat), on targetScreen: NSScreen? = nil) {
        let screen = targetScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = tileFrame(fractions: fractions, on: screen)
        DiagnosticLog.shared.info("tileWindowById: wid=\(wid) fractions=\(fractions) frame=(\(Int(frame.origin.x)),\(Int(frame.origin.y))) \(Int(frame.width))x\(Int(frame.height))")
        if let app = NSRunningApplication(processIdentifier: pid) { app.activate() }
        let moves = [(wid: wid, pid: pid, frame: frame)]
        batchMoveAndRaiseWindows(moves)
        let drifted = verifyMoves(moves)
        if !drifted.isEmpty {
            usleep(100_000)
            batchMoveAndRaiseWindows(drifted.map { (wid: $0.wid, pid: $0.pid, frame: $0.frame) })
        }
    }

    static func tileWindowById(wid: UInt32, pid: Int32, to position: TilePosition, on targetScreen: NSScreen? = nil) {
        tileWindowById(wid: wid, pid: pid, to: .tile(position), on: targetScreen)
    }

    static func tileWindowById(wid: UInt32, pid: Int32, to placement: PlacementSpec, on targetScreen: NSScreen? = nil) {
        let diag = DiagnosticLog.shared
        let screen = targetScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = tileFrame(for: placement, on: screen)

        diag.info("tileWindowById: wid=\(wid) pid=\(pid) pos=\(placement.wireValue) screen=\(screen.localizedName) frame=(\(Int(frame.origin.x)),\(Int(frame.origin.y))) \(Int(frame.width))x\(Int(frame.height))")

        // Focus the app so windows on other Spaces come to the current one
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }

        let moves = [(wid: wid, pid: pid, frame: frame)]
        batchMoveAndRaiseWindows(moves)

        // Verify and retry once if needed
        let drifted = verifyMoves(moves)
        if !drifted.isEmpty {
            diag.info("tileWindowById: wid=\(wid) drifted, retrying...")
            usleep(100_000)
            batchMoveAndRaiseWindows(drifted)
            let stillDrifted = verifyMoves(drifted)
            if stillDrifted.isEmpty {
                diag.success("tileWindowById: wid=\(wid) retry succeeded")
            } else {
                diag.warn("tileWindowById: wid=\(wid) still drifted after retry")
            }
        } else {
            diag.success("tileWindowById: tiled wid=\(wid) to \(placement.wireValue)")
        }
    }

    /// Distribute windows in a smart grid layout (delegates to batch operation)
    static func tileDistributeHorizontally(windows: [(wid: UInt32, pid: Int32)]) {
        batchRaiseAndDistribute(windows: windows)
    }

    /// Distribute ALL visible non-Lattices windows into a smart grid on the screen with the most windows.
    static func distributeVisible(reactivateLattices: Bool = true) {
        let diag = DiagnosticLog.shared
        let t = diag.startTimed("distributeVisible")

        let visible = visibleDistributableWindows()

        guard !visible.isEmpty else {
            diag.info("distributeVisible: no visible windows to distribute")
            diag.finish(t)
            return
        }

        let windows = visible.map { (wid: $0.wid, pid: $0.pid) }
        diag.info("distributeVisible: \(windows.count) windows")
        batchRaiseAndDistribute(windows: windows, reactivateLattices: reactivateLattices)
        diag.finish(t)
    }

    /// Distribute visible windows matching the frontmost app's broader type.
    /// Example: when the active app is a terminal, grid all visible terminal windows on that display.
    static func distributeVisibleByFrontmostType(reactivateLattices: Bool = true) {
        let diag = DiagnosticLog.shared
        let t = diag.startTimed("distributeVisibleByFrontmostType")

        let visible = visibleDistributableWindows()
        guard !visible.isEmpty else {
            diag.info("distributeVisibleByFrontmostType: no visible windows to distribute")
            diag.finish(t)
            return
        }

        let frontmostAppName = NSWorkspace.shared.frontmostApplication?.localizedName
        let anchor = frontmostAppName.flatMap { name in
            visible.first { $0.app.localizedCaseInsensitiveCompare(name) == .orderedSame }
        } ?? visible.first

        guard let anchor else {
            diag.info("distributeVisibleByFrontmostType: no anchor window resolved")
            diag.finish(t)
            return
        }

        let grouping = AppTypeClassifier.grouping(for: anchor.app)
        let anchorScreen = screenForWindowFrame(anchor.frame)
        let anchorScreenId = screenID(for: anchorScreen)

        let sameScreenMatches = visible.filter { entry in
            AppTypeClassifier.matches(entry.app, grouping: grouping) &&
            screenID(for: screenForWindowFrame(entry.frame)) == anchorScreenId
        }

        let matches = sameScreenMatches.isEmpty
            ? visible.filter { AppTypeClassifier.matches($0.app, grouping: grouping) }
            : sameScreenMatches

        guard !matches.isEmpty else {
            diag.info("distributeVisibleByFrontmostType: no matches for \(grouping.label)")
            diag.finish(t)
            return
        }

        let ordered = sortWindowsForGrid(matches)
        diag.info("distributeVisibleByFrontmostType: grouping=\(grouping.label) count=\(ordered.count) screen=\(anchorScreen.localizedName)")
        batchRaiseAndDistribute(
            windows: ordered.map { (wid: $0.wid, pid: $0.pid) },
            reactivateLattices: reactivateLattices
        )
        diag.finish(t)
    }

    /// Get NSRect (bottom-left origin) for a known CG window ID
    static func cgWindowFrame(wid: UInt32) -> NSRect? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in windowList {
            if let num = info[kCGWindowNumber as String] as? UInt32, num == wid,
               let dict = info[kCGWindowBounds as String] as? NSDictionary {
                var rect = CGRect.zero
                if CGRectMakeWithDictionaryRepresentation(dict, &rect) {
                    guard let primaryScreen = NSScreen.screens.first else { return nil }
                    let primaryHeight = primaryScreen.frame.height
                    return NSRect(
                        x: rect.origin.x,
                        y: primaryHeight - rect.origin.y - rect.height,
                        width: rect.width,
                        height: rect.height
                    )
                }
            }
        }
        return nil
    }

    /// Raise a window by matching its CG window ID to an AX element via frame comparison
    private static func raiseWindowById(wid: UInt32, pid: Int32) {
        let diag = DiagnosticLog.shared

        if let axWindow = findAXWindowByFrame(wid: wid, pid: pid) {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            diag.success("raiseWindowById: raised wid=\(wid)")
        } else {
            diag.warn("raiseWindowById: couldn't match AX window for wid=\(wid)")
        }

        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }

    /// Raise multiple windows at once, re-activating our app once at the end
    static func raiseWindowsAndReactivate(windows: [(wid: UInt32, pid: Int32)]) {
        let diag = DiagnosticLog.shared
        var activatedPids = Set<Int32>()
        for win in windows {
            if let axWindow = findAXWindowByFrame(wid: win.wid, pid: win.pid) {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            }
            if !activatedPids.contains(win.pid) {
                if let app = NSRunningApplication(processIdentifier: win.pid) {
                    app.activate()
                    activatedPids.insert(win.pid)
                }
            }
        }
        DesktopModel.shared.markInteraction(wids: windows.map(\.wid))
        diag.success("raiseWindowsAndReactivate: raised \(windows.count) windows")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Raise a window to front and then re-activate our own app so the panel stays visible
    static func raiseWindowAndReactivate(wid: UInt32, pid: Int32) {
        let diag = DiagnosticLog.shared
        diag.info("raiseWindowAndReactivate: wid=\(wid) pid=\(pid)")

        // Switch to window's space if needed
        let windowSpaces = getSpacesForWindow(wid)
        let currentSpace = getCurrentSpace()

        let doRaise = {
            if let axWindow = findAXWindowByFrame(wid: wid, pid: pid) {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                diag.success("raiseWindowAndReactivate: raised wid=\(wid)")
            }
            // Activate target app briefly so window comes to front
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.activate()
            }
            // Re-activate our app so the panel stays visible
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        if let windowSpace = windowSpaces.first, windowSpace != currentSpace {
            diag.info("Switching from space \(currentSpace) → \(windowSpace)")
            switchToSpace(spaceId: windowSpace)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { doRaise() }
        } else {
            doRaise()
        }
        DesktopModel.shared.markInteraction(wid: wid)
    }

    // MARK: - Batch Window Operations

    /// Move multiple windows to target frames in one shot.
    /// Single CGWindowList query, single AX query per process, all moves synchronous.
    static func batchMoveWindows(_ moves: [(wid: UInt32, pid: Int32, frame: CGRect)]) {
        guard !moves.isEmpty else { return }
        let diag = DiagnosticLog.shared

        // Group by pid so we query each app's AX windows once
        var byPid: [Int32: [(wid: UInt32, target: CGRect)]] = [:]
        for move in moves {
            byPid[move.pid, default: []].append((wid: move.wid, target: move.frame))
        }

        // For each process: get AX windows, match by CGWindowID, move+resize
        var moved = 0
        var failed = 0
        for (pid, windowMoves) in byPid {
            let appRef = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            guard err == .success, let axWindows = windowsRef as? [AXUIElement] else {
                diag.info("[batchMove] AX query failed for pid \(pid)")
                failed += windowMoves.count
                continue
            }

            // Build wid → AXUIElement map using _AXUIElementGetWindow
            var axByWid: [UInt32: AXUIElement] = [:]
            for axWin in axWindows {
                var windowId: CGWindowID = 0
                if _AXUIElementGetWindow(axWin, &windowId) == .success {
                    axByWid[windowId] = axWin
                }
            }

            for wm in windowMoves {
                guard let axWin = axByWid[wm.wid] else {
                    diag.info("[batchMove] no AX match for wid \(wm.wid)")
                    failed += 1
                    continue
                }

                applyFrameToAXWindow(axWin, wid: wm.wid, target: wm.target)
                moved += 1
            }
        }
        if failed > 0 {
            diag.info("[batchMove] \(failed) windows failed to match")
        }
        diag.success("batchMoveWindows: moved \(moved)/\(moves.count) windows")
    }

    /// Apply position+size to a single AX window. No delays, no retries — just set and go.
    private static func applyFrameToAXWindow(_ axWin: AXUIElement, wid: UInt32, target: CGRect) {
        var newPos = CGPoint(x: target.origin.x, y: target.origin.y)
        var newSize = CGSize(width: target.width, height: target.height)

        // Size first (avoids clipping at screen edges), then position
        if let sv = AXValueCreate(.cgSize, &newSize) {
            AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, sv)
        }
        if let pv = AXValueCreate(.cgPoint, &newPos) {
            AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, pv)
        }
    }

    /// Read back current AX position+size for a window element.
    static func readAXFrame(_ axWin: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }
        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: pos, size: size)
    }

    /// Verify which windows drifted from their targets using CGWindowList.
    /// Returns array of moves that still need correction.
    static func verifyMoves(_ moves: [(wid: UInt32, pid: Int32, frame: CGRect)], tolerance: CGFloat = 4) -> [(wid: UInt32, pid: Int32, frame: CGRect)] {
        guard let rawList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return moves  // can't verify, return all
        }

        var actualByWid: [UInt32: CGRect] = [:]
        for info in rawList {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat else { continue }
            actualByWid[wid] = CGRect(x: x, y: y, width: w, height: h)
        }

        let diag = DiagnosticLog.shared
        var drifted: [(wid: UInt32, pid: Int32, frame: CGRect)] = []
        for move in moves {
            guard let actual = actualByWid[move.wid] else {
                drifted.append(move)
                continue
            }
            let dx = abs(actual.origin.x - move.frame.origin.x)
            let dy = abs(actual.origin.y - move.frame.origin.y)
            let dw = abs(actual.width - move.frame.width)
            let dh = abs(actual.height - move.frame.height)
            if dx > tolerance || dy > tolerance || dw > tolerance || dh > tolerance {
                diag.info("[verify] wid \(move.wid) drifted: target \(move.frame) actual \(actual) (dx=\(Int(dx)) dy=\(Int(dy)) dw=\(Int(dw)) dh=\(Int(dh)))")
                drifted.append(move)
            }
        }
        return drifted
    }

    /// Raise and focus a single window by its CGWindowID.
    @discardableResult
    static func focusWindow(wid: UInt32, pid: Int32) -> Bool {
        return present(wid: wid, pid: pid)
    }

    // MARK: - Present

    /// Present a window: move it to the current space, bring it to front, optionally position it.
    /// This is the single entry point for "show me this window right now."
    @discardableResult
    static func present(wid: UInt32, pid: Int32, frame: CGRect? = nil) -> Bool {
        let diag = DiagnosticLog.shared

        // 1. Move to current space if needed
        let windowSpaces = getSpacesForWindow(wid)
        let currentSpace = getCurrentSpace()
        if currentSpace != 0, !windowSpaces.isEmpty, !windowSpaces.contains(currentSpace) {
            diag.info("present: wid \(wid) on space \(windowSpaces), moving to current space \(currentSpace)")
            _ = moveViaCGS(wid: wid, fromSpaces: windowSpaces, toSpace: currentSpace)
        }

        // 2. Position if requested
        if let frame = frame {
            if let mainConn = _SLSMainConnectionID, let moveWindow = _SLSMoveWindow {
                let cid = mainConn()
                var origin = CGPoint(x: frame.origin.x, y: frame.origin.y)
                moveWindow(cid, wid, &origin)
            }
            // Resize via AX
            let appRef = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let axWindows = windowsRef as? [AXUIElement] {
                for axWin in axWindows {
                    var windowId: CGWindowID = 0
                    if _AXUIElementGetWindow(axWin, &windowId) == .success, windowId == wid {
                        var size = CGSize(width: frame.width, height: frame.height)
                        let sizeValue = AXValueCreate(.cgSize, &size)!
                        AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, sizeValue)
                        break
                    }
                }
            }
        }

        // 3. Activate the app first (this may bring the wrong window forward)
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }

        // 4. Then order OUR window to front — after activate so we get the last word
        if let mainConn = _SLSMainConnectionID, let orderWindow = _SLSOrderWindow {
            let cid = mainConn()
            let err = orderWindow(cid, wid, 1, 0)
            if err != .success {
                diag.warn("present: SLSOrderWindow failed for wid \(wid): \(err)")
            }
        }

        // 5. Set as main window via AX
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let axWindows = windowsRef as? [AXUIElement] {
            for axWin in axWindows {
                var windowId: CGWindowID = 0
                if _AXUIElementGetWindow(axWin, &windowId) == .success, windowId == wid {
                    AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
                    break
                }
            }
        }

        // 6. Re-raise after delays to defeat focus stealing from the caller.
        // Two passes: early catch (200ms) and late catch (600ms) for slower responses.
        for delay in [0.2, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if let mainConn = _SLSMainConnectionID, let orderWindow = _SLSOrderWindow {
                    let cid = mainConn()
                    orderWindow(cid, wid, 1, 0)
                }
            }
        }

        DesktopModel.shared.markInteraction(wid: wid)
        return true
    }

    /// Move AND raise windows in a single CG+AX pass (avoids duplicate lookups).
    /// Does not reactivate lattices at the end — caller controls that.
    static func batchMoveAndRaiseWindows(_ moves: [(wid: UInt32, pid: Int32, frame: CGRect)]) {
        guard !moves.isEmpty else { return }
        let diag = DiagnosticLog.shared

        var byPid: [Int32: [(wid: UInt32, target: CGRect)]] = [:]
        for move in moves {
            byPid[move.pid, default: []].append((wid: move.wid, target: move.frame))
        }

        var processed = 0
        var activatedPids = Set<Int32>()

        // Freeze screen rendering for smooth batch moves
        let cid = _SLSMainConnectionID?()
        if let cid { _ = _SLSDisableUpdate?(cid) }

        for (pid, windowMoves) in byPid {
            let appRef = AXUIElementCreateApplication(pid)

            // Disable enhanced UI — breaks macOS tile lock so resize works
            AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, false as CFTypeRef)

            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            guard err == .success, let axWindows = windowsRef as? [AXUIElement] else { continue }

            // Build wid → AXUIElement map using _AXUIElementGetWindow
            var axByWid: [UInt32: AXUIElement] = [:]
            for axWin in axWindows {
                var windowId: CGWindowID = 0
                if _AXUIElementGetWindow(axWin, &windowId) == .success {
                    axByWid[windowId] = axWin
                }
            }

            for wm in windowMoves {
                guard let axWin = axByWid[wm.wid] else { continue }

                var newPos = CGPoint(x: wm.target.origin.x, y: wm.target.origin.y)
                var newSize = CGSize(width: wm.target.width, height: wm.target.height)

                // Size → Position → Size (same pattern as single-window tiler)
                if let sv = AXValueCreate(.cgSize, &newSize) {
                    AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, sv)
                }
                if let pv = AXValueCreate(.cgPoint, &newPos) {
                    AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, pv)
                }
                if let sv = AXValueCreate(.cgSize, &newSize) {
                    AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, sv)
                }

                // Raise
                AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString, kCFBooleanTrue)

                processed += 1
            }

            // Re-enable enhanced UI
            AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)

            // Activate each app once so its windows come to front
            if !activatedPids.contains(pid) {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate()
                    activatedPids.insert(pid)
                }
            }
        }

        // Unfreeze screen rendering
        if let cid { _ = _SLSReenableUpdate?(cid) }
        DesktopModel.shared.markInteraction(wids: moves.map(\.wid))
        diag.success("batchMoveAndRaiseWindows: processed \(processed)/\(moves.count) windows")
    }

    // MARK: - Grid Layout Strategy

    /// Optimal grid shapes for common window counts.
    /// Returns array of column counts per row (top row first).
    /// e.g. 5 → [3, 2] means 3 on top row, 2 on bottom row.
    static func gridShape(for count: Int) -> [Int] {
        switch count {
        case 1:  return [1]
        case 2:  return [2]
        case 3:  return [3]
        case 4:  return [2, 2]
        case 5:  return [3, 2]
        case 6:  return [3, 3]
        case 7:  return [4, 3]
        case 8:  return [4, 4]
        case 9:  return [3, 3, 3]
        case 10: return [5, 5]
        case 11: return [4, 4, 3]
        case 12: return [4, 4, 4]
        default:
            // General: bias toward more columns (landscape screens)
            let cols = Int(ceil(sqrt(Double(count) * 1.5)))
            var rows: [Int] = []
            var remaining = count
            while remaining > 0 {
                rows.append(min(cols, remaining))
                remaining -= cols
            }
            return rows
        }
    }

    /// Compute grid slot rects in AX coordinates (top-left origin) for N windows.
    /// If `region` is provided (fractional x, y, w, h), slots are constrained to that sub-area of the screen.
    static func computeGridSlots(count: Int, screen: NSScreen, region: (CGFloat, CGFloat, CGFloat, CGFloat)? = nil) -> [CGRect] {
        guard count > 0 else { return [] }
        let visible = screen.visibleFrame
        guard let primaryScreen = NSScreen.screens.first else { return [] }
        let primaryHeight = primaryScreen.frame.height

        // Compute the target area — full visible frame or a fractional sub-region
        let targetArea: CGRect
        if let (rx, ry, rw, rh) = region {
            targetArea = CGRect(
                x: visible.origin.x + visible.width * rx,
                y: visible.origin.y + visible.height * (1.0 - ry - rh),  // NSRect is bottom-left origin
                width: visible.width * rw,
                height: visible.height * rh
            )
        } else {
            targetArea = visible
        }

        // AX Y of target area's top edge
        let axTop = primaryHeight - targetArea.maxY
        let shape = gridShape(for: count)
        let rowCount = shape.count
        let rowH = targetArea.height / CGFloat(rowCount)

        var slots: [CGRect] = []
        for (row, cols) in shape.enumerated() {
            let colW = targetArea.width / CGFloat(cols)
            let axY = axTop + CGFloat(row) * rowH
            for col in 0..<cols {
                let x = targetArea.origin.x + CGFloat(col) * colW
                slots.append(CGRect(x: x, y: axY, width: colW, height: rowH))
            }
        }
        return slots
    }

    /// Raise multiple windows and arrange in smart grid — single CG query, single AX query per process.
    /// If `region` is provided (fractional x, y, w, h), the grid is constrained to that sub-area.
    static func batchRaiseAndDistribute(
        windows: [(wid: UInt32, pid: Int32)],
        region: (CGFloat, CGFloat, CGFloat, CGFloat)? = nil,
        reactivateLattices: Bool = true
    ) {
        guard !windows.isEmpty else { return }
        let diag = DiagnosticLog.shared

        // Find screen from first window
        guard let firstFrame = cgWindowFrame(wid: windows[0].wid) else {
            diag.warn("batchRaiseAndDistribute: no frame for first window wid=\(windows[0].wid)")
            return
        }
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSPoint(x: firstFrame.midX, y: firstFrame.midY))
        }) ?? NSScreen.main ?? NSScreen.screens[0]

        let visible = screen.visibleFrame
        let screenFrame = screen.frame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let shape = gridShape(for: windows.count)
        let desc = shape.map(String.init).joined(separator: "+")

        diag.info("Grid layout: \(windows.count) windows → [\(desc)]")
        diag.info("  Screen: \(screen.localizedName) \(Int(screenFrame.width))x\(Int(screenFrame.height))")
        diag.info("  Visible: origin=(\(Int(visible.origin.x)),\(Int(visible.origin.y))) size=\(Int(visible.width))x\(Int(visible.height))")
        if let region { diag.info("  Region: x=\(region.0) y=\(region.1) w=\(region.2) h=\(region.3)") }
        diag.info("  Primary height: \(Int(primaryHeight))")

        // Pre-compute all target slots
        let slots = computeGridSlots(count: windows.count, screen: screen, region: region)
        guard slots.count == windows.count else {
            diag.warn("  Slot count mismatch: \(slots.count) slots for \(windows.count) windows")
            return
        }

        for (i, slot) in slots.enumerated() {
            diag.info("  Slot \(i): x=\(Int(slot.origin.x)) y=\(Int(slot.origin.y)) w=\(Int(slot.width)) h=\(Int(slot.height))")
        }

        // Single CG query for frame lookup
        let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var cgFrames: [UInt32: CGRect] = [:]
        var cgNames: [UInt32: String] = [:]
        for info in windowList {
            guard let num = info[kCGWindowNumber as String] as? UInt32,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary else { continue }
            var rect = CGRect.zero
            if CGRectMakeWithDictionaryRepresentation(dict, &rect) { cgFrames[num] = rect }
            cgNames[num] = info[kCGWindowOwnerName as String] as? String
        }

        // Log before frames
        for (i, win) in windows.enumerated() {
            let app = cgNames[win.wid] ?? "?"
            if let cg = cgFrames[win.wid] {
                diag.info("  Before[\(i)] wid=\(win.wid) \(app): x=\(Int(cg.origin.x)) y=\(Int(cg.origin.y)) w=\(Int(cg.width)) h=\(Int(cg.height))")
            } else {
                diag.warn("  Before[\(i)] wid=\(win.wid) \(app): NO CG FRAME")
            }
        }

        // Group by pid for AX queries, keep slot mapping
        var byPid: [Int32: [(slotIdx: Int, wid: UInt32, target: CGRect)]] = [:]
        let moves: [(wid: UInt32, pid: Int32, frame: CGRect)] = windows.enumerated().map { index, win in
            let target = slots[index]
            byPid[win.pid, default: []].append((slotIdx: index, wid: win.wid, target: target))
            return (wid: win.wid, pid: win.pid, frame: target)
        }

        // Pass 1: Move all windows using exact wid→AX mapping.
        var moved = 0
        var failed: [UInt32] = []
        var resolvedAXElements: [(slotIdx: Int, el: AXUIElement)] = [] // for raise pass
        var activatedPids = Set<Int32>()

        let cid = _SLSMainConnectionID?()
        if let cid { _ = _SLSDisableUpdate?(cid) }

        for (pid, windowMoves) in byPid {
            let appRef = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, false as CFTypeRef)

            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            guard err == .success, let axWindows = windowsRef as? [AXUIElement] else {
                diag.warn("  AX query failed for pid=\(pid) err=\(err.rawValue)")
                failed.append(contentsOf: windowMoves.map(\.wid))
                AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
                continue
            }

            var axByWid: [UInt32: AXUIElement] = [:]
            for axWin in axWindows {
                var windowId: CGWindowID = 0
                if _AXUIElementGetWindow(axWin, &windowId) == .success {
                    axByWid[windowId] = axWin
                }
            }

            for wm in windowMoves {
                guard let axWin = axByWid[wm.wid] else {
                    if let cgRect = cgFrames[wm.wid] {
                        diag.warn("  wid=\(wm.wid): CG frame (\(Int(cgRect.origin.x)),\(Int(cgRect.origin.y)) \(Int(cgRect.width))x\(Int(cgRect.height))) — no AX wid match")
                    } else {
                        diag.warn("  wid=\(wm.wid): no CG frame and no AX wid match")
                    }
                    failed.append(wm.wid)
                    continue
                }

                var newPos = CGPoint(x: wm.target.origin.x, y: wm.target.origin.y)
                var newSize = CGSize(width: wm.target.width, height: wm.target.height)
                let sizeErr1 = AXValueCreate(.cgSize, &newSize).map {
                    AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, $0)
                }
                let posErr = AXValueCreate(.cgPoint, &newPos).map {
                    AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, $0)
                }
                let sizeErr2 = AXValueCreate(.cgSize, &newSize).map {
                    AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, $0)
                }
                diag.info("  Move[\(wm.slotIdx)] wid=\(wm.wid): target=(\(Int(wm.target.origin.x)),\(Int(wm.target.origin.y))) \(Int(wm.target.width))x\(Int(wm.target.height)) sizeErr1=\(sizeErr1?.rawValue ?? -1) posErr=\(posErr?.rawValue ?? -1) sizeErr2=\(sizeErr2?.rawValue ?? -1)")
                resolvedAXElements.append((slotIdx: wm.slotIdx, el: axWin))
                moved += 1
            }

            if !activatedPids.contains(pid) {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate()
                    activatedPids.insert(pid)
                }
            }

            AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
        }

        if let cid { _ = _SLSReenableUpdate?(cid) }

        // Pass 2: Raise all windows in slot order after app activation so final z-order matches the grid.
        resolvedAXElements.sort { $0.slotIdx < $1.slotIdx }
        for item in resolvedAXElements {
            AXUIElementPerformAction(item.el, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(item.el, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        diag.info("  Raised \(resolvedAXElements.count) windows in slot order")

        // Verify and retry drifted windows once using the battle-tested batch mover.
        let drifted = verifyMoves(moves)
        if !drifted.isEmpty {
            diag.warn("  Drifted after distribute: \(drifted.map(\.wid)) — retrying exact move path")
            usleep(100_000)
            batchMoveAndRaiseWindows(drifted)
            let stillDrifted = verifyMoves(drifted)
            if !stillDrifted.isEmpty {
                diag.warn("  Still drifted after retry: \(stillDrifted.map(\.wid))")
            }
        }

        if !failed.isEmpty {
            diag.warn("batchRaiseAndDistribute: failed wids=\(failed)")
        }
        DesktopModel.shared.markInteraction(wids: windows.map(\.wid))
        diag.success("batchRaiseAndDistribute: moved \(moved)/\(windows.count) [\(desc) grid]")
        if reactivateLattices {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Batch restore windows to saved frames (single CG query)
    static func batchRestoreWindows(_ restores: [(wid: UInt32, pid: Int32, frame: WindowFrame)]) {
        let moves = restores.map { (wid: $0.wid, pid: $0.pid,
                                     frame: CGRect(x: $0.frame.x, y: $0.frame.y,
                                                   width: $0.frame.w, height: $0.frame.h)) }
        batchMoveWindows(moves)
    }

    /// Restore a window to a saved frame (CG coordinates: top-left origin)
    static func restoreWindowFrame(wid: UInt32, pid: Int32, frame: WindowFrame) {
        guard let axWindow = findAXWindowByFrame(wid: wid, pid: pid) else {
            DiagnosticLog.shared.warn("restoreWindowFrame: couldn't match AX window for wid=\(wid)")
            return
        }
        var newPos = CGPoint(x: frame.x, y: frame.y)
        var newSize = CGSize(width: frame.w, height: frame.h)
        if let posValue = AXValueCreate(.cgPoint, &newPos) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &newSize) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        }
        DiagnosticLog.shared.success("restoreWindowFrame: restored wid=\(wid)")
    }

    /// Find the AX window element for a given CG window ID by matching frames
    static func findAXWindowByFrame(wid: UInt32, pid: Int32) -> AXUIElement? {
        // Get CG frame for the window
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }

        var cgRect = CGRect.zero
        for info in windowList {
            if let num = info[kCGWindowNumber as String] as? UInt32, num == wid,
               let dict = info[kCGWindowBounds as String] as? NSDictionary {
                CGRectMakeWithDictionaryRepresentation(dict, &cgRect)
                break
            }
        }
        guard cgRect.width > 0 else { return nil }

        // Find AX window with matching frame
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement] else { return nil }

        for win in windows {
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef)
            AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef)
            guard let pv = posRef, let sv = sizeRef else { continue }

            var pos = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sv as! AXValue, .cgSize, &size)

            if abs(cgRect.origin.x - pos.x) < 2 && abs(cgRect.origin.y - pos.y) < 2 &&
               abs(cgRect.width - size.width) < 2 && abs(cgRect.height - size.height) < 2 {
                return win
            }
        }
        return nil
    }

    // MARK: - Any-App Tiling via Accessibility

    /// Tile the frontmost window of any app to a position using AX API.
    /// Works for any application (Finder, Chrome, etc.), not just terminals.
    static func tileFrontmostViaAX(to position: TilePosition) {
        tileFrontmostViaAX(to: .tile(position))
    }

    static func tileFrontmostViaAX(to placement: PlacementSpec) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != "com.arach.lattices" else { return }

        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
              let axWindow = focusedRef else { return }
        let win = axWindow as! AXUIElement

        let screen = screenForAXWindow(win)
        let target = tileFrame(for: placement, on: screen)

        // Disable enhanced UI on the APP element (not window) — breaks macOS tile lock
        AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, false as CFTypeRef)

        // Freeze screen rendering so the size→position→size steps aren't visible
        let cid = _SLSMainConnectionID?()
        if let cid { _ = _SLSDisableUpdate?(cid) }

        // Size → Position → Size (same pattern as Rectangle and rift)
        var pos = CGPoint(x: target.origin.x, y: target.origin.y)
        var size = CGSize(width: target.width, height: target.height)

        if let sv = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sv)
        }
        if let pv = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pv)
        }
        if let sv = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sv)
        }

        // Unfreeze screen rendering
        if let cid { _ = _SLSReenableUpdate?(cid) }

        // Re-enable enhanced UI
        AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
    }

    /// Find which NSScreen contains a given AX window (nearest if center is off-screen)
    private static func screenForAXWindow(_ win: AXUIElement) -> NSScreen {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef)

        var pos = CGPoint.zero
        var size = CGSize.zero
        if let pv = posRef { AXValueGetValue(pv as! AXValue, .cgPoint, &pos) }
        if let sv = sizeRef { AXValueGetValue(sv as! AXValue, .cgSize, &size) }

        let primaryH = NSScreen.screens.first?.frame.height ?? 1080
        let cx = pos.x + size.width / 2
        let cy = primaryH - (pos.y + size.height / 2)
        let pt = NSPoint(x: cx, y: cy)

        return NSScreen.screens.first(where: { $0.frame.contains(pt) })
            ?? NSScreen.screens.min(by: {
                hypot(cx - $0.frame.midX, cy - $0.frame.midY) <
                hypot(cx - $1.frame.midX, cy - $1.frame.midY)
            })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    static func screenForWindowFrame(_ frame: WindowFrame) -> NSScreen {
        guard let primaryScreen = NSScreen.screens.first else {
            return NSScreen.main ?? NSScreen.screens[0]
        }

        let centerX = frame.x + frame.w / 2
        let centerY = frame.y + frame.h / 2
        let nsCenterY = primaryScreen.frame.height - centerY

        return NSScreen.screens.first(where: {
            $0.frame.contains(NSPoint(x: centerX, y: nsCenterY))
        }) ?? NSScreen.main ?? primaryScreen
    }

    // MARK: - Private

    private static func visibleDistributableWindows() -> [WindowEntry] {
        DesktopModel.shared.allWindows().filter { entry in
            entry.isOnScreen &&
            entry.app != "Lattices" &&
            entry.frame.w > 50 &&
            entry.frame.h > 50
        }
    }

    private static func sortWindowsForGrid(_ windows: [WindowEntry]) -> [WindowEntry] {
        windows.sorted { lhs, rhs in
            let rowTolerance = 40.0
            let yDelta = lhs.frame.y - rhs.frame.y
            if abs(yDelta) > rowTolerance {
                return lhs.frame.y < rhs.frame.y
            }

            let xDelta = lhs.frame.x - rhs.frame.x
            if abs(xDelta) > rowTolerance {
                return lhs.frame.x < rhs.frame.x
            }

            return lhs.zIndex < rhs.zIndex
        }
    }

    private static func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }

    private static func tileAppleScript(app: String, tag: String, bounds: (Int, Int, Int, Int)) {
        let (x1, y1, x2, y2) = bounds
        let script = """
        tell application "\(app)"
            repeat with w in windows
                if name of w contains "\(tag)" then
                    set bounds of w to {\(x1), \(y1), \(x2), \(y2)}
                    set index of w to 1
                    exit repeat
                end if
            end repeat
        end tell
        """
        runScript(script)
    }

    private static func tileFrontmost(bounds: (Int, Int, Int, Int)) {
        let (x1, y1, x2, y2) = bounds
        let script = """
        tell application "System Events"
            set frontApp to name of first application process whose frontmost is true
        end tell
        tell application frontApp
            set bounds of front window to {\(x1), \(y1), \(x2), \(y2)}
        end tell
        """
        runScript(script)
    }

    private static func runScript(_ script: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }
}
