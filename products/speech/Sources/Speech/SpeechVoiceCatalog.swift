import AVFoundation
import Foundation
import HudsonUI
import HudsonUIAudio
#if LATTICES_VOICE && canImport(HudsonSpeechEngine)
import HudsonSpeechEngine
#endif

extension Notification.Name {
    static let speechCredentialsDidChange = Notification.Name("lattices.speech.credentialsDidChange")
}

enum SpeechVoiceCatalogState: Equatable {
    case loading
    case ready([SpeechVoiceInfo])
    case empty(String)
    case unavailable(String)
    case failed(String)

    var voices: [SpeechVoiceInfo] {
        if case .ready(let voices) = self { return voices }
        return []
    }
}

/// Loads picker catalogs from the real Hudson/Vox/ElevenLabs sources.
/// Does not invent display names. OpenAI uses the Vox static TTS catalog when
/// HudsonSpeechEngine is compiled in; otherwise only the HudTTS default.
@MainActor
struct SpeechVoiceCatalogLoader {
    var credentialSource: LatticesSpeechCredentialSource
    var session: URLSession
    var kokoro: any SpeechKokoroSynthesizing
    var elevenLabsFetch: (String) async throws -> [SpeechVoiceInfo]

    init(
        credentialSource: LatticesSpeechCredentialSource = LatticesSpeechCredentialSource(),
        session: URLSession = .shared,
        kokoro: (any SpeechKokoroSynthesizing)? = nil,
        elevenLabsFetch: ((String) async throws -> [SpeechVoiceInfo])? = nil
    ) {
        self.credentialSource = credentialSource
        self.session = session
        self.kokoro = kokoro ?? SpeechKokoro.shared
        self.elevenLabsFetch = elevenLabsFetch ?? { key in
            try await SpeechElevenLabsVoiceCatalog.fetch(apiKey: key, session: session)
        }
    }

    func load(provider: String) async -> SpeechVoiceCatalogState {
        switch provider {
        case SpeechProviders.system:
            return .ready(Self.systemVoices())
        case SpeechProviders.openai:
            return .ready(Self.openaiVoices())
        case SpeechProviders.elevenlabs:
            return await loadElevenLabs()
        case SpeechProviders.kokoro:
            return await loadKokoro()
        default:
            return .unavailable("Unknown speech provider.")
        }
    }

    static func systemVoices() -> [SpeechVoiceInfo] {
        let defaultSystem = HudSystemSpeechDefaults.defaultVoiceIdentifier
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        if voices.isEmpty {
            return [SpeechVoiceInfo(
                id: defaultSystem,
                label: "System",
                provider: SpeechProviders.system,
                available: true,
                isDefault: true
            )]
        }
        return voices.map { voice in
            SpeechVoiceInfo(
                id: voice.identifier,
                label: voice.name,
                provider: SpeechProviders.system,
                available: true,
                isDefault: voice.identifier == defaultSystem
            )
        }
    }

    /// Vox `OpenAITTSProvider.supportedVoices` is the OpenAI TTS catalog.
    /// There is no live OpenAI voices endpoint. Without HudsonSpeechEngine,
    /// only the HudTTS adapter default is known.
    static func openaiVoices() -> [SpeechVoiceInfo] {
        #if LATTICES_VOICE && canImport(HudsonSpeechEngine)
        return OpenAITTSProvider.supportedVoices.map { id in
            SpeechVoiceInfo(
                id: id,
                label: id.capitalized,
                provider: SpeechProviders.openai,
                available: true,
                isDefault: id == "alloy"
            )
        }
        #else
        let adapter = HudTTSProviders.OpenAI()
        return [SpeechVoiceInfo(
            id: adapter.defaultVoice,
            label: adapter.defaultVoice.capitalized,
            provider: SpeechProviders.openai,
            available: true,
            isDefault: true
        )]
        #endif
    }

    static var openaiCatalogIsPartial: Bool {
        #if LATTICES_VOICE && canImport(HudsonSpeechEngine)
        false
        #else
        true
        #endif
    }

