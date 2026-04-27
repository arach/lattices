import AppKit
import CryptoKit
import DeckKit
import Foundation
import Security

enum LatticesCompanionSecurityError: LocalizedError {
    case missingHeader(String)
    case untrustedDevice
    case staleRequest
    case replayedRequest
    case invalidSignature
    case invalidEnvelope
    case invalidDeviceKey

    var errorDescription: String? {
        switch self {
        case .missingHeader(let name):
            return "Missing bridge security header: \(name)."
        case .untrustedDevice:
            return "This device is not trusted by the Mac bridge yet."
        case .staleRequest:
            return "This bridge request expired before it reached the Mac."
        case .replayedRequest:
            return "This bridge request was already used."
        case .invalidSignature:
            return "The bridge request signature could not be verified."
        case .invalidEnvelope:
            return "The bridge payload could not be decrypted."
        case .invalidDeviceKey:
            return "The device pairing key is invalid."
        }
    }
}

struct LatticesCompanionTrustedDeviceRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var publicKey: String
    var fingerprint: String
    var platform: String
    var appVersion: String?
    var pairedAt: Date
    var lastSeenAt: Date

    var summary: DeckTrustedDeviceSummary {
        DeckTrustedDeviceSummary(
            id: id,
            name: name,
            fingerprint: fingerprint,
            pairedAt: pairedAt,
            lastSeenAt: lastSeenAt
        )
    }
}

struct AuthorizedBridgeRequest {
    let device: LatticesCompanionTrustedDeviceRecord
    let requestNonce: String
    let requestTimestamp: String
}

final class LatticesCompanionSecurityCoordinator {
    static let shared = LatticesCompanionSecurityCoordinator()

    private enum DefaultsKey {
        static let trustedDevices = "companion.security.trustedDevices"
    }

    private enum KeychainKey {
        static let service = "com.arach.lattices.companion.bridge"
        static let account = "bridge.keyagreement.private"
    }

    private enum Header {
        static let deviceID = "x-lattices-device-id"
        static let timestamp = "x-lattices-timestamp"
        static let nonce = "x-lattices-nonce"
        static let signature = "x-lattices-signature"
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let bridgePrivateKey: Curve25519.KeyAgreement.PrivateKey
    private let timeSkewAllowance: TimeInterval = 120
    private let replayWindow: TimeInterval = 600

    private var trustedDevices: [String: LatticesCompanionTrustedDeviceRecord]
    private var seenNonces: [String: Date] = [:]

    private init() {
        self.bridgePrivateKey = Self.loadOrCreateBridgeKey()
        self.trustedDevices = Self.loadTrustedDevices()
    }

    var bridgePublicKeyBase64: String {
        Data(bridgePrivateKey.publicKey.rawRepresentation).base64EncodedString()
    }

    var bridgeFingerprint: String {
        Self.fingerprint(forPublicKeyBase64: bridgePublicKeyBase64)
    }

