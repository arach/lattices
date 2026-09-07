import XCTest
@testable import Lattices

final class TilePointerKeyboardTests: XCTestCase {
    func testNumpadMapsToMatrix() {
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 89), .topLeft)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 91), .top)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 92), .topRight)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 86), .left)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 87), .maximize)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 88), .right)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 83), .bottomLeft)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 84), .bottom)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 85), .bottomRight)
    }

    func testNumberRowMapsToMatrix() {
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 26), .topLeft)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 28), .top)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 25), .topRight)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 21), .left)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 23), .maximize)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 22), .right)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 18), .bottomLeft)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 19), .bottom)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forMatrixKeyCode: 20), .bottomRight)
    }

    func testArrowEdgesAndCorners() {
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forArrows: [.left]), .left)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forArrows: [.right]), .right)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forArrows: [.up]), .top)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forArrows: [.down]), .bottom)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forArrows: [.left, .down]), .bottomLeft)
        XCTAssertEqual(TilePointerKeyboard.tilePosition(forArrows: [.right, .up]), .topRight)
    }
}