    private func loadElevenLabs() async -> SpeechVoiceCatalogState {
        let adapter = HudTTSProviders.ElevenLabs()
        guard let keyName = adapter.credentialKey else {
            return .unavailable("ElevenLabs is missing a credential key.")
        }
        let data: Data?
        do {
            data = try credentialSource.vault.get(keyName)
        } catch {
            return .failed("Could not read Keychain. Try reopening Settings.")
        }
        guard SpeechCredentialAvailability.isAvailable(credentialKey: keyName, data: data),
              let data,
              let apiKey = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty
        else {
            return .unavailable("Save an API key to load voices from ElevenLabs.")
        }

        do {
            let voices = try await elevenLabsFetch(apiKey)
            if voices.isEmpty {
                return .empty("ElevenLabs returned no voices for this key.")
            }
            return .ready(voices)
        } catch {
            return .failed(SpeechErrorRedactor.message(from: error))
        }
    }

    private func loadKokoro() async -> SpeechVoiceCatalogState {
        guard SpeechKokoro.isCompiledIn else {
            return .unavailable(SpeechKokoroStatus.compiledOut.detail ?? "Kokoro is unavailable.")
        }
        let status = await kokoro.probe()
        guard status.available else {
            return .unavailable(status.detail ?? "Kokoro is unavailable.")
        }
        let voices = kokoro.cachedVoices()
        if voices.isEmpty {
            return .empty("mlx-audio did not report a Kokoro voice.")
        }
        return .ready(voices)
    }
}

enum SpeechElevenLabsVoiceCatalog {
    /// Same contract as Vox `ElevenLabsTTSProvider.voices`: GET /v2/voices.
    /// First page only (`page_size=100`).
    static func fetch(apiKey: String, session: URLSession) async throws -> [SpeechVoiceInfo] {
        var components = URLComponents(string: "https://api.elevenlabs.io/v2/voices")
        components?.queryItems = [URLQueryItem(name: "page_size", value: "100")]
        guard let url = components?.url else {
            throw SpeechQueueError.providerFailed("Could not build the ElevenLabs voices URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpeechQueueError.providerFailed("ElevenLabs voices returned no HTTP response.")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw SpeechQueueError.providerFailed(
                body.isEmpty
                    ? "ElevenLabs voices failed (HTTP \(http.statusCode))."
                    : SpeechErrorRedactor.redact(body)
            )
        }
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let raw = object["voices"] as? [[String: Any]]
        else {
            throw SpeechQueueError.providerFailed("ElevenLabs voices response was not a voice list.")
        }
        let defaultID = HudTTSProviders.ElevenLabs().defaultVoice
        let parsed: [SpeechVoiceInfo] = raw.compactMap { voice in
            guard let id = voice["voice_id"] as? String, !id.isEmpty else { return nil }
            let name = (voice["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return SpeechVoiceInfo(
                id: id,
                label: (name?.isEmpty == false) ? name! : id,
                provider: SpeechProviders.elevenlabs,
                available: true,
                isDefault: id == defaultID
            )
        }
        if parsed.contains(where: \.isDefault) { return parsed }
        return parsed.enumerated().map { index, voice in
            SpeechVoiceInfo(
                id: voice.id,
                label: voice.label,
                provider: voice.provider,
                available: voice.available,
                isDefault: index == 0
            )
        }
    }
}

@MainActor
final class SpeechVoiceCatalogStore: ObservableObject {
    static let shared = SpeechVoiceCatalogStore()

    @Published private(set) var states: [String: SpeechVoiceCatalogState] = [:]

    private var loader: SpeechVoiceCatalogLoader

    init(loader: SpeechVoiceCatalogLoader? = nil) {
        self.loader = loader ?? SpeechVoiceCatalogLoader()
    }

    func replaceLoader(_ loader: SpeechVoiceCatalogLoader) {
        self.loader = loader
    }

    func state(for provider: String) -> SpeechVoiceCatalogState? {
        states[provider]
    }

    func refresh(provider: String) async {
        states[provider] = .loading
        states[provider] = await loader.load(provider: provider)
    }

    func refreshListedProviders() async {
        var providers = [SpeechProviders.system, SpeechProviders.openai, SpeechProviders.elevenlabs]
        if SpeechKokoro.isCompiledIn {
            providers.append(SpeechProviders.kokoro)
        }
        for provider in providers {
            await refresh(provider: provider)
        }
    }
}