    func trustedDeviceSummaries() -> [DeckTrustedDeviceSummary] {
        trustedDevices.values
            .map(\.summary)
            .sorted { lhs, rhs in
                if lhs.lastSeenAt == rhs.lastSeenAt {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.lastSeenAt > rhs.lastSeenAt
            }
    }

    func clearTrustedDevices() {
        trustedDevices.removeAll()
        persistTrustedDevices()
    }

    func handlePairingRequest(_ request: DeckPairingRequest) -> DeckPairingResponse {
        let diag = DiagnosticLog.shared
        diag.info("CompanionPairing: request device=\(request.deviceName) id=\(request.deviceID)")

        guard
            request.deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            request.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            decodePublicKey(base64: request.devicePublicKey) != nil
        else {
            diag.warn("CompanionPairing: invalid key material for device id=\(request.deviceID)")
            return DeckPairingResponse(
                disposition: .denied,
                bridgeName: Host.current().localizedName ?? "Lattices Companion",
                bridgePublicKey: bridgePublicKeyBase64,
                bridgeFingerprint: bridgeFingerprint,
                requestSigningRequired: true,
                payloadEncryptionRequired: true,
                detail: LatticesCompanionSecurityError.invalidDeviceKey.localizedDescription
            )
        }

        if var existing = trustedDevices[request.deviceID], existing.publicKey == request.devicePublicKey {
            existing.lastSeenAt = Date()
            trustedDevices[request.deviceID] = existing
            persistTrustedDevices()
            diag.success("CompanionPairing: device already trusted id=\(request.deviceID)")
            return DeckPairingResponse(
                disposition: .alreadyTrusted,
                bridgeName: Host.current().localizedName ?? "Lattices Companion",
                bridgePublicKey: bridgePublicKeyBase64,
                bridgeFingerprint: bridgeFingerprint,
                requestSigningRequired: true,
                payloadEncryptionRequired: true,
                detail: "This device is already trusted on the Mac."
            )
        }

        let approved = promptForPairingApproval(request)
        guard approved else {
            diag.warn("CompanionPairing: denied device id=\(request.deviceID)")
            return DeckPairingResponse(
                disposition: .denied,
                bridgeName: Host.current().localizedName ?? "Lattices Companion",
                bridgePublicKey: bridgePublicKeyBase64,
                bridgeFingerprint: bridgeFingerprint,
                requestSigningRequired: true,
                payloadEncryptionRequired: true,
                detail: "Pairing was denied on the Mac."
            )
        }

        let now = Date()
        trustedDevices[request.deviceID] = LatticesCompanionTrustedDeviceRecord(
            id: request.deviceID,
            name: request.deviceName,
            publicKey: request.devicePublicKey,
            fingerprint: Self.fingerprint(forPublicKeyBase64: request.devicePublicKey),
            platform: request.platform,
            appVersion: request.appVersion,
            pairedAt: now,
            lastSeenAt: now
        )
        persistTrustedDevices()
        diag.success("CompanionPairing: approved device id=\(request.deviceID)")

        return DeckPairingResponse(
            disposition: .approved,
            bridgeName: Host.current().localizedName ?? "Lattices Companion",
            bridgePublicKey: bridgePublicKeyBase64,
            bridgeFingerprint: bridgeFingerprint,
            requestSigningRequired: true,
            payloadEncryptionRequired: true,
            detail: "Trusted and ready for encrypted bridge requests."
        )
    }

    func authorize(
        method: String,
        path: String,
        headers: [String: String],
        body: Data
    ) throws -> AuthorizedBridgeRequest {
        let deviceID = try requiredHeader(Header.deviceID, from: headers)
        let timestamp = try requiredHeader(Header.timestamp, from: headers)
        let requestNonce = try requiredHeader(Header.nonce, from: headers)
        let signature = try requiredHeader(Header.signature, from: headers)

        guard let device = trustedDevices[deviceID] else {
            throw LatticesCompanionSecurityError.untrustedDevice
        }

        let requestDate = try parseRequestDate(timestamp)
        let now = Date()
        guard abs(requestDate.timeIntervalSince(now)) <= timeSkewAllowance else {
            throw LatticesCompanionSecurityError.staleRequest
        }

        pruneSeenNonces(now: now)
        let replayKey = "\(deviceID):\(requestNonce)"
        guard seenNonces[replayKey] == nil else {
            throw LatticesCompanionSecurityError.replayedRequest
        }

        let expectedSignature = try requestSignature(
            method: method,
            path: path,
            device: device,
            timestamp: timestamp,
            requestNonce: requestNonce,
            body: body
        )
        guard Self.constantTimeEquals(signature, expectedSignature) else {
            throw LatticesCompanionSecurityError.invalidSignature
        }

        seenNonces[replayKey] = now
        touchDevice(deviceID: deviceID, at: now)
        return AuthorizedBridgeRequest(
            device: trustedDevices[deviceID] ?? device,
            requestNonce: requestNonce,
            requestTimestamp: timestamp
        )
    }

    func decodeProtectedBody<T: Decodable>(
        _ type: T.Type,
        body: Data,
        auth: AuthorizedBridgeRequest,
        method: String,
        path: String
    ) throws -> T {
        let envelope = try decoder.decode(DeckEncryptedEnvelope.self, from: body)
        let plaintext = try openEnvelope(
            envelope,
            device: auth.device,
            aad: requestAAD(
                method: method,
                path: path,
                deviceID: auth.device.id,
                timestamp: auth.requestTimestamp,
                requestNonce: auth.requestNonce
            )
        )
        return try decoder.decode(type, from: plaintext)
    }

    func encodeProtectedResponse<T: Encodable>(
        _ value: T,
        auth: AuthorizedBridgeRequest,
        status: Int,
        path: String
    ) throws -> DeckEncryptedEnvelope {
        let plaintext = try encoder.encode(value)
        return try sealEnvelope(
            plaintext,
            device: auth.device,
            aad: responseAAD(
                status: status,
                path: path,
                deviceID: auth.device.id,
                requestNonce: auth.requestNonce
            )
        )
    }
}

private extension LatticesCompanionSecurityCoordinator {
    static func loadTrustedDevices() -> [String: LatticesCompanionTrustedDeviceRecord] {
        guard
            let data = UserDefaults.standard.data(forKey: DefaultsKey.trustedDevices),
            let devices = try? JSONDecoder().decode([LatticesCompanionTrustedDeviceRecord].self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
    }

    static func loadOrCreateBridgeKey() -> Curve25519.KeyAgreement.PrivateKey {
        if
            let stored = KeychainBridge.load(service: KeychainKey.service, account: KeychainKey.account),
            let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: stored)
        {
            return key
        }

        let key = Curve25519.KeyAgreement.PrivateKey()
        let data = key.rawRepresentation
        _ = KeychainBridge.save(data, service: KeychainKey.service, account: KeychainKey.account)
        return key
    }

    static func fingerprint(forPublicKeyBase64 value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let compact = String(hex.prefix(12)).uppercased()
        return compact.chunked(into: 4).joined(separator: "-")
    }

