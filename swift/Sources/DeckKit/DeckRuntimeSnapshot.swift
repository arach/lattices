import Foundation

public struct DeckRuntimeSnapshot: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var cockpit: DeckCockpitState?
    public var trackpad: DeckTrackpadState?
    public var voice: DeckVoiceState?
    public var desktop: DeckDesktopSummary?
    public var layout: DeckLayoutState?
    public var switcher: DeckSwitcherState?
    public var telemetry: DeckSystemTelemetry?
    public var spaces: DeckSpacesState?
    public var cockpitMode: DeckCockpitModeState?
    public var activityLog: [DeckActivityLogEntry]?
    public var history: [DeckHistoryEntry]
    public var questions: [DeckQuestionCard]

    public init(
        updatedAt: Date = .now,
        cockpit: DeckCockpitState? = nil,
        trackpad: DeckTrackpadState? = nil,
        voice: DeckVoiceState? = nil,
        desktop: DeckDesktopSummary? = nil,
        layout: DeckLayoutState? = nil,
        switcher: DeckSwitcherState? = nil,
        telemetry: DeckSystemTelemetry? = nil,
        spaces: DeckSpacesState? = nil,
        cockpitMode: DeckCockpitModeState? = nil,
        activityLog: [DeckActivityLogEntry]? = nil,
        history: [DeckHistoryEntry] = [],
        questions: [DeckQuestionCard] = []
    ) {
        self.updatedAt = updatedAt
        self.cockpit = cockpit
        self.trackpad = trackpad
        self.voice = voice
        self.desktop = desktop
        self.layout = layout
        self.switcher = switcher
        self.telemetry = telemetry
        self.spaces = spaces
        self.cockpitMode = cockpitMode
        self.activityLog = activityLog
        self.history = history
        self.questions = questions
    }
}

public struct DeckVoiceState: Codable, Equatable, Sendable {
    public var phase: DeckVoicePhase
    public var transcript: String?
    public var transcriptLines: [DeckTranscriptLine]?
    public var responseSummary: String?
    public var provider: String?
    public var error: DeckVoiceError?       // currently-active error (cleared on recovery)
    public var lastError: DeckVoiceError?   // sticky most-recent error for the activity tape

    public init(
        phase: DeckVoicePhase,
        transcript: String? = nil,
        transcriptLines: [DeckTranscriptLine]? = nil,
        responseSummary: String? = nil,
        provider: String? = nil,
        error: DeckVoiceError? = nil,
        lastError: DeckVoiceError? = nil
    ) {
        self.phase = phase
        self.transcript = transcript
        self.transcriptLines = transcriptLines
        self.responseSummary = responseSummary
        self.provider = provider
        self.error = error
        self.lastError = lastError
    }
}

public struct DeckTranscriptLine: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var createdAt: Date
    public var text: String
    public var isFinal: Bool
    public var confidence: Double?
    public var source: String?

    public init(
        id: String,
        createdAt: Date = .now,
        text: String,
        isFinal: Bool,
        confidence: Double? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.source = source
    }
}

public enum DeckVoicePhase: String, Codable, CaseIterable, Sendable {
    case idle
    case listening
    case transcribing
    case reasoning
    case speaking
}

public struct DeckDesktopSummary: Codable, Equatable, Sendable {
    public var activeLayerName: String?
    public var activeAppName: String?
    public var screenCount: Int
    public var visibleWindowCount: Int
    public var sessionCount: Int
    public var currentSpaceIndex: Int?
    public var currentSpaceName: String?

    public init(
        activeLayerName: String? = nil,
        activeAppName: String? = nil,
        screenCount: Int,
        visibleWindowCount: Int,
        sessionCount: Int,
        currentSpaceIndex: Int? = nil,
        currentSpaceName: String? = nil
    ) {
        self.activeLayerName = activeLayerName
        self.activeAppName = activeAppName
        self.screenCount = screenCount
        self.visibleWindowCount = visibleWindowCount
        self.sessionCount = sessionCount
        self.currentSpaceIndex = currentSpaceIndex
        self.currentSpaceName = currentSpaceName
    }
}

public struct DeckLayoutState: Codable, Equatable, Sendable {
    public var screenName: String?
    public var frontmostWindow: DeckLayoutFocusWindow?
    public var preview: DeckLayoutPreview?

