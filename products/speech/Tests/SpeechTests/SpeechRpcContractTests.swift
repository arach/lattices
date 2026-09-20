import XCTest
@testable import SpeechAppRuntime

final class SpeechRpcContractTests: XCTestCase {
    func testSpeechTextPreservesWhitespaceForSynthesisIdentity() throws {
        let text = "  Ready.\n"
        let request = try SpeechRpc.parseEnqueue(.object(["text": .string(text)]))
        XCTAssertEqual(request.text, text)
    }

    func testWrongTypedRateDoesNotSilentlyUseDefault() {
        XCTAssertThrowsError(try SpeechRpc.parseEnqueue(.object([
            "text": .string("Ready"), "rate": .string("fast"),
        ])))
    }

    func testWrongTypedSourceDoesNotSilentlyDisappear() {
        XCTAssertThrowsError(try SpeechRpc.parseEnqueue(.object([
            "text": .string("Ready"), "source": .string("task"),
        ])))
    }
}
