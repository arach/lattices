import DeckKit
import Foundation

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

    func sendTrackpad(
        event: DeckTrackpadEvent,
        dx: Double = 0,
        dy: Double = 0
    ) {
        guard let endpoint = preferredEndpoint(), let health else { return }

        Task {
            do {
                _ = try await client.trackpad(
                    endpoint: endpoint,
                    health: health,
                    request: DeckTrackpadEventRequest(event: event, dx: dx, dy: dy)
                )
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

        guard let activeEndpoint else { return }
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
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                await self.refreshSnapshot(endpoint: endpoint)
            }
        }
    }

    func preferredEndpoint(fallback: BridgeEndpoint? = nil) -> BridgeEndpoint? {
        if let activeEndpoint {
            return activeEndpoint
        }
        return fallback
    }

    func canonicalEndpoint(from endpoint: BridgeEndpoint, health: BridgeHealthResponse) -> BridgeEndpoint {
        let host = health.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return endpoint }
        return BridgeEndpoint(
            name: endpoint.name,
            host: host,
            port: Int(health.port),
            source: endpoint.source
        )
    }

    func candidateEndpoints(for preferred: BridgeEndpoint) -> [BridgeEndpoint] {
        var candidates: [BridgeEndpoint] = [preferred]

        if let health {
            let canonical = canonicalEndpoint(from: preferred, health: health)
            if !candidates.contains(canonical) {
                candidates.append(canonical)
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
