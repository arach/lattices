#if LATTICES_VOICE && canImport(HudsonVoice)
import Foundation
import HudsonSpeechEngine
import VoxCore
import VoxService

/// Boots the embedded Vox engines with Kokoro TTS + Parakeet ASR for Lattices voice.
enum LatticesVoiceEngineLoader {
    static let kokoroModelId = "mlx-community/Kokoro-82M-bf16"
    static let kokoroVoiceId = "af_heart"

    static func loadEngines(runtimeHome: URL) throws -> (EngineManager, TTSEngineManager, String) {
        try seedRuntimeHome(runtimeHome)

        let configURL = runtimeHome.appendingPathComponent("providers.json")
        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                let config = try ProvidersConfig.load(from: configURL)
                let asrConfig = config.providers.contains(where: { $0.resolvedKind == .asr })
                    ? config
                    : defaultASRConfig()
                let ttsConfig = config.providers.contains(where: { $0.resolvedKind == .tts })
                    ? config.mergingMissingTTSDefaults()
                    : defaultTTSConfig()
                return (
                    EngineManager(provider: ProviderRegistry(config: asrConfig)),
                    TTSEngineManager(provider: TTSProviderRegistry(config: ttsConfig)),
                    resolveDefaultSynthesisModelId(for: ttsConfig)
                )
            } catch {
                DiagnosticLog.shared.warn(
                    "HudsonVoice: failed to parse providers.json — \(error.localizedDescription); using defaults"
                )
            }
        }

        let ttsConfig = defaultTTSConfig()
        return (
            EngineManager(provider: ProviderRegistry(config: defaultASRConfig())),
            TTSEngineManager(provider: TTSProviderRegistry(config: ttsConfig)),
            resolveDefaultSynthesisModelId(for: ttsConfig)
        )
    }

    private static func resolveDefaultSynthesisModelId(for config: ProvidersConfig) -> String {
        let models = config.providers
            .filter { $0.resolvedKind == .tts }
            .flatMap { $0.models ?? [] }
        if models.contains(kokoroModelId) {
            return kokoroModelId
        }
        return TTSDefaultModelSelector.defaultModelId(for: config)
    }

    private static func seedRuntimeHome(_ runtimeHome: URL) throws {
        try FileManager.default.createDirectory(at: runtimeHome, withIntermediateDirectories: true)

        let providersURL = runtimeHome.appendingPathComponent("providers.json")
        if !FileManager.default.fileExists(atPath: providersURL.path) {
            let userProviders = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".vox/providers.json")
            if FileManager.default.fileExists(atPath: userProviders.path) {
                try FileManager.default.copyItem(at: userProviders, to: providersURL)
            } else {
                try writeDefaultProviders(to: providersURL)
            }
        }

        let preferencesURL = runtimeHome.appendingPathComponent("preferences.json")
        var preferences = (try? VoxPreferences.load(from: preferencesURL)) ?? VoxPreferences()
        if preferences.speech.preferredSynthesisModelId?.isEmpty != false {
            preferences.speech.preferredSynthesisModelId = kokoroModelId
        }
        if preferences.speech.preferredSynthesisVoiceId?.isEmpty != false {
            preferences.speech.preferredSynthesisVoiceId = kokoroVoiceId
        }
        try preferences.save(to: preferencesURL)
    }

    private static func writeDefaultProviders(to url: URL) throws {
        let payload: [String: Any] = [
            "providers": [
                [
                    "id": "parakeet",
                    "kind": "asr",
                    "builtin": true,
                    "models": ["parakeet:v3"],
                ],
                [
                    "id": "mlx-audio",
                    "kind": "tts",
                    "builtin": true,
                    "models": [kokoroModelId],
                    "env": [
                        "VOX_MLX_AUDIO_USE_UV": "1",
                        "VOX_MLX_AUDIO_TTS_MODELS": kokoroModelId,
                        "VOX_MLX_AUDIO_TTS_DEFAULT_VOICE": kokoroVoiceId,
                        "VOX_PROVIDER_CALL_TIMEOUT_SECONDS": "300",
                    ],
                ],
                [
                    "id": "avspeech",
                    "kind": "tts",
                    "builtin": true,
                    "models": [AVSpeechSynthesizerProvider.modelID],
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    static func defaultASRConfig() -> ProvidersConfig {
        ProvidersConfig(providers: [
            ProviderEntry(
                id: "parakeet",
                kind: .asr,
                builtin: true,
                models: ["parakeet:v3"]
            ),
        ])
    }

    static func defaultTTSConfig() -> ProvidersConfig {
        ProvidersConfig(providers: [
            ProviderEntry(
                id: "mlx-audio",
                kind: .tts,
                builtin: true,
                models: [kokoroModelId],
                env: [
                    "VOX_MLX_AUDIO_USE_UV": "1",
                    "VOX_MLX_AUDIO_TTS_MODELS": kokoroModelId,
                    "VOX_MLX_AUDIO_TTS_DEFAULT_VOICE": kokoroVoiceId,
                    "VOX_PROVIDER_CALL_TIMEOUT_SECONDS": "300",
                ]
            ),
            ProviderEntry(
                id: "avspeech",
                kind: .tts,
                builtin: true,
                models: [AVSpeechSynthesizerProvider.modelID]
            ),
        ])
    }
}

private extension ProvidersConfig {
    func mergingMissingTTSDefaults() -> ProvidersConfig {
        let existingProviderIds = Set(
            providers
                .filter { $0.resolvedKind == .tts }
                .map { $0.id.lowercased() }
        )
        let additionalProviders = LatticesVoiceEngineLoader.defaultTTSConfig().providers.filter { entry in
            entry.resolvedKind == .tts && !existingProviderIds.contains(entry.id.lowercased())
        }
        guard !additionalProviders.isEmpty else { return self }
        return ProvidersConfig(providers: providers + additionalProviders)
    }
}
#endif
