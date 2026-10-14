import XCTest
@testable import Lattices

final class SpaceFilmstripTests: XCTestCase {
    func testEveryDesktopCentersIncludingBothEndsAndLongJumps() {
        for width: CGFloat in [272, 640, 968] {
            for selected in [0, 1, 8, 17, 63] {
                let center = CGFloat(selected) * SpaceFilmstripLayout.stride
                    + SpaceFilmstripLayout.cardWidth / 2
                    + SpaceFilmstripLayout.offset(selected: selected, viewportWidth: width)
                XCTAssertEqual(center, width / 2, accuracy: 0.001)
            }
        }
    }

    func testTrayFitsSmallAndLargeDisplaysAndCentersOnNegativeOrigin() {
        for width: CGFloat in [320, 1024, 3440] {
            for count in [1, 18, 64] {
                let trayWidth = SpaceFilmstripLayout.trayWidth(screenWidth: width, count: count)
                XCTAssertLessThanOrEqual(trayWidth, width - 48)
                XCTAssertLessThanOrEqual(trayWidth, 1000)
                let screen = CGRect(x: -3840, y: -396, width: width, height: 2160)
                let frame = SpaceSwitchBezel.frame(position: .center, direction: -1,
                    size: CGSize(width: trayWidth, height: SpaceFilmstripLayout.height), screen: screen)
                XCTAssertEqual(frame.midX, screen.midX)
                XCTAssertEqual(frame.midY, screen.midY)
            }
        }
    }

