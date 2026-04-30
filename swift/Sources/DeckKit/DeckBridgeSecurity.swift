import Foundation

public struct DeckPairingRequest: Codable, Equatable, Sendable {
    public var deviceID: String
    public var deviceName: String
    public var devicePublicKey: String
    public var platform: String
    public var appVersion: String?
    public var requestedCapabilities: [String]

    public init(
        deviceID: String,
        deviceName: String,
        devicePublicKey: String,
        platform: String,
        appVersion: String? = nil,
        requestedCapabilities: [String] = DeckBridgeCapability.defaultCompanionCapabilities
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.devicePublicKey = devicePublicKey
        self.platform = platform
        self.appVersion = appVersion
        self.requestedCapabilities = requestedCapabilities
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case deviceName
        case devicePublicKey
        case platform
        case appVersion
        case requestedCapabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        devicePublicKey = try container.decode(String.self, forKey: .devicePublicKey)
        platform = try container.decode(String.self, forKey: .platform)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        requestedCapabilities = try container.decodeIfPresent([String].self, forKey: .requestedCapabilities)
            ?? DeckBridgeCapability.defaultCompanionCapabilities
    }
}

public struct DeckPairingResponse: Codable, Equatable, Sendable {
    public var disposition: DeckPairingDisposition
    public var bridgeName: String
    public var bridgePublicKey: String
    public var bridgeFingerprint: String
    public var requestSigningRequired: Bool
    public var payloadEncryptionRequired: Bool
    public var grantedCapabilities: [String]
    public var detail: String?

    public init(
        disposition: DeckPairingDisposition,
        bridgeName: String,
        bridgePublicKey: String,
        bridgeFingerprint: String,
        requestSigningRequired: Bool,
        payloadEncryptionRequired: Bool,
        grantedCapabilities: [String] = DeckBridgeCapability.defaultCompanionCapabilities,
        detail: String? = nil
    ) {
        self.disposition = disposition
        self.bridgeName = bridgeName
        self.bridgePublicKey = bridgePublicKey
        self.bridgeFingerprint = bridgeFingerprint
        self.requestSigningRequired = requestSigningRequired
        self.payloadEncryptionRequired = payloadEncryptionRequired
        self.grantedCapabilities = grantedCapabilities
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey {
        case disposition
        case bridgeName
        case bridgePublicKey
        case bridgeFingerprint
        case requestSigningRequired
        case payloadEncryptionRequired
        case grantedCapabilities
        case detail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        disposition = try container.decode(DeckPairingDisposition.self, forKey: .disposition)
        bridgeName = try container.decode(String.self, forKey: .bridgeName)
        bridgePublicKey = try container.decode(String.self, forKey: .bridgePublicKey)
        bridgeFingerprint = try container.decode(String.self, forKey: .bridgeFingerprint)
        requestSigningRequired = try container.decode(Bool.self, forKey: .requestSigningRequired)
        payloadEncryptionRequired = try container.decode(Bool.self, forKey: .payloadEncryptionRequired)
        grantedCapabilities = try container.decodeIfPresent([String].self, forKey: .grantedCapabilities)
            ?? DeckBridgeCapability.defaultCompanionCapabilities
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
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
    public var capabilities: [String]
    public var pairedAt: Date
    public var lastSeenAt: Date

    public init(
        id: String,
        name: String,
        fingerprint: String,
        capabilities: [String] = [],
        pairedAt: Date,
        lastSeenAt: Date
    ) {
        self.id = id
        self.name = name
        self.fingerprint = fingerprint
        self.capabilities = capabilities
        self.pairedAt = pairedAt
        self.lastSeenAt = lastSeenAt
    }
}

public enum DeckBridgeCapability {
    public static let deckRead = "deck.read"
    public static let deckPerform = "deck.perform"
    public static let inputTrackpad = "input.trackpad"

    public static let defaultCompanionCapabilities = [
        deckRead,
        deckPerform,
        inputTrackpad,
    ]
}
