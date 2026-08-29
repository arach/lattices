import BlinkCore
@testable import BlinkPeer
import CryptoKit
import Foundation
import Testing

@Suite("Blink encrypted LAN peer protocol")
struct BlinkPeerProtocolTests {
    @Test("snapshot responses survive the peer wire codec")
    func snapshotResponseRoundTrip() throws {
        let snapshot = BlinkSnapshot(
            generatedAt: Date(timeIntervalSince1970: 42),
            etag: "\"snapshot-r1\"",
            notes: [],
            tombstones: [],
            issues: []
        )
        let clientKey = Curve25519.KeyAgreement.PrivateKey()
        let hostKey = Curve25519.KeyAgreement.PrivateKey()
        let clientShared = try BlinkPeerCrypto.symmetricKey(
            privateKey: clientKey,
            peerPublicKey: hostKey.publicKey.rawRepresentation
        )
        let hostShared = try BlinkPeerCrypto.symmetricKey(
            privateKey: hostKey,
            peerPublicKey: clientKey.publicKey.rawRepresentation
        )
        let envelope = BlinkPeerResponseEnvelope(
            id: UUID(),
            sealedPayload: try BlinkPeerCrypto.seal(
                BlinkPeerResponse.snapshot(.snapshot(snapshot)),
                using: hostShared
            )
        )

        let decoded = try JSONDecoder().decode(
            BlinkPeerResponseEnvelope.self,
            from: JSONEncoder().encode(envelope)
        )
        #expect(decoded.id == envelope.id)
        let response = try BlinkPeerCrypto.open(
            BlinkPeerResponse.self,
            from: decoded.sealedPayload,
            using: clientShared
        )
        guard case .snapshot(.snapshot(let result)) = response else {
            Issue.record("Expected a full snapshot response")
            return
        }
        #expect(result == snapshot)
    }

    @Test("device access requests survive the peer wire codec")
    func accessRequestRoundTrip() throws {
        let seed = UUID().uuidString.lowercased()
        let clientKey = Curve25519.KeyAgreement.PrivateKey()
        let hostKey = Curve25519.KeyAgreement.PrivateKey()
        let clientShared = try BlinkPeerCrypto.symmetricKey(
            privateKey: clientKey,
            peerPublicKey: hostKey.publicKey.rawRepresentation
        )
        let hostShared = try BlinkPeerCrypto.symmetricKey(
            privateKey: hostKey,
            peerPublicKey: clientKey.publicKey.rawRepresentation
        )
        let identity = BlinkPeerClientIdentity(
            credential: BlinkPeerCrypto.credential(
                seed: seed,
                hostPublicKey: hostKey.publicKey.rawRepresentation
            ),
            name: "Arach’s iPhone"
        )
        let envelope = BlinkPeerRequestEnvelope(
            id: UUID(),
            clientPublicKey: clientKey.publicKey.rawRepresentation,
            sealedPayload: try BlinkPeerCrypto.seal(
                BlinkPeerRequest.requestAccess(identity),
                using: clientShared
            )
        )

        let decoded = try JSONDecoder().decode(
            BlinkPeerRequestEnvelope.self,
            from: JSONEncoder().encode(envelope)
        )
        #expect(decoded.version == BlinkPeerWire.version)
        let request = try BlinkPeerCrypto.open(
            BlinkPeerRequest.self,
            from: decoded.sealedPayload,
            using: hostShared
        )
        guard case .requestAccess(let result) = request else {
            Issue.record("Expected a device access request")
            return
        }
        #expect(result == identity)
        #expect(decoded.sealedPayload.range(of: Data(seed.utf8)) == nil)
    }

    @Test("credentials are scoped to the authenticated host key")
    func hostScopedCredentials() {
        let seed = UUID().uuidString.lowercased()
        let firstHost = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let secondHost = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation

        let first = BlinkPeerCrypto.credential(seed: seed, hostPublicKey: firstHost)
        let firstAgain = BlinkPeerCrypto.credential(seed: seed, hostPublicKey: firstHost)
        let second = BlinkPeerCrypto.credential(seed: seed, hostPublicKey: secondHost)

        #expect(first == firstAgain)
        #expect(first != second)
        #expect(first.count == 64)
        #expect(!first.contains(seed))
    }

