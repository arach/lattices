import Foundation

/// Errors thrown by `WorkspaceStore`.
public enum WorkspaceStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    /// `config.json` exists but is not readable JSON. We refuse to write over a
    /// file we cannot parse — a malformed config is a user's work to recover,
    /// never ours to overwrite.
    case configUnreadable(path: String)
    case unknownWorkspace(name: String)
    case invalidName(String)
    case markNotFound(path: String)
    /// The asset is not one of the image types a panel mark can render.
    case markUnsupportedType(ext: String)
    case markTooLarge(bytes: Int, limit: Int)

    public var description: String {
        switch self {
        case .configUnreadable(let path):
            "config at \(path) is not valid JSON — fix or move it, then retry"
        case .unknownWorkspace(let name):
            "no workspace named '\(name)' — create it with `blink workspace init \(name)`"
        case .invalidName(let name):
            "'\(name)' is not a usable workspace name (letters, digits, hyphens)"
        case .markNotFound(let path):
            "no readable file at \(path)"
        case .markUnsupportedType(let ext):
            "'\(ext)' is not a supported mark format (\(WorkspaceStore.markFormats.sorted().joined(separator: ", ")))"
        case .markTooLarge(let bytes, let limit):
            "mark is \(bytes) bytes; the limit is \(limit)"
        }
    }
}

/// Reads and writes the `workspaces` section of `config.json` **surgically**.
///
/// The config file is a shared surface: the app owns most of it, agents own the
/// rest, and both write it. So this store never re-encodes a typed `BlinkConfig`
/// — it parses the file as generic JSON, replaces exactly the one key it owns,
/// and writes the rest back untouched. That is the same never-erase discipline
/// the frontmatter codec applies to foreign keys, applied to config.
///
/// Writes are atomic (temp + fsync + rename), so the app's config watcher either
/// sees the old file or the new one, never a half-written one, and hot-applies
/// the change without a restart.
public struct WorkspaceStore: Sendable {
    /// Image formats a panel mark may use.
    public static let markFormats: Set<String> = ["svg", "png", "jpg", "jpeg", "gif", "webp", "pdf", "tiff"]
    /// Brand marks render at 20pt; anything past this is a mistake, not a logo.
    public static let markSizeLimit = 2 * 1024 * 1024

    private let home: URL
    public let configURL: URL

    public init(home: URL = BlinkPaths.home()) {
        self.home = home
        self.configURL = home.appendingPathComponent("config.json", isDirectory: false)
    }

    /// Where installed marks land: `<home>/attachments/marks`.
    public var marksDirectory: URL {
        home.appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent("marks", isDirectory: true)
    }

    // MARK: - Names

