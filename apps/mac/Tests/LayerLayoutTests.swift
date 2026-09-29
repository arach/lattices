import CoreGraphics
import XCTest
@testable import Lattices

final class LayerLayoutTests: XCTestCase {
    private let ultrawide: CGFloat = 3440 / 1440
    private let standard: CGFloat = 1512 / 982

    func testParsesLayoutNames() {
        XCTAssertEqual(LayerLayout.Kind("auto"), .auto)
        XCTAssertEqual(LayerLayout.Kind("Smart"), .auto)
        XCTAssertEqual(LayerLayout.Kind("columns"), .columns)
        XCTAssertEqual(LayerLayout.Kind("master-stack"), .masterStack)
        XCTAssertNil(LayerLayout.Kind("spiral"))
    }

    func testAutoOnAnUltrawideGivesEachLaneAColumn() {
        // Entry order: terminal, browser, editor. Lanes put the editor in the middle.
        let frames = LayerLayout.frames(.auto, types: [.terminal, .browser, .editor], aspect: ultrawide)
        assertEqual(frames, [
            CGRect(x: 0, y: 0, width: 0.3, height: 1),
            CGRect(x: 0.7, y: 0, width: 0.3, height: 1),
            CGRect(x: 0.3, y: 0, width: 0.4, height: 1),
        ])
    }

    func testAutoOnAnUltrawideStacksALane() {
        let frames = LayerLayout.frames(.auto, types: [.editor, .editor, .browser], aspect: ultrawide)
        assertEqual(frames, [
            CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
        ])
    }

    func testAutoOnAStandardDisplayLeadsWithTheEditor() {
        let frames = LayerLayout.frames(.auto, types: [.terminal, .editor, .browser], aspect: standard)
        assertEqual(frames, [
            CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0, y: 0, width: 0.5, height: 1),
            CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ])
    }

    func testALoneWindowIsCentredOnAnUltrawide() {
        assertEqual(LayerLayout.frames(.auto, types: [.browser], aspect: ultrawide), [CGRect(x: 0.25, y: 0, width: 0.5, height: 1)])
        assertEqual(LayerLayout.frames(.columns, types: [.browser], aspect: standard), [CGRect(x: 0, y: 0, width: 1, height: 1)])
    }

    func testColumnsGiveExtrasToTheLeft() {
        let frames = LayerLayout.frames(.columns, types: Array(repeating: .other, count: 4), aspect: standard)
        assertEqual(frames, [
            CGRect(x: 0, y: 0, width: 1.0 / 3, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 1.0 / 3, height: 0.5),
            CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1),
            CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1),
        ])
    }

    func testMasterStack() {
        let frames = LayerLayout.frames(.masterStack, types: [.editor, .terminal, .browser], aspect: ultrawide)
        assertEqual(frames, [
            CGRect(x: 0, y: 0, width: 0.62, height: 1),
            CGRect(x: 0.62, y: 0, width: 0.38, height: 0.5),
            CGRect(x: 0.62, y: 0.5, width: 0.38, height: 0.5),
        ])
    }

    func testAStackOfFiveIsAGridTwoWide() {
        let frames = LayerLayout.frames(.masterStack, types: Array(repeating: .other, count: 6), aspect: standard)
        let right = 1 - LayerLayout.masterRatio
        assertEqual(Array(frames.dropFirst()), [
            CGRect(x: 0.62, y: 0, width: right / 2, height: 1.0 / 3),
            CGRect(x: 0.62 + right / 2, y: 0, width: right / 2, height: 1.0 / 3),
            CGRect(x: 0.62, y: 1.0 / 3, width: right / 2, height: 1.0 / 3),
            CGRect(x: 0.62 + right / 2, y: 1.0 / 3, width: right / 2, height: 1.0 / 3),
            CGRect(x: 0.62, y: 2.0 / 3, width: right, height: 1.0 / 3),
        ])
    }

    private func assertEqual(_ actual: [CGRect], _ expected: [CGRect], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (a, e) in zip(actual, expected) {
            for (x, y) in [(a.minX, e.minX), (a.minY, e.minY), (a.width, e.width), (a.height, e.height)] {
                XCTAssertEqual(x, y, accuracy: 1e-9, "\(a) ≠ \(e)", file: file, line: line)
            }
        }
    }
}
