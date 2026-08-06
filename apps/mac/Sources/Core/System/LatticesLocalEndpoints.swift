import Foundation

/// Loopback endpoints owned by the Lattices menu bar process.
///
/// These ports are **deterministic and Lattices-owned**. They are not discovered
/// at random and should not depend on an external daemon for normal operation.
///
/// | Service            | Port | WebSocket                         | Lifecycle                         |
/// |--------------------|------|-----------------------------------|-----------------------------------|
/// | Agent API / daemon | 9399 | `ws://127.0.0.1:9399`             | `DaemonServer` at app boot        |
/// | Voice runtime      | 9398 | `ws://127.0.0.1:9398`             | `LatticesVoiceRuntime` at app boot|
///
/// Documented for agents and humans in `docs/voice.md`, `docs/app.md`, and
/// `docs/api.md`. Prefer these constants over magic numbers elsewhere in the app.
enum LatticesLocalEndpoints {
    /// Loopback bind host for all Lattices-local services.
    static let loopbackHost = "127.0.0.1"

    /// Agent API / daemon WebSocket (`DaemonServer`).
    static let agentAPIPort: UInt16 = 9399

    /// Lattices-hosted Hudson Voice / Vox live-session WebSocket.
    ///
    /// Adjacent to the agent API (9399) so the Lattices local port family is
    /// self-describing: `939x` = Lattices process-owned loopback services.
    ///
    /// Override only for tests/dev with `LATTICES_VOICE_PORT` (preferred) or
    /// the legacy `HUDSON_VOICE_VOX_PORT` env var.
    static let voiceRuntimePort: UInt16 = 9398

    static var agentAPIWebSocketURL: String {
        "ws://\(loopbackHost):\(agentAPIPort)"
    }

    static var voiceRuntimeWebSocketURL: String {
        "ws://\(loopbackHost):\(resolvedVoiceRuntimePort)"
    }

    /// Effective voice port after env override (still always loopback).
    static var resolvedVoiceRuntimePort: UInt16 {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["LATTICES_VOICE_PORT"] ?? env["HUDSON_VOICE_VOX_PORT"],
           let value = UInt16(raw), value > 0 {
            return value
        }
        return voiceRuntimePort
    }
}
