import AppKit

// MARK: - Intent Engine

final class IntentEngine {
    static let shared = IntentEngine()

    private var intents: [String: IntentDef] = [:]
    private var intentOrder: [String] = []

    private init() {
        registerBuiltins()
    }

    func register(_ intent: IntentDef) {
        intents[intent.name] = intent
        if !intentOrder.contains(intent.name) {
            intentOrder.append(intent.name)
        }
    }

    func definitions() -> [IntentDef] {
        intentOrder.compactMap { intents[$0] }
    }

    // MARK: - Execution

    func execute(_ request: IntentRequest) throws -> JSON {
        // 1. Direct match by intent name
        if let def = intents[request.intent] {
            return try def.handler(request)
        }

        // 2. Fuzzy match by intent name (handle voice transcription typos)
        let normalized = request.intent.lowercased().replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        if let def = intents[normalized] {
            return try def.handler(request)
        }

        // 3. No match
        throw IntentError.unknownIntent(request.intent, available: Array(intents.keys).sorted())
    }

    // MARK: - Discovery

    func catalog() -> JSON {
        .array(intentOrder.compactMap { name in
            guard let def = intents[name] else { return nil }
            return .object([
                "intent": .string(def.name),
                "description": .string(def.description),
                "examples": .array(def.examples.map { .string($0) }),
                "slots": .array(def.slots.map { slot in
                    var obj: [String: JSON] = [
                        "name": .string(slot.name),
                        "type": .string(slot.type),
                        "required": .bool(slot.required),
                        "description": .string(slot.description),
                    ]
                    if let vals = slot.enumValues {
                        obj["values"] = .array(vals.map { .string($0) })
                    }
                    return .object(obj)
                })
            ])
        })
    }

    // MARK: - Built-in Intents

    /// Track recently tiled wids so batch operations (e.g. "tile iTerm left, iTerm right")
    /// don't pick the same window twice. Resets after 2 seconds.
    private static var recentlyTiledWids: Set<UInt32> = []
    private static var recentlyTiledTimer: Timer?

