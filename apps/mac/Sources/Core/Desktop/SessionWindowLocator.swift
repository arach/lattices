import AppKit
import ApplicationServices
import CoreGraphics

struct LocatedWindow {
    let wid: UInt32
    let pid: pid_t
}

enum SessionWindowLocator {
    static func tag(for session: String) -> String {
        Terminal.windowTag(for: session)
    }

    static func extractSessionName(from title: String) -> String? {
        guard let range = title.range(of: #"\[lattices:([^\]]+)\]"#, options: .regularExpression) else {
            return nil
        }
        let match = String(title[range])
        return String(match.dropFirst(10).dropLast(1))
    }

    static func matches(session: String, title: String, extractedSessionName: String? = nil) -> Bool {
        if extractedSessionName == session {
            return true
        }
        return title.contains(tag(for: session))
    }

    static func cachedWindow(forSession session: String, in windows: [UInt32: WindowEntry]) -> WindowEntry? {
        windows.values.first { entry in
            matches(session: session, title: entry.title, extractedSessionName: entry.latticesSession)
        }
    }

    static func cachedWindow(forSession session: String, desktopModel: DesktopModel = .shared) -> WindowEntry? {
        cachedWindow(forSession: session, in: desktopModel.windows)
    }

    static func findCGWindow(tag: String) -> LocatedWindow? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in windowList {
            if let name = info[kCGWindowName as String] as? String,
               name.contains(tag),
               let wid = info[kCGWindowNumber as String] as? UInt32,
               let pid = info[kCGWindowOwnerPID as String] as? pid_t {
                return LocatedWindow(wid: wid, pid: pid)
            }
        }
        return nil
    }

    static func findWindow(session: String, terminal: Terminal) -> LocatedWindow? {
        findWindow(tag: tag(for: session), terminal: terminal)
    }

    static func findWindow(tag: String, terminal: Terminal) -> LocatedWindow? {
        if let match = findCGWindow(tag: tag) {
            return match
        }

        if let ax = findAXWindow(terminal: terminal, tag: tag),
           let wid = matchCGWindow(pid: ax.pid, axWindow: ax.window) {
            return LocatedWindow(wid: wid, pid: ax.pid)
        }

        return nil
    }

    static func findAXWindow(terminal: Terminal, tag: String) -> (pid: pid_t, window: AXUIElement)? {
        let diag = DiagnosticLog.shared
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == terminal.bundleId
        }) else {
            diag.error("SessionWindowLocator.findAXWindow: \(terminal.rawValue) (\(terminal.bundleId)) not running")
            return nil
        }

        let pid = app.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement] else {
            diag.error("SessionWindowLocator.findAXWindow: AX error \(err.rawValue) — Accessibility not granted?")
            return nil
        }

        diag.info("SessionWindowLocator.findAXWindow: \(windows.count) windows for \(terminal.rawValue), searching for \(tag)")
        for win in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? "<no title>"
            if title.contains(tag) {
                diag.success("SessionWindowLocator.findAXWindow: matched \"\(title)\"")
                return (pid, win)
            } else {
                diag.info("  skip: \"\(title)\"")
            }
        }

        diag.warn("SessionWindowLocator.findAXWindow: no window matched tag \(tag)")
        return nil
    }

    static func matchCGWindow(pid: pid_t, axWindow: AXUIElement) -> UInt32? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
        guard let pv = posRef, let sv = sizeRef else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)

        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

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
}
