import XCTest
@testable import SpeechAppRuntime

@MainActor
final class SpeechMigrationTests: XCTestCase {
    func testMigrationPreservesSpeechChoicesAndDoesNotImportOtherSettings() {
        let name = "SpeechMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("speech-choice", forKey: "speech.preferredVoice.system")
        SpeechVoicePreferences.migrateLegacyDefaults(to: defaults, legacyDomains: [[
            "speech.preferredVoice.system": "old-choice",
            "speech.preferredVoice.openai": "alloy",
            "voice.secret": "never-copy"
        ]])
        XCTAssertEqual(defaults.string(forKey: "speech.preferredVoice.system"), "speech-choice")
        XCTAssertEqual(defaults.string(forKey: "speech.preferredVoice.openai"), "alloy")
        XCTAssertNil(defaults.object(forKey: "voice.secret"))
        defaults.removeObject(forKey: "speech.preferredVoice.openai")
        SpeechVoicePreferences.migrateLegacyDefaults(to: defaults, legacyDomains: [["speech.preferredVoice.openai": "alloy"]])
        XCTAssertNil(defaults.object(forKey: "speech.preferredVoice.openai"))
    }
}
