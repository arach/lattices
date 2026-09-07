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
    /// Live load gauges. nil when the machine isn't reporting telemetry
    /// (offline / standby / discovered-but-not-paired).
    var metrics: HomeMachineMetrics? = nil
    /// Whether this host's microphone is open right now. Per-machine because
    /// with a fleet, "a mic is live" is not useful without "on which one".
    var voice: HomeVoiceActivity = .off
    /// Whether there is a live authenticated session behind this card.
    /// A host can be trusted and visible on the network without one, and
    /// offering a mic we cannot actually route to is worse than offering
    /// none — the tap would look accepted and do nothing.
    var hasLiveSession: Bool = true
}

/// What a host's voice runtime is doing, reduced to what the roster needs.
///
/// Deliberately not `DeckVoicePhase` — the card only needs to distinguish
/// "your microphone is open on that machine" from "it is busy thinking" from
/// "nothing". Keeping the view model free of the wire enum also keeps the
/// mock fixtures free of DeckKit.
enum HomeVoiceActivity: Equatable {
    /// Nothing running.
    case off
    /// The microphone is open. This is the state that must never be subtle.
    case listening
    /// Captured, now transcribing / reasoning / speaking. Mic is closed.
    case working
}

/// Per-machine load metrics surfaced as gauges. All fields are 0…100
/// percentages and any may be nil if that signal isn't available.
struct HomeMachineMetrics: Equatable {
    let cpuPercent: Double?
    let gpuPercent: Double?
    let memoryPercent: Double?
    let thermalPercent: Double?
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

struct HomeAgentFeedEntry: Identifiable, Equatable {
    let id: String
    let glyph: String         // "✓", "⏳", "•"
    let text: String
    let tint: LatsTint
    /// Consecutive identical-signature lines collapsed into this row.
    var repeatCount: Int = 1
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
            latencyMs: 14,
            metrics: HomeMachineMetrics(
                cpuPercent: 39,
                gpuPercent: 12,
                memoryPercent: 67,
                thermalPercent: 28
            )
        ),
        HomeMachine(
            id: "arach-mini",
            name: "arach-mini",
            host: "mini.local",
            icon: "macmini",
            status: .online,
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

    static let recent: [HomeRecentEntry] = [
        HomeRecentEntry(id: "r1", kind: .command, title: "tile chrome two-up right", subtitle: "voice · 3 windows moved", target: "laptop", agoLabel: "2m"),
        HomeRecentEntry(id: "r2", kind: .voice,   title: "“open shell in the lats…”", subtitle: "agent · iTerm 2",         target: "laptop", agoLabel: "14m"),
        HomeRecentEntry(id: "r3", kind: .layout,  title: "snap left",                  subtitle: "iTerm 2 · display 1",      target: "laptop", agoLabel: "1h"),
        HomeRecentEntry(id: "r4", kind: .layout,  title: "restored layout · …",        subtitle: "5 windows · 2 displays",   target: "mini",   agoLabel: "3h"),
        HomeRecentEntry(id: "r5", kind: .switchAction, title: "next window · Codex",   subtitle: "act.08 · keyboard",        target: "laptop", agoLabel: "yesterday"),
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

    static let agentFeed: [HomeAgentFeedEntry] = [
        HomeAgentFeedEntry(id: "f1", glyph: "✓", text: "designed home arch", tint: .green),
        HomeAgentFeedEntry(id: "f2", glyph: "⏳", text: "writing tile spec",   tint: .violet),
        HomeAgentFeedEntry(id: "f3", glyph: "•", text: "12 tools used · 4m",  tint: .blue),
    ]

}
