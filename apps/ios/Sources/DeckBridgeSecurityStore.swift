import CryptoKit
import DeckKit
import Foundation
import Security
import UIKit

enum DeckBridgeSecurityError: LocalizedError {
    case pairingRequired
    case insufficientCapability(String)
    case invalidBridgeKey
    case invalidEnvelope

    var errorDescription: String? {
        switch self {
        case .pairingRequired:
            return "Approve this iPad or iPhone on your Mac before using the protected bridge."
        case .insufficientCapability(let capability):
            return "This pairing does not grant the required bridge capability: \(capability). Pair again from the Mac."
        case .invalidBridgeKey:
            return "The Mac bridge returned an invalid encryption identity."
        case .invalidEnvelope:
            return "The encrypted bridge payload could not be decoded."
        }
    }
}

struct StoredBridgeTrust: Codable, Equatable, Sendable {
    var bridgeName: String
    var bridgePublicKey: String
    var bridgeFingerprint: String
    var requestSigningRequired: Bool
    var payloadEncryptionRequired: Bool
    var grantedCapabilities: [String]?
    var pairedAt: Date

    /// Where this Mac was last reachable. Optional so records written before
    /// these fields existed still decode — synthesized `Decodable` uses
    /// `decodeIfPresent` for optionals, so old JSON reads back with both nil.
    ///
    /// This is what lets a paired-but-not-currently-discovered Mac stay in the
    /// roster as something you can reconnect to, rather than a dead card.
    var lastKnownHost: String?
    var lastKnownPort: Int?

    var effectiveCapabilities: [String] {
        grantedCapabilities ?? DeckBridgeCapability.legacyCompanionCapabilities
    }
}

struct PreparedBridgeRequest {
    let headers: [String: String]
    let body: Data?
    let requestNonce: String
}

final class DeckBridgeSecurityStore {
    static let shared = DeckBridgeSecurityStore()
    static let trustDidChangeNotification = Notification.Name("DeckBridgeSecurityStore.trustDidChange")

    private enum DefaultsKey {
        static let deviceID = "companion.security.deviceID"
        static let trustedBridges = "companion.security.trustedBridges"
    }

    private enum KeychainKey {
        static let service = "dev.lattices.app.companion"
        static let account = "device.keyagreement.private"
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let privateKey: Curve25519.KeyAgreement.PrivateKey
    private let deviceID: String
    private var trustedBridges: [String: StoredBridgeTrust]

    private init() {
        self.privateKey = Self.loadOrCreatePrivateKey()

        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: DefaultsKey.deviceID), saved.isEmpty == false {
            self.deviceID = saved
        } else {
            let generated = UUID().uuidString.lowercased()
            defaults.set(generated, forKey: DefaultsKey.deviceID)
            self.deviceID = generated
        }

        self.trustedBridges = Self.loadTrustedBridges()
    }

    var devicePublicKeyBase64: String {
        Data(privateKey.publicKey.rawRepresentation).base64EncodedString()
    }

