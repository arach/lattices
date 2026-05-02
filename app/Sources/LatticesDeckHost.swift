import AppKit
import DeckKit
import Foundation

enum LatticesDeckHostError: LocalizedError {
    case unsupportedAction(String)
    case missingPayload(String)
    case invalidSwitcherItem(String)
    case noFrontmostWindow
    case invalidResizeDimension(String)
    case invalidResizeDirection(String)
    case noVisibleTargets(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedAction(let actionID):
            return "Unsupported deck action: \(actionID)"
        case .missingPayload(let name):
            return "Missing deck payload field: \(name)"
        case .invalidSwitcherItem(let itemID):
            return "Unknown switcher item: \(itemID)"
        case .noFrontmostWindow:
            return "There is no frontmost desktop window to control."
        case .invalidResizeDimension(let value):
            return "Unsupported resize dimension: \(value)"
        case .invalidResizeDirection(let value):
            return "Unsupported resize direction: \(value)"
        case .noVisibleTargets(let label):
            return "There are no visible \(label) to switch to right now."
        }
    }
}

final class LatticesDeckHost: DeckHost, @unchecked Sendable {
    static let shared = LatticesDeckHost()

    private let security: DeckSecurityConfiguration
    private let replayLock = NSLock()
    private var lastReplayMessage: String?
    private var lastReplayAt: Date?
    private var lastReplayUndoActionID: String?

    init(security: DeckSecurityConfiguration = .standaloneBonjour()) {
        self.security = security
    }

    var securityConfiguration: DeckSecurityConfiguration {
        security
    }

    func manifest() async throws -> DeckManifest {
        try manifestSync()
    }

    func runtimeSnapshot() async throws -> DeckRuntimeSnapshot {
        try runtimeSnapshotSync()
    }

    func perform(_ request: DeckActionRequest) async throws -> DeckActionResult {
        try performSync(request)
    }

    func manifestSync() throws -> DeckManifest {
        var capabilities: [DeckCapability] = [
            .trackpadProxy,
            .voiceAgent,
            .layoutControl,
            .appSwitching,
            .taskSwitching,
            .historyFeed,
            .systemTelemetry,
            .spaces,
            .keyboardForwarding,
            .activityLog,
            .cockpitModes,
            .transcriptStream,
        ]
        if security.mode == .embedded {
            capabilities.append(.embeddedSecurityDelegation)
        }

        return DeckManifest(
            product: DeckProductIdentity(
                id: "com.arach.lattices.companion",
                displayName: "Lattices Companion",
                owner: "lattices"
            ),
            security: security,
            capabilities: capabilities,
            pages: [
                DeckPage(
                    id: "command",
                    title: "Command",
                    iconSystemName: "circle.grid.2x2.fill",
                    kind: .cockpit,
                    accentToken: "lattices-cockpit",
                    deckID: "command"
                ),
                DeckPage(
                    id: "dev",
                    title: "Dev",
                    iconSystemName: "terminal.fill",
                    kind: .switch,
                    accentToken: "lattices-dev",
                    deckID: "dev"
                ),
                DeckPage(
                    id: "media",
                    title: "Media",
                    iconSystemName: "play.rectangle.fill",
                    kind: .custom,
                    accentToken: "lattices-media",
                    deckID: "media"
                ),
                DeckPage(
                    id: "windows",
                    title: "Windows",
                    iconSystemName: "rectangle.3.group.fill",
                    kind: .layout,
                    accentToken: "lattices-layout",
                    deckID: "windows"
                ),
                DeckPage(
                    id: "voice",
                    title: "Voice",
                    iconSystemName: "waveform.badge.mic",
                    kind: .voice,
                    accentToken: "lattices-voice",
                    deckID: "voice"
                ),
            ]
        )
    }

    func runtimeSnapshotSync() throws -> DeckRuntimeSnapshot {
        try MainActorSync.run { self.snapshotOnMainActor() }
    }

    func performSync(_ request: DeckActionRequest) throws -> DeckActionResult {
        let outcome = try handle(request)
        recordAction(request: request, outcome: outcome)
        flushMainQueue()
        let snapshot = try runtimeSnapshotSync()

        return DeckActionResult(
            ok: true,
            summary: outcome.summary,
            detail: outcome.detail,
            runtimeSnapshot: snapshot,
            suggestedActions: outcome.suggestedActions
        )
    }
}

private extension LatticesDeckHost {
    enum ResizeDimension: String {
        case width
        case height
        case both

        init(requestValue: String) throws {
            switch requestValue.lowercased() {
            case "width":
                self = .width
            case "height":
                self = .height
            case "both", "size":
                self = .both
            default:
                throw LatticesDeckHostError.invalidResizeDimension(requestValue)
            }
        }
    }

    enum ResizeDirection: String {
        case grow
        case shrink

        init(requestValue: String) throws {
            switch requestValue.lowercased() {
            case "grow", "increase", "expand":
                self = .grow
            case "shrink", "decrease", "reduce":
                self = .shrink
            default:
                throw LatticesDeckHostError.invalidResizeDirection(requestValue)
            }
        }
    }

    struct ActionOutcome {
        let summary: String
        let detail: String?
        let suggestedActions: [DeckSuggestedAction]
    }

