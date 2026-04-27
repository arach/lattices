import Foundation

public struct DeckTrackpadState: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var isAvailable: Bool
    public var statusTitle: String
    public var statusDetail: String?
    public var pointerScale: Double
    public var scrollScale: Double
    public var supportsDragLock: Bool

    public init(
        isEnabled: Bool,
        isAvailable: Bool,
        statusTitle: String,
        statusDetail: String? = nil,
        pointerScale: Double = 1.6,
        scrollScale: Double = 1.0,
        supportsDragLock: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.isAvailable = isAvailable
        self.statusTitle = statusTitle
        self.statusDetail = statusDetail
        self.pointerScale = pointerScale
        self.scrollScale = scrollScale
        self.supportsDragLock = supportsDragLock
    }
}

public struct DeckTrackpadEventRequest: Codable, Equatable, Sendable {
    public var event: DeckTrackpadEvent
    public var dx: Double
    public var dy: Double

    public init(
        event: DeckTrackpadEvent,
        dx: Double = 0,
        dy: Double = 0
    ) {
        self.event = event
        self.dx = dx
        self.dy = dy
    }
}

public enum DeckTrackpadEvent: String, Codable, CaseIterable, Sendable {
    case move
    case click
    case rightClick
    case scroll
    case mouseDown
    case mouseUp
    case drag
}

public struct DeckTrackpadEventResult: Codable, Equatable, Sendable {
    public var ok: Bool

    public init(ok: Bool) {
        self.ok = ok
    }
}
