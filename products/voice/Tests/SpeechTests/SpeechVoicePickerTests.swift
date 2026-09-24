import XCTest
import HudsonUI
import HudsonUIAudio
#if LATTICES_VOICE && canImport(HudsonSpeechEngine)
import HudsonSpeechEngine
#endif
@testable import SpeechAppRuntime

@MainActor
final class SpeechVoicePickerTests: XCTestCase {
    func testPreferredVoiceIsUsedWhenEnqueueOmitsVoice() throws {
        let queue = SpeechQueue(
            synthesizer: FakeSpeechSynthesizer(),
            player: FakeSpeechPlayer(),
            preferredVoiceForProvider: { provider in
                provider == "openai" ? "coral" : nil
            }
        )
        let job = try queue.enqueue(SpeechEnqueueRequest(
            text: "No voice override",
            provider: "openai",
            model: nil,
            voice: nil,
            rate: 1,
            instructions: nil,
            voiceSettings: nil,
            cachePolicy: .reuse,
            source: nil
        ))
        XCTAssertEqual(job.voice, "coral")
        _ = try queue.stop()
    }

    func testExplicitVoiceOverrideBeatsStoredPreference() throws {
        let queue = SpeechQueue(
            synthesizer: FakeSpeechSynthesizer(),
            player: FakeSpeechPlayer(),
            preferredVoiceForProvider: { _ in "alloy" }
        )
        let job = try queue.enqueue(SpeechEnqueueRequest(
            text: "MCP named a voice",
            provider: "openai",
            model: nil,
            voice: "echo",
            rate: 1,
            instructions: nil,
            voiceSettings: nil,
            cachePolicy: .reuse,
            source: nil
        ))
        XCTAssertEqual(job.voice, "echo")
        let parsed = try SpeechRpc.parseEnqueue(.object([
            "text": .string("MCP named a voice"),
            "provider": .string("openai"),
            "voice": .string("echo"),
        ]))
        XCTAssertEqual(parsed.voice, "echo")
        _ = try queue.stop()
    }

    func testWhitespaceVoiceIsTreatedAsNoOverride() throws {
        let queue = SpeechQueue(
            synthesizer: FakeSpeechSynthesizer(),
            player: FakeSpeechPlayer(),
            preferredVoiceForProvider: { _ in "nova" }
        )
        let job = try queue.enqueue(SpeechEnqueueRequest(
            text: "blank voice",
            provider: "openai",
            model: nil,
            voice: "  ",
            rate: 1,
            instructions: nil,
            voiceSettings: nil,
            cachePolicy: .reuse,
            source: nil
        ))
        XCTAssertEqual(job.voice, "nova")
        _ = try queue.stop()
    }

    func testOpenAICatalogComesFromVoxWhenCompiled() {
        let voices = SpeechVoiceCatalogLoader.openaiVoices()
        XCTAssertFalse(voices.isEmpty)
        XCTAssertTrue(voices.contains(where: { $0.id == "alloy" }))
        XCTAssertFalse(voices.contains(where: { $0.provider == "groq" }))
        #if LATTICES_VOICE && canImport(HudsonSpeechEngine)
        XCTAssertEqual(voices.map(\.id), OpenAITTSProvider.supportedVoices)
        XCTAssertFalse(SpeechVoiceCatalogLoader.openaiCatalogIsPartial)
        #else
        XCTAssertEqual(voices.map(\.id), [HudTTSProviders.OpenAI().defaultVoice])
        XCTAssertTrue(SpeechVoiceCatalogLoader.openaiCatalogIsPartial)
        #endif
    }

    func testElevenLabsMissingKeyDoesNotInventVoices() async {
        let loader = SpeechVoiceCatalogLoader(
            credentialSource: LatticesSpeechCredentialSource(
                vault: HudVault(service: "dev.lattices.app.voice.speech-voice-empty")
            ),
            elevenLabsFetch: { _ in
                XCTFail("ElevenLabs must not be fetched without a key")
                return []
            }
        )
        let state = await loader.load(provider: "elevenlabs")
        XCTAssertEqual(state, .unavailable("Save an API key to load voices from ElevenLabs."))
        XCTAssertTrue(state.voices.isEmpty)
    }

