#if canImport(HudsonVoice)
import Foundation
import HudsonVoice

/// Builds the live voxd endpoint for HudsonVoice sessions.
///
/// HudsonVoice's built-in default (`HudVoxEndpoint.defaultPort`) can lag the
/// installed daemon — e.g. the SDK defaults to 42138 while the running voxd is on
/// 42137 — so a session that trusts the SDK default silently dials a dead port and
/// the mic flashes red and fails. We always discover the real port from
/// `~/.vox/runtime.json` via `VoxDaemon` instead.
///
/// This replaces `VoxClient.discoverDaemon()` for the HudsonVoice surfaces.
enum VoxEndpointResolver {
    /// The endpoint to hand `HudVoxLiveSession` / `HudVoicePanel`.
    static func resolve(host: String = "127.0.0.1") -> HudVoxEndpoint {
        HudVoxEndpoint(host: host, port: VoxDaemon.port)
    }
}
#endif