    /// This device's own fingerprint, derived exactly as the Mac derives it for
    /// its approval alert (`LatticesCompanionSecurityCoordinator.fingerprint`).
    /// Both screens show the same string — that is the whole point of showing
    /// it, and it is why this derivation must not drift from the Mac's.
    ///
    /// Hex has no confusable pairs to worry about: `O`, `I` and `L` are not in
    /// the alphabet, so `0` and `1` are unambiguous.
    var deviceFingerprint: String {
        let digest = SHA256.hash(data: Data(devicePublicKeyBase64.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let compact = String(hex.prefix(12)).uppercased()
        return stride(from: 0, to: compact.count, by: 4).map { offset in
            let start = compact.index(compact.startIndex, offsetBy: offset)
            let end = compact.index(start, offsetBy: min(4, compact.count - offset))
            return String(compact[start..<end])
        }.joined(separator: "-")
    }

    func isTrusted(health: BridgeHealthResponse) -> Bool {
        trustedBridges[health.bridgePublicKey] != nil
    }

    /// Whether this device has paired with the Mac behind an endpoint.
    ///
    /// One definition, because this comparison was previously written out by
    /// hand in `ContentView.prepareConnection` and `DeckFleetStore.synchronize`
    /// and the two are easy to let drift apart.
    ///
    /// Note the limit of what this proves: the fingerprint arrives in an
    /// unauthenticated Bonjour TXT record, so a match is a *hint* that this is
    /// a Mac we know, good enough to decide what to show in a roster. It is not
    /// authentication — that happens against `health.bridgePublicKey` when the
    /// connection is actually made.
    func isTrusted(endpoint: BridgeEndpoint) -> Bool {
        guard let fingerprint = endpoint.bridgeFingerprint, !fingerprint.isEmpty else { return false }
        return trustedBridges.values.contains {
            $0.bridgeFingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame
        }
    }

    /// The trust record for a Mac, by the public key its `/health` reports.
    /// This is the authenticated identity — prefer it over fingerprint matching
    /// anywhere the answer decides what a control does.
    func trust(forPublicKey publicKey: String) -> StoredBridgeTrust? {
        trustedBridges[publicKey]
    }

    /// All Macs this device has paired with (most recently paired first).
    func trustedBridgeList() -> [StoredBridgeTrust] {
        trustedBridges.values.sorted { $0.pairedAt > $1.pairedAt }
    }

    /// Forget a previously paired bridge by its public key.
    func forgetBridge(publicKey: String) {
        guard trustedBridges.removeValue(forKey: publicKey) != nil else { return }
        persistTrustedBridges()
        NotificationCenter.default.post(name: Self.trustDidChangeNotification, object: nil)
    }

    func pairingRequest() -> DeckPairingRequest {
        DeckPairingRequest(
            deviceID: deviceID,
            deviceName: UIDevice.current.name,
            devicePublicKey: devicePublicKeyBase64,
            platform: "iOS \(UIDevice.current.systemVersion)",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            requestedCapabilities: DeckBridgeCapability.defaultCompanionCapabilities
        )
    }

    func storePairing(
        _ response: DeckPairingResponse,
        lastKnownHost: String? = nil,
        lastKnownPort: Int? = nil
    ) {
        // `alreadyTrusted` comes back for a Mac we have paired with before, so
        // keep the original pairing date rather than restamping it every time
        // a retry resolves.
        let existing = trustedBridges[response.bridgePublicKey]
        trustedBridges[response.bridgePublicKey] = StoredBridgeTrust(
            bridgeName: response.bridgeName,
            bridgePublicKey: response.bridgePublicKey,
            bridgeFingerprint: response.bridgeFingerprint,
            requestSigningRequired: response.requestSigningRequired,
            payloadEncryptionRequired: response.payloadEncryptionRequired,
            grantedCapabilities: response.grantedCapabilities,
            pairedAt: existing?.pairedAt ?? Date(),
            lastKnownHost: lastKnownHost ?? existing?.lastKnownHost,
            lastKnownPort: lastKnownPort ?? existing?.lastKnownPort
        )
        persistTrustedBridges()
        NotificationCenter.default.post(name: Self.trustDidChangeNotification, object: nil)
    }

    /// Remember where a Mac answered, so it stays reconnectable once it stops
    /// advertising on Bonjour. Only ever called after `/health` has proved the
    /// public key, so an address can never be attached to the wrong Mac.
    func rememberAddress(forPublicKey publicKey: String, host: String, port: Int) {
        guard var trust = trustedBridges[publicKey] else { return }
        guard trust.lastKnownHost != host || trust.lastKnownPort != port else { return }
        trust.lastKnownHost = host
        trust.lastKnownPort = port
        trustedBridges[publicKey] = trust
        persistTrustedBridges()
    }

    /// Remember where a Mac answered, so it stays reconnectable once it stops
    /// advertising on Bonjour. Only ever called after `/health` has proved the
    /// public key, so an address can never be attached to the wrong Mac.
    func rememberAddress(forPublicKey publicKey: String, host: String, port: Int) {
        guard var trust = trustedBridges[publicKey] else { return }
        guard trust.lastKnownHost != host || trust.lastKnownPort != port else { return }
        trust.lastKnownHost = host
        trust.lastKnownPort = port
        trustedBridges[publicKey] = trust
        persistTrustedBridges()
    }

    func prepareRequest(
        method: String,
        path: String,
        plaintextBody: Data?,
        health: BridgeHealthResponse
    ) throws -> PreparedBridgeRequest {
        guard let trust = trustedBridges[health.bridgePublicKey] else {
            throw DeckBridgeSecurityError.pairingRequired
        }
        try requireCapability(for: path, trust: trust)

        let requestNonce = UUID().uuidString.lowercased()
        let timestamp = ISO8601DateFormatter.latticesBridge.string(from: Date())
        let bodyData: Data

        if trust.payloadEncryptionRequired, let plaintextBody {
            let envelope = try sealEnvelope(
                plaintextBody,
                publicKeyBase64: health.bridgePublicKey,
                aad: requestAAD(
                    method: method,
                    path: path,
                    deviceID: deviceID,
                    timestamp: timestamp,
                    requestNonce: requestNonce
                )
            )
            bodyData = try encoder.encode(envelope)
        } else {
            bodyData = plaintextBody ?? Data()
        }

        let signature = try requestSignature(
            method: method,
            path: path,
            bridgePublicKeyBase64: health.bridgePublicKey,
            timestamp: timestamp,
            requestNonce: requestNonce,
            body: bodyData
        )

        return PreparedBridgeRequest(
            headers: [
                "X-Lattices-Device-Id": deviceID,
                "X-Lattices-Timestamp": timestamp,
                "X-Lattices-Nonce": requestNonce,
                "X-Lattices-Signature": signature,
            ],
            body: bodyData.isEmpty ? nil : bodyData,
            requestNonce: requestNonce
        )
    }

    func openProtectedResponse<T: Decodable>(
        _ type: T.Type,
        data: Data,
        status: Int,
        path: String,
        requestNonce: String,
        health: BridgeHealthResponse
    ) throws -> T {
        let envelope = try decoder.decode(DeckEncryptedEnvelope.self, from: data)
        let plaintext = try openEnvelope(
            envelope,
            publicKeyBase64: health.bridgePublicKey,
            aad: responseAAD(
                status: status,
                path: path,
                deviceID: deviceID,
                requestNonce: requestNonce
            )
        )
        return try decoder.decode(type, from: plaintext)
    }
}

private extension DeckBridgeSecurityStore {
    static func loadTrustedBridges() -> [String: StoredBridgeTrust] {
        guard
            let data = UserDefaults.standard.data(forKey: DefaultsKey.trustedBridges),
            let bridges = try? JSONDecoder().decode([StoredBridgeTrust].self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: bridges.map { ($0.bridgePublicKey, $0) })
    }

    static func loadOrCreatePrivateKey() -> Curve25519.KeyAgreement.PrivateKey {
        if
            let stored = MobileKeychainBridge.load(service: KeychainKey.service, account: KeychainKey.account),
            let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: stored)
        {
            return key
        }

        let key = Curve25519.KeyAgreement.PrivateKey()
        _ = MobileKeychainBridge.save(
            key.rawRepresentation,
            service: KeychainKey.service,
            account: KeychainKey.account
        )
        return key
    }

    func persistTrustedBridges() {
        let values = trustedBridges.values.sorted {
            $0.bridgeName.localizedCaseInsensitiveCompare($1.bridgeName) == .orderedAscending
        }
        guard let data = try? encoder.encode(values) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.trustedBridges)
    }

