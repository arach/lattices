#if LATTICES_VOICE && canImport(HudsonVoice)
import Foundation
import HudsonVoice

/// Resolves the voice runtime used by every Lattices dictation surface.
///
/// Lattices normally owns an authenticated, in-process Vox service. If that
/// service cannot start, accept a current Hudson capability file as a fallback.
/// Never manufacture a default endpoint: returning a dead port made the UI say
/// voice was available even though every capture was guaranteed to fail.
enum HudsonVoiceRuntimeResolver {
    static func resolve(
        clientId: String = "lattices",
        mode: HudVoiceMode? = nil
    ) -> (endpoint: HudVoxEndpoint, options: HudVoxLiveSessionOptions, source: String, pid: Int?, authToken: String?, capabilityPath: String?)? {
        if let embedded = LatticesVoiceRuntime.connection(clientId: clientId, mode: mode) {
            return (
                endpoint: embedded.endpoint,
                options: embedded.options,
                source: embedded.source,
                pid: embedded.pid,
                authToken: embedded.authToken,
                capabilityPath: embedded.runtimePath
            )
        }

        do {
            let connection = try HudsonVoiceRuntime.resolveConnection(
                clientId: clientId,
                mode: mode,
                metadata: ["hostApp": "lattices"]
            )
            return (
                endpoint: connection.endpoint,
                options: connection.options,
                source: "hudson-voice",
                pid: connection.capability.pid.map(Int.init),
                authToken: connection.capability.authToken,
                capabilityPath: HudsonVoiceRuntime.runtimeURL().path
            )
        } catch {
            DiagnosticLog.shared.warn(
                "HudsonVoice: no usable embedded or external runtime — \(error.localizedDescription)"
            )
            return nil
        }
    }
}
#endif