    @Test("snapshot requests carry the credential that proves trust")
    func snapshotRequestCarriesCredential() throws {
        let clientKey = Curve25519.KeyAgreement.PrivateKey()
        let hostKey = Curve25519.KeyAgreement.PrivateKey()
        let clientShared = try BlinkPeerCrypto.symmetricKey(
            privateKey: clientKey,
            peerPublicKey: hostKey.publicKey.rawRepresentation
        )
        let hostShared = try BlinkPeerCrypto.symmetricKey(
            privateKey: hostKey,
            peerPublicKey: clientKey.publicKey.rawRepresentation
        )
        let credential = BlinkPeerCrypto.credential(
            seed: UUID().uuidString.lowercased(),
            hostPublicKey: hostKey.publicKey.rawRepresentation
        )
        let envelope = BlinkPeerRequestEnvelope(
            id: UUID(),
            clientPublicKey: clientKey.publicKey.rawRepresentation,
            sealedPayload: try BlinkPeerCrypto.seal(
                BlinkPeerRequest.fetchSnapshot(credential: credential, ifNoneMatch: "\"r1\""),
                using: clientShared
            )
        )

        let decoded = try JSONDecoder().decode(
            BlinkPeerRequestEnvelope.self,
            from: JSONEncoder().encode(envelope)
        )
        let request = try BlinkPeerCrypto.open(
            BlinkPeerRequest.self,
            from: decoded.sealedPayload,
            using: hostShared
        )
        guard case .fetchSnapshot(let sent, let etag) = request else {
            Issue.record("Expected a snapshot request")
            return
        }
        #expect(sent == credential)
        #expect(etag == "\"r1\"")
        #expect(BlinkPeerCrypto.isWellFormedCredential(sent))
        // The credential must not be readable without the sealed channel key.
        #expect(decoded.sealedPayload.range(of: Data(credential.utf8)) == nil)
    }

    @Test("malformed credentials are rejected before any trust lookup")
    func credentialShapeIsValidated() {
        #expect(!BlinkPeerCrypto.isWellFormedCredential(""))
        #expect(!BlinkPeerCrypto.isWellFormedCredential(String(repeating: "a", count: 63)))
        #expect(!BlinkPeerCrypto.isWellFormedCredential(String(repeating: "z", count: 64)))
        #expect(!BlinkPeerCrypto.isWellFormedCredential(String(repeating: "A", count: 64)))
        #expect(BlinkPeerCrypto.isWellFormedCredential(String(repeating: "a", count: 64)))
    }

