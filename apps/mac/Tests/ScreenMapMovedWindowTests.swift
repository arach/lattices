import CoreGraphics
import XCTest
@testable import Lattices

/// Regression coverage for the Studio immediate-movement reconcile path:
/// `ScreenMapEditorState.updatingMovedWindows` must refresh moved entries
/// from live geometry while leaving every unrelated staged frame/layer/canvas
/// edit untouched — no editor rebuild, deterministic without GUI automation.
final class ScreenMapMovedWindowTests: XCTestCase {
    private func entry(
        id: UInt32,
        frame: CGRect,
        edited: CGRect? = nil,
        virtualFrame: CGRect? = nil,
        layer: Int = 0,
        displayIndex: Int = 0
    ) -> ScreenMapWindowEntry {
        ScreenMapWindowEntry(
            id: id, pid: Int32(id) + 100, app: "App\(id)", title: "Title \(id)",
            originalFrame: frame,
            editedFrame: edited ?? frame,
            virtualFrame: virtualFrame ?? frame,
            zIndex: Int(id), layer: layer, displayIndex: displayIndex,
            isOnScreen: true,
            latticesSession: "sess-\(id)",
            tmuxCommand: "vim",
            tmuxPaneTitle: "pane-\(id)"
        )
    }

    func testMovedWindowAdoptsLiveFrameAndDisplay() {
        let old = CGRect(x: 100, y: 100, width: 800, height: 600)
        let live = CGRect(x: 3600, y: 400, width: 900, height: 700)
        let updated = ScreenMapEditorState.updatingMovedWindows(
            [entry(id: 1, frame: old, displayIndex: 0)],
            movedFrames: [1: live],
            displayIndexForFrame: { _ in 1 }
        )
        XCTAssertEqual(updated[0].originalFrame, live)
        XCTAssertEqual(updated[0].editedFrame, live)
        XCTAssertEqual(updated[0].virtualFrame, live)
        XCTAssertEqual(updated[0].displayIndex, 1)
        XCTAssertFalse(updated[0].hasEdits)
    }

    func testUnrelatedStagedEditsSurviveUntouched() {
        let base = CGRect(x: 0, y: 0, width: 500, height: 400)
        let staged = CGRect(x: 40, y: 40, width: 640, height: 480)
        let canvasSpot = CGRect(x: 9000, y: 9000, width: 500, height: 400)
        let untouched = entry(
            id: 2, frame: base, edited: staged, virtualFrame: canvasSpot,
            layer: 3, displayIndex: 0
        )
        let updated = ScreenMapEditorState.updatingMovedWindows(
            [entry(id: 1, frame: base), untouched],
            movedFrames: [1: CGRect(x: 3600, y: 300, width: 500, height: 400)],
            displayIndexForFrame: { _ in 1 }
        )
        XCTAssertEqual(updated[1].editedFrame, staged)
        XCTAssertEqual(updated[1].virtualFrame, canvasSpot)
        XCTAssertEqual(updated[1].layer, 3)
        XCTAssertEqual(updated[1].originalFrame, base)
        XCTAssertTrue(updated[1].hasEdits)
    }

    func testMovedWindowStagedEditIsReplacedByLiveTruth() {
        let base = CGRect(x: 0, y: 0, width: 500, height: 400)
        let staged = CGRect(x: 10, y: 10, width: 300, height: 200)
        let live = CGRect(x: 3500, y: 300, width: 500, height: 400)
        let updated = ScreenMapEditorState.updatingMovedWindows(
            [entry(id: 1, frame: base, edited: staged)],
            movedFrames: [1: live],
            displayIndexForFrame: { _ in 1 }
        )
        XCTAssertEqual(updated[0].editedFrame, live)
        XCTAssertFalse(updated[0].hasEdits)
    }

    func testMissingLiveFrameLeavesEntryUntouched() {
        let base = CGRect(x: 0, y: 0, width: 500, height: 400)
        let original = entry(id: 1, frame: base, layer: 2)
        let updated = ScreenMapEditorState.updatingMovedWindows(
            [original],
            movedFrames: [99: CGRect(x: 1, y: 1, width: 2, height: 2)],
            displayIndexForFrame: { _ in 1 }
        )
        XCTAssertEqual(updated[0].originalFrame, base)
        XCTAssertEqual(updated[0].layer, 2)
        XCTAssertEqual(updated[0].displayIndex, 0)
    }

