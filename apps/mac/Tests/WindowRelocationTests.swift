import CoreGraphics
import XCTest
@testable import Lattices

final class WindowRelocationTests: XCTestCase {
    private final class Desktop {
        let physicalFrame = CGRect(x: 0, y: 0, width: 1720, height: 1440)
        let virtualFrame = CGRect(x: 3440, y: 0, width: 720, height: 900)
        var displays = [
            WindowRelocation.Display(id: "physical", index: 0, currentSpaceId: 3, spaceIds: [1, 3, 4]),
            WindowRelocation.Display(id: "virtual", index: 2, currentSpaceId: 2377, spaceIds: [1956, 2377]),
        ]
        var state: WindowRelocation.Snapshot
        var operations: [String] = []
        var refusedSpaces: Set<Int> = []
        var ignoreSpace = false
        var ignoreFrame = false
        var preserveWrongMembership = false
        var transientStagingFrame = false
        var stagingSettled = false
        var disconnectDestinationAfterStaging = false

        init(sourceSpace: Int = 1956) {
            state = .init(frame: CGRect(x: 3440, y: 0, width: 720, height: 900), displayId: "virtual", spaceIds: [sourceSpace])
        }

        var destination: WindowRelocation.Destination {
            .init(displayId: "physical", spaceId: 3, frame: physicalFrame)
        }

        var environment: WindowRelocation.Environment {
            .init(
                displays: { self.displays },
                snapshot: { self.state },
                moveSpace: { space in
                    self.operations.append("space:\(space)")
                    if self.refusedSpaces.contains(space) { return "simulated refusal" }
                    if self.ignoreSpace { return nil }
                    guard let display = self.displays.first(where: { $0.spaceIds.contains(space) }),
                          display.id == self.state.displayId else { return "cross-display carry refused" }
                    self.state = .init(frame: self.state.frame, displayId: display.id, spaceIds: [space])
                    if self.disconnectDestinationAfterStaging && space == 2377 {
                        self.displays.removeAll { $0.id == "physical" }
                    }
                    if self.transientStagingFrame && space == 2377 {
                        self.state = .init(frame: CGRect(x: 3501, y: 66, width: 659, height: 824), displayId: display.id, spaceIds: [space])
                    }
                    return nil
                },
                moveFrame: { frame in
                    self.operations.append("frame:\(Int(frame.minX))")
                    guard !self.ignoreFrame,
                          let source = self.displays.first(where: { $0.id == self.state.displayId }),
                          self.state.spaceIds == [source.currentSpaceId] else { return }
                    let target = self.displays.first(where: { $0.id == (frame.minX >= 3440 ? "virtual" : "physical") })!
                    self.state = .init(frame: frame, displayId: target.id,
                                       spaceIds: self.preserveWrongMembership ? self.state.spaceIds : [target.currentSpaceId])
                },
                wait: { predicate in
                    // Model Mission Control having committed membership while
                    // the CG window still has thumbnail geometry.
                    if self.transientStagingFrame && self.state.spaceIds == [2377] && !predicate(self.state) {
                        self.state = .init(frame: self.virtualFrame, displayId: "virtual", spaceIds: [2377])
                        self.stagingSettled = true
                    }
                    return self.state
                }
            )
        }

        func move(to destination: WindowRelocation.Destination? = nil) -> WindowRelocation.Result {
            WindowRelocation.execute(from: state, to: destination ?? self.destination, tolerance: 6, environment: environment)
        }
    }

    func testInactiveVirtualDesktopStagesBeforeMovingToPhysicalDesktopTwo() {
        let desktop = Desktop()
        let result = desktop.move()
        XCTAssertTrue(result.verified)
        XCTAssertEqual(desktop.operations, ["space:2377", "frame:0"])
        XCTAssertEqual(result.after.displayId, "physical")
        XCTAssertEqual(result.after.spaceIds, [3], "Physical Desktop 2 must not be confused with virtual Desktop 2 (1956)")
        XCTAssertEqual(result.after.frame, desktop.physicalFrame)
    }

    func testInactiveDestinationMovesAfterDisplayTransfer() {
        let desktop = Desktop()
        let destination = WindowRelocation.Destination(displayId: "physical", spaceId: 4, frame: desktop.physicalFrame)
        let result = desktop.move(to: destination)
        XCTAssertTrue(result.verified)
        XCTAssertEqual(desktop.operations, ["space:2377", "frame:0", "space:4"])
    }

