import Foundation

public struct DeckPairingRequest: Codable, Equatable, Sendable {
    public var deviceID: String
    public var deviceName: String
    public var devicePublicKey: String
    public var platform: String
    public var appVersion: String?

    public init(
        deviceID: String,
        deviceName: String,
        devicePublicKey: String,
        platform: String,
        appVersion: String? = nil
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.devicePublicKey = devicePublicKey
        self.platform = platform
        self.appVersion = appVersion
    }
}

public struct DeckPairingResponse: Codable, Equatable, Sendable {
    public var disposition: DeckPairingDisposition
    public var bridgeName: String
    public var bridgePublicKey: String
    public var bridgeFingerprint: String
    public var requestSigningRequired: Bool
    public var payloadEncryptionRequired: Bool
    public var detail: String?

    public init(
        disposition: DeckPairingDisposition,
        bridgeName: String,
        bridgePublicKey: String,
        bridgeFingerprint: String,
        requestSigningRequired: Bool,
        payloadEncryptionRequired: Bool,
        detail: String? = nil
    ) {
        self.disposition = disposition
        self.bridgeName = bridgeName
        self.bridgePublicKey = bridgePublicKey
        self.bridgeFingerprint = bridgeFingerprint
        self.requestSigningRequired = requestSigningRequired
        self.payloadEncryptionRequired = payloadEncryptionRequired
        self.detail = detail
    }
}

public enum DeckPairingDisposition: String, Codable, CaseIterable, Sendable {
    case approved
    case alreadyTrusted
    case denied
}

public struct DeckEncryptedEnvelope: Codable, Equatable, Sendable {
    public var sealedBox: String

    public init(sealedBox: String) {
        self.sealedBox = sealedBox
    }
}

public struct DeckTrustedDeviceSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var fingerprint: String
    public var pairedAt: Date
    public var lastSeenAt: Date

    public init(
        id: String,
        name: String,
        fingerprint: String,
        pairedAt: Date,
        lastSeenAt: Date
    ) {
        self.id = id
        self.name = name
        self.fingerprint = fingerprint
        self.pairedAt = pairedAt
        self.lastSeenAt = lastSeenAt
    }
}
