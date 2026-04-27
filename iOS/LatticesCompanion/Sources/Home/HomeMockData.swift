import SwiftUI

// MARK: - Home view models
//
// These are UI-facing types for the Home (passive single-pane-of-glass) surface.
// Decoupled from DeckRuntimeSnapshot so sections can preview standalone.
// Real data flows through adapters at integration time.

enum HomeMachineStatus {
    case active   // online + paired + foreground (the human is here)
    case online   // online + paired
    case standby  // paired but idle / asleep-ish
    case offline  // paired but unreachable

    var label: String {
        switch self {
        case .active: return "ACTIVE"
        case .online: return "ONLINE"
        case .standby: return "STANDBY"
        case .offline: return "OFFLINE"
        }
    }

    var tint: Color {
        switch self {
        case .active: return LatsPalette.green
        case .online: return LatsPalette.blue
        case .standby: return LatsPalette.amber
        case .offline: return LatsPalette.textFaint
        }
    }
}

enum HomeAgentState: Equatable {
    case idle
    case running(task: String)
    case waiting(message: String)

    var label: String {
        switch self {
        case .idle: return "idle"
        case .running(let task): return task
        case .waiting(let msg): return msg
        }
    }

    var tint: Color {
        switch self {
        case .idle: return LatsPalette.textFaint
        case .running: return LatsPalette.violet
        case .waiting: return LatsPalette.amber
        }
    }
}

struct HomeMachine: Identifiable, Equatable {
    let id: String
    let name: String          // display name e.g. "arach-laptop"
    let host: String          // host e.g. "laptop.local"
    let icon: String          // SF Symbol
    let status: HomeMachineStatus
    let isForeground: Bool    // is this the Mac the user is physically at?
    let scene: String?        // current scene name if known
    let focusedApp: String?   // foreground app
    let focusedWindow: String?// foreground window title
    let lastAction: String?   // last action label
    let lastActionAgo: String?// "2m" / "1h"
    let agentState: HomeAgentState
    let attentionCount: Int   // pending attention items
    let latencyMs: Int?       // ping latency in ms
}

// MARK: - Scenes (layout presets — instant, deterministic)

struct HomeScene: Identifiable, Equatable {
    let id: String
    let name: String          // "Deep Work"
    let tint: LatsTint
    let summary: String       // "5 win · 2 disp"
    let targetHints: [String] // e.g. ["Cur", "iTm", "Chr"]
    let hotkey: String?       // "⌘1"
}

// MARK: - Routines (agent recipes — multi-step, may pause)

struct HomeRoutine: Identifiable, Equatable {
    let id: String
    let name: String
    let stepPreview: String   // "Open Zoom > Tile Linear right > Mute Slack > Start 15m timer"
    let lastRun: String?      // "yesterday · 9:30"
    let isAgentic: Bool
    let hotkey: String?       // "^vs"
}

// MARK: - Recent activity

enum HomeRecentKind: String {
    case command, voice, layout, switchAction, agent, scene

    var dotColor: Color {
        switch self {
        case .command: return LatsPalette.red
        case .voice:   return LatsPalette.red
        case .layout:  return LatsPalette.green
        case .switchAction: return LatsPalette.blue
        case .agent:   return LatsPalette.violet
        case .scene:   return LatsPalette.teal
        }
    }

    var label: String {
        switch self {
        case .command: return "command"
        case .voice: return "voice"
        case .layout: return "layout"
        case .switchAction: return "switch"
        case .agent: return "agent"
        case .scene: return "scene"
        }
    }
}

struct HomeRecentEntry: Identifiable, Equatable {
    let id: String
    let kind: HomeRecentKind
    let title: String         // primary text
    let subtitle: String?     // "voice · 3 windows moved"
    let target: String?       // machine name
    let agoLabel: String      // "2m"
}

// MARK: - Sync / broadcast actions

struct HomeSyncAction: Identifiable, Equatable {
    let id: String
    let title: String         // "Sync clipboards"
    let subtitle: String      // brief description
    let icon: String          // SF Symbol
    let hotkey: String?       // "^v"
}

// MARK: - Cloud aggregate state

struct HomeCloudStatus: Equatable {
    let agentsRunning: Int
    let buildsQueued: Int
    let lastDeployAgo: String?
}

// MARK: - Foreground machine overflow content

struct HomeAttentionItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let label: String
    let tint: LatsTint
}

struct HomeCalendarEvent: Identifiable, Equatable {
    let id: String
    let timeLabel: String     // "3:00pm"
    let title: String
}

