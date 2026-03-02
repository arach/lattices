import Foundation

// MARK: - Registry Types

enum Access: String, Codable {
    case read, mutate
}

struct Param {
    let name: String
    let type: String        // "string", "int", "uint32", "bool"
    let required: Bool
    let description: String
}

enum ReturnShape {
    case array(model: String)
    case object(model: String)
    case ok
    case custom(String)
}

struct Endpoint {
    let method: String
    let description: String
    let access: Access
    let params: [Param]
    let returns: ReturnShape
    let handler: (JSON?) throws -> JSON
}

struct Field {
    let name: String
    let type: String        // "string", "int", "double", "bool", "[Model]", "Model?"
    let required: Bool
    let description: String
}

struct ApiModel {
    let name: String
    let fields: [Field]
}

// MARK: - Central Registry

final class LatticeApi {
    static let shared = LatticeApi()

    private(set) var endpoints: [String: Endpoint] = [:]
    private(set) var models: [String: ApiModel] = [:]
    private var endpointOrder: [String] = []
    private var modelOrder: [String] = []

    private let startTime = Date()

    func register(_ endpoint: Endpoint) {
        endpoints[endpoint.method] = endpoint
        if !endpointOrder.contains(endpoint.method) {
            endpointOrder.append(endpoint.method)
        }
    }

    func model(_ model: ApiModel) {
        models[model.name] = model
        if !modelOrder.contains(model.name) {
            modelOrder.append(model.name)
        }
    }

    func dispatch(method: String, params: JSON?) throws -> JSON {
        guard let endpoint = endpoints[method] else {
            throw RouterError.unknownMethod(method)
        }
        return try endpoint.handler(params)
    }

    func handle(_ request: DaemonRequest) -> DaemonResponse {
        do {
            let result = try dispatch(method: request.method, params: request.params)
            return DaemonResponse(id: request.id, result: result, error: nil)
        } catch {
            return DaemonResponse(id: request.id, result: nil, error: error.localizedDescription)
        }
    }

    func schema() -> JSON {
        let modelsList: [JSON] = modelOrder.compactMap { name in
            guard let m = models[name] else { return nil }
            return .object([
                "name": .string(m.name),
                "fields": .array(m.fields.map { f in
                    .object([
                        "name": .string(f.name),
                        "type": .string(f.type),
                        "required": .bool(f.required),
                        "description": .string(f.description)
                    ])
                })
            ])
        }

        let methodsList: [JSON] = endpointOrder.compactMap { name in
            guard let ep = endpoints[name] else { return nil }

            let returnsJson: JSON
            switch ep.returns {
            case .array(let model):
                returnsJson = .object(["type": .string("array"), "model": .string(model)])
            case .object(let model):
                returnsJson = .object(["type": .string("object"), "model": .string(model)])
            case .ok:
                returnsJson = .object(["type": .string("ok")])
            case .custom(let desc):
                returnsJson = .object(["type": .string("custom"), "description": .string(desc)])
            }

            return .object([
                "method": .string(ep.method),
                "description": .string(ep.description),
                "access": .string(ep.access.rawValue),
                "params": .array(ep.params.map { p in
                    .object([
                        "name": .string(p.name),
                        "type": .string(p.type),
                        "required": .bool(p.required),
                        "description": .string(p.description)
                    ])
                }),
                "returns": returnsJson
            ])
        }

        return .object([
            "version": .string("1.0"),
            "models": .array(modelsList),
            "methods": .array(methodsList)
        ])
    }

    // MARK: - Setup