    func testSourceStagingWaitsForWindowGeometryAfterMissionControl() {
        let desktop = Desktop()
        desktop.transientStagingFrame = true
        let result = desktop.move()
        XCTAssertTrue(result.verified)
        XCTAssertTrue(desktop.stagingSettled)
        XCTAssertEqual(result.after.frame, desktop.physicalFrame)
    }

    func testActiveSourceNeedsNoStaging() {
        let desktop = Desktop(sourceSpace: 2377)
        XCTAssertTrue(desktop.move().verified)
        XCTAssertEqual(desktop.operations, ["frame:0"])
    }

    func testSameDisplayDesktopMoveDoesNotTouchGeometry() {
        let desktop = Desktop()
        let result = desktop.move(to: .init(displayId: "virtual", spaceId: 2377, frame: desktop.virtualFrame))
        XCTAssertTrue(result.verified)
        XCTAssertEqual(desktop.operations, ["space:2377"])
    }

    func testStagingRefusalStopsBeforeFrameMutation() {
        let desktop = Desktop()
        desktop.refusedSpaces = [2377]
        let result = desktop.move()
        XCTAssertFalse(result.verified)
        XCTAssertFalse(result.rollbackAttempted)
        XCTAssertTrue(result.rollbackVerified, "The original state is confirmed unchanged")
        XCTAssertEqual(desktop.operations, ["space:2377"])
        XCTAssertEqual(result.after.spaceIds, [1956])
    }

    func testUnverifiedCarryDoesNotBecomeSuccess() {
        let desktop = Desktop()
        desktop.ignoreSpace = true
        let result = desktop.move()
        XCTAssertFalse(result.verified)
        XCTAssertEqual(desktop.operations, ["space:2377"])
        XCTAssertEqual(result.after.spaceIds, [1956])
    }

    func testRefusedGeometryRollsBackStagingToOriginalDesktop() {
        let desktop = Desktop()
        desktop.ignoreFrame = true
        let result = desktop.move()
        XCTAssertFalse(result.verified)
        XCTAssertTrue(result.rollbackAttempted)
        XCTAssertTrue(result.rollbackVerified)
        XCTAssertEqual(desktop.operations, ["space:2377", "frame:0", "space:1956"])
        XCTAssertEqual(result.after.spaceIds, [1956])
        XCTAssertEqual(result.after.frame, desktop.virtualFrame)
    }

    func testRefusedDestinationDesktopRestoresOriginalDisplayAndDesktop() {
        let desktop = Desktop()
        desktop.refusedSpaces = [4]
        let result = desktop.move(to: .init(displayId: "physical", spaceId: 4, frame: desktop.physicalFrame))
        XCTAssertFalse(result.verified)
        XCTAssertTrue(result.rollbackAttempted)
        XCTAssertTrue(result.rollbackVerified)
        XCTAssertEqual(desktop.operations, ["space:2377", "frame:0", "space:4", "frame:3440", "space:1956"])
        XCTAssertEqual(result.after.spaceIds, [1956])
        XCTAssertEqual(result.after.displayId, "virtual")
    }

    func testFrameOnPhysicalDisplayWithVirtualMembershipIsNeverSuccess() {
        let desktop = Desktop(sourceSpace: 2377)
        desktop.preserveWrongMembership = true
        let result = desktop.move()
        XCTAssertFalse(result.verified)
        XCTAssertFalse(result.rollbackVerified, "An inconsistent partial transfer must remain visible in the receipt")
        XCTAssertEqual(result.after.frame, desktop.physicalFrame)
        XCTAssertEqual(result.after.spaceIds, [2377])
        XCTAssertNotNil(result.failure)
    }

    func testMismatchedDestinationDisplayAndDesktopIsRejectedBeforeMutation() {
        let desktop = Desktop()
        let result = desktop.move(to: .init(displayId: "physical", spaceId: 1956, frame: desktop.physicalFrame))
        XCTAssertFalse(result.verified)
        XCTAssertEqual(desktop.operations, [])
    }

    func testFullScreenActiveDesktopIsRejectedBeforeMutation() {
        let desktop = Desktop()
        desktop.displays[0] = .init(id: "physical", index: 0, currentSpaceId: 9999, spaceIds: [1, 3, 4])
        let result = desktop.move()
        XCTAssertFalse(result.verified)
        XCTAssertEqual(desktop.operations, [])
    }

    func testDestinationDisconnectDuringStagingRestoresOriginalSpaceWithoutFrameWrite() {
        let desktop = Desktop()
        desktop.disconnectDestinationAfterStaging = true
        let result = desktop.move()
        XCTAssertFalse(result.verified)
        XCTAssertTrue(result.rollbackVerified)
        XCTAssertEqual(desktop.operations, ["space:2377", "space:1956"])
    }

