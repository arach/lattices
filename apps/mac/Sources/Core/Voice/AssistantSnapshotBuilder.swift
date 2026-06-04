import AppKit

enum AssistantSnapshotBuilder {
    static func build() -> [String: Any] {
        let allWindows = DesktopModel.shared.allWindows()
        let smEnabled = UserDefaults(suiteName: "com.apple.WindowManager")?.bool(forKey: "GloballyEnabled") ?? false
        let grouping = UserDefaults(suiteName: "com.apple.WindowManager")?.integer(forKey: "AppWindowGroupingBehavior") ?? 0

        let windowList: [[String: Any]] = allWindows.enumerated().map { (zIndex, w) in
            var entry: [String: Any] = [
                "wid": w.wid,
                "app": w.app,
                "title": w.title,
                "frame": "\(Int(w.frame.x)),\(Int(w.frame.y)) \(Int(w.frame.w))x\(Int(w.frame.h))",
                "onScreen": w.isOnScreen,
                "zIndex": zIndex,
            ]
            if let session = w.latticesSession {
                entry["session"] = session
            }
            if !w.spaceIds.isEmpty {
                entry["spaces"] = w.spaceIds
            }
            return entry
        }

        let screens: [[String: Any]] = NSScreen.screens.enumerated().map { (i, s) in
            [
                "index": i + 1,
                "width": Int(s.frame.width),
                "height": Int(s.frame.height),
                "isMain": s == NSScreen.main,
                "visibleWidth": Int(s.visibleFrame.width),
                "visibleHeight": Int(s.visibleFrame.height),
            ]
        }

        var layerInfo: [String: Any]?
        let layerStore = SessionLayerStore.shared
        if layerStore.activeIndex >= 0 && layerStore.activeIndex < layerStore.layers.count {
            let current = layerStore.layers[layerStore.activeIndex]
            layerInfo = ["name": current.name, "index": layerStore.activeIndex]
        }

        let terminals = ProcessModel.shared.synthesizeTerminals()
        let terminalList: [[String: Any]] = terminals.compactMap { inst in
            var entry: [String: Any] = [
                "tty": inst.tty,
                "hasClaude": inst.hasClaude,
                "displayName": inst.displayName,
                "isActiveTab": inst.isActiveTab,
            ]
            if let cwd = inst.cwd { entry["cwd"] = cwd }
            if let app = inst.app { entry["app"] = app.rawValue }
            if let session = inst.tmuxSession { entry["tmuxSession"] = session }
            if let wid = inst.windowId { entry["windowId"] = Int(wid) }
            if let title = inst.tabTitle { entry["tabTitle"] = title }

            let userProcesses = inst.processes.filter {
                !["zsh", "bash", "fish", "login", "-zsh", "-bash"].contains($0.comm)
            }
            if !userProcesses.isEmpty {
                entry["runningCommands"] = userProcesses.map { proc in
                    var cmd: [String: Any] = ["command": proc.comm]
                    if let cwd = proc.cwd { cmd["cwd"] = cwd }
                    return cmd
                }
            }
            return entry
        }

        let tmuxList: [[String: Any]] = TmuxModel.shared.sessions.map { s in
            [
                "name": s.name,
                "windowCount": s.windowCount,
                "attached": s.attached,
            ]
        }

        var snapshot: [String: Any] = [
            "stageManager": smEnabled,
            "smGrouping": grouping == 0 ? "all-at-once" : "one-at-a-time",
            "windows": windowList,
            "terminals": terminalList,
            "screens": screens,
            "windowCount": allWindows.count,
            "onScreenCount": allWindows.filter(\.isOnScreen).count,
        ]
        if !tmuxList.isEmpty { snapshot["tmuxSessions"] = tmuxList }
        if let layerInfo { snapshot["currentLayer"] = layerInfo }

        return snapshot
    }
}
