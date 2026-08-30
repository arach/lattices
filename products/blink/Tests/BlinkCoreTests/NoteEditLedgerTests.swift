import Foundation
import Testing
@testable import BlinkCore

@Suite("NoteEditLedger")
struct NoteEditLedgerTests {
    private func tempLedger() -> (NoteEditLedger, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlinkLedger-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("edits.sqlite")
        let ledger = NoteEditLedger(fileURL: url)!
        return (ledger, dir)
    }

    @Test("records after a successful file save")
    func recordsAfterSave() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlinkLedgerNotes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let home = dir.deletingLastPathComponent()
        let ledgerURL = dir.appendingPathComponent("edits.sqlite")
        let ledger = NoteEditLedger(fileURL: ledgerURL)
        let store = NoteFileStore(directory: dir, ledger: ledger)
        var note = Note(
            id: "standup",
            content: "# Standup\nhello",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        try store.save(note, writer: "grok")
        note.content = "# Standup\nhello\nmore"
        note.updatedAt = Date(timeIntervalSince1970: 2)
        try store.save(note, writer: "user")
        try store.delete(id: "standup", writer: "cli")

        let history = ledger?.history(noteID: "standup") ?? []
        #expect(history.map(\.kind) == [.delete, .update, .create])
        #expect(history.map(\.writer) == ["cli", "user", "grok"])
        _ = home
    }

    @Test("save still succeeds when ledger is nil")
    func saveWithoutLedger() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlinkLedgerNone-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NoteFileStore(directory: dir, ledger: nil)
        let note = Note(
            id: "ok",
            content: "# Ok",
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.save(note, writer: "grok")
        #expect(try store.load(id: "ok").content == "# Ok")
    }

    @Test("lastWriter round-trips in frontmatter")
    func lastWriterRoundTrip() throws {
        var presentation = NotePresentation()
        presentation.lastWriter = "grok"
        let note = Note(
            id: "agent-grok",
            content: "# Grok",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10),
            presentation: presentation
        )
        let decoded = try Frontmatter.decode(Frontmatter.encode(note))
        #expect(decoded.presentation.lastWriter == "grok")
    }
}

@Suite("NoteStore ledger")
struct NoteStoreLedgerTests {
    @Test("store create and update stamp lastWriter")
    func storeStampsWriter() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlinkStoreLedger-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ledger = NoteEditLedger(fileURL: dir.appendingPathComponent("edits.sqlite"))
        let store = NoteStore(fileStore: NoteFileStore(directory: dir, ledger: ledger))
        let created = try await store.create(content: "# Hello\nfirst", writer: "user")
        #expect(created.presentation.lastWriter == "user")
        let updated = try await store.update(id: created.id, content: "# Hello\nsecond", writer: "grok")
        #expect(updated.presentation.lastWriter == "grok")
        let history = ledger?.history(noteID: created.id) ?? []
        #expect(history.map(\.kind) == [.update, .create])
        #expect(history.map(\.writer) == ["grok", "user"])
    }

    @Test("reconcile does not double-log a ledger-backed save")
    func reconcileSkipsKnownWrite() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlinkReconcileLedger-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ledger = NoteEditLedger(fileURL: dir.appendingPathComponent("edits.sqlite"))
        let files = NoteFileStore(directory: dir, ledger: ledger)
        let watcher = NoteStore(fileStore: files)
        _ = try await watcher.load()
        let writer = NoteStore(fileStore: files)
        let created = try await writer.create(content: "# Hello\nfirst", writer: "cli")
        let diff = await watcher.reconcile()
        #expect(diff.created == [created.id])
        #expect(diff.updated.isEmpty)
        let history = ledger?.history(noteID: created.id) ?? []
        #expect(history.map(\.kind) == [.create])
        #expect(history.first?.writer == "cli")
    }
}

