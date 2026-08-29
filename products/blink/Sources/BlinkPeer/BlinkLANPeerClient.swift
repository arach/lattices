@preconcurrency import MultipeerConnectivity

import BlinkCore
import CryptoKit
import Foundation

/// Discovers Blink Macs, completes the encrypted pairing handshake, and then
/// exposes the app-level `BlinkPeerTransport` snapshot boundary.
public final class BlinkLANPeerClient: NSObject, BlinkPeerTransport, @unchecked Sendable {
    private struct PendingConnection {
        var attemptID: UUID
        var candidateID: String
        var continuation: CheckedContinuation<Void, any Error>
    }

    private struct DiscoveredPeer {
        var peer: MCPeerID
        var hostID: String
        var hostPublicKey: Data
    }

    private let identity: BlinkPeerClientIdentity
    private let peerID: MCPeerID
    private var session: MCSession
    private let browser: MCNearbyServiceBrowser
    private let lock = NSLock()
    private var peersByID: [String: DiscoveredPeer] = [:]
    private var pendingConnection: PendingConnection?
    private var activeAttemptID: UUID?
    private var pendingResponses: [UUID: CheckedContinuation<BlinkPeerResponse, any Error>] = [:]
    private var connectedPeer: MCPeerID?
    private var connectionPrivateKey: Curve25519.KeyAgreement.PrivateKey?
    private var connectionKey: SymmetricKey?
    /// The host-scoped credential for the current connection. Every data-bearing
    /// request re-presents it, so the Mac never has to trust `MCPeerID`.
    private var connectionCredential: String?
    private var pairedHostStorage: BlinkPeerHost?
    private var connectionObserver: (@Sendable (Bool) -> Void)?
    private var browsingFailureStorage: String?

    public var pairedHost: BlinkPeerHost? {
        lock.withLock { pairedHostStorage }
    }

    public var browsingFailure: String? {
        lock.withLock { browsingFailureStorage }
    }

    public init(identity: BlinkPeerClientIdentity) {
        self.identity = identity
        var displayName = identity.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayName.isEmpty { displayName = "Mobile device" }
        while displayName.utf8.count > 60 { displayName.removeLast() }
        let peerID = MCPeerID(displayName: displayName)
        self.peerID = peerID
        self.session = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        self.browser = MCNearbyServiceBrowser(peer: peerID, serviceType: BlinkLANPeerServer.serviceType)
        super.init()
        session.delegate = self
        browser.delegate = self
    }

