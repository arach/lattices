import XCTest
@testable import Lattices

final class MachinesTests: XCTestCase {
    private func host(_ name: String, _ side: VisitTrust.Side) -> VisitTrust.Host {
        .init(name: name, address: "\(name):5287", side: side, bridgePublicKey: "key-\(name)",
              bridgeFingerprint: "fp-\(name)", capabilities: ["input.trackpad"], pairedAt: Date(timeIntervalSince1970: 1))
    }
    func testMergesNamesAddressesAndTransitiveAliases() {
        let paired = host("ARCHIE", .left)
        let sources: [MachineInventory.Source] = [
            .init(name: paired.name, address: "100.64.0.1:5287", visit: paired),
            .init(name: "box", address: "100.64.0.1", remote: "box"),
            .init(name: "archie", address: "archie", client: .init(id: 1, host: "archie", active: true)),
            .init(name: "other", address: "100.64.0.2", remote: "other"),
        ]
        for input in [sources, Array(sources.reversed())] {
            let machines = MachineInventory.merge(input)
            XCTAssertEqual(machines.count, 2)
            let machine = machines.first { $0.visit != nil }!
            XCTAssertEqual(machine.remote, "box")
            XCTAssertEqual(machine.clients.count, 1)
            XCTAssertTrue(machine.sharing)
            XCTAssertEqual(machine.visit, paired)
        }
    }
    func testDistinctMachinesAndEmptySources() {
        XCTAssertTrue(MachineInventory.merge([]).isEmpty)
        XCTAssertEqual(MachineInventory.merge([
            .init(name: "a", address: "10.0.0.1"), .init(name: "b", address: "10.0.0.2")
        ]).count, 2)
        XCTAssertEqual(MachineInventory.addressKey("[::1]:5287"), "::1")
        XCTAssertEqual(MachineInventory.addressKey("ARCHIE.local.:9399"), "archie.local")
    }
    func testSideSwapPreservesAllTrust() throws {
        let a = host("a", .left), b = host("b", .right)
        let moved = try VisitTrust.assigningSide(.right, to: "A", in: [a, b])
        var expectedA = a, expectedB = b
        expectedA.side = .right; expectedB.side = .left
        XCTAssertEqual(moved, [expectedA, expectedB])
        XCTAssertEqual(Set(moved.map(\.side)).count, 2)
        XCTAssertEqual(try VisitTrust.assigningSide(.right, to: "a", in: moved), moved)
    }
    func testVacantSideAndMissingHost() throws {
        let a = host("a", .left)
        let moved = try VisitTrust.assigningSide(.top, to: "a", in: [a])
        XCTAssertEqual(moved.first?.side, .top)
        XCTAssertEqual(moved.first?.bridgePublicKey, a.bridgePublicKey)
        XCTAssertThrowsError(try VisitTrust.assigningSide(.bottom, to: "missing", in: [a]))
    }
    func testBridgeAddressValidation() {
        XCTAssertEqual(VisitTrust.bridgeURL("box:5287")?.host, "box")
        XCTAssertNotNil(VisitTrust.bridgeURL("[::1]:5287"))
        XCTAssertNil(VisitTrust.bridgeURL("user:password@box:5287"))
        XCTAssertNil(VisitTrust.bridgeURL("box:5287/path"))
        XCTAssertNil(VisitTrust.bridgeURL("box:5287?token=secret"))
    }
    func testLegacyPageName() {
        XCTAssertEqual(AppPage.named("hosts"), .machines)
        XCTAssertEqual(AppPage.named("machines"), .machines)
        XCTAssertTrue(AppPage.navigationGroups[0].pages.contains(.machines))
    }
}
