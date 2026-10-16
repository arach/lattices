import CoreGraphics
import XCTest
@testable import Lattices

final class LayerPreviewPickTests: XCTestCase {
    /// Two rows as the preview lays them out, flipped (y grows down): A and
    /// B on top, C and D under them, shifted right.
    private let a = CGRect(x: 0, y: 0, width: 400, height: 300)
    private let b = CGRect(x: 430, y: 0, width: 400, height: 300)
    private let c = CGRect(x: 200, y: 360, width: 400, height: 300)
    private let d = CGRect(x: 630, y: 360, width: 400, height: 300)
    private var rows: [CGRect] { [a, b, c, d] }

    private func pick(_ from: Int, _ direction: LayerSlots.Direction, in rects: [CGRect]? = nil) -> Int? {
        LayerPreviewView.neighbour(of: from, in: rects ?? rows, toward: direction)
    }

    func testLeftAndRightMoveAlongARow() {
        XCTAssertEqual(pick(0, .right), 1)
        XCTAssertEqual(pick(1, .left), 0)
        XCTAssertEqual(pick(2, .right), 3)
        XCTAssertEqual(pick(3, .left), 2)
    }

    func testDownPicksTheTileBelowNearestAcross() {
        // Only C sits under A.
        XCTAssertEqual(pick(0, .down), 2)
        // C and D both sit under B; D's centre is nearer.
        XCTAssertEqual(pick(1, .down), 3)
        // A and B both sit over C; A's centre is nearer.
        XCTAssertEqual(pick(2, .up), 0)
        XCTAssertEqual(pick(3, .up), 1)
    }

    func testArrowsStopAtTheEdge() {
        XCTAssertNil(pick(0, .left))
        XCTAssertNil(pick(0, .up))
        XCTAssertNil(pick(1, .up))
        XCTAssertNil(pick(3, .right))
        XCTAssertNil(pick(2, .down))
        XCTAssertNil(pick(3, .down))
    }

    func testATileInTheSameRowWinsOverANearerOneOutOfIt() {
        let near = CGRect(x: 430, y: 360, width: 400, height: 300)
        let far = CGRect(x: 1500, y: 0, width: 400, height: 300)
        XCTAssertEqual(pick(0, .right, in: [a, near, far]), 2)
    }

    func testWithNothingInLineTheNearestThatWayWins() {
        // Nothing to the right of B shares its row: D, below and right, is next.
        XCTAssertEqual(pick(1, .right), 3)
    }

    func testNoOtherTileOrNoPickGoesNowhere() {
        XCTAssertNil(pick(0, .right, in: [a]))
        XCTAssertNil(pick(4, .right))
        XCTAssertNil(pick(0, .right, in: []))
    }
}
