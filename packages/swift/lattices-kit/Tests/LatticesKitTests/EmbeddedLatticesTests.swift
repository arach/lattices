import XCTest
@testable import LatticesKit

final class EmbeddedLatticesTests: XCTestCase {
    func testSessionNameMatchesCliContractForKnownPath() {
        let server = Lattices()

        XCTAssertEqual(server.sessionName(for: "/Users/art/dev/lattices"), "lattices-c36f74")
    }

    func testReadinessContainsHostPermissionState() {
        let lattices = Lattices()

        let readiness = lattices.readiness(for: [.windowManagement])

        XCTAssertEqual(readiness.features, [.windowManagement])
        XCTAssertEqual(readiness.permissions.map(\.permission), [.accessibility])
        XCTAssertFalse(readiness.hostDisplayName.isEmpty)
    }

    func testDispatchAcceptsOrcaPermissionAliases() throws {
        let lattices = Lattices()

        let result = try lattices.dispatch(method: "permissions.status", params: ["id": "screenshots"])
        let status = try result.decoded(as: LatticesPermissionStatus.self)

        XCTAssertEqual(status.permission, .screenRecording)
    }

    func testExtractsSessionTitleTag() {
        XCTAssertEqual(
            EmbeddedLatticesWindows.extractSessionName(from: "[lattices:lattices-c36f74] zsh"),
            "lattices-c36f74"
        )
    }
}
