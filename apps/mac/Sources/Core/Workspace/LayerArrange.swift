import AppKit

extension WorkspaceManager {
    /// Lays a layer's windows out by its `layout` (`LayerLayout`) on the main
    /// display, and raises them with the layer's first window in front and
    /// its app active. Like staging, it only takes windows on the desktop the
    /// main display is showing, parked ones included. Entries that set their
    /// own `tile` or `display` keep their place, and the windows in `except`
    /// (the ones it keeps put away) are left out. Returns whether it moved any.
    @discardableResult
    func arrangeLayer(_ layer: Layer, windows: [WindowEntry], except: Set<UInt32> = []) -> Bool {
        guard let name = layer.layout else { return false }
        let diag = DiagnosticLog.shared
        guard let kind = LayerLayout.Kind(name) else {
            diag.warn("arrangeLayer: unknown layout '\(name)' on layer \(layer.id)")
            return false
        }
        let main = CGMainDisplayID()
        guard let screen = NSScreen.screens.first,
              let display = WindowTiler.displaySpaces(forDisplayID: main, in: WindowTiler.getDisplaySpaces()),
              display.spaces.contains(where: { $0.id == display.currentSpaceId }) else { return false }
        let bounds = CGDisplayBounds(main)
        let others = Self.displayBounds(except: main)

        let members = memberWindows(of: layer, in: windows)
        let axByWid = Self.standardWindows(of: Set(members.map { $0.entry.pid }))
        let visible = WindowTiler.tileFrame(fractions: (0, 0, 1, 1), on: screen)
        let plan = LayerLayout.plan(kind, members: members, excluding: except,
            main: bounds, otherDisplays: others, currentSpace: display.currentSpaceId,
            visibleFrame: visible, standardWindows: Set(axByWid.keys))
        guard let focus = plan.first?.entry else { return false }
        let size = screen.visibleFrame.size
        let moves: [(wid: UInt32, pid: Int32, frame: CGRect, axWindow: AXUIElement)] = plan.compactMap { item in
            guard let axWindow = axByWid[item.entry.wid] else { return nil }
            return (item.entry.wid, item.entry.pid, item.frame, axWindow)
        }
        // Batch activation goes app by app in order of first appearance, so
        // the first window's app goes last, and the first window after the
        // rest of its app's.
        let ordered = moves.filter { $0.pid != focus.pid }
            + moves.filter { $0.pid == focus.pid && $0.wid != focus.wid }
            + moves.filter { $0.wid == focus.wid }
        WindowTiler.batchMoveAndRaiseWindows(ordered, activation: .allApps)
        diag.info("arrangeLayer: \(layer.id) \(name) → \(ordered.count) windows on \(Int(size.width))×\(Int(size.height))")
        return true
    }

    /// Each app's standard windows by window id, leaving out minimized ones.
    static func standardWindows(of pids: Set<Int32>) -> [UInt32: AXUIElement] {
        var byWid: [UInt32: AXUIElement] = [:]
        for pid in pids {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success,
                  let axWindows = value as? [AXUIElement] else { continue }
            for axWindow in axWindows {
                var wid: CGWindowID = 0
                var subrole: CFTypeRef?
                var minimized: CFTypeRef?
                guard _AXUIElementGetWindow(axWindow, &wid) == .success else { continue }
                AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subrole)
                AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimized)
                guard (subrole as? String) == kAXStandardWindowSubrole as String,
                      (minimized as? Bool) != true else { continue }
                byWid[wid] = axWindow
            }
        }
        return byWid
    }

    /// CG bounds of every active display but `main`.
    private static func displayBounds(except main: CGDirectDisplayID) -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { $0 != main }.map { CGDisplayBounds($0) }
    }
}