    func persistTrustedDevices() {
        let sorted = trustedDevices.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        guard let data = try? encoder.encode(sorted) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.trustedDevices)
    }

    func requiredHeader(_ name: String, from headers: [String: String]) throws -> String {
        guard let value = headers[name], value.isEmpty == false else {
            throw LatticesCompanionSecurityError.missingHeader(name)
        }
        return value
    }

    func parseRequestDate(_ timestamp: String) throws -> Date {
        guard let value = ISO8601DateFormatter.latticesBridge.date(from: timestamp) else {
            throw LatticesCompanionSecurityError.staleRequest
        }
        return value
    }

    func requestSignature(
        method: String,
        path: String,
        device: LatticesCompanionTrustedDeviceRecord,
        timestamp: String,
        requestNonce: String,
        body: Data
    ) throws -> String {
        let key = try signingKey(for: device)
        let canonical = requestCanonicalData(
            method: method,
            path: path,
            deviceID: device.id,
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

    func signingKey(for device: LatticesCompanionTrustedDeviceRecord) throws -> SymmetricKey {
        let publicKey = try trustedPublicKey(for: device)
        let sharedSecret = try bridgePrivateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("lattices-bridge-v1".utf8),
            sharedInfo: Data("signing".utf8),
            outputByteCount: 32
        )
    }

    func encryptionKey(for device: LatticesCompanionTrustedDeviceRecord) throws -> SymmetricKey {
        let publicKey = try trustedPublicKey(for: device)
        let sharedSecret = try bridgePrivateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("lattices-bridge-v1".utf8),
            sharedInfo: Data("encryption".utf8),
            outputByteCount: 32
        )
    }

    func trustedPublicKey(for device: LatticesCompanionTrustedDeviceRecord) throws -> Curve25519.KeyAgreement.PublicKey {
        guard let key = decodePublicKey(base64: device.publicKey) else {
            throw LatticesCompanionSecurityError.invalidDeviceKey
        }
        return key
    }

    func decodePublicKey(base64: String) -> Curve25519.KeyAgreement.PublicKey? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
    }

    func openEnvelope(
        _ envelope: DeckEncryptedEnvelope,
        device: LatticesCompanionTrustedDeviceRecord,
        aad: Data
    ) throws -> Data {
        guard let data = Data(base64Encoded: envelope.sealedBox),
              let sealed = try? ChaChaPoly.SealedBox(combined: data) else {
            throw LatticesCompanionSecurityError.invalidEnvelope
        }
        let key = try encryptionKey(for: device)
        guard let plaintext = try? ChaChaPoly.open(sealed, using: key, authenticating: aad) else {
            throw LatticesCompanionSecurityError.invalidEnvelope
        }
        return plaintext
    }

    func sealEnvelope(
        _ plaintext: Data,
        device: LatticesCompanionTrustedDeviceRecord,
        aad: Data
    ) throws -> DeckEncryptedEnvelope {
        let key = try encryptionKey(for: device)
        let sealed = try ChaChaPoly.seal(plaintext, using: key, authenticating: aad)
        return DeckEncryptedEnvelope(sealedBox: Data(sealed.combined).base64EncodedString())
    }

    func pruneSeenNonces(now: Date) {
        seenNonces = seenNonces.filter { now.timeIntervalSince($0.value) < replayWindow }
    }

    func touchDevice(deviceID: String, at date: Date) {
        guard var device = trustedDevices[deviceID] else { return }
        guard date.timeIntervalSince(device.lastSeenAt) >= 30 else { return }
        device.lastSeenAt = date
        trustedDevices[deviceID] = device
        persistTrustedDevices()
    }

    func promptForPairingApproval(_ request: DeckPairingRequest) -> Bool {
        if Thread.isMainThread {
            return runPairingAlert(request)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var approved = false

        DispatchQueue.main.async {
            approved = self.runPairingAlert(request)
            semaphore.signal()
        }

        semaphore.wait()
        return approved
    }

    func runPairingAlert(_ request: DeckPairingRequest) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Allow \(request.deviceName) to pair with Lattices?"
        alert.informativeText = """
        This device is asking for encrypted local-network control of your Mac.

        Device ID: \(request.deviceID)
        Device Fingerprint: \(Self.fingerprint(forPublicKeyBase64: request.devicePublicKey))
        Platform: \(request.platform)
        """
        alert.addButton(withTitle: "Allow Pairing")
        alert.addButton(withTitle: "Deny")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsData = Array(lhs.utf8)
        let rhsData = Array(rhs.utf8)
        guard lhsData.count == rhsData.count else { return false }
        var diff: UInt8 = 0
        for index in lhsData.indices {
            diff |= lhsData[index] ^ rhsData[index]
        }
        return diff == 0
    }
}

private enum KeychainBridge {
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

private extension String {
    func chunked(into size: Int) -> [String] {
        guard size > 0, isEmpty == false else { return [self] }
        var chunks: [String] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[index..<next]))
            index = next
        }
        return chunks
    }
}
