import DeckKit
import Foundation

/// Projects live `DeckStore` snapshots onto the design's channel model.
///
/// The mapping follows the design's premise — a channel describes an *agent*
/// working on a Mac, not the Mac itself — so the agent plan drives the task and
/// step list, `snapshot.questions` drives the blocked ("needs you") state, and
/// the activity log drives both the per-channel tape and the fleet feed.
@MainActor
enum FleetDeckAdapter {

    static func channels(from stores: [DeckStore]) -> [FleetChannel] {
        stores.enumerated().map { index, store in channel(from: store, index: index) }
    }

    static func channel(from store: DeckStore, index: Int) -> FleetChannel {
        let snapshot = store.snapshot
        let name = store.connectionLabel
        let question = snapshot?.questions.first
        let agentRows = snapshot?.cockpitMode?.agentRows ?? []
        let log = snapshot?.activityLog ?? []

        // `.attn` means exactly one thing: an agent is blocked on a human
        // decision. It must not be reachable any other way — it is what sorts a
        // channel to the front of the strip and what `focusAttention()` hunts
        // for, so anything else wearing it sends the user somewhere with
        // nothing to answer. `DeckStore.errorMessage` in particular covers
        // everything from a lost connection to a single rejected trackpad
        // gesture; it reports as `fault`, never as state.
        let state: FleetChannelState = {
            if question != nil { return .attn }
            if snapshot == nil { return .down }
            if snapshot?.cockpitMode?.mode == .agent { return .run }
            if agentRows.contains(where: { $0.state == .live }) { return .run }
            return .idle
        }()

        let liveRow = agentRows.first { $0.state == .live }
        let task: String = {
            if let question { return question.detail ?? question.prompt }
            if let liveRow { return liveRow.text }
            if let error = store.errorMessage { return error }
            if let layer = snapshot?.desktop?.activeLayerName { return "Standing by on \(layer)." }
            return "No agent running on this Mac."
        }()

        return FleetChannel(
            id: store.sessionID.uuidString,
            channelLabel: "CH \(String(format: "%02d", index + 1))",
            deviceName: name,
            deviceIcon: FleetDeviceIcon.infer(from: name),
            appName: snapshot?.layout?.frontmostWindow?.appName
                ?? snapshot?.desktop?.activeAppName
                ?? "—",
            fileName: snapshot?.layout?.frontmostWindow?.title
                ?? snapshot?.desktop?.currentSpaceName
                ?? "",
            agentName: log.first?.tag.uppercased() ?? "AGENT",
            hue: index,
            state: state,
            task: task,
            steps: steps(from: agentRows, isBlocked: question != nil),
            output: output(store: store, log: log),
            decision: question.map { decision(from: $0) },
            lastEventText: log.first?.text ?? "no activity yet",
            lastEventTime: log.first.map { relativeTime(since: $0.createdAt) } ?? "—",
            fault: store.errorMessage,
            cpu: snapshot?.telemetry?.cpuLoadPercent.map { Int($0.rounded()) },
            mem: snapshot?.telemetry?.memoryUsedPercent.map { Int($0.rounded()) },
            latency: nil,
            logLines: logLines(from: log, channel: index),
            logSource: "~/lats/ch\(String(format: "%02d", index + 1))/agent.log",
            logLineCount: log.count
        )
    }

    /// The fleet feed is every Mac's activity log merged newest-first, which is
    /// what the design's right-hand column shows.
    static func feed(from stores: [DeckStore], channels: [FleetChannel]) -> [FleetFeedEvent] {
        var events: [(FleetFeedEvent, Date)] = []

        for (index, store) in stores.enumerated() {
            guard channels.indices.contains(index) else { continue }
            let isBlocked = channels[index].state == .attn

            if let question = store.snapshot?.questions.first {
                events.append((
                    FleetFeedEvent(
                        id: "q-\(store.sessionID)-\(question.id)",
                        time: "now",
                        channelIndex: index,
                        agent: channels[index].agentName,
                        text: "needs your call · \(question.prompt)",
                        kind: .attn
                    ),
                    .now
                ))
            }

            let entries = store.snapshot?.activityLog ?? []
            for (entryIndex, entry) in entries.enumerated() {
                events.append((
                    FleetFeedEvent(
                        id: "\(store.sessionID)-\(entry.id)",
                        time: relativeTime(since: entry.createdAt),
                        channelIndex: index,
                        agent: entry.tag.uppercased(),
                        text: entry.text,
                        // The newest line on a blocked channel is the one the
                        // design brightens.
                        kind: isBlocked && entryIndex == 0 ? .hot : .normal
                    ),
                    entry.createdAt
                ))
            }
        }

        return events
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// A Mac's advertised cockpit pages become the command bay's sets. Falls
    /// back to the design's canonical four when the bridge advertises none.
    static func sets(from store: DeckStore?) -> [FleetCommandSet] {
        let pages = store?.snapshot?.cockpit?.pages ?? []
        guard !pages.isEmpty else { return FleetCommandSet.canonical }
        return pages.map(FleetCommandSet.init(page:))
    }

    // MARK: Pieces

    private static func steps(from rows: [DeckAgentPlanRow], isBlocked: Bool) -> [FleetStep] {
        rows.enumerated().map { index, row in
            let state: FleetStepState
            switch row.state {
            case .done: state = .done
            case .live: state = isBlocked ? .blocked : .now
            case .next: state = .queued
            }
            return FleetStep(id: index, state: state, text: row.text)
        }
    }

    private static func output(store: DeckStore, log: [DeckActivityLogEntry]) -> String {
        if let error = store.errorMessage { return error }
        if let summary = store.snapshot?.voice?.responseSummary, !summary.isEmpty { return summary }
        if let replay = store.snapshot?.cockpitMode?.replayMessage, !replay.isEmpty { return replay }
        if log.count > 1 { return log[1].text }
        return log.first?.text ?? "Nothing reported yet."
    }

    private static func decision(from card: DeckQuestionCard) -> FleetDecision {
        let keys = ["A", "B", "C", "D"]
        return FleetDecision(
            question: card.prompt,
            options: card.options.enumerated().map { index, option in
                FleetDecisionOption(
                    id: option.id,
                    key: index < keys.count ? keys[index] : "\(index + 1)",
                    title: option.title,
                    detail: option.detail ?? "",
                    verb: "SEND",
                    actionID: option.actionID,
                    resolvedTask: "Applying: \(option.title).",
                    resolvedOutput: "Sent to the Mac — waiting for the agent to pick it up.",
                    feedText: "answered · \(option.title)"
                )
            }
        )
    }

    private static func logLines(from log: [DeckActivityLogEntry], channel: Int) -> [FleetLogLine] {
        // The design's log screen reads bottom-up (newest last), the opposite of
        // the activity log's newest-first order.
        log.reversed().enumerated().map { index, entry in
            FleetLogLine(
                id: "\(channel)-\(entry.id)",
                time: clockTime(entry.createdAt),
                tag: entry.tag.lowercased(),
                message: entry.text,
                style: index == log.count - 1 ? .highlight : .normal
            )
        }
    }

    // MARK: Formatting

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func clockTime(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    /// The design's compact age stamps: 4s, 12s, 2m, 9m, 1h.
    static func relativeTime(since date: Date) -> String {
        let seconds = max(0, Int(Date.now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86_400)d"
    }
}