    func testRollbackRefusalReportsPartialFailureAndRecovery() {
        let desktop = Desktop()
        desktop.ignoreFrame = true
        desktop.refusedSpaces = [1956]
        let result = desktop.move()
        XCTAssertFalse(result.verified)
        XCTAssertTrue(result.rollbackAttempted)
        XCTAssertFalse(result.rollbackVerified)
        XCTAssertEqual(result.after.spaceIds, [2377])
        XCTAssertTrue(result.recoveryMessage?.contains("Locate the window in Overview") == true)
    }

    func testAlreadyAtDestinationDoesNotMutate() {
        let desktop = Desktop()
        desktop.state = .init(frame: desktop.physicalFrame, displayId: "physical", spaceIds: [3])
        let result = desktop.move()
        XCTAssertTrue(result.verified)
        XCTAssertNil(result.recoveryMessage)
        XCTAssertEqual(desktop.operations, [])
    }

    func testMultiSpaceWindowIsRejectedWithoutMutation() {
        let desktop = Desktop()
        desktop.state = .init(frame: desktop.virtualFrame, displayId: "virtual", spaceIds: [1956, 2377])
        XCTAssertFalse(desktop.move().verified)
        XCTAssertEqual(desktop.operations, [])
    }

    func testInvalidDestinationFrameIsRejectedWithoutMutation() {
        let desktop = Desktop()
        let destination = WindowRelocation.Destination(
            displayId: "physical", spaceId: 3,
            frame: CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100))
        XCTAssertFalse(desktop.move(to: destination).verified)
        XCTAssertEqual(desktop.operations, [])
    }

    func testStaleSourceDoesNotRestoreOverNewerWindowState() {
        let desktop = Desktop()
        let old = desktop.state
        desktop.state = .init(frame: desktop.virtualFrame, displayId: "virtual", spaceIds: [2377])
        let result = WindowRelocation.execute(from: old, to: desktop.destination,
                                              tolerance: 6, environment: desktop.environment)
        XCTAssertFalse(result.verified)
        XCTAssertFalse(result.rollbackAttempted)
        XCTAssertEqual(result.after, desktop.state)
        XCTAssertEqual(desktop.operations, [])
    }
    func testUndoRestoresOriginalDisplayFrameAndInactiveSpace() {
        let desktop = Desktop()
        let original = desktop.state
        XCTAssertTrue(desktop.move().verified)
        let undo = desktop.move(to: .init(displayId: original.displayId!,
            spaceId: original.spaceIds[0], frame: original.frame!))
        XCTAssertTrue(undo.verified)
        XCTAssertEqual(undo.after, original)
    }

    func testUndoGuardRejectsChangedSpaceFrameOrMissingWindow() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(WindowRelocation.undoConflict(frame: frame, expectedFrame: frame,
            spaceIds: [4], expectedSpaceIds: [3], tolerance: 6), "current-space-mismatch")
        XCTAssertEqual(WindowRelocation.undoConflict(frame: frame.offsetBy(dx: 30, dy: 0), expectedFrame: frame,
            spaceIds: [3], expectedSpaceIds: [3], tolerance: 6), "current-frame-mismatch")
        XCTAssertEqual(WindowRelocation.undoConflict(frame: nil, expectedFrame: frame,
            spaceIds: [3], expectedSpaceIds: [3], tolerance: 6), "window-frame-unavailable")
        XCTAssertNil(WindowRelocation.undoConflict(frame: frame, expectedFrame: frame,
            spaceIds: [3], expectedSpaceIds: [3], tolerance: 6))
        XCTAssertNil(WindowRelocation.undoConflict(frame: frame, expectedFrame: frame,
            spaceIds: [4], expectedSpaceIds: nil, tolerance: 6), "legacy frame-only receipts remain supported")
    }

    func testRuntimeAndDirectCarryFailPromptlyWhenAnotherTransactionOwnsGate() {
        WindowRelocationGate.lock.lock()
        defer { WindowRelocationGate.lock.unlock() }
        let done = expectation(description: "both paths refuse without AX access")
        DispatchQueue.global().async {
            do {
                _ = try ActionRuntime().executeWindowMove(params: .object(["wid": .int(1), "display": .int(0)]))
                XCTFail("must not run while gate is held")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("in progress"))
            }
            if case .failed(let reason) = WindowSpaceCarry.carry(wid: 1, pid: 1, to: 1) {
                XCTAssertTrue(reason.contains("in progress"))
            } else { XCTFail("direct carry must share the relocation gate") }
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
    }

}