    func testUnresolvableDisplayKeepsOldIndex() {
        let live = CGRect(x: 3600, y: 300, width: 500, height: 400)
        let updated = ScreenMapEditorState.updatingMovedWindows(
            [entry(id: 1, frame: .init(x: 0, y: 0, width: 500, height: 400), displayIndex: 0)],
            movedFrames: [1: live],
            displayIndexForFrame: { _ in nil }
        )
        XCTAssertEqual(updated[0].displayIndex, 0)
    }

    func testMovedEntryKeepsIdentityMetadata() {
        let live = CGRect(x: 3600, y: 300, width: 500, height: 400)
        let updated = ScreenMapEditorState.updatingMovedWindows(
            [entry(id: 7, frame: .init(x: 0, y: 0, width: 500, height: 400))],
            movedFrames: [7: live],
            displayIndexForFrame: { _ in 1 }
        )
        XCTAssertEqual(updated[0].id, 7)
        XCTAssertEqual(updated[0].latticesSession, "sess-7")
        XCTAssertEqual(updated[0].tmuxCommand, "vim")
        XCTAssertEqual(updated[0].zIndex, 7)
    }

    func testFailedMoveReconcilesNothingAndKeepsAllStagedEdits() {
        // A failed/blocked move produces an empty movedWids set — the
        // reconcile pass must be an identity, even for the requested target.
        let base = CGRect(x: 0, y: 0, width: 500, height: 400)
        let staged = CGRect(x: 25, y: 25, width: 700, height: 500)
        let requested = entry(id: 1, frame: base, edited: staged, layer: 4)
        let bystander = entry(id: 2, frame: base, edited: staged)
        let updated = ScreenMapEditorState.updatingMovedWindows(
            [requested, bystander],
            movedFrames: [:],
            displayIndexForFrame: { _ in 1 }
        )
        XCTAssertEqual(updated[0].editedFrame, staged)
        XCTAssertEqual(updated[0].layer, 4)
        XCTAssertTrue(updated[0].hasEdits)
        XCTAssertEqual(updated[1].editedFrame, staged)
    }

    func testPartialMoveRefreshesOnlySuccessfulTarget() {
        // Batch of two where only wid 1 verifiably moved: wid 1 adopts live
        // state, wid 2 (failed) keeps its staged edit untouched.
        let base = CGRect(x: 0, y: 0, width: 500, height: 400)
        let staged = CGRect(x: 25, y: 25, width: 700, height: 500)
        let live = CGRect(x: 3600, y: 300, width: 500, height: 400)
        let updated = ScreenMapEditorState.updatingMovedWindows(
            [entry(id: 1, frame: base, edited: staged), entry(id: 2, frame: base, edited: staged)],
            movedFrames: [1: live],
            displayIndexForFrame: { _ in 1 }
        )
        XCTAssertEqual(updated[0].editedFrame, live)
        XCTAssertFalse(updated[0].hasEdits)
        XCTAssertEqual(updated[0].displayIndex, 1)
        XCTAssertEqual(updated[1].editedFrame, staged)
        XCTAssertTrue(updated[1].hasEdits)
        XCTAssertEqual(updated[1].displayIndex, 0)
    }

    // MARK: - Edits staged while the async move was pending

    func testUnchangedFingerprintResetsEntryToLiveTruth() {
        let base = CGRect(x: 0, y: 0, width: 500, height: 400)
        let live = CGRect(x: 3600, y: 300, width: 500, height: 400)
        let target = entry(id: 1, frame: base)
        let updated = ScreenMapEditorState.updatingMovedWindows(
            [target],
            movedFrames: [1: live],
            expectedFingerprints: [1: target.stagingFingerprint],
            displayIndexForFrame: { _ in 1 }
        )
        XCTAssertEqual(updated[0].originalFrame, live)
        XCTAssertEqual(updated[0].editedFrame, live)
        XCTAssertEqual(updated[0].virtualFrame, live)
        XCTAssertEqual(updated[0].displayIndex, 1)
        XCTAssertFalse(updated[0].hasEdits)
    }

    func testEditDuringPendingMoveKeepsNewerStagedStateOnLiveBaseline() {
        // Fingerprint was captured before the user dragged the entry again:
        // the verified live frame must still become the new originalFrame
        // (the real move happened), while the newer staged fields survive.
        let base = CGRect(x: 0, y: 0, width: 500, height: 400)
        let live = CGRect(x: 3600, y: 300, width: 500, height: 400)
        let newerEdit = CGRect(x: 50, y: 60, width: 640, height: 480)
        let canvasSpot = CGRect(x: 9000, y: 9000, width: 500, height: 400)
        let preMove = entry(id: 1, frame: base)
        let reEdited = entry(
            id: 1, frame: base, edited: newerEdit, virtualFrame: canvasSpot,
            layer: 5, displayIndex: 1
        )
        let updated = ScreenMapEditorState.updatingMovedWindows(
            [reEdited],
            movedFrames: [1: live],
            expectedFingerprints: [1: preMove.stagingFingerprint],
            displayIndexForFrame: { _ in 0 }
        )
        XCTAssertEqual(updated[0].originalFrame, live)
        XCTAssertEqual(updated[0].editedFrame, newerEdit)
        XCTAssertEqual(updated[0].virtualFrame, canvasSpot)
        XCTAssertEqual(updated[0].layer, 5)
        XCTAssertEqual(updated[0].displayIndex, 1)
        XCTAssertTrue(updated[0].hasEdits)
    }