    private static func markTiled(_ wid: UInt32) {
        recentlyTiledWids.insert(wid)
        recentlyTiledTimer?.invalidate()
        recentlyTiledTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            recentlyTiledWids.removeAll()
        }
    }

    private func registerBuiltins() {

        // ── Window Tiling ───────────────────────────────────────

        register(IntentDef(
            name: "tile_window",
            description: "Tile a window to a screen position",
            examples: [
                "tile this left",
                "snap to the right half",
                "maximize the window",
                "put it in the top left corner",
                "center the window",
                "make it full screen"
            ],
            slots: [
                IntentSlot(name: "position", type: "position", required: true,
                           description: "Target tile position. Named positions or grid:CxR:C,R syntax.",
                           enumValues: TilePosition.allCases.map(\.rawValue)),
                IntentSlot(name: "app", type: "string", required: false,
                           description: "Target app name (defaults to frontmost)", enumValues: nil),
                IntentSlot(name: "wid", type: "int", required: false,
                           description: "Target window ID", enumValues: nil),
                IntentSlot(name: "session", type: "string", required: false,
                           description: "Target session name", enumValues: nil),
                IntentSlot(name: "selection", type: "bool", required: false,
                           description: "Apply to the active multi-window selection instead of a single window", enumValues: nil),
            ],
            handler: { req in
                guard let posStr = req.slots["position"]?.stringValue else {
                    throw IntentError.missingSlot("position")
                }
                guard let placement = PlacementSpec(string: posStr) else {
                    throw IntentError.invalidSlot("Unknown position: \(posStr)")
                }

                // Resolve target: explicit session, wid, app name, or frontmost
                if let session = req.slots["session"]?.stringValue {
                    return try LatticesApi.shared.dispatch(
                        method: "window.place",
                        params: .object(["session": .string(session), "placement": placement.jsonValue])
                    )
                }

                // For wid/app/frontmost: use WindowTiler directly
                func tileEntry(_ entry: WindowEntry) {
                    IntentEngine.markTiled(entry.wid)
                    DispatchQueue.main.async {
                        WindowTiler.tileWindowById(wid: entry.wid, pid: entry.pid, to: placement)
                    }
                }

                if let wid = req.slots["wid"]?.uint32Value,
                   let entry = DesktopModel.shared.windows[wid] {
                    tileEntry(entry)
                    return .object(["ok": .bool(true), "wid": .int(Int(wid)), "position": .string(posStr)])
                }

                if let app = req.slots["app"]?.stringValue {
                    // Skip windows already tiled in this batch (e.g. two iTerm windows side by side)
                    let alreadyTiled = IntentEngine.recentlyTiledWids
                    if let entry = DesktopModel.shared.windows.values.first(where: {
                        $0.app.localizedCaseInsensitiveContains(app) && !alreadyTiled.contains($0.wid)
                    }) {
                        tileEntry(entry)
                        return .object(["ok": .bool(true), "app": .string(entry.app), "wid": .int(Int(entry.wid)), "position": .string(posStr)])
                    }
                    throw IntentError.targetNotFound("No window found for app '\(app)'")
                }

                if req.slots["selection"]?.boolValue == true {
                    let selectionIds = WindowSelectionStore.shared.windowIds
                    guard !selectionIds.isEmpty else {
                        throw IntentError.targetNotFound("No active window selection")
                    }

                    if selectionIds.count == 1,
                       let wid = selectionIds.first,
                       let entry = DesktopModel.shared.windows[wid] {
                        tileEntry(entry)
                        return .object([
                            "ok": .bool(true),
                            "target": .string("selection"),
                            "wid": .int(Int(wid)),
                            "position": .string(posStr)
                        ])
                    }

                    return try LatticesApi.shared.dispatch(
                        method: "space.optimize",
                        params: .object([
                            "scope": .string("selection"),
                            "windowIds": .array(selectionIds.map { .int(Int($0)) }),
                            "region": .string(posStr)
                        ])
                    )
                }

                // Default: tile frontmost window
                DispatchQueue.main.async {
                    WindowTiler.tileFrontmostViaAX(to: placement)
                }
                return .object(["ok": .bool(true), "target": .string("frontmost"), "position": .string(posStr)])
            }
        ))

        // ── Focus Window / App ──────────────────────────────────

        register(IntentDef(
            name: "focus",
            description: "Focus a window, app, or session",
            examples: [
                "switch to Chrome",
                "focus the terminal",
                "go to my frontend project",
                "show Slack"
            ],
            slots: [
                IntentSlot(name: "app", type: "string", required: false,
                           description: "App name to focus", enumValues: nil),
                IntentSlot(name: "session", type: "string", required: false,
                           description: "Session name to focus", enumValues: nil),
                IntentSlot(name: "wid", type: "int", required: false,
                           description: "Window ID to focus", enumValues: nil),
            ],
            handler: { req in
                if let session = req.slots["session"]?.stringValue {
                    return try LatticesApi.shared.dispatch(
                        method: "window.focus",
                        params: .object(["session": .string(session)])
                    )
                }
                if let wid = req.slots["wid"]?.intValue {
                    return try LatticesApi.shared.dispatch(
                        method: "window.focus",
                        params: .object(["wid": .int(wid)])
                    )
                }
                if let app = req.slots["app"]?.stringValue {
                    if let entry = DesktopModel.shared.windows.values.first(where: {
                        $0.app.localizedCaseInsensitiveContains(app)
                    }) {
                        return try LatticesApi.shared.dispatch(
                            method: "window.focus",
                            params: .object(["wid": .int(Int(entry.wid))])
                        )
                    }
                    // Try launching the app
                    NSWorkspace.shared.launchApplication(app)
                    return .object(["ok": .bool(true), "launched": .string(app)])
                }
                throw IntentError.missingSlot("app, session, or wid")
            }
        ))

        // ── Launch Session ──────────────────────────────────────

        register(IntentDef(
            name: "launch",
            description: "Launch a project session",
            examples: [
                "open my frontend project",
                "launch the API",
                "start working on lattices",
                "open the backend"
            ],
            slots: [
                IntentSlot(name: "project", type: "string", required: true,
                           description: "Project name or path", enumValues: nil),
            ],
            handler: { req in
                guard let project = req.slots["project"]?.stringValue else {
                    throw IntentError.missingSlot("project")
                }

                // Try matching by name against discovered projects
                let projects = try LatticesApi.shared.dispatch(method: "projects.list", params: nil)
                if case .array(let list) = projects {
                    for p in list {
                        let name = p["name"]?.stringValue ?? ""
                        let path = p["path"]?.stringValue ?? ""
                        if name.localizedCaseInsensitiveContains(project) ||
                           path.localizedCaseInsensitiveContains(project) {
                            return try LatticesApi.shared.dispatch(
                                method: "session.launch",
                                params: .object(["path": .string(path)])
                            )
                        }
                    }
                }
                throw IntentError.targetNotFound("No project matching '\(project)'")
            }
        ))

        // ── Switch Layer ────────────────────────────────────────

        register(IntentDef(
            name: "switch_layer",
            description: "Switch to a workspace layer",
            examples: [
                "switch to the web layer",
                "go to mobile",
                "layer 2",
                "switch to review"
            ],
            slots: [
                IntentSlot(name: "layer", type: "string", required: true,
                           description: "Layer name or index", enumValues: nil),
            ],
            handler: { req in
                guard let layer = req.slots["layer"]?.stringValue else {
                    throw IntentError.missingSlot("layer")
                }

                // Try as index first
                if let index = Int(layer) {
                    // Try session layers first, then config layers
                    let session = SessionLayerStore.shared
                    if !session.layers.isEmpty && index < session.layers.count {
                        DispatchQueue.main.async { session.switchTo(index: index) }
                        return .object(["ok": .bool(true), "type": .string("session"), "index": .int(index)])
                    }
                    return try LatticesApi.shared.dispatch(
                        method: "layer.switch",
                        params: .object(["index": .int(index)])
                    )
                }

                // Try as name — session layers first
                let session = SessionLayerStore.shared
                if let idx = session.layers.firstIndex(where: {
                    $0.name.localizedCaseInsensitiveContains(layer)
                }) {
                    DispatchQueue.main.async { session.switchTo(index: idx) }
                    return .object(["ok": .bool(true), "type": .string("session"), "name": .string(session.layers[idx].name)])
                }

                // Then config layers
                return try LatticesApi.shared.dispatch(
                    method: "layer.switch",
                    params: .object(["name": .string(layer)])
                )
            }
        ))

        // ── Search Windows ─────────────────────────────────────

        register(IntentDef(
            name: "search",
            description: "Search for windows by app name, title, session, or screen text",
            examples: [
                "find the error message",
                "search for TODO",
                "find all terminal windows",
                "find chrome",
                "where does it say build failed",
                "look for port 3000"
            ],
            slots: [
                IntentSlot(name: "query", type: "query", required: true,
                           description: "Text to search for", enumValues: nil),
            ],
            handler: { req in
                return try SearchIntent().perform(slots: req.slots)
            }
        ))

        // ── List Windows ────────────────────────────────────────

        register(IntentDef(
            name: "list_windows",
            description: "List all visible windows",
            examples: [
                "what windows are open",
                "show me all windows",
                "what's on screen"
            ],
            slots: [],
            handler: { _ in
                try LatticesApi.shared.dispatch(method: "windows.list", params: nil)
            }
        ))

        // ── List Sessions ───────────────────────────────────────

        register(IntentDef(
            name: "list_sessions",
            description: "List active terminal sessions",
            examples: [
                "what sessions are running",
                "show my projects",
                "list sessions"
            ],
            slots: [],
            handler: { _ in
                try LatticesApi.shared.dispatch(method: "tmux.sessions", params: nil)
            }
        ))

        // ── Distribute Windows ──────────────────────────────────

        register(IntentDef(
            name: "distribute",
            description: "Distribute windows evenly in a grid, optionally filtered by app or window type and constrained to a screen region",
            examples: [
                "spread out the windows",
                "distribute everything",
                "organize the windows",
                "clean up the layout",
                "grid the terminals on the right",
                "tile all iTerm windows on the left half",
                "arrange my chrome windows in the bottom"
            ],
            slots: [
                IntentSlot(name: "app", type: "string", required: false,
                           description: "Filter to windows of this app (e.g. 'iTerm2', 'Google Chrome')", enumValues: nil),
                IntentSlot(name: "type", type: "string", required: false,
                           description: "Filter to a window type (e.g. 'terminal', 'browser', 'editor')",
                           enumValues: AppType.allCases.map(\.rawValue)),
                IntentSlot(name: "region", type: "position", required: false,
                           description: "Constrain the grid to a screen region. Uses tile position names.",
                           enumValues: ["left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right",
                                        "left-third", "center-third", "right-third"]),
                IntentSlot(name: "selection", type: "bool", required: false,
                           description: "Use the active selected windows instead of all visible windows", enumValues: nil),
            ],
            handler: { req in
                var params: [String: JSON] = [:]
                if let app = req.slots["app"]?.stringValue {
                    params["app"] = .string(app)
                }
                if let type = req.slots["type"]?.stringValue {
                    params["type"] = .string(type)
                }
                if let region = req.slots["region"]?.stringValue {
                    params["region"] = .string(region)
                }
                if req.slots["selection"]?.boolValue == true {
                    let selectionIds = WindowSelectionStore.shared.windowIds
                    guard !selectionIds.isEmpty else {
                        throw IntentError.targetNotFound("No active window selection")
                    }
                    params["scope"] = .string("selection")
                    params["windowIds"] = .array(selectionIds.map { .int(Int($0)) })
                    return try LatticesApi.shared.dispatch(
                        method: "space.optimize",
                        params: .object(params)
                    )
                }
                return try LatticesApi.shared.dispatch(
                    method: "layout.distribute",
                    params: params.isEmpty ? nil : .object(params)
                )
            }
        ))

        // ── Create Layer ────────────────────────────────────────

        register(IntentDef(
            name: "create_layer",
            description: "Create a new session layer from current windows",
            examples: [
                "save this layout as review",
                "create a layer called deploy",
                "make a new layer"
            ],
            slots: [
                IntentSlot(name: "name", type: "string", required: true,
                           description: "Name for the new layer", enumValues: nil),
                IntentSlot(name: "capture_visible", type: "bool", required: false,
                           description: "Auto-capture visible windows into the layer", enumValues: nil),
            ],
            handler: { req in
                guard let name = req.slots["name"]?.stringValue else {
                    throw IntentError.missingSlot("name")
                }

                var windowIds: [JSON] = []
                if req.slots["capture_visible"]?.boolValue == true {
                    for entry in DesktopModel.shared.windows.values where entry.isOnScreen {
                        windowIds.append(.int(Int(entry.wid)))
                    }
                }

                return try LatticesApi.shared.dispatch(
                    method: "session.layers.create",
                    params: .object([
                        "name": .string(name),
                        "windowIds": .array(windowIds)
                    ])
                )
            }
        ))

        // ── Kill Session ────────────────────────────────────────

        register(IntentDef(
            name: "kill",
            description: "Kill a terminal session",
            examples: [
                "stop the frontend session",
                "kill the API",
                "shut down that project"
            ],
            slots: [
                IntentSlot(name: "session", type: "string", required: true,
                           description: "Session name or project name", enumValues: nil),
            ],
            handler: { req in
                guard let session = req.slots["session"]?.stringValue else {
                    throw IntentError.missingSlot("session")
                }

                // Try direct name first
                let sessions = try LatticesApi.shared.dispatch(method: "tmux.sessions", params: nil)
                if case .array(let list) = sessions {
                    for s in list {
                        let name = s["name"]?.stringValue ?? ""
                        if name.localizedCaseInsensitiveContains(session) {
                            return try LatticesApi.shared.dispatch(
                                method: "session.kill",
                                params: .object(["name": .string(name)])
                            )
                        }
                    }
                }
                throw IntentError.targetNotFound("No session matching '\(session)'")
            }
        ))

        // ── Scan (trigger OCR) ──────────────────────────────────

        register(IntentDef(
            name: "scan",
            description: "Trigger an immediate screen text scan",
            examples: [
                "scan the screen",
                "read what's on screen",
                "update OCR"
            ],
            slots: [],
            handler: { _ in
                try LatticesApi.shared.dispatch(method: "ocr.scan", params: nil)
            }
        ))

        // ── Swap Windows ───────────────────────────────────────

        register(IntentDef(
            name: "swap",
            description: "Swap the positions of two windows",
            examples: [
                "swap Chrome and iTerm",
                "switch those two",
                "swap the left and right windows"
            ],
            slots: [
                IntentSlot(name: "wid_a", type: "int", required: true,
                           description: "Window ID of the first window", enumValues: nil),
                IntentSlot(name: "wid_b", type: "int", required: true,
                           description: "Window ID of the second window", enumValues: nil),
            ],
            handler: { req in
                guard let widA = req.slots["wid_a"]?.uint32Value,
                      let widB = req.slots["wid_b"]?.uint32Value else {
                    throw IntentError.missingSlot("wid_a and wid_b")
                }
                guard let entryA = DesktopModel.shared.windows[widA],
                      let entryB = DesktopModel.shared.windows[widB] else {
                    throw IntentError.targetNotFound("One or both windows not found")
                }

                // Read current CG frames (top-left origin) directly from CGWindowList
                guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
                    throw IntentError.targetNotFound("Couldn't read window list")
                }
                var cgFrames: [UInt32: CGRect] = [:]
                for info in windowList {
                    guard let num = info[kCGWindowNumber as String] as? UInt32,
                          (num == widA || num == widB),
                          let dict = info[kCGWindowBounds as String] as? NSDictionary else { continue }
                    var rect = CGRect.zero
                    if CGRectMakeWithDictionaryRepresentation(dict, &rect) {
                        cgFrames[num] = rect
                    }
                }
                guard let frameA = cgFrames[widA], let frameB = cgFrames[widB] else {
                    throw IntentError.targetNotFound("Couldn't read window frames")
                }

                // Swap: move A to B's frame, B to A's frame
                let moves: [(wid: UInt32, pid: Int32, frame: CGRect)] = [
                    (wid: widA, pid: entryA.pid, frame: frameB),
                    (wid: widB, pid: entryB.pid, frame: frameA),
                ]
                DispatchQueue.main.async {
                    WindowTiler.batchMoveAndRaiseWindows(moves)
                }
                return .object([
                    "ok": .bool(true),
                    "swapped": .array([.int(Int(widA)), .int(Int(widB))]),
                ])
            }
        ))

        // ── Hide / Minimize ────────────────────────────────────

        register(IntentDef(
            name: "hide",
            description: "Hide or minimize a window or app",
            examples: [
                "hide Slack",
                "minimize that",
                "put away Messages",
                "hide the browser"
            ],
            slots: [
                IntentSlot(name: "app", type: "string", required: false,
                           description: "App name to hide", enumValues: nil),
                IntentSlot(name: "wid", type: "int", required: false,
                           description: "Window ID to minimize", enumValues: nil),
            ],
            handler: { req in
                // Hide by wid — minimize just that window via AX
                if let wid = req.slots["wid"]?.uint32Value,
                   let entry = DesktopModel.shared.windows[wid] {
                    let appRef = AXUIElementCreateApplication(entry.pid)
                    var windowsRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                       let axWindows = windowsRef as? [AXUIElement] {
                        for axWin in axWindows {
                            var windowId: CGWindowID = 0
                            if _AXUIElementGetWindow(axWin, &windowId) == .success, windowId == wid {
                                AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                                return .object(["ok": .bool(true), "action": .string("minimized"), "wid": .int(Int(wid))])
                            }
                        }
                    }
                    throw IntentError.targetNotFound("Couldn't find AX window for wid \(wid)")
                }

                // Hide by app name — hide the entire app
                if let appName = req.slots["app"]?.stringValue {
                    let apps = NSWorkspace.shared.runningApplications
                    if let app = apps.first(where: {
                        ($0.localizedName ?? "").localizedCaseInsensitiveContains(appName)
                    }) {
                        app.hide()
                        return .object(["ok": .bool(true), "action": .string("hidden"), "app": .string(app.localizedName ?? appName)])
                    }
                    throw IntentError.targetNotFound("No running app matching '\(appName)'")
                }

                throw IntentError.missingSlot("app or wid")
            }
        ))

        // ── Highlight ──────────────────────────────────────────

        register(IntentDef(
            name: "highlight",
            description: "Flash a window's border to identify it visually",
            examples: [
                "which one is the lattices terminal",
                "highlight Chrome",
                "show me that window",
                "flash the iTerm window"
            ],
            slots: [
                IntentSlot(name: "wid", type: "int", required: false,
                           description: "Window ID to highlight", enumValues: nil),
                IntentSlot(name: "app", type: "string", required: false,
                           description: "App name to highlight", enumValues: nil),
            ],
            handler: { req in
                if let wid = req.slots["wid"]?.uint32Value {
                    DispatchQueue.main.async {
                        WindowTiler.highlightWindowById(wid: wid)
                    }
                    return .object(["ok": .bool(true), "wid": .int(Int(wid))])
                }

                if let appName = req.slots["app"]?.stringValue {
                    if let entry = DesktopModel.shared.windows.values.first(where: {
                        $0.app.localizedCaseInsensitiveContains(appName)
                    }) {
                        DispatchQueue.main.async {
                            WindowTiler.highlightWindowById(wid: entry.wid)
                        }
                        return .object(["ok": .bool(true), "wid": .int(Int(entry.wid)), "app": .string(entry.app)])
                    }
                    throw IntentError.targetNotFound("No window found for app '\(appName)'")
                }

                throw IntentError.missingSlot("wid or app")
            }
        ))

        // ── Move to Display ────────────────────────────────────

        register(IntentDef(
            name: "move_to_display",
            description: "Move a window to another monitor/display, optionally positioning it",
            examples: [
                "put this on the vertical monitor",
                "move Chrome to the second display",
                "send iTerm to the other screen",
                "move that to my main monitor"
            ],
            slots: [
                IntentSlot(name: "wid", type: "int", required: false,
                           description: "Window ID to move", enumValues: nil),
                IntentSlot(name: "app", type: "string", required: false,
                           description: "App name to move", enumValues: nil),
                IntentSlot(name: "display", type: "int", required: true,
                           description: "Target display index (0 = main, 1 = second, etc.)", enumValues: nil),
                IntentSlot(name: "position", type: "position", required: false,
                           description: "Tile position on the target display (e.g. 'left', 'maximize')",
                           enumValues: ["left", "right", "top", "bottom", "maximize", "center",
                                        "top-left", "top-right", "bottom-left", "bottom-right"]),
            ],
            handler: { req in
                guard let display = req.slots["display"]?.intValue else {
                    throw IntentError.missingSlot("display")
                }

                // Resolve window target
                let wid: UInt32
                if let w = req.slots["wid"]?.uint32Value {
                    wid = w
                } else if let appName = req.slots["app"]?.stringValue,
                          let entry = DesktopModel.shared.windows.values.first(where: {
                              $0.app.localizedCaseInsensitiveContains(appName)
                          }) {
                    wid = entry.wid
                } else {
                    // Frontmost window
                    guard let frontApp = NSWorkspace.shared.frontmostApplication,
                          frontApp.bundleIdentifier != "com.arach.lattices" else {
                        throw IntentError.targetNotFound("No frontmost window")
                    }
                    let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)
                    var focusedRef: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success else {
                        throw IntentError.targetNotFound("No focused window")
                    }
                    var frontWid: CGWindowID = 0
                    guard _AXUIElementGetWindow(focusedRef as! AXUIElement, &frontWid) == .success else {
                        throw IntentError.targetNotFound("Couldn't get frontmost window ID")
                    }
                    wid = frontWid
                }

                // Use window.present with display + optional position
                var params: [String: JSON] = [
                    "wid": .int(Int(wid)),
                    "display": .int(display),
                ]
                if let pos = req.slots["position"]?.stringValue {
                    params["position"] = .string(pos)
                }
                return try LatticesApi.shared.dispatch(method: "window.present", params: .object(params))
            }
        ))

        // ── Find / Summon Mouse ────────────────────────────────

        register(IntentDef(
            name: "find_mouse",
            description: "Show a sonar pulse at the current mouse cursor position",
            examples: [
                "where's my mouse",
                "find the cursor",
                "I lost my mouse",
                "find mouse",
                "show cursor"
            ],
            slots: [],
            handler: { _ in
                DispatchQueue.main.async { MouseFinder.shared.find() }
                let pos = NSEvent.mouseLocation
                return .object(["ok": .bool(true), "x": .int(Int(pos.x)), "y": .int(Int(pos.y))])
            }
        ))

        register(IntentDef(
            name: "summon_mouse",
            description: "Warp the mouse cursor to the center of the screen",
            examples: [
                "summon mouse",
                "bring the cursor here",
                "center the mouse",
                "mouse come here",
                "bring mouse back"
            ],
            slots: [],
            handler: { _ in
                DispatchQueue.main.async { MouseFinder.shared.summon() }
                return .object(["ok": .bool(true)])
            }
        ))

        // ── Undo / Restore ─────────────────────────────────────

        register(IntentDef(
            name: "undo",
            description: "Undo the last window move — restore windows to their previous positions",
            examples: [
                "put it back",
                "undo that",
                "restore the windows",
                "that was wrong, undo"
            ],
            slots: [],
            handler: { _ in
                let history = HandsOffSession.shared.frameHistory
                guard !history.isEmpty else {
                    throw IntentError.targetNotFound("No window moves to undo")
                }

                let restores = history.map { (wid: $0.wid, pid: $0.pid, frame: $0.frame) }
                DispatchQueue.main.async {
                    WindowTiler.batchRestoreWindows(restores)
                }
                HandsOffSession.shared.clearFrameHistory()
                return .object([
                    "ok": .bool(true),
                    "restored": .int(restores.count),
                ])
            }
        ))
    }
}

