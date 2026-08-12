import CoreGraphics
import XCTest
@testable import Lattices

final class WorkspaceMapGeometryTests: XCTestCase {
    private let primaryHeight: CGFloat = 1_117

    func testPrimaryDisplayStartsAtTopLeftOrigin() {
        let converted = DisplayGeometryMapper.topLeftFrame(
            CGRect(x: 0, y: 0, width: 1_728, height: primaryHeight),
            primaryHeight: primaryHeight
        )
        XCTAssertEqual(converted, CGRect(x: 0, y: 0, width: 1_728, height: primaryHeight))
    }

    func testDisplaysAboveAndBelowPrimaryKeepSignedGlobalOffsets() {
        let above = DisplayGeometryMapper.topLeftFrame(
            CGRect(x: 200, y: primaryHeight, width: 1_200, height: 900),
            primaryHeight: primaryHeight
        )
        XCTAssertEqual(above, CGRect(x: 200, y: -900, width: 1_200, height: 900))

        let below = DisplayGeometryMapper.topLeftFrame(
            CGRect(x: 200, y: -700, width: 1_200, height: 700),
            primaryHeight: primaryHeight
        )
        XCTAssertEqual(below, CGRect(x: 200, y: primaryHeight, width: 1_200, height: 700))
    }

    func testDisplaysLeftAndRightPreserveHorizontalOffsets() {
        let left = DisplayGeometryMapper.topLeftFrame(
            CGRect(x: -1_920, y: 37, width: 1_920, height: 1_080),
            primaryHeight: primaryHeight
        )
        XCTAssertEqual(left, CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080))

        let right = DisplayGeometryMapper.topLeftFrame(
            CGRect(x: 1_728, y: 37, width: 2_560, height: 1_080),
            primaryHeight: primaryHeight
        )
        XCTAssertEqual(right, CGRect(x: 1_728, y: 0, width: 2_560, height: 1_080))
    }
}
