import Foundation

public enum TerminalApp: String, CaseIterable, Codable, Identifiable, Sendable {
    case terminal = "Terminal"
    case iterm2 = "iTerm2"
    case ghostty = "Ghostty"

    public var id: String { rawValue }

    public var bundleIdentifier: String {
        switch self {
        case .terminal:
            return "com.apple.Terminal"
        case .iterm2:
            return "com.googlecode.iterm2"
        case .ghostty:
            return "com.mitchellh.ghostty"
        }
    }

    public static func named(_ appName: String) -> TerminalApp? {
        allCases.first { $0.rawValue == appName }
    }
}

public struct TerminalFrame: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct TerminalWindow: Codable, Equatable, Identifiable, Sendable {
    public let wid: UInt32
    public let app: String
    public let bundleIdentifier: String?
    public let pid: Int32
    public let title: String
    public let frame: TerminalFrame
    public let isOnScreen: Bool
    public let latticesSession: String?
    public var axVerified: Bool
    public var zIndex: Int

    public var id: UInt32 { wid }

    public init(
        wid: UInt32,
        app: String,
        bundleIdentifier: String? = nil,
        pid: Int32,
        title: String,
        frame: TerminalFrame,
        isOnScreen: Bool,
        latticesSession: String? = nil,
        axVerified: Bool = true,
        zIndex: Int = 0
    ) {
        self.wid = wid
        self.app = app
        self.bundleIdentifier = bundleIdentifier
        self.pid = pid
        self.title = title
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.latticesSession = latticesSession
        self.axVerified = axVerified
        self.zIndex = zIndex
    }
}

public struct ProcessEntry: Codable, Equatable, Identifiable, Sendable {
    public let pid: Int
    public let ppid: Int
    public let pgid: Int
    public let tty: String
    public let comm: String
    public let args: String
    public var cwd: String?

    public var id: Int { pid }

    public init(pid: Int, ppid: Int, pgid: Int, tty: String, comm: String, args: String, cwd: String? = nil) {
        self.pid = pid
        self.ppid = ppid
        self.pgid = pgid
        self.tty = tty
        self.comm = comm
        self.args = args
        self.cwd = cwd
    }
}

public struct TmuxSession: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let windowCount: Int
    public let attached: Bool
    public let panes: [TmuxPane]

    public init(name: String, windowCount: Int, attached: Bool, panes: [TmuxPane]) {
        self.id = name
        self.name = name
        self.windowCount = windowCount
        self.attached = attached
        self.panes = panes
    }
}

public struct TmuxPane: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let windowIndex: Int
    public let windowName: String
    public let title: String
    public let currentCommand: String
    public let pid: Int
    public let isActive: Bool

    public init(
        id: String,
        windowIndex: Int,
        windowName: String,
        title: String,
        currentCommand: String,
        pid: Int,
        isActive: Bool
    ) {
        self.id = id
        self.windowIndex = windowIndex
        self.windowName = windowName
        self.title = title
        self.currentCommand = currentCommand
        self.pid = pid
        self.isActive = isActive
    }
}

public struct TerminalTab: Codable, Equatable, Sendable {
    public let app: TerminalApp
    public let windowIndex: Int
    public let tabIndex: Int
    public let tty: String
    public let isActiveTab: Bool
    public let title: String
    public let sessionId: String?

    public init(
        app: TerminalApp,
        windowIndex: Int,
        tabIndex: Int,
        tty: String,
        isActiveTab: Bool,
        title: String,
        sessionId: String? = nil
    ) {
        self.app = app
        self.windowIndex = windowIndex
        self.tabIndex = tabIndex
        self.tty = tty
        self.isActiveTab = isActiveTab
        self.title = title
        self.sessionId = sessionId
    }
}

public enum TerminalWindowResolution: String, Codable, Sendable {
    case latticesTag
    case appWindowIndex
    case processTreeTTY
}

public enum TerminalConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

public enum TerminalCWDSource: String, Codable, Sendable {
    case interestingProcess
    case shell
}