// MARK: - Errors

enum IntentError: LocalizedError {
    case unknownIntent(String, available: [String])
    case missingSlot(String)
    case invalidSlot(String)
    case targetNotFound(String)

    var errorDescription: String? {
        switch self {
        case .unknownIntent(let name, let available):
            return "Unknown intent '\(name)'. Available: \(available.joined(separator: ", "))"
        case .missingSlot(let name):
            return "Missing required slot: \(name)"
        case .invalidSlot(let detail):
            return detail
        case .targetNotFound(let detail):
            return detail
        }
    }
}

// MARK: - Claude CLI Fallback

struct ClaudeResolvedIntent {
    let intent: String
    let slots: [String: JSON]
}

struct ClaudeAgentPlan {
    let steps: [ClaudeResolvedIntent]
    let reasoning: String
}

enum ClaudeFallback {

    private static var claudePath: String? { Preferences.resolveClaudePath() }

    /// Shell out to Claude CLI to resolve a voice command transcript into an intent + slots.
    /// Runs synchronously — call from a background thread.
    static func resolve(
        transcript: String,
        windows: [WindowEntry],
        intentCatalog: JSON
    ) -> ClaudeResolvedIntent? {

        let timer = DiagnosticLog.shared.startTimed("Claude fallback")

        // Build window context (compact)
        // Compact window list — just app and title, max 20
        let windowList = windows.prefix(20).map { "\($0.app): \($0.title)" }.joined(separator: "\n")

        // Compact intent list — just name and slot names
        var intentList = ""
        if case .array(let intents) = intentCatalog {
            for intent in intents {
                let name = intent["intent"]?.stringValue ?? ""
                var slotNames: [String] = []
                if case .array(let slots) = intent["slots"] {
                    slotNames = slots.compactMap { $0["name"]?.stringValue }
                }
                let s = slotNames.isEmpty ? "" : "(\(slotNames.joined(separator: ",")))"
                intentList += "\(name)\(s), "
            }
        }

        let prompt = """
        Voice command resolver. Whisper transcript (may have typos): "\(transcript)"
        Intents: \(intentList.trimmingCharacters(in: .init(charactersIn: ", ")))
        Windows: \(windowList)
        Return ONLY a JSON object like {"intent":"search","slots":{"query":"dewey"},"reasoning":"user wants to find dewey windows"}. For search, extract the key term. Use window names from the list. If unclear, use intent "unknown".
        """

        guard let path = claudePath else {
            DiagnosticLog.shared.warn("ClaudeFallback: claude CLI not found")
            DiagnosticLog.shared.finish(timer)
            return nil
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)

        proc.arguments = [
            "-p", prompt,
            "--model", "haiku",
            "--output-format", "text",
            "--no-session-persistence",
            "--max-budget-usd", "0.50",
        ]

        // Clear CLAUDECODE env var to allow nested invocation
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        proc.environment = env

        let pipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            DiagnosticLog.shared.warn("ClaudeFallback: failed to launch claude CLI — \(error)")
            return nil
        }

