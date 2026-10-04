import AppKit
import XCTest
@testable import Lattices

final class OverviewPointerDropTests: XCTestCase {
    func testReleaseAndCancellationAreTerminal() {
        var release = OverviewPointerRelease()
        XCTAssertTrue(release.claim())
        XCTAssertTrue(release.finished)
        XCTAssertFalse(release.claim(), "A repeated mouse-up cannot move again")
        var cancelled = OverviewPointerRelease()
        XCTAssertTrue(cancelled.claim())
        XCTAssertFalse(cancelled.claim(), "Release after Escape must not commit")
    }

    func testSourceCannotArmOutsideItsBounds() {
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let source = OverviewImmediateDragSource.Source(frame: CGRect(x: 100, y: 100, width: 40, height: 40))
        root.addSubview(source)
        XCTAssertNil(OverviewImmediateDragSource.Source.frontmost(in: root, windowPoint: CGPoint(x: 20, y: 20)))
        XCTAssertTrue(OverviewImmediateDragSource.Source.frontmost(in: root, windowPoint: CGPoint(x: 120, y: 120)) === source)
        source.isHidden = true
        XCTAssertNil(OverviewImmediateDragSource.Source.frontmost(in: root, windowPoint: CGPoint(x: 120, y: 120)))
    }

    func testDestinationUsesBoundsNotUnclippedVisibleRect() {
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let first = OverviewPointerDrop.Target(frame: CGRect(x: 20, y: 20, width: 80, height: 60))
        let last = OverviewPointerDrop.Target(frame: CGRect(x: 200, y: 200, width: 80, height: 60))
        root.addSubview(first); root.addSubview(last)
        XCTAssertTrue(OverviewPointerDrag.hit(root, point: CGPoint(x: 40, y: 40)) === first)
        XCTAssertNil(OverviewPointerDrag.hit(root, point: CGPoint(x: 150, y: 150)))
        XCTAssertTrue(OverviewPointerDrag.hit(root, point: CGPoint(x: 220, y: 220)) === last)
        last.isHidden = true
        XCTAssertNil(OverviewPointerDrag.hit(root, point: CGPoint(x: 220, y: 220)))
    }
}
