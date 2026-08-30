import Foundation
import Testing
@testable import BlinkCore

@Suite("Blink snapshots")
struct BlinkSnapshotTests {
    @Test("full snapshots preserve exact frontmattered markdown and stable ETags")
    func exactSnapshot() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteFileStore(directory: directory)
        var presentation = NotePresentation()
        presentation.workspace = "demo"
        let note = Note(
            id: "hello",
            content: "# Hello\nBody",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            tags: ["ios"],
            pinned: true,
            presentation: presentation,
            extraFrontmatter: ["source: agent://example"]
        )
        try store.save(note)
        let expectedMarkdown = try String(contentsOf: store.url(for: note.id), encoding: .utf8)
        let first = try BlinkSnapshotBuilder(notesDirectory: directory) {
            Date(timeIntervalSince1970: 1_000)
        }.build()
        let second = try BlinkSnapshotBuilder(notesDirectory: directory) {
            Date(timeIntervalSince1970: 2_000)
        }.build()

        #expect(first.notes.count == 1)
        #expect(first.notes[0].markdown == expectedMarkdown)
        #expect(first.notes[0].presentation.workspace == "demo")
        #expect(first.notes[0].tags == ["ios"])
        #expect(first.notes[0].pinned)
        #expect(first.etag == second.etag)
        #expect(first.generatedAt != second.generatedAt)
    }

    @Test("identity-divergent files are quarantined instead of becoming notes")
    func identityQuarantine() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoded = Frontmatter.encode(
            Note(
                id: "claimed-id",
                content: "# Divergent",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try Data(encoded.utf8).write(to: directory.appendingPathComponent("file-id.md"))

        let snapshot = try BlinkSnapshotBuilder(notesDirectory: directory).build()

        #expect(snapshot.notes.isEmpty)
        #expect(snapshot.issues == [
            BlinkSnapshotIssue(
                code: .identityMismatch,
                fileName: "file-id.md",
                expectedID: "file-id",
                claimedID: "claimed-id"
            )
        ])
    }

    @Test("an unreadable notes root never becomes an authoritative empty snapshot")
    func directoryFailure() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let notADirectory = root.appendingPathComponent("Notes")
        try Data("not a directory".utf8).write(to: notADirectory)

        #expect(throws: BlinkSnapshotBuilderError.self) {
            _ = try BlinkSnapshotBuilder(
                notesDirectory: notADirectory,
                maxStabilityAttempts: 2
            ).build()
        }
    }

    @Test("snapshot service returns not-modified for an exact corpus ETag")
    func conditionalFetch() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try NoteFileStore(directory: directory).save(
            Note(
                id: "one",
                content: "# One",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let service = BlinkSnapshotService(
            builder: BlinkSnapshotBuilder(notesDirectory: directory)
        )

        let first = try await service.fetchSnapshot(ifNoneMatch: nil)
        let snapshot: BlinkSnapshot
        switch first {
        case .snapshot(let value): snapshot = value
        case .notModified: Issue.record("First fetch unexpectedly returned not-modified")
            return
        }

        #expect(
            try await service.fetchSnapshot(ifNoneMatch: snapshot.etag)
                == .notModified(etag: snapshot.etag)
        )
    }

    @Test("tombstones persist atomically and appear only for absent notes")
    func tombstones() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        let storeURL = root.appendingPathComponent("sync/tombstones.json")
        let tombstoneStore = BlinkTombstoneStore(fileURL: storeURL)
        let deleted = try await tombstoneStore.recordDeletion(
            id: "gone",
            at: Date(timeIntervalSince1970: 300)
        )
        _ = try await tombstoneStore.recordDeletion(
            id: "back-again",
            at: Date(timeIntervalSince1970: 400)
        )
        try NoteFileStore(directory: notes).save(
            Note(
                id: "back-again",
                content: "# Restored",
                createdAt: Date(timeIntervalSince1970: 500),
                updatedAt: Date(timeIntervalSince1970: 500)
            )
        )
        let service = BlinkSnapshotService(
            builder: BlinkSnapshotBuilder(notesDirectory: notes),
            tombstoneStore: tombstoneStore
        )

        let result = try await service.fetchSnapshot(ifNoneMatch: nil)
        guard case .snapshot(let snapshot) = result else {
            Issue.record("Snapshot fetch unexpectedly returned not-modified")
            return
        }
        #expect(snapshot.tombstones == [deleted])

        let reloaded = BlinkTombstoneStore(fileURL: storeURL)
        #expect(try await reloaded.all().map(\.id) == ["gone", "back-again"])
    }

    @Test("independent tombstone stores serialize concurrent journal updates")
    func concurrentTombstoneWriters() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("sync/tombstones.json")
        let first = BlinkTombstoneStore(fileURL: fileURL)
        let second = BlinkTombstoneStore(fileURL: fileURL)
        let ids = (0..<40).map { "deleted-\($0)" }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    let store = index.isMultiple(of: 2) ? first : second
                    _ = try await store.recordDeletion(
                        id: id,
                        at: Date(timeIntervalSince1970: Double(index))
                    )
                }
            }
            try await group.waitForAll()
        }

        #expect(try await first.all().map(\.id).sorted() == ids.sorted())
    }

    @Test("a quarantined source file suppresses its stale tombstone")
    func quarantineSuppressesStaleTombstone() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not frontmatter".utf8).write(
            to: directory.appendingPathComponent("restored.md")
        )
        let stale = BlinkSnapshotTombstone(
            id: "restored",
            deletedAt: Date(timeIntervalSince1970: 10),
            revision: "stale"
        )

        let snapshot = try BlinkSnapshotBuilder(notesDirectory: directory)
            .build(tombstones: [stale])

        #expect(snapshot.notes.isEmpty)
        #expect(snapshot.issues.map(\.expectedID) == ["restored"])
        #expect(snapshot.tombstones.isEmpty)
    }

    @Test("NoteStore records direct and externally observed deletions")
    func noteStoreDeletionJournal() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        let fileStore = NoteFileStore(directory: notes)
        let tombstones = BlinkTombstoneStore(
            fileURL: root.appendingPathComponent("sync/tombstones.json")
        )
        let store = NoteStore(fileStore: fileStore, tombstoneStore: tombstones)
        _ = try await store.load()

        let direct = try await store.create(content: "# Direct")
        try await store.delete(id: direct.id)

        let external = try await store.create(content: "# External")
        try fileStore.delete(id: external.id)
        let diff = await store.reconcile()

        #expect(diff.deleted == [external.id])
        #expect(diff.tombstoneFailures.isEmpty)
        #expect(try await tombstones.all().map(\.id) == [direct.id, external.id].sorted())
    }

    @Test("mobile cache retains quarantined notes until an explicit tombstone")
    func mobileCacheQuarantine() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = BlinkSnapshotCache(fileURL: root.appendingPathComponent("snapshot.json"))
        let now = Date(timeIntervalSince1970: 12)
        let note = BlinkSnapshotNote(
            id: "keep-me",
            revision: "r1",
            markdown: "---\nid: keep-me\ncreated: 1970-01-01T00:00:12.000Z\nupdated: 1970-01-01T00:00:12.000Z\ntags: []\npinned: false\n---\nKeep me",
            title: "Keep me",
            updatedAt: now,
            tags: [],
            pinned: false,
            presentation: NotePresentation()
        )
        let first = BlinkSnapshot(
            generatedAt: now,
            etag: "\"one\"",
            notes: [note],
            tombstones: [],
            issues: []
        )
        _ = try await cache.apply(first)

        let quarantined = BlinkSnapshot(
            generatedAt: now.addingTimeInterval(1),
            etag: "\"two\"",
            notes: [],
            tombstones: [],
            issues: [
                BlinkSnapshotIssue(
                    code: .invalidFrontmatter,
                    fileName: "keep-me.md",
                    expectedID: "keep-me"
                )
            ]
        )
        let retained = try await cache.apply(quarantined)
        #expect(retained.notes.map(\.id) == ["keep-me"])
        #expect(retained.etag == "\"two\"")

        var deleted = quarantined
        deleted.etag = "\"three\""
        deleted.tombstones = [
            BlinkSnapshotTombstone(id: "keep-me", deletedAt: now, revision: "delete-r1")
        ]
        let removed = try await cache.apply(deleted)
        #expect(removed.notes.isEmpty)
    }

    @Test("mobile cache never retains quarantined notes across peer identities")
    func mobileCachePeerIsolation() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = BlinkSnapshotCache(fileURL: root.appendingPathComponent("snapshot.json"))
        let now = Date(timeIntervalSince1970: 20)
        let note = BlinkSnapshotNote(
            id: "private-a",
            revision: "r1",
            markdown: "---\nid: private-a\ncreated: 1970-01-01T00:00:20.000Z\nupdated: 1970-01-01T00:00:20.000Z\ntags: []\npinned: false\n---\nPrivate A",
            title: "Private A",
            updatedAt: now,
            tags: [],
            pinned: false,
            presentation: NotePresentation()
        )
        let first = BlinkSnapshot(
            generatedAt: now,
            etag: "\"peer-a\"",
            notes: [note],
            tombstones: [],
            issues: []
        )
        _ = try await cache.apply(
            first,
            sourceIdentity: "public-key-a",
            syncedAt: now
        )

        let peerB = BlinkSnapshot(
            generatedAt: now.addingTimeInterval(1),
            etag: "\"peer-b\"",
            notes: [],
            tombstones: [],
            issues: [
                BlinkSnapshotIssue(
                    code: .invalidFrontmatter,
                    fileName: "private-a.md",
                    expectedID: "private-a"
                )
            ]
        )
        let isolated = try await cache.apply(
            peerB,
            sourceIdentity: "public-key-b",
            syncedAt: now.addingTimeInterval(1)
        )

        #expect(isolated.notes.isEmpty)
        let record = try await cache.loadRecord()
        #expect(record?.sourceIdentity == "public-key-b")
        #expect(record?.snapshot.etag == "\"peer-b\"")
    }

    @Test("legacy mobile caches load unbound and cannot retain notes for a new peer")
    func legacyMobileCacheMigration() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("snapshot.json")
        let cache = BlinkSnapshotCache(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 25)
        let note = BlinkSnapshotNote(
            id: "legacy-note",
            revision: "r1",
            markdown: "---\nid: legacy-note\ncreated: 1970-01-01T00:00:25.000Z\nupdated: 1970-01-01T00:00:25.000Z\ntags: []\npinned: false\n---\nLegacy",
            title: "Legacy",
            updatedAt: now,
            tags: [],
            pinned: false,
            presentation: NotePresentation()
        )
        let legacy = BlinkSnapshot(
            generatedAt: now,
            etag: "\"legacy\"",
            notes: [note],
            tombstones: [],
            issues: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(legacy).write(to: fileURL)

        let loaded = try await cache.loadRecord()
        #expect(loaded?.sourceIdentity == nil)
        #expect(loaded?.lastSuccessfulSyncAt == nil)
        #expect(loaded?.snapshot == legacy)

        let incoming = BlinkSnapshot(
            generatedAt: now.addingTimeInterval(1),
            etag: "\"new-peer\"",
            notes: [],
            tombstones: [],
            issues: [
                BlinkSnapshotIssue(
                    code: .invalidFrontmatter,
                    fileName: "legacy-note.md",
                    expectedID: "legacy-note"
                )
            ]
        )
        let isolated = try await cache.apply(
            incoming,
            sourceIdentity: "new-peer-public-key",
            syncedAt: now.addingTimeInterval(1)
        )
        #expect(isolated.notes.isEmpty)
    }

    @Test("peer identity and successful sync time persist with the snapshot")
    func mobileCacheRecordMetadata() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = BlinkSnapshotCache(fileURL: root.appendingPathComponent("snapshot.json"))
        let generatedAt = Date(timeIntervalSince1970: 30)
        let firstSync = Date(timeIntervalSince1970: 40)
        let secondSync = Date(timeIntervalSince1970: 50)
        let snapshot = BlinkSnapshot(
            generatedAt: generatedAt,
            etag: "\"stable\"",
            notes: [],
            tombstones: [],
            issues: []
        )

        _ = try await cache.apply(
            snapshot,
            sourceIdentity: "public-key-a",
            syncedAt: firstSync
        )
        #expect(
            try await cache.recordSuccessfulSync(
                sourceIdentity: "public-key-a",
                at: secondSync
            )
        )
        #expect(
            try await cache.recordSuccessfulSync(
                sourceIdentity: "public-key-b",
                at: secondSync.addingTimeInterval(1)
            ) == false
        )

        let record = try await cache.loadRecord()
        #expect(record?.sourceIdentity == "public-key-a")
        #expect(record?.lastSuccessfulSyncAt == secondSync)
        #expect(record?.snapshot == snapshot)
    }

    @Test("replaceable mobile cache is excluded from device backups after every save")
    func mobileCacheBackupExclusion() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("snapshot.json")
        let cache = BlinkSnapshotCache(fileURL: fileURL, excludeFromBackup: true)
        let first = BlinkSnapshot(
            generatedAt: Date(timeIntervalSince1970: 60),
            etag: "\"first\"",
            notes: [],
            tombstones: [],
            issues: []
        )
        _ = try await cache.apply(first, sourceIdentity: "peer-a")
        #expect(
            try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true
        )

        var replacement = first
        replacement.etag = "\"replacement\""
        _ = try await cache.apply(replacement, sourceIdentity: "peer-a")
        #expect(
            try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
