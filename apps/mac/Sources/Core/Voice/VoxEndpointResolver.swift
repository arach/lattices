#if canImport(HudsonVoice)
import Foundation
import HudsonVoice

/// Resolves the voice runtime Lattices should use.
///
/// HudsonVoice speaks Vox's local WebSocket JSON-RPC contract directly and is the
/// only voice path: Lattices always connects to HudsonVoice's default endpoint.
/// Vox is no longer a standalone service, so there is no runtime-file discovery
/// and no fallback chain.
enum HudsonVoiceRuntimeResolver {
    static func resolve(
        clientId: String = "lattices",
        mode: HudVoiceMode? = nil
    ) -> (endpoint: HudVoxEndpoint, options: HudVoxLiveSessionOptions, source: String, pid: Int?)? {
        let endpoint = HudVoxEndpoint(
            host: "127.0.0.1",
            port: HudVoxEndpoint.defaultPort
        )
        let options = HudVoxLiveSessionOptions(
            clientId: clientId,
            mode: mode ?? .pushToTalk,
            metadata: ["hostApp": "lattices"]
        )
        return (endpoint: endpoint, options: options, source: "hudson-voice", pid: nil)
    }
}
#endif
