@testable import ActionCore
import Foundation
import XCTest

final class ActionSessionArchiveTests: XCTestCase {
    func testEveryLeaseIsRecordedWithItsCallerAndActs() async throws {
        try await withArchive { archive, store in
            let begun = try await store.begin(
                ownerID: "client-a",
                agent: "Codex 1a2b",
                task: "Rename the layer",
                mode: "background",
                sessionID: nil,
                implicit: false,
                client: "Action MCP",
                clientProcess: "bun 41250 ← claude 41012"
            )
            _ = try await store.touch(ownerID: "client-a", leaseID: begun.lease.leaseId, axTier: "semantic", actionKind: "click")
            _ = try await store.release(ownerID: "client-a", leaseID: begun.lease.leaseId, outcome: "done", summary: "Renamed")

            let directory = archive.directoryURL(for: begun.lease.sessionId)
            let session = try json(directory.appendingPathComponent("session.json")) as? [String: Any]
            let drive = session?["drive"] as? [String: Any]
            XCTAssertEqual(session?["state"] as? String, "completed")
            XCTAssertEqual(session?["recordedBy"] as? String, "action-agent")
            XCTAssertEqual(drive?["agent"] as? String, "Codex 1a2b")
            XCTAssertEqual(drive?["client"] as? String, "Action MCP")
            XCTAssertEqual(drive?["clientProcess"] as? String, "bun 41250 ← claude 41012")
            XCTAssertEqual(drive?["actCount"] as? Int, 1)
            XCTAssertEqual(drive?["outcome"] as? String, "done")

            let trace = try json(directory.appendingPathComponent("drive-trace.json")) as? [[String: Any]]
            XCTAssertEqual(trace?.compactMap { $0["type"] as? String }, [
                "drive.lease_began", "drive.act_tier", "drive.lease_ended",
            ])
            XCTAssertEqual(trace?[1]["actionKind"] as? String, "click")
        }
    }

    func testClearSparesSessionsStillDriving() async throws {
        try await withArchive { archive, store in
            let done = try await store.begin(
                ownerID: "client-a", agent: "A", task: "Finished", mode: nil, sessionID: nil, implicit: false
            )
            _ = try await store.release(ownerID: "client-a", leaseID: done.lease.leaseId, outcome: "done", summary: nil)
            let live = try await store.begin(
                ownerID: "client-a", agent: "A", task: "Still going", mode: nil, sessionID: nil, implicit: false
            )

            let result = await store.clearSessions()
            XCTAssertEqual(result?.removed, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: archive.directoryURL(for: done.lease.sessionId).path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: archive.directoryURL(for: live.lease.sessionId).path))
        }
    }

    func testPruneAgesOutThenHoldsTheSizeCap() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("action-archive-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let archive = ActionSessionArchive(
            rootURL: root.appendingPathComponent("sessions"),
            scratchURLs: [],
            maximumAge: 24 * 60 * 60,
            maximumBytes: 300 * 1024
        )

        func seed(_ id: String, ageHours: Double, kilobytes: Int) throws {
            let directory = archive.directoryURL(for: id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("capture.mov")
            try Data(repeating: 1, count: kilobytes * 1024).write(to: file)
            let date = now.addingTimeInterval(-ageHours * 60 * 60)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: directory.path)
        }
        try seed("stale", ageHours: 48, kilobytes: 10)
        try seed("old", ageHours: 3, kilobytes: 200)
        try seed("recent", ageHours: 2, kilobytes: 200)
        try seed("live", ageHours: 5, kilobytes: 50)

        let result = archive.prune(keeping: ["live"], now: now)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: archive.rootURL.path).sorted()
        XCTAssertEqual(remaining, ["live", "recent"])
        XCTAssertEqual(result.removed, 2)
    }

    private func withArchive(
        _ body: (ActionSessionArchive, ActionDriveLeaseStore) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("action-archive-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = ActionSessionArchive(rootURL: root.appendingPathComponent("sessions"), scratchURLs: [])
        let store = ActionDriveLeaseStore(
            rootURL: root.appendingPathComponent("leases"),
            publishesPresence: false,
            sessionArchive: archive
        )
        try await body(archive, store)
    }

    private func json(_ url: URL) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }
}
