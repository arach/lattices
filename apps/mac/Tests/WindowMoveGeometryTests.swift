import CoreGraphics
import XCTest
@testable import Lattices

final class WindowMoveGeometryTests: XCTestCase {
    // MARK: - Display index → screen resolution (UUID matching)

    private let uuidA = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    private let uuidB = "A46D2F5E-11B8-4A1C-9F0D-63C1F1249B77"

    func testMatchIndexPrefersUUIDOverArrayOrder() {
        // SkyLight says display 0 is uuidB, but NSScreen.screens lists uuidB
        // second. UUID matching must win over the index.
        let index = DisplayGeometryMapper.matchIndex(
            displayId: uuidB,
            displayIndex: 0,
            identifiers: [uuidA, uuidB]
        )
        XCTAssertEqual(index, 1)
    }

    func testMatchIndexNormalizesBracesAndCase() {
        let index = DisplayGeometryMapper.matchIndex(
            displayId: "{\(uuidB.lowercased())}",
            displayIndex: 0,
            identifiers: [uuidA, uuidB]
        )
        XCTAssertEqual(index, 1)
    }

    func testMatchIndexFallsBackToArrayIndexWithoutIdentifier() {
        let index = DisplayGeometryMapper.matchIndex(
            displayId: "",
            displayIndex: 1,
            identifiers: [nil, nil]
        )
        XCTAssertEqual(index, 1)
    }

    func testMatchIndexFallsBackToArrayIndexWhenUUIDUnknown() {
        // The wanted UUID matches no screen; the historical index fallback
        // still resolves rather than dropping the request.
        let index = DisplayGeometryMapper.matchIndex(
            displayId: "0000AAAA-0000-0000-0000-000000000000",
            displayIndex: 0,
            identifiers: [uuidA, uuidB]
        )
        XCTAssertEqual(index, 0)
    }

    func testMatchIndexReturnsNilWhenNothingResolves() {
        let index = DisplayGeometryMapper.matchIndex(
            displayId: "0000AAAA-0000-0000-0000-000000000000",
            displayIndex: 5,
            identifiers: [uuidA, uuidB]
        )
        XCTAssertNil(index)
    }

    // MARK: - Normalized frame remap for display-only window.move

    func testNormalizedFractionsOfInteriorWindow() {
        let container = CGRect(x: 0, y: 30, width: 1_000, height: 970)
        let frame = CGRect(x: 250, y: 272.5, width: 500, height: 485)
        let fractions = DisplayGeometryMapper.normalizedFractions(of: frame, in: container)
        XCTAssertNotNil(fractions)
        XCTAssertEqual(fractions!.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(fractions!.y, 0.25, accuracy: 0.0001)
        XCTAssertEqual(fractions!.w, 0.5, accuracy: 0.0001)
        XCTAssertEqual(fractions!.h, 0.5, accuracy: 0.0001)
    }

    func testNormalizedFractionsClampsOversizedWindow() {
        // A window larger than the target's visible frame must shrink to fit
        // rather than overflow the display.
        let container = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frame = CGRect(x: -100, y: -50, width: 1_600, height: 1_200)
        let fractions = DisplayGeometryMapper.normalizedFractions(of: frame, in: container)
        XCTAssertNotNil(fractions)
        XCTAssertEqual(fractions!.x, 0, accuracy: 0.0001)
        XCTAssertEqual(fractions!.y, 0, accuracy: 0.0001)
        XCTAssertEqual(fractions!.w, 1, accuracy: 0.0001)
        XCTAssertEqual(fractions!.h, 1, accuracy: 0.0001)
    }

    func testNormalizedFractionsClampsWindowHangingOffTheEdge() {
        // Half off the right edge: size is preserved, origin clamps so the
        // remapped window still fits inside the unit square.
        let container = CGRect(x: 100, y: 0, width: 1_000, height: 1_000)
        let frame = CGRect(x: 900, y: 0, width: 400, height: 400)
        let fractions = DisplayGeometryMapper.normalizedFractions(of: frame, in: container)
        XCTAssertNotNil(fractions)
        XCTAssertEqual(fractions!.w, 0.4, accuracy: 0.0001)
        XCTAssertEqual(fractions!.x, 0.6, accuracy: 0.0001)
        XCTAssertEqual(fractions!.x + fractions!.w, 1, accuracy: 0.0001)
    }

    func testNormalizedFractionsPreservesGlobalOffsets() {
        // A secondary display to the right of the primary: fractions are
        // relative to that display's own visible frame, not global zero.
        let container = CGRect(x: 3_440, y: 265, width: 3_840, height: 2_130)
        let frame = CGRect(x: 5_360, y: 265, width: 1_920, height: 1_065)
        let fractions = DisplayGeometryMapper.normalizedFractions(of: frame, in: container)
        XCTAssertNotNil(fractions)
        XCTAssertEqual(fractions!.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(fractions!.y, 0, accuracy: 0.0001)
        XCTAssertEqual(fractions!.w, 0.5, accuracy: 0.0001)
        XCTAssertEqual(fractions!.h, 0.5, accuracy: 0.0001)
    }

    func testNormalizedFractionsRejectsDegenerateGeometry() {
        let container = CGRect(x: 0, y: 0, width: 0, height: 600)
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNil(DisplayGeometryMapper.normalizedFractions(of: frame, in: container))
        XCTAssertNil(DisplayGeometryMapper.normalizedFractions(
            of: CGRect(x: 0, y: 0, width: 0, height: 0),
            in: CGRect(x: 0, y: 0, width: 800, height: 600)
        ))
    }
}
