import Foundation
import Testing
@testable import BlinkCore

@Suite("Desk layout store")
struct DeskLayoutStoreTests {
    @Test func roundTripListAndDelete() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DeskLayoutStore(directory: root)
        let layout = DeskLayout(name: "incident-response", updated: Date(timeIntervalSince1970: 10), panels: [
            DeskPanel(id: "lead", slot: 1, mode: "read", frame: DeskFrame(x: 1, y: 2, width: 300, height: 400), display: 1)
        ])
        try store.save(layout)
        #expect(try store.load(layout.name) == layout)
        #expect(try store.list().map(\.name) == [layout.name])
        try store.delete(layout.name)
        #expect(try store.list().isEmpty)
    }

    @Test func rejectsUnsafeNames() {
        #expect(throws: DeskLayoutStoreError.invalidName("../escape")) { try DeskLayoutStore.validate("../escape") }
    }
}
