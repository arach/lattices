import Foundation
import HudsonUIAudio
import HudsonSpeechEngine
import VoxCore
import VoxService

/// Speech hosts the same Vox mlx-audio synthesis engine directly. It does not
/// connect to or own the Lattices capture runtime on port 9398.
@MainActor
enum SpeechKokoroRuntime {
    static let modelID = "mlx-community/Kokoro-82M-bf16"
    static let voiceID = "af_heart"
    private static var status = SpeechKokoroStatus(available: false, modelId: modelID,
        voiceId: voiceID, detail: "Kokoro has not been checked.")
    private static let engine = TTSEngineManager(provider: TTSProviderRegistry(config: ProvidersConfig(providers: [
        ProviderEntry(id: "mlx-audio", kind: .tts, builtin: true, models: [modelID], env: [
            "VOX_MLX_AUDIO_USE_UV": "1", "VOX_MLX_AUDIO_TTS_MODELS": modelID,
            "VOX_MLX_AUDIO_TTS_DEFAULT_VOICE": voiceID, "VOX_PROVIDER_CALL_TIMEOUT_SECONDS": "300"
        ])
    ])))
    static func kokoroStatus() -> SpeechKokoroStatus { status }
    static func probeKokoro() async -> SpeechKokoroStatus {
        do {
            let voices = try await engine.voices(modelId: modelID)
            let mapped = voices.map { SpeechVoiceInfo(id: $0.id, label: $0.name.isEmpty ? $0.id : $0.name,
                provider: SpeechProviders.kokoro, available: $0.available, isDefault: $0.id == voiceID || $0.isDefault) }
            status = SpeechKokoroStatus(available: mapped.contains { $0.available }, modelId: modelID,
                voiceId: voiceID, detail: mapped.isEmpty ? "Kokoro reported no voices." : nil, voices: mapped)
        } catch {
            status = SpeechKokoroStatus(available: false, modelId: modelID, voiceId: voiceID,
                detail: SpeechErrorRedactor.message(from: error))
        }
        return status
    }
    static func synthesizeKokoro(text: String, voice: String?, rate: Double, model: String?) async throws -> HudTTSResult {
        let selected = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedModel = selected.isEmpty ? modelID : selected
        guard selectedModel.lowercased().contains("kokoro") else {
            throw SpeechQueueError.providerFailed("Kokoro requires a Kokoro model through mlx-audio")
        }
        let output = try await engine.synthesize(SynthesisRequest(text: text, modelId: selectedModel,
            voiceId: voice ?? voiceID, format: "wav", speed: rate))
        guard !output.audioData.isEmpty, output.modelId.lowercased().contains("kokoro") else {
            throw SpeechQueueError.providerFailed("Kokoro did not produce valid audio")
        }
        let format: HudTTSAudioFormat = output.format.lowercased() == "mp3" ? .mp3 : output.format.lowercased() == "caf" ? .caf : .wav
        return HudTTSResult(audioData: output.audioData, format: format,
            providerID: HudTTSProviderID(rawValue: SpeechProviders.kokoro), voice: output.voiceId.isEmpty ? voiceID : output.voiceId)
    }
}
