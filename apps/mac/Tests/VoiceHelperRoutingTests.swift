import XCTest
@testable import Lattices

final class VoiceHelperRoutingTests: XCTestCase {
    func testVoiceVerbsMapToHelperMethods() {
        let expected: [String: String] = [
            "voice.say": "speech.enqueue",
            "voice.stop": "speech.stop",
            "voice.pause": "speech.pause",
            "voice.resume": "speech.resume",
            "voice.seek": "speech.seek",
            "voice.skip": "speech.next",
            "voice.list": "speech.voices",
            "voice.select": "speech.preferredVoice.set",
            "voice.lease": "speech.playback.reserve",
        ]
        for (verb, helper) in expected {
            XCTAssertEqual(VoiceHelperRouting.helperMethod(for: verb), helper, verb)
        }
        XCTAssertEqual(VoiceHelperRouting.helperMethod(for: "speech.enqueue"), "speech.enqueue")
        XCTAssertTrue(VoiceHelperRouting.isHelperVerb("voice.release"))
        for daemonVerb in ["voice.status", "voice.listen", "voice.stopListening", "voice.simulate", "voice.reconnect"] {
            XCTAssertFalse(VoiceHelperRouting.isHelperVerb(daemonVerb), daemonVerb)
        }
    }

    func testSpeechEventsAreAlsoSentAsVoiceEvents() {
        let events = VoiceHelperRouting.clientEvents(for: DaemonEvent(event: "speech.changed", data: .null))
        XCTAssertEqual(events.map(\.event), ["speech.changed", "voice.changed"])
        XCTAssertEqual(VoiceHelperRouting.clientEvents(for: DaemonEvent(event: "windows.changed", data: .null)).count, 1)
    }

    func testSpeakingDetection() {
        XCTAssertFalse(VoiceHelperRouting.isSpeaking(nil))
        XCTAssertFalse(VoiceHelperRouting.isSpeaking(.object(["current": .null, "queued": .array([])])))
        XCTAssertTrue(VoiceHelperRouting.isSpeaking(.object(["current": .object(["state": .string("playing")]), "queued": .array([])])))
        XCTAssertTrue(VoiceHelperRouting.isSpeaking(.object(["current": .null, "queued": .array([.object([:])])])))
    }

    func testSchemaAdvertisesVoiceNotSpeech() {
        let api = LatticesApi()
        VoiceHelperRouting.registerSchema(on: api)
        let methods = api.endpoints.keys
        for verb in ["voice.say", "voice.stop", "voice.pause", "voice.resume", "voice.skip", "voice.seek", "voice.list", "voice.select", "voice.lease", "voice.release"] {
            XCTAssertTrue(methods.contains(verb), verb)
        }
        XCTAssertFalse(methods.contains { $0.hasPrefix("speech.") })
        XCTAssertEqual(VoiceHelperRouting.errorCode(VoiceHelperRouting.notInstalledError), "helper_not_installed")
        XCTAssertTrue(VoiceHelperRouting.notInstalledError.contains("Lattices › Apps › Install Voice"))
    }

    func testClientWithoutCapabilityIsToldWhyVoiceIsUnavailable() {
        // Voice removes its capability file on quit, so no file means not running.
        XCTAssertEqual(VoiceHelperRouting.unauthorizedReason(capabilityPresent: false, installed: false), VoiceHelperRouting.notInstalledError)
        XCTAssertEqual(VoiceHelperRouting.unauthorizedReason(capabilityPresent: false, installed: true), VoiceHelperRouting.unreachableError)
        XCTAssertEqual(VoiceHelperRouting.unauthorizedReason(capabilityPresent: true, installed: true), VoiceHelperRouting.unauthorizedError)
        XCTAssertEqual(VoiceHelperRouting.errorCode(VoiceHelperRouting.unreachableError), "helper_unreachable")
        XCTAssertEqual(VoiceHelperRouting.errorCode(VoiceHelperRouting.unauthorizedError), "helper_unauthorized")
    }
}