    @Test("approved devices persist and can be revoked")
    func trustStoreLifecycle() throws {
        let storage = BlinkInMemorySecretStorage()
        let store = BlinkPeerTrustStore(storage: storage, storageKey: "trusted")
        let identity = BlinkPeerClientIdentity(
            credential: UUID().uuidString.lowercased(),
            name: "Arach’s iPhone"
        )

        #expect(!store.contains(credential: identity.credential))
        let approved = store.approve(identity)
        #expect(approved.name == identity.name)
        #expect(store.contains(credential: identity.credential))
        #expect(store.peers == [approved])
        #expect(store.persistenceFailure == nil)

        let reloaded = BlinkPeerTrustStore(storage: storage, storageKey: "trusted")
        #expect(
            try store.hostAgreementPrivateKey().rawRepresentation
                == reloaded.hostAgreementPrivateKey().rawRepresentation
        )
        #expect(reloaded.peers == [approved])
        #expect(try reloaded.revoke(id: identity.credential))
        #expect(reloaded.peers.isEmpty)
        #expect(try !reloaded.revoke(id: identity.credential))
    }

    @Test("pairing secrets never land in UserDefaults")
    func trustStoreKeepsSecretsOutOfDefaults() throws {
        let storage = BlinkInMemorySecretStorage()
        let store = BlinkPeerTrustStore(storage: storage, storageKey: "trusted")
        let credential = BlinkPeerCrypto.credential(
            seed: UUID().uuidString.lowercased(),
            hostPublicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        )
        store.approve(BlinkPeerClientIdentity(credential: credential, name: "iPhone"))
        let hostKey = try store.hostAgreementPrivateKey().rawRepresentation

        let peers = try #require(try storage.data(forKey: "trusted"))
        #expect(peers.range(of: Data(credential.utf8)) != nil)
        #expect(try storage.data(forKey: "trusted.host-agreement-key") == hostKey)

        let defaults = UserDefaults.standard
        #expect(defaults.data(forKey: "trusted") == nil)
        #expect(defaults.data(forKey: "trusted.host-agreement-key") == nil)
    }

    @Test("the Keychain path round-trips real items")
    func keychainStorageRoundTrip() throws {
        // Scoped to a throwaway service so this never touches the app's own
        // pairing secrets, and cleaned up on every exit path.
        let service = "dev.arach.blink.peer.test.\(UUID().uuidString)"
        let storage = BlinkKeychainSecretStorage(service: service)
        let key = "trusted"
        let first = Data("first".utf8)
        let second = Data("second".utf8)

        do {
            try storage.set(first, forKey: key)
        } catch {
            // A locked or headless keychain cannot serve this path. The
            // in-memory suite still covers the trust store's own behavior.
            return
        }
        defer { try? storage.removeValue(forKey: key) }

        #expect(try storage.data(forKey: key) == first)
        // Rewriting an existing item takes the SecItemUpdate branch.
        try storage.set(second, forKey: key)
        #expect(try storage.data(forKey: key) == second)
        #expect(try storage.data(forKey: "never-written") == nil)

        try storage.removeValue(forKey: key)
        #expect(try storage.data(forKey: key) == nil)
        // Deleting an absent item is not an error.
        try storage.removeValue(forKey: key)
    }

    @Test("the trust store survives a relaunch against the real Keychain")
    func trustStorePersistsThroughKeychain() throws {
        let service = "dev.arach.blink.peer.test.\(UUID().uuidString)"
        let storage = BlinkKeychainSecretStorage(service: service)
        let store = BlinkPeerTrustStore(storage: storage, storageKey: "trusted")
        let identity = BlinkPeerClientIdentity(
            credential: UUID().uuidString.lowercased(),
            name: "Arach’s iPhone"
        )
        defer {
            try? storage.removeValue(forKey: "trusted")
            try? storage.removeValue(forKey: "trusted.host-agreement-key")
        }

        store.approve(identity)
        let hostKey = try store.hostAgreementPrivateKey().rawRepresentation
        guard store.persistenceFailure == nil else { return }

        // A fresh store shares no in-process cache with the first one.
        let relaunched = BlinkPeerTrustStore(storage: storage, storageKey: "trusted")
        #expect(relaunched.contains(credential: identity.credential))
        #expect(try relaunched.hostAgreementPrivateKey().rawRepresentation == hostKey)
    }

    @Test("a reconnecting device cannot relabel its own entry")
    func trustStorePinsTheApprovedName() {
        let store = BlinkPeerTrustStore(
            storage: BlinkInMemorySecretStorage(),
            storageKey: "trusted"
        )
        let credential = UUID().uuidString.lowercased()
        store.approve(BlinkPeerClientIdentity(credential: credential, name: "Arach’s iPhone"))
        store.approve(BlinkPeerClientIdentity(credential: credential, name: "Arach’s MacBook Pro"))

        #expect(store.peers.map(\.name) == ["Arach’s iPhone"])
    }

    @Test("a failed Keychain write leaves access approved")
    func failedRevocationRemainsApproved() throws {
        let storage = BlinkWriteFailingSecretStorage()
        let store = BlinkPeerTrustStore(storage: storage, storageKey: "trusted")
        let identity = BlinkPeerClientIdentity(
            credential: UUID().uuidString.lowercased(),
            name: "Arach’s iPhone"
        )
        store.approve(identity)
        storage.rejectWrites = true

        #expect(throws: BlinkFailingSecretStorageError.self) {
            try store.revoke(id: identity.credential)
        }
        #expect(store.contains(credential: identity.credential))
        #expect(store.persistenceFailure != nil)

        let relaunched = BlinkPeerTrustStore(storage: storage, storageKey: "trusted")
        #expect(relaunched.contains(credential: identity.credential))
    }

    @Test("a Keychain failure never creates an ephemeral Mac identity")
    func hostIdentityFailsClosed() {
        let store = BlinkPeerTrustStore(
            storage: BlinkFailingSecretStorage(),
            storageKey: "trusted"
        )
        do {
            _ = try store.hostAgreementPrivateKey()
            Issue.record("Expected host identity creation to fail")
        } catch {}
        #expect(store.persistenceFailure != nil)
    }
}