    func requestSignature(
        method: String,
        path: String,
        bridgePublicKeyBase64: String,
        timestamp: String,
        requestNonce: String,
        body: Data
    ) throws -> String {
        let key = try signingKey(bridgePublicKeyBase64: bridgePublicKeyBase64)
        let canonical = requestCanonicalData(
            method: method,
            path: path,
            deviceID: deviceID,
            timestamp: timestamp,
            requestNonce: requestNonce,
            body: body
        )
        let mac = HMAC<SHA256>.authenticationCode(for: canonical, using: key)
        return Data(mac).base64EncodedString()
    }

    func requestCanonicalData(
        method: String,
        path: String,
        deviceID: String,
        timestamp: String,
        requestNonce: String,
        body: Data
    ) -> Data {
        let digest = SHA256.hash(data: body)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let canonical = [
            method.uppercased(),
            path,
            deviceID,
            timestamp,
            requestNonce,
            hex
        ].joined(separator: "\n")
        return Data(canonical.utf8)
    }

    func requestAAD(
        method: String,
        path: String,
        deviceID: String,
        timestamp: String,
        requestNonce: String
    ) -> Data {
        let value = [
            "request",
            method.uppercased(),
            path,
            deviceID,
            timestamp,
            requestNonce
        ].joined(separator: "\n")
        return Data(value.utf8)
    }

