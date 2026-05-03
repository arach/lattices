import DeckKit
import Foundation

// MARK: - Live data adapter
//
// Builds Home view-models from real DeckStore + trusted-bridge state.
// - Active endpoint     → rich snapshot data (active, foreground, with scene/app/agent)
// - Discovered bridges  → online-and-pingable (sparse fields)
// - Trusted-but-offline → paired previously, currently unreachable
//
// Sections without a backend yet (terminal, calendar, scenes, routines, sync)
// pass through as empty arrays — their tiles/sections gate on emptiness.

@MainActor
enum HomeDataAdapter {

    static func machines(
        store: DeckStore,
        trustedBridges: [StoredBridgeTrust]
    ) -> [HomeMachine] {
        var result: [HomeMachine] = []
        var seen = Set<String>()

        if let endpoint = store.activeEndpoint {
            let key = nameKey(endpoint.name, host: endpoint.host)
            seen.insert(key)
            result.append(makeActive(endpoint: endpoint, snapshot: store.snapshot))
        }

        for bridge in store.discoveredBridges {
            let key = nameKey(bridge.name, host: bridge.host)
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(makeDiscovered(endpoint: bridge))
        }

        for trust in trustedBridges {
            let key = nameKey(trust.bridgeName, host: trust.bridgeName)
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(makeTrustedOffline(trust: trust))
        }

        return result
    }

    /// Recent activity tape — uses snapshot.history when available. Returns
    /// an empty array when there is no history; the tape hides itself rather
    /// than showing fake entries.
    static func recent(snapshot: DeckRuntimeSnapshot?, machineLabel: String) -> [HomeRecentEntry] {
        let history = snapshot?.history ?? []
        guard !history.isEmpty else { return [] }
        return history.prefix(8).map { entry in
            HomeRecentEntry(
                id: entry.id,
                kind: kind(for: entry.kind),
                title: entry.title,
                subtitle: entry.detail,
                target: machineLabel,
                agoLabel: agoLabel(from: entry.createdAt)
            )
        }
    }

    /// Agent feed — drawn from `snapshot.activityLog`. The narration tape that
    /// the Mac emits as the agent works (tag + tint + text). Empty when no log.
    static func agentFeed(snapshot: DeckRuntimeSnapshot?) -> [HomeAgentFeedEntry] {
        let log = snapshot?.activityLog ?? []
        guard !log.isEmpty else { return [] }
        return log.prefix(12).map { entry in
            HomeAgentFeedEntry(
                id: entry.id,
                glyph: glyph(forTag: entry.tag),
                text: entry.text,
                tint: latsTint(from: entry.tint)
            )
        }
    }

    /// Pending attention items — drawn from `snapshot.questions`. Each
    /// question becomes one row. Tint is amber for "needs decision".
    static func attention(snapshot: DeckRuntimeSnapshot?) -> [HomeAttentionItem] {
        let questions = snapshot?.questions ?? []
        guard !questions.isEmpty else { return [] }
        return questions.prefix(6).map { card in
            HomeAttentionItem(
                id: card.id,
                icon: "questionmark.circle",
                label: card.prompt,
                tint: .amber
            )
        }
    }

    /// Cloud aggregate — minimal wiring. `agentsRunning` is 1 when the
    /// cockpit is in agent mode, otherwise 0. Builds + last-deploy have no
    /// backend yet. The cloud strip self-hides when everything is zero/nil.
    static func cloud(snapshot: DeckRuntimeSnapshot?) -> HomeCloudStatus {
        let agentRunning = (snapshot?.cockpitMode?.mode == .agent) ? 1 : 0
        return HomeCloudStatus(
            agentsRunning: agentRunning,
            buildsQueued: 0,
            lastDeployAgo: nil
        )
    }

    /// Bottom bar telemetry — drawn from `snapshot.telemetry`. Returns
    /// `.empty` (which the bar treats as "hide cluster") when no telemetry.
    static func bottomTelemetry(
        snapshot: DeckRuntimeSnapshot?,
        machineLabel: String
    ) -> HomeBottomTelemetry {
        guard let tel = snapshot?.telemetry else { return .empty }
        let scene = snapshot?.desktop?.activeLayerName
            ?? snapshot?.desktop?.currentSpaceName
        let context: String
        if let scene, !scene.isEmpty {
            context = "\(machineLabel.lowercased()) ~ \(scene.lowercased())"
        } else {
            context = machineLabel.lowercased()
        }

        let displayCount = max(1, snapshot?.desktop?.screenCount ?? 1)
        let displayIndex = min(
            max(1, (snapshot?.desktop?.currentSpaceIndex ?? 0) + 1),
            displayCount
        )

        return HomeBottomTelemetry(
            contextLabel: context,
            windows: tel.windowCount,
            displayIndex: displayIndex,
            displayCount: displayCount,
            cpuPercent: percentInt(tel.cpuLoadPercent),
            memPercent: percentInt(tel.memoryUsedPercent),
            tempCelsius: tel.temperatureCelsius.map { Int($0.rounded()) }
        )
    }
}

// MARK: - Builders

private extension HomeDataAdapter {

