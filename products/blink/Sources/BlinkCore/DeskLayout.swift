import Foundation

public struct DeskFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct DeskPanel: Codable, Equatable, Sendable {
    public var id: String
    public var slot: Int?
    public var mode: String
    public var frame: DeskFrame
    public var display: Int

    public init(id: String, slot: Int? = nil, mode: String, frame: DeskFrame, display: Int) {
        self.id = id; self.slot = slot; self.mode = mode; self.frame = frame; self.display = display
    }
}

public struct DeskLayout: Codable, Equatable, Sendable {
    public var name: String
    public var updated: Date
    public var panels: [DeskPanel]

    public init(name: String, updated: Date = Date(), panels: [DeskPanel]) {
        self.name = name; self.updated = updated; self.panels = panels
    }
}

public enum DeskLayoutStoreError: Error, LocalizedError, Equatable {
    case invalidName(String)
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name): "invalid desk name '\(name)'"
        case .notFound(let name): "no saved desk named '\(name)'"
        }
    }
}

public struct DeskLayoutStore: Sendable {
    public let directory: URL
    public init(directory: URL = BlinkPaths.desks()) { self.directory = directory }

    public static func validate(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !value.isEmpty, value.count <= 80,
              value.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else { throw DeskLayoutStoreError.invalidName(name) }
        return value
    }

    public func url(for name: String) throws -> URL {
        directory.appendingPathComponent("\(try Self.validate(name)).json")
    }

    public func save(_ layout: DeskLayout) throws {
        let name = try Self.validate(layout.name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = try url(for: name)
        let temporary = directory.appendingPathComponent(".\(name).\(UUID().uuidString).tmp")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(layout)
        data.append(0x0a)
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: data); try handle.synchronize(); try handle.close()
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? handle.close(); try? FileManager.default.removeItem(at: temporary); throw error
        }
    }

    public func load(_ name: String) throws -> DeskLayout {
        let file = try url(for: name)
        guard FileManager.default.fileExists(atPath: file.path) else { throw DeskLayoutStoreError.notFound(name) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DeskLayout.self, from: Data(contentsOf: file))
    }

    public func list() throws -> [DeskLayout] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { try? load($0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func delete(_ name: String) throws {
        let file = try url(for: name)
        guard FileManager.default.fileExists(atPath: file.path) else { throw DeskLayoutStoreError.notFound(name) }
        try FileManager.default.removeItem(at: file)
    }
}