struct HomeAgentFeedEntry: Identifiable, Equatable {
    let id: String
    let glyph: String         // "✓", "⏳", "•"
    let text: String
    let tint: LatsTint
}

struct HomeTerminalLine: Identifiable, Equatable {
    let id: String
    let text: String
    let isPrompt: Bool        // dim styling
}

// MARK: - Sample data
//
// Every section's #Preview should pull from here so the whole Home renders
// coherently and section diffs only touch one entry point.

enum HomeMock {

    // Foreground machine + 1 background + 1 standby + 1 cloud — the canonical fleet
    static let fleet: [HomeMachine] = [
        HomeMachine(
            id: "arach-laptop",
            name: "arach-laptop",
            host: "laptop.local",
            icon: "laptopcomputer",
            status: .active,
            isForeground: true,
            scene: "Deep Work",
            focusedApp: "VS Code",
            focusedWindow: "HomeView.swift",
            lastAction: "regrid layout",
            lastActionAgo: "2m",
            agentState: .running(task: "writing tile spec"),
            attentionCount: 3,
            latencyMs: 14
        ),
        HomeMachine(
            id: "arach-mini",
            name: "arach-mini",
            host: "mini.local",
            icon: "macmini",
            status: .standby,
            isForeground: false,
            scene: "Wind Down",
            focusedApp: "Music",
            focusedWindow: "Now Playing",
            lastAction: "sync clipboard",
            lastActionAgo: "12m",
            agentState: .idle,
            attentionCount: 0,
            latencyMs: 8
        ),
        HomeMachine(
            id: "arach-studio",
            name: "arach-studio",
            host: "studio.local",
            icon: "macstudio",
            status: .online,
            isForeground: false,
            scene: "Code Review",
            focusedApp: "Cursor",
            focusedWindow: "Plan.md",
            lastAction: "scene apply",
            lastActionAgo: "1m",
            agentState: .running(task: "review pass"),
            attentionCount: 1,
            latencyMs: 22
        ),
        HomeMachine(
            id: "codex-cluster",
            name: "codex-cluster",
            host: "remote",
            icon: "server.rack",
            status: .offline,
            isForeground: false,
            scene: nil,
            focusedApp: nil,
            focusedWindow: nil,
            lastAction: nil,
            lastActionAgo: "yesterday",
            agentState: .idle,
            attentionCount: 0,
            latencyMs: nil
        ),
    ]

    // Smaller fleets for adaptive previews
    static let fleetOne: [HomeMachine]   = Array(fleet.prefix(1))
    static let fleetTwo: [HomeMachine]   = Array(fleet.prefix(2))
    static let fleetFour: [HomeMachine]  = fleet
    static let fleetEmpty: [HomeMachine] = []

    static let scenes: [HomeScene] = [
        HomeScene(id: "deep",   name: "Deep Work",   tint: .green,  summary: "3 win · 1 disp", targetHints: ["Cur", "Not", "Thi"], hotkey: "⌘1"),
        HomeScene(id: "review", name: "Code Review", tint: .blue,   summary: "5 win · 2 disp", targetHints: ["Cur", "iTm", "Chr"], hotkey: "⌘2"),
        HomeScene(id: "rsrch",  name: "Research",    tint: .teal,   summary: "6 win · 2 disp", targetHints: ["Chr", "Saf", "Not"], hotkey: "⌘3"),
        HomeScene(id: "mtg",    name: "Meeting",     tint: .amber,  summary: "2 win · 1 disp", targetHints: ["Zoo", "Not"],         hotkey: "⌘4"),
        HomeScene(id: "stream", name: "Stream",      tint: .pink,   summary: "4 win · 2 disp", targetHints: ["OBS", "Chr", "Dis"], hotkey: "⌘5"),
        HomeScene(id: "wind",   name: "Wind Down",   tint: .violet, summary: "2 win · 1 disp", targetHints: ["Saf", "Spo"],         hotkey: "⌘6"),
    ]