    func handle(_ request: DeckActionRequest) throws -> ActionOutcome {
        switch request.actionID {
        case "voice.toggle":
            try MainActorSync.run {
                HandsOffSession.shared.toggle()
            }
            return try voiceOutcome()

        case "voice.cancel":
            try MainActorSync.run {
                HandsOffSession.shared.cancel()
            }
            return ActionOutcome(
                summary: "Stopped voice control",
                detail: "Cancelled the active hands-off voice turn.",
                suggestedActions: voiceSuggestions(for: .idle)
            )

        // Single-shot voice command path (transcribe → match intent → execute).
        // Distinct from voice.toggle / voice.cancel which drive the chat-style
        // HandsOffSession. Lives here so the iPad companion can fire dictation
        // on the active Mac via the existing /deck/perform bridge.
        case "voice.command.start":
            try MainActorSync.run {
                AudioLayer.shared.startVoiceCommand()
            }
            return try voiceOutcome()

        case "voice.command.stop":
            try MainActorSync.run {
                AudioLayer.shared.stopVoiceCommand()
            }
            return try voiceOutcome()

        case "voice.command.toggle":
            try MainActorSync.run {
                if AudioLayer.shared.isListening {
                    AudioLayer.shared.stopVoiceCommand()
                } else {
                    AudioLayer.shared.startVoiceCommand()
                }
            }
            return try voiceOutcome()

        case "switch.cycleApplication":
            return try cycleApplication(direction: request.payload["direction"]?.stringValue ?? "next")

        case "switch.cycleWindow":
            return try cycleWindow(direction: request.payload["direction"]?.stringValue ?? "next")

        case "layout.activateLayer":
            var params: [String: JSON] = [:]
            if let index = request.payload["index"]?.intValue {
                params["index"] = .int(index)
            }
            if let name = request.payload["name"]?.stringValue {
                params["name"] = .string(name)
            }
            params["mode"] = .string(request.payload["mode"]?.stringValue ?? "launch")
            let result = try callAPI("layer.activate", params: params)
            let label = result["label"]?.stringValue ?? params["name"]?.stringValue ?? "layer"
            return ActionOutcome(
                summary: "Activated \(label)",
                detail: "Focused the requested workspace layer.",
                suggestedActions: [
                    DeckSuggestedAction(
                        id: "layout.optimize",
                        title: "Retile Visible Windows",
                        iconSystemName: "rectangle.3.group"
                    )
                ]
            )

        case "layout.optimize":
            try MainActorSync.run {
                let wids = DesktopModel.shared.allWindows()
                    .filter { $0.isOnScreen && $0.app != "Lattices" }
                    .map(\.wid)
                HandsOffSession.shared.snapshotFrames(wids: wids)
            }
            var params: [String: JSON] = [:]
            if let scope = request.payload["scope"]?.stringValue {
                params["scope"] = .string(scope)
            }
            if let strategy = request.payload["strategy"]?.stringValue {
                params["strategy"] = .string(strategy)
            }
            if let region = request.payload["region"]?.stringValue {
                params["region"] = .string(region)
            }
            if let app = request.payload["app"]?.stringValue {
                params["app"] = .string(app)
            }
            if let type = request.payload["type"]?.stringValue {
                params["type"] = .string(type)
            }
            let result = try callAPI("space.optimize", params: params)
            let count = result["windowCount"]?.intValue ?? 0
            return ActionOutcome(
                summary: count > 0 ? "Optimized \(count) windows" : "Nothing needed rearranging",
                detail: "Applied the current layout strategy to the visible workspace.",
                suggestedActions: []
            )

        case "layout.placeFrontmost":
            guard let placement = request.payload["placement"]?.stringValue else {
                throw LatticesDeckHostError.missingPayload("placement")
            }
            try MainActorSync.run {
                if let frontmost = self.currentFrontmostWindow(
                    from: DesktopModel.shared.allWindows().filter(\.isOnScreen)
                ) {
                    HandsOffSession.shared.snapshotFrames(wids: [frontmost.wid])
                }
            }
            _ = try callAPI("window.place", params: [
                "placement": .string(placement)
            ])
            return ActionOutcome(
                summary: "Placed the frontmost window",
                detail: "Applied the \(placement) placement to the current frontmost target.",
                suggestedActions: []
            )

        case "layout.resizeFrontmost":
            let dimension = try ResizeDimension(requestValue: request.payload["dimension"]?.stringValue ?? "both")
            let direction = try ResizeDirection(requestValue: request.payload["direction"]?.stringValue ?? "grow")
            return try resizeFrontmostWindow(dimension: dimension, direction: direction)

        case "switch.focusItem":
            guard let itemID = request.payload["itemID"]?.stringValue else {
                throw LatticesDeckHostError.missingPayload("itemID")
            }
            return try focusSwitcherItem(itemID)

        case "history.undoLast":
            _ = try callAPI("intents.execute", params: [
                "intent": .string("undo")
            ])
            return ActionOutcome(
                summary: "Undid the last window move",
                detail: "Restored the most recent saved window frames.",
                suggestedActions: []
            )

        case "keys.send", "key.send":
            guard let key = request.payload["key"]?.stringValue else {
                throw LatticesDeckHostError.missingPayload("key")
            }
            let modifiers = request.payload["modifiers"]?.arrayValue?.compactMap(\.stringValue) ?? []
            DiagnosticLog.shared.info("DeckHost keys.send: key=\(key) modifiers=\(modifiers)")

            // Ctrl+Left / Ctrl+Right: macOS filters synthesized Mission Control hot keys at
            // .cghidEventTap, so route directly to the SkyLight space switcher instead.
            if let direction = spaceSwitchDirection(key: key, modifiers: modifiers) {
                DiagnosticLog.shared.info("DeckHost keys.send → spaces.switchActive direction=\(direction)")
                return try MainActorSync.run { self.switchActiveSpace(direction: direction) }
            }

            let sent = try CompanionKeyboardController.shared.send(key: key, modifiers: modifiers)
            return ActionOutcome(
                summary: "Sent \(sent)",
                detail: "Forwarded the key chord to the active macOS application.",
                suggestedActions: []
            )

        case "spaces.focusRelative":
            let direction = request.payload["direction"]?.intValue ?? 1
            return try MainActorSync.run { self.switchActiveSpace(direction: direction > 0 ? 1 : -1) }

        case "mouse.find":
            let result = try callAPI("mouse.find")
            let x = result["x"]?.intValue ?? 0
            let y = result["y"]?.intValue ?? 0
            return ActionOutcome(
                summary: "Located the mouse",
                detail: "Pulsed the cursor near \(x), \(y).",
                suggestedActions: []
            )

        case "mouse.summon":
            let result = try callAPI("mouse.summon")
            let x = result["x"]?.intValue ?? 0
            let y = result["y"]?.intValue ?? 0
            return ActionOutcome(
                summary: "Summoned the mouse",
                detail: "Moved the cursor toward \(x), \(y).",
                suggestedActions: []
            )

        default:
            throw LatticesDeckHostError.unsupportedAction(request.actionID)
        }
    }

