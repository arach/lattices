import XCTest
@testable import Lattices

final class LayerSlotsTests: XCTestCase {
    func testLayersFillTheSlotsRoundTheMiddle() {
        XCTAssertEqual((0..<9).map(LayerSlots.slot(forIndex:)), [1, 2, 3, 4, 6, 7, 8, 9, nil])
        XCTAssertNil(LayerSlots.index(forSlot: LayerSlots.centre))
        XCTAssertEqual(LayerSlots.index(forSlot: 6), 4)
    }

    func testArrowsMoveAcrossThePadAndHopTheMiddle() {
        // Layer 3 sits in slot 4, layer 4 in slot 6.
        XCTAssertEqual(LayerSlots.neighbour(of: 3, .right, count: 8), 4)
        XCTAssertEqual(LayerSlots.neighbour(of: 4, .left, count: 8), 3)
        // Slot 2 down hops the middle to slot 8.
        XCTAssertEqual(LayerSlots.neighbour(of: 1, .down, count: 8), 6)
        XCTAssertEqual(LayerSlots.neighbour(of: 0, .down, count: 8), 3)
    }

    func testArrowsStopAtTheEdge() {
        XCTAssertNil(LayerSlots.neighbour(of: 0, .left, count: 8))
        XCTAssertNil(LayerSlots.neighbour(of: 0, .up, count: 8))
        XCTAssertNil(LayerSlots.neighbour(of: 7, .right, count: 8))
        XCTAssertNil(LayerSlots.neighbour(of: 7, .down, count: 8))
    }

    func testArrowsSkipEmptySlots() {
        // Three layers fill the top row only.
        XCTAssertEqual(LayerSlots.neighbour(of: 0, .right, count: 3), 1)
        XCTAssertNil(LayerSlots.neighbour(of: 0, .down, count: 3))
        XCTAssertNil(LayerSlots.neighbour(of: 2, .right, count: 3))
        // Five layers: slot 3 down lands on slot 6.
        XCTAssertEqual(LayerSlots.neighbour(of: 2, .down, count: 5), 4)
        // Slot 4 down: slot 7 is empty, so it runs off the pad.
        XCTAssertNil(LayerSlots.neighbour(of: 3, .down, count: 5))
    }
}
