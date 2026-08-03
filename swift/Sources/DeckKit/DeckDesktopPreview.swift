import Foundation

public enum DeckDesktopPreviewScope: String, Codable, CaseIterable, Sendable {
    case display
    case frontmostWindow
}

/// A bounded request for one current desktop frame.
///
/// Desktop preview is intentionally pull-based: the iPad asks for the next
/// frame only after it has decoded the previous one. That keeps a slow or
/// backgrounded client from building an unbounded capture queue on the Mac.
public struct DeckDesktopPreviewRequest: Codable, Equatable, Sendable {
    public var displayIndex: Int?
    public var maxPixelWidth: Int
    public var scope: DeckDesktopPreviewScope

    public init(
        displayIndex: Int? = nil,
        maxPixelWidth: Int = 1_440,
        scope: DeckDesktopPreviewScope = .display
    ) {
        self.displayIndex = displayIndex
        self.maxPixelWidth = maxPixelWidth
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey {
        case displayIndex
        case maxPixelWidth
        case scope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayIndex = try container.decodeIfPresent(Int.self, forKey: .displayIndex)
        maxPixelWidth = try container.decodeIfPresent(Int.self, forKey: .maxPixelWidth) ?? 1_440
        scope = try container.decodeIfPresent(DeckDesktopPreviewScope.self, forKey: .scope) ?? .display
    }
}

public struct DeckDesktopPreviewDisplay: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { displayIndex }
    public var displayIndex: Int
    public var name: String
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(
        displayIndex: Int,
        name: String,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.displayIndex = displayIndex
        self.name = name
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// One encrypted JPEG frame plus enough display metadata for the iPad to let
/// the user move between monitors without a second discovery request.
public struct DeckDesktopPreviewFrame: Codable, Equatable, Sendable {
    public var capturedAt: Date
    public var displayIndex: Int
    public var displays: [DeckDesktopPreviewDisplay]
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var jpegBase64: String

    public init(
        capturedAt: Date = .now,
        displayIndex: Int,
        displays: [DeckDesktopPreviewDisplay],
        pixelWidth: Int,
        pixelHeight: Int,
        jpegBase64: String
    ) {
        self.capturedAt = capturedAt
        self.displayIndex = displayIndex
        self.displays = displays
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.jpegBase64 = jpegBase64
    }
}
