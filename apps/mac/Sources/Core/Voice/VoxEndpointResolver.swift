#if canImport(HudsonVoice)
import Foundation
import HudsonVoice

/// Resolves the voice runtime Lattices should use.
///
/// HudsonVoice's current native surface speaks Vox's local WebSocket JSON-RPC
/// contract directly. Prefer a discovered standalone Vox runtime, then fall
/// back to HudsonVoice's default endpoint so built-in voice mode remains usable
/// in Hudson-hosted/dev environments.
enum HudsonVoiceRuntimeResolver {
    static func resolve(
        clientId: String = "lattices",
        mode: HudVoiceMode? = nil
    ) -> (endpoint: HudVoxEndpoint, options: HudVoxLiveSessionOptions, source: String, pid: Int?)? {
        let standalone = VoxDaemon.info()
        let endpoint = HudVoxEndpoint(
            host: "127.0.0.1",
            port: standalone?.port ?? HudVoxEndpoint.defaultPort
        )
        let options = HudVoxLiveSessionOptions(
            clientId: clientId,
            mode: mode ?? .pushToTalk,
            metadata: ["hostApp": "lattices"]
        )
        return (
            endpoint: endpoint,
            options: options,
            source: standalone == nil ? "hudson-voice-default" : "vox-runtime",
            pid: standalone?.pid
        )
    }
}
#endif
