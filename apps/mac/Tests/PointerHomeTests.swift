import XCTest
@testable import Lattices

final class PointerHomeTests: XCTestCase {
    func testParsesClients() {
        let out = """
        id 0: archie:4242 (left) active: true, ips: {192.168.18.28}
        id 3: unknown:4242 (right) active: false, ips: {}
        """
        XCTAssertEqual(PointerHome.parseClients(out), [
            .init(id: 0, host: "archie", active: true),
            .init(id: 3, host: "unknown", active: false),
        ])
    }

    func testIgnoresNoise() {
        XCTAssertEqual(PointerHome.parseClients("could not connect\n\n"), [])
    }
}