    deinit {
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    public func startBrowsing() {
        lock.withLock { browsingFailureStorage = nil }
        browser.startBrowsingForPeers()
    }

    public func stopBrowsing() {
        browser.stopBrowsingForPeers()
    }

    public func observeConnection(_ observer: @escaping @Sendable (Bool) -> Void) {
        lock.withLock { connectionObserver = observer }
    }

    public func availablePeers() -> [BlinkLANPeerCandidate] {
        lock.withLock {
            peersByID.map {
                BlinkLANPeerCandidate(
                    id: $0.key,
                    name: $0.value.peer.displayName,
                    hostID: $0.value.hostID,
                    publicKey: $0.value.hostPublicKey.base64EncodedString()
                )
            }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    @discardableResult
    public func connect(to candidateID: String) async throws -> BlinkPeerHost {
        let discovered = try lock.withLock { () throws -> DiscoveredPeer in
            guard let peer = peersByID[candidateID] else { throw BlinkPeerError.peerUnavailable }
            return peer
        }

        failAllPending(with: BlinkPeerError.connectionFailed("A newer connection replaced this session."))
        let attemptID = UUID()
        let nextSession = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        nextSession.delegate = self
        let previousSession = lock.withLock { () -> MCSession in
            let previous = session
            session = nextSession
            activeAttemptID = attemptID
            pairedHostStorage = nil
            return previous
        }
        previousSession.disconnect()

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let responseKey = try BlinkPeerCrypto.symmetricKey(
            privateKey: privateKey,
            peerPublicKey: discovered.hostPublicKey
        )
        let securedIdentity = BlinkPeerClientIdentity(
            credential: BlinkPeerCrypto.credential(
                seed: identity.credential,
                hostPublicKey: discovered.hostPublicKey
            ),
            name: identity.name
        )
        let installed = lock.withLock { () -> Bool in
            guard activeAttemptID == attemptID, session === nextSession else { return false }
            connectionPrivateKey = privateKey
            connectionKey = responseKey
            connectionCredential = securedIdentity.credential
            return true
        }
        guard installed else {
            nextSession.disconnect()
            throw BlinkPeerError.connectionFailed("A newer connection replaced this attempt.")
        }

        do {
            try await waitForConnection(
                to: discovered.peer,
                candidateID: candidateID,
                attemptID: attemptID,
                using: nextSession
            )
            let response = try await request(
                .requestAccess(securedIdentity),
                timeout: .seconds(90),
                expectedAttemptID: attemptID,
                expectedSession: nextSession
            )
            switch response {
            case .accessGranted(let host):
                guard host.id == discovered.hostID,
                      host.publicKey == discovered.hostPublicKey.base64EncodedString()
                else { throw BlinkPeerError.invalidResponse }
                let stillCurrent = lock.withLock { () -> Bool in
                    guard activeAttemptID == attemptID, session === nextSession else {
                        return false
                    }
                    pairedHostStorage = host
                    return true
                }
                guard stillCurrent else {
                    throw BlinkPeerError.connectionFailed("A newer connection replaced this attempt.")
                }
                notifyConnectionObserver(isConnected: true)
                return host
            case .failure(let failure) where failure.code == "access-denied":
                nextSession.disconnect()
                throw BlinkPeerError.accessDenied
            case .failure(let failure):
                throw BlinkPeerError.remoteFailure(code: failure.code, message: failure.message)
            case .snapshot:
                throw BlinkPeerError.invalidResponse
            }
        } catch {
            nextSession.disconnect()
            throw error
        }
    }

    public func disconnect() {
        let currentSession = lock.withLock { () -> MCSession in
            pairedHostStorage = nil
            return session
        }
        failAllPending(with: BlinkPeerError.connectionFailed("The session disconnected."))
        currentSession.disconnect()
        notifyConnectionObserver(isConnected: false)
    }

    public func fetchSnapshot(ifNoneMatch etag: String?) async throws -> BlinkSnapshotFetchResult {
        let credential = lock.withLock { () -> String? in
            pairedHostStorage == nil ? nil : connectionCredential
        }
        guard let credential else { throw BlinkPeerError.unauthorized }
        let response = try await request(
            .fetchSnapshot(credential: credential, ifNoneMatch: etag)
        )
        switch response {
        case .snapshot(let result): return result
        case .failure(let failure) where failure.code == "unauthorized":
            throw BlinkPeerError.unauthorized
        case .failure(let failure):
            throw BlinkPeerError.remoteFailure(code: failure.code, message: failure.message)
        case .accessGranted:
            throw BlinkPeerError.invalidResponse
        }
    }

    private func waitForConnection(
        to peer: MCPeerID,
        candidateID: String,
        attemptID: UUID,
        using session: MCSession
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let registered = lock.withLock { () -> Bool in
                guard activeAttemptID == attemptID, self.session === session else {
                    return false
                }
                pendingConnection = PendingConnection(
                    attemptID: attemptID,
                    candidateID: candidateID,
                    continuation: continuation
                )
                return true
            }
            guard registered else {
                continuation.resume(
                    throwing: BlinkPeerError.connectionFailed("A newer connection replaced this attempt.")
                )
                return
            }
            browser.invitePeer(peer, to: session, withContext: nil, timeout: 12)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                self?.timeOutConnection(attemptID: attemptID)
            }
        }
    }

    private func request(
        _ request: BlinkPeerRequest,
        timeout: Duration = .seconds(12),
        expectedAttemptID: UUID? = nil,
        expectedSession: MCSession? = nil
    ) async throws -> BlinkPeerResponse {
        let connection = try lock.withLock { () throws -> (
            MCPeerID?,
            Curve25519.KeyAgreement.PrivateKey?,
            SymmetricKey?,
            MCSession
        ) in
            if let expectedAttemptID, activeAttemptID != expectedAttemptID {
                throw BlinkPeerError.connectionFailed("A newer connection replaced this attempt.")
            }
            if let expectedSession, session !== expectedSession {
                throw BlinkPeerError.connectionFailed("A newer connection replaced this session.")
            }
            return (connectedPeer, connectionPrivateKey, connectionKey, session)
        }
        guard let peer = connection.0,
              let privateKey = connection.1,
              let responseKey = connection.2
        else {
            throw BlinkPeerError.connectionFailed("The Mac is not connected.")
        }
        let id = UUID()
        let sealedPayload = try BlinkPeerCrypto.seal(request, using: responseKey)
        let data = try JSONEncoder().encode(
            BlinkPeerRequestEnvelope(
                id: id,
                clientPublicKey: privateKey.publicKey.rawRepresentation,
                sealedPayload: sealedPayload
            )
        )
        return try await withCheckedThrowingContinuation { continuation in
            let dispatchError = lock.withLock { () -> (any Error)? in
                if let expectedAttemptID, activeAttemptID != expectedAttemptID {
                    return BlinkPeerError.connectionFailed(
                        "A newer connection replaced this attempt."
                    )
                }
                if let expectedSession, session !== expectedSession {
                    return BlinkPeerError.connectionFailed(
                        "A newer connection replaced this session."
                    )
                }
                guard session === connection.3, connectedPeer == peer else {
                    return BlinkPeerError.connectionFailed("The Mac is no longer connected.")
                }

                pendingResponses[id] = continuation
                do {
                    try connection.3.send(data, toPeers: [peer], with: .reliable)
                    return nil
                } catch {
                    pendingResponses[id] = nil
                    return error
                }
            }
            if let dispatchError {
                continuation.resume(throwing: dispatchError)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finishResponse(id: id, result: .failure(BlinkPeerError.requestTimedOut))
            }
        }
    }

    private func timeOutConnection(attemptID: UUID) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
            guard pendingConnection?.attemptID == attemptID else { return nil }
            defer { pendingConnection = nil }
            if activeAttemptID == attemptID {
                activeAttemptID = nil
                connectionPrivateKey = nil
                connectionKey = nil
                connectionCredential = nil
            }
            return pendingConnection?.continuation
        }
        continuation?.resume(throwing: BlinkPeerError.requestTimedOut)
    }

    private func finishResponse(
        id: UUID,
        result: Result<BlinkPeerResponse, any Error>
    ) {
        let continuation = lock.withLock { pendingResponses.removeValue(forKey: id) }
        continuation?.resume(with: result)
    }

    private func failAllPending(with error: any Error) {
        let pending = lock.withLock { () -> (
            CheckedContinuation<Void, any Error>?,
            [CheckedContinuation<BlinkPeerResponse, any Error>]
        ) in
            let connection = pendingConnection?.continuation
            pendingConnection = nil
            activeAttemptID = nil
            let responses = Array(pendingResponses.values)
            pendingResponses.removeAll()
            connectedPeer = nil
            connectionPrivateKey = nil
            connectionKey = nil
            connectionCredential = nil
            return (connection, responses)
        }
        pending.0?.resume(throwing: error)
        pending.1.forEach { $0.resume(throwing: error) }
    }

    private func candidateID(for peer: MCPeerID) -> String {
        "\(peer.displayName)#\(peer.hash)"
    }

    private func notifyConnectionObserver(isConnected: Bool) {
        let observer = lock.withLock { connectionObserver }
        observer?(isConnected)
    }
}

