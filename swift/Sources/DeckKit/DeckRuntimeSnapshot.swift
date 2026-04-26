import Foundation

public struct DeckRuntimeSnapshot: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var cockpit: DeckCockpitState?
    public var trackpad: DeckTrackpadState?
    public var voice: DeckVoiceState?
    public var desktop: DeckDesktopSummary?
    public var layout: DeckLayoutState?
    public var switcher: DeckSwitcherState?
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
        self.history = history
        self.questions = questions
    }
}

public struct DeckVoiceState: Codable, Equatable, Sendable {
    public var phase: DeckVoicePhase
    public var transcript: String?
    public var responseSummary: String?
    public var provider: String?

    public init(
        phase: DeckVoicePhase,
        transcript: String? = nil,
        responseSummary: String? = nil,
        provider: String? = nil
    ) {
        self.phase = phase
        self.transcript = transcript
        self.responseSummary = responseSummary
        self.provider = provider
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

    public init(
        activeLayerName: String? = nil,
        activeAppName: String? = nil,
        screenCount: Int,
        visibleWindowCount: Int,
        sessionCount: Int
    ) {
        self.activeLayerName = activeLayerName
        self.activeAppName = activeAppName
        self.screenCount = screenCount
        self.visibleWindowCount = visibleWindowCount
        self.sessionCount = sessionCount
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

    public init(
        aspectRatio: Double,
        windows: [DeckLayoutPreviewWindow]
    ) {
        self.aspectRatio = aspectRatio
        self.windows = windows
    }
}

public struct DeckLayoutPreviewWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var itemID: String
    public var title: String
    public var subtitle: String?
    public var normalizedFrame: DeckRect
    public var isFrontmost: Bool

    public init(
        id: String,
        itemID: String,
        title: String,
        subtitle: String? = nil,
        normalizedFrame: DeckRect,
        isFrontmost: Bool = false
    ) {
        self.id = id
        self.itemID = itemID
        self.title = title
        self.subtitle = subtitle
        self.normalizedFrame = normalizedFrame
        self.isFrontmost = isFrontmost
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
