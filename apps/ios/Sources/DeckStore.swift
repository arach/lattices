import DeckKit
import Foundation

/// How aggressively the store should pull snapshots from the Mac. Two
/// presets, mapped to interval values inside `DeckStore`:
/// - `.fast`    → ~1s (active engagement: Deck open, voice in flight)
/// - `.ambient` → ~5s (passive observation: Home idle)
enum DeckPollPriority {
    case fast
    case ambient
}

@MainActor
final class DeckStore: ObservableObject {
    @Published private(set) var discoveredBridges: [BridgeEndpoint] = []
    @Published private(set) var activeEndpoint: BridgeEndpoint?
    @Published private(set) var health: BridgeHealthResponse?
    @Published private(set) var manifest: DeckManifest?
    @Published private(set) var snapshot: DeckRuntimeSnapshot?
    @Published private(set) var lastActionResult: DeckActionResult?
    @Published private(set) var lastActionLabel: String?
    @Published private(set) var isPerformingAction = false
    @Published var selectedPageID = "voice"
    @Published var selectedCockpitPageID = "main"
    @Published var manualHost = ""
    @Published var manualPort = "5287"
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let client = DeckBridgeClient()
    private let discovery = BridgeDiscovery()
    private var pollingTask: Task<Void, Never>?

    /// UI hint for how aggressively to poll. Hosts flip this to `.fast` when
    /// the user is actively engaged (Deck open, voice panel open, recording)
    /// and back to `.ambient` when they're just looking at Home idle.
    /// The store will *also* go fast on its own if the snapshot reports voice
    /// activity or pending questions, so callers don't have to be exhaustive.
    private var uiPriority: DeckPollPriority = .ambient

    var connectionLabel: String {
        // Prefer human-readable names (Bonjour service name / health-reported name)
        // over raw hosts/UUIDs which look like "F8B453FB-…" in the UI.
        if let endpointName = activeEndpoint?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !endpointName.isEmpty,
           !looksLikeUUID(endpointName) {
            return endpointName
        }
        if let healthName = health?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !healthName.isEmpty,
           !looksLikeUUID(healthName) {
            return healthName
        }
        if let endpointHost = activeEndpoint?.host.trimmingCharacters(in: .whitespacesAndNewlines),
           !endpointHost.isEmpty {
            return endpointHost
                .replacingOccurrences(of: ".local", with: "")
                .replacingOccurrences(of: ".lan", with: "")
        }
        return "Mac"
    }

    private func looksLikeUUID(_ s: String) -> Bool {
        // Crude check: 32+ hex/dash chars, no spaces. Matches "F8B453FB-F2AD-4194-…"
        let hex = CharacterSet(charactersIn: "0123456789ABCDEFabcdef-")
        return s.count >= 16 && s.unicodeScalars.allSatisfy { hex.contains($0) }
    }

    init() {
        discovery.onUpdate = { [weak self] bridges in
            Task { @MainActor [weak self] in
                self?.handleDiscoveryUpdate(bridges)
            }
        }
        discovery.start()
    }

    deinit {
        pollingTask?.cancel()
        discovery.stop()
    }

    func refreshDiscovery() {
        discovery.refresh()
    }

    func connect(to endpoint: BridgeEndpoint) {
        activeEndpoint = endpoint
        manualHost = endpoint.host
        manualPort = String(endpoint.port)
        errorMessage = nil
        lastActionResult = nil
        lastActionLabel = nil
        isPerformingAction = false

        Task {
            await loadConnection(endpoint: endpoint, forceManifest: true)
        }
    }

    func connectManually() {
        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            errorMessage = "Enter a Mac host name or Bonjour address."
            return
        }

        guard let port = Int(manualPort), port > 0 else {
            errorMessage = "Enter a valid bridge port."
            return
        }

