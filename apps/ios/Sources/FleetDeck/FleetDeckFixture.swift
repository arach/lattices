import Foundation

/// The design's own `CHANS` / `FEED` / `LOGS` data, carried over verbatim so the
/// deck can be rendered and reviewed against the source artifact without a Mac
/// on the network. Used by `FleetDeckPreviewHost` (`--fleet-preview`) and by
/// SwiftUI previews; never by a live deck.
enum FleetDeckFixture {

    static let channels: [FleetChannel] = [
        FleetChannel(
            id: "ch01",
            channelLabel: "CH 01",
            deviceName: "Arach MacBook Pro",
            deviceIcon: .laptop,
            appName: "Xcode",
            fileName: "FleetDeckScreen.swift",
            agentName: "CODEX",
            hue: 0,
            state: .run,
            task: "Polishing the common deck layout — spacing pass on control tiles.",
            steps: [
                FleetStep(id: 0, state: .done, text: "Read design notes + current layout"),
                FleetStep(id: 1, state: .done, text: "Retuned tile grid to 4-up"),
                FleetStep(id: 2, state: .now, text: "Adjusting key-row shadows"),
                FleetStep(id: 3, state: .queued, text: "Post diff for review")
            ],
            output: "Rebuilt tile bay at 150px; contrast on tile-meta bumped to pass at arm’s length.",
            decision: nil,
            lastEventText: "polishing common deck",
            lastEventTime: "12s",
            cpu: 24,
            mem: 52,
            latency: "14ms",
            logLines: logLines(0),
            logSource: "~/lats/ch01/agent.log",
            logLineCount: 2100
        ),
        FleetChannel(
            id: "ch02",
            channelLabel: "CH 02",
            deviceName: "Studio",
            deviceIcon: .studio,
            appName: "iTerm2",
            fileName: "simulator · 12/18",
            agentName: "TESTER",
            hue: 1,
            state: .run,
            task: "Running the simulator suite across three device profiles.",
            steps: [
                FleetStep(id: 0, state: .done, text: "Booted 3 simulators"),
                FleetStep(id: 1, state: .done, text: "Unit suite green · 212/212"),
                FleetStep(id: 2, state: .now, text: "UI suite running · 12/18"),
                FleetStep(id: 3, state: .queued, text: "Publish results to feed")
            ],
            output: "FleetDeckScreenTests: 12 of 18 passing so far, no flakes.",
            decision: nil,
            lastEventText: "UI suite 12/18",
            lastEventTime: "4s",
            cpu: 35,
            mem: 59,
            latency: "11ms",
            logLines: logLines(1),
            logSource: "~/lats/ch02/agent.log",
            logLineCount: 2237
        ),
        FleetChannel(
            id: "ch03",
            channelLabel: "CH 03",
            deviceName: "Mac mini",
            deviceIcon: .mini,
            appName: "Figma",
            fileName: "lane model v3",
            agentName: "SCOUT",
            hue: 2,
            state: .attn,
            task: "Lane model review is blocked — two naming options need your call.",
            steps: [
                FleetStep(id: 0, state: .done, text: "Mapped interaction lanes"),
                FleetStep(id: 1, state: .done, text: "Drafted two naming schemes"),
                FleetStep(id: 2, state: .blocked, text: "Waiting on your pick"),
                FleetStep(id: 3, state: .queued, text: "Apply across screens")
            ],
            output: "Option A: route/lane/bus. Option B: channel/track/send. Say the word.",
            decision: FleetDecision(
                question: "Which naming scheme should I apply across all screens?",
                options: [
                    FleetDecisionOption(
                        id: "ch03-a",
                        key: "A",
                        title: "route / lane / bus",
                        detail: "matches the audio-desk metaphor",
                        verb: "APPLY",
                        actionID: nil,
                        resolvedTask: "Applying route/lane/bus naming across 14 screens.",
                        resolvedOutput: "Renaming in progress — 6 of 14 screens updated, no conflicts.",
                        feedText: "applying naming A · route/lane/bus"
                    ),
                    FleetDecisionOption(
                        id: "ch03-b",
                        key: "B",
                        title: "channel / track / send",
                        detail: "matches the deck labels",
                        verb: "APPLY",
                        actionID: nil,
                        resolvedTask: "Applying channel/track/send naming across 14 screens.",
                        resolvedOutput: "Renaming in progress — 6 of 14 screens updated, matches deck labels.",
                        feedText: "applying naming B · channel/track/send"
                    )
                ]
            ),
            lastEventText: "awaiting your review",
            lastEventTime: "2m",
            cpu: 46,
            mem: 66,
            latency: "18ms",
            logLines: logLines(2),
            logSource: "~/lats/ch03/agent.log",
            logLineCount: 2374
        ),
        FleetChannel(
            id: "ch04",
            channelLabel: "CH 04",
            deviceName: "Build Mac",
            deviceIcon: .laptop,
            appName: "Safari",
            fileName: "ci dashboard",
            agentName: "BUILD",
            hue: 3,
            state: .attn,
            task: "Build 412 is signed and staged — needs your go before it ships.",
            steps: [
                FleetStep(id: 0, state: .done, text: "Build 412 succeeded"),
                FleetStep(id: 1, state: .done, text: "Artifacts signed + uploaded"),
                FleetStep(id: 2, state: .blocked, text: "Waiting on ship approval"),
                FleetStep(id: 3, state: .queued, text: "Push to TestFlight")
            ],
            output: "412 is clean: 0 warnings, 212/212 tests. Ship it or hold?",
            decision: FleetDecision(
                question: "Push build 412 to TestFlight now?",
                options: [
                    FleetDecisionOption(
                        id: "ch04-a",
                        key: "A",
                        title: "Ship it",
                        detail: "notify the fleet when live",
                        verb: "PUSH",
                        actionID: nil,
                        resolvedTask: "Pushing build 412 to TestFlight and notifying the fleet.",
                        resolvedOutput: "Upload started — processing usually takes about 8 minutes.",
                        feedText: "shipping build 412 → TestFlight"
                    ),
                    FleetDecisionOption(
                        id: "ch04-b",
                        key: "B",
                        title: "Hold for nightly",
                        detail: "roll it into the 02:00 batch",
                        verb: "HOLD",
                        actionID: nil,
                        resolvedTask: "Holding 412 — queued behind tonight’s nightly batch.",
                        resolvedOutput: "412 parked. Nightly kicks off at 02:00 and will pick it up.",
                        feedText: "held build 412 for nightly"
                    )
                ]
            ),
            lastEventText: "awaiting ship approval",
            lastEventTime: "9m",
            cpu: 8,
            mem: 31,
            latency: "12ms",
            logLines: logLines(3),
            logSource: "~/lats/ch04/agent.log",
            logLineCount: 2511
        )
    ]

