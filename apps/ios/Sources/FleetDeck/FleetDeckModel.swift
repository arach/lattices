import DeckKit
import SwiftUI

// MARK: - Channel

/// Mirrors the design's three channel states. The design leads with what the
/// agent is doing, not what the Mac is: a channel is `attn` when its agent is
/// blocked on a human decision, which is the only state that reorders the strip.
enum FleetChannelState: String {
    case run, attn, idle, down

    var label: String {
        switch self {
        case .run:  return "RUNNING"
        case .attn: return "NEEDS YOU"
        case .idle: return "IDLE"
        case .down: return "UNREACHABLE"
        }
    }
}

/// `.chan-ic` — the three machine silhouettes the design draws.
enum FleetDeviceIcon: String {
    case laptop, studio, mini

    var symbol: String {
        switch self {
        case .laptop: return "laptopcomputer"
        case .studio: return "desktopcomputer"
        case .mini:   return "macmini"
        }
    }

    /// Best-effort match on the Mac's advertised name.
    static func infer(from name: String) -> FleetDeviceIcon {
        let lowered = name.lowercased()
        if lowered.contains("studio") || lowered.contains("imac") { return .studio }
        if lowered.contains("mini") { return .mini }
        return .laptop
    }
}

/// Design step states: `1` done, `2` running, `3` blocked on you, `0` queued.
enum FleetStepState {
    case done, now, blocked, queued
}

struct FleetStep: Identifiable {
    let id: Int
    var state: FleetStepState
    var text: String
}

struct FleetDecisionOption: Identifiable {
    let id: String
    /// The keyboard letter shown in the `kbd` chip — A, B, …
    var key: String
    var title: String
    var detail: String
    /// The verb on the right edge of the row: APPLY / PUSH / HOLD.
    var verb: String
    /// Bridge action fired when the option is picked. `nil` in the design fixture.
    var actionID: String?
    /// What the console reads once this option is taken.
    var resolvedTask: String
    var resolvedOutput: String
    var feedText: String
}

struct FleetDecision {
    var question: String
    var options: [FleetDecisionOption]
}

struct FleetChannel: Identifiable {
    let id: String
    var channelLabel: String
    var deviceName: String
    var deviceIcon: FleetDeviceIcon
    var appName: String
    var fileName: String
    var agentName: String
    /// 0-based index into `FleetV6.agentHues`.
    var hue: Int
    var state: FleetChannelState
    var task: String
    var steps: [FleetStep]
    var output: String
    var decision: FleetDecision?
    var lastEventText: String
    var lastEventTime: String
    /// Last transport or action failure, if any. Deliberately *not* folded into
    /// `state`: a rejected trackpad gesture is not an agent asking you a
    /// question, and conflating them hijacks the deck's triage.
    var fault: String? = nil
    var cpu: Int?
    var mem: Int?
    var latency: String?
    var logLines: [FleetLogLine]
    var logSource: String
    var logLineCount: Int