    func voiceOutcome() throws -> ActionOutcome {
        let phase = try MainActorSync.run { self.currentVoicePhase() }
        let summary: String
        let detail: String

        switch phase {
        case .listening:
            summary = "Voice control is listening"
            detail = "The hands-off voice session is capturing your next instruction."
        case .reasoning:
            summary = "Voice control is working"
            detail = "The hands-off voice session is resolving your last request."
        default:
            summary = "Voice control is idle"
            detail = "The hands-off voice session is ready for the next command."
        }

        return ActionOutcome(
            summary: summary,
            detail: detail,
            suggestedActions: voiceSuggestions(for: phase)
        )
    }

    func focusSwitcherItem(_ itemID: String) throws -> ActionOutcome {
        if let raw = itemID.stripPrefix("window:"), let wid = UInt32(raw) {
            let entry = try MainActorSync.run {
                guard let window = DesktopModel.shared.windows[wid] else {
                    throw LatticesDeckHostError.invalidSwitcherItem(itemID)
                }
                return window
            }
            _ = try callAPI("window.focus", params: ["wid": .int(Int(wid))])
            return ActionOutcome(
                summary: "Focused \(entry.app)",
                detail: entry.title.isEmpty ? "Brought the selected window to the front." : entry.title,
                suggestedActions: []
            )
        }

        if let session = itemID.stripPrefix("session:") {
            _ = try callAPI("window.focus", params: ["session": .string(session)])
            return ActionOutcome(
                summary: "Focused \(session)",
                detail: "Raised the tmux session window.",
                suggestedActions: []
            )
        }

        if let appName = itemID.stripPrefix("app:") {
            let entry = try MainActorSync.run {
                guard let window = DesktopModel.shared.windowForApp(app: appName, title: nil) else {
                    throw LatticesDeckHostError.invalidSwitcherItem(itemID)
                }
                return window
            }
            _ = try callAPI("window.focus", params: ["wid": .int(Int(entry.wid))])
            return ActionOutcome(
                summary: "Focused \(entry.app)",
                detail: entry.title.isEmpty ? "Brought the app's active window forward." : entry.title,
                suggestedActions: []
            )
        }

        if let raw = itemID.stripPrefix("workspace-layer:"), let index = Int(raw) {
            let result = try callAPI("layer.activate", params: [
                "index": .int(index),
                "mode": .string("focus")
            ])
            let label = result["label"]?.stringValue ?? "layer"
            return ActionOutcome(
                summary: "Switched to \(label)",
                detail: "Focused the workspace layer's windows.",
                suggestedActions: []
            )
        }

        if let layerID = itemID.stripPrefix("session-layer:") {
            let layerName = try MainActorSync.run {
                guard let layer = SessionLayerStore.shared.layerById(layerID) else {
                    throw LatticesDeckHostError.invalidSwitcherItem(itemID)
                }
                return layer.name
            }
            _ = try callAPI("session.layers.switch", params: [
                "name": .string(layerName)
            ])
            return ActionOutcome(
                summary: "Switched to \(layerName)",
                detail: "Raised the tagged windows for that session layer.",
                suggestedActions: []
            )
        }

        throw LatticesDeckHostError.invalidSwitcherItem(itemID)
    }

    func callAPI(_ method: String, params: [String: JSON] = [:]) throws -> JSON {
        try LatticesApi.shared.dispatch(
            method: method,
            params: params.isEmpty ? nil : .object(params)
        )
    }

    func resizeFrontmostWindow(
        dimension: ResizeDimension,
        direction: ResizeDirection
    ) throws -> ActionOutcome {
        let resolved = try MainActorSync.run {
            try self.resizeFrontmostWindowOnMainActor(
                dimension: dimension,
                direction: direction
            )
        }

        try MainActorSync.run {
            HandsOffSession.shared.snapshotFrames(wids: [resolved.entry.wid])
        }

        _ = try callAPI("window.present", params: [
            "wid": .int(Int(resolved.entry.wid)),
            "x": .int(Int(resolved.frame.origin.x.rounded())),
            "y": .int(Int(resolved.frame.origin.y.rounded())),
            "w": .int(Int(resolved.frame.width.rounded())),
            "h": .int(Int(resolved.frame.height.rounded())),
        ])

        let summary: String
        switch (direction, dimension) {
        case (.grow, .width):
            summary = "Made \(resolved.entry.app) wider"
        case (.grow, .height):
            summary = "Made \(resolved.entry.app) taller"
        case (.grow, .both):
            summary = "Grew \(resolved.entry.app)"
        case (.shrink, .width):
            summary = "Made \(resolved.entry.app) narrower"
        case (.shrink, .height):
            summary = "Made \(resolved.entry.app) shorter"
        case (.shrink, .both):
            summary = "Shrank \(resolved.entry.app)"
        }

        let title = resolved.entry.title.isEmpty ? resolved.entry.app : resolved.entry.title
        let size = "\(Int(resolved.frame.width.rounded()))×\(Int(resolved.frame.height.rounded()))"

        return ActionOutcome(
            summary: summary,
            detail: "\(title) is now \(size).",
            suggestedActions: []
        )
    }