    func testLayerChangeDuringPendingMoveIsPreserved() {
        // A layer-only re-stage (frames untouched) must also defeat the full
        // reset — the fingerprint covers every stageable field.
        let base = CGRect(x: 0, y: 0, width: 500, height: 400)
        let live = CGRect(x: 3600, y: 300, width: 500, height: 400)
        let preMove = entry(id: 1, frame: base, layer: 0)
        let reLayered = entry(id: 1, frame: base, layer: 3)
        let updated = ScreenMapEditorState.updatingMovedWindows(
            [reLayered],
            movedFrames: [1: live],
            expectedFingerprints: [1: preMove.stagingFingerprint],
            displayIndexForFrame: { _ in 1 }
        )
        XCTAssertEqual(updated[0].originalFrame, live)
        XCTAssertEqual(updated[0].layer, 3)
        XCTAssertEqual(updated[0].editedFrame, base)
    }

    func testPartialSuccessWithMidFlightEditOnlyTouchesVerifiedTargets() {
        // wid 1 verified and untouched → full reset; wid 2 verified but
        // re-edited mid-flight → live baseline + newer edit; wid 3 failed →
        // completely untouched.
        let base = CGRect(x: 0, y: 0, width: 500, height: 400)
        let live1 = CGRect(x: 3600, y: 300, width: 500, height: 400)
        let live2 = CGRect(x: 4200, y: 300, width: 500, height: 400)
        let newerEdit = CGRect(x: 5, y: 5, width: 300, height: 200)
        let staged = CGRect(x: 25, y: 25, width: 700, height: 500)
        let pristine = entry(id: 1, frame: base)
        let reEdited = entry(id: 2, frame: base, edited: newerEdit)
        let preMove2 = entry(id: 2, frame: base)
        let failed = entry(id: 3, frame: base, edited: staged)
        let updated = ScreenMapEditorState.updatingMovedWindows(
            [pristine, reEdited, failed],
            movedFrames: [1: live1, 2: live2],
            expectedFingerprints: [
                1: pristine.stagingFingerprint,
                2: preMove2.stagingFingerprint,
            ],
            displayIndexForFrame: { _ in 1 }
        )
        XCTAssertEqual(updated[0].editedFrame, live1)
        XCTAssertFalse(updated[0].hasEdits)
        XCTAssertEqual(updated[1].originalFrame, live2)
        XCTAssertEqual(updated[1].editedFrame, newerEdit)
        XCTAssertTrue(updated[1].hasEdits)
        XCTAssertEqual(updated[2].originalFrame, base)
        XCTAssertEqual(updated[2].editedFrame, staged)
    }

    // MARK: - Display index resolution (hoisted from the snapshot path)

    // Two displays in CG top-left space: primary 3440×1440 at origin,
    // secondary 3840×2160 to its right, vertically offset (the layout the
    // live smoke ran against).
    private let displayRects = [
        CGRect(x: 0, y: 0, width: 3440, height: 1440),
        CGRect(x: 3440, y: 235, width: 3840, height: 2160),
    ]

    func testDisplayIndexByMidpointContainment() {
        let onSecond = CGRect(x: 3600, y: 400, width: 800, height: 600)
        XCTAssertEqual(
            ScreenMapController.displayIndex(forCGFrame: onSecond, displayCGRects: displayRects),
            1
        )
        let onFirst = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertEqual(
            ScreenMapController.displayIndex(forCGFrame: onFirst, displayCGRects: displayRects),
            0
        )
    }

    func testDisplayIndexFallsBackToNearestCenter() {
        // Straddling far off the top of the second display: contained by
        // neither rect, but the second display's center is nearer.
        let offscreen = CGRect(x: 5000, y: -400, width: 400, height: 300)
        XCTAssertEqual(
            ScreenMapController.displayIndex(forCGFrame: offscreen, displayCGRects: displayRects),
            1
        )
    }
}
