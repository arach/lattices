import XCTest
@testable import Lattices

final class InputOwnershipTests: XCTestCase {
    func testSuccessfulFactoryRunsOnceAndStops() {
        var attempts: [String] = []
        let selected = EventTapInstallation.firstAvailable(["HID", "session"]) { candidate -> String? in
            attempts.append(candidate)
            return candidate
        }
        XCTAssertEqual(selected, "HID")
        XCTAssertEqual(attempts, ["HID"])
    }

    func testFallbackDoesNotRepeatSuccessfulFactory() {
        var attempts: [String] = []
        let selected = EventTapInstallation.firstAvailable(["HID", "session"]) { candidate -> String? in
            attempts.append(candidate)
            return candidate == "session" ? candidate : nil
        }
        XCTAssertEqual(selected, "session")
        XCTAssertEqual(attempts, ["HID", "session"])
    }

    func testUnavailableFactoriesAreEachTriedOnce() {
        var attempts: [String] = []
        let selected: String? = EventTapInstallation.firstAvailable(["HID", "session"]) { candidate in
            attempts.append(candidate)
            return nil
        }
        XCTAssertNil(selected)
        XCTAssertEqual(attempts, ["HID", "session"])
    }

    func testLeaseRejectsSecondOwnerAndReleasesOnClose() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("input.lock").path
        var first: AppInputLease? = try AppInputLease(path: path)
        try withExtendedLifetime(first) {
            XCTAssertThrowsError(try AppInputLease(path: path)) { error in
                guard case AppInputLease.Failure.occupied = error else {
                    return XCTFail("Expected occupied lease, got \(error)")
                }
            }
        }
        first = nil
        let replacement = try AppInputLease(path: path)
        try withExtendedLifetime(replacement) {
            XCTAssertThrowsError(try AppInputLease(path: path))
        }
    }

    func testLeaseFailsClosedWhenPathCannotBeOpened() {
        XCTAssertThrowsError(try AppInputLease(path: "/nonexistent-\(UUID().uuidString)/input.lock"))
    }

    func testPeerIdentityExcludesCompanionsAndSelf() {
        XCTAssertTrue(AppInputLease.isPeer(bundleIdentifier: "dev.lattices.app", pid: 2, ownPID: 1))
        XCTAssertTrue(AppInputLease.isPeer(bundleIdentifier: "dev.lattices.app.dev", pid: 2, ownPID: 1))
        XCTAssertFalse(AppInputLease.isPeer(bundleIdentifier: "dev.lattices.app.dev", pid: 1, ownPID: 1))
        for identifier in ["dev.lattices.Action", "dev.lattices.Blink", "dev.lattices.Speech", "other"] {
            XCTAssertFalse(AppInputLease.isPeer(bundleIdentifier: identifier, pid: 2, ownPID: 1))
        }
    }
}
