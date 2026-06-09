import Foundation

/// File-based discovery of the local voxd transcription daemon.
///
/// voxd writes its live port + pid to `~/.vox/runtime.json`. This is the single
/// source of truth for "is Vox reachable, and on what port" — it replaces the
/// connection-state bookkeeping the old `VoxClient` singleton kept.
///
/// Pure Foundation, intentionally **not** gated on `canImport(HudsonVoice)`, so the
/// availability/launch paths (AudioLayer, HandsOffSession, the voice overlay, the
/// daemon API) still compile in a build without the voice product. The HudsonVoice
/// surfaces turn this into a `HudVoxEndpoint` via `VoxEndpointResolver`.
enum VoxDaemon {
    /// voxd's long-standing default port — used when runtime.json is absent.
    static let fallbackPort: UInt16 = 42137
    private static let runtimePath = NSHomeDirectory() + "/.vox/runtime.json"

    struct Info {
        let port: UInt16
        let pid: Int
        let version: String
    }

    /// Parsed `~/.vox/runtime.json` with a verified-alive pid, or nil if the file
    /// is missing, malformed, or names a process that is no longer running.
    static func info() -> Info? {
        guard let data = FileManager.default.contents(atPath: runtimePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = json["port"] as? Int, port > 0, port <= 65535,
              let pid = json["pid"] as? Int else {
            return nil
        }
        // A runtime.json can outlive its daemon — verify the pid is actually alive.
        guard kill(Int32(pid), 0) == 0 else {
            DiagnosticLog.shared.warn("VoxDaemon: stale runtime.json — pid \(pid) not running")
            return nil
        }
        let version = json["version"] as? String ?? "unknown"
        return Info(port: UInt16(port), pid: pid, version: version)
    }

    /// voxd's live port, falling back to the long-standing default when unknown.
    static var port: UInt16 { info()?.port ?? fallbackPort }

    /// Whether voxd is discoverable and its process is alive right now.
    static var isRunning: Bool { info() != nil }
}
