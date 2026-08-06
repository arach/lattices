import XCTest
@testable import Lattices

/// Pure unit tests for Scout binding recovery (no Scout process / broker).
/// Ported from the useful core of draft PR #80 (codex/fix-assistant-voice-runtime).
final class ScoutAssistantTransportTests: XCTestCase {
    func testRecognizesExpiredScoutBindingRef() {
        let error = ScoutAssistantTransportError.commandFailed(
            "error: target ref:w-bon7zf is not currently routable; nothing was sent."
        )
        XCTAssertTrue(ScoutAssistantTransport.isUnroutableBindingError(error))
        XCTAssertTrue(error.shouldClearBinding)
    }

    func testRecognizesNoAgentMatchForScoutBindingRef() {
        let error = ScoutAssistantTransportError.commandFailed(
            "No agent matches ref:w-retired"
        )
        XCTAssertTrue(ScoutAssistantTransport.isUnroutableBindingError(error))
        XCTAssertTrue(error.shouldClearBinding)
    }

    func testDoesNotTreatUnrelatedScoutFailureAsUnroutableRef() {
        let error = ScoutAssistantTransportError.commandFailed(
            "Scout broker is unavailable"
        )
        XCTAssertFalse(ScoutAssistantTransport.isUnroutableBindingError(error))
        XCTAssertFalse(error.shouldClearBinding)
    }

    func testDoesNotTreatProjectNoMatchAsUnroutableRef() {
        let error = ScoutAssistantTransportError.commandFailed(
            "No agent matches project lattices"
        )
        XCTAssertFalse(ScoutAssistantTransport.isUnroutableBindingError(error))
        XCTAssertFalse(error.shouldClearBinding)
    }

    func testOfflineQueuedTargetClearsBinding() {
        let error = ScoutAssistantTransportError.targetOffline(
            summary: "Will deliver when online",
            targetLabel: "session-x"
        )
        XCTAssertTrue(error.shouldClearBinding)
        XCTAssertTrue(ScoutAssistantTransport.isUnroutableBindingError(error))
    }
}
