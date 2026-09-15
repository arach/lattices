import Foundation

/// Per-provider preferred Speech voice. Stored in UserDefaults on this Mac.
/// Explicit `speech.enqueue` / MCP `voice` values are not written here.
@MainActor
final class SpeechVoicePreferences {
    static var shared = SpeechVoicePreferences()

    static func migrateLegacyDefaults(to destination: UserDefaults = .standard, legacyDomains: [[String: Any]]? = nil) {
        let marker = "speech.legacyPreferencesImported"
        guard !destination.bool(forKey: marker) else { return }
        // Source Info.plist and LatticesRuntime identify the two current domains;
        // installed legacy Lattices was independently observed as com.arach.lattices.
        let domains = legacyDomains ?? ["dev.lattices.app", "dev.lattices.app.dev", "com.arach.lattices"].map {
            UserDefaults.standard.persistentDomain(forName: $0) ?? [:]
        }
        for values in domains {
            for (key, value) in values where key.hasPrefix("speech.preferredVoice.") {
                if destination.object(forKey: key) == nil, let voice = value as? String { destination.set(voice, forKey: key) }
            }
        }
        destination.set(true, forKey: marker)
    }

    static let previewPhrase = "This is the selected voice."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func preferredVoice(for provider: String) -> String? {
        let value = defaults.string(forKey: Self.key(provider))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    func setPreferredVoice(_ voice: String?, for provider: String) {
        let cleaned = voice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if cleaned.isEmpty {
            defaults.removeObject(forKey: Self.key(provider))
        } else {
            defaults.set(cleaned, forKey: Self.key(provider))
        }
    }

    /// MCP/RPC `voice` wins when it is a non-empty string. Otherwise the
    /// stored preference for that provider is used. Nil means the provider
    /// default at synthesis.
    func resolvedVoice(explicit: String?, provider: String) -> String? {
        let override = explicit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !override.isEmpty { return override }
        return preferredVoice(for: provider)
    }

    private static func key(_ provider: String) -> String {
        "speech.preferredVoice.\(provider)"
    }
}
