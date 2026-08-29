import Testing
import Foundation
@testable import BlinkCore

@Suite("NoteStore")
struct NoteStoreTests {
    private func tempStore() -> (NoteStore, URL) {
        let (store, dir, _) = tempStoreWithCenter()
        return (store, dir)
    }

    /// Each store gets a private NotificationCenter so parallel tests can't
    /// observe each other's notifications (the app injects `.default`).
    private func tempStoreWithCenter() -> (NoteStore, URL, NotificationCenter) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlinkCoreStoreTests-\(UUID().uuidString)", isDirectory: true)
        let center = NotificationCenter()
        let store = NoteStore(fileStore: NoteFileStore(directory: dir), notificationCenter: center)
        return (store, dir, center)
    }

    @Test("create assigns unique slugs for duplicate titles")
    func duplicateTitles() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = try await store.create(content: "# Meeting Notes\nfirst")
        let b = try await store.create(content: "# Meeting Notes\nsecond")
        let c = try await store.create(content: "# Meeting Notes\nthird")

        #expect(a.id == "meeting-notes")
        #expect(b.id == "meeting-notes-2")
        #expect(c.id == "meeting-notes-3")
    }

    @Test("create persists workspace membership atomically")
    func createWithWorkspace() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var presentation = NotePresentation()
        presentation.workspace = "demo"
        let created = try await store.create(
            content: "# Demo note\nblank slate",
            presentation: presentation
        )

        #expect(created.presentation.workspace == "demo")
        let onDisk = try NoteFileStore(directory: dir).load(id: created.id)
        #expect(onDisk.presentation.workspace == "demo")
    }

    @Test("update bumps updatedAt and persists")
    func updatePersists() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let created = try await store.create(content: "# Doc\noriginal")
        // Ensure a measurable time delta.
        try await Task.sleep(nanoseconds: 5_000_000)
        let updated = try await store.update(id: created.id, content: "# Doc\nchanged")

        #expect(updated.updatedAt > created.updatedAt)
        #expect(updated.content == "# Doc\nchanged")

        // Reload from disk in a fresh store to prove persistence.
        let fresh = NoteStore(fileStore: NoteFileStore(directory: dir))
        let all = try await fresh.load()
        #expect(all.first { $0.id == created.id }?.content == "# Doc\nchanged")
    }

    @Test("content save never clobbers metadata an agent wrote to disk")
    func externalFrontmatterSurvivesContentSave() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let created = try await store.create(content: "# Doc\noriginal")

        // An agent edits the file on disk while the note is "open": adds its
        // own key and sets Blink-owned metadata. The in-memory copy is stale.
        let fileStore = NoteFileStore(directory: dir)
        var external = try fileStore.load(id: created.id)
        external.extraFrontmatter = ["source: agent://claude"]
        external.tags = ["inbox"]
        external.pinned = true
        try fileStore.save(external)

        // The editor's next keystroke save must merge, not clobber.
        let saved = try await store.update(id: created.id, content: "# Doc\nchanged")
        #expect(saved.content == "# Doc\nchanged")
        #expect(saved.extraFrontmatter == ["source: agent://claude"])
        #expect(saved.tags == ["inbox"])
        #expect(saved.pinned == true)

        let onDisk = try fileStore.load(id: created.id)
        #expect(onDisk.extraFrontmatter == ["source: agent://claude"])
        #expect(onDisk.tags == ["inbox"])
        #expect(onDisk.pinned == true)
    }

    @Test("reconcile diffs external creates, edits, and deletes")
    func reconcileDiffsExternalChanges() async throws {
        let (store, dir, center) = tempStoreWithCenter()
        defer { try? FileManager.default.removeItem(at: dir) }

        let kept = try await store.create(content: "# Kept\nstays")
        let edited = try await store.create(content: "# Edited\nbefore")
        let removed = try await store.create(content: "# Removed\ngoes away")

        // External writer: one new file, one edit, one delete.
        let fileStore = NoteFileStore(directory: dir)
        let now = Date()
        try fileStore.save(
            Note(id: "cli-born", content: "# CLI born\n", createdAt: now, updatedAt: now)
        )
        var change = try fileStore.load(id: edited.id)
        change.content = "# Edited\nafter"
        try fileStore.save(change)
        try fileStore.delete(id: removed.id)

        // Collect notifications posted by reconcile.
        let events = NotificationLog()
        let names: [Notification.Name] = [.blinkNoteCreated, .blinkNoteUpdated, .blinkNoteDeleted]
        let observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { note in
                let id = note.userInfo?["id"] as? String ?? "?"
                let kind = name.rawValue.split(separator: ".").last.map(String.init) ?? "?"
                events.append("\(kind):\(id)")
            }
        }
        defer { observers.forEach(center.removeObserver) }

        let diff = await store.reconcile()
        #expect(diff.created == ["cli-born"])
        #expect(diff.updated == [edited.id])
        #expect(diff.deleted == [removed.id])

        #expect(await store.note(id: "cli-born") != nil)
        #expect(await store.note(id: edited.id)?.content == "# Edited\nafter")
        #expect(await store.note(id: removed.id) == nil)
        #expect(await store.note(id: kept.id)?.content == "# Kept\nstays")

        #expect(events.all.sorted() == [
            "created:cli-born", "deleted:\(removed.id)", "updated:\(edited.id)",
        ])

        // A second reconcile with nothing changed is silent.
        let second = await store.reconcile()
        #expect(second.isEmpty)
    }

    @Test("reconcile treats an unreadable file as untouched, not deleted")
    func reconcileSkipsMalformedFiles() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let note = try await store.create(content: "# Fragile\nbody")

        // An external writer mangles the file (no frontmatter at all).
        let fileURL = dir.appendingPathComponent("\(note.id).md")
        try "not frontmatter".write(to: fileURL, atomically: true, encoding: .utf8)

        let diff = await store.reconcile()
        #expect(diff.isEmpty)
        #expect(await store.note(id: note.id)?.content == "# Fragile\nbody")
    }

    @Test("update of unknown id throws")
    func updateUnknownThrows() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: NoteFileStoreError.self) {
            _ = try await store.update(id: "nonexistent", content: "x")
        }
    }

    @Test("delete removes the file and the in-memory entry")
    func deleteRemoves() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let note = try await store.create(content: "# Trash\nbye")
        let fileStore = NoteFileStore(directory: dir)
        #expect(FileManager.default.fileExists(atPath: fileStore.url(for: note.id).path))

        try await store.delete(id: note.id)
        #expect(await store.note(id: note.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: fileStore.url(for: note.id).path))
    }

    @Test("all() is sorted by updatedAt descending")
    func sortedDescending() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = try await store.create(content: "# Alpha")
        try await Task.sleep(nanoseconds: 2_000_000)
        let b = try await store.create(content: "# Beta")
        try await Task.sleep(nanoseconds: 2_000_000)
        _ = try await store.update(id: a.id, content: "# Alpha\nedited")

        let all = await store.all()
        // a was updated most recently, so it should sort first; b second.
        #expect(all.map(\.id) == [a.id, b.id])
    }

    @Test("load reads existing files from disk")
    func loadFromDisk() async throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await store.create(content: "# Persisted\nhi")

        let fresh = NoteStore(fileStore: NoteFileStore(directory: dir))
        let loaded = try await fresh.load()
        #expect(loaded.contains { $0.content == "# Persisted\nhi" })
    }

    @Test("create posts blinkNoteCreated with correct id")
    func createNotification() async throws {
        let (store, dir, center) = tempStoreWithCenter()
        defer { try? FileManager.default.removeItem(at: dir) }

        let received = NotificationBox()
        let token = center.addObserver(
            forName: .blinkNoteCreated, object: nil, queue: nil
        ) { note in
            received.set(note.userInfo?["id"] as? String)
        }
        defer { center.removeObserver(token) }

        let created = try await store.create(content: "# Notify\nx")
        #expect(received.value == created.id)
    }

    @Test("update and delete post notifications with correct id")
    func updateDeleteNotifications() async throws {
        let (store, dir, center) = tempStoreWithCenter()
        defer { try? FileManager.default.removeItem(at: dir) }
        let created = try await store.create(content: "# N\n1")

        let updatedBox = NotificationBox()
        let deletedBox = NotificationBox()
        let t1 = center.addObserver(forName: .blinkNoteUpdated, object: nil, queue: nil) {
            updatedBox.set($0.userInfo?["id"] as? String)
        }
        let t2 = center.addObserver(forName: .blinkNoteDeleted, object: nil, queue: nil) {
            deletedBox.set($0.userInfo?["id"] as? String)
        }
        defer {
            center.removeObserver(t1)
            center.removeObserver(t2)
        }

        _ = try await store.update(id: created.id, content: "# N\n2")
        #expect(updatedBox.value == created.id)

        try await store.delete(id: created.id)
        #expect(deletedBox.value == created.id)
    }
}

/// Thread-safe holder so notification observers can hand a value back to the test.
/// Thread-safe multi-event collector for reconcile's notification bursts.
final class NotificationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func append(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        items.append(s)
    }
    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return items
    }
}

final class NotificationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?
    func set(_ v: String?) {
        lock.lock(); defer { lock.unlock() }
        _value = v
    }
    var value: String? {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
}