    static func setup() {
        let api = LatticeApi.shared

        // ── Models ──────────────────────────────────────────────

        api.model(ApiModel(name: "Window", fields: [
            Field(name: "wid", type: "int", required: true, description: "CGWindowID"),
            Field(name: "app", type: "string", required: true, description: "Application name"),
            Field(name: "pid", type: "int", required: true, description: "Process ID"),
            Field(name: "title", type: "string", required: true, description: "Window title"),
            Field(name: "frame", type: "Frame", required: true, description: "Window frame {x, y, w, h}"),
            Field(name: "spaceIds", type: "[int]", required: true, description: "Space IDs the window is on"),
            Field(name: "isOnScreen", type: "bool", required: true, description: "Whether window is currently visible"),
            Field(name: "latticeSession", type: "string", required: false, description: "Associated lattice session name"),
        ]))

        api.model(ApiModel(name: "TmuxSession", fields: [
            Field(name: "name", type: "string", required: true, description: "Session name"),
            Field(name: "windowCount", type: "int", required: true, description: "Number of tmux windows"),
            Field(name: "attached", type: "bool", required: true, description: "Whether a client is attached"),
            Field(name: "panes", type: "[TmuxPane]", required: true, description: "Panes in this session"),
        ]))

        api.model(ApiModel(name: "TmuxPane", fields: [
            Field(name: "id", type: "string", required: true, description: "Pane ID (e.g. %0)"),
            Field(name: "windowIndex", type: "int", required: true, description: "Tmux window index"),
            Field(name: "windowName", type: "string", required: true, description: "Tmux window name"),
            Field(name: "title", type: "string", required: true, description: "Pane title"),
            Field(name: "currentCommand", type: "string", required: true, description: "Currently running command"),
            Field(name: "pid", type: "int", required: true, description: "Process ID of the pane"),
            Field(name: "isActive", type: "bool", required: true, description: "Whether this pane is active"),
            Field(name: "children", type: "[PaneChild]", required: false, description: "Interesting child processes in this pane"),
        ]))

        api.model(ApiModel(name: "Project", fields: [
            Field(name: "path", type: "string", required: true, description: "Absolute path to project"),
            Field(name: "name", type: "string", required: true, description: "Project display name"),
            Field(name: "sessionName", type: "string", required: true, description: "Tmux session name"),
            Field(name: "isRunning", type: "bool", required: true, description: "Whether the session is active"),
            Field(name: "hasConfig", type: "bool", required: true, description: "Whether .lattice.json exists"),
            Field(name: "paneCount", type: "int", required: true, description: "Number of configured panes"),
            Field(name: "paneNames", type: "[string]", required: true, description: "Names of configured panes"),
            Field(name: "devCommand", type: "string", required: false, description: "Dev command if detected"),
            Field(name: "packageManager", type: "string", required: false, description: "Detected package manager"),
        ]))

        api.model(ApiModel(name: "Display", fields: [
            Field(name: "displayIndex", type: "int", required: true, description: "Display index"),
            Field(name: "displayId", type: "string", required: true, description: "Display identifier"),
            Field(name: "currentSpaceId", type: "int", required: true, description: "Currently active space ID"),
            Field(name: "spaces", type: "[Space]", required: true, description: "Spaces on this display"),
        ]))

        api.model(ApiModel(name: "Space", fields: [
            Field(name: "id", type: "int", required: true, description: "Space ID"),
            Field(name: "index", type: "int", required: true, description: "Space index"),
            Field(name: "display", type: "int", required: true, description: "Display index"),
            Field(name: "isCurrent", type: "bool", required: true, description: "Whether this is the active space"),
        ]))

        api.model(ApiModel(name: "Layer", fields: [
            Field(name: "id", type: "string", required: true, description: "Layer identifier"),
            Field(name: "label", type: "string", required: true, description: "Layer display label"),
            Field(name: "index", type: "int", required: true, description: "Layer index"),
            Field(name: "projectCount", type: "int", required: true, description: "Number of projects in layer"),
        ]))

        api.model(ApiModel(name: "Process", fields: [
            Field(name: "pid", type: "int", required: true, description: "Process ID"),
            Field(name: "ppid", type: "int", required: true, description: "Parent process ID"),
            Field(name: "command", type: "string", required: true, description: "Command basename (e.g. node, claude)"),
            Field(name: "args", type: "string", required: true, description: "Full command line"),
            Field(name: "cwd", type: "string", required: false, description: "Working directory"),
            Field(name: "tty", type: "string", required: true, description: "Controlling TTY"),
            Field(name: "tmuxSession", type: "string", required: false, description: "Linked tmux session name"),
            Field(name: "tmuxPaneId", type: "string", required: false, description: "Linked tmux pane ID"),
            Field(name: "windowId", type: "int", required: false, description: "Linked macOS window ID"),
        ]))

        api.model(ApiModel(name: "PaneChild", fields: [
            Field(name: "pid", type: "int", required: true, description: "Process ID"),
            Field(name: "command", type: "string", required: true, description: "Command basename"),
            Field(name: "args", type: "string", required: true, description: "Full command line"),
            Field(name: "cwd", type: "string", required: false, description: "Working directory"),
        ]))

        api.model(ApiModel(name: "TerminalInstance", fields: [
            Field(name: "tty", type: "string", required: true, description: "Controlling TTY (universal join key)"),
            Field(name: "app", type: "string", required: false, description: "Terminal emulator name (iTerm2, Terminal, etc.)"),
            Field(name: "windowIndex", type: "int", required: false, description: "Terminal window index"),
            Field(name: "tabIndex", type: "int", required: false, description: "Tab index within the window"),
            Field(name: "isActiveTab", type: "bool", required: true, description: "Whether this is the selected tab"),
            Field(name: "tabTitle", type: "string", required: false, description: "Tab title from the terminal emulator"),
            Field(name: "terminalSessionId", type: "string", required: false, description: "Terminal-specific session ID (iTerm2 unique ID)"),
            Field(name: "processes", type: "[Process]", required: true, description: "Interesting processes on this TTY"),
            Field(name: "shellPid", type: "int", required: false, description: "Root shell PID for this TTY"),
            Field(name: "cwd", type: "string", required: false, description: "Working directory (from deepest interesting process)"),
            Field(name: "tmuxSession", type: "string", required: false, description: "Linked tmux session name"),
            Field(name: "tmuxPaneId", type: "string", required: false, description: "Linked tmux pane ID"),
            Field(name: "windowId", type: "int", required: false, description: "Linked macOS window ID (CGWindowID)"),
            Field(name: "windowTitle", type: "string", required: false, description: "macOS window title"),
            Field(name: "hasClaude", type: "bool", required: true, description: "Whether a claude process is running on this TTY"),
            Field(name: "displayName", type: "string", required: true, description: "Best display name (session > tab title > tty)"),
        ]))

        api.model(ApiModel(name: "DaemonStatus", fields: [
            Field(name: "uptime", type: "double", required: true, description: "Seconds since daemon started"),
            Field(name: "clientCount", type: "int", required: true, description: "Connected WebSocket clients"),
            Field(name: "version", type: "string", required: true, description: "Daemon version"),
            Field(name: "windowCount", type: "int", required: true, description: "Tracked window count"),
            Field(name: "tmuxSessionCount", type: "int", required: true, description: "Active tmux session count"),
        ]))

        // ── Endpoints: Read ─────────────────────────────────────

        api.register(Endpoint(
            method: "windows.list",
            description: "List all windows known to the system",
            access: .read,
            params: [],
            returns: .array(model: "Window"),
            handler: { _ in
                let entries = DesktopModel.shared.allWindows()
                return .array(entries.map { Encoders.window($0) })
            }
        ))

        api.register(Endpoint(
            method: "windows.get",
            description: "Get a single window by ID",
            access: .read,
            params: [Param(name: "wid", type: "uint32", required: true, description: "Window ID")],
            returns: .object(model: "Window"),
            handler: { params in
                guard let wid = params?["wid"]?.uint32Value else {
                    throw RouterError.missingParam("wid")
                }
                guard let entry = DesktopModel.shared.windows[wid] else {
                    throw RouterError.notFound("window \(wid)")
                }
                return Encoders.window(entry)
            }
        ))

        api.register(Endpoint(
            method: "tmux.sessions",
            description: "List all tmux sessions with child process enrichment",
            access: .read,
            params: [],
            returns: .array(model: "TmuxSession"),
            handler: { _ in
                let sessions = TmuxModel.shared.sessions
                return .array(sessions.map { Encoders.enrichedSession($0) })
            }
        ))

        api.register(Endpoint(
            method: "tmux.inventory",
            description: "Get full tmux inventory including orphaned sessions",
            access: .read,
            params: [],
            returns: .custom("Object with 'all' and 'orphans' arrays of TmuxSession"),
            handler: { _ in
                let inv = InventoryManager.shared
                return .object([
                    "all": .array(inv.allSessions.map { Encoders.session($0) }),
                    "orphans": .array(inv.orphans.map { Encoders.session($0) })
                ])
            }
        ))

        api.register(Endpoint(
            method: "projects.list",
            description: "List all discovered projects",
            access: .read,
            params: [],
            returns: .array(model: "Project"),
            handler: { _ in
                let projects = ProjectScanner.shared.projects
                return .array(projects.map { Encoders.project($0) })
            }
        ))

        api.register(Endpoint(
            method: "spaces.list",
            description: "List all displays and their spaces",
            access: .read,
            params: [],
            returns: .array(model: "Display"),
            handler: { _ in
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
        ))

        api.register(Endpoint(
            method: "layers.list",
            description: "List all workspace layers and the active index",
            access: .read,
            params: [],
            returns: .custom("Object with 'layers' array of Layer and 'active' index"),
            handler: { _ in
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
        ))

        api.register(Endpoint(
            method: "daemon.status",
            description: "Get daemon status including uptime and counts",
            access: .read,
            params: [],
            returns: .object(model: "DaemonStatus"),
            handler: { _ in
                let uptime = Date().timeIntervalSince(api.startTime)
                return .object([
                    "uptime": .double(uptime),
                    "clientCount": .int(DaemonServer.shared.clientCount),
                    "version": .string("1.0.0"),
                    "windowCount": .int(DesktopModel.shared.windows.count),
                    "tmuxSessionCount": .int(TmuxModel.shared.sessions.count)
                ])
            }
        ))

        api.register(Endpoint(
            method: "processes.list",
            description: "List interesting developer processes with tmux/window linkage",
            access: .read,
            params: [Param(name: "command", type: "string", required: false, description: "Filter by command name (e.g. claude)")],
            returns: .array(model: "Process"),
            handler: { params in
                let pm = ProcessModel.shared
                var enriched = pm.enrichedProcesses()
                if let cmd = params?["command"]?.stringValue {
                    enriched = enriched.filter { $0.process.comm == cmd }
                }
                return .array(enriched.map { Encoders.process($0) })
            }
        ))

        api.register(Endpoint(
            method: "processes.tree",
            description: "Get all descendant processes of a given PID",
            access: .read,
            params: [Param(name: "pid", type: "int", required: true, description: "Parent process ID")],
            returns: .array(model: "Process"),
            handler: { params in
                guard let pid = params?["pid"]?.intValue else {
                    throw RouterError.missingParam("pid")
                }
                let pm = ProcessModel.shared
                let descendants = pm.descendants(of: pid)
                return .array(descendants.map { entry in
                    let enrichment = pm.enrich(entry)
                    return Encoders.process(enrichment)
                })
            }
        ))

        api.register(Endpoint(
            method: "terminals.list",
            description: "List all synthesized terminal instances (unified TTY view)",
            access: .read,
            params: [
                Param(name: "refresh", type: "bool", required: false, description: "Force-refresh terminal tab cache before synthesizing"),
            ],
            returns: .array(model: "TerminalInstance"),
            handler: { params in
                let pm = ProcessModel.shared
                if params?["refresh"]?.boolValue == true {
                    pm.refreshTerminalTabs()
                }
                let instances = pm.synthesizeTerminals()
                return .array(instances.map { Encoders.terminalInstance($0) })
            }
        ))

        api.register(Endpoint(
            method: "terminals.search",
            description: "Search terminal instances by command, cwd, app, session, or hasClaude",
            access: .read,
            params: [
                Param(name: "command", type: "string", required: false, description: "Filter by command name substring"),
                Param(name: "cwd", type: "string", required: false, description: "Filter by working directory substring"),
                Param(name: "app", type: "string", required: false, description: "Filter by terminal app name"),
                Param(name: "session", type: "string", required: false, description: "Filter by tmux session name"),
                Param(name: "hasClaude", type: "bool", required: false, description: "Filter to only Claude-running TTYs"),
            ],
            returns: .array(model: "TerminalInstance"),
            handler: { params in
                var instances = ProcessModel.shared.synthesizeTerminals()

                if let cmd = params?["command"]?.stringValue {
                    instances = instances.filter { inst in
                        inst.processes.contains { $0.comm.contains(cmd) || $0.args.contains(cmd) }
                    }
                }
                if let cwd = params?["cwd"]?.stringValue {
                    instances = instances.filter { inst in
                        inst.cwd?.contains(cwd) == true
                    }
                }
                if let app = params?["app"]?.stringValue {
                    instances = instances.filter { $0.app?.rawValue == app }
                }
                if let session = params?["session"]?.stringValue {
                    instances = instances.filter { $0.tmuxSession == session }
                }
                if let hasClaude = params?["hasClaude"]?.boolValue {
                    instances = instances.filter { $0.hasClaude == hasClaude }
                }

                return .array(instances.map { Encoders.terminalInstance($0) })
            }
        ))

        // ── Endpoints: Mutations ────────────────────────────────

        api.register(Endpoint(
            method: "window.tile",
            description: "Tile a session's terminal window to a position",
            access: .mutate,
            params: [
                Param(name: "session", type: "string", required: true, description: "Tmux session name"),
                Param(name: "position", type: "string", required: true,
                      description: "Tile position (\(TilePosition.allCases.map(\.rawValue).joined(separator: ", ")))"),
            ],
            returns: .ok,
            handler: { params in
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
        ))

        api.register(Endpoint(
            method: "window.focus",
            description: "Focus a window by wid or session name",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: false, description: "Window ID (takes priority)"),
                Param(name: "session", type: "string", required: false, description: "Tmux session name (fallback)"),
            ],
            returns: .ok,
            handler: { params in
                if let wid = params?["wid"]?.uint32Value {
                    guard let entry = DesktopModel.shared.windows[wid] else {
                        throw RouterError.notFound("window \(wid)")
                    }
                    DispatchQueue.main.async {
                        WindowTiler.focusWindow(wid: wid, pid: entry.pid)
                    }
                    return .object(["ok": .bool(true), "wid": .int(Int(wid)), "app": .string(entry.app)])
                }
                guard let session = params?["session"]?.stringValue else {
                    throw RouterError.missingParam("session or wid")
                }
                let terminal = Preferences.shared.terminal
                DispatchQueue.main.async {
                    WindowTiler.navigateToWindow(session: session, terminal: terminal)
                }
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "window.move",
            description: "Move a session's window to a different space",
            access: .mutate,
            params: [
                Param(name: "session", type: "string", required: true, description: "Tmux session name"),
                Param(name: "spaceId", type: "int", required: true, description: "Target space ID"),
            ],
            returns: .ok,
            handler: { params in
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
        ))

        api.register(Endpoint(
            method: "session.launch",
            description: "Launch a project's tmux session",
            access: .mutate,
            params: [Param(name: "path", type: "string", required: true, description: "Absolute project path")],
            returns: .ok,
            handler: { params in
                guard let path = params?["path"]?.stringValue else {
                    throw RouterError.missingParam("path")
                }
                guard let project = ProjectScanner.shared.projects.first(where: { $0.path == path }) else {
                    throw RouterError.notFound("project at \(path)")
                }
                DispatchQueue.main.async {
                    SessionManager.launch(project: project)
                }
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "session.kill",
            description: "Kill a tmux session by name",
            access: .mutate,
            params: [Param(name: "name", type: "string", required: true, description: "Session name")],
            returns: .ok,
            handler: { params in
                guard let name = params?["name"]?.stringValue else {
                    throw RouterError.missingParam("name")
                }
                SessionManager.killByName(name)
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "session.detach",
            description: "Detach all clients from a tmux session",
            access: .mutate,
            params: [Param(name: "name", type: "string", required: true, description: "Session name")],
            returns: .ok,
            handler: { params in
                guard let name = params?["name"]?.stringValue else {
                    throw RouterError.missingParam("name")
                }
                SessionManager.detachByName(name)
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "session.sync",
            description: "Sync a project's tmux session panes to match config",
            access: .mutate,
            params: [Param(name: "path", type: "string", required: true, description: "Absolute project path")],
            returns: .ok,
            handler: { params in
                guard let path = params?["path"]?.stringValue else {
                    throw RouterError.missingParam("path")
                }
                guard let project = ProjectScanner.shared.projects.first(where: { $0.path == path }) else {
                    throw RouterError.notFound("project at \(path)")
                }
                SessionManager.sync(project: project)
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "session.restart",
            description: "Restart a project session or specific pane",
            access: .mutate,
            params: [
                Param(name: "path", type: "string", required: true, description: "Absolute project path"),
                Param(name: "pane", type: "string", required: false, description: "Specific pane name to restart"),
            ],
            returns: .ok,
            handler: { params in
                guard let path = params?["path"]?.stringValue else {
                    throw RouterError.missingParam("path")
                }
                guard let project = ProjectScanner.shared.projects.first(where: { $0.path == path }) else {
                    throw RouterError.notFound("project at \(path)")
                }
                let paneName = params?["pane"]?.stringValue
                SessionManager.restart(project: project, paneName: paneName)
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "layer.switch",
            description: "Switch to a workspace layer by index",
            access: .mutate,
            params: [Param(name: "index", type: "int", required: true, description: "Layer index")],
            returns: .ok,
            handler: { params in
                guard let index = params?["index"]?.intValue else {
                    throw RouterError.missingParam("index")
                }
                DispatchQueue.main.async {
                    WorkspaceManager.shared.tileLayer(index: index, launch: true)
                    EventBus.shared.post(.layerSwitched(index: index))
                }
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "group.launch",
            description: "Launch all sessions in a project group",
            access: .mutate,
            params: [Param(name: "id", type: "string", required: true, description: "Group identifier")],
            returns: .ok,
            handler: { params in
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
        ))

        api.register(Endpoint(
            method: "group.kill",
            description: "Kill all sessions in a project group",
            access: .mutate,
            params: [Param(name: "id", type: "string", required: true, description: "Group identifier")],
            returns: .ok,
            handler: { params in
                guard let groupId = params?["id"]?.stringValue else {
                    throw RouterError.missingParam("id")
                }
                guard let group = WorkspaceManager.shared.group(byId: groupId) else {
                    throw RouterError.notFound("group \(groupId)")
                }
                WorkspaceManager.shared.killGroup(group)
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "projects.scan",
            description: "Trigger a rescan of project directories",
            access: .mutate,
            params: [],
            returns: .ok,
            handler: { _ in
                DispatchQueue.main.async {
                    ProjectScanner.shared.scan()
                }
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "layout.distribute",
            description: "Distribute visible windows evenly across the screen",
            access: .mutate,
            params: [],
            returns: .ok,
            handler: { _ in
                DispatchQueue.main.async {
                    WindowTiler.distributeVisible()
                }
                return .object(["ok": .bool(true)])
            }
        ))

        // ── Meta endpoint ───────────────────────────────────────

        api.register(Endpoint(
            method: "api.schema",
            description: "Get the full API schema including all methods and models",
            access: .read,
            params: [],
            returns: .custom("Full API schema with version, models, and methods"),
            handler: { _ in
                api.schema()
            }
        ))
    }
}

// MARK: - Encoders

enum Encoders {
    static func window(_ w: WindowEntry) -> JSON {
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

    static func session(_ s: TmuxSession) -> JSON {
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

    static func process(_ e: ProcessModel.Enrichment) -> JSON {
        var obj: [String: JSON] = [
            "pid": .int(e.process.pid),
            "ppid": .int(e.process.ppid),
            "command": .string(e.process.comm),
            "args": .string(e.process.args),
            "tty": .string(e.process.tty),
        ]
        if let cwd = e.process.cwd { obj["cwd"] = .string(cwd) }
        if let s = e.tmuxSession { obj["tmuxSession"] = .string(s) }
        if let p = e.tmuxPaneId { obj["tmuxPaneId"] = .string(p) }
        if let w = e.windowId { obj["windowId"] = .int(Int(w)) }
        return .object(obj)
    }

    static func paneChild(_ entry: ProcessEntry) -> JSON {
        var obj: [String: JSON] = [
            "pid": .int(entry.pid),
            "command": .string(entry.comm),
            "args": .string(entry.args),
        ]
        if let cwd = entry.cwd { obj["cwd"] = .string(cwd) }
        return .object(obj)
    }

    static func terminalInstance(_ inst: TerminalInstance) -> JSON {
        var obj: [String: JSON] = [
            "tty": .string(inst.tty),
            "isActiveTab": .bool(inst.isActiveTab),
            "hasClaude": .bool(inst.hasClaude),
            "displayName": .string(inst.displayName),
            "processes": .array(inst.processes.map { entry in
                var p: [String: JSON] = [
                    "pid": .int(entry.pid),
                    "ppid": .int(entry.ppid),
                    "command": .string(entry.comm),
                    "args": .string(entry.args),
                    "tty": .string(entry.tty),
                ]
                if let cwd = entry.cwd { p["cwd"] = .string(cwd) }
                return .object(p)
            }),
        ]
        if let app = inst.app { obj["app"] = .string(app.rawValue) }
        if let wi = inst.windowIndex { obj["windowIndex"] = .int(wi) }
        if let ti = inst.tabIndex { obj["tabIndex"] = .int(ti) }
        if let title = inst.tabTitle { obj["tabTitle"] = .string(title) }
        if let sid = inst.terminalSessionId { obj["terminalSessionId"] = .string(sid) }
        if let pid = inst.shellPid { obj["shellPid"] = .int(pid) }
        if let cwd = inst.cwd { obj["cwd"] = .string(cwd) }
        if let s = inst.tmuxSession { obj["tmuxSession"] = .string(s) }
        if let p = inst.tmuxPaneId { obj["tmuxPaneId"] = .string(p) }
        if let w = inst.windowId { obj["windowId"] = .int(Int(w)) }
        if let t = inst.windowTitle { obj["windowTitle"] = .string(t) }
        return .object(obj)
    }

    static func enrichedSession(_ s: TmuxSession) -> JSON {
        let pm = ProcessModel.shared
        return .object([
            "name": .string(s.name),
            "windowCount": .int(s.windowCount),
            "attached": .bool(s.attached),
            "panes": .array(s.panes.map { pane in
                let children = pm.interestingDescendants(of: pane.pid)
                var obj: [String: JSON] = [
                    "id": .string(pane.id),
                    "windowIndex": .int(pane.windowIndex),
                    "windowName": .string(pane.windowName),
                    "title": .string(pane.title),
                    "currentCommand": .string(pane.currentCommand),
                    "pid": .int(pane.pid),
                    "isActive": .bool(pane.isActive),
                ]
                if !children.isEmpty {
                    obj["children"] = .array(children.map { Encoders.paneChild($0) })
                }
                return .object(obj)
            })
        ])
    }

    static func project(_ p: Project) -> JSON {
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