    func testElevenLabsEmptyAndFailedResultsStayHonest() async {
        let vault = HudVault(service: "dev.lattices.app.voice.speech-voice-el")
        try? vault.set("elevenlabs_key", Data("sk-test".utf8))
        defer { try? vault.delete("elevenlabs_key") }

        let emptyLoader = SpeechVoiceCatalogLoader(
            credentialSource: LatticesSpeechCredentialSource(vault: vault),
            elevenLabsFetch: { _ in [] }
        )
        let empty = await emptyLoader.load(provider: "elevenlabs")
        XCTAssertEqual(empty, .empty("ElevenLabs returned no voices for this key."))

        let failedLoader = SpeechVoiceCatalogLoader(
            credentialSource: LatticesSpeechCredentialSource(vault: vault),
            elevenLabsFetch: { _ in throw SpeechQueueError.providerFailed("ElevenLabs voices failed (HTTP 401).") }
        )
        let failed = await failedLoader.load(provider: "elevenlabs")
        XCTAssertEqual(failed, .failed("ElevenLabs voices failed (HTTP 401)."))
    }

    func testKokoroCatalogUsesProbedVoicesOnly() async {
        let kokoro = FakeSpeechKokoro(status: SpeechKokoroStatus(
            available: true,
            modelId: "mlx-community/Kokoro-82M-bf16",
            voiceId: "af_heart",
            detail: nil,
            voices: [
                SpeechVoiceInfo(id: "af_heart", label: "af_heart", provider: "kokoro", available: true, isDefault: true),
                SpeechVoiceInfo(id: "af_bella", label: "af_bella", provider: "kokoro", available: true, isDefault: false),
            ]
        ))
        let loader = SpeechVoiceCatalogLoader(kokoro: kokoro)
        guard SpeechKokoro.isCompiledIn else {
            let state = await loader.load(provider: "kokoro")
            XCTAssertEqual(state, .unavailable(SpeechKokoroStatus.compiledOut.detail ?? ""))
            return
        }
        let state = await loader.load(provider: "kokoro")
        XCTAssertEqual(state.voices.map(\.id), ["af_heart", "af_bella"])
    }

    func testPreviewEnqueueUsesExplicitVoiceAndDoesNotHideAsUICue() throws {
        let queue = SpeechQueue(
            synthesizer: FakeSpeechSynthesizer(),
            player: FakeSpeechPlayer(),
            preferredVoiceForProvider: { _ in "alloy" }
        )
        let job = try SpeechRuntime.enqueuePreview(provider: "openai", voice: "echo", queue: queue)
        XCTAssertEqual(job.voice, "echo")
        XCTAssertEqual(job.text, SpeechVoicePreferences.previewPhrase)
        XCTAssertEqual(job.source?.kind, "preview")
        XCTAssertEqual(SpeechHUDPresentation.action(for: queue.snapshot), .show)
        _ = try queue.stop()
    }

    func testResolvedVoiceHelperKeepsExplicitMCPOverride() {
        let defaults = UserDefaults(suiteName: "speech-voice-pref-\(UUID().uuidString)")!
        let prefs = SpeechVoicePreferences(defaults: defaults)
        prefs.setPreferredVoice("alloy", for: "openai")
        XCTAssertEqual(prefs.resolvedVoice(explicit: "coral", provider: "openai"), "coral")
        XCTAssertEqual(prefs.resolvedVoice(explicit: nil, provider: "openai"), "alloy")
        XCTAssertEqual(prefs.resolvedVoice(explicit: "  ", provider: "openai"), "alloy")
    }
}

@MainActor
private final class FakeSpeechKokoro: SpeechKokoroSynthesizing {
    var status: SpeechKokoroStatus

    init(status: SpeechKokoroStatus) {
        self.status = status
    }

    func cachedStatus() -> SpeechKokoroStatus { status }
    func cachedVoices() -> [SpeechVoiceInfo] { status.voices }
    func probe() async -> SpeechKokoroStatus { status }
    func synthesize(text: String, voice: String?, rate: Double, model: String?) async throws -> HudTTSResult {
        throw SpeechQueueError.providerFailed("fake Kokoro has no audio")
    }
}