@Suite("Blink LAN peer approval")
struct BlinkLANPeerServerAdmissionTests {
    private func makeServer() throws -> BlinkLANPeerServer {
        try BlinkLANPeerServer(
            hostID: UUID().uuidString.lowercased(),
            displayName: "Blink · Test",
            snapshotService: BlinkSnapshotService(
                builder: BlinkSnapshotBuilder(notesDirectory: URL(fileURLWithPath: "/dev/null")),
                tombstoneStore: BlinkTombstoneStore(fileURL: URL(fileURLWithPath: "/dev/null"))
            ),
            trustStore: BlinkPeerTrustStore(
                storage: BlinkInMemorySecretStorage(),
                storageKey: "trusted"
            )
        )
    }

    @Test("only one approval prompt is outstanding at a time")
    func approvalPromptsAreSerialized() throws {
        let server = try makeServer()
        #expect(server.claimApprovalSlot(for: "iPhone#1") == .ask)
        // A second, distinct peer must not open a nested modal.
        #expect(server.claimApprovalSlot(for: "iPhone#2") == .alreadyPending)
        server.releaseApprovalSlot(approved: true)
        #expect(server.claimApprovalSlot(for: "iPhone#2") == .ask)
    }

    @Test("a denial silences new prompts for the cooldown window")
    func denialStartsACooldown() throws {
        let server = try makeServer()
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(server.claimApprovalSlot(for: "attacker#1", now: start) == .ask)
        server.releaseApprovalSlot(approved: false, now: start)

        // Reconnecting under a fresh display name must not mint a new modal.
        #expect(server.claimApprovalSlot(for: "attacker#2", now: start.addingTimeInterval(1)) == .cooling)
        #expect(
            server.claimApprovalSlot(
                for: "attacker#3",
                now: start.addingTimeInterval(BlinkLANPeerServer.approvalCooldown - 1)
            ) == .cooling
        )
        #expect(
            server.claimApprovalSlot(
                for: "attacker#4",
                now: start.addingTimeInterval(BlinkLANPeerServer.approvalCooldown + 1)
            ) == .ask
        )
    }

}

private enum BlinkFailingSecretStorageError: Error {
    case unavailable
}

private final class BlinkFailingSecretStorage: BlinkPeerSecretStorage, @unchecked Sendable {
    func data(forKey key: String) throws -> Data? {
        throw BlinkFailingSecretStorageError.unavailable
    }

    func set(_ data: Data, forKey key: String) throws {
        throw BlinkFailingSecretStorageError.unavailable
    }

    func removeValue(forKey key: String) throws {
        throw BlinkFailingSecretStorageError.unavailable
    }
}

private final class BlinkWriteFailingSecretStorage: BlinkPeerSecretStorage, @unchecked Sendable {
    var rejectWrites = false
    private var values: [String: Data] = [:]

    func data(forKey key: String) throws -> Data? {
        values[key]
    }

    func set(_ data: Data, forKey key: String) throws {
        if rejectWrites { throw BlinkFailingSecretStorageError.unavailable }
        values[key] = data
    }

    func removeValue(forKey key: String) throws {
        values[key] = nil
    }
}