    static let feed: [FleetFeedEvent] = [
        event(0, "4s", 1, "TESTER", "UI suite 12/18 · no flakes", .normal),
        event(1, "12s", 0, "CODEX", "tile bay rebuilt · diff staged", .hot),
        event(2, "31s", 1, "TESTER", "unit suite green · 212/212", .normal),
        event(3, "48s", 0, "CODEX", "key-row shadow pass started", .normal),
        event(4, "1m", 2, "SCOUT", "needs your call · lane naming", .attn),
        event(5, "2m", 3, "BUILD", "needs your go · ship build 412", .attn),
        event(6, "2m", 0, "CODEX", "read design notes · started task", .normal),
        event(7, "3m", 2, "SCOUT", "drafted naming schemes A/B", .normal),
        event(8, "5m", 1, "TESTER", "booted 3 simulators", .normal),
        event(9, "9m", 3, "BUILD", "build 412 signed · 0 warnings", .normal)
    ]

    private static func event(
        _ index: Int,
        _ time: String,
        _ channel: Int,
        _ agent: String,
        _ text: String,
        _ kind: FleetFeedKind
    ) -> FleetFeedEvent {
        FleetFeedEvent(id: "fx-\(index)", time: time, channelIndex: channel, agent: agent, text: text, kind: kind)
    }

    // MARK: Logs

