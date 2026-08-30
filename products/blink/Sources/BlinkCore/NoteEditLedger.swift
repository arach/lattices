import CSQLite
import Foundation

/// Why this row exists. `externalDetected` is only for reconcile: Blink saw
/// the file change after the fact and does not know the writer or exact time.
public enum NoteEditKind: String, Sendable {
    case create
    case update
    case delete
    case externalDetected = "external_detected"
}

/// One append-only row. The markdown file remains note truth; this is a
/// sidecar history.
public struct NoteEditEvent: Equatable, Sendable {
    public var id: Int64
    public var noteID: String
    public var kind: NoteEditKind
    public var writer: String?
    public var at: Date
    public var detectedAt: Date?

    public init(
        id: Int64,
        noteID: String,
        kind: NoteEditKind,
        writer: String?,
        at: Date,
        detectedAt: Date? = nil
    ) {
        self.id = id
        self.noteID = noteID
        self.kind = kind
        self.writer = writer
        self.at = at
        self.detectedAt = detectedAt
    }
}

/// Global SQLite ledger next to Notes. Never throws into a note save: open
/// and append failures are swallowed by the caller.
public final class NoteEditLedger: @unchecked Sendable {
    public let fileURL: URL
    private var db: OpaquePointer?
    private let lock = NSLock()

    public init?(fileURL: URL) {
        self.fileURL = fileURL
        let parent = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            fileURL.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        db = handle
        guard Self.migrate(handle) else {
            sqlite3_close(handle)
            db = nil
            return nil
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    /// Ledger beside a Notes directory: `<parent>/edits.sqlite`.
    public static func besideNotes(_ notesDirectory: URL) -> NoteEditLedger? {
        NoteEditLedger(
            fileURL: notesDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("edits.sqlite", isDirectory: false)
        )
    }

    @discardableResult
    public func record(
        noteID: String,
        kind: NoteEditKind,
        writer: String?,
        at: Date = Date(),
        detectedAt: Date? = nil
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return false }
        let sql = """
            INSERT INTO edits (note_id, kind, writer, at, detected_at)
            VALUES (?, ?, ?, ?, ?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return false
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, noteID)
        bind(stmt, 2, kind.rawValue)
        bind(stmt, 3, writer)
        bind(stmt, 4, Self.stamp(at))
        bind(stmt, 5, detectedAt.map(Self.stamp))
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    public func history(noteID: String, limit: Int = 50) -> [NoteEditEvent] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let sql = """
            SELECT id, note_id, kind, writer, at, detected_at
            FROM edits
            WHERE note_id = ?
            ORDER BY id DESC
            LIMIT ?;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, noteID)
        sqlite3_bind_int(stmt, 2, Int32(max(limit, 0)))
        var rows: [NoteEditEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let event = row(stmt) { rows.append(event) }
        }
        return rows
    }

    public func last(noteID: String) -> NoteEditEvent? {
        history(noteID: noteID, limit: 1).first
    }

    private static func migrate(_ db: OpaquePointer) -> Bool {
        let sql = """
            CREATE TABLE IF NOT EXISTS edits (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                note_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                writer TEXT,
                at TEXT NOT NULL,
                detected_at TEXT
            );
            CREATE INDEX IF NOT EXISTS edits_note_id ON edits(note_id, id);
            """
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func row(_ stmt: OpaquePointer) -> NoteEditEvent? {
        let id = sqlite3_column_int64(stmt, 0)
        guard let noteID = column(stmt, 1),
              let kindRaw = column(stmt, 2),
              let kind = NoteEditKind(rawValue: kindRaw),
              let atRaw = column(stmt, 4),
              let at = Self.parse(atRaw)
        else { return nil }
        let detected = column(stmt, 5).flatMap(Self.parse)
        return NoteEditEvent(
            id: id,
            noteID: noteID,
            kind: kind,
            writer: column(stmt, 3),
            at: at,
            detectedAt: detected
        )
    }

    private func column(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }

    private static func stamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private static func parse(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