public enum TerminalHarnessKind: String, Codable, Sendable {
    case claude
    case codex
}

public struct DetectedHarness: Codable, Equatable, Identifiable, Sendable {
    public let kind: TerminalHarnessKind
    public let pid: Int
    public let command: String
    public let args: String
    public let evidence: String

    public var id: String { "\(kind.rawValue):\(pid)" }

    public init(kind: TerminalHarnessKind, pid: Int, command: String, args: String, evidence: String) {
        self.kind = kind
        self.pid = pid
        self.command = command
        self.args = args
        self.evidence = evidence
    }
}

public enum TerminalFocusGranularity: String, Codable, Sendable {
    case window
    case tab
    case pane
    case none
}

public struct TerminalCapabilities: Codable, Equatable, Sendable {
    public let canFocus: Bool
    public let canPlace: Bool
    public let canCapturePane: Bool
    public let canResolveCwd: Bool
    public let focusGranularity: TerminalFocusGranularity
    public let requiresAutomation: Bool

    public init(
        canFocus: Bool,
        canPlace: Bool,
        canCapturePane: Bool,
        canResolveCwd: Bool,
        focusGranularity: TerminalFocusGranularity,
        requiresAutomation: Bool
    ) {
        self.canFocus = canFocus
        self.canPlace = canPlace
        self.canCapturePane = canCapturePane
        self.canResolveCwd = canResolveCwd
        self.focusGranularity = focusGranularity
        self.requiresAutomation = requiresAutomation
    }
}

public struct TerminalJoinProvenance: Codable, Equatable, Sendable {
    public let tty: TerminalConfidence
    public let cwd: TerminalConfidence?
    public let window: TerminalConfidence?
    public let tmux: TerminalConfidence?
    public let harness: TerminalConfidence?
    public let notes: [String]

    public init(
        tty: TerminalConfidence,
        cwd: TerminalConfidence?,
        window: TerminalConfidence?,
        tmux: TerminalConfidence?,
        harness: TerminalConfidence?,
        notes: [String] = []
    ) {
        self.tty = tty
        self.cwd = cwd
        self.window = window
        self.tmux = tmux
        self.harness = harness
        self.notes = notes
    }
}

public struct TerminalPaneCapture: Codable, Equatable, Sendable {
    public let text: String
    public let observedAt: Date
    public let lineLimit: Int
    public let lineCount: Int
    public let truncated: Bool

    public init(text: String, observedAt: Date, lineLimit: Int, lineCount: Int, truncated: Bool) {
        self.text = text
        self.observedAt = observedAt
        self.lineLimit = lineLimit
        self.lineCount = lineCount
        self.truncated = truncated
    }
}

public struct TerminalInstance: Codable, Equatable, Identifiable, Sendable {
    public let observedAt: Date
    public let stableKey: String
    public let tty: String
    public let app: TerminalApp?
    public let appName: String?
    public let appBundleIdentifier: String?
    public let appPid: Int32?
    public let windowIndex: Int?
    public let tabIndex: Int?
    public let isActiveTab: Bool
    public let tabTitle: String?
    public let terminalSessionId: String?
    public let processes: [ProcessEntry]
    public let detectedHarnesses: [DetectedHarness]
    public let shellPid: Int?
    public let cwd: String?
    public let cwdSource: TerminalCWDSource?
    public let tmuxSession: String?
    public let tmuxPaneId: String?
    public let windowId: UInt32?
    public let windowTitle: String?
    public let windowResolution: TerminalWindowResolution?
    public let focusHandle: String?
    public let placementHandle: String?
    public let capabilities: TerminalCapabilities
    public let provenance: TerminalJoinProvenance
    public let paneCapture: TerminalPaneCapture?

    public var id: String { tty }

    public var hasClaude: Bool {
        detectedHarnesses.contains { $0.kind == .claude }
    }

    public var hasCodex: Bool {
        detectedHarnesses.contains { $0.kind == .codex }
    }

    public var displayName: String {
        if let session = tmuxSession { return session }
        if let title = tabTitle, !title.isEmpty { return title }
        if let title = windowTitle, !title.isEmpty { return title }
        return tty
    }