    func testProjectionClipsToRequestedDisplayAndPreservesEmptyDesktops() {
        let spaces = [SpaceInfo(id: 42, index: 1, display: 1, isCurrent: true),
                      SpaceInfo(id: 43, index: 2, display: 1, isCurrent: false)]
        let windows = [window(1, frame: WindowFrame(x: -1100, y: 0, w: 600, h: 500)),
                       window(2, frame: WindowFrame(x: 50, y: 0, w: 600, h: 500))]
        let cards = SpaceFilmstripLayout.cards(spaces: spaces, windows: windows,
            bounds: CGRect(x: -1000, y: 0, width: 1000, height: 1000))
        XCTAssertEqual(cards.map(\.id), [42, 43])
        XCTAssertEqual(cards[0].windows.count, 1)
        XCTAssertEqual(cards[0].windows[0].rect, CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        XCTAssertTrue(cards[1].windows.isEmpty)
    }

    func testPreviewsAreBoundedAndExcludeHiddenAndOwnWindows() {
        let spaces = [SpaceInfo(id: 42, index: 1, display: 0, isCurrent: true)]
        var windows = (1...100).map { window(UInt32($0), z: $0) }
        var hidden = window(101, z: 0)
        hidden.appHidden = true
        var collapsed = window(102, z: 0)
        collapsed.collapsed = true
        windows += [hidden, collapsed,
            WindowEntry(wid: 103, app: "Lattices", pid: getpid(), title: "Overlay",
                        frame: windows[0].frame, spaceIds: [42], isOnScreen: true, latticesSession: nil)]
        let cards = SpaceFilmstripLayout.cards(spaces: spaces, windows: windows,
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        XCTAssertEqual(cards[0].windows.count, 6)
        XCTAssertEqual(cards[0].windows.map(\.app), ["App 6", "App 5", "App 4", "App 3", "App 2", "App 1"])
    }

    func testInactiveUntitledWindowStillHasAPlanWithoutAXVerification() {
        let spaces = [SpaceInfo(id: 42, index: 1, display: 0, isCurrent: false)]
        let window = WindowEntry(wid: 1, app: "Editor", pid: -1, title: "",
            frame: WindowFrame(x: 0, y: 0, w: 500, h: 500), spaceIds: [42],
            isOnScreen: false, latticesSession: nil, axVerified: false)
        let cards = SpaceFilmstripLayout.cards(spaces: spaces, windows: [window],
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        XCTAssertEqual(cards[0].windows.count, 1)
        XCTAssertEqual(cards[0].windows[0].app, "Editor")
    }

    // MARK: Motion

    private func strip(count: Int = 18) -> SpaceFilmstripView {
        let view = SpaceFilmstripView()
        let cards = (0..<count).map { SpaceFilmstripCard(id: $0, number: $0 + 1, windows: []) }
        view.configure(cards: cards, size: CGSize(width: 1000, height: SpaceFilmstripLayout.height), scale: 2)
        return view
    }

    private func offset(_ index: Int) -> CGFloat {
        SpaceFilmstripLayout.offset(selected: index, viewportWidth: 1000 - 32)
    }

    func testReopenTravelsFromDepartureNotThePreviousGesture() {
        let view = strip()
        view.select(2, animated: false)
        view.select(9, animated: true)
        // Gesture ends; the next opens elsewhere in the same run-loop pass,
        // before Core Animation commits anything.
        view.configure(cards: (0..<18).map { SpaceFilmstripCard(id: $0, number: $0 + 1, windows: []) },
                       size: CGSize(width: 1000, height: SpaceFilmstripLayout.height), scale: 2)
        XCTAssertEqual(view.animationCount, 0)
        view.select(14, animated: false)
        view.select(15, animated: true)
        XCTAssertEqual(view.trackX, offset(15), accuracy: 0.001)
        XCTAssertEqual(view.trackDeltas.count, 1)
        XCTAssertEqual(view.trackDeltas[0], offset(14) - offset(15), accuracy: 0.001)
    }

    func testReversalAndMergedBurstStayContinuous() {
        let view = strip()
        view.select(5, animated: false)
        // Visible position = model + remaining deltas. With no time elapsed
        // every retarget must leave the strip exactly where it was.
        for target in [6, 7, 6, 5, 12, 4] {
            view.select(target, animated: true)
            XCTAssertEqual(view.trackX + view.trackDeltas.reduce(0, +), offset(5), accuracy: 0.001)
        }
        XCTAssertEqual(view.trackX, offset(4), accuracy: 0.001)
    }

    func testTravelLegsAreAdditiveSelfRemovingAndReleasedOnClear() {
        let view = strip()
        view.select(0, animated: false)
        view.select(1, animated: true)
        XCTAssertGreaterThan(view.animationCount, 0)
        var point: [Float] = [0, 0]
        SpaceFilmstripView.travelTiming.getControlPoint(at: 1, values: &point)
        XCTAssertEqual(point[1], 0, "zero initial slope keeps speed continuous")
        view.clear()
        XCTAssertEqual(view.animationCount, 0)
        XCTAssertNil(view.selected)
    }

    func testReduceMotionSelectsWithoutAnimation() {
        let view = strip()
        view.select(3, animated: false)
        view.select(8, animated: false)
        XCTAssertEqual(view.animationCount, 0)
        XCTAssertEqual(view.trackX, offset(8), accuracy: 0.001)
        XCTAssertEqual(view.cardOpacities[8], 1)
        XCTAssertEqual(view.cardOpacities[7], SpaceFilmstripView.emphasis(distance: 1))
    }

    func testPassingLightIsBoundedAndReleasedWithTheGesture() {
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        host.wantsLayer = true
        let wash = SpaceSwitchWash()
        XCTAssertEqual(wash.liveBandCount, 0)
        for _ in 0..<20 { wash.pass(direction: 1, in: host) }
        wash.pass(direction: -1, in: host)
        XCTAssertLessThanOrEqual(wash.liveBandCount, 3)
        XCTAssertLessThanOrEqual(host.layer?.sublayers?.count ?? 0, 3)
        wash.release()
        XCTAssertEqual(wash.liveBandCount, 0)
        XCTAssertEqual(host.layer?.sublayers?.count ?? 0, 0)
    }

    func testScrubbingKeepsTrackStillAndReleaseDoesNotTravelThroughCards() {
        let view = strip()
        view.select(1, animated: false)
        let departure = view.trackX
        for number in [3, 4, 9, 10, 18, 17, 6] {
            view.scrub(number: number, total: 18, animated: true)
            XCTAssertEqual(view.trackX, departure)
            XCTAssertEqual(view.selected, 1)
            XCTAssertTrue(view.isScrubbing)
        }
        view.endScrubbing(at: 5, animated: true)
        XCTAssertEqual(view.selected, 5)
        XCTAssertEqual(view.trackX, offset(5), accuracy: 0.001)
        XCTAssertTrue(view.trackDeltas.isEmpty, "Release reveals the destination without replaying intermediate cards")
        XCTAssertFalse(view.isScrubbing)
        view.clear()
        XCTAssertEqual(view.animationCount, 0)
    }

    func testCaptureExclusionsRejectSyntheticAppKitWindowNumbers() {
        XCTAssertEqual(SpaceSwitchBezel.captureWindowIDs([-1, 0, 42, Int(UInt32.max), Int(UInt32.max) + 1, Int.max]),
                       [42, UInt32.max])
    }

    private func window(_ id: UInt32, z: Int = 0,
                        frame: WindowFrame = WindowFrame(x: 0, y: 0, w: 500, h: 500)) -> WindowEntry {
        WindowEntry(wid: id, app: "App \(id)", pid: -1, title: "Window", frame: frame,
                    spaceIds: [42], isOnScreen: false, latticesSession: nil, zIndex: z)
    }
}
