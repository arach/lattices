#if canImport(HudsonVoice)
import Foundation
import HudsonVoice

/// Resolves the voice runtime Lattices should use.
///
/// Lattices is the HudsonKit host app here: it starts the embedded Vox runtime
/// and writes the private, tokened capability file during app boot.
enum HudsonVoiceRuntimeResolver {
    static func resolve(
        clientId: String = "lattices",
        mode: HudVoiceMode? = nil
    ) -> (endpoint: HudVoxEndpoint, options: HudVoxLiveSessionOptions)? {
        do {
            let connection = try HudsonVoiceRuntime.resolveConnection(
                clientId: clientId,
                mode: mode,
                metadata: ["hostApp": "lattices"]
            )
            return (connection.endpoint, connection.options)
        } catch {
            DiagnosticLog.shared.warn("HudsonVoice: embedded runtime unavailable - \(error.localizedDescription)")
            return nil
        }
    }
}
#endif