        proc.waitUntilExit()
        let exitCode = proc.terminationStatus
        DiagnosticLog.shared.finish(timer)
        DiagnosticLog.shared.info("ClaudeFallback: exit code \(exitCode)")

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !errOutput.isEmpty {
            DiagnosticLog.shared.warn("ClaudeFallback: stderr → \(errOutput.prefix(200))")
        }
        DiagnosticLog.shared.info("ClaudeFallback: raw output → \(output.prefix(300))")

        // Parse JSON from text output
        guard let jsonStr = extractJSON(from: output),
              let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let intent = json["intent"] as? String,
              intent != "unknown" else {
            DiagnosticLog.shared.info("ClaudeFallback: couldn't parse response")
            return nil
        }

        if let reasoning = json["reasoning"] as? String {
            DiagnosticLog.shared.info("ClaudeFallback: reasoning → \(reasoning)")
        }

        // Convert slots
        var slots: [String: JSON] = [:]
        if let rawSlots = json["slots"] as? [String: Any] {
            for (key, value) in rawSlots {
                if let s = value as? String {
                    slots[key] = .string(s)
                } else if let n = value as? Int {
                    slots[key] = .int(n)
                } else if let b = value as? Bool {
                    slots[key] = .bool(b)
                }
            }
        }

        return ClaudeResolvedIntent(intent: intent, slots: slots)
    }

    private static func extractJSON(from text: String) -> String? {
        // Try to find JSON object in the response
        // Claude might return it directly, or wrapped in ```json ... ```
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Find first { and last }
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else { return nil }

        return String(cleaned[start...end])
    }
}
