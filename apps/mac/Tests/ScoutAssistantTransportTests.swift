import XCTest
@testable import Lattices

final class ScoutAssistantTransportTests: XCTestCase {
    func testRecognizesExpiredScoutBindingRef() {
        let error = ScoutAssistantTransportError.commandFailed(
            "error: target ref:w-bon7zf is not currently routable; nothing was sent."
        )

        XCTAssertTrue(ScoutAssistantTransport.isUnroutableBindingError(error))
    }

    func testRecognizesNoAgentMatchForScoutBindingRef() {
        let error = ScoutAssistantTransportError.commandFailed(
            "No agent matches ref:w-retired"
        )

        XCTAssertTrue(ScoutAssistantTransport.isUnroutableBindingError(error))
    }

    func testDoesNotRetryUnrelatedScoutFailure() {
        let error = ScoutAssistantTransportError.commandFailed(
            "Scout broker is unavailable"
        )

        XCTAssertFalse(ScoutAssistantTransport.isUnroutableBindingError(error))
    }

    func testDoesNotRetryNonBindingNoAgentMatch() {
        let error = ScoutAssistantTransportError.commandFailed(
            "No agent matches project lattices"
        )

        XCTAssertFalse(ScoutAssistantTransport.isUnroutableBindingError(error))
    }
}
