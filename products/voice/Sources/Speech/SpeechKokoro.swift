import Foundation
import HudsonUIAudio

struct SpeechKokoroStatus: Equatable, Sendable {
    var available: Bool
    var modelId: String
    var voiceId: String
    var detail: String?
    var voices: [SpeechVoiceInfo]

    init(
        available: Bool,
        modelId: String,
        voiceId: String,
        detail: String?,
        voices: [SpeechVoiceInfo] = []
    ) {
        self.available = available
        self.modelId = modelId
        self.voiceId = voiceId
        self.detail = detail
        self.voices = voices
    }

    static let compiledOut = SpeechKokoroStatus(
        available: false,
        modelId: "mlx-community/Kokoro-82M-bf16",
        voiceId: "af_heart",
        detail: "Kokoro is unavailable because HudsonVoice is not compiled into this build."
    )
}

@MainActor
protocol SpeechKokoroSynthesizing: AnyObject {
    func cachedStatus() -> SpeechKokoroStatus
    func cachedVoices() -> [SpeechVoiceInfo]
    func probe() async -> SpeechKokoroStatus
    func synthesize(text: String, voice: String?, rate: Double, model: String?) async throws -> HudTTSResult
}

enum SpeechKokoro {
    static var isCompiledIn: Bool {
        #if canImport(VoxService)
        true
        #else
        false
        #endif
    }

    @MainActor
    static var shared: any SpeechKokoroSynthesizing {
        #if canImport(VoxService)
        LiveSpeechKokoro.shared
        #else
        UnavailableSpeechKokoro.shared
        #endif
    }
}

@MainActor
final class UnavailableSpeechKokoro: SpeechKokoroSynthesizing {
    static let shared = UnavailableSpeechKokoro()

    func cachedStatus() -> SpeechKokoroStatus { .compiledOut }

    func cachedVoices() -> [SpeechVoiceInfo] { [] }

    func probe() async -> SpeechKokoroStatus { .compiledOut }

    func synthesize(text: String, voice: String?, rate: Double, model: String?) async throws -> HudTTSResult {
        throw SpeechQueueError.providerFailed(SpeechKokoroStatus.compiledOut.detail ?? "Kokoro is unavailable")
    }
}

#if canImport(VoxService)
@MainActor
final class LiveSpeechKokoro: SpeechKokoroSynthesizing {
    static let shared = LiveSpeechKokoro()

    func cachedStatus() -> SpeechKokoroStatus {
        SpeechKokoroRuntime.kokoroStatus()
    }

    func cachedVoices() -> [SpeechVoiceInfo] {
        SpeechKokoroRuntime.kokoroStatus().voices
    }

    func probe() async -> SpeechKokoroStatus {
        await SpeechKokoroRuntime.probeKokoro()
    }

    func synthesize(text: String, voice: String?, rate: Double, model: String?) async throws -> HudTTSResult {
        try await SpeechKokoroRuntime.synthesizeKokoro(
            text: text, voice: voice, rate: rate, model: model
        )
    }
}
#endif