    static func makeActive(
        endpoint: BridgeEndpoint,
        snapshot: DeckRuntimeSnapshot?
    ) -> HomeMachine {
        let displayName = endpoint.name.isEmpty ? endpoint.host : endpoint.name
        let host = displayHost(endpoint.host)

        let desktop = snapshot?.desktop
        let voice = snapshot?.voice
        let firstHistory = snapshot?.history.first
        let frontTitle = snapshot?.layout?.frontmostWindow?.title

        return HomeMachine(
            id: endpoint.id,
            name: displayName,
            host: host,
            icon: iconFor(displayName + " " + host),
            status: .active,
            isForeground: true,                     // assume the connected Mac is foreground
            scene: nonEmpty(desktop?.activeLayerName),
            focusedApp: nonEmpty(desktop?.activeAppName),
            focusedWindow: nonEmpty(frontTitle),
            lastAction: nonEmpty(firstHistory?.title),
            lastActionAgo: firstHistory.map { agoLabel(from: $0.createdAt) },
            agentState: agentState(for: voice),
            attentionCount: snapshot?.questions.count ?? 0,
            latencyMs: nil,
            metrics: metrics(from: snapshot?.telemetry)
        )
    }

    /// Map `DeckSystemTelemetry` onto the gauge struct. Returns nil if no
    /// telemetry sample exists, so the card hides its gauge cluster.
    static func metrics(from tel: DeckSystemTelemetry?) -> HomeMachineMetrics? {
        guard let tel else { return nil }
        return HomeMachineMetrics(
            cpuPercent: tel.cpuLoadPercent,
            gpuPercent: tel.gpuLoadPercent,
            memoryPercent: tel.memoryUsedPercent,
            thermalPercent: tel.thermalPressurePercent
        )
    }

    static func makeDiscovered(endpoint: BridgeEndpoint) -> HomeMachine {
        let displayName = endpoint.name.isEmpty ? endpoint.host : endpoint.name
        let host = displayHost(endpoint.host)
        return HomeMachine(
            id: endpoint.id,
            name: displayName,
            host: host,
            icon: iconFor(displayName + " " + host),
            status: .online,
            isForeground: false,
            scene: nil,
            focusedApp: nil,
            focusedWindow: nil,
            lastAction: nil,
            lastActionAgo: nil,
            agentState: .idle,
            attentionCount: 0,
            latencyMs: nil
        )
    }

    static func makeTrustedOffline(trust: StoredBridgeTrust) -> HomeMachine {
        HomeMachine(
            id: "trusted-\(trust.bridgePublicKey)",
            name: trust.bridgeName,
            host: "paired",
            icon: iconFor(trust.bridgeName),
            status: .offline,
            isForeground: false,
            scene: nil,
            focusedApp: nil,
            focusedWindow: nil,
            lastAction: nil,
            lastActionAgo: trust.pairedAt.timeIntervalSinceNow > -60
                ? "just now"
                : agoLabel(from: trust.pairedAt),
            agentState: .idle,
            attentionCount: 0,
            latencyMs: nil
        )
    }
}

// MARK: - Helpers

private extension HomeDataAdapter {

    /// Loose match: lowercase, strip `.local`, keep alphanumerics only.
    /// Used so a Bonjour discovery and a saved trust collapse into one entry
    /// even when the names differ slightly ("Arach's Mac mini" vs "mini").
    static func nameKey(_ name: String, host: String) -> String {
        let candidate = name.isEmpty ? host : name
        return candidate
            .lowercased()
            .replacingOccurrences(of: ".local", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    static func iconFor(_ hint: String) -> String {
        let s = hint.lowercased()
        if s.contains("mini")   { return "macmini" }
        if s.contains("studio") { return "macstudio" }
        if s.contains("imac")   { return "desktopcomputer" }
        if s.contains("air") || s.contains("book") || s.contains("pro") {
            return "laptopcomputer"
        }
        return "macwindow.and.iphone"
    }

    static func displayHost(_ host: String) -> String {
        host.replacingOccurrences(of: ".local", with: "")
            .replacingOccurrences(of: ".lan", with: "")
    }

    static func agentState(for voice: DeckVoiceState?) -> HomeAgentState {
        guard let voice else { return .idle }
        switch voice.phase {
        case .idle:         return .idle
        case .listening:    return .running(task: "listening")
        case .transcribing: return .running(task: "transcribing")
        case .reasoning:    return .running(task: "thinking")
        case .speaking:     return .running(task: "responding")
        }
    }

    static func kind(for historyKind: DeckHistoryKind) -> HomeRecentKind {
        switch historyKind {
        case .voice:      return .voice
        case .layout:     return .layout
        case .switcher:   return .switchAction
        case .automation: return .agent
        }
    }

    /// Map an activity-log tint string ("green", "violet", etc.) onto the
    /// design-system tint enum. Defaults to `.blue` for unknown / nil.
    static func latsTint(from rawTint: String?) -> LatsTint {
        guard let raw = rawTint?.lowercased(), !raw.isEmpty else { return .blue }
        return LatsTint(rawValue: raw) ?? .blue
    }

    /// Pick a glyph for an activity-log entry based on its tag string.
    /// Tags like "DONE" / "OK" → ✓, "WAIT" / "PENDING" → ⏳, others → •.
    static func glyph(forTag tag: String) -> String {
        let t = tag.lowercased()
        if t.contains("done") || t.contains("ok") || t.contains("ready") || t.contains("complete") {
            return "\u{2713}"
        }
        if t.contains("wait") || t.contains("pending") || t.contains("running") || t.contains("listen") {
            return "\u{23F3}"
        }
        return "\u{2022}"
    }

    /// Round a 0…100 percent (Double?) to an Int, clamped to [0, 100].
    /// Treats nil as 0 — caller decides whether telemetry is shown at all.
    static func percentInt(_ p: Double?) -> Int {
        guard let p else { return 0 }
        return min(100, max(0, Int(p.rounded())))
    }

    static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return s
    }

    static func agoLabel(from date: Date) -> String {
        let seconds = max(1, Int(-date.timeIntervalSinceNow))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        return "\(weeks)w"
    }
}