    /// Workspace names are slugs — they are JSON keys, they appear in note
    /// frontmatter, and an installed mark is filed under them. Normalizing up
    /// front means `"Q3 Planning"` and `q3-planning` are the same workspace.
    public static func normalize(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Require at least one ASCII alphanumeric: those are the only characters
        // `Slug` keeps, so anything else would collapse to the "untitled"
        // fallback and quietly address the wrong workspace.
        guard trimmed.contains(where: { $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw WorkspaceStoreError.invalidName(name)
        }
        return Slug.generate(from: trimmed)
    }

    // MARK: - Read

    /// Every defined workspace, keyed by name. Absent config → no workspaces,
    /// which is the correct unbranded default rather than an error.
    public func all() throws -> [String: Workspace] {
        let raw = try configObject()
        guard let dict = raw["workspaces"] as? [String: Any] else { return [:] }
        return try decode([String: Workspace].self, from: dict)
    }

    public func workspace(named name: String) throws -> Workspace? {
        try all()[try Self.normalize(name)]
    }

    /// The config's named style registry — the base a workspace's `style` names.
    public func styles() throws -> [String: Treatment] {
        let raw = try configObject()
        guard let dict = raw["styles"] as? [String: Any] else { return [:] }
        return try decode([String: Treatment].self, from: dict)
    }

    // MARK: - Write

    /// Create or replace a workspace definition. Returns the normalized name.
    @discardableResult
    public func save(_ workspace: Workspace, named name: String) throws -> String {
        let key = try Self.normalize(name)
        try mutate { workspaces in
            workspaces[key] = try encodeToObject(workspace)
        }
        return key
    }

    /// Read-modify-write one workspace in place, creating it if absent.
    /// The whole point of the feature's write path: an agent adjusts one brand
    /// field without restating the rest of the brand — or the rest of the config.
    @discardableResult
    public func update(
        named name: String,
        createIfMissing: Bool = true,
        _ edit: (inout Workspace) throws -> Void
    ) throws -> Workspace {
        let key = try Self.normalize(name)
        let existing = try all()[key]
        if existing == nil, !createIfMissing {
            throw WorkspaceStoreError.unknownWorkspace(name: key)
        }
        var workspace = existing ?? Workspace()
        try edit(&workspace)
        try save(workspace, named: key)
        return workspace
    }

    /// Forget a workspace definition. Notes that reference it are untouched and
    /// simply render unbranded — membership lives in the note, not here.
    @discardableResult
    public func remove(named name: String) throws -> Bool {
        let key = try Self.normalize(name)
        var removed = false
        try mutate { workspaces in
            removed = workspaces.removeValue(forKey: key) != nil
        }
        return removed
    }

    // MARK: - Brand assets

    /// Copy a brand mark into `<home>/attachments/marks` and return the relative
    /// path to record in a treatment (`marks/<name>.<ext>`).
    ///
    /// Installing rather than referencing an arbitrary path is the safe default:
    /// the app only ever reads marks from inside the attachments directory (see
    /// `BlinkPaths.attachment(named:)`), so a brand asset that lives anywhere
    /// else would silently fail to render. Type and size are checked here so the
    /// failure is a clear CLI error instead of a blank panel corner.
    public func installMark(from source: URL, for name: String) throws -> String {
        let key = try Self.normalize(name)
        let src = source.standardizedFileURL.resolvingSymlinksInPath()

        guard let values = try? src.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true
        else { throw WorkspaceStoreError.markNotFound(path: source.path) }

        let ext = src.pathExtension.lowercased()
        guard Self.markFormats.contains(ext) else {
            throw WorkspaceStoreError.markUnsupportedType(ext: ext.isEmpty ? "(none)" : ext)
        }
        let size = values.fileSize ?? 0
        guard size <= Self.markSizeLimit else {
            throw WorkspaceStoreError.markTooLarge(bytes: size, limit: Self.markSizeLimit)
        }

        let data = try Data(contentsOf: src)
        try FileManager.default.createDirectory(at: marksDirectory, withIntermediateDirectories: true)
        let destination = marksDirectory.appendingPathComponent("\(key).\(ext)", isDirectory: false)
        try data.write(to: destination, options: .atomic)
        return "marks/\(key).\(ext)"
    }

    // MARK: - Config plumbing

    /// The whole config file as a generic JSON object. Missing file → empty
    /// object; unparseable file → throw, so we never overwrite what we can't read.
    private func configObject() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: configURL), !data.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else { throw WorkspaceStoreError.configUnreadable(path: configURL.path) }
        return dict
    }

    /// Mutate only the `workspaces` sub-object and write the file back whole.
    private func mutate(_ edit: (inout [String: Any]) throws -> Void) throws {
        var config = try configObject()
        var workspaces = (config["workspaces"] as? [String: Any]) ?? [:]
        try edit(&workspaces)
        if workspaces.isEmpty {
            config.removeValue(forKey: "workspaces")
        } else {
            config["workspaces"] = workspaces
        }
        try write(config)
    }

    /// Atomic write: temp file in the same directory, fsync, rename. Matches
    /// `NoteFileStore.save` — the config watcher must never observe a torn file.
    private func write(_ config: [String: Any]) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: config,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )

        let temp = configURL.deletingLastPathComponent()
            .appendingPathComponent(".config.json.tmp", isDirectory: false)
        if FileManager.default.fileExists(atPath: temp.path) {
            try FileManager.default.removeItem(at: temp)
        }
        FileManager.default.createFile(atPath: temp.path, contents: nil)

        let handle = try FileHandle(forWritingTo: temp)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: temp)
            throw error
        }

        if FileManager.default.fileExists(atPath: configURL.path) {
            _ = try FileManager.default.replaceItemAt(configURL, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: configURL)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(type, from: data)
    }

    private func encodeToObject(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