    @MainActor
    func snapshotOnMainActor() -> DeckRuntimeSnapshot {
        let handsOff = HandsOffSession.shared
        let audio = AudioLayer.shared
        let windows = DesktopModel.shared.allWindows()
        let visibleWindows = windows.filter(\.isOnScreen)
        let sessions = TmuxModel.shared.sessions
        let spacesState = buildSpacesState()
        let currentSpaceIndex = spacesState.currentSpaceIndex
        let currentSpaceName = spacesState.currentSpaceName
        let voice = DeckVoiceState(
            phase: currentVoicePhase(),
            transcript: currentVoiceTranscript(handsOff: handsOff, audio: audio),
            transcriptLines: buildTranscriptLines(handsOff: handsOff, audio: audio),
            responseSummary: currentVoiceResponseSummary(handsOff: handsOff, audio: audio),
            provider: audio.providerName == "none" ? "vox" : audio.providerName
        )
        let desktop = DeckDesktopSummary(
            activeLayerName: activeLayerName(),
            activeAppName: visibleWindows.first?.app ?? NSWorkspace.shared.frontmostApplication?.localizedName,
            screenCount: NSScreen.screens.count,
            visibleWindowCount: visibleWindows.count,
            sessionCount: sessions.count,
            currentSpaceIndex: currentSpaceIndex,
            currentSpaceName: currentSpaceName
        )
        let layoutState = buildLayoutState(windows: visibleWindows)
        let switcherState = DeckSwitcherState(items: buildSwitcherItems(
            windows: visibleWindows,
            sessions: sessions
        ))
        let telemetry = SystemTelemetryMonitor.shared.snapshot(
            windowCount: visibleWindows.count,
            sessionCount: sessions.count
        )
        let cockpitMode = buildCockpitModeState(handsOff: handsOff)
        let activityLog = CompanionActivityLog.shared.snapshot()

        return DeckRuntimeSnapshot(
            updatedAt: Date(),
            cockpit: buildCockpitState(
                voice: voice,
                desktop: desktop,
                layoutState: layoutState
            ),
            trackpad: LatticesCompanionTrackpadController.shared.state(
                isEnabled: Preferences.shared.companionTrackpadEnabled
            ),
            voice: voice,
            desktop: desktop,
            layout: layoutState,
            switcher: switcherState,
            telemetry: telemetry,
            spaces: spacesState,
            cockpitMode: cockpitMode,
            activityLog: activityLog,
            history: buildHistoryEntries(handsOff: handsOff),
            questions: []
        )
    }

    @MainActor
    func buildCockpitState(
        voice: DeckVoiceState,
        desktop: DeckDesktopSummary,
        layoutState: DeckLayoutState?
    ) -> DeckCockpitState {
        LatticesCompanionCockpitCatalog.renderedState(
            layout: Preferences.shared.companionCockpitLayout,
            voice: voice,
            desktop: desktop,
            layoutState: layoutState
        )
    }

    @MainActor
    func buildTranscriptLines(handsOff: HandsOffSession, audio: AudioLayer) -> [DeckTranscriptLine]? {
        var lines = handsOff.chatLog.suffix(10).compactMap { entry -> DeckTranscriptLine? in
            guard entry.role == .user else { return nil }
            return DeckTranscriptLine(
                id: "voice-\(entry.id.uuidString)",
                createdAt: entry.timestamp,
                text: entry.text,
                isFinal: true,
                confidence: nil,
                source: "hands-off"
            )
        }

        if let transcript = audio.lastTranscript ?? handsOff.lastTranscript,
           !transcript.isEmpty,
           !lines.contains(where: { $0.text == transcript }) {
            lines.append(DeckTranscriptLine(
                id: "voice-current",
                createdAt: Date(),
                text: transcript,
                isFinal: currentVoicePhase() == .idle,
                confidence: audio.matchConfidence > 0 ? audio.matchConfidence : nil,
                source: audio.providerName == "none" ? "vox" : audio.providerName
            ))
        }

        return lines.isEmpty ? nil : Array(lines.suffix(8).reversed())
    }

    @MainActor
    func buildSpacesState() -> DeckSpacesState {
        let displays = WindowTiler.getDisplaySpaces()
        let deckDisplays = displays.map { display -> DeckSpaceDisplay in
            let spaces = display.spaces.map { space in
                DeckSpace(
                    id: space.id,
                    index: space.index,
                    name: spaceName(for: space.index),
                    isCurrent: space.isCurrent
                )
            }
            let current = spaces.first(where: \.isCurrent)
            return DeckSpaceDisplay(
                id: display.displayId.isEmpty ? "display-\(display.displayIndex)" : display.displayId,
                displayIndex: display.displayIndex,
                currentSpaceID: display.currentSpaceId == 0 ? nil : display.currentSpaceId,
                currentSpaceIndex: current?.index,
                currentSpaceName: current?.name,
                spaces: spaces
            )
        }

        let primaryCurrent = deckDisplays.first?.spaces.first(where: \.isCurrent)
            ?? deckDisplays.flatMap(\.spaces).first(where: \.isCurrent)

        return DeckSpacesState(
            currentSpaceIndex: primaryCurrent?.index,
            currentSpaceName: primaryCurrent?.name,
            displays: deckDisplays
        )
    }

    @MainActor
    func buildCockpitModeState(handsOff: HandsOffSession) -> DeckCockpitModeState {
        let now = Date()

        switch handsOff.state {
        case .connecting, .listening:
            return DeckCockpitModeState(
                mode: .rec,
                startedAt: handsOff.stateChangedAt,
                elapsedSeconds: now.timeIntervalSince(handsOff.stateChangedAt)
            )
        case .thinking:
            return DeckCockpitModeState(
                mode: .agent,
                startedAt: handsOff.stateChangedAt,
                elapsedSeconds: now.timeIntervalSince(handsOff.stateChangedAt),
                agentProgress: 0.45,
                agentRows: buildAgentRows(handsOff: handsOff)
            )
        case .idle:
            break
        }

        if let replay = currentReplay(now: now) {
            return DeckCockpitModeState(
                mode: .replay,
                startedAt: replay.createdAt,
                elapsedSeconds: now.timeIntervalSince(replay.createdAt),
                replayMessage: replay.message,
                replayUndoExpiresAt: replay.createdAt.addingTimeInterval(5),
                replayUndoActionID: replay.undoActionID
            )
        }

        if let historyDate = handsOff.frameHistoryUpdatedAt,
           !handsOff.frameHistory.isEmpty,
           now.timeIntervalSince(historyDate) <= 5 {
            return DeckCockpitModeState(
                mode: .replay,
                startedAt: historyDate,
                elapsedSeconds: now.timeIntervalSince(historyDate),
                replayMessage: replayMessageFromRecentAction(handsOff: handsOff),
                replayUndoExpiresAt: historyDate.addingTimeInterval(5),
                replayUndoActionID: "history.undoLast"
            )
        }

        return DeckCockpitModeState(mode: .idle)
    }

