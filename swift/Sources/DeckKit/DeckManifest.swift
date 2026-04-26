import Foundation

public struct DeckManifest: Codable, Equatable, Sendable {
    public var product: DeckProductIdentity
    public var security: DeckSecurityConfiguration
    public var capabilities: [DeckCapability]
    public var pages: [DeckPage]

    public init(
        product: DeckProductIdentity,
        security: DeckSecurityConfiguration,
        capabilities: [DeckCapability],
        pages: [DeckPage]
    ) {
        self.product = product
        self.security = security
        self.capabilities = capabilities
        self.pages = pages
    }
}

public struct DeckProductIdentity: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var owner: String

    public init(id: String, displayName: String, owner: String) {
        self.id = id
        self.displayName = displayName
        self.owner = owner
    }
}

public enum DeckCapability: String, Codable, CaseIterable, Sendable {
    case voiceAgent
    case layoutControl
    case appSwitching
    case taskSwitching
    case screenPreview
    case trackpadProxy
    case historyFeed
    case questionCards
    case embeddedSecurityDelegation
}

public struct DeckPage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var iconSystemName: String
    public var kind: DeckPageKind
    public var accentToken: String?

    public init(
        id: String,
        title: String,
        iconSystemName: String,
        kind: DeckPageKind,
        accentToken: String? = nil
    ) {
        self.id = id
        self.title = title
        self.iconSystemName = iconSystemName
        self.kind = kind
        self.accentToken = accentToken
    }
}

public enum DeckPageKind: String, Codable, CaseIterable, Sendable {
    case cockpit
    case voice
    case mac
    case layout
    case `switch`
    case history
    case custom
}

public struct DeckSecurityConfiguration: Codable, Equatable, Sendable {
    public var mode: DeckSecurityMode
    public var pairingStrategy: DeckPairingStrategy
    public var requestSigningRequired: Bool
    public var delegatedOwner: String?

    public init(
        mode: DeckSecurityMode,
        pairingStrategy: DeckPairingStrategy,
        requestSigningRequired: Bool,
        delegatedOwner: String? = nil
    ) {
        self.mode = mode
        self.pairingStrategy = pairingStrategy
        self.requestSigningRequired = requestSigningRequired
        self.delegatedOwner = delegatedOwner
    }
}

public extension DeckSecurityConfiguration {
    static func standaloneBonjour(requestSigningRequired: Bool = true) -> Self {
        DeckSecurityConfiguration(
            mode: .standalone,
            pairingStrategy: .bonjour,
            requestSigningRequired: requestSigningRequired
        )
    }

    static func embeddedDelegated(
        owner: String,
        requestSigningRequired: Bool = true
    ) -> Self {
        DeckSecurityConfiguration(
            mode: .embedded,
            pairingStrategy: .delegated,
            requestSigningRequired: requestSigningRequired,
            delegatedOwner: owner
        )
    }
}

public enum DeckSecurityMode: String, Codable, CaseIterable, Sendable {
    case standalone
    case embedded
}

public enum DeckPairingStrategy: String, Codable, CaseIterable, Sendable {
    case bonjour
    case delegated
}
