import Foundation

public struct DeckCockpitState: Codable, Equatable, Sendable {
    public var title: String?
    public var detail: String?
    public var pages: [DeckCockpitPage]

    public init(
        title: String? = nil,
        detail: String? = nil,
        pages: [DeckCockpitPage]
    ) {
        self.title = title
        self.detail = detail
        self.pages = pages
    }
}

public struct DeckCockpitPage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var columns: Int
    public var tiles: [DeckCockpitTile]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        columns: Int = 4,
        tiles: [DeckCockpitTile]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.columns = columns
        self.tiles = tiles
    }
}

public struct DeckCockpitTile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var shortcutID: String
    public var title: String
    public var subtitle: String?
    public var iconSystemName: String
    public var accentToken: String?
    public var deckID: String?
    public var categoryTint: String?
    public var actionID: String?
    public var payload: [String: DeckValue]
    public var isEnabled: Bool
    public var isActive: Bool

    public init(
        id: String,
        shortcutID: String,
        title: String,
        subtitle: String? = nil,
        iconSystemName: String,
        accentToken: String? = nil,
        deckID: String? = nil,
        categoryTint: String? = nil,
        actionID: String? = nil,
        payload: [String: DeckValue] = [:],
        isEnabled: Bool = true,
        isActive: Bool = false
    ) {
        self.id = id
        self.shortcutID = shortcutID
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
        self.accentToken = accentToken
        self.deckID = deckID
        self.categoryTint = categoryTint
        self.actionID = actionID
        self.payload = payload
        self.isEnabled = isEnabled
        self.isActive = isActive
    }
}
