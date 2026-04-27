import Foundation

public struct DeckActionRequest: Codable, Equatable, Sendable {
    public var pageID: String?
    public var actionID: String
    public var payload: [String: DeckValue]

    public init(
        pageID: String? = nil,
        actionID: String,
        payload: [String: DeckValue] = [:]
    ) {
        self.pageID = pageID
        self.actionID = actionID
        self.payload = payload
    }
}

public struct DeckActionResult: Codable, Equatable, Sendable {
    public var ok: Bool
    public var summary: String
    public var detail: String?
    public var runtimeSnapshot: DeckRuntimeSnapshot?
    public var suggestedActions: [DeckSuggestedAction]

    public init(
        ok: Bool,
        summary: String,
        detail: String? = nil,
        runtimeSnapshot: DeckRuntimeSnapshot? = nil,
        suggestedActions: [DeckSuggestedAction] = []
    ) {
        self.ok = ok
        self.summary = summary
        self.detail = detail
        self.runtimeSnapshot = runtimeSnapshot
        self.suggestedActions = suggestedActions
    }
}

public struct DeckSuggestedAction: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var iconSystemName: String?

    public init(id: String, title: String, iconSystemName: String? = nil) {
        self.id = id
        self.title = title
        self.iconSystemName = iconSystemName
    }
}
