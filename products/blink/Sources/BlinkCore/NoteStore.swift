import Foundation

public extension Notification.Name {
    /// Posted after a note is created. `userInfo["id"]` holds the note id.
    static let blinkNoteCreated = Notification.Name("blink.note.created")
    /// Posted after a note is updated. `userInfo["id"]` holds the note id.
    static let blinkNoteUpdated = Notification.Name("blink.note.updated")
    /// Posted after a note is deleted. `userInfo["id"]` holds the note id.
    static let blinkNoteDeleted = Notification.Name("blink.note.deleted")
}

/// The single source of truth for notes. Owns the in-memory index and coordinates
/// persistence through a `NoteFileStore`. An actor so concurrent callers cannot
/// corrupt the index; value types crossing the boundary are `Sendable`.
///
/// After each mutation it posts a notification (on the injected center,
/// `.default` in the app) so UI and other windows can react.
public actor NoteStore {
    private let fileStore: NoteFileStore
    private var notes: [String: Note] = [:]
    private let clock: @Sendable () -> Date
    private let notificationCenter: NotificationCenter
    private let tombstoneStore: BlinkTombstoneStore?

    public init(
        fileStore: NoteFileStore,
        notificationCenter: NotificationCenter = .default,
        tombstoneStore: BlinkTombstoneStore? = nil
    ) {
        self.fileStore = fileStore
        self.clock = { Date() }
        self.notificationCenter = notificationCenter
        self.tombstoneStore = tombstoneStore
    }

    /// Testing hook: inject a clock so `createdAt`/`updatedAt` are controllable.
    init(
        fileStore: NoteFileStore,
        notificationCenter: NotificationCenter = .default,
        tombstoneStore: BlinkTombstoneStore? = nil,
        clock: @escaping @Sendable () -> Date
    ) {
        self.fileStore = fileStore
        self.clock = clock
        self.notificationCenter = notificationCenter
        self.tombstoneStore = tombstoneStore
    }

    /// Read the directory into memory. Returns all notes sorted `updatedAt` desc.
    @discardableResult
    public func load() throws -> [Note] {
        let loaded = try fileStore.loadAll()
        notes = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        return all()
    }

    /// Create a new note from raw markdown content. Assigns a unique slug id and
    /// stamps timestamps, then persists.
    @discardableResult
    public func create(
        content: String,
        presentation: NotePresentation = NotePresentation(),
        writer: String? = nil
    ) async throws -> Note {
        let base = Slug.generate(from: Note.extractTitle(from: content))
        let id = Slug.unique(base, existing: Set(notes.keys))
        let now = clock()
        var presentation = presentation
        if let writer { presentation.lastWriter = writer }
        let note = normalized(
            Note(
                id: id,
                content: content,
                createdAt: now,
                updatedAt: now,
                tags: [],
                pinned: false,
                presentation: presentation
            )
        )
        try fileStore.save(note, writer: writer)
        notes[id] = note
        try? await tombstoneStore?.remove(id: id)
        post(.blinkNoteCreated, id: id)
        return note
    }

    /// Replace a note's content and bump `updatedAt`. Throws if `id` is unknown.
    ///
    /// Content is the only field this API owns. All other metadata (tags,
    /// pinned, createdAt, extra frontmatter) is re-read from disk at save time,
    /// so an agent editing the file's frontmatter while the note is open in a
    /// panel is never clobbered by the editor's next keystroke save.
    @discardableResult
    public func update(id: String, content: String, writer: String? = nil) throws -> Note {
        guard var note = notes[id] else {
            throw NoteFileStoreError.noteNotFound(id: id)
        }
        if let onDisk = try? fileStore.load(id: id) {
            note.tags = onDisk.tags
            note.pinned = onDisk.pinned
            note.createdAt = onDisk.createdAt
            note.extraFrontmatter = onDisk.extraFrontmatter
        }
        note.content = content
        note.updatedAt = clock()
        if let writer { note.presentation.lastWriter = writer }
        note = normalized(note)
        try fileStore.save(note, writer: writer)
        notes[id] = note
        post(.blinkNoteUpdated, id: id)
        return note
    }

    /// Set a note's sheet template (the Blink-owned `blink.sheet` presentation
    /// field) and persist. Like `update(content:)`, foreign frontmatter is
    /// re-read from disk so a concurrent external edit is never clobbered;
    /// content stays as last known (an open panel re-flushes its own edits).
    /// Pass `nil` to clear the override and fall back to the config default.
    @discardableResult
    public func updateSheet(id: String, sheet: String?, writer: String? = nil) throws -> Note {
        guard var note = notes[id] else {
            throw NoteFileStoreError.noteNotFound(id: id)
        }
        if let onDisk = try? fileStore.load(id: id) {
            note.tags = onDisk.tags
            note.pinned = onDisk.pinned
            note.createdAt = onDisk.createdAt
            note.extraFrontmatter = onDisk.extraFrontmatter
        }
        note.presentation.sheet = sheet
        note.updatedAt = clock()
        if let writer { note.presentation.lastWriter = writer }
        note = normalized(note)
        try fileStore.save(note, writer: writer)
        notes[id] = note
        post(.blinkNoteUpdated, id: id)
        return note
    }

    /// Delete a note by id. Throws if `id` is unknown.
    public func delete(id: String, writer: String? = nil) async throws {
        guard notes[id] != nil else {
            throw NoteFileStoreError.noteNotFound(id: id)
        }
        try await tombstoneStore?.recordDeletion(id: id, at: clock())
        try fileStore.delete(id: id, writer: writer)
        notes[id] = nil
        post(.blinkNoteDeleted, id: id)
    }

    /// The difference between the on-disk directory and the in-memory index,
    /// as note ids. Returned by `reconcile()` so callers can log or react.
    public struct ReconcileDiff: Equatable, Sendable {
        public var created: [String] = []
        public var updated: [String] = []
        public var deleted: [String] = []
        public var tombstoneFailures: [String] = []
        public var isEmpty: Bool {
            created.isEmpty && updated.isEmpty && deleted.isEmpty && tombstoneFailures.isEmpty
        }
    }

    /// Re-scan the directory and reconcile the in-memory index with it,
    /// posting created/updated/deleted notifications for every difference.
    /// This is what makes the filesystem a real API: any external writer
    /// (the `blink` CLI, an agent, a sync tool) becomes visible to every UI
    /// surface the moment the app notices the change.
    ///
    /// Files that fail to decode are skipped, not treated as deletions — a
    /// malformed foreign file must never cascade into closing panels.
    @discardableResult
    public func reconcile() async -> ReconcileDiff {
        let onDisk = Dictionary(
            fileStore.loadAllLenient().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let present = fileStore.existingIDs()
        var diff = ReconcileDiff()

        for (id, note) in onDisk {
            if let known = notes[id] {
                if known != note { diff.updated.append(id) }
            } else {
                diff.created.append(id)
            }
            notes[id] = note
        }
        // Deleted = the file is gone. A present-but-undecodable file keeps its
        // in-memory version untouched (it may be foreign, or mid-rewrite).
        let deletionCandidates = notes.keys.filter { !present.contains($0) }
        for id in deletionCandidates {
            do {
                try await tombstoneStore?.recordDeletion(id: id, at: clock())
                diff.deleted.append(id)
                notes[id] = nil
            } catch {
                // Retain the known note so the next reconcile retries the
                // journal write instead of silently losing delete evidence.
                diff.tombstoneFailures.append(id)
            }
        }

        // Retry stale tombstone cleanup for every present note, not only a
        // newly discovered one. Independent CLI/app writers can transiently
        // contend on the journal; reconciliation is the convergence loop.
        for id in onDisk.keys {
            do {
                try await tombstoneStore?.remove(id: id)
            } catch {
                if !diff.tombstoneFailures.contains(id) {
                    diff.tombstoneFailures.append(id)
                }
            }
        }

        diff.created.sort()
        diff.updated.sort()
        diff.deleted.sort()
        diff.tombstoneFailures.sort()
        let detected = clock()
        for id in diff.created {
            recordExternal(id: id, at: notes[id]?.updatedAt ?? detected, writer: notes[id]?.presentation.lastWriter, detected: detected)
            post(.blinkNoteCreated, id: id)
        }
        for id in diff.updated {
            recordExternal(id: id, at: notes[id]?.updatedAt ?? detected, writer: notes[id]?.presentation.lastWriter, detected: detected)
            post(.blinkNoteUpdated, id: id)
        }
        for id in diff.deleted {
            recordExternal(id: id, at: detected, writer: nil, detected: detected)
            post(.blinkNoteDeleted, id: id)
        }

        return diff
    }

    /// Look up a note by id.
    public func note(id: String) -> Note? {
        notes[id]
    }

    /// All notes, sorted by `updatedAt` descending (ties broken by id for stability).
    public func all() -> [Note] {
        notes.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    /// Round-trip a note through the codec so the in-memory version is always
    /// identical to what decoding its own file yields (ISO8601 truncates dates
    /// to milliseconds). Without this, `reconcile` would see every note the
    /// app itself created as "externally updated".
    private func normalized(_ note: Note) -> Note {
        (try? Frontmatter.decode(Frontmatter.encode(note))) ?? note
    }

    /// Reconcile only knows the file changed. Skip if the ledger already
    /// recorded this mutation (same note, same `at`) so CLI+watcher don't
    /// double-count. Stamp `detectedAt`; never invent a writer.
    private func recordExternal(id: String, at: Date, writer: String?, detected: Date) {
        if let last = fileStore.ledger?.last(noteID: id),
           last.kind != .externalDetected,
           abs(last.at.timeIntervalSince(at)) < 0.002 {
            return
        }
        _ = fileStore.ledger?.record(
            noteID: id,
            kind: .externalDetected,
            writer: writer,
            at: at,
            detectedAt: detected
        )
    }



    private func post(_ name: Notification.Name, id: String) {
        notificationCenter.post(name: name, object: nil, userInfo: ["id": id])
    }
}
