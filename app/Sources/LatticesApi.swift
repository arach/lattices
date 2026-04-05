import AppKit
import ApplicationServices
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

final class LatticesApi {
    static let shared = LatticesApi()

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
        let api = LatticesApi.shared

        // ── Models ──────────────────────────────────────────────

        api.model(ApiModel(name: "Window", fields: [
            Field(name: "wid", type: "int", required: true, description: "CGWindowID"),
            Field(name: "app", type: "string", required: true, description: "Application name"),
            Field(name: "pid", type: "int", required: true, description: "Process ID"),
            Field(name: "title", type: "string", required: true, description: "Window title"),
            Field(name: "frame", type: "Frame", required: true, description: "Window frame {x, y, w, h}"),
            Field(name: "spaceIds", type: "[int]", required: true, description: "Space IDs the window is on"),
            Field(name: "isOnScreen", type: "bool", required: true, description: "Whether window is currently visible"),
            Field(name: "latticesSession", type: "string", required: false, description: "Associated lattices session name"),
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
            Field(name: "hasConfig", type: "bool", required: true, description: "Whether .lattices.json exists"),
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

        api.model(ApiModel(name: "OcrResult", fields: [
            Field(name: "wid", type: "int", required: true, description: "Window ID"),
            Field(name: "app", type: "string", required: true, description: "Application name"),
            Field(name: "title", type: "string", required: true, description: "Window title"),
            Field(name: "frame", type: "Frame", required: true, description: "Window frame"),
            Field(name: "fullText", type: "string", required: true, description: "All recognized text"),
            Field(name: "blocks", type: "[OcrBlock]", required: true, description: "Individual text blocks with position/confidence"),
            Field(name: "timestamp", type: "double", required: true, description: "Scan timestamp (Unix)"),
        ]))

        api.model(ApiModel(name: "OcrBlock", fields: [
            Field(name: "text", type: "string", required: true, description: "Recognized text"),
            Field(name: "confidence", type: "double", required: true, description: "Recognition confidence 0-1"),
            Field(name: "x", type: "double", required: true, description: "Normalized bounding box x"),
            Field(name: "y", type: "double", required: true, description: "Normalized bounding box y"),
            Field(name: "w", type: "double", required: true, description: "Normalized bounding box width"),
            Field(name: "h", type: "double", required: true, description: "Normalized bounding box height"),
        ]))

        api.model(ApiModel(name: "OcrSearchResult", fields: [
            Field(name: "id", type: "int", required: true, description: "Database row ID"),
            Field(name: "wid", type: "int", required: true, description: "Window ID"),
            Field(name: "app", type: "string", required: true, description: "Application name"),
            Field(name: "title", type: "string", required: true, description: "Window title"),
            Field(name: "frame", type: "Frame", required: true, description: "Window frame at scan time"),
            Field(name: "fullText", type: "string", required: true, description: "Full recognized text"),
            Field(name: "snippet", type: "string", required: true, description: "Highlighted snippet (FTS5)"),
            Field(name: "timestamp", type: "double", required: true, description: "Scan timestamp (Unix)"),
            Field(name: "source", type: "string", required: true, description: "Text source: 'accessibility' or 'ocr'"),
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
            method: "windows.search",
            description: "Search windows by title, app, and OCR content",
            access: .read,
            params: [
                Param(name: "query", type: "string", required: true, description: "Search text"),
                Param(name: "ocr", type: "bool", required: false, description: "Include OCR content (default true)"),
                Param(name: "limit", type: "int", required: false, description: "Max results (default 50)"),
            ],
            returns: .array(model: "Window"),
            handler: { params in
                guard let query = params?["query"]?.stringValue?.lowercased(), !query.isEmpty else {
                    throw RouterError.missingParam("query")
                }
                let includeOcr = params?["ocr"]?.boolValue ?? true
                let limit = params?["limit"]?.intValue ?? 50
                let ocrResults = OcrModel.shared.results

                var matches: [JSON] = []
                for entry in DesktopModel.shared.allWindows() {
                    let matchesApp = entry.app.lowercased().contains(query)
                    let matchesTitle = entry.title.lowercased().contains(query)
                    let matchesSession = entry.latticesSession?.lowercased().contains(query) ?? false
                    let ocrText = includeOcr ? ocrResults[entry.wid]?.fullText : nil
                    let matchesOcrContent = ocrText?.lowercased().contains(query) ?? false

                    if matchesApp || matchesTitle || matchesSession || matchesOcrContent {
                        var obj = Encoders.window(entry)
                        if matchesOcrContent, let text = ocrText,
                           let range = text.lowercased().range(of: query) {
                            // Extract snippet around match
                            let half = max(0, (80 - text.distance(from: range.lowerBound, to: range.upperBound)) / 2)
                            let start = text.index(range.lowerBound, offsetBy: -half, limitedBy: text.startIndex) ?? text.startIndex
                            let end = text.index(range.upperBound, offsetBy: half, limitedBy: text.endIndex) ?? text.endIndex
                            var snippet = String(text[start..<end])
                                .replacingOccurrences(of: "\n", with: " ")
                                .trimmingCharacters(in: .whitespaces)
                            if start > text.startIndex { snippet = "…" + snippet }
                            if end < text.endIndex { snippet += "…" }
                            if case .object(var dict) = obj {
                                dict["ocrSnippet"] = .string(snippet)
                                dict["matchSource"] = .string("ocr")
                                obj = .object(dict)
                            }
                        } else if case .object(var dict) = obj {
                            let source = matchesTitle ? "title" : matchesApp ? "app" : "session"
                            dict["matchSource"] = .string(source)
                            obj = .object(dict)
                        }
                        matches.append(obj)
                        if matches.count >= limit { break }
                    }
                }
                return .array(matches)
            }
        ))

        // MARK: - Unified Search

        api.register(Endpoint(
            method: "lattices.search",
            description: "Unified search across windows, terminals, and OCR. Single entry point for all search surfaces.",
            access: .read,
            params: [
                Param(name: "query", type: "string", required: true, description: "Search text"),
                Param(name: "sources", type: "array<string>", required: false, description: "Data sources to include: titles, apps, sessions, cwd, tabs, tmux, ocr, processes. Omit for smart default (everything except ocr). Use ['all'] for everything."),
                Param(name: "after", type: "string", required: false, description: "ISO8601 timestamp — only windows interacted with after this time"),
                Param(name: "before", type: "string", required: false, description: "ISO8601 timestamp — only windows interacted with before this time"),
                Param(name: "recency", type: "bool", required: false, description: "Boost score for recently-focused windows (default true)"),
                Param(name: "limit", type: "int", required: false, description: "Max results (default 20)"),
                // Legacy compat
                Param(name: "mode", type: "string", required: false, description: "Legacy: 'quick', 'complete', 'terminal'. Mapped to sources internally."),
            ],
            returns: .array(model: "SearchResult"),
            handler: { params in
                guard let query = params?["query"]?.stringValue?.lowercased(), !query.isEmpty else {
                    throw RouterError.missingParam("query")
                }
                let limit = params?["limit"]?.intValue ?? 20
                let useRecency = params?["recency"]?.boolValue ?? true

                // ── Resolve sources ──

                // All available source names
                let allSources: Set<String> = ["titles", "apps", "sessions", "cwd", "tabs", "tmux", "ocr", "processes"]
                // Smart default: everything except OCR (fast)
                let defaultSources: Set<String> = ["titles", "apps", "sessions", "cwd", "tabs", "tmux"]

                var sources: Set<String>
                if let arr = params?["sources"]?.arrayValue {
                    let names = arr.compactMap(\.stringValue)
                    if names.contains("all") {
                        sources = allSources
                    } else if names.contains("terminals") {
                        // Shorthand expansion
                        sources = Set(names).subtracting(["terminals"]).union(["cwd", "tabs", "tmux", "processes"])
                    } else {
                        sources = Set(names).intersection(allSources)
                        if sources.isEmpty { sources = defaultSources }
                    }
                } else if let mode = params?["mode"]?.stringValue {
                    // Legacy mode param → sources mapping
                    switch mode {
                    case "quick":    sources = ["titles", "apps", "sessions"]
                    case "terminal": sources = ["cwd", "tabs", "tmux", "processes"]
                    default:         sources = allSources  // "complete"
                    }
                } else {
                    sources = defaultSources
                }

                let includeWindowIndex = !sources.isDisjoint(with: ["titles", "apps", "sessions"])
                let includeOcr = sources.contains("ocr")
                let includeTerminals = !sources.isDisjoint(with: ["cwd", "tabs", "tmux", "processes"])

                // ── Resolve time filters ──

                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let isoFormatterNoFrac = ISO8601DateFormatter()

                func parseDate(_ str: String?) -> Date? {
                    guard let str else { return nil }
                    return isoFormatter.date(from: str) ?? isoFormatterNoFrac.date(from: str)
                }

                let afterDate = parseDate(params?["after"]?.stringValue)
                let beforeDate = parseDate(params?["before"]?.stringValue)

                // Default time window: 2 days (only applies when no explicit time filters given)
                let defaultCutoff = (afterDate == nil && beforeDate == nil)
                    ? Date().addingTimeInterval(-2 * 24 * 3600)
                    : nil

                let now = Date()
                let desktop = DesktopModel.shared

                /// Check if a window passes the time filter.
                /// Windows with no interaction date are included if they're currently on screen (live windows).
                func passesTimeFilter(wid: UInt32, entry: WindowEntry) -> Bool {
                    if let interacted = desktop.lastInteractionDate(for: wid) {
                        if let after = afterDate, interacted < after { return false }
                        if let before = beforeDate, interacted > before { return false }
                        if let cutoff = defaultCutoff, interacted < cutoff { return false }
                        return true
                    }
                    // No interaction date — include if currently visible (it's a live window we just haven't tracked yet)
                    return entry.isOnScreen
                }

                /// Recency boost: windows focused recently score higher.
                /// Frontmost (zIndex 0) gets +4, last 5 min +3, last hour +2, last day +1.
                func recencyBoost(wid: UInt32, zIndex: Int) -> Int {
                    guard useRecency else { return 0 }
                    if zIndex == 0 { return 4 }
                    guard let last = desktop.lastInteractionDate(for: wid) else { return 0 }
                    let ago = now.timeIntervalSince(last)
                    if ago < 300 { return 3 }    // 5 min
                    if ago < 3600 { return 2 }   // 1 hour
                    if ago < 86400 { return 1 }  // 1 day
                    return 0
                }

                // ── Accumulator ──

                struct Accum {
                    let entry: WindowEntry
                    var score: Int
                    var sources: [String]
                    var ocrSnippet: String?
                    var tabs: [JSON]
                    var lastInteraction: Date?
                }
                var byWid: [UInt32: Accum] = [:]

                // ── Tier 1: Window index (title, app, session) ──

                if includeWindowIndex {
                    let ocrResults = includeOcr ? OcrModel.shared.results : [:]
                    let checkTitles = sources.contains("titles")
                    let checkApps = sources.contains("apps")
                    let checkSessions = sources.contains("sessions")

                    for entry in desktop.allWindows() {
                        guard passesTimeFilter(wid: entry.wid, entry: entry) else { continue }

                        var score = 0
                        var matchSources: [String] = []
                        var ocrSnippet: String? = nil

                        if checkTitles && entry.title.lowercased().contains(query) { score += 3; matchSources.append("title") }
                        if checkApps && entry.app.lowercased().contains(query) { score += 2; matchSources.append("app") }
                        if checkSessions && entry.latticesSession?.lowercased().contains(query) == true { score += 3; matchSources.append("session") }

                        if includeOcr, let ocrResult = ocrResults[entry.wid] {
                            let text = ocrResult.fullText
                            if text.lowercased().contains(query) {
                                score += 1; matchSources.append("ocr")
                                if let range = text.lowercased().range(of: query) {
                                    let half = max(0, (80 - text.distance(from: range.lowerBound, to: range.upperBound)) / 2)
                                    let start = text.index(range.lowerBound, offsetBy: -half, limitedBy: text.startIndex) ?? text.startIndex
                                    let end = text.index(range.upperBound, offsetBy: half, limitedBy: text.endIndex) ?? text.endIndex
                                    var snippet = String(text[start..<end])
                                        .replacingOccurrences(of: "\n", with: " ")
                                        .trimmingCharacters(in: .whitespaces)
                                    if start > text.startIndex { snippet = "…" + snippet }
                                    if end < text.endIndex { snippet += "…" }
                                    ocrSnippet = snippet
                                }
                            }
                        }

                        if score > 0 {
                            score += recencyBoost(wid: entry.wid, zIndex: entry.zIndex)
                            byWid[entry.wid] = Accum(
                                entry: entry, score: score, sources: matchSources,
                                ocrSnippet: ocrSnippet, tabs: [],
                                lastInteraction: desktop.lastInteractionDate(for: entry.wid)
                            )
                        }
                    }
                }

                // ── Tier 2: Terminal inspection (cwd, tab titles, tmux sessions, processes) ──

                if includeTerminals {
                    let checkCwd = sources.contains("cwd")
                    let checkTabs = sources.contains("tabs")
                    let checkTmux = sources.contains("tmux")
                    let checkProcesses = sources.contains("processes")

                    let instances = ProcessModel.shared.synthesizeTerminals()
                    for inst in instances {
                        let cwdMatch = checkCwd && (inst.cwd?.lowercased().contains(query) ?? false)
                        let tabMatch = checkTabs && (inst.tabTitle?.lowercased().contains(query) ?? false)
                        let tmuxMatch = checkTmux && (inst.tmuxSession?.lowercased().contains(query) ?? false)
                        let processMatch = checkProcesses && inst.processes.contains {
                            $0.comm.lowercased().contains(query) || $0.args.lowercased().contains(query)
                        }
                        guard cwdMatch || tabMatch || tmuxMatch || processMatch else { continue }

                        var tab: [String: JSON] = [:]
                        if let idx = inst.tabIndex { tab["tabIndex"] = .int(idx) }
                        if let cwd = inst.cwd { tab["cwd"] = .string(cwd) }
                        if let title = inst.tabTitle { tab["tabTitle"] = .string(title) }
                        tab["hasClaude"] = .bool(inst.hasClaude)
                        if let session = inst.tmuxSession { tab["tmuxSession"] = .string(session) }
                        if processMatch {
                            let matched = inst.processes.filter {
                                $0.comm.lowercased().contains(query) || $0.args.lowercased().contains(query)
                            }
                            tab["matchedProcesses"] = .array(matched.map { .string($0.comm) })
                        }

                        let tabJson = JSON.object(tab)
                        var tabScore = 0
                        if cwdMatch { tabScore += 3 }
                        if tabMatch { tabScore += 2 }
                        if tmuxMatch { tabScore += 3 }
                        if processMatch { tabScore += 2 }

                        if let wid = inst.windowId {
                            if var acc = byWid[wid] {
                                acc.score += tabScore
                                if cwdMatch && !acc.sources.contains("cwd") { acc.sources.append("cwd") }
                                if tabMatch && !acc.sources.contains("tab") { acc.sources.append("tab") }
                                if tmuxMatch && !acc.sources.contains("tmux") { acc.sources.append("tmux") }
                                if processMatch && !acc.sources.contains("process") { acc.sources.append("process") }
                                acc.tabs.append(tabJson)
                                byWid[wid] = acc
                            } else if let entry = desktop.windows[wid] {
                                guard passesTimeFilter(wid: wid, entry: entry) else { continue }
                                var matchSources: [String] = []
                                if cwdMatch { matchSources.append("cwd") }
                                if tabMatch { matchSources.append("tab") }
                                if tmuxMatch { matchSources.append("tmux") }
                                if processMatch { matchSources.append("process") }
                                let score = tabScore + recencyBoost(wid: wid, zIndex: entry.zIndex)
                                byWid[wid] = Accum(
                                    entry: entry, score: score, sources: matchSources,
                                    ocrSnippet: nil, tabs: [tabJson],
                                    lastInteraction: desktop.lastInteractionDate(for: wid)
                                )
                            }
                        }
                    }
                }

                // ── Build results ──

                let sorted = byWid.values.sorted { $0.score > $1.score }
                return .array(Array(sorted.prefix(limit)).map { acc in
                    var obj = Encoders.window(acc.entry)
                    if case .object(var dict) = obj {
                        dict["score"] = .int(acc.score)
                        dict["matchSources"] = .array(acc.sources.map { .string($0) })
                        if let snippet = acc.ocrSnippet { dict["ocrSnippet"] = .string(snippet) }
                        if !acc.tabs.isEmpty { dict["terminalTabs"] = .array(acc.tabs) }
                        if let last = acc.lastInteraction {
                            dict["lastInteraction"] = .string(ISO8601DateFormatter().string(from: last))
                        }
                        obj = .object(dict)
                    }
                    return obj
                })
            }
        ))

        // MARK: - Window Layer Tags

        api.register(Endpoint(
            method: "window.assignLayer",
            description: "Tag a window with a layer id (in-memory only)",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: true, description: "Window ID"),
                Param(name: "layer", type: "string", required: true, description: "Layer id (e.g. 'lattices', 'vox')")
            ],
            returns: .ok,
            handler: { params in
                guard let wid = params?["wid"]?.uint32Value else {
                    throw RouterError.missingParam("wid")
                }
                guard let layerId = params?["layer"]?.stringValue, !layerId.isEmpty else {
                    throw RouterError.missingParam("layer")
                }
                DesktopModel.shared.assignLayer(wid: wid, layerId: layerId)
                return .object(["ok": .bool(true), "wid": .int(Int(wid)), "layer": .string(layerId)])
            }
        ))

        api.register(Endpoint(
            method: "window.removeLayer",
            description: "Remove layer tag from a window",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: true, description: "Window ID")
            ],
            returns: .ok,
            handler: { params in
                guard let wid = params?["wid"]?.uint32Value else {
                    throw RouterError.missingParam("wid")
                }
                DesktopModel.shared.removeLayerTag(wid: wid)
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "window.layerMap",
            description: "Get all window-to-layer assignments",
            access: .read,
            params: [],
            returns: .custom("{ [wid]: layerId }"),
            handler: { _ in
                let tags = DesktopModel.shared.windowLayerTags
                var obj: [String: JSON] = [:]
                for (wid, layerId) in tags {
                    obj[String(wid)] = .string(layerId)
                }
                return .object(obj)
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
            method: "diagnostics.list",
            description: "Get recent diagnostic log entries",
            access: .read,
            params: [Param(name: "limit", type: "int", required: false, description: "Max entries to return (default 40)")],
            returns: .custom("Array of log entries with time, level, message"),
            handler: { params in
                let limit = params?["limit"]?.intValue ?? 40
                let entries = DiagnosticLog.shared.entries.suffix(limit)
                let fmt = DateFormatter()
                fmt.dateFormat = "HH:mm:ss.SSS"
                return .object([
                    "entries": .array(entries.map { entry in
                        .object([
                            "time": .string(fmt.string(from: entry.time)),
                            "level": .string("\(entry.level)"),
                            "message": .string(entry.message)
                        ])
                    })
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

        // ── Endpoints: OCR ─────────────────────────────────────

        api.register(Endpoint(
            method: "ocr.snapshot",
            description: "Get the latest OCR scan results for all on-screen windows",
            access: .read,
            params: [],
            returns: .array(model: "OcrResult"),
            handler: { _ in
                let results = OcrModel.shared.results
                return .array(results.values.map { Encoders.ocrResult($0) })
            }
        ))

        api.register(Endpoint(
            method: "ocr.search",
            description: "Search OCR text across all windows (queries persistent SQLite FTS5 index by default)",
            access: .read,
            params: [
                Param(name: "query", type: "string", required: true, description: "Search text (FTS5 query syntax)"),
                Param(name: "app", type: "string", required: false, description: "Filter by app name"),
                Param(name: "limit", type: "int", required: false, description: "Max results (default 50)"),
                Param(name: "live", type: "bool", required: false, description: "Search in-memory snapshot instead of history (default false)"),
            ],
            returns: .array(model: "OcrSearchResult"),
            handler: { params in
                guard let query = params?["query"]?.stringValue else {
                    throw RouterError.missingParam("query")
                }
                let app = params?["app"]?.stringValue
                let limit = params?["limit"]?.intValue ?? 50
                let live = params?["live"]?.boolValue ?? false

                if live {
                    // In-memory snapshot search (original behavior)
                    var results = Array(OcrModel.shared.results.values)
                    let q = query.lowercased()
                    results = results.filter { $0.fullText.lowercased().contains(q) }
                    if let app { results = results.filter { $0.app == app } }
                    return .array(results.prefix(limit).map { Encoders.ocrResult($0) })
                }

                // Persistent FTS5 search
                let results = OcrStore.shared.search(query: query, app: app, limit: limit)
                return .array(results.map { Encoders.ocrSearchResult($0) })
            }
        ))

        api.register(Endpoint(
            method: "ocr.history",
            description: "Get OCR content timeline for a specific window",
            access: .read,
            params: [
                Param(name: "wid", type: "uint32", required: true, description: "Window ID"),
                Param(name: "limit", type: "int", required: false, description: "Max results (default 50)"),
            ],
            returns: .array(model: "OcrSearchResult"),
            handler: { params in
                guard let wid = params?["wid"]?.uint32Value else {
                    throw RouterError.missingParam("wid")
                }
                let limit = params?["limit"]?.intValue ?? 50
                let results = OcrStore.shared.history(wid: wid, limit: limit)
                return .array(results.map { Encoders.ocrSearchResult($0) })
            }
        ))

        api.register(Endpoint(
            method: "ocr.recent",
            description: "Get recent OCR entries across all windows (chronological, from persistent store)",
            access: .read,
            params: [
                Param(name: "limit", type: "int", required: false, description: "Max results (default 50)"),
            ],
            returns: .array(model: "OcrSearchResult"),
            handler: { params in
                let limit = params?["limit"]?.intValue ?? 50
                let results = OcrStore.shared.recent(limit: limit)
                return .array(results.map { Encoders.ocrSearchResult($0) })
            }
        ))

        api.register(Endpoint(
            method: "ocr.scan",
            description: "Trigger an immediate OCR scan",
            access: .mutate,
            params: [],
            returns: .ok,
            handler: { _ in
                OcrModel.shared.scan()
                return .object(["ok": .bool(true)])
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
                      description: "Placement shorthand or grid syntax"),
            ],
            returns: .ok,
            handler: { params in
                guard case .object(var dict) = params else {
                    throw RouterError.missingParam("session")
                }
                guard dict["session"]?.stringValue != nil else {
                    throw RouterError.missingParam("session")
                }
                dict["placement"] = dict["placement"] ?? dict["position"]
                return try Self.executeWindowPlacement(params: .object(dict))
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
                    var raised = false
                    if Thread.isMainThread {
                        raised = WindowTiler.focusWindow(wid: wid, pid: entry.pid)
                    } else {
                        DispatchQueue.main.sync {
                            raised = WindowTiler.focusWindow(wid: wid, pid: entry.pid)
                        }
                    }
                    return .object(["ok": .bool(raised), "wid": .int(Int(wid)), "app": .string(entry.app),
                                    "raised": .bool(raised)])
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
            method: "window.place",
            description: "Place a window or session using a typed placement spec",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: false, description: "Window ID"),
                Param(name: "session", type: "string", required: false, description: "Tmux session name"),
                Param(name: "app", type: "string", required: false, description: "Application name"),
                Param(name: "title", type: "string", required: false, description: "Optional title substring for app matching"),
                Param(name: "display", type: "int", required: false, description: "Target display index"),
                Param(name: "placement", type: "string|object", required: true, description: "Placement shorthand or typed placement object"),
            ],
            returns: .custom("Execution receipt with target resolution, placement, and trace"),
            handler: { params in
                try Self.executeWindowPlacement(params: params)
            }
        ))

        // ── Present Window ────────────────────────────────────────────
        api.register(Endpoint(
            method: "window.present",
            description: "Present a window: move to current space, bring to front, optionally position it",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: true, description: "Window ID"),
                Param(name: "x", type: "double", required: false, description: "Target x position"),
                Param(name: "y", type: "double", required: false, description: "Target y position"),
                Param(name: "w", type: "double", required: false, description: "Target width"),
                Param(name: "h", type: "double", required: false, description: "Target height"),
                Param(name: "position", type: "string", required: false,
                      description: "Tile position (e.g. center, left, right, bottom-right)"),
            ],
            returns: .ok,
            handler: { params in
                guard let wid = params?["wid"]?.uint32Value else {
                    throw RouterError.missingParam("wid")
                }
                guard let entry = DesktopModel.shared.windows[wid] else {
                    throw RouterError.notFound("window \(wid)")
                }

                // Resolve position to fractional rect
                var fractions: (CGFloat, CGFloat, CGFloat, CGFloat)? = nil
                if let placement = Self.parsePlacement(from: params?["placement"] ?? params?["position"]) {
                    fractions = placement.fractions
                }

                var frame: CGRect? = nil
                if let fracs = fractions {
                    let screen = Self.resolveTargetScreen(for: entry, displayIndex: params?["display"]?.intValue)
                    // Compute pixel frame (needs main thread for NSScreen)
                    if Thread.isMainThread {
                        frame = WindowTiler.tileFrame(fractions: fracs, on: screen)
                    } else {
                        DispatchQueue.main.sync {
                            frame = WindowTiler.tileFrame(fractions: fracs, on: screen)
                        }
                    }
                } else if let x = params?["x"]?.intValue,
                          let y = params?["y"]?.intValue,
                          let w = params?["w"]?.intValue,
                          let h = params?["h"]?.intValue {
                    frame = CGRect(x: x, y: y, width: w, height: h)
                }

                var presented = false
                if Thread.isMainThread {
                    presented = WindowTiler.present(wid: wid, pid: entry.pid, frame: frame)
                } else {
                    DispatchQueue.main.sync {
                        presented = WindowTiler.present(wid: wid, pid: entry.pid, frame: frame)
                    }
                }
                return .object(["ok": .bool(presented), "wid": .int(Int(wid)), "app": .string(entry.app)])
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
            description: "Switch to a workspace layer by index or name",
            access: .mutate,
            params: [
                Param(name: "index", type: "int", required: false, description: "Layer index"),
                Param(name: "name", type: "string", required: false, description: "Layer id or label (case-insensitive)")
            ],
            returns: .ok,
            handler: { params in
                var dict: [String: JSON] = [:]
                if case .object(let obj) = params {
                    dict = obj
                }
                dict["mode"] = dict["mode"] ?? .string("launch")
                return try Self.executeLayerActivation(params: .object(dict))
            }
        ))

        api.register(Endpoint(
            method: "layer.activate",
            description: "Activate a workspace layer using an explicit activation mode",
            access: .mutate,
            params: [
                Param(name: "index", type: "int", required: false, description: "Layer index"),
                Param(name: "name", type: "string", required: false, description: "Layer id or label (case-insensitive)"),
                Param(name: "mode", type: "string", required: false, description: "Activation mode: launch, focus, or retile"),
            ],
            returns: .custom("Execution receipt with resolved layer, activation mode, and trace"),
            handler: { params in
                try Self.executeLayerActivation(params: params)
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
            description: "Distribute windows evenly in a grid, optionally filtered by app and constrained to a screen region",
            access: .mutate,
            params: [
                Param(name: "app", type: "string", required: false, description: "Filter to windows of this app (e.g. 'iTerm2')"),
                Param(name: "region", type: "string", required: false, description: "Constrain grid to a screen region (e.g. 'right', 'left', 'top-right'). Uses tile position names."),
            ],
            returns: .ok,
            handler: { params in
                var dict: [String: JSON] = [:]
                if case .object(let obj) = params {
                    dict = obj
                }
                // If app is provided, switch to app scope
                if dict["app"] != nil && dict["scope"] == nil {
                    dict["scope"] = .string("app")
                } else {
                    dict["scope"] = dict["scope"] ?? .string("visible")
                }
                dict["strategy"] = dict["strategy"] ?? .string("balanced")
                return try Self.executeSpaceOptimization(params: .object(dict))
            }
        ))

        api.register(Endpoint(
            method: "space.optimize",
            description: "Optimize a set of windows using an explicit scope and strategy",
            access: .mutate,
            params: [
                Param(name: "scope", type: "string", required: false, description: "Optimization scope: visible, active-app, app, or selection"),
                Param(name: "strategy", type: "string", required: false, description: "Optimization strategy: balanced or mosaic"),
                Param(name: "app", type: "string", required: false, description: "App name for app-scoped optimization"),
                Param(name: "title", type: "string", required: false, description: "Optional title substring for app-scoped optimization"),
                Param(name: "windowIds", type: "[uint32]", required: false, description: "Explicit window selection for selection scope"),
            ],
            returns: .custom("Execution receipt with scope, strategy, resolved windows, and trace"),
            handler: { params in
                try Self.executeSpaceOptimization(params: params)
            }
        ))

        // ── Session Layers ────────────────────────────────────────

        api.model(ApiModel(name: "WindowRef", fields: [
            Field(name: "id", type: "string", required: true, description: "Stable UUID for this ref"),
            Field(name: "app", type: "string", required: true, description: "Application name"),
            Field(name: "contentHint", type: "string", required: false, description: "Title substring hint for matching"),
            Field(name: "tile", type: "string", required: false, description: "Intended tile position"),
            Field(name: "display", type: "int", required: false, description: "Intended display index"),
            Field(name: "wid", type: "int", required: false, description: "Resolved CGWindowID"),
            Field(name: "pid", type: "int", required: false, description: "Resolved process ID"),
            Field(name: "title", type: "string", required: false, description: "Resolved window title"),
            Field(name: "frame", type: "Frame", required: false, description: "Resolved window frame"),
        ]))

        api.model(ApiModel(name: "SessionLayer", fields: [
            Field(name: "id", type: "string", required: true, description: "Layer UUID"),
            Field(name: "name", type: "string", required: true, description: "Layer display name"),
            Field(name: "windows", type: "[WindowRef]", required: true, description: "Window references in this layer"),
        ]))

        api.register(Endpoint(
            method: "session.layers.create",
            description: "Create a named session layer with optional window references",
            access: .mutate,
            params: [
                Param(name: "name", type: "string", required: true, description: "Layer name"),
                Param(name: "windowIds", type: "[uint32]", required: false, description: "Window IDs to include"),
                Param(name: "windows", type: "[object]", required: false, description: "Window refs as {app, contentHint}"),
            ],
            returns: .object(model: "SessionLayer"),
            handler: { params in
                guard let name = params?["name"]?.stringValue, !name.isEmpty else {
                    throw RouterError.missingParam("name")
                }
                var refs: [WindowRef] = []

                // Build refs from windowIds
                if case .array(let ids) = params?["windowIds"] {
                    for idJson in ids {
                        if let wid = idJson.uint32Value, let entry = DesktopModel.shared.windows[wid] {
                            refs.append(WindowRef(
                                app: entry.app, contentHint: entry.title,
                                wid: entry.wid, pid: entry.pid, title: entry.title, frame: entry.frame
                            ))
                        }
                    }
                }

                // Build refs from windows array
                if case .array(let winSpecs) = params?["windows"] {
                    for spec in winSpecs {
                        guard let app = spec["app"]?.stringValue else { continue }
                        let hint = spec["contentHint"]?.stringValue
                        var ref = WindowRef(app: app, contentHint: hint)
                        // Try to resolve immediately
                        if let entry = DesktopModel.shared.windowForApp(app: app, title: hint) {
                            ref.wid = entry.wid
                            ref.pid = entry.pid
                            ref.title = entry.title
                            ref.frame = entry.frame
                        }
                        refs.append(ref)
                    }
                }

                let layer = SessionLayerStore.shared.create(name: name, windows: refs)
                // Update layer tags
                for ref in refs {
                    if let wid = ref.wid {
                        DesktopModel.shared.assignLayer(wid: wid, layerId: name)
                    }
                }
                return Encoders.sessionLayer(layer)
            }
        ))

        api.register(Endpoint(
            method: "session.layers.delete",
            description: "Delete a session layer by id or name",
            access: .mutate,
            params: [
                Param(name: "id", type: "string", required: false, description: "Layer UUID"),
                Param(name: "name", type: "string", required: false, description: "Layer name"),
            ],
            returns: .ok,
            handler: { params in
                let store = SessionLayerStore.shared
                if let id = params?["id"]?.stringValue {
                    store.delete(id: id)
                } else if let name = params?["name"]?.stringValue, let layer = store.layerByName(name) {
                    store.delete(id: layer.id)
                } else {
                    throw RouterError.missingParam("id or name")
                }
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "session.layers.list",
            description: "List all session layers with resolved window info",
            access: .read,
            params: [],
            returns: .custom("Object with 'layers' array and 'activeIndex'"),
            handler: { _ in
                let store = SessionLayerStore.shared
                return .object([
                    "layers": .array(store.layers.map { Encoders.sessionLayer($0) }),
                    "activeIndex": .int(store.activeIndex)
                ])
            }
        ))

        api.register(Endpoint(
            method: "session.layers.assign",
            description: "Add window ref(s) to a session layer",
            access: .mutate,
            params: [
                Param(name: "layerId", type: "string", required: false, description: "Layer UUID"),
                Param(name: "layerName", type: "string", required: false, description: "Layer name"),
                Param(name: "wid", type: "uint32", required: false, description: "Single window ID to add"),
                Param(name: "windowIds", type: "[uint32]", required: false, description: "Multiple window IDs to add"),
                Param(name: "window", type: "object", required: false, description: "Window ref as {app, contentHint}"),
            ],
            returns: .ok,
            handler: { params in
                let store = SessionLayerStore.shared
                let layerId: String
                if let id = params?["layerId"]?.stringValue {
                    layerId = id
                } else if let name = params?["layerName"]?.stringValue, let layer = store.layerByName(name) {
                    layerId = layer.id
                } else {
                    throw RouterError.missingParam("layerId or layerName")
                }

                if let wid = params?["wid"]?.uint32Value {
                    store.assignByWid(wid, toLayerId: layerId)
                }
                if case .array(let ids) = params?["windowIds"] {
                    for idJson in ids {
                        if let wid = idJson.uint32Value {
                            store.assignByWid(wid, toLayerId: layerId)
                        }
                    }
                }
                if let spec = params?["window"] {
                    if let app = spec["app"]?.stringValue {
                        let hint = spec["contentHint"]?.stringValue
                        var ref = WindowRef(app: app, contentHint: hint)
                        if let entry = DesktopModel.shared.windowForApp(app: app, title: hint) {
                            ref.wid = entry.wid
                            ref.pid = entry.pid
                            ref.title = entry.title
                            ref.frame = entry.frame
                        }
                        store.assign(ref: ref, toLayerId: layerId)
                    }
                }
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "session.layers.remove",
            description: "Remove window ref(s) from a session layer",
            access: .mutate,
            params: [
                Param(name: "layerId", type: "string", required: false, description: "Layer UUID"),
                Param(name: "layerName", type: "string", required: false, description: "Layer name"),
                Param(name: "refId", type: "string", required: true, description: "WindowRef ID to remove"),
            ],
            returns: .ok,
            handler: { params in
                let store = SessionLayerStore.shared
                let layerId: String
                if let id = params?["layerId"]?.stringValue {
                    layerId = id
                } else if let name = params?["layerName"]?.stringValue, let layer = store.layerByName(name) {
                    layerId = layer.id
                } else {
                    throw RouterError.missingParam("layerId or layerName")
                }
                guard let refId = params?["refId"]?.stringValue else {
                    throw RouterError.missingParam("refId")
                }
                store.remove(refId: refId, fromLayerId: layerId)
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "session.layers.switch",
            description: "Switch to a session layer by index or name",
            access: .mutate,
            params: [
                Param(name: "index", type: "int", required: false, description: "Layer index"),
                Param(name: "name", type: "string", required: false, description: "Layer name"),
            ],
            returns: .ok,
            handler: { params in
                let store = SessionLayerStore.shared
                let index: Int
                if let i = params?["index"]?.intValue {
                    index = i
                } else if let name = params?["name"]?.stringValue,
                          let i = store.layers.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                    index = i
                } else {
                    throw RouterError.missingParam("index or name")
                }
                DispatchQueue.main.async {
                    store.switchTo(index: index)
                }
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "session.layers.rename",
            description: "Rename a session layer",
            access: .mutate,
            params: [
                Param(name: "id", type: "string", required: false, description: "Layer UUID"),
                Param(name: "oldName", type: "string", required: false, description: "Current layer name"),
                Param(name: "name", type: "string", required: true, description: "New layer name"),
            ],
            returns: .ok,
            handler: { params in
                let store = SessionLayerStore.shared
                guard let newName = params?["name"]?.stringValue, !newName.isEmpty else {
                    throw RouterError.missingParam("name")
                }
                if let id = params?["id"]?.stringValue {
                    store.rename(id: id, name: newName)
                } else if let oldName = params?["oldName"]?.stringValue, let layer = store.layerByName(oldName) {
                    store.rename(id: layer.id, name: newName)
                } else {
                    throw RouterError.missingParam("id or oldName")
                }
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "session.layers.clear",
            description: "Clear all session layers",
            access: .mutate,
            params: [],
            returns: .ok,
            handler: { _ in
                SessionLayerStore.shared.clear()
                return .object(["ok": .bool(true)])
            }
        ))

        // ── Intents ───────────────────────────────────────────────

        api.model(ApiModel(name: "IntentSlot", fields: [
            Field(name: "name", type: "string", required: true, description: "Slot name"),
            Field(name: "type", type: "string", required: true, description: "Slot type (string, int, position, query, bool)"),
            Field(name: "required", type: "bool", required: true, description: "Whether the slot is required"),
            Field(name: "description", type: "string", required: true, description: "Slot description"),
            Field(name: "values", type: "[string]", required: false, description: "Allowed values for enum slots"),
        ]))

        api.model(ApiModel(name: "IntentDef", fields: [
            Field(name: "intent", type: "string", required: true, description: "Intent identifier"),
            Field(name: "description", type: "string", required: true, description: "What the intent does"),
            Field(name: "examples", type: "[string]", required: true, description: "Example phrases"),
            Field(name: "slots", type: "[IntentSlot]", required: true, description: "Named parameters"),
        ]))

        api.register(Endpoint(
            method: "intents.list",
            description: "List all available intents with their slots and example phrases",
            access: .read,
            params: [],
            returns: .array(model: "IntentDef"),
            handler: { _ in
                IntentEngine.shared.catalog()
            }
        ))

        api.register(Endpoint(
            method: "intents.execute",
            description: "Execute a structured intent (from voice, agent, or script)",
            access: .mutate,
            params: [
                Param(name: "intent", type: "string", required: true, description: "Intent name (e.g. 'tile_window', 'focus', 'launch')"),
                Param(name: "slots", type: "object", required: false, description: "Named parameters for the intent"),
                Param(name: "rawText", type: "string", required: false, description: "Original transcription text"),
                Param(name: "confidence", type: "double", required: false, description: "Transcription confidence (0-1)"),
                Param(name: "source", type: "string", required: false, description: "Source of the intent (e.g. 'vox', 'siri', 'cli')"),
            ],
            returns: .custom("Intent-specific result"),
            handler: { params in
                guard let intentName = params?["intent"]?.stringValue else {
                    throw RouterError.missingParam("intent")
                }

                // Extract slots
                var slots: [String: JSON] = [:]
                if case .object(let obj) = params?["slots"] {
                    slots = obj
                }

                let request = IntentRequest(
                    intent: intentName,
                    slots: slots,
                    rawText: params?["rawText"]?.stringValue,
                    confidence: params?["confidence"]?.numericDouble,
                    source: params?["source"]?.stringValue
                )

                return try IntentEngine.shared.execute(request)
            }
        ))

        // ── Voice / Audio ─────────────────────────────────────────

        api.register(Endpoint(
            method: "voice.status",
            description: "Check audio provider status (e.g. Vox availability)",
            access: .read,
            params: [],
            returns: .custom("Provider status with name and listening state"),
            handler: { _ in
                let audio = AudioLayer.shared
                return .object([
                    "provider": .string(audio.providerName),
                    "available": .bool(audio.provider?.isAvailable ?? false),
                    "listening": .bool(audio.isListening),
                    "lastTranscript": audio.lastTranscript.map { .string($0) } ?? .null
                ])
            }
        ))

        api.register(Endpoint(
            method: "voice.listen",
            description: "Start voice capture via the audio provider (e.g. Vox)",
            access: .mutate,
            params: [],
            returns: .ok,
            handler: { _ in
                guard AudioLayer.shared.provider != nil else {
                    throw RouterError.custom("No audio provider available. Is Vox running?")
                }
                DispatchQueue.main.async {
                    AudioLayer.shared.startVoiceCommand()
                }
                return .object(["ok": .bool(true), "provider": .string(AudioLayer.shared.providerName)])
            }
        ))

        api.register(Endpoint(
            method: "voice.stop",
            description: "Stop voice capture and process the transcription",
            access: .mutate,
            params: [],
            returns: .ok,
            handler: { _ in
                DispatchQueue.main.async {
                    AudioLayer.shared.stopVoiceCommand()
                }
                return .object(["ok": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "voice.simulate",
            description: "Simulate a voice command: parse text into an intent and execute it",
            access: .mutate,
            params: [
                Param(name: "text", type: "string", required: true, description: "Voice command text (as if transcribed)"),
                Param(name: "execute", type: "bool", required: false, description: "Actually execute the intent (default true)"),
            ],
            returns: .custom("Parsed intent with execution result"),
            handler: { params in
                guard let text = params?["text"]?.stringValue, !text.isEmpty else {
                    throw RouterError.missingParam("text")
                }
                let shouldExecute = params?["execute"]?.boolValue ?? true

                let matcher = PhraseMatcher.shared
                guard let matched = matcher.match(text: text) else {
                    return .object([
                        "parsed": .bool(false),
                        "text": .string(text),
                        "intent": .null,
                        "message": .string("No intent matched")
                    ])
                }

                var response: [String: JSON] = [
                    "parsed": .bool(true),
                    "text": .string(text),
                    "intent": .string(matched.intentName),
                    "slots": .object(matched.slots),
                    "confidence": .double(matched.confidence),
                ]

                if shouldExecute {
                    do {
                        let result = try matcher.execute(matched)
                        response["executed"] = .bool(true)
                        response["result"] = result
                    } catch {
                        response["executed"] = .bool(false)
                        response["error"] = .string(error.localizedDescription)
                    }
                }

                return .object(response)
            }
        ))

        api.register(Endpoint(
            method: "voice.reconnect",
            description: "Force disconnect and reconnect the Vox WebSocket connection",
            access: .mutate,
            params: [],
            returns: .custom("Reconnection initiated with previous and new connection state"),
            handler: { _ in
                let client = VoxClient.shared
                let previousState = "\(client.connectionState)"
                DispatchQueue.main.async {
                    client.reconnect()
                }
                return .object([
                    "ok": .bool(true),
                    "previousState": .string(previousState),
                    "action": .string("reconnecting"),
                ])
            }
        ))

        // ── Meta endpoint ───────────────────────────────────────

        // ── Mouse Finder ────────────────────────────────────────

        api.register(Endpoint(
            method: "mouse.find",
            description: "Show a sonar pulse at the current mouse cursor position",
            access: .read,
            params: [],
            returns: .ok,
            handler: { _ in
                DispatchQueue.main.async { MouseFinder.shared.find() }
                let pos = NSEvent.mouseLocation
                return .object(["ok": .bool(true), "x": .int(Int(pos.x)), "y": .int(Int(pos.y))])
            }
        ))

        api.register(Endpoint(
            method: "mouse.summon",
            description: "Warp the mouse cursor to screen center (or a given point) and show a sonar pulse",
            access: .mutate,
            params: [
                Param(name: "x", type: "int", required: false, description: "Target X coordinate (screen, bottom-left origin)"),
                Param(name: "y", type: "int", required: false, description: "Target Y coordinate (screen, bottom-left origin)"),
            ],
            returns: .ok,
            handler: { params in
                let target: CGPoint?
                if let x = params?["x"]?.intValue, let y = params?["y"]?.intValue {
                    target = CGPoint(x: CGFloat(x), y: CGFloat(y))
                } else {
                    target = nil
                }
                DispatchQueue.main.async { MouseFinder.shared.summon(to: target) }
                let pos = target ?? {
                    let screen = NSScreen.main ?? NSScreen.screens[0]
                    return CGPoint(x: screen.frame.midX, y: screen.frame.midY)
                }()
                return .object(["ok": .bool(true), "x": .int(Int(pos.x)), "y": .int(Int(pos.y))])
            }
        ))

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

private extension LatticesApi {
    static func parsePlacement(from json: JSON?) -> PlacementSpec? {
        PlacementSpec(json: json)
    }

    static func resolveTargetScreen(for entry: WindowEntry?, displayIndex: Int?) -> NSScreen {
        if let displayIndex, displayIndex >= 0, displayIndex < NSScreen.screens.count {
            return NSScreen.screens[displayIndex]
        }
        if let entry {
            return WindowTiler.screenForWindowFrame(entry.frame)
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    static func frontmostWindowTarget() -> (wid: UInt32, pid: Int32)? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != "com.arach.lattices" else {
            return nil
        }

        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
              let focusedWindow = focusedRef else {
            return nil
        }

        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(focusedWindow as! AXUIElement, &wid) == .success else {
            return nil
        }
        return (UInt32(wid), app.processIdentifier)
    }

    static func executeWindowPlacement(params: JSON?) throws -> JSON {
        guard let placement = parsePlacement(from: params?["placement"] ?? params?["position"]) else {
            throw RouterError.missingParam("placement")
        }

        let displayIndex = params?["display"]?.intValue
        var trace: [JSON] = []

        if let wid = params?["wid"]?.uint32Value {
            guard let entry = DesktopModel.shared.windows[wid] else {
                throw RouterError.notFound("window \(wid)")
            }
            let screen = resolveTargetScreen(for: entry, displayIndex: displayIndex)
            trace.append(.string("resolved target by wid"))
            trace.append(.string("placement \(placement.wireValue)"))
            DispatchQueue.main.async {
                WindowTiler.tileWindowById(wid: wid, pid: entry.pid, to: placement, on: screen)
            }
            return .object([
                "ok": .bool(true),
                "target": .string("wid"),
                "wid": .int(Int(wid)),
                "app": .string(entry.app),
                "placement": placement.jsonValue,
                "trace": .array(trace),
            ])
        }

        if let session = params?["session"]?.stringValue {
            let screen = resolveTargetScreen(
                for: DesktopModel.shared.windowForSession(session),
                displayIndex: displayIndex
            )
            trace.append(.string("resolved target by session"))
            trace.append(.string("placement \(placement.wireValue)"))

            if let entry = DesktopModel.shared.windowForSession(session) {
                DispatchQueue.main.async {
                    WindowTiler.tileWindowById(wid: entry.wid, pid: entry.pid, to: placement, on: screen)
                }
                return .object([
                    "ok": .bool(true),
                    "target": .string("session"),
                    "session": .string(session),
                    "wid": .int(Int(entry.wid)),
                    "placement": placement.jsonValue,
                    "trace": .array(trace),
                ])
            }

            let terminal = Preferences.shared.terminal
            trace.append(.string("session window not in DesktopModel; using terminal fallback"))
            DispatchQueue.main.async {
                WindowTiler.tile(session: session, terminal: terminal, to: placement, on: screen)
            }
            return .object([
                "ok": .bool(true),
                "target": .string("session"),
                "session": .string(session),
                "placement": placement.jsonValue,
                "trace": .array(trace),
            ])
        }

        if let app = params?["app"]?.stringValue {
            let title = params?["title"]?.stringValue
            guard let entry = DesktopModel.shared.windowForApp(app: app, title: title) else {
                throw RouterError.notFound("window for app \(app)")
            }
            let screen = resolveTargetScreen(for: entry, displayIndex: displayIndex)
            trace.append(.string("resolved target by app/title match"))
            trace.append(.string("placement \(placement.wireValue)"))
            DispatchQueue.main.async {
                WindowTiler.tileWindowById(wid: entry.wid, pid: entry.pid, to: placement, on: screen)
            }
            return .object([
                "ok": .bool(true),
                "target": .string("app"),
                "app": .string(entry.app),
                "wid": .int(Int(entry.wid)),
                "placement": placement.jsonValue,
                "trace": .array(trace),
            ])
        }

        if let target = frontmostWindowTarget() {
            let wid = target.wid
            let entry = DesktopModel.shared.windows[wid]
            let screen = resolveTargetScreen(for: entry, displayIndex: displayIndex)
            trace.append(.string("resolved target by frontmost window"))
            trace.append(.string("placement \(placement.wireValue)"))
            DispatchQueue.main.async {
                WindowTiler.tileWindowById(wid: wid, pid: target.pid, to: placement, on: screen)
            }

            var response: [String: JSON] = [
                "ok": .bool(true),
                "target": .string("frontmost"),
                "wid": .int(Int(wid)),
                "placement": placement.jsonValue,
                "trace": .array(trace),
            ]
            if let entry {
                response["app"] = .string(entry.app)
            }
            return .object(response)
        }

        throw RouterError.custom("Could not resolve a window target for placement")
    }

    static func executeLayerActivation(params: JSON?) throws -> JSON {
        let wm = WorkspaceManager.shared
        guard let layers = wm.config?.layers, !layers.isEmpty else {
            throw RouterError.notFound("workspace layers")
        }

        let index: Int
        var trace: [JSON] = []

        if let value = params?["index"]?.intValue {
            index = value
            trace.append(.string("resolved layer by index"))
        } else if let name = params?["name"]?.stringValue, let value = wm.layerIndex(named: name) {
            index = value
            trace.append(.string("resolved layer by name"))
        } else {
            throw RouterError.missingParam("index or name")
        }

        guard index >= 0, index < layers.count else {
            throw RouterError.notFound("layer \(index)")
        }

        let mode = try parseLayerActivationMode(params?["mode"]?.stringValue)
        let layer = layers[index]
        let previousIndex = wm.activeLayerIndex
        trace.append(.string("activation mode \(mode)"))

        DispatchQueue.main.async {
            switch mode {
            case "focus":
                wm.focusLayer(index: index)
            case "retile":
                wm.tileLayer(index: index, launch: false, force: true)
            default:
                wm.tileLayer(index: index, launch: true, force: true)
            }

            if previousIndex != index || mode != "focus" {
                EventBus.shared.post(.layerSwitched(index: index))
            }
        }

        return .object([
            "ok": .bool(true),
            "index": .int(index),
            "id": .string(layer.id),
            "label": .string(layer.label),
            "mode": .string(mode),
            "trace": .array(trace),
        ])
    }

    static func executeSpaceOptimization(params: JSON?) throws -> JSON {
        let scope = try parseOptimizationScope(from: params)
        let strategy = try parseOptimizationStrategy(params?["strategy"]?.stringValue)
        var trace: [JSON] = [.string("resolved scope \(scope)"), .string("resolved strategy \(strategy)")]
        let windows = resolveOptimizationTargets(scope: scope, params: params, trace: &trace)

        // Resolve optional region constraint (e.g. "right" → right half of screen)
        var region: (CGFloat, CGFloat, CGFloat, CGFloat)? = nil
        if let regionStr = params?["region"]?.stringValue {
            if let spec = PlacementSpec(string: regionStr) {
                region = spec.fractions
                trace.append(.string("region \(regionStr) → fractions \(spec.fractions)"))
            } else {
                trace.append(.string("unknown region \(regionStr), using full screen"))
            }
        }

        if strategy == "mosaic" {
            trace.append(.string("strategy mosaic currently uses the smart-grid distributor"))
        }

        guard !windows.isEmpty else {
            trace.append(.string("no eligible windows resolved"))
            return .object([
                "ok": .bool(true),
                "scope": .string(scope),
                "strategy": .string(strategy),
                "windowCount": .int(0),
                "wids": .array([]),
                "trace": .array(trace),
            ])
        }

        let targets = windows.map { (wid: $0.wid, pid: $0.pid) }
        DispatchQueue.main.async {
            WindowTiler.batchRaiseAndDistribute(windows: targets, region: region)
        }

        return .object([
            "ok": .bool(true),
            "scope": .string(scope),
            "strategy": .string(strategy),
            "windowCount": .int(windows.count),
            "wids": .array(windows.map { .int(Int($0.wid)) }),
            "trace": .array(trace),
        ])
    }

    static func parseLayerActivationMode(_ raw: String?) throws -> String {
        let mode = normalizeToken(raw ?? "launch")
        switch mode {
        case "launch", "focus", "retile":
            return mode
        default:
            throw RouterError.custom("Unsupported layer activation mode: \(raw ?? mode)")
        }
    }

    static func parseOptimizationScope(from params: JSON?) throws -> String {
        if params?["windowIds"] != nil {
            return "selection"
        }
        if params?["app"] != nil {
            return "app"
        }

        let scope = normalizeToken(params?["scope"]?.stringValue ?? "visible")
        switch scope {
        case "visible", "selection", "app", "active-app", "frontmost-app", "current-app":
            return scope
        default:
            throw RouterError.custom("Unsupported optimization scope: \(params?["scope"]?.stringValue ?? scope)")
        }
    }

    static func parseOptimizationStrategy(_ raw: String?) throws -> String {
        let strategy = normalizeToken(raw ?? "balanced")
        switch strategy {
        case "balanced", "mosaic":
            return strategy
        default:
            throw RouterError.custom("Unsupported optimization strategy: \(raw ?? strategy)")
        }
    }

    static func resolveOptimizationTargets(scope: String, params: JSON?, trace: inout [JSON]) -> [WindowEntry] {
        let visible = distributableWindows()
        let titleFilter = params?["title"]?.stringValue

        switch scope {
        case "selection":
            let ids = selectedWindowIds(from: params?["windowIds"])
            trace.append(.string("selection size \(ids.count)"))
            return dedupeWindows(visible.filter { ids.contains($0.wid) })

        case "app":
            guard let app = params?["app"]?.stringValue else {
                trace.append(.string("missing app for app scope"))
                return []
            }
            trace.append(.string("filtered by app \(app)"))
            if let titleFilter {
                trace.append(.string("title contains \(titleFilter)"))
            }
            return dedupeWindows(visible.filter {
                $0.app.localizedCaseInsensitiveCompare(app) == .orderedSame &&
                (titleFilter == nil || $0.title.localizedCaseInsensitiveContains(titleFilter!))
            })

        case "active-app", "frontmost-app", "current-app":
            let activeApp = params?["app"]?.stringValue ?? frontmostOptimizableApp()
            guard let activeApp else {
                trace.append(.string("no active app available"))
                return []
            }
            trace.append(.string("resolved active app \(activeApp)"))
            if let titleFilter {
                trace.append(.string("title contains \(titleFilter)"))
            }
            return dedupeWindows(visible.filter {
                $0.app.localizedCaseInsensitiveCompare(activeApp) == .orderedSame &&
                (titleFilter == nil || $0.title.localizedCaseInsensitiveContains(titleFilter!))
            })

        default:
            trace.append(.string("using visible window scope"))
            return dedupeWindows(visible)
        }
    }

    static func selectedWindowIds(from json: JSON?) -> [UInt32] {
        guard case .array(let values) = json else { return [] }
        return values.compactMap(\.uint32Value)
    }

    static func distributableWindows() -> [WindowEntry] {
        DesktopModel.shared.allWindows().filter { entry in
            entry.isOnScreen &&
            entry.app != "Lattices" &&
            entry.frame.w > 50 &&
            entry.frame.h > 50
        }
    }

    static func dedupeWindows(_ windows: [WindowEntry]) -> [WindowEntry] {
        var seen: Set<UInt32> = []
        var result: [WindowEntry] = []
        for window in windows where !seen.contains(window.wid) {
            seen.insert(window.wid)
            result.append(window)
        }
        return result
    }

    static func frontmostOptimizableApp() -> String? {
        if let app = NSWorkspace.shared.frontmostApplication?.localizedName,
           !app.localizedCaseInsensitiveContains("lattices") {
            return app
        }
        return distributableWindows().first?.app
    }

    static func normalizeToken(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
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
            "isOnScreen": .bool(w.isOnScreen),
            "axVerified": .bool(w.axVerified)
        ]
        if let session = w.latticesSession {
            obj["latticesSession"] = .string(session)
        }
        if let layerTag = DesktopModel.shared.windowLayerTags[w.wid] {
            obj["layerTag"] = .string(layerTag)
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

    static func ocrResult(_ r: OcrWindowResult) -> JSON {
        .object([
            "wid": .int(Int(r.wid)),
            "app": .string(r.app),
            "title": .string(r.title),
            "frame": .object([
                "x": .double(r.frame.x),
                "y": .double(r.frame.y),
                "w": .double(r.frame.w),
                "h": .double(r.frame.h)
            ]),
            "fullText": .string(r.fullText),
            "blocks": .array(r.texts.map { block in
                .object([
                    "text": .string(block.text),
                    "confidence": .double(Double(block.confidence)),
                    "x": .double(block.boundingBox.origin.x),
                    "y": .double(block.boundingBox.origin.y),
                    "w": .double(block.boundingBox.size.width),
                    "h": .double(block.boundingBox.size.height)
                ])
            }),
            "timestamp": .double(r.timestamp.timeIntervalSince1970),
            "source": .string(r.source.rawValue)
        ])
    }

    static func ocrSearchResult(_ r: OcrSearchResult) -> JSON {
        .object([
            "id": .int(Int(r.id)),
            "wid": .int(Int(r.wid)),
            "app": .string(r.app),
            "title": .string(r.title),
            "frame": .object([
                "x": .double(r.frame.x),
                "y": .double(r.frame.y),
                "w": .double(r.frame.w),
                "h": .double(r.frame.h)
            ]),
            "fullText": .string(r.fullText),
            "snippet": .string(r.snippet),
            "timestamp": .double(r.timestamp.timeIntervalSince1970),
            "source": .string(r.source.rawValue)
        ])
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

    static func windowRef(_ ref: WindowRef) -> JSON {
        var obj: [String: JSON] = [
            "id": .string(ref.id),
            "app": .string(ref.app),
        ]
        if let hint = ref.contentHint { obj["contentHint"] = .string(hint) }
        if let tile = ref.tile { obj["tile"] = .string(tile) }
        if let display = ref.display { obj["display"] = .int(display) }
        if let wid = ref.wid { obj["wid"] = .int(Int(wid)) }
        if let pid = ref.pid { obj["pid"] = .int(Int(pid)) }
        if let title = ref.title { obj["title"] = .string(title) }
        if let frame = ref.frame {
            obj["frame"] = .object([
                "x": .double(frame.x), "y": .double(frame.y),
                "w": .double(frame.w), "h": .double(frame.h)
            ])
        }
        return .object(obj)
    }

    static func sessionLayer(_ layer: SessionLayer) -> JSON {
        .object([
            "id": .string(layer.id),
            "name": .string(layer.name),
            "windows": .array(layer.windows.map { windowRef($0) })
        ])
    }
}

// MARK: - Errors

enum RouterError: LocalizedError {
    case unknownMethod(String)
    case missingParam(String)
    case notFound(String)
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .unknownMethod(let m): return "Unknown method: \(m)"
        case .missingParam(let p):  return "Missing parameter: \(p)"
        case .notFound(let what):   return "Not found: \(what)"
        case .custom(let msg):      return msg
        }
    }
}