    static let routines: [HomeRoutine] = [
        HomeRoutine(
            id: "standup",
            name: "Standup setup",
            stepPreview: "Open Zoom > Tile Linear right > Mute Slack > Start 15m timer",
            lastRun: "yesterday · 9:30",
            isAgentic: false,
            hotkey: "^vs"
        ),
        HomeRoutine(
            id: "pull-all",
            name: "Pull all repos",
            stepPreview: "Scan ~/dev > git pull > Report stale branches",
            lastRun: "2h ago",
            isAgentic: true,
            hotkey: nil
        ),
        HomeRoutine(
            id: "screenshots",
            name: "Screenshot cleanup",
            stepPreview: "Move to ~/Pictures/Inbox > OCR > Tag by app",
            lastRun: "3d ago",
            isAgentic: true,
            hotkey: nil
        ),
        HomeRoutine(
            id: "eod",
            name: "End of day",
            stepPreview: "Save layout > Close non-essentials > Push WIP > Status to Linear",
            lastRun: "Friday · 18:42",
            isAgentic: true,
            hotkey: "^vq"
        ),
    ]

    static let recent: [HomeRecentEntry] = [
        HomeRecentEntry(id: "r1", kind: .command, title: "tile chrome two-up right", subtitle: "voice · 3 windows moved", target: "laptop", agoLabel: "2m"),
        HomeRecentEntry(id: "r2", kind: .voice,   title: "“open shell in the lats…”", subtitle: "agent · iTerm 2",         target: "laptop", agoLabel: "14m"),
        HomeRecentEntry(id: "r3", kind: .layout,  title: "snap left",                  subtitle: "iTerm 2 · display 1",      target: "laptop", agoLabel: "1h"),
        HomeRecentEntry(id: "r4", kind: .layout,  title: "restored layout · …",        subtitle: "5 windows · 2 displays",   target: "mini",   agoLabel: "3h"),
        HomeRecentEntry(id: "r5", kind: .switchAction, title: "next window · Codex",   subtitle: "act.08 · keyboard",        target: "laptop", agoLabel: "yesterday"),
    ]

    static let sync: [HomeSyncAction] = [
        HomeSyncAction(id: "s1", title: "Sync clipboards",  subtitle: "Share the latest copy across every target",    icon: "doc.on.clipboard",  hotkey: "^v"),
        HomeSyncAction(id: "s2", title: "Mirror project",   subtitle: "Open the same repo and branch on each target", icon: "square.on.square",  hotkey: nil),
        HomeSyncAction(id: "s3", title: "Pull all repos",   subtitle: "git pull across every dev workspace, in parallel", icon: "arrow.triangle.2.circlepath", hotkey: nil),
        HomeSyncAction(id: "s4", title: "DND everywhere",   subtitle: "Silence notifications, hide the dock, focus layouts", icon: "bell.slash", hotkey: nil),
        HomeSyncAction(id: "s5", title: "Snapshot layouts", subtitle: "Save current window layout on each target",       icon: "square.grid.2x2", hotkey: nil),
    ]

    static let cloud = HomeCloudStatus(
        agentsRunning: 2,
        buildsQueued: 1,
        lastDeployAgo: "4m"
    )

    static let attention: [HomeAttentionItem] = [
        HomeAttentionItem(id: "a1", icon: "exclamationmark.triangle", label: "4 stale browser tabs",        tint: .amber),
        HomeAttentionItem(id: "a2", icon: "internaldrive",            label: "build cache 8.2 GB",          tint: .blue),
        HomeAttentionItem(id: "a3", icon: "bubble.left",              label: "Slack: 3 dms",                tint: .pink),
    ]

    static let calendar: [HomeCalendarEvent] = [
        HomeCalendarEvent(id: "c1", timeLabel: "3:00pm", title: "standup"),
        HomeCalendarEvent(id: "c2", timeLabel: "4:30pm", title: "design review"),
        HomeCalendarEvent(id: "c3", timeLabel: "6:00pm", title: "gym"),
    ]

    static let agentFeed: [HomeAgentFeedEntry] = [
        HomeAgentFeedEntry(id: "f1", glyph: "✓", text: "designed home arch", tint: .green),
        HomeAgentFeedEntry(id: "f2", glyph: "⏳", text: "writing tile spec",   tint: .violet),
        HomeAgentFeedEntry(id: "f3", glyph: "•", text: "12 tools used · 4m",  tint: .blue),
    ]

    static let terminal: [HomeTerminalLine] = [
        HomeTerminalLine(id: "t1", text: "~/dev/lattices",            isPrompt: true),
        HomeTerminalLine(id: "t2", text: "$ swift build -c release", isPrompt: false),
        HomeTerminalLine(id: "t3", text: "Compiling DeckKit…",        isPrompt: false),
        HomeTerminalLine(id: "t4", text: "Compiling Sources…",        isPrompt: false),
    ]
}