        connect(to: BridgeEndpoint(name: host, host: host, port: port, source: "Manual"))
    }

    func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
        activeEndpoint = nil
        health = nil
        manifest = nil
        snapshot = nil
        lastActionResult = nil
        lastActionLabel = nil
        isPerformingAction = false
    }

    func refreshSnapshot() {
        guard let endpoint = activeEndpoint else { return }
        Task {
            await refreshSnapshot(endpoint: endpoint)
        }
    }

    /// Tell the store the user is actively engaged (or no longer engaged)
    /// so it can speed up / slow down snapshot polling. Idempotent — call as
    /// often as needed from `.onAppear` / `.onChange` hooks. The store will
    /// independently go fast for in-snapshot signals (voice, attention) so
    /// callers don't need to be perfect.
    func setUIPriority(_ priority: DeckPollPriority) {
        uiPriority = priority
    }

    func perform(
        actionID: String,
        pageID: String? = nil,
        payload: [String: DeckValue] = [:],
        label: String? = nil
    ) {
        let actionLabel = label ?? actionID
        guard let endpoint = preferredEndpoint(), let health else { return }

        Task {
            do {
                lastActionLabel = actionLabel
                isPerformingAction = true
                let request = DeckActionRequest(pageID: pageID, actionID: actionID, payload: payload)
                let result = try await performWithFallback(request: request, preferred: endpoint, health: health)
                lastActionResult = result
                if let runtimeSnapshot = result.runtimeSnapshot {
                    snapshot = runtimeSnapshot
                }
                try? await Task.sleep(for: .milliseconds(350))
                await refreshSnapshot(endpoint: endpoint)
                errorMessage = nil
            } catch {
                lastActionResult = nil
                errorMessage = error.localizedDescription
            }
            isPerformingAction = false
        }
    }

    // MARK: - Voice (relay)
    //
    // The iPad never captures audio. These thin wrappers fire `voice.command.*`
    // on the active Mac via the same /deck/perform bridge other actions use.
    // Live phase + transcript + errors stream back through `snapshot.voice` on
    // the existing polling cadence — no separate event channel needed.

    var voiceState: DeckVoiceState? { snapshot?.voice }

    func startVoice() {
        perform(actionID: "voice.command.start", pageID: "home", label: "voice")
    }

    func stopVoice() {
        perform(actionID: "voice.command.stop", pageID: "home", label: "voice")
    }

    func toggleVoice() {
        perform(actionID: "voice.command.toggle", pageID: "home", label: "voice")
    }

    func sendTrackpad(
        event: DeckTrackpadEvent,
        dx: Double = 0,
        dy: Double = 0
    ) {
        guard let endpoint = preferredEndpoint(), let health else { return }

        Task {
            do {
                let result = try await client.trackpad(
                    endpoint: endpoint,
                    health: health,
                    request: DeckTrackpadEventRequest(event: event, dx: dx, dy: dy)
                )
                if !result.ok {
                    errorMessage = "Trackpad input was rejected. Check that the Mac bridge is enabled and has Accessibility permission."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private extension DeckStore {
    func handleDiscoveryUpdate(_ bridges: [BridgeEndpoint]) {
        discoveredBridges = bridges

        if activeEndpoint == nil, let first = bridges.first {
            connect(to: first)
            return
        }

        guard let activeEndpoint, activeEndpoint.source == "Bonjour" else { return }
        if let replacement = bridges.first(where: { bridge in
            bridge.name == activeEndpoint.name && bridge.port == activeEndpoint.port && bridge.host != activeEndpoint.host
        }) {
            self.activeEndpoint = replacement
            manualHost = replacement.host
        }
    }

    func loadConnection(endpoint: BridgeEndpoint, forceManifest: Bool) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let healthResponse = try await client.health(endpoint: endpoint)
            health = healthResponse
            let resolvedEndpoint = canonicalEndpoint(from: endpoint, health: healthResponse)
            activeEndpoint = resolvedEndpoint
            manualHost = resolvedEndpoint.host
            manualPort = String(resolvedEndpoint.port)
            if forceManifest || manifest == nil {
                manifest = try await client.manifest(endpoint: resolvedEndpoint)
                if let firstPage = manifest?.pages.first(where: { $0.id == selectedPageID }) ?? manifest?.pages.first {
                    selectedPageID = firstPage.id
                }
            }
            try await ensurePairing(endpoint: resolvedEndpoint, health: healthResponse)
            snapshot = try await client.snapshot(endpoint: resolvedEndpoint, health: healthResponse)
            if let firstCockpitPage = snapshot?.cockpit?.pages.first(where: { $0.id == selectedCockpitPageID }) ?? snapshot?.cockpit?.pages.first {
                selectedCockpitPageID = firstCockpitPage.id
            }
            errorMessage = nil
            startPolling(endpoint: resolvedEndpoint)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshSnapshot(endpoint: BridgeEndpoint) async {
        do {
            let target = preferredEndpoint(fallback: endpoint) ?? endpoint
            guard let health else { return }
            snapshot = try await client.snapshot(endpoint: target, health: health)
            if let firstCockpitPage = snapshot?.cockpit?.pages.first(where: { $0.id == selectedCockpitPageID }) ?? snapshot?.cockpit?.pages.first {
                selectedCockpitPageID = firstCockpitPage.id
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startPolling(endpoint: BridgeEndpoint) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.currentPollInterval ?? 5.0
                try? await Task.sleep(for: .seconds(interval))
                guard let self else { return }
                await self.refreshSnapshot(endpoint: endpoint)
            }
        }
    }

    /// Decide the next poll interval based on UI hint + last snapshot.
    /// Voice activity, pending attention, or an explicit `.fast` UI hint
    /// pull us into 1s mode; otherwise we sip at 5s. Intervals are
    /// re-evaluated each tick so the loop adapts as state changes.
    private var currentPollInterval: TimeInterval {
        if uiPriority == .fast { return 1.0 }
        if let voice = snapshot?.voice {
            if voice.phase != .idle { return 1.0 }
            if voice.error != nil   { return 1.0 }
        }
        if !(snapshot?.questions.isEmpty ?? true) { return 1.0 }
        return 5.0
    }

    func preferredEndpoint(fallback: BridgeEndpoint? = nil) -> BridgeEndpoint? {
        if let activeEndpoint {
            return activeEndpoint
        }
        return fallback
    }

    func canonicalEndpoint(from endpoint: BridgeEndpoint, health: BridgeHealthResponse) -> BridgeEndpoint {
        let healthName = health.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointHost = endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines)
        return BridgeEndpoint(
            name: healthName.isEmpty ? endpoint.name : healthName,
            host: endpointHost.isEmpty ? endpoint.host : endpointHost,
            port: Int(health.port),
            source: endpoint.source
        )
    }

    func reportedEndpoint(from endpoint: BridgeEndpoint, health: BridgeHealthResponse) -> BridgeEndpoint? {
        let host = health.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host != endpoint.host else { return nil }
        let healthName = health.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return BridgeEndpoint(
            name: healthName.isEmpty ? endpoint.name : healthName,
            host: host,
            port: Int(health.port),
            source: "Health"
        )
    }

    func candidateEndpoints(for preferred: BridgeEndpoint) -> [BridgeEndpoint] {
        var candidates: [BridgeEndpoint] = [preferred]

        if let health {
            let canonical = canonicalEndpoint(from: preferred, health: health)
            if !candidates.contains(canonical) {
                candidates.append(canonical)
            }
            if let reported = reportedEndpoint(from: preferred, health: health),
               !candidates.contains(reported) {
                candidates.append(reported)
            }
        }

        for bridge in discoveredBridges where bridge.name == preferred.name && bridge.port == preferred.port {
            if !candidates.contains(bridge) {
                candidates.append(bridge)
            }
        }

        return candidates
    }

    func performWithFallback(
        request: DeckActionRequest,
        preferred: BridgeEndpoint,
        health: BridgeHealthResponse
    ) async throws -> DeckActionResult {
        var lastError: Error?

        for candidate in candidateEndpoints(for: preferred) {
            do {
                let result = try await client.perform(endpoint: candidate, health: health, request: request)
                if activeEndpoint != candidate {
                    activeEndpoint = candidate
                    manualHost = candidate.host
                    manualPort = String(candidate.port)
                }
                return result
            } catch {
                lastError = error
            }
        }

        throw lastError ?? DeckBridgeClientError.invalidResponse
    }

    func ensurePairing(endpoint: BridgeEndpoint, health: BridgeHealthResponse) async throws {
        guard manifest?.security.requestSigningRequired == true else { return }
        let security = DeckBridgeSecurityStore.shared
        guard security.isTrusted(health: health) == false else { return }

        let pairing = try await client.pair(endpoint: endpoint)
        switch pairing.disposition {
        case .approved, .alreadyTrusted:
            security.storePairing(pairing)
        case .denied:
            throw DeckBridgeClientError.badStatus(403, pairing.detail ?? "Pairing was denied on the Mac.")
        }
    }
}
