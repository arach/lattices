import XCTest
@testable import Lattices

final class EventSubscriptionsTests: XCTestCase {
    func testClientsReceiveEverythingUntilTheySubscribe() {
        XCTAssertTrue(EventSubscriptions.wants(nil, event: "windows.changed"))
    }

    func testSubscribeNarrowsAndStarRestoresAll() {
        let only = EventSubscriptions.apply(
            method: "events.subscribe",
            params: .object(["events": .array([.string("windows.changed")])]),
            to: nil
        )
        XCTAssertEqual(only, ["windows.changed"])
        XCTAssertTrue(EventSubscriptions.wants(only, event: "windows.changed"))
        XCTAssertFalse(EventSubscriptions.wants(only, event: "tmux.changed"))
        XCTAssertNil(EventSubscriptions.apply(
            method: "events.subscribe",
            params: .object(["events": .array([.string("*")])]),
            to: only
        ))
    }

    func testUnsubscribeRemovesFromAllOrStopsEverything() {
        let filter = EventSubscriptions.apply(
            method: "events.unsubscribe",
            params: .object(["events": .array([.string("processes.changed")])]),
            to: nil
        )
        XCTAssertEqual(filter, EventSubscriptions.known.subtracting(["processes.changed"]))
        XCTAssertEqual(EventSubscriptions.apply(method: "events.unsubscribe", params: nil, to: nil), [])
    }

    func testResultListsTheFilter() {
        XCTAssertEqual(EventSubscriptions.result(nil)["events"], .array([.string("*")]))
        XCTAssertEqual(EventSubscriptions.result(["b", "a"])["events"], .array([.string("a"), .string("b")]))
    }
}
