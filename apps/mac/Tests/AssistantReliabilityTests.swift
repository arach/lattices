import XCTest
@testable import Lattices

/// Pure unit tests for assistant / dictation helpers (no Bun, Scout, or mic).
final class AssistantReliabilityTests: XCTestCase {

    // MARK: - Dictation buffer

    func testDictationBufferEmptyDraftTakesPhrase() {
        XCTAssertEqual(WorkspaceDictationBuffer.appending("hello", to: ""), "hello")
        XCTAssertEqual(WorkspaceDictationBuffer.appending("  hi  ", to: "   "), "hi")
    }

    func testDictationBufferAppendsWithSingleSpace() {
        XCTAssertEqual(
            WorkspaceDictationBuffer.appending("world", to: "hello"),
            "hello world"
        )
        XCTAssertEqual(
            WorkspaceDictationBuffer.appending("world", to: "hello "),
            "hello world"
        )
    }

    func testDictationBufferIgnoresEmptyPhrase() {
        XCTAssertEqual(WorkspaceDictationBuffer.appending("   ", to: "keep"), "keep")
        XCTAssertEqual(WorkspaceDictationBuffer.appending("", to: "keep"), "keep")
    }

    // MARK: - Scout offline detection

    func testScoutOfflineQueueWhenParkedForOnline() {
        let flight: [String: Any] = [
            "state": "queued",
            "summary": "Will deliver when online",
            "targetAgentId": "session-abc",
        ]
        let error = ScoutAssistantTransport.offlineQueueError(
            fromFlight: flight,
            targetLabel: nil
        )
        guard case .targetOffline(let summary, let label)? = error else {
            return XCTFail("expected targetOffline, got \(String(describing: error))")
        }
        XCTAssertTrue(summary.localizedCaseInsensitiveContains("online"))
        XCTAssertEqual(label, "session-abc")
        XCTAssertTrue(error?.shouldClearBinding == true)
    }

    func testScoutOfflineNotRaisedForActiveFlight() {
        let flight: [String: Any] = [
            "state": "running",
            "summary": "Working…",
        ]
        XCTAssertNil(
            ScoutAssistantTransport.offlineQueueError(fromFlight: flight, targetLabel: "x")
        )
    }

    func testScoutOfflineRequiresOfflineWording() {
        let flight: [String: Any] = [
            "state": "queued",
            "summary": "Waiting in broker queue",
        ]
        XCTAssertNil(
            ScoutAssistantTransport.offlineQueueError(fromFlight: flight, targetLabel: nil)
        )
    }

    // MARK: - Agent-runtime error copy

    func testAgentRuntimeEmptyReplyMessage() {
        let error = AgentRuntimeTransportError.emptyReply
        XCTAssertEqual(error.errorDescription, "The agent finished without a text reply.")
    }

    func testAgentRuntimeTimeoutMessage() {
        let error = AgentRuntimeTransportError.timeout
        XCTAssertEqual(error.errorDescription, "The agent turn timed out.")
    }

    func testDefaultHarnessPreferencePutsPiFirst() {
        XCTAssertEqual(AgentRuntimeTransport.defaultHarnessPreference.first, "pi")
        XCTAssertTrue(AgentRuntimeTransport.defaultHarnessPreference.contains("claude-code"))
    }
}
