import Foundation
import SQLite3

// MARK: - Search Result

struct OcrSearchResult {
    let id: Int64
    let wid: UInt32
    let app: String
    let title: String
    let frame: WindowFrame
    let fullText: String
    let snippet: String
    let timestamp: Date
}

// MARK: - SQLite OCR Store

final class OcrStore {
    static let shared = OcrStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.arach.lattices.ocrstore", qos: .background)

    // Cached prepared statements
    private var insertStmt: OpaquePointer?
    private var cleanupStmt: OpaquePointer?

    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // MARK: - Open / Schema

    func open() {
        queue.sync {
            guard db == nil else { return }

            let dir = NSHomeDirectory() + "/.lattices"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let path = dir + "/ocr.db"

            guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
                DiagnosticLog.shared.error("OcrStore: failed to open \(path)")
                return
            }

            // WAL mode for concurrent reads/writes
            exec("PRAGMA journal_mode=WAL")
            exec("PRAGMA synchronous=NORMAL")

            // Main table
            exec("""
                CREATE TABLE IF NOT EXISTS ocr_entry (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    wid INTEGER NOT NULL,
                    app TEXT NOT NULL,
                    title TEXT NOT NULL,
                    frame_x REAL,
                    frame_y REAL,
                    frame_w REAL,
                    frame_h REAL,
                    full_text TEXT NOT NULL,
                    timestamp REAL NOT NULL
                )
            """)
            exec("CREATE INDEX IF NOT EXISTS idx_ocr_entry_timestamp ON ocr_entry(timestamp)")
            exec("CREATE INDEX IF NOT EXISTS idx_ocr_entry_wid ON ocr_entry(wid)")

            // FTS5 content-sync table
            exec("""
                CREATE VIRTUAL TABLE IF NOT EXISTS ocr_fts USING fts5(
                    full_text, app, title,
                    content='ocr_entry', content_rowid='id'
                )
            """)

            // Triggers to keep FTS in sync
            exec("""
                CREATE TRIGGER IF NOT EXISTS ocr_fts_ai AFTER INSERT ON ocr_entry BEGIN
                    INSERT INTO ocr_fts(rowid, full_text, app, title)
                    VALUES (new.id, new.full_text, new.app, new.title);
                END
            """)
            exec("""
                CREATE TRIGGER IF NOT EXISTS ocr_fts_ad AFTER DELETE ON ocr_entry BEGIN
                    INSERT INTO ocr_fts(ocr_fts, rowid, full_text, app, title)
                    VALUES ('delete', old.id, old.full_text, old.app, old.title);
                END
            """)
            exec("""
                CREATE TRIGGER IF NOT EXISTS ocr_fts_au AFTER UPDATE ON ocr_entry BEGIN
                    INSERT INTO ocr_fts(ocr_fts, rowid, full_text, app, title)
                    VALUES ('delete', old.id, old.full_text, old.app, old.title);
                    INSERT INTO ocr_fts(rowid, full_text, app, title)
                    VALUES (new.id, new.full_text, new.app, new.title);
                END
            """)

            // Prepare cached statements
            prepareInsert()
            prepareCleanup()

            // Run cleanup on open
            cleanupSync(olderThanDays: 3)

            DiagnosticLog.shared.info("OcrStore: opened \(path)")
        }
    }

    // MARK: - Insert (batch, async)

    func insert(results: [OcrWindowResult]) {
        guard !results.isEmpty else { return }
        queue.async { [weak self] in
            guard let self, let db = self.db, let stmt = self.insertStmt else { return }

            sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

            for r in results {
                let ts = r.timestamp.timeIntervalSince1970
                sqlite3_bind_int(stmt, 1, Int32(r.wid))
                self.bindText(stmt, 2, r.app)
                self.bindText(stmt, 3, r.title)
                sqlite3_bind_double(stmt, 4, r.frame.x)
                sqlite3_bind_double(stmt, 5, r.frame.y)
                sqlite3_bind_double(stmt, 6, r.frame.w)
                sqlite3_bind_double(stmt, 7, r.frame.h)
                self.bindText(stmt, 8, r.fullText)
                sqlite3_bind_double(stmt, 9, ts)
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
            }

            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    // MARK: - Search (FTS5, synchronous)

    func search(query: String, app: String? = nil, limit: Int = 50) -> [OcrSearchResult] {
        guard let db else { return [] }

        var sql = """
            SELECT e.id, e.wid, e.app, e.title,
                   e.frame_x, e.frame_y, e.frame_w, e.frame_h,
                   e.full_text, e.timestamp,
                   snippet(ocr_fts, 0, '»', '«', '…', 32) AS snip
            FROM ocr_fts f
            JOIN ocr_entry e ON e.id = f.rowid
            WHERE ocr_fts MATCH ?1
        """
        if app != nil { sql += " AND e.app = ?2" }
        sql += " ORDER BY rank LIMIT ?3"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt!, 1, query)
        if let app { bindText(stmt!, 2, app) }
        sqlite3_bind_int(stmt!, 3, Int32(limit))

        var results: [OcrSearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(rowToSearchResult(stmt!))
        }
        return results
    }

    // MARK: - History (per-window, synchronous)

    func history(wid: UInt32, limit: Int = 50) -> [OcrSearchResult] {
        guard let db else { return [] }

        let sql = """
            SELECT id, wid, app, title,
                   frame_x, frame_y, frame_w, frame_h,
                   full_text, timestamp, '' AS snip
            FROM ocr_entry
            WHERE wid = ?1
            ORDER BY timestamp DESC
            LIMIT ?2
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt!, 1, Int32(wid))
        sqlite3_bind_int(stmt!, 2, Int32(limit))

        var results: [OcrSearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(rowToSearchResult(stmt!))
        }
        return results
    }

    // MARK: - Recent (chronological, synchronous)

    func recent(limit: Int = 50) -> [OcrSearchResult] {
        guard let db else { return [] }

        let sql = """
            SELECT id, wid, app, title,
                   frame_x, frame_y, frame_w, frame_h,
                   full_text, timestamp, '' AS snip
            FROM ocr_entry
            ORDER BY timestamp DESC
            LIMIT ?1
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt!, 1, Int32(limit))

        var results: [OcrSearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(rowToSearchResult(stmt!))
        }
        return results
    }

    // MARK: - Cleanup

    private func cleanupSync(olderThanDays days: Int) {
        guard let db, let stmt = cleanupStmt else { return }
        let cutoff = Date().timeIntervalSince1970 - Double(days * 86400)
        sqlite3_bind_double(stmt, 1, cutoff)
        sqlite3_step(stmt)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)

        let deleted = sqlite3_changes(db)
        if deleted > 0 {
            DiagnosticLog.shared.info("OcrStore: cleaned up \(deleted) entries older than \(days) days")
        }
    }

    // MARK: - Helpers

    private func exec(_ sql: String) {
        guard let db else { return }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            DiagnosticLog.shared.error("OcrStore SQL error: \(msg)")
            sqlite3_free(err)
        }
    }

    private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
    }

    private func prepareInsert() {
        let sql = """
            INSERT INTO ocr_entry (wid, app, title, frame_x, frame_y, frame_w, frame_h, full_text, timestamp)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
        """
        sqlite3_prepare_v2(db, sql, -1, &insertStmt, nil)
    }

    private func prepareCleanup() {
        let sql = "DELETE FROM ocr_entry WHERE timestamp < ?1"
        sqlite3_prepare_v2(db, sql, -1, &cleanupStmt, nil)
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String {
        if let cStr = sqlite3_column_text(stmt, index) {
            return String(cString: cStr)
        }
        return ""
    }

    private func rowToSearchResult(_ stmt: OpaquePointer) -> OcrSearchResult {
        OcrSearchResult(
            id: sqlite3_column_int64(stmt, 0),
            wid: UInt32(sqlite3_column_int(stmt, 1)),
            app: columnText(stmt, 2),
            title: columnText(stmt, 3),
            frame: WindowFrame(
                x: sqlite3_column_double(stmt, 4),
                y: sqlite3_column_double(stmt, 5),
                w: sqlite3_column_double(stmt, 6),
                h: sqlite3_column_double(stmt, 7)
            ),
            fullText: columnText(stmt, 8),
            snippet: columnText(stmt, 10),
            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
        )
    }
}
