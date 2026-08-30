import Testing
import CoreGraphics
@testable import BlinkCore

@Suite("BlinkGrid placement")
struct BlinkGridTests {
    // A clean 1000×1000 area makes the arithmetic checkable by hand:
    // margin = 40, gap = 20, inner = (40,40,920,920), 3×3 cell = 880/3 ≈ 293.33.
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 1000)

    private func approxEqual(_ a: CGRect, _ b: CGRect, _ tol: CGFloat = 0.02) -> Bool {
        abs(a.minX - b.minX) <= tol && abs(a.minY - b.minY) <= tol
            && abs(a.width - b.width) <= tol && abs(a.height - b.height) <= tol
    }

    @Test("slot 1 is the top-left 3×3 cell")
    func slotOne() {
        let f = BlinkGrid.frame(forSlot: 1, in: area)!
        #expect(approxEqual(f, CGRect(x: 40, y: 666.6667, width: 293.3333, height: 293.3333)))
    }

    @Test("slot 9 is the bottom-right cell (lowest, rightmost)")
    func slotNine() {
        let f = BlinkGrid.frame(forSlot: 9, in: area)!
        #expect(approxEqual(f, CGRect(x: 666.6667, y: 40, width: 293.3333, height: 293.3333)))
    }

    @Test("row-major order: 1 top-left, 5 center, 9 bottom-right")
    func rowMajor() {
        let one = BlinkGrid.frame(forSlot: 1, in: area)!
        let five = BlinkGrid.frame(forSlot: 5, in: area)!
        let nine = BlinkGrid.frame(forSlot: 9, in: area)!
        #expect(one.minX < five.minX && five.minX < nine.minX)   // left → right
        #expect(one.minY > five.minY && five.minY > nine.minY)   // top → bottom (AppKit y-up)
    }

    @Test("slot count and out-of-range are nil")
    func slotBounds() {
        #expect(BlinkGrid.slotFrames(in: area).count == 9)
        #expect(BlinkGrid.frame(forSlot: 0, in: area) == nil)
        #expect(BlinkGrid.frame(forSlot: 10, in: area) == nil)
    }

    @Test("named zones alias the 3×3 slots")
    func namedZones() {
        #expect(BlinkGrid.placement(for: "top-left") == BlinkGrid.placement(forSlot: 1))
        #expect(BlinkGrid.placement(for: "center") == BlinkGrid.placement(forSlot: 5))
        #expect(BlinkGrid.placement(for: "bottom-right") == BlinkGrid.placement(forSlot: 9))
        #expect(BlinkGrid.placement(for: "6") == BlinkGrid.placement(forSlot: 6))
    }

    @Test("left-half fills the left column, full height")
    func leftHalf() {
        let f = BlinkGrid.frame(for: BlinkGrid.placement(for: "left-half")!, in: area)
        // cols=2 → cell width (900)/2 = 450; rows=1 → full inner height 920.
        #expect(approxEqual(f, CGRect(x: 40, y: 40, width: 450, height: 920)))
    }

    @Test("full covers the whole inner (inset) area")
    func full() {
        let f = BlinkGrid.frame(for: BlinkGrid.placement(for: "full")!, in: area)
        #expect(approxEqual(f, area.insetBy(dx: 40, dy: 40)))
    }

    @Test("a spanning block covers its cells plus the gaps between them")
    func spans() {
        // Top row, full width: 3 cells + 2 gaps = inner width.
        let top = GridPlacement(columns: 3, rows: 3, col: 0, row: 0, colSpan: 3, rowSpan: 1)
        let f = BlinkGrid.frame(for: top, in: area)
        #expect(approxEqual(f, CGRect(x: 40, y: 666.6667, width: 920, height: 293.3333)))
    }

    @Test("raw specs parse into placements")
    func rawSpecs() {
        #expect(BlinkGrid.placement(for: "3x3:2,1") == GridPlacement(columns: 3, rows: 3, col: 2, row: 1))
        #expect(
            BlinkGrid.placement(for: "2x2:1,0+1x2")
                == GridPlacement(columns: 2, rows: 2, col: 1, row: 0, colSpan: 1, rowSpan: 2)
        )
        #expect(BlinkGrid.placement(for: "garbage") == nil)
        #expect(BlinkGrid.placement(for: "3x3:9") == nil) // missing row component
    }

    @Test("out-of-range col/row clamp onto the grid")
    func clamping() {
        let wild = GridPlacement(columns: 3, rows: 3, col: 5, row: 5)
        #expect(approxEqual(BlinkGrid.frame(for: wild, in: area), BlinkGrid.frame(forSlot: 9, in: area)!))
    }

    @Test("placement is deterministic (same input, same frame)")
    func deterministic() {
        #expect(BlinkGrid.frame(forSlot: 6, in: area) == BlinkGrid.frame(forSlot: 6, in: area))
    }
}
