import AppKit
import ApplicationServices

/// Moves a window to another Space the one way macOS still allows since
/// 14.5: open Mission Control and drag the window's thumbnail onto the
/// target desktop in the Spaces bar, as a person would. The CGS move calls
/// are silently refused for other apps' windows, so this is the fallback
/// `window.move` and `window.present` use.
///
/// Holding a window by its title bar and switching Spaces doesn't work where
/// Lattices owns ⌃-arrow: the Dock ignores its own shortcut once Lattices
/// has turned it off, and the Dock-swipe switch doesn't fire while a mouse
/// button is down. Mission Control is drawn by WindowManager, which exposes
/// the Spaces bar to accessibility, so the drop target can be read.
///
/// Blocks for one to three seconds; never call it on the main thread.
/// Mission Control shows while it runs, and the view returns to the Space
/// the display was on.
enum WindowSpaceCarry {
    enum Outcome {
        case moved
        case failed(String)
    }

    static func carry(wid: UInt32, pid: pid_t, to target: Int) -> Outcome {
        precondition(!Thread.isMainThread, "WindowSpaceCarry blocks; run it off the main thread")
        let diag = DiagnosticLog.shared

        let from = WindowTiler.getSpacesForWindow(wid)
        if from.contains(target) { return .moved }
        guard from.count == 1, let source = from.first else {
            return .failed("window \(wid) is on \(from.count) Spaces; only a window on one Space can be carried")
        }
        guard let display = WindowTiler.getDisplaySpaces().first(where: {
            $0.orderedSpaceIds.contains(source) && $0.orderedSpaceIds.contains(target)
        }), let targetIndex = display.orderedSpaceIds.firstIndex(of: target) else {
            return .failed("Spaces \(source) and \(target) are on different displays; move the window to the display first")
        }
        if let app = NSRunningApplication(processIdentifier: pid), app.isHidden {
            return .failed("\(app.localizedName ?? "the app") is hidden; show it before moving its window")
        }
        guard let windowManager = windowManagerApp() else {
            return .failed("WindowManager isn't running")
        }
        let startSpace = display.currentSpaceId
        let restoreCursor = CGEvent(source: nil)?.location
        defer {
            if let restoreCursor { CGWarpMouseCursorPosition(restoreCursor) }
        }

        // 1. Mission Control shows the current Space's windows, so stand on
        //    the window's Space first.
        if startSpace != source {
            guard WindowTiler.switchToSpace(spaceId: source) else {
                return .failed("couldn't switch to the window's Space \(source)")
            }
        }
        defer {
            if WindowTiler.getDisplaySpaces().first(where: { $0.displayId == display.displayId })?.currentSpaceId != startSpace {
                if !WindowTiler.switchToSpace(spaceId: startSpace) {
                    diag.warn("WindowSpaceCarry: could not restore display \(display.displayIndex) view to Space \(startSpace)")
                }
            }
        }
        guard waitUntil(timeout: 1.0, { isOnScreen(wid) }), let home = bounds(wid) else {
            return .failed("window \(wid) didn't come on screen on Space \(source)")
        }

        // 2. Open Mission Control and wait for the thumbnail to settle.
        guard openMissionControl(windowManager) else {
            return .failed("Mission Control didn't open")
        }
        defer { closeMissionControl(windowManager) }
        var thumb = home
        let openedAt = Date()
        var stableSince = Date()
        let settled = waitUntil(timeout: 1.5) {
            guard let now = bounds(wid) else { return false }
            if now != thumb {
                thumb = now
                stableSince = Date()
            }
            // A small lone window can keep its original bounds in Mission
            // Control. Stable geometry, not a mandatory size change, is the
            // condition for a settled thumbnail.
            return Date().timeIntervalSince(openedAt) >= 0.35 && Date().timeIntervalSince(stableSince) >= 0.15
        }
        guard settled else { return .failed("no Mission Control thumbnail for window \(wid)") }
        guard let bar = spacesBar(windowManager, containing: CGPoint(x: home.midX, y: home.midY)) else {
            return .failed("no Spaces bar on the window's display")
        }
        guard bar.buttons.count == display.orderedSpaceIds.count else {
            return .failed("the Spaces bar shows \(bar.buttons.count) Spaces, expected \(display.orderedSpaceIds.count)")
        }
        let button = bar.buttons[targetIndex]

        // 3. Pick the thumbnail up and bring it to the bar, which expands
        //    under the cursor.
        let events = CGEventSource(stateID: .combinedSessionState)
        var cursor = CGPoint(x: thumb.midX, y: thumb.midY)
        func mouse(_ type: CGEventType, _ point: CGPoint) {
            CGEvent(mouseEventSource: events, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        func drag(to point: CGPoint, steps: Int) {
            let origin = cursor
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                mouse(.leftMouseDragged, CGPoint(x: origin.x + (point.x - origin.x) * t,
                                                 y: origin.y + (point.y - origin.y) * t))
                usleep(20_000)
            }
            cursor = point
        }
        let pickup = cursor
        diag.info("WindowSpaceCarry: wid=\(wid) \(source) → \(target) (Space \(targetIndex + 1) of \(display.orderedSpaceIds.count))")
        mouse(.mouseMoved, pickup)
        usleep(80_000)
        mouse(.leftMouseDown, pickup)
        usleep(120_000)
        drag(to: CGPoint(x: bar.frame.midX, y: bar.frame.minY + 30), steps: 20)

        // Collapsed, the buttons sit above the display's top edge.
        var drop = CGPoint.zero
        let expanded = waitUntil(timeout: 1.5) {
            guard let frame = frame(button), frame.minY >= bar.frame.minY else { return false }
            // WindowManager reports an expanded thumbnail's centre as its
            // position (the size is the collapsed label's). Drop there: a
            // drop in the gap between thumbnails makes a full-screen Space.
            drop = frame.origin
            return true
        }
        guard expanded else {
            drag(to: pickup, steps: 10)
            mouse(.leftMouseUp, pickup)
            return .failed("the Spaces bar didn't expand")
        }
        drag(to: drop, steps: 12)
        usleep(400_000)
        mouse(.leftMouseUp, drop)

        // 4. Check where it landed.
        _ = waitUntil(timeout: 1.0) { WindowTiler.getSpacesForWindow(wid) != [source] }
        let after = WindowTiler.getSpacesForWindow(wid)
        if after.contains(target) {
            diag.success("WindowSpaceCarry: wid=\(wid) now on \(after)")
            return .moved
        }
        let desktops = Set(WindowTiler.getDisplaySpaces().flatMap { $0.spaces.map(\.id) })
        if let fullScreen = after.first(where: { !desktops.contains($0) }) {
            closeMissionControl(windowManager)
            let recovered = leaveFullScreen(wid: wid, pid: pid, space: fullScreen)
            let recovery = recovered ? "left full screen" : "could not leave full screen"
            diag.warn("WindowSpaceCarry: wid=\(wid) dropped between desktops; \(recovery)")
            return .failed("the drop missed Space \(target) and made a full-screen Space; \(recovery)")
        }
        diag.warn("WindowSpaceCarry: wid=\(wid) stayed on \(after)")
        return .failed("the drop didn't take (window still on \(after))")
    }

    // MARK: - Mission Control

    private struct SpacesBar {
        let frame: CGRect
        let buttons: [AXUIElement]
    }

    private static func windowManagerApp() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager").first
        else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 1.0)
        return element
    }

    /// One `mc.display` group per display while Mission Control is open.
    private static func missionControlDisplays(_ windowManager: AXUIElement) -> [AXUIElement] {
        children(windowManager).filter { identifier($0) == "mc.display" }
    }

    private static func openMissionControl(_ windowManager: AXUIElement) -> Bool {
        if !missionControlDisplays(windowManager).isEmpty { return true }
        toggleMissionControl()
        return waitUntil(timeout: 1.5) { !missionControlDisplays(windowManager).isEmpty }
    }

    private static func closeMissionControl(_ windowManager: AXUIElement) {
        // Checked first: the toggle would open it again.
        guard !missionControlDisplays(windowManager).isEmpty else { return }
        toggleMissionControl()
        _ = waitUntil(timeout: 1.5) { missionControlDisplays(windowManager).isEmpty }
    }

    /// The app rather than ⌃↑ or Escape: it works whatever the shortcut is
    /// set to, and Escape from Lattices doesn't reach Mission Control.
    private static func toggleMissionControl() {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    private static func spacesBar(_ windowManager: AXUIElement, containing point: CGPoint) -> SpacesBar? {
        guard let display = missionControlDisplays(windowManager).first(where: {
            frame($0)?.contains(point) ?? false
        }), let group = children(display).first(where: { string($0, kAXDescriptionAttribute) == "Spaces Bar"
            || string($0, kAXTitleAttribute) == "Spaces Bar"
            || children($0).contains { identifier($0) == "mc.spaces.list" } }),
            let list = children(group).first(where: { identifier($0) == "mc.spaces.list" }),
            let displayFrame = frame(display)
        else { return nil }
        return SpacesBar(frame: displayFrame, buttons: children(list))
    }

    // MARK: - Pieces

    private static func leaveFullScreen(wid: UInt32, pid: pid_t, space: Int) -> Bool {
        guard WindowTiler.switchToSpace(spaceId: space) else { return false }
        usleep(300_000)
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement],
              let window = windows.first(where: { window in
                  var id: CGWindowID = 0
                  return _AXUIElementGetWindow(window, &id) == .success && id == wid
              }) else { return false }
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
        return waitUntil(timeout: 2.0) { !WindowTiler.getSpacesForWindow(wid).contains(space) }
    }

    private static func bounds(_ wid: UInt32) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]],
              let info = list.first,
              let dict = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: dict as CFDictionary)
    }

    private static func isOnScreen(_ wid: UInt32) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]],
              let info = list.first else { return false }
        return info[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        return value as? [AXUIElement] ?? []
    }

    private static func identifier(_ element: AXUIElement) -> String? {
        string(element, kAXIdentifierAttribute)
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return value as? String
    }

    private static func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            usleep(30_000)
        } while Date() < deadline
        return condition()
    }
}