    public init(
        screenName: String? = nil,
        frontmostWindow: DeckLayoutFocusWindow? = nil,
        preview: DeckLayoutPreview? = nil
    ) {
        self.screenName = screenName
        self.frontmostWindow = frontmostWindow
        self.preview = preview
    }
}

public struct DeckLayoutFocusWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var itemID: String
    public var appName: String
    public var title: String?
    public var frame: DeckRect
    public var normalizedFrame: DeckRect?
    public var placement: String?

    public init(
        id: String,
        itemID: String,
        appName: String,
        title: String? = nil,
        frame: DeckRect,
        normalizedFrame: DeckRect? = nil,
        placement: String? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.normalizedFrame = normalizedFrame
        self.placement = placement
    }
}

public struct DeckLayoutPreview: Codable, Equatable, Sendable {
    public var aspectRatio: Double
    public var windows: [DeckLayoutPreviewWindow]
    public var displayCount: Int?

    public init(
        aspectRatio: Double,
        windows: [DeckLayoutPreviewWindow],
        displayCount: Int? = nil
    ) {
        self.aspectRatio = aspectRatio
        self.windows = windows
        self.displayCount = displayCount
    }
}

public struct DeckLayoutPreviewWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var itemID: String
    public var title: String
    public var subtitle: String?
    public var normalizedFrame: DeckRect
    public var appCategory: String?
    public var appCategoryTint: String?
    public var isFrontmost: Bool
    public var displayIndex: Int?

    public init(
        id: String,
        itemID: String,
        title: String,
        subtitle: String? = nil,
        normalizedFrame: DeckRect,
        appCategory: String? = nil,
        appCategoryTint: String? = nil,
        isFrontmost: Bool = false,
        displayIndex: Int? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.title = title
        self.subtitle = subtitle
        self.normalizedFrame = normalizedFrame
        self.appCategory = appCategory
        self.appCategoryTint = appCategoryTint
        self.isFrontmost = isFrontmost
        self.displayIndex = displayIndex
    }
}

public struct DeckRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct DeckSwitcherState: Codable, Equatable, Sendable {
    public var items: [DeckSwitcherItem]

    public init(items: [DeckSwitcherItem]) {
        self.items = items
    }
}

public struct DeckSwitcherItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var iconToken: String?
    public var kind: DeckSwitcherItemKind
    public var isFrontmost: Bool

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        iconToken: String? = nil,
        kind: DeckSwitcherItemKind,
        isFrontmost: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconToken = iconToken
        self.kind = kind
        self.isFrontmost = isFrontmost
    }
}

public enum DeckSwitcherItemKind: String, Codable, CaseIterable, Sendable {
    case application
    case window
    case tab
    case task
    case session
}

public struct DeckHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var createdAt: Date
    public var title: String
    public var detail: String?
    public var kind: DeckHistoryKind
    public var undoActionID: String?

    public init(
        id: String,
        createdAt: Date = .now,
        title: String,
        detail: String? = nil,
        kind: DeckHistoryKind,
        undoActionID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.detail = detail
        self.kind = kind
        self.undoActionID = undoActionID
    }
}

public enum DeckHistoryKind: String, Codable, CaseIterable, Sendable {
    case voice
    case layout
    case switcher
    case automation
}

public struct DeckSystemTelemetry: Codable, Equatable, Sendable {
    public var sampledAt: Date
    public var cpuLoadPercent: Double?
    public var memoryUsedPercent: Double?
    public var gpuLoadPercent: Double?
    public var thermalPressurePercent: Double?
    public var thermalState: DeckThermalState?
    public var temperatureCelsius: Double?
    public var batteryPercent: Double?
    public var isCharging: Bool?
    public var powerSource: String?
    public var windowCount: Int
    public var sessionCount: Int

    public init(
        sampledAt: Date = .now,
        cpuLoadPercent: Double? = nil,
        memoryUsedPercent: Double? = nil,
        gpuLoadPercent: Double? = nil,
        thermalPressurePercent: Double? = nil,
        thermalState: DeckThermalState? = nil,
        temperatureCelsius: Double? = nil,
        batteryPercent: Double? = nil,
        isCharging: Bool? = nil,
        powerSource: String? = nil,
        windowCount: Int,
        sessionCount: Int
    ) {
        self.sampledAt = sampledAt
        self.cpuLoadPercent = cpuLoadPercent
        self.memoryUsedPercent = memoryUsedPercent
        self.gpuLoadPercent = gpuLoadPercent
        self.thermalPressurePercent = thermalPressurePercent
        self.thermalState = thermalState
        self.temperatureCelsius = temperatureCelsius
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.powerSource = powerSource
        self.windowCount = windowCount
        self.sessionCount = sessionCount
    }
}