    func responseAAD(
        status: Int,
        path: String,
        deviceID: String,
        requestNonce: String
    ) -> Data {
        let value = [
            "response",
            String(status),
            path,
            deviceID,
            requestNonce
        ].joined(separator: "\n")
        return Data(value.utf8)
    }

    func requireCapability(for path: String, trust: StoredBridgeTrust) throws {
        let required: String?
        switch path {
        case "/deck/snapshot":
            required = DeckBridgeCapability.deckRead
        case "/deck/perform":
            required = DeckBridgeCapability.deckPerform
        case "/deck/trackpad":
            required = DeckBridgeCapability.inputTrackpad
        case "/deck/preview":
            required = DeckBridgeCapability.screenPreview
        default:
            required = nil
        }

        guard let required else { return }
        guard trust.effectiveCapabilities.contains(required) else {
            throw DeckBridgeSecurityError.insufficientCapability(required)
        }
    }

    func sharedSecret(bridgePublicKeyBase64: String) throws -> SharedSecret {
        guard
            let bridgeData = Data(base64Encoded: bridgePublicKeyBase64),
            let publicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: bridgeData)
        else {
            throw DeckBridgeSecurityError.invalidBridgeKey
        }
        return try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
    }

    func signingKey(bridgePublicKeyBase64: String) throws -> SymmetricKey {
        let sharedSecret = try sharedSecret(bridgePublicKeyBase64: bridgePublicKeyBase64)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("lattices-bridge-v1".utf8),
            sharedInfo: Data("signing".utf8),
            outputByteCount: 32
        )
    }

    func encryptionKey(bridgePublicKeyBase64: String) throws -> SymmetricKey {
        let sharedSecret = try sharedSecret(bridgePublicKeyBase64: bridgePublicKeyBase64)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("lattices-bridge-v1".utf8),
            sharedInfo: Data("encryption".utf8),
            outputByteCount: 32
        )
    }

    func sealEnvelope(
        _ plaintext: Data,
        publicKeyBase64: String,
        aad: Data
    ) throws -> DeckEncryptedEnvelope {
        let key = try encryptionKey(bridgePublicKeyBase64: publicKeyBase64)
        let sealed = try ChaChaPoly.seal(plaintext, using: key, authenticating: aad)
        return DeckEncryptedEnvelope(sealedBox: Data(sealed.combined).base64EncodedString())
    }

    func openEnvelope(
        _ envelope: DeckEncryptedEnvelope,
        publicKeyBase64: String,
        aad: Data
    ) throws -> Data {
        guard let data = Data(base64Encoded: envelope.sealedBox),
              let sealed = try? ChaChaPoly.SealedBox(combined: data) else {
            throw DeckBridgeSecurityError.invalidEnvelope
        }
        let key = try encryptionKey(bridgePublicKeyBase64: publicKeyBase64)
        guard let plaintext = try? ChaChaPoly.open(sealed, using: key, authenticating: aad) else {
            throw DeckBridgeSecurityError.invalidEnvelope
        }
        return plaintext
    }
}

private enum MobileKeychainBridge {
    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func save(_ data: Data, service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        var insert = query
        insert[kSecValueData as String] = data
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        return addStatus == errSecSuccess
    }
}

private extension ISO8601DateFormatter {
    static let latticesBridge: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