    @MainActor
    func resizeFrontmostWindowOnMainActor(
        dimension: ResizeDimension,
        direction: ResizeDirection
    ) throws -> (entry: WindowEntry, frame: CGRect) {
        let windows = DesktopModel.shared.allWindows().filter(\.isOnScreen)
        guard let entry = currentFrontmostWindow(from: windows) else {
            throw LatticesDeckHostError.noFrontmostWindow
        }

        let screen = WindowTiler.screenForWindowFrame(entry.frame)
        let visibleFrame = cgVisibleFrame(for: screen)
        let currentFrame = CGRect(
            x: entry.frame.x,
            y: entry.frame.y,
            width: entry.frame.w,
            height: entry.frame.h
        )

        return (
            entry,
            adjustedFrame(
                currentFrame: currentFrame,
                visibleFrame: visibleFrame,
                dimension: dimension,
                direction: direction
            )
        )
    }

    @MainActor
    func currentVoicePhase() -> DeckVoicePhase {
        let handsOff = HandsOffSession.shared
        switch handsOff.state {
        case .idle:
            break
        case .connecting, .listening:
            return .listening
        case .thinking:
            return .reasoning
        }

        let audio = AudioLayer.shared
        if audio.isListening {
            return .listening
        }
        if audio.executionResult == "Transcribing..." {
            return .transcribing
        }
        if audio.executionResult == "thinking..." {
            return .reasoning
        }
        return .idle
    }

    @MainActor
    func currentVoiceTranscript(handsOff: HandsOffSession, audio: AudioLayer) -> String? {
        if audio.isListening || audio.executionResult != nil || audio.lastTranscript != nil {
            return audio.lastTranscript
        }
        return handsOff.lastTranscript
    }

    @MainActor
    func currentVoiceResponseSummary(handsOff: HandsOffSession, audio: AudioLayer) -> String? {
        switch handsOff.state {
        case .connecting, .listening, .thinking:
            return handsOff.lastResponse ?? audio.executionResult
        case .idle:
            return audio.executionResult ?? handsOff.lastResponse
        }
    }

    @MainActor
    func activeLayerName() -> String? {
        let workspace = WorkspaceManager.shared
        if let label = workspace.activeLayer?.label, !label.isEmpty {
            return label
        }

        let sessionLayers = SessionLayerStore.shared
        guard sessionLayers.activeIndex >= 0,
              sessionLayers.activeIndex < sessionLayers.layers.count else {
            return nil
        }
        return sessionLayers.layers[sessionLayers.activeIndex].name
    }

    @MainActor
    func buildLayoutState(windows: [WindowEntry]) -> DeckLayoutState? {
        let deckWindows = windows.filter { $0.app != "Lattices" }
        guard let frontmost = currentFrontmostWindow(from: deckWindows) else {
            return nil
        }

        let frontmostScreen = WindowTiler.screenForWindowFrame(frontmost.frame)
        let frontmostVisible = cgVisibleFrame(for: frontmostScreen)
        let frontmostRect = normalizedRect(for: frontmost.frame, within: frontmostVisible)
        let placement = WindowTiler.inferTilePosition(frame: frontmost.frame, screen: frontmostScreen)?.rawValue
        let aspectRatio = frontmostVisible.height > 0 ? frontmostVisible.width / frontmostVisible.height : 1.0

        // Distribute windows per NSScreen — same pattern as HUDMinimap.windowsOnScreen.
        // Each window's normalizedFrame is relative to its own display's visible frame so
        // the iPad mini-displays render correctly per-monitor.
        let screens = NSScreen.screens
        var previewWindows: [DeckLayoutPreviewWindow] = []
        for (idx, screen) in screens.enumerated() {
            let visible = cgVisibleFrame(for: screen)
            let screenID = ObjectIdentifier(screen)
            let onScreen = deckWindows
                .filter { ObjectIdentifier(WindowTiler.screenForWindowFrame($0.frame)) == screenID }
                .sorted { $0.zIndex > $1.zIndex }
            for window in onScreen {
                guard let rect = normalizedRect(for: window.frame, within: visible) else { continue }
                previewWindows.append(DeckLayoutPreviewWindow(
                    id: "window:\(window.wid)",
                    itemID: "window:\(window.wid)",
                    title: window.title.isEmpty ? window.app : window.title,
                    subtitle: window.title.isEmpty ? nil : window.app,
                    normalizedFrame: rect,
                    appCategory: appCategory(for: window.app),
                    appCategoryTint: appCategoryTint(for: window.app),
                    isFrontmost: window.wid == frontmost.wid,
                    displayIndex: idx
                ))
            }
        }

        return DeckLayoutState(
            screenName: frontmostScreen.localizedName,
            frontmostWindow: DeckLayoutFocusWindow(
                id: "window:\(frontmost.wid)",
                itemID: "window:\(frontmost.wid)",
                appName: frontmost.app,
                title: frontmost.title.isEmpty ? nil : frontmost.title,
                frame: deckRect(for: frontmost.frame),
                normalizedFrame: frontmostRect,
                placement: placement
            ),
            preview: DeckLayoutPreview(
                aspectRatio: aspectRatio,
                windows: previewWindows,
                displayCount: screens.count
            )
        )
    }