    public init(
        observedAt: Date,
        stableKey: String,
        tty: String,
        app: TerminalApp?,
        appName: String?,
        appBundleIdentifier: String?,
        appPid: Int32?,
        windowIndex: Int?,
        tabIndex: Int?,
        isActiveTab: Bool,
        tabTitle: String?,
        terminalSessionId: String?,
        processes: [ProcessEntry],
        detectedHarnesses: [DetectedHarness],
        shellPid: Int?,
        cwd: String?,
        cwdSource: TerminalCWDSource?,
        tmuxSession: String?,
        tmuxPaneId: String?,
        windowId: UInt32?,
        windowTitle: String?,
        windowResolution: TerminalWindowResolution?,
        focusHandle: String?,
        placementHandle: String?,
        capabilities: TerminalCapabilities,
        provenance: TerminalJoinProvenance,
        paneCapture: TerminalPaneCapture? = nil
    ) {
        self.observedAt = observedAt
        self.stableKey = stableKey
        self.tty = tty
        self.app = app
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.appPid = appPid
        self.windowIndex = windowIndex
        self.tabIndex = tabIndex
        self.isActiveTab = isActiveTab
        self.tabTitle = tabTitle
        self.terminalSessionId = terminalSessionId
        self.processes = processes
        self.detectedHarnesses = detectedHarnesses
        self.shellPid = shellPid
        self.cwd = cwd
        self.cwdSource = cwdSource
        self.tmuxSession = tmuxSession
        self.tmuxPaneId = tmuxPaneId
        self.windowId = windowId
        self.windowTitle = windowTitle
        self.windowResolution = windowResolution
        self.focusHandle = focusHandle
        self.placementHandle = placementHandle
        self.capabilities = capabilities
        self.provenance = provenance
        self.paneCapture = paneCapture
    }
}

public struct TerminalInventorySnapshot: Codable, Equatable, Sendable {
    public let snapshotId: String
    public let observedAt: Date
    public let timestamp: Date
    public let terminals: [TerminalInstance]
    public let tmuxSessions: [TmuxSession]
    public let terminalTabs: [TerminalTab]
    public let terminalWindows: [TerminalWindow]

    public init(
        snapshotId: String,
        observedAt: Date,
        timestamp: Date,
        terminals: [TerminalInstance],
        tmuxSessions: [TmuxSession],
        terminalTabs: [TerminalTab],
        terminalWindows: [TerminalWindow]
    ) {
        self.snapshotId = snapshotId
        self.observedAt = observedAt
        self.timestamp = timestamp
        self.terminals = terminals
        self.tmuxSessions = tmuxSessions
        self.terminalTabs = terminalTabs
        self.terminalWindows = terminalWindows
    }
}

public struct TerminalInventoryOptions: Sendable {
    public var apps: [TerminalApp]
    public var additionalTerminalAppNames: [String]
    public var interestingCommands: Set<String>
    public var includePaneContent: Bool
    public var paneContentLineLimit: Int

    public init(
        apps: [TerminalApp] = TerminalApp.allCases,
        additionalTerminalAppNames: [String] = [],
        interestingCommands: Set<String> = ProcessQuery.defaultInterestingCommands,
        includePaneContent: Bool = false,
        paneContentLineLimit: Int = 120
    ) {
        self.apps = apps
        self.additionalTerminalAppNames = additionalTerminalAppNames
        self.interestingCommands = interestingCommands
        self.includePaneContent = includePaneContent
        self.paneContentLineLimit = paneContentLineLimit
    }
}

public enum LatticesTerminalTag {
    public static func windowTag(for session: String) -> String {
        "[lattices:\(session)]"
    }

    public static func extractSessionName(from title: String) -> String? {
        guard let range = title.range(of: #"\[lattices:([^\]]+)\]"#, options: .regularExpression) else {
            return nil
        }
        let match = String(title[range])
        return String(match.dropFirst(10).dropLast(1))
    }
}