public enum DeckThermalState: String, Codable, CaseIterable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

public struct DeckSpacesState: Codable, Equatable, Sendable {
    public var currentSpaceIndex: Int?
    public var currentSpaceName: String?
    public var displays: [DeckSpaceDisplay]

    public init(
        currentSpaceIndex: Int? = nil,
        currentSpaceName: String? = nil,
        displays: [DeckSpaceDisplay]
    ) {
        self.currentSpaceIndex = currentSpaceIndex
        self.currentSpaceName = currentSpaceName
        self.displays = displays
    }
}

public struct DeckSpaceDisplay: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayIndex: Int
    public var currentSpaceID: Int?
    public var currentSpaceIndex: Int?
    public var currentSpaceName: String?
    public var spaces: [DeckSpace]

    public init(
        id: String,
        displayIndex: Int,
        currentSpaceID: Int? = nil,
        currentSpaceIndex: Int? = nil,
        currentSpaceName: String? = nil,
        spaces: [DeckSpace]
    ) {
        self.id = id
        self.displayIndex = displayIndex
        self.currentSpaceID = currentSpaceID
        self.currentSpaceIndex = currentSpaceIndex
        self.currentSpaceName = currentSpaceName
        self.spaces = spaces
    }
}

public struct DeckSpace: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var index: Int
    public var name: String?
    public var isCurrent: Bool

    public init(id: Int, index: Int, name: String? = nil, isCurrent: Bool) {
        self.id = id
        self.index = index
        self.name = name
        self.isCurrent = isCurrent
    }
}

public struct DeckCockpitModeState: Codable, Equatable, Sendable {
    public var mode: DeckCockpitMode
    public var startedAt: Date?
    public var elapsedSeconds: Double?
    public var replayMessage: String?
    public var replayUndoExpiresAt: Date?
    public var replayUndoActionID: String?
    public var agentProgress: Double?
    public var agentRows: [DeckAgentPlanRow]

    public init(
        mode: DeckCockpitMode,
        startedAt: Date? = nil,
        elapsedSeconds: Double? = nil,
        replayMessage: String? = nil,
        replayUndoExpiresAt: Date? = nil,
        replayUndoActionID: String? = nil,
        agentProgress: Double? = nil,
        agentRows: [DeckAgentPlanRow] = []
    ) {
        self.mode = mode
        self.startedAt = startedAt
        self.elapsedSeconds = elapsedSeconds
        self.replayMessage = replayMessage
        self.replayUndoExpiresAt = replayUndoExpiresAt
        self.replayUndoActionID = replayUndoActionID
        self.agentProgress = agentProgress
        self.agentRows = agentRows
    }
}

public enum DeckCockpitMode: String, Codable, CaseIterable, Sendable {
    case idle
    case rec
    case replay
    case agent
}

public struct DeckAgentPlanRow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var state: DeckAgentPlanRowState
    public var text: String

    public init(id: String, state: DeckAgentPlanRowState, text: String) {
        self.id = id
        self.state = state
        self.text = text
    }
}

public enum DeckAgentPlanRowState: String, Codable, CaseIterable, Sendable {
    case done
    case live
    case next
}

public struct DeckActivityLogEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var createdAt: Date
    public var tag: String
    public var tint: String?
    public var text: String

    public init(
        id: String,
        createdAt: Date = .now,
        tag: String,
        tint: String? = nil,
        text: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.tag = tag
        self.tint = tint
        self.text = text
    }
}

public struct DeckQuestionCard: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var prompt: String
    public var detail: String?
    public var options: [DeckQuestionOption]

    public init(
        id: String,
        prompt: String,
        detail: String? = nil,
        options: [DeckQuestionOption]
    ) {
        self.id = id
        self.prompt = prompt
        self.detail = detail
        self.options = options
    }
}

public struct DeckQuestionOption: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String?
    public var actionID: String

    public init(id: String, title: String, detail: String? = nil, actionID: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.actionID = actionID
    }
}