    @MainActor
    func buildSwitcherItems(
        windows: [WindowEntry],
        sessions: [TmuxSession]
    ) -> [DeckSwitcherItem] {
        var items: [DeckSwitcherItem] = []

        if let layers = WorkspaceManager.shared.config?.layers {
            for (index, layer) in layers.enumerated() {
                items.append(DeckSwitcherItem(
                    id: "workspace-layer:\(index)",
                    title: layer.label,
                    subtitle: "\(layer.projects.count) project target(s)",
                    iconToken: "workspace-layer",
                    kind: .task,
                    isFrontmost: WorkspaceManager.shared.activeLayerIndex == index
                ))
            }
        }

        let sessionLayerStore = SessionLayerStore.shared
        for (index, layer) in sessionLayerStore.layers.enumerated() {
            items.append(DeckSwitcherItem(
                id: "session-layer:\(layer.id)",
                title: layer.name,
                subtitle: "\(layer.windows.count) tagged window(s)",
                iconToken: "session-layer",
                kind: .task,
                isFrontmost: sessionLayerStore.activeIndex == index
            ))
        }

        var seenApps = Set<String>()
        for window in windows where seenApps.insert(window.app).inserted {
            items.append(DeckSwitcherItem(
                id: "app:\(window.app)",
                title: window.app,
                subtitle: window.title.isEmpty ? "Application" : window.title,
                iconToken: window.app.lowercased(),
                kind: .application,
                isFrontmost: window.zIndex == 0
            ))
        }

        for window in windows.prefix(8) {
            items.append(DeckSwitcherItem(
                id: "window:\(window.wid)",
                title: window.title.isEmpty ? window.app : window.title,
                subtitle: window.app,
                iconToken: "window",
                kind: .window,
                isFrontmost: window.zIndex == 0
            ))
        }

        for session in sessions.prefix(8) {
            let paneSummary = session.panes
                .map(\.currentCommand)
                .filter { !["zsh", "bash", "fish", "sh"].contains($0) }
                .prefix(2)
                .joined(separator: " · ")

            items.append(DeckSwitcherItem(
                id: "session:\(session.name)",
                title: session.name,
                subtitle: paneSummary.isEmpty ? "tmux session" : paneSummary,
                iconToken: "terminal",
                kind: .session,
                isFrontmost: false
            ))
        }

        return items
    }

    @MainActor
    func buildHistoryEntries(handsOff: HandsOffSession) -> [DeckHistoryEntry] {
        var entries: [DeckHistoryEntry] = []

        if !handsOff.frameHistory.isEmpty {
            entries.append(DeckHistoryEntry(
                id: "undo-last-move",
                createdAt: Date(),
                title: "Last window move can be undone",
                detail: "Use the history action to roll back the most recent layout change.",
                kind: .layout,
                undoActionID: "history.undoLast"
            ))
        }

        for (index, action) in handsOff.recentActions.enumerated() {
            let summary = actionSummary(for: action)
            entries.append(DeckHistoryEntry(
                id: "recent-action-\(index)",
                createdAt: Date(),
                title: summary.title,
                detail: summary.detail,
                kind: summary.kind,
                undoActionID: summary.kind == .layout && !handsOff.frameHistory.isEmpty
                    ? "history.undoLast"
                    : nil
            ))
        }

        for entry in handsOff.chatLog.suffix(8).reversed() {
            let kind: DeckHistoryKind
            switch entry.role {
            case .user, .assistant:
                kind = .voice
            case .system:
                kind = .automation
            }

            entries.append(DeckHistoryEntry(
                id: "chat-\(entry.id.uuidString)",
                createdAt: entry.timestamp,
                title: historyTitle(for: entry),
                detail: entry.detail,
                kind: kind
            ))
        }

        return Array(entries.prefix(12))
    }

    @MainActor
    func currentFrontmostWindow(from windows: [WindowEntry]) -> WindowEntry? {
        if let target = frontmostWindowTarget(),
           let entry = DesktopModel.shared.windows[target.wid],
           entry.isOnScreen,
           entry.app != "Lattices" {
            return entry
        }

        return windows
            .filter { $0.app != "Lattices" }
            .min { lhs, rhs in
                lhs.zIndex < rhs.zIndex
            }
    }

    func spaceSwitchDirection(key: String, modifiers: [String]) -> Int? {
        let normalized = key.lowercased()
            .replacingOccurrences(of: "←", with: "left")
            .replacingOccurrences(of: "→", with: "right")
        guard normalized == "left" || normalized == "right" else { return nil }
        let hasControl = modifiers.contains { mod in
            let m = mod.lowercased()
            return m == "control" || m == "ctrl" || m == "⌃"
        }
        guard hasControl else { return nil }
        return normalized == "right" ? 1 : -1
    }

    @MainActor
    func switchActiveSpace(direction: Int) -> ActionOutcome {
        let displays = WindowTiler.getDisplaySpaces()
        guard !displays.isEmpty else {
            return ActionOutcome(summary: "No displays available", detail: nil, suggestedActions: [])
        }

        let activeScreen: NSScreen? = {
            if let frontmost = frontmostWindowTarget(),
               let entry = DesktopModel.shared.windows[frontmost.wid] {
                return WindowTiler.screenForWindowFrame(entry.frame)
            }
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        }()

        let preferredDisplayIndex = NSScreen.screens.firstIndex { activeScreen === $0 } ?? 0
        let display = displays.first(where: { $0.displayIndex == preferredDisplayIndex }) ?? displays[0]

        guard let currentIdx = display.spaces.firstIndex(where: { $0.isCurrent }) else {
            return ActionOutcome(
                summary: "No current space",
                detail: "Could not determine the active space on display \(display.displayIndex + 1).",
                suggestedActions: []
            )
        }

        let targetIdx = currentIdx + direction
        guard targetIdx >= 0, targetIdx < display.spaces.count else {
            return ActionOutcome(
                summary: direction > 0 ? "Already on last space" : "Already on first space",
                detail: nil,
                suggestedActions: []
            )
        }

        let target = display.spaces[targetIdx]
        WindowTiler.switchToSpace(spaceId: target.id)
        return ActionOutcome(
            summary: direction > 0 ? "Next space" : "Previous space",
            detail: "Switched display \(display.displayIndex + 1) to space \(target.index).",
            suggestedActions: []
        )
    }

