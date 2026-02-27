import Foundation

enum MessageRouter {
    private static let startTime = Date()

    static func handle(_ request: DaemonRequest) -> DaemonResponse {
        do {
            let result = try dispatch(method: request.method, params: request.params)
            return DaemonResponse(id: request.id, result: result, error: nil)
        } catch {
            return DaemonResponse(id: request.id, result: nil, error: error.localizedDescription)
        }
    }

    private static func dispatch(method: String, params: JSON?) throws -> JSON {
        switch method {
        // Phase 1: Read-only
        case "windows.list":    return windowsList()
        case "windows.get":     return try windowsGet(params)
        case "tmux.sessions":   return tmuxSessions()
        case "tmux.inventory":  return tmuxInventory()
        case "projects.list":   return projectsList()
        case "spaces.list":     return spacesList()
        case "layers.list":     return layersList()
        case "daemon.status":   return daemonStatus()

        // Phase 2: Mutations
        case "window.tile":     return try windowTile(params)
        case "window.focus":    return try windowFocus(params)
        case "window.move":     return try windowMove(params)
        case "session.launch":  return try sessionLaunch(params)
        case "session.kill":    return try sessionKill(params)
        case "session.detach":  return try sessionDetach(params)
        case "session.sync":    return try sessionSync(params)
        case "session.restart": return try sessionRestart(params)
        case "layer.switch":    return try layerSwitch(params)
        case "group.launch":    return try groupLaunch(params)
        case "group.kill":      return try groupKill(params)
        case "projects.scan":   return projectsScan()

        default:
            throw RouterError.unknownMethod(method)
        }
    }

    // MARK: - Phase 1: Read-only handlers

    private static func windowsList() -> JSON {
        let entries = DesktopModel.shared.allWindows()
        return .array(entries.map { encodeWindow($0) })
    }

    private static func windowsGet(_ params: JSON?) throws -> JSON {
        guard let wid = params?["wid"]?.uint32Value else {
            throw RouterError.missingParam("wid")
        }
        guard let entry = DesktopModel.shared.windows[wid] else {
            throw RouterError.notFound("window \(wid)")
        }
        return encodeWindow(entry)
    }

    private static func tmuxSessions() -> JSON {
        let sessions = TmuxModel.shared.sessions
        return .array(sessions.map { encodeSession($0) })
    }

    private static func tmuxInventory() -> JSON {
        let inv = InventoryManager.shared
        return .object([
            "all": .array(inv.allSessions.map { encodeSession($0) }),
            "orphans": .array(inv.orphans.map { encodeSession($0) })
        ])
    }

    private static func projectsList() -> JSON {
        let projects = ProjectScanner.shared.projects
        return .array(projects.map { encodeProject($0) })
    }

    private static func spacesList() -> JSON {
        let displays = WindowTiler.getDisplaySpaces()
        return .array(displays.map { display in
            .object([
                "displayIndex": .int(display.displayIndex),
                "displayId": .string(display.displayId),
                "currentSpaceId": .int(display.currentSpaceId),
                "spaces": .array(display.spaces.map { space in
                    .object([
                        "id": .int(space.id),
                        "index": .int(space.index),
                        "display": .int(space.display),
                        "isCurrent": .bool(space.isCurrent)
                    ])
                })
            ])
        })
    }

    private static func layersList() -> JSON {
        let wm = WorkspaceManager.shared
        guard let config = wm.config, let layers = config.layers else {
            return .object([
                "layers": .array([]),
                "active": .int(0)
            ])
        }
        return .object([
            "layers": .array(layers.enumerated().map { i, layer in
                .object([
                    "id": .string(layer.id),
                    "label": .string(layer.label),
                    "index": .int(i),
                    "projectCount": .int(layer.projects.count)
                ])
            }),
            "active": .int(wm.activeLayerIndex)
        ])
    }

