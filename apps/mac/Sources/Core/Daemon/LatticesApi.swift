import AppKit
import ApplicationServices
import DeckKit
import Foundation
#if LATTICES_VOICE && canImport(HudsonVoice)
import HudsonVoice
#endif

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
            Field(name: "name", type: "string", required: true, description: "Lattices display name for the space"),
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

        api.model(ApiModel(name: "OverlayLayer", fields: [
            Field(name: "id", type: "string", required: true, description: "Overlay layer identifier"),
            Field(name: "kind", type: "string", required: true, description: "Overlay kind: toast, label, highlight, pet"),
            Field(name: "owner", type: "string", required: true, description: "Layer owner namespace"),
            Field(name: "expiresAt", type: "double", required: false, description: "Expiration timestamp (Unix seconds)"),
        ]))

        api.model(ApiModel(name: "ActionReceipt", fields: [
            Field(name: "ok", type: "bool", required: true, description: "Whether the action completed successfully"),
            Field(name: "status", type: "string", required: true, description: "ok, planned, partial, failed, or blocked"),
            Field(name: "receiptId", type: "string", required: true, description: "Execution receipt identifier"),
            Field(name: "requestId", type: "string", required: true, description: "Caller request identifier"),
            Field(name: "source", type: "string", required: true, description: "Calling surface, such as daemon, voice, CLI, or companion"),
            Field(name: "action", type: "object", required: true, description: "Canonical action descriptor"),
            Field(name: "target", type: "object", required: true, description: "Resolved target with confidence and identifiers"),
            Field(name: "targetKind", type: "string", required: true, description: "Compatibility target kind such as wid, session, app, or frontmost"),
            Field(name: "targetResolution", type: "string", required: true, description: "Resolution strategy used for the target"),
            Field(name: "placement", type: "object", required: false, description: "Resolved placement spec for window.place"),
            Field(name: "plan", type: "object", required: false, description: "Dry-run plan used before mutation"),
            Field(name: "mutations", type: "[object]", required: true, description: "Applied mutations and frame changes"),
            Field(name: "verified", type: "bool", required: true, description: "Whether the final state was verified"),
            Field(name: "undoable", type: "bool", required: false, description: "Whether the receipt can be restored through actions.undo"),
            Field(name: "undoOf", type: "[string]", required: false, description: "Receipt ids restored by an actions.undo receipt"),
            Field(name: "trace", type: "[string]", required: true, description: "Human-readable execution trace"),
            Field(name: "events", type: "[object]", required: true, description: "Structured execution events"),
        ]))

        api.model(ApiModel(name: "RunSession", fields: [
            Field(name: "id", type: "string", required: true, description: "Stable run identifier"),
            Field(name: "title", type: "string", required: true, description: "Human-readable run title"),
            Field(name: "source", type: "string", required: true, description: "Calling surface, such as palette, CLI, daemon, or agent"),
            Field(name: "state", type: "string", required: true, description: "created, running, completed, failed, or cancelled"),
            Field(name: "startedAt", type: "string", required: true, description: "ISO-8601 start timestamp"),
            Field(name: "completedAt", type: "string", required: false, description: "ISO-8601 completion timestamp"),
            Field(name: "artifactDirectoryPath", type: "string", required: true, description: "Local directory containing run artifacts"),
            Field(name: "surfaces", type: "[object]", required: true, description: "Windows, apps, or regions involved in the run"),
            Field(name: "artifacts", type: "[RunArtifact]", required: true, description: "Artifacts produced by the run"),
            Field(name: "trace", type: "[RunTraceEvent]", required: true, description: "Machine-readable run timeline"),
        ]))

        api.model(ApiModel(name: "RunArtifact", fields: [
            Field(name: "id", type: "string", required: true, description: "Stable artifact identifier"),
            Field(name: "runId", type: "string", required: true, description: "Owning run id"),
            Field(name: "kind", type: "string", required: true, description: "Artifact kind, such as screenshot or recording"),
            Field(name: "path", type: "string", required: true, description: "Absolute local artifact path"),
            Field(name: "relativePath", type: "string", required: true, description: "Path relative to the run artifact directory"),
            Field(name: "mimeType", type: "string", required: true, description: "Artifact MIME type"),
            Field(name: "createdAt", type: "string", required: true, description: "ISO-8601 creation timestamp"),
            Field(name: "metadata", type: "object", required: true, description: "Artifact-specific metadata such as dimensions and target window"),
        ]))

        api.model(ApiModel(name: "RunTraceEvent", fields: [
            Field(name: "id", type: "string", required: true, description: "Stable trace event identifier"),
            Field(name: "runId", type: "string", required: true, description: "Owning run id"),
            Field(name: "time", type: "string", required: true, description: "ISO-8601 event timestamp"),
            Field(name: "kind", type: "string", required: true, description: "Event kind, such as run.created or artifact.created"),
            Field(name: "summary", type: "string", required: true, description: "Human-readable event summary"),
            Field(name: "data", type: "object", required: true, description: "Structured event payload"),
        ]))

        api.model(ApiModel(name: "AXElement", fields: [
            Field(name: "id", type: "string", required: true, description: "Snapshot-local element id, such as e1"),
            Field(name: "role", type: "string", required: true, description: "Accessibility role, such as AXButton or AXTextField"),
            Field(name: "roleDescription", type: "string", required: false, description: "Localized role description"),
            Field(name: "title", type: "string", required: false, description: "AX title"),
            Field(name: "label", type: "string", required: false, description: "AX label when available"),
            Field(name: "value", type: "string", required: false, description: "AX value converted to a short string"),
            Field(name: "description", type: "string", required: false, description: "AX description"),
            Field(name: "help", type: "string", required: false, description: "AX help text"),
            Field(name: "identifier", type: "string", required: false, description: "AX identifier"),
            Field(name: "frame", type: "Frame", required: false, description: "Screen-coordinate element frame"),
            Field(name: "enabled", type: "bool", required: false, description: "Whether the element is enabled"),
            Field(name: "selected", type: "bool", required: false, description: "Whether the element is selected"),
            Field(name: "focused", type: "bool", required: false, description: "Whether the element is focused"),
            Field(name: "actions", type: "[string]", required: true, description: "Supported AX action names"),
            Field(name: "path", type: "string", required: true, description: "Snapshot-local tree path"),
            Field(name: "depth", type: "int", required: true, description: "Tree depth from the target window"),
            Field(name: "childCount", type: "int", required: true, description: "Number of AX children reported for the element"),
        ]))

        api.model(ApiModel(name: "ComputerWindowState", fields: [
            Field(name: "ok", type: "bool", required: true, description: "Whether the snapshot completed"),
            Field(name: "snapshotId", type: "string", required: true, description: "Snapshot id for this inspection"),
            Field(name: "target", type: "Window", required: true, description: "Resolved target window"),
            Field(name: "mode", type: "string", required: true, description: "ax, both, or screenshot"),
            Field(name: "elements", type: "[AXElement]", required: true, description: "Accessibility elements in traversal order"),
            Field(name: "elementCount", type: "int", required: true, description: "Number of returned elements"),
            Field(name: "treeMarkdown", type: "string", required: true, description: "Compact tree view for humans and agents"),
            Field(name: "warnings", type: "[string]", required: true, description: "Non-fatal traversal or capture warnings"),
            Field(name: "artifact", type: "RunArtifact", required: false, description: "Optional screenshot artifact when capture is enabled"),
            Field(name: "run", type: "RunSession", required: false, description: "Run record when capture is enabled"),
        ]))

        api.model(ApiModel(name: "MouseShortcutConfig", fields: [
            Field(name: "version", type: "int", required: true, description: "Mouse shortcut config version"),
            Field(name: "tuning", type: "object", required: true, description: "Gesture recognition tuning values"),
            Field(name: "rules", type: "[MouseShortcutRule]", required: true, description: "Ordered gesture rules"),
        ]))

        api.model(ApiModel(name: "MouseShortcutRule", fields: [
            Field(name: "id", type: "string", required: true, description: "Stable rule identifier"),
            Field(name: "enabled", type: "bool", required: true, description: "Whether the rule is active"),
            Field(name: "device", type: "string|object", required: true, description: "Device selector, usually 'any'"),
            Field(name: "trigger", type: "object", required: true, description: "Gesture trigger: { button, kind, direction?, shape? }"),
            Field(name: "action", type: "object", required: true, description: "Primary action, usually { type: 'shortcut.send', shortcut }"),
            Field(name: "actions", type: "[object]", required: false, description: "Optional multi-action sequence"),
            Field(name: "visual", type: "object", required: false, description: "Optional gesture visual renderer metadata"),
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
                                "name": .string(Self.defaultSpaceName(for: space.index)),
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
            method: "deck.manifest",
            description: "Get the shared companion deck manifest exposed by the macOS app",
            access: .read,
            params: [],
            returns: .custom("DeckKit manifest for the Lattices companion surface"),
            handler: { _ in
                try Self.encodeDeckValue(LatticesDeckHost.shared.manifestSync())
            }
        ))

        api.register(Endpoint(
            method: "deck.snapshot",
            description: "Get the current companion deck runtime snapshot",
            access: .read,
            params: [],
            returns: .custom("DeckKit runtime snapshot with voice, layout, switcher, and history state"),
            handler: { _ in
                try Self.encodeDeckValue(LatticesDeckHost.shared.runtimeSnapshotSync())
            }
        ))

        api.register(Endpoint(
            method: "deck.perform",
            description: "Perform a companion deck action and return the updated runtime snapshot",
            access: .mutate,
            params: [
                Param(name: "pageID", type: "string", required: false, description: "Deck page ID"),
                Param(name: "actionID", type: "string", required: true, description: "Deck action identifier"),
                Param(name: "payload", type: "object", required: false, description: "Deck action payload"),
            ],
            returns: .custom("DeckKit action result"),
            handler: { params in
                let request = try Self.decodeDeckActionRequest(from: params)
                let result = try LatticesDeckHost.shared.performSync(request)
                return try Self.encodeDeckValue(result)
            }
        ))

        api.register(Endpoint(
            method: "overlay.publish",
            description: "Publish a transient visual layer on the invisible screen overlay canvas",
            access: .mutate,
            params: [
                Param(name: "kind", type: "string", required: true, description: "toast, label, highlight, or pet"),
                Param(name: "id", type: "string", required: false, description: "Stable layer id; generated if omitted"),
                Param(name: "text", type: "string", required: false, description: "Toast/label text"),
                Param(name: "detail", type: "string", required: false, description: "Secondary toast/label text"),
                Param(name: "message", type: "string", required: false, description: "Pet speech/message"),
                Param(name: "glyph", type: "string", required: false, description: "Pet glyph, emoji, or short symbol"),
                Param(name: "petId", type: "string", required: false, description: "Bundled pet id from Resources/Pets"),
                Param(name: "state", type: "string", required: false, description: "Pet animation state"),
                Param(name: "name", type: "string", required: false, description: "Pet name"),
                Param(name: "targetApp", type: "string", required: false, description: "App name to activate when this pet is clicked"),
                Param(name: "targetBundleId", type: "string", required: false, description: "Bundle identifier to activate when this pet is clicked"),
                Param(name: "targetAppPath", type: "string", required: false, description: "Application bundle path to open when this pet is clicked"),
                Param(name: "scale", type: "double", required: false, description: "Actor scale multiplier"),
                Param(name: "labelHidden", type: "bool", required: false, description: "Hide the actor label/message"),
                Param(name: "closeOnActivate", type: "bool", required: false, description: "Remove the actor after activating its target app"),
                Param(name: "hudUrl", type: "string", required: false, description: "URL to render in a hover HUD web view"),
                Param(name: "hudHTML", type: "string", required: false, description: "Inline HTML to render in a hover HUD web view"),
                Param(name: "hudWidth", type: "double", required: false, description: "Hover HUD width"),
                Param(name: "hudHeight", type: "double", required: false, description: "Hover HUD height"),
                Param(name: "hudReadAccess", type: "string", required: false, description: "Local folder the file-backed HUD may read"),
                Param(name: "x", type: "double", required: false, description: "Screen-local x coordinate"),
                Param(name: "y", type: "double", required: false, description: "Screen-local y coordinate"),
                Param(name: "w", type: "double", required: false, description: "Highlight width"),
                Param(name: "h", type: "double", required: false, description: "Highlight height"),
                Param(name: "placement", type: "string", required: false, description: "top, bottom, center, cursor, or point"),
                Param(name: "style", type: "string", required: false, description: "info, success, warning, danger, or playful"),
                Param(name: "display", type: "int", required: false, description: "Display index; omit for all displays"),
                Param(name: "ttlMs", type: "int", required: false, description: "Time to live in milliseconds"),
                Param(name: "opacity", type: "double", required: false, description: "Opacity 0-1"),
                Param(name: "zIndex", type: "int", required: false, description: "Layer ordering"),
                Param(name: "dismissible", type: "bool", required: false, description: "Whether click-away dismissal removes the layer"),
            ],
            returns: .object(model: "OverlayLayer"),
            handler: { params in
                try Self.publishOverlay(params)
            }
        ))

        api.register(Endpoint(
            method: "overlay.clear",
            description: "Clear overlay layers published through the daemon API",
            access: .mutate,
            params: [
                Param(name: "id", type: "string", required: false, description: "Specific layer id to clear"),
                Param(name: "owner", type: "string", required: false, description: "Owner namespace to clear; defaults to agentApi"),
            ],
            returns: .ok,
            handler: { params in
                try Self.clearOverlay(params)
            }
        ))

        api.register(Endpoint(
            method: "overlay.actor.publish",
            description: "Create or update a small generative overlay actor",
            access: .mutate,
            params: [
                Param(name: "id", type: "string", required: false, description: "Stable actor id; generated if omitted"),
                Param(name: "renderer", type: "string", required: false, description: "Renderer type; sprite is currently supported"),
                Param(name: "asset", type: "string", required: false, description: "Bundled sprite asset id"),
                Param(name: "state", type: "string", required: false, description: "Actor state or animation name"),
                Param(name: "name", type: "string", required: false, description: "Actor display name"),
                Param(name: "message", type: "string", required: false, description: "Attached message text"),
                Param(name: "targetApp", type: "string", required: false, description: "App name to activate when this actor is clicked"),
                Param(name: "targetBundleId", type: "string", required: false, description: "Bundle identifier to activate when this actor is clicked"),
                Param(name: "targetAppPath", type: "string", required: false, description: "Application bundle path to open when this actor is clicked"),
                Param(name: "scale", type: "double", required: false, description: "Actor scale multiplier"),
                Param(name: "labelHidden", type: "bool", required: false, description: "Hide the actor label/message"),
                Param(name: "closeOnActivate", type: "bool", required: false, description: "Remove the actor after activating its target app"),
                Param(name: "hudUrl", type: "string", required: false, description: "URL to render in a hover HUD web view"),
                Param(name: "hudHTML", type: "string", required: false, description: "Inline HTML to render in a hover HUD web view"),
                Param(name: "hudWidth", type: "double", required: false, description: "Hover HUD width"),
                Param(name: "hudHeight", type: "double", required: false, description: "Hover HUD height"),
                Param(name: "hudReadAccess", type: "string", required: false, description: "Local folder the file-backed HUD may read"),
                Param(name: "x", type: "double", required: false, description: "Screen-local x coordinate"),
                Param(name: "y", type: "double", required: false, description: "Screen-local y coordinate"),
                Param(name: "placement", type: "string", required: false, description: "top, bottom, center, cursor, or point"),
                Param(name: "style", type: "string", required: false, description: "info, success, warning, danger, or playful"),
                Param(name: "display", type: "int", required: false, description: "Display index; omit for all displays"),
                Param(name: "ttlMs", type: "int", required: false, description: "Time to live in milliseconds; omit or pass 0 for persistent"),
                Param(name: "opacity", type: "double", required: false, description: "Opacity 0-1"),
                Param(name: "zIndex", type: "int", required: false, description: "Layer ordering"),
                Param(name: "dismissible", type: "bool", required: false, description: "Whether click-away dismissal removes the actor; defaults false"),
            ],
            returns: .object(model: "OverlayLayer"),
            handler: { params in
                try Self.publishOverlayActor(params)
            }
        ))

        api.register(Endpoint(
            method: "overlay.actor.moveTo",
            description: "Move an overlay actor with app-owned easing",
            access: .mutate,
            params: [
                Param(name: "id", type: "string", required: true, description: "Actor id"),
                Param(name: "x", type: "double", required: true, description: "Target screen-local x coordinate"),
                Param(name: "y", type: "double", required: true, description: "Target screen-local y coordinate"),
                Param(name: "durationMs", type: "int", required: false, description: "Animation duration in milliseconds"),
                Param(name: "easing", type: "string", required: false, description: "linear, easeInOut, or spring"),
            ],
            returns: .ok,
            handler: { params in
                try Self.moveOverlayActor(params)
            }
        ))

        api.register(Endpoint(
            method: "overlay.actor.hud",
            description: "Attach, update, or clear a hover web HUD for an overlay actor",
            access: .mutate,
            params: [
                Param(name: "id", type: "string", required: true, description: "Actor id"),
                Param(name: "hudUrl", type: "string", required: false, description: "URL to render in the hover HUD web view"),
                Param(name: "hudHTML", type: "string", required: false, description: "Inline HTML to render in the hover HUD web view"),
                Param(name: "hudTitle", type: "string", required: false, description: "HUD title metadata"),
                Param(name: "hudWidth", type: "double", required: false, description: "HUD width"),
                Param(name: "hudHeight", type: "double", required: false, description: "HUD height"),
                Param(name: "hudReadAccess", type: "string", required: false, description: "Local folder the file-backed HUD may read"),
                Param(name: "clear", type: "bool", required: false, description: "Clear the actor HUD"),
            ],
            returns: .ok,
            handler: { params in
                try Self.setOverlayActorHUD(params)
            }
        ))

        api.register(Endpoint(
            method: "overlay.actor.visibility",
            description: "Show, hide, toggle, or inspect the persistent overlay actor layer",
            access: .mutate,
            params: [
                Param(name: "action", type: "string", required: false, description: "show, hide, toggle, or status"),
                Param(name: "visible", type: "bool", required: false, description: "Set actor layer visibility"),
                Param(name: "hidden", type: "bool", required: false, description: "Set actor layer hidden state"),
                Param(name: "feedback", type: "bool", required: false, description: "Show a short desktop feedback toast"),
            ],
            returns: .custom("Object with ok, visible, hidden, and actorCount"),
            handler: { params in
                try Self.setOverlayActorVisibility(params)
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
                Param(name: "refresh", type: "bool", required: false, description: "Explicitly refresh terminal tab metadata through terminal app scripting before synthesizing"),
            ],
            returns: .array(model: "TerminalInstance"),
            handler: { params in
                let pm = ProcessModel.shared
                DesktopModel.shared.forcePoll()
                TmuxModel.shared.poll()
                pm.poll()
                if !Thread.isMainThread {
                    DispatchQueue.main.sync {}
                }
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
            method: "window.resolve",
            description: "Resolve a window target and optional placement plan without moving anything",
            access: .read,
            params: [
                Param(name: "target", type: "object", required: false, description: "Target descriptor with kind wid, session, app, or frontmost"),
                Param(name: "wid", type: "uint32", required: false, description: "Window ID target"),
                Param(name: "session", type: "string", required: false, description: "Tmux session target"),
                Param(name: "app", type: "string", required: false, description: "App name target"),
                Param(name: "title", type: "string", required: false, description: "Optional title substring for app target"),
                Param(name: "placement", type: "object|string", required: false, description: "Optional placement to plan"),
                Param(name: "display", type: "int", required: false, description: "Optional display index"),
            ],
            returns: .custom("Resolved target plus optional placement plan"),
            handler: { params in
                try ActionRuntime.shared.resolveWindowPlace(params: params)
            }
        ))

        api.register(Endpoint(
            method: "actions.execute",
            description: "Execute a canonical action and return a structured receipt. Initially supports window.place.",
            access: .mutate,
            params: [
                Param(name: "type", type: "string", required: false, description: "Action type, e.g. window.place"),
                Param(name: "action", type: "object", required: false, description: "Single action object"),
                Param(name: "actions", type: "array<object>", required: false, description: "Batch of action objects"),
                Param(name: "target", type: "object", required: false, description: "Target descriptor for window.place"),
                Param(name: "args", type: "object", required: false, description: "Action args, including placement"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
                Param(name: "requestId", type: "string", required: false, description: "Caller-supplied request id"),
                Param(name: "dryRun", type: "bool", required: false, description: "Plan and resolve without moving windows"),
            ],
            returns: .custom("ActionReceipt for one action; batch receipt with receipts for actions[]"),
            handler: { params in
                try ActionRuntime.shared.execute(params: params)
            }
        ))

        api.register(Endpoint(
            method: "actions.history",
            description: "Return recent action execution receipts.",
            access: .read,
            params: [
                Param(name: "limit", type: "int", required: false, description: "Max receipts to return (default 20)"),
                Param(name: "type", type: "string", required: false, description: "Filter by action type"),
                Param(name: "source", type: "string", required: false, description: "Filter by source"),
                Param(name: "wid", type: "uint32", required: false, description: "Filter by window id"),
                Param(name: "requestId", type: "string", required: false, description: "Filter by request id"),
                Param(name: "session", type: "string", required: false, description: "Filter by tmux session"),
                Param(name: "status", type: "string", required: false, description: "Filter by receipt status"),
                Param(name: "undoable", type: "bool", required: false, description: "Filter to receipts that can or cannot be undone"),
            ],
            returns: .array(model: "ActionReceipt"),
            handler: { params in
                ActionRuntime.shared.history(params: params)
            }
        ))

        api.register(Endpoint(
            method: "actions.undo",
            description: "Restore the latest undoable window placement receipt, or a specific receipt/request group.",
            access: .mutate,
            params: [
                Param(name: "receiptId", type: "string", required: false, description: "Specific receipt to undo"),
                Param(name: "requestId", type: "string", required: false, description: "Specific request group to undo"),
                Param(name: "wid", type: "uint32", required: false, description: "Limit undo selection to one window id"),
                Param(name: "steps", type: "int", required: false, description: "Number of recent undoable groups to restore (default 1)"),
                Param(name: "force", type: "bool", required: false, description: "Restore even when the current frame no longer matches the receipt"),
                Param(name: "dryRun", type: "bool", required: false, description: "Plan the restore without moving windows"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
            ],
            returns: .custom("ActionReceipt for the undo operation"),
            handler: { params in
                try ActionRuntime.shared.undo(params: params)
            }
        ))

        api.register(Endpoint(
            method: "runs.create",
            description: "Create a local run record and artifact directory",
            access: .mutate,
            params: [
                Param(name: "title", type: "string", required: false, description: "Run title"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
                Param(name: "wid", type: "uint32", required: false, description: "Optional window surface to attach"),
            ],
            returns: .object(model: "RunSession"),
            handler: { params in
                let title = params?["title"]?.stringValue ?? "Manual run"
                let source = params?["source"]?.stringValue ?? "daemon"
                let surfaces: [RunSurface]
                if let wid = params?["wid"]?.uint32Value {
                    guard let window = DesktopModel.shared.windows[wid] else {
                        throw RouterError.notFound("window \(wid)")
                    }
                    surfaces = [.window(window)]
                } else {
                    surfaces = []
                }
                return try RunStore.shared.createRun(title: title, source: source, surfaces: surfaces).json
            }
        ))

        api.register(Endpoint(
            method: "runs.list",
            description: "List recent local runs",
            access: .read,
            params: [
                Param(name: "limit", type: "int", required: false, description: "Max runs to return (default 20)"),
            ],
            returns: .array(model: "RunSession"),
            handler: { params in
                let limit = params?["limit"]?.intValue ?? 20
                return .array(RunStore.shared.list(limit: limit).map(\.json))
            }
        ))

        api.register(Endpoint(
            method: "runs.get",
            description: "Inspect one local run, including artifacts and trace events",
            access: .read,
            params: [
                Param(name: "id", type: "string", required: true, description: "Run id"),
            ],
            returns: .object(model: "RunSession"),
            handler: { params in
                guard let id = params?["id"]?.stringValue, !id.isEmpty else {
                    throw RouterError.missingParam("id")
                }
                guard let run = RunStore.shared.get(id: id) else {
                    throw RouterError.notFound("run \(id)")
                }
                return run.json
            }
        ))

        api.register(Endpoint(
            method: "runs.artifacts",
            description: "List artifacts for one local run",
            access: .read,
            params: [
                Param(name: "id", type: "string", required: true, description: "Run id"),
            ],
            returns: .array(model: "RunArtifact"),
            handler: { params in
                guard let id = params?["id"]?.stringValue, !id.isEmpty else {
                    throw RouterError.missingParam("id")
                }
                guard let artifacts = RunStore.shared.artifacts(for: id) else {
                    throw RouterError.notFound("run \(id)")
                }
                return .array(artifacts.map(\.json))
            }
        ))

        api.register(Endpoint(
            method: "capture.screenshotWindow",
            description: "Capture a window screenshot as a run artifact. Defaults to the frontmost non-Lattices window.",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: false, description: "Target window id"),
                Param(name: "session", type: "string", required: false, description: "Target lattices session"),
                Param(name: "app", type: "string", required: false, description: "Target app name"),
                Param(name: "title", type: "string", required: false, description: "Optional title substring for app target, or run title when no app is provided"),
                Param(name: "runId", type: "string", required: false, description: "Existing run id to append to"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
                Param(name: "filename", type: "string", required: false, description: "Optional artifact filename"),
            ],
            returns: .custom("Object with ok, run, artifact, and target window"),
            handler: { params in
                try CaptureController.shared.screenshotWindow(params: params)
            }
        ))

        api.register(Endpoint(
            method: "capture.recordWindow",
            description: "Start recording a target window as a run artifact. Defaults to region capture so overlays and visible cursor cues are included.",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: false, description: "Target window id"),
                Param(name: "session", type: "string", required: false, description: "Target lattices session"),
                Param(name: "app", type: "string", required: false, description: "Target app name"),
                Param(name: "title", type: "string", required: false, description: "Optional title substring for app target, or run title when no app is provided"),
                Param(name: "mode", type: "string", required: false, description: "region (default, captures overlays) or app-window (captures only the app window)"),
                Param(name: "fps", type: "double", required: false, description: "Frames per second for region recording"),
                Param(name: "scale", type: "double", required: false, description: "Output scale for region recording"),
                Param(name: "filename", type: "string", required: false, description: "Optional .mov artifact filename"),
                Param(name: "runId", type: "string", required: false, description: "Existing run id to append to"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
            ],
            returns: .custom("Object with ok, run, recording artifact, stopFile, finishedFile, and debugLog"),
            handler: { params in
                try CaptureController.shared.recordWindow(params: params)
            }
        ))

        api.register(Endpoint(
            method: "capture.recordRegion",
            description: "Start recording a screen region as a run artifact. If no explicit region is supplied, resolves a window target and records its frame.",
            access: .mutate,
            params: [
                Param(name: "x", type: "double", required: false, description: "Region x in screen coordinates"),
                Param(name: "y", type: "double", required: false, description: "Region y in screen coordinates"),
                Param(name: "width", type: "double", required: false, description: "Region width"),
                Param(name: "height", type: "double", required: false, description: "Region height"),
                Param(name: "w", type: "double", required: false, description: "Alias for width"),
                Param(name: "h", type: "double", required: false, description: "Alias for height"),
                Param(name: "wid", type: "uint32", required: false, description: "Window id whose frame should be recorded when no explicit region is supplied"),
                Param(name: "app", type: "string", required: false, description: "App whose window frame should be recorded when no explicit region is supplied"),
                Param(name: "fps", type: "double", required: false, description: "Frames per second"),
                Param(name: "scale", type: "double", required: false, description: "Output scale"),
                Param(name: "filename", type: "string", required: false, description: "Optional .mov artifact filename"),
                Param(name: "runId", type: "string", required: false, description: "Existing run id to append to"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
            ],
            returns: .custom("Object with ok, run, recording artifact, stopFile, finishedFile, and debugLog"),
            handler: { params in
                try CaptureController.shared.recordRegion(params: params)
            }
        ))

        api.register(Endpoint(
            method: "capture.stopRecording",
            description: "Stop a recording started by capture.recordWindow or capture.recordRegion.",
            access: .mutate,
            params: [
                Param(name: "runId", type: "string", required: false, description: "Run id with a recording artifact"),
                Param(name: "id", type: "string", required: false, description: "Alias for runId"),
                Param(name: "stopFile", type: "string", required: false, description: "Stop signal file path when no run id is available"),
                Param(name: "finishedFile", type: "string", required: false, description: "Finished marker path"),
                Param(name: "wait", type: "bool", required: false, description: "Wait for finished marker (default true)"),
                Param(name: "timeoutMs", type: "int", required: false, description: "Timeout while waiting for finished marker"),
            ],
            returns: .custom("Object with ok, finished, marker, and optional completed run"),
            handler: { params in
                try CaptureController.shared.stopRecording(params: params)
            }
        ))

        api.register(Endpoint(
            method: "computer.prepare",
            description: "Resolve and optionally capture a computer-use target without mutating it.",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: false, description: "Specific terminal window id"),
                Param(name: "tty", type: "string", required: false, description: "Specific terminal TTY"),
                Param(name: "app", type: "string", required: false, description: "Preferred terminal app, such as iTerm2"),
                Param(name: "text", type: "string", required: false, description: "Optional text to stage"),
                Param(name: "treatment", type: "string", required: false, description: "observe, stage, present, or execute"),
                Param(name: "capture", type: "bool", required: false, description: "Capture target screenshot artifact (default true)"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
            ],
            returns: .custom("Object with ok, run, selected target, candidates, and optional artifacts"),
            handler: { params in
                try ComputerUseController.shared.prepare(params: params)
            }
        ))

        api.register(Endpoint(
            method: "computer.windowState",
            description: "Inspect a target window's Accessibility tree and return snapshot-local element ids.",
            access: .read,
            params: [
                Param(name: "wid", type: "uint32", required: false, description: "Target window id"),
                Param(name: "session", type: "string", required: false, description: "Target lattices session"),
                Param(name: "app", type: "string", required: false, description: "Target app name"),
                Param(name: "title", type: "string", required: false, description: "Optional title substring for app target"),
                Param(name: "mode", type: "string", required: false, description: "ax (default), both, or screenshot"),
                Param(name: "capture", type: "bool", required: false, description: "Capture a screenshot artifact; defaults true for both/screenshot and false for ax"),
                Param(name: "maxDepth", type: "int", required: false, description: "Maximum AX tree depth to traverse (default 8, max 14)"),
                Param(name: "maxElements", type: "int", required: false, description: "Maximum elements to return (default 250, max 1000)"),
                Param(name: "timeoutMs", type: "int", required: false, description: "Traversal timeout in milliseconds (default 1200, max 5000)"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label when capture creates a run"),
            ],
            returns: .object(model: "ComputerWindowState"),
            handler: { params in
                try ComputerUseController.shared.windowState(params: params)
            }
        ))

        api.register(Endpoint(
            method: "computer.focusWindow",
            description: "Resolve, optionally capture, focus, and verify a target window.",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: false, description: "Target window id"),
                Param(name: "session", type: "string", required: false, description: "Target lattices session"),
                Param(name: "app", type: "string", required: false, description: "Target app name"),
                Param(name: "title", type: "string", required: false, description: "Optional title substring for app target"),
                Param(name: "treatment", type: "string", required: false, description: "observe, stage, present, or execute"),
                Param(name: "dryRun", type: "bool", required: false, description: "Plan without focusing"),
                Param(name: "capture", type: "bool", required: false, description: "Capture before/after artifacts (default true)"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
            ],
            returns: .custom("Object with ok, run, target, focused, and optional artifacts"),
            handler: { params in
                try ComputerUseController.shared.focusWindow(params: params)
            }
        ))

        api.register(Endpoint(
            method: "computer.showCursor",
            description: "Resolve the cursor location and show a visible cursor appearance.",
            access: .mutate,
            params: [
                Param(name: "x", type: "double", required: false, description: "Screen x coordinate; defaults to current cursor"),
                Param(name: "y", type: "double", required: false, description: "Screen y coordinate; defaults to current cursor"),
                Param(name: "treatment", type: "string", required: false, description: "observe, stage, present, or execute"),
                Param(name: "style", type: "string", required: false, description: "spotlight, pulse, or marker"),
                Param(name: "appearance", type: "string", required: false, description: "Alias for style"),
                Param(name: "shape", type: "string", required: false, description: "Marker shape override: arrow, needle, petal, shard, chevron, facet, wedge, prism, notch, or kite; defaults to Settings"),
                Param(name: "angleDeg", type: "double", required: false, description: "Marker rotation override; defaults to Settings"),
                Param(name: "size", type: "string", required: false, description: "Marker size override: tiny, small, regular, or large; defaults to Settings"),
                Param(name: "color", type: "string", required: false, description: "pearl, mist, ash, graphite, white, green, amber, pink, red, or #RRGGBB"),
                Param(name: "durationMs", type: "int", required: false, description: "Appearance duration in milliseconds"),
                Param(name: "label", type: "string", required: false, description: "Optional marker label"),
                Param(name: "caption", type: "string", required: false, description: "Readable overlay caption for recordings; use auto for current selections"),
                Param(name: "captionTitle", type: "string", required: false, description: "Caption panel title"),
                Param(name: "captionBody", type: "string", required: false, description: "Caption panel body copy"),
                Param(name: "captionTags", type: "string", required: false, description: "Comma-separated caption tags, or omitted for current selection tags"),
                Param(name: "captionLeadMs", type: "double", required: false, description: "Delay before the cursor action begins, so the caption lands first"),
                Param(name: "captionSound", type: "string", required: false, description: "Caption cue sound: none, tick, click, engage, or chime"),
                Param(name: "captionPlacement", type: "string", required: false, description: "Caption placement: top-left, top-right, bottom-left, bottom-right, top-center, center, or near-cursor"),
                Param(name: "captionX", type: "double", required: false, description: "Absolute caption top-left x coordinate"),
                Param(name: "captionY", type: "double", required: false, description: "Absolute caption top-left y coordinate"),
                Param(name: "captionXRatio", type: "double", required: false, description: "Window-relative caption top-left x ratio"),
                Param(name: "captionYRatio", type: "double", required: false, description: "Window-relative caption top-left y ratio"),
                Param(name: "sound", type: "string", required: false, description: "Cursor motion cue sound: none, tick, click, engage, or chime"),
                Param(name: "glow", type: "string", required: false, description: "Marker glow treatment: none, soft, halo, or comet"),
                Param(name: "idle", type: "string", required: false, description: "Marker idle treatment: still, breathe, wiggle, orbit, hover, nod, drift, shimmer, blink, or tremble"),
                Param(name: "edge", type: "string", required: false, description: "Start/arrival accent: none, pulse, ripple, tick, reticle, blink, spark, underline, echo, scan, or pin"),
                Param(name: "dryRun", type: "bool", required: false, description: "Plan without showing"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
            ],
            returns: .custom("Object with ok, run, cursor, appearance, and shown"),
            handler: { params in
                try ComputerUseController.shared.showCursor(params: params)
            }
        ))

        api.register(Endpoint(
            method: "computer.magicCursor",
            description: "Animate a non-interactive overlay cursor to a target point and optionally set text through Accessibility without focusing the app.",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: false, description: "Target window id"),
                Param(name: "app", type: "string", required: false, description: "Target app name"),
                Param(name: "title", type: "string", required: false, description: "Optional title substring for app target"),
                Param(name: "text", type: "string", required: false, description: "Text to set through AX when treatment is execute"),
                Param(name: "append", type: "bool", required: false, description: "Append to the current editable value instead of replacing it"),
                Param(name: "x", type: "double", required: false, description: "Target x coordinate, or absolute AX target point"),
                Param(name: "y", type: "double", required: false, description: "Target y coordinate, or absolute AX target point"),
                Param(name: "xRatio", type: "double", required: false, description: "Window-relative target x ratio, 0 left to 1 right"),
                Param(name: "yRatio", type: "double", required: false, description: "Window-relative target y ratio, 0 top to 1 bottom"),
                Param(name: "fromX", type: "double", required: false, description: "Starting x coordinate for the ghost cursor path"),
                Param(name: "fromY", type: "double", required: false, description: "Starting y coordinate for the ghost cursor path"),
                Param(name: "fromXRatio", type: "double", required: false, description: "Window-relative starting x ratio"),
                Param(name: "fromYRatio", type: "double", required: false, description: "Window-relative starting y ratio"),
                Param(name: "treatment", type: "string", required: false, description: "observe, stage, present, or execute"),
                Param(name: "style", type: "string", required: false, description: "Defaults to marker for magic cursor paths"),
                Param(name: "shape", type: "string", required: false, description: "Marker shape override: arrow, needle, petal, shard, chevron, facet, wedge, prism, notch, or kite"),
                Param(name: "angleDeg", type: "double", required: false, description: "Marker rotation override"),
                Param(name: "size", type: "string", required: false, description: "Marker size override: tiny, small, regular, or large"),
                Param(name: "color", type: "string", required: false, description: "pearl, mist, ash, graphite, white, green, amber, pink, red, or #RRGGBB"),
                Param(name: "trail", type: "string", required: false, description: "Path treatment: thread, ribbon, spark, comet, route, or none"),
                Param(name: "motion", type: "string", required: false, description: "Velocity treatment: glide, snap, float, rush, crawl, accelerate, teleport, spring, magnet, or slingshot"),
                Param(name: "trajectory", type: "string", required: false, description: "Path trajectory: straight, soft, arc, swoop, or overshoot"),
                Param(name: "glow", type: "string", required: false, description: "Marker glow treatment: none, soft, halo, or comet"),
                Param(name: "idle", type: "string", required: false, description: "Marker idle treatment: still, breathe, wiggle, orbit, hover, nod, drift, shimmer, blink, or tremble"),
                Param(name: "edge", type: "string", required: false, description: "Start/arrival accent: none, pulse, ripple, tick, reticle, blink, spark, underline, echo, scan, or pin"),
                Param(name: "durationMs", type: "int", required: false, description: "Total overlay duration in milliseconds"),
                Param(name: "typewriter", type: "bool", required: false, description: "When setting AX text, reveal characters incrementally without keyboard events"),
                Param(name: "typeIntervalMs", type: "double", required: false, description: "Milliseconds between AX text updates for typewriter mode"),
                Param(name: "label", type: "string", required: false, description: "Optional marker label"),
                Param(name: "caption", type: "string", required: false, description: "Readable overlay caption for recordings; use auto for current selections"),
                Param(name: "captionTitle", type: "string", required: false, description: "Caption panel title"),
                Param(name: "captionBody", type: "string", required: false, description: "Caption panel body copy"),
                Param(name: "captionTags", type: "string", required: false, description: "Comma-separated caption tags, or omitted for current selection tags"),
                Param(name: "captionLeadMs", type: "double", required: false, description: "Delay before the cursor action begins, so the caption lands first"),
                Param(name: "captionSound", type: "string", required: false, description: "Caption cue sound: none, tick, click, engage, or chime"),
                Param(name: "captionPlacement", type: "string", required: false, description: "Caption placement: top-left, top-right, bottom-left, bottom-right, top-center, center, or near-cursor"),
                Param(name: "captionX", type: "double", required: false, description: "Absolute caption top-left x coordinate"),
                Param(name: "captionY", type: "double", required: false, description: "Absolute caption top-left y coordinate"),
                Param(name: "captionXRatio", type: "double", required: false, description: "Window-relative caption top-left x ratio"),
                Param(name: "captionYRatio", type: "double", required: false, description: "Window-relative caption top-left y ratio"),
                Param(name: "sound", type: "string", required: false, description: "Cursor motion cue sound: none, tick, click, engage, or chime"),
                Param(name: "dryRun", type: "bool", required: false, description: "Plan without showing or setting AX text"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
            ],
            returns: .custom("Object with ok, run, target, from/cursor points, appearance, transport, and optional AX insertion details"),
            handler: { params in
                try ComputerUseController.shared.magicCursor(params: params)
            }
        ))

        api.register(Endpoint(
            method: "computer.launchApp",
            description: "Launch or focus a normal macOS app and capture the resulting run artifact.",
            access: .mutate,
            params: [
                Param(name: "app", type: "string", required: true, description: "App name, such as Scout, Slack, or Notes"),
                Param(name: "bundleId", type: "string", required: false, description: "Bundle identifier fallback for precise app launch"),
                Param(name: "path", type: "string", required: false, description: "Explicit .app bundle path"),
                Param(name: "title", type: "string", required: false, description: "Optional title substring used to select the app window"),
                Param(name: "treatment", type: "string", required: false, description: "observe, stage, present, or execute"),
                Param(name: "dryRun", type: "bool", required: false, description: "Plan without launching"),
                Param(name: "capture", type: "bool", required: false, description: "Capture the launched app window (default true)"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
            ],
            returns: .custom("Object with ok, run, app, target window, and launch/focus flags"),
            handler: { params in
                try ComputerUseController.shared.launchApp(params: params)
            }
        ))

        api.register(Endpoint(
            method: "computer.typeWindowText",
            description: "Focus a normal app window and type or paste text into it, optionally after a window-relative click.",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: false, description: "Target window id"),
                Param(name: "app", type: "string", required: false, description: "Target app name"),
                Param(name: "title", type: "string", required: false, description: "Optional title substring for app target"),
                Param(name: "text", type: "string", required: true, description: "Text to insert"),
                Param(name: "enter", type: "bool", required: false, description: "Press Enter after typing (default false)"),
                Param(name: "send", type: "bool", required: false, description: "Alias for enter in chat-style demos"),
                Param(name: "x", type: "double", required: false, description: "Absolute click x coordinate before typing"),
                Param(name: "y", type: "double", required: false, description: "Absolute click y coordinate before typing"),
                Param(name: "xRatio", type: "double", required: false, description: "Window-relative click x ratio, 0 left to 1 right"),
                Param(name: "yRatio", type: "double", required: false, description: "Window-relative click y ratio, 0 top to 1 bottom"),
                Param(name: "treatment", type: "string", required: false, description: "observe, stage, present, or execute"),
                Param(name: "dryRun", type: "bool", required: false, description: "Stage without typing"),
                Param(name: "capture", type: "bool", required: false, description: "Capture before/after artifacts (default true)"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
            ],
            returns: .custom("Object with ok, run, target window, typed text, and artifacts"),
            handler: { params in
                try ComputerUseController.shared.typeWindowText(params: params)
            }
        ))

        api.register(Endpoint(
            method: "computer.click",
            description: "Stage or execute a click target. In auto/ax transport Lattices prefers AXPress without focusing or moving the hardware pointer.",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: false, description: "Target window id"),
                Param(name: "app", type: "string", required: false, description: "Target app name"),
                Param(name: "title", type: "string", required: false, description: "Optional title substring for app target"),
                Param(name: "x", type: "double", required: false, description: "Absolute click x coordinate"),
                Param(name: "y", type: "double", required: false, description: "Absolute click y coordinate"),
                Param(name: "xRatio", type: "double", required: false, description: "Window-relative click x ratio, 0 left to 1 right"),
                Param(name: "yRatio", type: "double", required: false, description: "Window-relative click y ratio, 0 top to 1 bottom"),
                Param(name: "button", type: "string", required: false, description: "left or right"),
                Param(name: "transport", type: "string", required: false, description: "auto, ax, or pointer. auto tries AXPress before pointer fallback"),
                Param(name: "axLabel", type: "string", required: false, description: "Optional AX title/description text to prefer, such as Send"),
                Param(name: "noFocus", type: "bool", required: false, description: "Require AX/no-focus execution; do not focus or use pointer fallback"),
                Param(name: "treatment", type: "string", required: false, description: "stage, present, or execute; execute is required to post the click"),
                Param(name: "dryRun", type: "bool", required: false, description: "Stage without clicking"),
                Param(name: "capture", type: "bool", required: false, description: "Capture before/after artifacts when targeting a window (default true)"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
            ],
            returns: .custom("Object with ok, run, cursor point, target window, and clicked flag"),
            handler: { params in
                try ComputerUseController.shared.click(params: params)
            }
        ))

        api.register(Endpoint(
            method: "computer.demoScout",
            description: "Warm up a Scout memo/demo recording run: launch/focus Scout, capture it, and optionally type a staged message.",
            access: .mutate,
            params: [
                Param(name: "app", type: "string", required: false, description: "Scout app name override (default Scout)"),
                Param(name: "title", type: "string", required: false, description: "Optional title substring for the Scout window"),
                Param(name: "text", type: "string", required: false, description: "Message draft to type when treatment is execute"),
                Param(name: "enter", type: "bool", required: false, description: "Press Enter after typing (default false)"),
                Param(name: "send", type: "bool", required: false, description: "Alias for enter"),
                Param(name: "click", type: "bool", required: false, description: "Click the likely composer area before typing"),
                Param(name: "xRatio", type: "double", required: false, description: "Composer click x ratio; default 0.5"),
                Param(name: "yRatio", type: "double", required: false, description: "Composer click y ratio; default 0.86 from top"),
                Param(name: "treatment", type: "string", required: false, description: "observe, stage, present, or execute"),
                Param(name: "dryRun", type: "bool", required: false, description: "Stage without launching/typing"),
                Param(name: "capture", type: "bool", required: false, description: "Capture before/after artifacts (default true)"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
            ],
            returns: .custom("Object with ok, run, Scout target, artifacts, and typed/clicked flags"),
            handler: { params in
                try ComputerUseController.shared.demoScout(params: params)
            }
        ))

        api.register(Endpoint(
            method: "computer.typeText",
            description: "Resolve a terminal target and insert text using the least intrusive available transport.",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: false, description: "Specific terminal window id"),
                Param(name: "tty", type: "string", required: false, description: "Specific terminal TTY"),
                Param(name: "app", type: "string", required: false, description: "Preferred terminal app, such as iTerm2"),
                Param(name: "text", type: "string", required: true, description: "Text to insert"),
                Param(name: "enter", type: "bool", required: false, description: "Press Enter after typing (default false)"),
                Param(name: "treatment", type: "string", required: false, description: "observe, stage, present, or execute"),
                Param(name: "transport", type: "string", required: false, description: "auto, tmux, or pasteboard"),
                Param(name: "dryRun", type: "bool", required: false, description: "Stage without typing"),
                Param(name: "capture", type: "bool", required: false, description: "Capture before/after artifacts (default true)"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
            ],
            returns: .custom("Object with ok, run, selected terminal, transport, and artifacts"),
            handler: { params in
                try ComputerUseController.shared.typeText(params: params)
            }
        ))

        api.register(Endpoint(
            method: "computer.demoTerminal",
            description: "Select a terminal, capture before/after screenshots, focus it, and insert bounded text without pressing Enter by default.",
            access: .mutate,
            params: [
                Param(name: "wid", type: "uint32", required: false, description: "Specific terminal window id"),
                Param(name: "tty", type: "string", required: false, description: "Specific terminal TTY"),
                Param(name: "app", type: "string", required: false, description: "Preferred terminal app, such as iTerm2"),
                Param(name: "text", type: "string", required: false, description: "Text to insert"),
                Param(name: "enter", type: "bool", required: false, description: "Press Enter after typing (default false)"),
                Param(name: "dryRun", type: "bool", required: false, description: "Plan and capture without typing"),
                Param(name: "source", type: "string", required: false, description: "Calling surface label"),
            ],
            returns: .custom("Object with ok, run, selected terminal, candidates, beforeArtifact, and afterArtifact"),
            handler: { params in
                try ComputerUseController.shared.demoTerminal(params: params)
            }
        ))

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
                    var obj: [String: JSON] = [
                        "ok": .bool(raised),
                        "wid": .int(Int(wid)),
                        "pid": .int(Int(entry.pid)),
                        "app": .string(entry.app),
                        "title": .string(entry.title),
                        "raised": .bool(raised),
                        "targetResolution": .string("wid"),
                    ]
                    if let session = entry.latticesSession {
                        obj["session"] = .string(session)
                        obj["latticesSession"] = .string(session)
                    }
                    return .object(obj)
                }
                guard let session = params?["session"]?.stringValue else {
                    throw RouterError.missingParam("session or wid")
                }

                if let entry = Self.windowEntry(forSession: session) {
                    var raised = false
                    if Thread.isMainThread {
                        raised = WindowTiler.focusWindow(wid: entry.wid, pid: entry.pid)
                    } else {
                        DispatchQueue.main.sync {
                            raised = WindowTiler.focusWindow(wid: entry.wid, pid: entry.pid)
                        }
                    }
                    return .object([
                        "ok": .bool(raised),
                        "wid": .int(Int(entry.wid)),
                        "pid": .int(Int(entry.pid)),
                        "app": .string(entry.app),
                        "title": .string(entry.title),
                        "session": .string(session),
                        "latticesSession": .string(entry.latticesSession ?? session),
                        "raised": .bool(raised),
                        "targetResolution": .string("session"),
                    ])
                }

                let terminal = Preferences.shared.terminal
                if let located = SessionWindowLocator.findWindow(session: session, terminal: terminal) {
                    var raised = false
                    if Thread.isMainThread {
                        raised = WindowTiler.focusWindow(wid: located.wid, pid: Int32(located.pid))
                    } else {
                        DispatchQueue.main.sync {
                            raised = WindowTiler.focusWindow(wid: located.wid, pid: Int32(located.pid))
                        }
                    }
                    var obj: [String: JSON] = [
                        "ok": .bool(raised),
                        "wid": .int(Int(located.wid)),
                        "pid": .int(Int(located.pid)),
                        "session": .string(session),
                        "raised": .bool(raised),
                        "targetResolution": .string("session-locator"),
                    ]
                    if let entry = DesktopModel.shared.windows[located.wid] {
                        obj["app"] = .string(entry.app)
                        obj["title"] = .string(entry.title)
                        if let latticesSession = entry.latticesSession {
                            obj["latticesSession"] = .string(latticesSession)
                        }
                    }
                    return .object(obj)
                }

                throw RouterError.notFound("window for session \(session)")
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
            description: "Distribute windows evenly in a grid, optionally filtered by app or type and constrained to a screen region",
            access: .mutate,
            params: [
                Param(name: "app", type: "string", required: false, description: "Filter to windows of this app (e.g. 'iTerm2')"),
                Param(name: "type", type: "string", required: false, description: "Filter to an app type (e.g. 'terminal', 'browser', 'editor')"),
                Param(name: "region", type: "string", required: false, description: "Constrain grid to a screen region (e.g. 'right', 'left', 'top-right'). Uses tile position names."),
            ],
            returns: .ok,
            handler: { params in
                var dict: [String: JSON] = [:]
                if case .object(let obj) = params {
                    dict = obj
                }
                // Explicit filters select the matching scope automatically.
                if dict["app"] != nil && dict["scope"] == nil {
                    dict["scope"] = .string("app")
                } else if dict["type"] != nil && dict["scope"] == nil {
                    dict["scope"] = .string("type")
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
                Param(name: "scope", type: "string", required: false, description: "Optimization scope: visible, active-app, active-type, app, type, or selection"),
                Param(name: "strategy", type: "string", required: false, description: "Optimization strategy: balanced or mosaic"),
                Param(name: "app", type: "string", required: false, description: "App name for app-scoped optimization"),
                Param(name: "type", type: "string", required: false, description: "App type for type-scoped optimization"),
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
                Param(name: "source", type: "string", required: false, description: "Source of the intent (e.g. 'hudson-voice', 'siri', 'cli')"),
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
            description: "Check voice runtime provider status",
            access: .read,
            params: [],
            returns: .custom("Provider status with name and listening state"),
            handler: { _ in
                let audio = AudioLayer.shared
                return .object([
                    "provider": .string(audio.providerName),
                    "available": .bool(audio.provider?.isAvailable ?? false),
                    "listening": .bool(audio.isListening),
                    "lastTranscript": audio.lastTranscript.map { .string($0) } ?? .null,
                    "assistantHandoffPrompt": audio.assistantHandoffPrompt.map { .string($0) } ?? .null,
                    "lastError": audio.provider?.lastErrorMessage.map { .string($0) } ?? .null
                ])
            }
        ))

        api.register(Endpoint(
            method: "voice.listen",
            description: "Start voice capture via the audio provider",
            access: .mutate,
            params: [],
            returns: .ok,
            handler: { _ in
                guard AudioLayer.shared.provider != nil else {
                    throw RouterError.custom("No audio provider available. Is the voice runtime available?")
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
            method: "assistant.preview",
            description: "Preview the hands-off assistant planner against a live or supplied desktop snapshot. This is a dry run: it returns the plan and never speaks, mutates chat state, or executes actions.",
            access: .read,
            params: [
                Param(name: "text", type: "string", required: true, description: "Transcript or instruction to preview"),
                Param(name: "snapshot", type: "object", required: false, description: "Synthetic desktop snapshot. If omitted, the current live desktop snapshot is used."),
                Param(name: "history", type: "array", required: false, description: "Optional [{ role, content }] assistant conversation history"),
                Param(name: "trace", type: "bool", required: false, description: "Write an opt-in JSONL trace to ~/.lattices/assistant-preview-debug.jsonl"),
            ],
            returns: .custom("{ ok, dryRun, transcript, snapshotSource, data: { actions, spoken, _meta }, preview }"),
            handler: { params in
                guard let text = params?["text"]?.stringValue, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw RouterError.missingParam("text")
                }

                var snapshotOverride: [String: Any]?
                if let snapshotJson = params?["snapshot"] {
                    guard case .object = snapshotJson else {
                        throw RouterError.custom("snapshot must be an object")
                    }
                    guard let snapshot = try AssistantPreviewPlanner.foundationObject(from: snapshotJson) as? [String: Any] else {
                        throw RouterError.custom("snapshot must be an object")
                    }
                    snapshotOverride = snapshot
                }

                var history: [[String: String]] = []
                if let historyJson = params?["history"] {
                    guard case .array(let rows) = historyJson else {
                        throw RouterError.custom("history must be an array")
                    }
                    history = try rows.compactMap { row in
                        guard case .object(let obj) = row else {
                            throw RouterError.custom("history entries must be objects")
                        }
                        guard let role = obj["role"]?.stringValue,
                              ["user", "assistant"].contains(role),
                              let content = obj["content"]?.stringValue,
                              !content.isEmpty else {
                            return nil
                        }
                        return ["role": role, "content": content]
                    }
                }

                return try AssistantPreviewPlanner.shared.preview(
                    transcript: text,
                    snapshotOverride: snapshotOverride,
                    history: history,
                    trace: params?["trace"]?.boolValue ?? false
                )
            }
        ))

        api.register(Endpoint(
            method: "voice.reconnect",
            description: "Re-probe the voice runtime. HudsonVoice opens a fresh session per capture, so there is no persistent socket to reconnect.",
            access: .mutate,
            params: [],
            returns: .custom("Voice runtime reachability: { ok, runtimeAvailable, runtimeHost, service, transport, endpoint, port, pid, capabilityPath }"),
            handler: { _ in
                #if LATTICES_VOICE && canImport(HudsonVoice)
                let runtime = HudsonVoiceRuntimeResolver.resolve(clientId: "lattices")
                return .object([
                    "ok": .bool(true),
                    "runtimeAvailable": .bool(runtime != nil),
                    "runtimeHost": .string(runtime?.source ?? "none"),
                    "service": .string("hudson-voice"),
                    "transport": .string("ws+json-rpc"),
                    "endpoint": runtime.map { .string($0.endpoint.url.absoluteString) } ?? .null,
                    "port": runtime.map { .int(Int($0.endpoint.port)) } ?? .null,
                    "pid": runtime?.pid.map { .int($0) } ?? .null,
                    "capabilityPath": runtime?.capabilityPath.map { .string($0) } ?? .null,
                    "requiresAuth": .bool(runtime?.authToken != nil),
                    "runtimeError": .null,
                    "note": .string("HudsonVoice is compiled in; Lattices uses HudsonVoice's Vox WebSocket contract for live sessions."),
                ])
                #else
                return .object([
                    "ok": .bool(true),
                    "runtimeAvailable": .bool(false),
                    "runtimeHost": .string("none"),
                    "service": .null,
                    "transport": .null,
                    "endpoint": .null,
                    "port": .null,
                    "pid": .null,
                    "capabilityPath": .null,
                    "runtimeError": .string("HudsonVoice is not compiled into this build."),
                    "note": .string("HudsonVoice is not compiled into this build."),
                ])
                #endif
            }
        ))

        api.register(Endpoint(
            method: "handsoff.run",
            description: "Run a transcript through the real hands-off LLM pipeline, silently and dry-run by default. Same code path voice uses. Optional `snapshot` override feeds the model a synthetic desktop. No actions are executed; no chat log or handsoff.jsonl pollution. Dev builds also write a rich trace to ~/.lattices/handsoff-debug.jsonl.",
            access: .read,
            params: [
                Param(name: "text", type: "string", required: true, description: "Transcript to process"),
                Param(name: "snapshot", type: "object", required: false, description: "Override snapshot. If omitted, the live buildSnapshot() is used."),
            ],
            returns: .custom("Worker response: { data: { actions, spoken, _meta }, ... }"),
            handler: { params in
                guard let text = params?["text"]?.stringValue, !text.isEmpty else {
                    throw RouterError.missingParam("text")
                }

                // Decode optional snapshot override (JSON.object → [String: Any])
                var snapshotOverride: [String: Any]? = nil
                if let snapshotJson = params?["snapshot"],
                   case .object = snapshotJson {
                    let data = try JSONEncoder().encode(snapshotJson)
                    if let any = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        snapshotOverride = any
                    }
                }

                let semaphore = DispatchSemaphore(value: 0)
                var workerResponse: [String: Any]?
                var rpcError: Error?

                HandsOffSession.shared.runRpc(
                    transcript: text,
                    snapshotOverride: snapshotOverride
                ) { result in
                    switch result {
                    case .success(let response): workerResponse = response
                    case .failure(let err): rpcError = err
                    }
                    semaphore.signal()
                }

                // Generous timeout — LLM turns can be several seconds.
                let timeout = DispatchTime.now() + .seconds(60)
                if semaphore.wait(timeout: timeout) == .timedOut {
                    throw RouterError.custom("handsoff.run: timed out waiting for worker")
                }

                if let rpcError { throw rpcError }
                guard let workerResponse else {
                    throw RouterError.custom("handsoff.run: empty response")
                }

                let data = try JSONSerialization.data(withJSONObject: workerResponse)
                return try JSONDecoder().decode(JSON.self, from: data)
            }
        ))

        // ── Meta endpoint ───────────────────────────────────────

        // ── Settings ────────────────────────────────────────────

        api.register(Endpoint(
            method: "settings.cursorAppearance.get",
            description: "Return the default cursor marker appearance settings",
            access: .read,
            params: [],
            returns: .custom("Object with shape, angleDeg, size, and supported settings options"),
            handler: { _ in
                Self.cursorAppearanceSettingsResponse()
            }
        ))

        api.register(Endpoint(
            method: "settings.cursorAppearance.set",
            description: "Update default cursor marker appearance settings",
            access: .mutate,
            params: [
                Param(name: "shape", type: "string", required: false, description: "Default marker shape: arrow, needle, petal, shard, chevron, facet, wedge, prism, notch, or kite"),
                Param(name: "angleDeg", type: "int", required: false, description: "Default marker rotation: -8 or -16"),
                Param(name: "size", type: "string", required: false, description: "Default marker size: tiny, small, regular, or large"),
            ],
            returns: .custom("Updated cursor marker settings"),
            handler: { params in
                try Self.updateCursorAppearanceSettings(params)
            }
        ))

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
            method: "mouse.shortcuts.get",
            description: "Return the live mouse shortcut config and backing file path",
            access: .read,
            params: [],
            returns: .custom("Mouse shortcut response: { ok, path, ruleCount, config }"),
            handler: { _ in
                try Self.mouseShortcutResponse(config: MouseShortcutStore.shared.currentConfig)
            }
        ))

        api.register(Endpoint(
            method: "mouse.shortcuts.reload",
            description: "Reload mouse shortcuts from ~/.lattices/mouse-shortcuts.json without restarting the app",
            access: .mutate,
            params: [],
            returns: .custom("Mouse shortcut response: { ok, path, ruleCount, config, reloaded }"),
            handler: { _ in
                let config = MouseShortcutStore.shared.reloadNow()
                return try Self.mouseShortcutResponse(config: config, extra: ["reloaded": .bool(true)])
            }
        ))

        api.register(Endpoint(
            method: "mouse.shortcuts.set",
            description: "Replace the mouse shortcut config, persist it, and activate it immediately",
            access: .mutate,
            params: [
                Param(name: "config", type: "object", required: true, description: "Full MouseShortcutConfig object; top-level config fields are also accepted"),
            ],
            returns: .custom("Mouse shortcut response: { ok, path, ruleCount, config, replaced }"),
            handler: { params in
                let config = try Self.decodeMouseShortcutConfig(from: params)
                try Self.validateMouseShortcutConfig(config)
                MouseShortcutStore.shared.replaceConfig(config)
                return try Self.mouseShortcutResponse(
                    config: MouseShortcutStore.shared.currentConfig,
                    extra: ["replaced": .bool(true)]
                )
            }
        ))

        api.register(Endpoint(
            method: "mouse.shortcuts.upsert",
            description: "Create or replace a single mouse shortcut rule, persist it, and activate it immediately",
            access: .mutate,
            params: [
                Param(name: "rule", type: "object", required: true, description: "MouseShortcutRule object; top-level rule fields are also accepted"),
            ],
            returns: .custom("MouseShortcutConfig plus { created, rule }"),
            handler: { params in
                let rule = try Self.decodeMouseShortcutRule(from: params)
                try Self.validateMouseShortcutRule(rule)
                let created = MouseShortcutStore.shared.upsertRule(rule)
                return try Self.mouseShortcutResponse(
                    config: MouseShortcutStore.shared.currentConfig,
                    extra: [
                        "created": .bool(created),
                        "rule": try Self.encodeJSON(rule),
                    ]
                )
            }
        ))

        api.register(Endpoint(
            method: "mouse.shortcuts.remove",
            description: "Remove a mouse shortcut rule by id, persist the config, and activate it immediately",
            access: .mutate,
            params: [
                Param(name: "id", type: "string", required: true, description: "MouseShortcutRule id"),
            ],
            returns: .custom("MouseShortcutConfig plus { removed, id }"),
            handler: { params in
                guard let params else {
                    throw RouterError.missingParam("id")
                }
                let id = try Self.requiredString(params, "id")
                let removed = MouseShortcutStore.shared.removeRule(id: id)
                return try Self.mouseShortcutResponse(
                    config: MouseShortcutStore.shared.currentConfig,
                    extra: [
                        "removed": .bool(removed),
                        "id": .string(id),
                    ]
                )
            }
        ))

        api.register(Endpoint(
            method: "mouse.shortcuts.restoreDefaults",
            description: "Restore the default mouse shortcut config and activate it immediately",
            access: .mutate,
            params: [],
            returns: .custom("Mouse shortcut response: { ok, path, ruleCount, config, restoredDefaults }"),
            handler: { _ in
                MouseShortcutStore.shared.restoreDefaults()
                return try Self.mouseShortcutResponse(
                    config: MouseShortcutStore.shared.currentConfig,
                    extra: ["restoredDefaults": .bool(true)]
                )
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
    static func publishOverlay(_ params: JSON?) throws -> JSON {
        guard let params else {
            throw RouterError.missingParam("kind")
        }
        guard let kind = params["kind"]?.stringValue?.lowercased(), !kind.isEmpty else {
            throw RouterError.missingParam("kind")
        }

        let id = params["id"]?.stringValue ?? "agent-\(UUID().uuidString)"
        let style = try parseOverlayStyle(params["style"]?.stringValue)
        let placement = try parseOverlayPlacement(params["placement"]?.stringValue)
        let screen = try parseOverlayScreen(params["display"]?.intValue)
        let point = parseOverlayPoint(params)
        let opacity = CGFloat(max(0.05, min(params["opacity"]?.numericDouble ?? 1.0, 1.0)))
        let zIndex = params["zIndex"]?.intValue ?? 500
        let ttlMs = params["ttlMs"]?.intValue ?? defaultOverlayTTL(for: kind)
        let expiresAt = ttlMs > 0 ? Date().addingTimeInterval(Double(ttlMs) / 1000.0) : nil
        let payload: ScreenOverlayPayload

        switch kind {
        case "toast":
            let text = try requiredString(params, "text")
            payload = .toast(ScreenOverlayTextPayload(
                text: text,
                detail: params["detail"]?.stringValue,
                point: point,
                placement: placement,
                style: style
            ))
        case "label":
            let text = try requiredString(params, "text")
            payload = .label(ScreenOverlayTextPayload(
                text: text,
                detail: params["detail"]?.stringValue,
                point: point,
                placement: placement == .top ? .point : placement,
                style: style
            ))
        case "highlight":
            guard let rect = parseOverlayRect(params) else {
                throw RouterError.custom("highlight requires x, y, w, and h")
            }
            payload = .highlight(ScreenOverlayHighlightPayload(
                rect: rect,
                label: params["text"]?.stringValue ?? params["label"]?.stringValue,
                style: style,
                cornerRadius: CGFloat(params["cornerRadius"]?.numericDouble ?? 10)
            ))
        case "pet":
            let glyph = params["glyph"]?.stringValue ?? "✦"
            payload = .pet(ScreenOverlayPetPayload(
                glyph: String(glyph.prefix(4)),
                petID: params["petId"]?.stringValue,
                state: params["state"]?.stringValue,
                name: params["name"]?.stringValue,
                message: params["message"]?.stringValue ?? params["text"]?.stringValue,
                targetApp: params["targetApp"]?.stringValue ?? params["app"]?.stringValue,
                targetBundleIdentifier: params["targetBundleId"]?.stringValue ?? params["bundleIdentifier"]?.stringValue,
                targetAppPath: params["targetAppPath"]?.stringValue,
                scale: CGFloat(max(0.55, min(params["scale"]?.numericDouble ?? 1.0, 1.35))),
                labelHidden: params["labelHidden"]?.boolValue ?? false,
                closeOnActivate: params["closeOnActivate"]?.boolValue ?? false,
                hud: try parseActorHUD(params),
                point: point,
                placement: placement,
                style: style,
                isDragging: false,
                dismissible: params["dismissible"]?.boolValue ?? true
            ))
        default:
            throw RouterError.custom("Unsupported overlay kind: \(kind)")
        }

        let layer = ScreenOverlayLayerSnapshot(
            id: ScreenOverlayLayerID(id),
            owner: .agentApi,
            screen: screen,
            zIndex: zIndex,
            opacity: opacity,
            payload: payload,
            expiresAt: expiresAt
        )

        runOnMain {
            ScreenOverlayCanvasController.shared.publishLayer(layer)
        }

        var result: [String: JSON] = [
            "id": .string(id),
            "kind": .string(kind),
            "owner": .string(ScreenOverlayOwner.agentApi.rawValue),
        ]
        if let expiresAt {
            result["expiresAt"] = .double(expiresAt.timeIntervalSince1970)
        }
        return .object(result)
    }

    static func clearOverlay(_ params: JSON?) throws -> JSON {
        let owner = try parseOverlayOwner(params?["owner"]?.stringValue)
        if let id = params?["id"]?.stringValue, !id.isEmpty {
            runOnMain {
                ScreenOverlayCanvasController.shared.removeLayer(id: ScreenOverlayLayerID(id))
            }
        } else {
            runOnMain {
                ScreenOverlayCanvasController.shared.removeLayers(owner: owner)
            }
        }
        return .object(["ok": .bool(true)])
    }

    static func publishOverlayActor(_ params: JSON?) throws -> JSON {
        guard let params else {
            throw RouterError.missingParam("id")
        }
        let id = params["id"]?.stringValue ?? "actor-\(UUID().uuidString)"
        let renderer = params["renderer"]?.stringValue?.lowercased() ?? "sprite"
        guard renderer == "sprite" || renderer == "pet" else {
            throw RouterError.custom("Unsupported overlay actor renderer: \(renderer)")
        }

        let style = try parseOverlayStyle(params["style"]?.stringValue)
        let point = parseOverlayPoint(params)
        let placement = try parseOverlayPlacement(params["placement"]?.stringValue ?? (point == nil ? "bottom" : "point"))
        let screen = try parseOverlayScreen(params["display"]?.intValue)
        let opacity = CGFloat(max(0.05, min(params["opacity"]?.numericDouble ?? 1.0, 1.0)))
        let zIndex = params["zIndex"]?.intValue ?? 520
        let ttlMs = params["ttlMs"]?.intValue ?? 0
        let expiresAt = ttlMs > 0 ? Date().addingTimeInterval(Double(ttlMs) / 1000.0) : nil
        let asset = params["asset"]?.stringValue ?? params["petId"]?.stringValue
        let message = params["message"]?.stringValue ?? params["text"]?.stringValue

        let layer = ScreenOverlayLayerSnapshot(
            id: ScreenOverlayLayerID(id),
            owner: .agentApi,
            screen: screen,
            zIndex: zIndex,
            opacity: opacity,
            payload: .pet(ScreenOverlayPetPayload(
                glyph: String((params["glyph"]?.stringValue ?? "✦").prefix(4)),
                petID: asset,
                state: params["state"]?.stringValue ?? "idle",
                name: params["name"]?.stringValue,
                message: message,
                targetApp: params["targetApp"]?.stringValue ?? params["app"]?.stringValue,
                targetBundleIdentifier: params["targetBundleId"]?.stringValue ?? params["bundleIdentifier"]?.stringValue,
                targetAppPath: params["targetAppPath"]?.stringValue,
                scale: CGFloat(max(0.55, min(params["scale"]?.numericDouble ?? 1.0, 1.35))),
                labelHidden: params["labelHidden"]?.boolValue ?? false,
                closeOnActivate: params["closeOnActivate"]?.boolValue ?? false,
                hud: try parseActorHUD(params),
                point: point,
                placement: placement,
                style: style,
                isDragging: false,
                dismissible: params["dismissible"]?.boolValue ?? false
            )),
            expiresAt: expiresAt
        )

        runOnMain {
            ScreenOverlayCanvasController.shared.publishLayer(layer)
        }

        var result: [String: JSON] = [
            "id": .string(id),
            "kind": .string("actor"),
            "owner": .string(ScreenOverlayOwner.agentApi.rawValue),
            "renderer": .string(renderer),
        ]
        if let expiresAt {
            result["expiresAt"] = .double(expiresAt.timeIntervalSince1970)
        }
        return .object(result)
    }

    static func moveOverlayActor(_ params: JSON?) throws -> JSON {
        guard let params else {
            throw RouterError.missingParam("id")
        }
        let id = try requiredString(params, "id")
        guard let x = params["x"]?.numericDouble else {
            throw RouterError.missingParam("x")
        }
        guard let y = params["y"]?.numericDouble else {
            throw RouterError.missingParam("y")
        }
        let durationMs = params["durationMs"]?.intValue ?? 700
        let easing = params["easing"]?.stringValue
        var moved = false
        runOnMain {
            moved = ScreenOverlayCanvasController.shared.moveLayer(
                id: ScreenOverlayLayerID(id),
                to: CGPoint(x: x, y: y),
                durationMs: durationMs,
                easing: easing
            )
        }
        guard moved else {
            throw RouterError.custom("Overlay actor not found or not movable: \(id)")
        }
        return .object([
            "ok": .bool(true),
            "id": .string(id),
            "x": .double(x),
            "y": .double(y),
        ])
    }

    static func setOverlayActorHUD(_ params: JSON?) throws -> JSON {
        guard let params else {
            throw RouterError.missingParam("id")
        }
        let id = try requiredString(params, "id")
        let hud = params["clear"]?.boolValue == true ? nil : try parseActorHUD(params, requireContent: true)
        var updated = false

        runOnMain {
            updated = ScreenOverlayCanvasController.shared.setActorHUD(id: ScreenOverlayLayerID(id), hud: hud)
        }
        guard updated else {
            throw RouterError.custom("Overlay actor not found or not HUD-capable: \(id)")
        }
        return .object(["ok": .bool(true), "id": .string(id), "hasHUD": .bool(hud?.hasContent == true)])
    }

    static func setOverlayActorVisibility(_ params: JSON?) throws -> JSON {
        let action = params?["action"]?.stringValue?.lowercased()
        let feedback = params?["feedback"]?.boolValue ?? true
        var snapshot = ScreenOverlayActorVisibilitySnapshot(hidden: false, actorCount: 0)

        runOnMain {
            let controller = ScreenOverlayCanvasController.shared
            if let visible = params?["visible"]?.boolValue {
                snapshot = controller.setAgentActorsHidden(!visible, showFeedback: feedback)
                return
            }
            if let hidden = params?["hidden"]?.boolValue {
                snapshot = controller.setAgentActorsHidden(hidden, showFeedback: feedback)
                return
            }

            switch action {
            case nil, "toggle":
                let current = controller.agentActorsVisibility()
                snapshot = controller.setAgentActorsHidden(!current.hidden, showFeedback: feedback)
            case "show", "on":
                snapshot = controller.setAgentActorsHidden(false, showFeedback: feedback)
            case "hide", "off":
                snapshot = controller.setAgentActorsHidden(true, showFeedback: feedback)
            case "status":
                snapshot = controller.agentActorsVisibility()
            default:
                snapshot = controller.agentActorsVisibility()
            }
        }

        if let action,
           !["toggle", "show", "on", "hide", "off", "status"].contains(action),
           params?["visible"]?.boolValue == nil,
           params?["hidden"]?.boolValue == nil {
            throw RouterError.custom("Unsupported actor visibility action: \(action)")
        }

        return .object([
            "ok": .bool(true),
            "visible": .bool(snapshot.visible),
            "hidden": .bool(snapshot.hidden),
            "actorCount": .int(snapshot.actorCount),
        ])
    }

    static func parseActorHUD(_ params: JSON, requireContent: Bool = false) throws -> ScreenOverlayActorHUD? {
        let url = params["hudUrl"]?.stringValue
            ?? params["hudURL"]?.stringValue
            ?? params["hud"]?.stringValue
        let html = params["hudHTML"]?.stringValue
            ?? params["hudHtml"]?.stringValue
        guard url?.isEmpty == false || html?.isEmpty == false else {
            if requireContent {
                throw RouterError.missingParam("hudUrl")
            }
            return nil
        }

        let width = CGFloat(max(220, min(params["hudWidth"]?.numericDouble ?? params["width"]?.numericDouble ?? 360, 720)))
        let height = CGFloat(max(140, min(params["hudHeight"]?.numericDouble ?? params["height"]?.numericDouble ?? 240, 560)))
        return ScreenOverlayActorHUD(
            url: url,
            html: html,
            title: params["hudTitle"]?.stringValue ?? params["title"]?.stringValue,
            width: width,
            height: height,
            readAccessPath: params["hudReadAccess"]?.stringValue
                ?? params["readAccess"]?.stringValue
        )
    }

    static func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    static func parseOverlayScreen(_ displayIndex: Int?) throws -> ScreenOverlayScreenTarget {
        guard let displayIndex else { return .all }
        guard displayIndex >= 0, displayIndex < NSScreen.screens.count else {
            throw RouterError.custom("Invalid display index: \(displayIndex)")
        }
        return .screen(id: ScreenOverlayCanvasController.screenID(for: NSScreen.screens[displayIndex]))
    }

    static func parseOverlayPoint(_ params: JSON) -> CGPoint? {
        guard let x = params["x"]?.numericDouble,
              let y = params["y"]?.numericDouble else { return nil }
        return CGPoint(x: x, y: y)
    }

    static func parseOverlayRect(_ params: JSON) -> CGRect? {
        guard let x = params["x"]?.numericDouble,
              let y = params["y"]?.numericDouble,
              let w = params["w"]?.numericDouble,
              let h = params["h"]?.numericDouble else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func parseOverlayPlacement(_ value: String?) throws -> ScreenOverlayPlacement {
        let raw = value?.lowercased() ?? ScreenOverlayPlacement.top.rawValue
        guard let placement = ScreenOverlayPlacement(rawValue: raw) else {
            throw RouterError.custom("Unsupported overlay placement: \(raw)")
        }
        return placement
    }

    static func parseOverlayStyle(_ value: String?) throws -> ScreenOverlayStyle {
        let raw = value?.lowercased() ?? ScreenOverlayStyle.info.rawValue
        guard let style = ScreenOverlayStyle(rawValue: raw) else {
            throw RouterError.custom("Unsupported overlay style: \(raw)")
        }
        return style
    }

    static func parseOverlayOwner(_ value: String?) throws -> ScreenOverlayOwner {
        let raw = value ?? ScreenOverlayOwner.agentApi.rawValue
        guard let owner = ScreenOverlayOwner(rawValue: raw) else {
            throw RouterError.custom("Unsupported overlay owner: \(raw)")
        }
        return owner
    }

    static func defaultOverlayTTL(for kind: String) -> Int {
        switch kind {
        case "highlight":
            return 2500
        case "pet":
            return 4200
        default:
            return 2800
        }
    }

    static func requiredString(_ params: JSON, _ key: String) throws -> String {
        guard let value = params[key]?.stringValue, !value.isEmpty else {
            throw RouterError.missingParam(key)
        }
        return value
    }

    static func decodeDeckActionRequest(from json: JSON?) throws -> DeckActionRequest {
        guard let json else {
            throw RouterError.missingParam("actionID")
        }
        guard case .object(var object) = json else {
            throw RouterError.custom("Invalid deck action request: params must be an object")
        }
        object["payload"] = object["payload"] ?? .object([:])
        let data = try JSONEncoder().encode(JSON.object(object))
        do {
            return try JSONDecoder().decode(DeckActionRequest.self, from: data)
        } catch {
            throw RouterError.custom("Invalid deck action request: \(error.localizedDescription)")
        }
    }

    static func encodeDeckValue<T: Encodable>(_ value: T) throws -> JSON {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSON.self, from: data)
    }

    static func encodeJSON<T: Encodable>(_ value: T) throws -> JSON {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSON.self, from: data)
    }

    static func decodeJSON<T: Decodable>(_ type: T.Type, from json: JSON, label: String) throws -> T {
        let data = try JSONEncoder().encode(json)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RouterError.custom("Invalid \(label): \(error.localizedDescription)")
        }
    }

    static func decodeMouseShortcutConfig(from json: JSON?) throws -> MouseShortcutConfig {
        guard let json else {
            throw RouterError.missingParam("config")
        }
        let configJSON = json["config"] ?? json
        return try decodeJSON(MouseShortcutConfig.self, from: configJSON, label: "mouse shortcut config")
    }

    static func decodeMouseShortcutRule(from json: JSON?) throws -> MouseShortcutRule {
        guard let json else {
            throw RouterError.missingParam("rule")
        }
        let ruleJSON = json["rule"] ?? json
        return try decodeJSON(MouseShortcutRule.self, from: ruleJSON, label: "mouse shortcut rule")
    }

    static func validateMouseShortcutConfig(_ config: MouseShortcutConfig) throws {
        guard config.version >= 1 else {
            throw RouterError.custom("Mouse shortcut config version must be >= 1")
        }
        var seen = Set<String>()
        for rule in config.rules {
            try validateMouseShortcutRule(rule)
            guard seen.insert(rule.id).inserted else {
                throw RouterError.custom("Duplicate mouse shortcut rule id: \(rule.id)")
            }
        }
    }

    static func validateMouseShortcutRule(_ rule: MouseShortcutRule) throws {
        let trimmedID = rule.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw RouterError.custom("Mouse shortcut rule id cannot be empty")
        }
        let actions = rule.effectiveActions
        guard !actions.isEmpty else {
            throw RouterError.custom("Mouse shortcut rule \(rule.id) must define at least one action")
        }
        for action in actions {
            switch action.type {
            case .shortcutSend:
                guard let shortcut = action.shortcut,
                      shortcut.key != nil || shortcut.keyCode != nil else {
                    throw RouterError.custom("shortcut.send action in \(rule.id) requires shortcut.key or shortcut.keyCode")
                }
            case .appActivate:
                guard let app = action.app?.trimmingCharacters(in: .whitespacesAndNewlines), !app.isEmpty else {
                    throw RouterError.custom("app.activate action in \(rule.id) requires app")
                }
            default:
                break
            }
        }
    }

    static func mouseShortcutResponse(config: MouseShortcutConfig, extra: [String: JSON] = [:]) throws -> JSON {
        var object: [String: JSON] = [
            "ok": .bool(true),
            "path": .string(MouseShortcutStore.shared.configURL.path),
            "ruleCount": .int(config.rules.count),
            "config": try encodeJSON(config),
        ]
        for (key, value) in extra {
            object[key] = value
        }
        return .object(object)
    }

    static func cursorAppearanceSettingsResponse() -> JSON {
        let prefs = Preferences.shared
        return .object([
            "ok": .bool(true),
            "shape": .string(prefs.cursorMarkerShape.rawValue),
            "angleDeg": .int(prefs.cursorMarkerAngleDeg),
            "size": .string(prefs.cursorMarkerSize.rawValue),
            "scale": .double(Double(prefs.cursorMarkerSize.scale)),
            "shapeOptions": .array(CursorMarkerShape.settingsOptions.map { shape in
                .object([
                    "id": .string(shape.rawValue),
                    "label": .string(shape.label),
                ])
            }),
            "angleOptions": .array([-8, -16].map { .int($0) }),
            "sizeOptions": .array(CursorMarkerSize.settingsOptions.map { size in
                .object([
                    "id": .string(size.rawValue),
                    "label": .string(size.label),
                    "scale": .double(Double(size.scale)),
                ])
            }),
        ])
    }

    static func updateCursorAppearanceSettings(_ params: JSON?) throws -> JSON {
        let rawShape = params?["shape"]?.stringValue
        let rawSize = params?["size"]?.stringValue
            ?? params?["markerSize"]?.stringValue
            ?? params?["cursorSize"]?.stringValue
        let rawAngle: Int?
        if let value = params?["angleDeg"]?.intValue {
            rawAngle = value
        } else if let value = params?["rotationDeg"]?.intValue {
            rawAngle = value
        } else if let value = params?["angle"]?.intValue {
            rawAngle = value
        } else if let value = params?["rotation"]?.intValue {
            rawAngle = value
        } else if let value = params?["angleDeg"]?.numericDouble {
            rawAngle = Int(value.rounded())
        } else if let value = params?["rotationDeg"]?.numericDouble {
            rawAngle = Int(value.rounded())
        } else {
            rawAngle = nil
        }

        let shape: CursorMarkerShape?
        if let rawShape, !rawShape.isEmpty {
            guard let parsed = CursorMarkerShape(rawValue: rawShape),
                  CursorMarkerShape.settingsOptions.contains(parsed) else {
                let options = CursorMarkerShape.settingsOptions.map(\.rawValue).joined(separator: ", ")
                throw RouterError.custom("Unsupported cursor marker shape: \(rawShape). Use \(options).")
            }
            shape = parsed
        } else {
            shape = nil
        }

        let size: CursorMarkerSize?
        if let rawSize, !rawSize.isEmpty {
            guard let parsed = CursorMarkerSize(rawValue: rawSize),
                  CursorMarkerSize.settingsOptions.contains(parsed) else {
                let options = CursorMarkerSize.settingsOptions.map(\.rawValue).joined(separator: ", ")
                throw RouterError.custom("Unsupported cursor marker size: \(rawSize). Use \(options).")
            }
            size = parsed
        } else if let rawScale = params?["scale"]?.numericDouble
                    ?? params?["markerScale"]?.numericDouble
                    ?? params?["cursorScale"]?.numericDouble {
            size = CursorMarkerSize.closest(to: rawScale)
        } else {
            size = nil
        }

        let apply = {
            let prefs = Preferences.shared
            if let shape {
                prefs.cursorMarkerShape = shape
            }
            if let rawAngle {
                prefs.cursorMarkerAngleDeg = Preferences.normalizedCursorMarkerAngle(rawAngle)
            }
            if let size {
                prefs.cursorMarkerSize = size
            }
        }

        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.sync(execute: apply)
        }

        return cursorAppearanceSettingsResponse()
    }

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
              !LatticesRuntime.isLatticesBundleIdentifier(app.bundleIdentifier) else {
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

    static func windowEntry(forSession session: String) -> WindowEntry? {
        if let entry = DesktopModel.shared.windowForSession(session) {
            return entry
        }

        return ProcessModel.shared.synthesizeTerminals()
            .first { $0.tmuxSession == session }
            .flatMap { instance in
                instance.windowId.flatMap { DesktopModel.shared.windows[$0] }
            }
    }

    static func executeWindowPlacement(params: JSON?) throws -> JSON {
        try ActionRuntime.shared.executeWindowPlace(params: params, source: "daemon")
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

    static func defaultSpaceName(for index: Int) -> String {
        if let layers = WorkspaceManager.shared.config?.layers,
           layers.indices.contains(index - 1) {
            return layers[index - 1].label
        }

        let defaults = ["main", "code", "chat", "review", "media", "notes", "ops", "admin", "scratch"]
        if defaults.indices.contains(index - 1) {
            return defaults[index - 1]
        }
        return "space \(index)"
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
        if params?["type"] != nil {
            return "type"
        }

        let scope = normalizeToken(params?["scope"]?.stringValue ?? "visible")
        switch scope {
        case "visible", "selection", "app", "type",
             "active-app", "frontmost-app", "current-app",
             "active-type", "frontmost-type", "current-type":
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

        case "type":
            guard let typeName = params?["type"]?.stringValue,
                  let appType = parseOptimizationAppType(typeName) else {
                trace.append(.string("missing or unknown type for type scope"))
                return []
            }
            trace.append(.string("filtered by type \(appType.rawValue)"))
            if let titleFilter {
                trace.append(.string("title contains \(titleFilter)"))
            }
            return dedupeWindows(visible.filter {
                AppTypeClassifier.matches($0.app, type: appType) &&
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

        case "active-type", "frontmost-type", "current-type":
            let activeApp = params?["app"]?.stringValue ?? frontmostOptimizableApp()
            guard let activeApp else {
                trace.append(.string("no active app available"))
                return []
            }
            let grouping = AppTypeClassifier.grouping(for: activeApp)
            trace.append(.string("resolved active type \(grouping.label) from \(activeApp)"))
            if let titleFilter {
                trace.append(.string("title contains \(titleFilter)"))
            }
            return dedupeWindows(visible.filter {
                AppTypeClassifier.matches($0.app, grouping: grouping) &&
                (titleFilter == nil || $0.title.localizedCaseInsensitiveContains(titleFilter!))
            })

        default:
            trace.append(.string("using visible window scope"))
            return dedupeWindows(visible)
        }
    }

    static func parseOptimizationAppType(_ raw: String) -> AppType? {
        let normalized = normalizeToken(raw)
        return AppType.allCases.first { $0.rawValue == normalized }
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