    @MainActor
    func buildAgentRows(handsOff: HandsOffSession) -> [DeckAgentPlanRow] {
        let transcript = handsOff.lastTranscript ?? "voice request"
        var rows: [DeckAgentPlanRow] = [
            DeckAgentPlanRow(id: "capture", state: .done, text: "captured: \(transcript)"),
            DeckAgentPlanRow(id: "resolve", state: .live, text: "resolve workspace intent"),
            DeckAgentPlanRow(id: "apply", state: .next, text: "apply actions on Mac"),
        ]

        for (index, action) in handsOff.recentActions.prefix(3).enumerated() {
            let summary = actionSummary(for: action)
            rows.append(DeckAgentPlanRow(
                id: "recent-\(index)",
                state: .next,
                text: summary.title.lowercased()
            ))
        }

        return rows
    }

    @MainActor
    func replayMessageFromRecentAction(handsOff: HandsOffSession) -> String {
        if let action = handsOff.recentActions.first {
            return actionSummary(for: action).title
        }
        if let transcript = handsOff.lastTranscript, !transcript.isEmpty {
            return transcript
        }
        return "Last window move"
    }

    func cycleApplication(direction: String) throws -> ActionOutcome {
        let target = try MainActorSync.run {
            try self.nextApplicationTargetOnMainActor(direction: direction)
        }
        _ = try callAPI("window.focus", params: ["wid": .int(Int(target.wid))])
        let title = target.title.isEmpty ? target.app : target.title
        return ActionOutcome(
            summary: "Focused \(target.app)",
            detail: title,
            suggestedActions: []
        )
    }

    func cycleWindow(direction: String) throws -> ActionOutcome {
        let target = try MainActorSync.run {
            try self.nextWindowTargetOnMainActor(direction: direction)
        }
        _ = try callAPI("window.focus", params: ["wid": .int(Int(target.wid))])
        return ActionOutcome(
            summary: "Focused \(target.app)",
            detail: target.title.isEmpty ? "Moved to the next visible window." : target.title,
            suggestedActions: []
        )
    }

    @MainActor
    func nextApplicationTargetOnMainActor(direction: String) throws -> WindowEntry {
        let windows = DesktopModel.shared.allWindows()
            .filter { $0.isOnScreen && $0.app != "Lattices" }
            .sorted { lhs, rhs in
                lhs.zIndex < rhs.zIndex
            }

        var orderedApps: [String] = []
        for window in windows where !orderedApps.contains(window.app) {
            orderedApps.append(window.app)
        }

        guard !orderedApps.isEmpty else {
            throw LatticesDeckHostError.noVisibleTargets("applications")
        }

        let currentApp = currentFrontmostWindow(from: windows)?.app ?? orderedApps.first!
        let currentIndex = orderedApps.firstIndex(of: currentApp) ?? 0
        let targetIndex = wrappedIndex(
            currentIndex,
            count: orderedApps.count,
            direction: direction
        )
        let targetApp = orderedApps[targetIndex]

        guard let target = windows.first(where: { $0.app == targetApp }) else {
            throw LatticesDeckHostError.noVisibleTargets("applications")
        }

        return target
    }

    @MainActor
    func nextWindowTargetOnMainActor(direction: String) throws -> WindowEntry {
        let windows = DesktopModel.shared.allWindows()
            .filter { $0.isOnScreen && $0.app != "Lattices" }
            .sorted { lhs, rhs in
                lhs.zIndex < rhs.zIndex
            }

        guard !windows.isEmpty else {
            throw LatticesDeckHostError.noVisibleTargets("windows")
        }

        let currentWID = currentFrontmostWindow(from: windows)?.wid ?? windows[0].wid
        let currentIndex = windows.firstIndex(where: { $0.wid == currentWID }) ?? 0
        let targetIndex = wrappedIndex(
            currentIndex,
            count: windows.count,
            direction: direction
        )
        return windows[targetIndex]
    }

    func wrappedIndex(_ currentIndex: Int, count: Int, direction: String) -> Int {
        guard count > 0 else { return 0 }
        if direction.lowercased().hasPrefix("prev") {
            return (currentIndex - 1 + count) % count
        }
        return (currentIndex + 1) % count
    }

    @MainActor
    func frontmostWindowTarget() -> (wid: UInt32, pid: Int32)? {
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

    @MainActor
    func cgVisibleFrame(for screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGRect(
            x: visible.minX,
            y: primaryHeight - visible.maxY,
            width: visible.width,
            height: visible.height
        )
    }

    func deckRect(for frame: WindowFrame) -> DeckRect {
        DeckRect(x: frame.x, y: frame.y, w: frame.w, h: frame.h)
    }

    func deckRect(for frame: CGRect) -> DeckRect {
        DeckRect(
            x: frame.origin.x,
            y: frame.origin.y,
            w: frame.width,
            h: frame.height
        )
    }

    func normalizedRect(for frame: WindowFrame, within visibleFrame: CGRect) -> DeckRect? {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return nil }

        let x1 = max(0, min(1, (frame.x - visibleFrame.minX) / visibleFrame.width))
        let y1 = max(0, min(1, (frame.y - visibleFrame.minY) / visibleFrame.height))
        let x2 = max(0, min(1, ((frame.x + frame.w) - visibleFrame.minX) / visibleFrame.width))
        let y2 = max(0, min(1, ((frame.y + frame.h) - visibleFrame.minY) / visibleFrame.height))

        guard x2 > x1, y2 > y1 else { return nil }
        return DeckRect(x: x1, y: y1, w: x2 - x1, h: y2 - y1)
    }