    private static let rawLogs: [[(String, String, String, FleetLogStyle)]] = [
        [
            ("09:40:38", "agent", "picked up task · deck layout polish", .dim),
            ("09:40:41", "fs", "watching 24 files in FleetDeck/", .dim),
            ("09:40:44", "agent", "read design notes · 6 constraints", .normal),
            ("09:40:51", "layout", "measuring tile bay at arm’s length", .dim),
            ("09:40:57", "layout", "row pitch 128 → 150px", .normal),
            ("09:41:02", "xcodebuild", "Compiling FleetDeckScreen.swift", .dim),
            ("09:41:04", "layout", "tile grid → 4 columns, pitch 150px", .normal),
            ("09:41:07", "layout", "contrast(tile-meta) 3.1 → 4.6 · pass", .normal),
            ("09:41:09", "xcodebuild", "Build succeeded · 0 warnings", .dim),
            ("09:41:12", "agent", "shadow pass · key row, 3 of 5 layers", .highlight),
            ("09:41:14", "diff", "+142 −38 · 2 files staged", .normal),
            ("09:41:15", "agent", "waiting for review before commit", .dim)
        ],
        [
            ("09:40:12", "agent", "picked up task · simulator suite", .dim),
            ("09:40:18", "simctl", "erasing stale devices · 3 removed", .dim),
            ("09:40:24", "simctl", "Booted iPhone SE · iOS 18.2", .dim),
            ("09:40:27", "xctest", "discovering test bundles", .dim),
            ("09:40:29", "xctest", "230 cases across 4 targets", .normal),
            ("09:40:31", "simctl", "Booted iPhone 15 Pro · iOS 18.2", .dim),
            ("09:40:33", "simctl", "Booted iPad Pro 11″ · iOS 18.2", .dim),
            ("09:40:35", "xctest", "FleetDeckUnitTests · 212/212 passed", .normal),
            ("09:40:52", "xctest", "FleetDeckScreenTests · starting 18 cases", .dim),
            ("09:41:03", "xctest", "case 09 testChannelSwitch · 0.41s", .normal),
            ("09:41:08", "xctest", "case 12 testDecisionRoute · 0.36s", .normal),
            ("09:41:11", "agent", "12 of 18 green · no flakes detected", .highlight)
        ],
        [
            ("09:38:31", "agent", "picked up task · lane model review", .dim),
            ("09:38:40", "figma", "fetching lane model v3", .dim),
            ("09:38:47", "figma", "14 frames · 62 layers", .normal),
            ("09:38:55", "agent", "diffing against v2 naming", .dim),
            ("09:38:58", "agent", "9 labels differ", .normal),
            ("09:39:02", "figma", "opened lane model v3 · 14 frames", .dim),
            ("09:39:20", "agent", "mapped 6 interaction lanes", .normal),
            ("09:39:44", "agent", "naming scheme A · route / lane / bus", .normal),
            ("09:39:46", "agent", "naming scheme B · channel / track / send", .normal),
            ("09:39:47", "agent", "conflict: deck labels already say channel", .warn),
            ("09:39:48", "agent", "blocked · needs a human decision", .warn),
            ("09:41:15", "agent", "idle 2m · holding 14 frames unrenamed", .dim)
        ],
        [
            ("09:31:40", "agent", "nightly queue drained · 0 pending", .dim),
            ("09:31:52", "git", "fetched origin/main · 4 commits", .dim),
            ("09:32:01", "ci", "resolving package graph", .dim),
            ("09:32:05", "ci", "cache hit · restored 1.2 GB", .normal),
            ("09:32:08", "ci", "build 412 queued", .normal),
            ("09:32:10", "ci", "build 412 · archive started", .dim),
            ("09:33:58", "ci", "archive succeeded in 1m48s", .normal),
            ("09:34:02", "codesign", "signed with Developer ID · valid", .dim),
            ("09:34:19", "ci", "artifacts uploaded · 84.2 MB", .normal),
            ("09:34:20", "ci", "tests 212/212 · warnings 0", .highlight),
            ("09:34:21", "agent", "ship gate · needs approval to push", .warn),
            ("09:41:15", "agent", "holding · nightly window opens 02:00", .dim)
        ]
    ]

    private static func logLines(_ channel: Int) -> [FleetLogLine] {
        rawLogs[channel].enumerated().map { index, line in
            FleetLogLine(
                id: "log-\(channel)-\(index)",
                time: line.0,
                tag: line.1,
                message: line.2,
                style: line.3
            )
        }
    }
}