    /// `.chan-foot` right edge — "CPU 24% · 14ms".
    var footerMetrics: String {
        var parts: [String] = []
        if let cpu { parts.append("CPU \(cpu)%") }
        if let latency { parts.append(latency) }
        else if let mem { parts.append("MEM \(mem)%") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Feed

enum FleetFeedKind {
    case normal, hot, attn
}

struct FleetFeedEvent: Identifiable {
    let id: String
    var time: String
    /// Index into `FleetDeckModel.channels`.
    var channelIndex: Int
    var agent: String
    var text: String
    var kind: FleetFeedKind
}

enum FleetFeedFilter {
    case all, attention
}

// MARK: - Log

enum FleetLogStyle {
    case normal, dim, highlight, warn
}

struct FleetLogLine: Identifiable {
    let id: String
    var time: String
    var tag: String
    var message: String
    var style: FleetLogStyle
}

// MARK: - Command bay

struct FleetCommandTile: Identifiable {
    let id: String
    var title: String
    /// The uppercase caption under the title — "01 · spawn".
    var meta: String
    var symbol: String
    var actionID: String?
    var payload: [String: DeckValue] = [:]
    var isEnabled: Bool = true
    var col: Int? = nil
    var row: Int? = nil
    var colSpan: Int = 1
    var rowSpan: Int = 1
}

struct FleetCommandSet: Identifiable {
    let id: String
    var key: String
    var columns: Int = 4
    var rows: Int? = nil
    var tiles: [FleetCommandTile]
}

// MARK: - Layout

/// The design's two body layouts. `ops` is the default four-up triage view;
/// `focus` collapses the channel strip to a switcher rail and gives one Mac's
/// log the full panel.
enum FleetDeckLayout: String {
    case ops, focus

    var label: String {
        switch self {
        case .ops:   return "AGENT OPS"
        case .focus: return "FOCUS"
        }
    }
}

// MARK: - Model

/// Holds everything the deck renders plus the selection/triage logic the design
/// spells out in JS: attention-first channel ordering, "answer here, then jump
/// to the next blocker", and the optimistic console flip after a decision.
@MainActor
final class FleetDeckModel: ObservableObject {
    @Published private(set) var channels: [FleetChannel] = []
    @Published private(set) var feed: [FleetFeedEvent] = []
    @Published var sets: [FleetCommandSet] = FleetCommandSet.canonical

    @Published var currentIndex = 0
    /// Voice routing target. `channels.count` means ALL.
    @Published var routeIndex = 0
    @Published var setIndex = 0
    @Published var feedFilter: FleetFeedFilter = .all
    @Published var layout: FleetDeckLayout = .ops
    @Published private(set) var lastResolvedIndex: Int?

    /// Set for the design fixture so decisions resolve locally instead of being
    /// dispatched to a Mac.
    private(set) var isFixture = false

    /// Cleared once the deck has picked its opening channel.
    private var needsInitialSelection = true

    /// A host the presenter asked us to open on, held until a matching channel
    /// exists. Honored once, then cleared — after that the user's taps win.
    private var pendingHostID: String?

    init() {}

    // MARK: Derived

    var current: FleetChannel? {
        channels.indices.contains(currentIndex) ? channels[currentIndex] : nil
    }

    /// The identity of whatever is on deck. This — not `currentIndex` — is what
    /// callers should resolve a host against; indices shift as channels come and
    /// go, and nothing guarantees channel order matches any other collection's.
    var currentHostID: String? { current?.id }

    var attentionIndices: [Int] {
        channels.indices.filter { channels[$0].state == .attn }
    }

    /// Blocked channels promote to the front of the strip — the design's only
    /// triage affordance beyond the status dot.
    var channelOrder: [Int] {
        let blocked = channels.indices.filter { channels[$0].state == .attn }
        let rest = channels.indices.filter { channels[$0].state != .attn }
        return blocked + rest
    }

    var visibleFeed: [FleetFeedEvent] {
        switch feedFilter {
        case .all: return feed
        case .attention: return feed.filter { $0.kind == .attn }
        }
    }

    var routeLabel: String {
        guard channels.indices.contains(routeIndex) else { return "ALL" }
        return channels[routeIndex].channelLabel
    }

    var activeSet: FleetCommandSet? {
        sets.indices.contains(setIndex) ? sets[setIndex] : nil
    }

    // MARK: Selection

    func select(_ index: Int) {
        guard channels.indices.contains(index), index != currentIndex else { return }
        // A deliberate tap retires any host request still waiting to land, so a
        // late arrival cannot yank the user off the channel they just chose.
        pendingHostID = nil
        currentIndex = index
        routeIndex = index
    }

    /// Put a specific host on deck. Used when the deck is opened from somewhere
    /// that already knows which Mac the user meant — tapping one on Home, say.
    /// An explicit request outranks the "open on what needs you" default: the
    /// user named a Mac, so triage does not get to override them.
    func requestHost(_ hostID: String?) {
        guard let hostID else { return }
        needsInitialSelection = false
        if let index = channels.firstIndex(where: { $0.id == hostID }) {
            currentIndex = index
            routeIndex = index
            pendingHostID = nil
        } else {
            // The channel may not exist yet — its store is still connecting.
            pendingHostID = hostID
        }
    }

    /// Jump to the next channel that is blocked on a decision, skipping `from`.
    func nextBlocker(from index: Int) -> Int? {
        attentionIndices.first { $0 != index }
    }

    /// The status-bar ATTN chip: hop to the first blocker, or the next one if
    /// you are already standing on a blocker.
    func focusAttention() {
        let blocked = attentionIndices
        guard !blocked.isEmpty else { return }
        if blocked.contains(currentIndex) {
            if let next = nextBlocker(from: currentIndex) { select(next) }
        } else if let first = blocked.first {
            select(first)
        }
    }

    // MARK: Decisions

    /// Answer a channel's open question. The console flips to the chosen branch
    /// immediately and the deck moves on to the next blocker, so the user never
    /// has to go looking for what is waiting.
    func resolve(channelIndex: Int, optionIndex: Int, dispatch: ((FleetDecisionOption) -> Void)? = nil) {
        guard channels.indices.contains(channelIndex),
              let decision = channels[channelIndex].decision,
              decision.options.indices.contains(optionIndex)
        else { return }

        let option = decision.options[optionIndex]
        dispatch?(option)

        var channel = channels[channelIndex]
        channel.decision = nil
        channel.state = .run
        channel.task = option.resolvedTask
        channel.output = option.resolvedOutput
        channel.steps = channel.steps.map { step in
            guard step.state == .blocked else { return step }
            var resolved = step
            resolved.state = .done
            resolved.text = "You chose: \(option.title)"
            return resolved
        }
        if let queued = channel.steps.firstIndex(where: { $0.state == .queued }) {
            channel.steps[queued].state = .now
        }
        channel.lastEventText = option.feedText
        channel.lastEventTime = "now"
        channels[channelIndex] = channel

        feed.removeAll { $0.channelIndex == channelIndex && $0.kind == .attn }
        feed.insert(
            FleetFeedEvent(
                id: "resolved-\(channelIndex)-\(option.id)",
                time: "now",
                channelIndex: channelIndex,
                agent: channel.agentName,
                text: option.feedText,
                kind: .hot
            ),
            at: 0
        )

        lastResolvedIndex = channelIndex

        if let next = nextBlocker(from: channelIndex) {
            currentIndex = next
            routeIndex = next
        } else if feedFilter == .attention {
            feedFilter = .all
        }
    }

    func deferDecision() {
        if let next = nextBlocker(from: currentIndex) { select(next) }
    }

    // MARK: Ingest

    /// Replace the deck's contents from live snapshots, holding the user's
    /// place: selection follows the channel it was on, not its position.
    /// Command sets are deliberately *not* ingested here. They belong to whichever
    /// Mac is on deck, and selection can change inside this call — deriving them
    /// from the pre-ingest host is how a tile advertised by one Mac ends up
    /// dispatched to another. The controller sets them once selection settles.
    func ingest(channels newChannels: [FleetChannel], feed newFeed: [FleetFeedEvent]) {
        let previousID = channels.indices.contains(currentIndex) ? channels[currentIndex].id : nil
        channels = newChannels
        feed = newFeed

        if let pendingHostID, let index = newChannels.firstIndex(where: { $0.id == pendingHostID }) {
            // The host the presenter asked for has finally shown up.
            currentIndex = index
            routeIndex = index
            self.pendingHostID = nil
            needsInitialSelection = false
        } else if needsInitialSelection, !newChannels.isEmpty {
            // "The deck opens on what needs you."
            currentIndex = newChannels.firstIndex { $0.state == .attn } ?? 0
            routeIndex = currentIndex
            needsInitialSelection = false
        } else if let previousID, let index = newChannels.firstIndex(where: { $0.id == previousID }) {
            currentIndex = index
        } else {
            currentIndex = min(currentIndex, max(0, newChannels.count - 1))
        }
        routeIndex = min(routeIndex, newChannels.count)
        setIndex = min(setIndex, max(0, sets.count - 1))
        if lastResolvedIndex.map({ !newChannels.indices.contains($0) }) ?? false {
            lastResolvedIndex = nil
        }
    }

    func loadFixture() {
        isFixture = true
        channels = FleetDeckFixture.channels
        feed = FleetDeckFixture.feed
        sets = FleetCommandSet.canonical
        // "The deck opens on what needs you" — the design boots on CH 03.
        currentIndex = 2
        routeIndex = 2
        needsInitialSelection = false
    }
}