    func adjustedFrame(
        currentFrame: CGRect,
        visibleFrame: CGRect,
        dimension: ResizeDimension,
        direction: ResizeDirection
    ) -> CGRect {
        var next = currentFrame

        let widthStep = max(88.0, visibleFrame.width * 0.08)
        let heightStep = max(72.0, visibleFrame.height * 0.08)
        let widthDelta = direction == .grow ? widthStep : -widthStep
        let heightDelta = direction == .grow ? heightStep : -heightStep
        let minWidth = min(max(320.0, visibleFrame.width * 0.24), visibleFrame.width)
        let minHeight = min(max(220.0, visibleFrame.height * 0.24), visibleFrame.height)
        let maxWidth = visibleFrame.width
        let maxHeight = visibleFrame.height

        let centerX = currentFrame.midX
        let centerY = currentFrame.midY

        switch dimension {
        case .width:
            next.size.width = max(minWidth, min(maxWidth, currentFrame.width + widthDelta))
        case .height:
            next.size.height = max(minHeight, min(maxHeight, currentFrame.height + heightDelta))
        case .both:
            next.size.width = max(minWidth, min(maxWidth, currentFrame.width + widthDelta))
            next.size.height = max(minHeight, min(maxHeight, currentFrame.height + heightDelta))
        }

        next.origin.x = centerX - next.width / 2
        next.origin.y = centerY - next.height / 2

        next.origin.x = max(visibleFrame.minX, min(next.origin.x, visibleFrame.maxX - next.width))
        next.origin.y = max(visibleFrame.minY, min(next.origin.y, visibleFrame.maxY - next.height))
        return next.integral
    }

    func actionSummary(for action: [String: Any]) -> (title: String, detail: String?, kind: DeckHistoryKind) {
        let intent = action["intent"] as? String ?? "action"
        let slots = action["slots"] as? [String: Any] ?? [:]
        let title = intent
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")

        let detail = slots.keys.sorted().compactMap { key -> String? in
            guard let value = slots[key] else { return nil }
            return "\(key)=\(value)"
        }
        .joined(separator: ", ")

        let kind: DeckHistoryKind
        if ["tile_window", "swap", "distribute", "move_to_display"].contains(intent) {
            kind = .layout
        } else if intent.contains("focus") || intent.contains("switch") || intent.contains("launch") {
            kind = .switcher
        } else {
            kind = .automation
        }

        return (title, detail.isEmpty ? nil : detail, kind)
    }

    @MainActor
    func spaceName(for index: Int) -> String {
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

    func appCategory(for appName: String) -> String {
        AppTypeClassifier.classify(appName).rawValue
    }

    func appCategoryTint(for appName: String) -> String {
        switch AppTypeClassifier.classify(appName) {
        case .terminal, .editor:
            return "green"
        case .browser:
            return "blue"
        case .chat:
            return "teal"
        case .media:
            return "pink"
        case .design:
            return "violet"
        case .system:
            return "amber"
        case .other:
            return "amber"
        }
    }

    func recordAction(request: DeckActionRequest, outcome: ActionOutcome) {
        CompanionActivityLog.shared.record(
            tag: "DECK",
            tint: actionTint(for: request.actionID),
            text: outcome.summary
        )

        let hasUndo = ((try? MainActorSync.run {
            !HandsOffSession.shared.frameHistory.isEmpty
        }) ?? false)

        replayLock.lock()
        lastReplayMessage = outcome.summary
        lastReplayAt = Date()
        lastReplayUndoActionID = hasUndo ? "history.undoLast" : nil
        replayLock.unlock()
    }

    func currentReplay(now: Date) -> (message: String, createdAt: Date, undoActionID: String?)? {
        replayLock.lock()
        let message = lastReplayMessage
        let createdAt = lastReplayAt
        let undoActionID = lastReplayUndoActionID
        replayLock.unlock()

        guard let message, let createdAt, now.timeIntervalSince(createdAt) <= 5 else {
            return nil
        }
        return (message, createdAt, undoActionID)
    }

    func actionTint(for actionID: String) -> String {
        if actionID.hasPrefix("voice") { return "red" }
        if actionID.hasPrefix("layout") { return "blue" }
        if actionID.hasPrefix("switch") { return "violet" }
        if actionID.hasPrefix("mouse") { return "teal" }
        if actionID.hasPrefix("key") || actionID.hasPrefix("keys") { return "amber" }
        if actionID.hasPrefix("history") { return "green" }
        return "amber"
    }

    func historyTitle(for entry: VoiceChatEntry) -> String {
        switch entry.role {
        case .user:
            return "You: \(entry.text)"
        case .assistant:
            return "Lattices: \(entry.text)"
        case .system:
            return "System: \(entry.text)"
        }
    }

    func voiceSuggestions(for phase: DeckVoicePhase) -> [DeckSuggestedAction] {
        switch phase {
        case .idle:
            return [
                DeckSuggestedAction(
                    id: "voice.toggle",
                    title: "Start Voice",
                    iconSystemName: "mic.fill"
                )
            ]
        case .listening:
            return [
                DeckSuggestedAction(
                    id: "voice.toggle",
                    title: "Stop Listening",
                    iconSystemName: "stop.fill"
                ),
                DeckSuggestedAction(
                    id: "voice.cancel",
                    title: "Cancel",
                    iconSystemName: "xmark"
                )
            ]
        case .transcribing, .reasoning, .speaking:
            return [
                DeckSuggestedAction(
                    id: "voice.cancel",
                    title: "Cancel",
                    iconSystemName: "xmark"
                )
            ]
        }
    }

    func flushMainQueue() {
        guard !Thread.isMainThread else { return }
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            semaphore.signal()
        }
        semaphore.wait()
    }
}

private enum MainActorSync {
    static func run<T>(_ body: @escaping @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated(body)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>!

        Task { @MainActor in
            result = Result {
                try body()
            }
            semaphore.signal()
        }

        semaphore.wait()
        return try result.get()
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