extension BlinkLANPeerClient: MCNearbyServiceBrowserDelegate {
    public func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        guard info?["version"] == BlinkPeerWire.discoveryVersion,
              let hostID = info?["hostID"],
              !hostID.isEmpty,
              let encodedKey = info?["hostKey"],
              let hostPublicKey = Data(base64Encoded: encodedKey),
              (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: hostPublicKey)) != nil
        else { return }
        lock.withLock {
            peersByID[candidateID(for: peerID)] = DiscoveredPeer(
                peer: peerID,
                hostID: hostID,
                hostPublicKey: hostPublicKey
            )
        }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        lock.withLock { peersByID[candidateID(for: peerID)] = nil }
    }

    public func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: any Error
    ) {
        lock.withLock { browsingFailureStorage = error.localizedDescription }
    }
}

extension BlinkLANPeerClient: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard lock.withLock({ self.session === session }) else { return }
        switch state {
        case .connected:
            let id = candidateID(for: peerID)
            let continuation = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
                guard pendingConnection?.candidateID == id,
                      pendingConnection?.attemptID == activeAttemptID
                else { return nil }
                connectedPeer = peerID
                defer { pendingConnection = nil }
                return pendingConnection?.continuation
            }
            continuation?.resume()
        case .notConnected:
            let id = candidateID(for: peerID)
            let wasCurrentSession = lock.withLock {
                connectedPeer == peerID || pendingConnection?.candidateID == id
            }
            if wasCurrentSession {
                lock.withLock { pairedHostStorage = nil }
                failAllPending(with: BlinkPeerError.connectionFailed("The Mac ended the session."))
                notifyConnectionObserver(isConnected: false)
            }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard lock.withLock({ self.session === session && connectedPeer == peerID }) else { return }
        guard let envelope = try? JSONDecoder().decode(BlinkPeerResponseEnvelope.self, from: data),
              envelope.version == BlinkPeerWire.version,
              let responseKey = lock.withLock({ connectionKey }),
              let response = try? BlinkPeerCrypto.open(
                  BlinkPeerResponse.self,
                  from: envelope.sealedPayload,
                  using: responseKey
              )
        else { return }
        finishResponse(id: envelope.id, result: .success(response))
    }

    public func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    public func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    public func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: (any Error)?
    ) {}
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
