import Testing
import Foundation
@testable import BlinkCore

@Suite("NoteFileStore")
struct NoteFileStoreTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BlinkCoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeNote(id: String, content: String) -> Note {
        let now = Date(timeIntervalSince1970: 1_700_000_000.5)
        return Note(id: id, content: content, createdAt: now, updatedAt: now)
    }

    @Test("Init creates the directory if missing")
    func initCreatesDirectory() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = NoteFileStore(directory: dir)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("Save then load round-trips")
    func saveLoadRoundTrip() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NoteFileStore(directory: dir)
        let note = makeNote(id: "hello-world", content: "# Hello World\n\nbody\n")
        try store.save(note)

        let loaded = try store.load(id: "hello-world")
        #expect(loaded.content == note.content)
        #expect(loaded.id == note.id)
    }

    @Test("url(for:) matches the layout")
    func urlLayout() {
        let dir = tempDir()
        let store = NoteFileStore(directory: dir)
        #expect(store.url(for: "abc").lastPathComponent == "abc.md")
    }

    @Test("Saved destination file is never empty")
    func destinationNotEmpty() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NoteFileStore(directory: dir)
        try store.save(makeNote(id: "n1", content: "content"))
        let data = try Data(contentsOf: store.url(for: "n1"))
        #expect(!data.isEmpty)
    }

    @Test("loadAll finds every .md file")
    func loadAllFindsFiles() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NoteFileStore(directory: dir)
        try store.save(makeNote(id: "a", content: "A"))
        try store.save(makeNote(id: "b", content: "B"))
        try store.save(makeNote(id: "c", content: "C"))
        let all = try store.loadAll()
        #expect(Set(all.map(\.id)) == ["a", "b", "c"])
    }

    @Test("loadAll ignores tmp and dotfiles")
    func loadAllIgnoresTmp() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NoteFileStore(directory: dir)
        try store.save(makeNote(id: "real", content: "real"))

        // Drop a stray tmp file and a dotfile the loader must skip.
        let stray = dir.appendingPathComponent(".real.md.tmp")
        try "garbage".data(using: .utf8)!.write(to: stray)
        let hidden = dir.appendingPathComponent(".hidden.md")
        try "garbage".data(using: .utf8)!.write(to: hidden)

        let all = try store.loadAll()
        #expect(all.map(\.id) == ["real"])
    }

    @Test("delete removes the file")
    func deleteRemovesFile() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NoteFileStore(directory: dir)
        try store.save(makeNote(id: "gone", content: "x"))
        #expect(FileManager.default.fileExists(atPath: store.url(for: "gone").path))
        try store.delete(id: "gone")
        #expect(!FileManager.default.fileExists(atPath: store.url(for: "gone").path))
    }

    @Test("load of a missing id throws")
    func loadMissingThrows() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NoteFileStore(directory: dir)
        #expect(throws: NoteFileStoreError.self) {
            _ = try store.load(id: "nope")
        }
    }

    @Test("Overwriting a note leaves no tmp files behind")
    func noTmpLeftover() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NoteFileStore(directory: dir)
        try store.save(makeNote(id: "n", content: "v1"))
        try store.save(makeNote(id: "n", content: "v2"))
        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(!entries.contains { $0.hasSuffix(".tmp") })
        #expect(try store.load(id: "n").content == "v2")
    }
}