    private static func daemonStatus() -> JSON {
        let uptime = Date().timeIntervalSince(startTime)
        return .object([
            "uptime": .double(uptime),
            "clientCount": .int(DaemonServer.shared.clientCount),
            "version": .string("1.0.0"),
            "windowCount": .int(DesktopModel.shared.windows.count),
            "tmuxSessionCount": .int(TmuxModel.shared.sessions.count)
        ])
    }

    // MARK: - Phase 2: Mutation handlers

    private static func windowTile(_ params: JSON?) throws -> JSON {
        guard let session = params?["session"]?.stringValue else {
            throw RouterError.missingParam("session")
        }
        guard let posStr = params?["position"]?.stringValue,
              let position = TilePosition(rawValue: posStr) else {
            throw RouterError.missingParam("position (valid: \(TilePosition.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        let terminal = Preferences.shared.terminal
        DispatchQueue.main.async {
            WindowTiler.tile(session: session, terminal: terminal, to: position)
        }
        return .object(["ok": .bool(true)])
    }

    private static func windowFocus(_ params: JSON?) throws -> JSON {
        // wid-based focus: raise any window by CGWindowID
        if let wid = params?["wid"]?.uint32Value {
            guard let entry = DesktopModel.shared.windows[wid] else {
                throw RouterError.notFound("window \(wid)")
            }
            DispatchQueue.main.async {
                WindowTiler.focusWindow(wid: wid, pid: entry.pid)
            }
            return .object(["ok": .bool(true), "wid": .int(Int(wid)), "app": .string(entry.app)])
        }

        // session-based focus: existing tmux path
        guard let session = params?["session"]?.stringValue else {
            throw RouterError.missingParam("session or wid")
        }
        let terminal = Preferences.shared.terminal
        DispatchQueue.main.async {
            WindowTiler.navigateToWindow(session: session, terminal: terminal)
        }
        return .object(["ok": .bool(true)])
    }

    private static func windowMove(_ params: JSON?) throws -> JSON {
        guard let session = params?["session"]?.stringValue else {
            throw RouterError.missingParam("session")
        }
        guard let spaceId = params?["spaceId"]?.intValue else {
            throw RouterError.missingParam("spaceId")
        }
        let terminal = Preferences.shared.terminal
        DispatchQueue.main.async {
            _ = WindowTiler.moveWindowToSpace(session: session, terminal: terminal, spaceId: spaceId)
        }
        return .object(["ok": .bool(true)])
    }

    private static func sessionLaunch(_ params: JSON?) throws -> JSON {
        guard let path = params?["path"]?.stringValue else {
            throw RouterError.missingParam("path")
        }
        let scanner = ProjectScanner.shared
        guard let project = scanner.projects.first(where: { $0.path == path }) else {
            throw RouterError.notFound("project at \(path)")
        }
        DispatchQueue.main.async {
            SessionManager.launch(project: project)
        }
        return .object(["ok": .bool(true)])
    }

    private static func sessionKill(_ params: JSON?) throws -> JSON {
        guard let name = params?["name"]?.stringValue else {
            throw RouterError.missingParam("name")
        }
        SessionManager.killByName(name)
        return .object(["ok": .bool(true)])
    }

    private static func sessionDetach(_ params: JSON?) throws -> JSON {
        guard let name = params?["name"]?.stringValue else {
            throw RouterError.missingParam("name")
        }
        SessionManager.detachByName(name)
        return .object(["ok": .bool(true)])
    }

    private static func sessionSync(_ params: JSON?) throws -> JSON {
        guard let path = params?["path"]?.stringValue else {
            throw RouterError.missingParam("path")
        }
        let scanner = ProjectScanner.shared
        guard let project = scanner.projects.first(where: { $0.path == path }) else {
            throw RouterError.notFound("project at \(path)")
        }
        SessionManager.sync(project: project)
        return .object(["ok": .bool(true)])
    }

    private static func sessionRestart(_ params: JSON?) throws -> JSON {
        guard let path = params?["path"]?.stringValue else {
            throw RouterError.missingParam("path")
        }
        let scanner = ProjectScanner.shared
        guard let project = scanner.projects.first(where: { $0.path == path }) else {
            throw RouterError.notFound("project at \(path)")
        }
        let paneName = params?["pane"]?.stringValue
        SessionManager.restart(project: project, paneName: paneName)
        return .object(["ok": .bool(true)])
    }

    private static func layerSwitch(_ params: JSON?) throws -> JSON {
        guard let index = params?["index"]?.intValue else {
            throw RouterError.missingParam("index")
        }
        DispatchQueue.main.async {
            WorkspaceManager.shared.switchToLayer(index: index)
            EventBus.shared.post(.layerSwitched(index: index))
        }
        return .object(["ok": .bool(true)])
    }

    private static func groupLaunch(_ params: JSON?) throws -> JSON {
        guard let groupId = params?["id"]?.stringValue else {
            throw RouterError.missingParam("id")
        }
        guard let group = WorkspaceManager.shared.group(byId: groupId) else {
            throw RouterError.notFound("group \(groupId)")
        }
        DispatchQueue.main.async {
            WorkspaceManager.shared.launchGroup(group)
        }
        return .object(["ok": .bool(true)])
    }

    private static func groupKill(_ params: JSON?) throws -> JSON {
        guard let groupId = params?["id"]?.stringValue else {
            throw RouterError.missingParam("id")
        }
        guard let group = WorkspaceManager.shared.group(byId: groupId) else {
            throw RouterError.notFound("group \(groupId)")
        }
        WorkspaceManager.shared.killGroup(group)
        return .object(["ok": .bool(true)])
    }

    private static func projectsScan() -> JSON {
        DispatchQueue.main.async {
            ProjectScanner.shared.scan()
        }
        return .object(["ok": .bool(true)])
    }

    // MARK: - Encoders

    private static func encodeWindow(_ w: WindowEntry) -> JSON {
        var obj: [String: JSON] = [
            "wid": .int(Int(w.wid)),
            "app": .string(w.app),
            "pid": .int(Int(w.pid)),
            "title": .string(w.title),
            "frame": .object([
                "x": .double(w.frame.x),
                "y": .double(w.frame.y),
                "w": .double(w.frame.w),
                "h": .double(w.frame.h)
            ]),
            "spaceIds": .array(w.spaceIds.map { .int($0) }),
            "isOnScreen": .bool(w.isOnScreen)
        ]
        if let session = w.latticeSession {
            obj["latticeSession"] = .string(session)
        }
        return .object(obj)
    }

    private static func encodeSession(_ s: TmuxSession) -> JSON {
        .object([
            "name": .string(s.name),
            "windowCount": .int(s.windowCount),
            "attached": .bool(s.attached),
            "panes": .array(s.panes.map { pane in
                .object([
                    "id": .string(pane.id),
                    "windowIndex": .int(pane.windowIndex),
                    "windowName": .string(pane.windowName),
                    "title": .string(pane.title),
                    "currentCommand": .string(pane.currentCommand),
                    "pid": .int(pane.pid),
                    "isActive": .bool(pane.isActive)
                ])
            })
        ])
    }

    private static func encodeProject(_ p: Project) -> JSON {
        var obj: [String: JSON] = [
            "path": .string(p.path),
            "name": .string(p.name),
            "sessionName": .string(p.sessionName),
            "isRunning": .bool(p.isRunning),
            "hasConfig": .bool(p.hasConfig),
            "paneCount": .int(p.paneCount),
            "paneNames": .array(p.paneNames.map { .string($0) })
        ]
        if let cmd = p.devCommand { obj["devCommand"] = .string(cmd) }
        if let pm = p.packageManager { obj["packageManager"] = .string(pm) }
        return .object(obj)
    }
}

// MARK: - Errors

enum RouterError: LocalizedError {
    case unknownMethod(String)
    case missingParam(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .unknownMethod(let m): return "Unknown method: \(m)"
        case .missingParam(let p):  return "Missing parameter: \(p)"
        case .notFound(let what):   return "Not found: \(what)"
        }
    }
}
