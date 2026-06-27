#if LATTICES_VOICE && canImport(HudsonVoice)
import Darwin
import Foundation
import HudsonVoice

/// Resolves the voice runtime Lattices should use.
///
/// HudsonVoice speaks Vox's local WebSocket JSON-RPC contract directly. Prefer
/// the runtime file written by Vox so dev builds can move ports without making
/// Lattices point at a stale default.
enum HudsonVoiceRuntimeResolver {
    private struct RuntimeFile: Decodable {
        let host: String?
        let port: UInt16?
        let pid: Int?
        let serviceName: String?
        let service: String?
        let transport: String?
        let webSocketUrl: String?
        let authToken: String?
    }

    static func resolve(
        clientId: String = "lattices",
        mode: HudVoiceMode? = nil
    ) -> (endpoint: HudVoxEndpoint, options: HudVoxLiveSessionOptions, source: String, pid: Int?, authToken: String?, capabilityPath: String?)? {
        let runtime = resolvedRuntime()
        let endpoint = HudVoxEndpoint(host: runtime.host, port: runtime.port)
        let options = HudVoxLiveSessionOptions(
            clientId: clientId,
            mode: mode ?? .pushToTalk,
            metadata: ["hostApp": "lattices"]
        )
        return (
            endpoint: endpoint,
            options: options,
            source: runtime.source,
            pid: runtime.pid,
            authToken: runtime.authToken,
            capabilityPath: runtime.path
        )
    }

    private static func resolvedRuntime() -> (host: String, port: UInt16, source: String, pid: Int?, authToken: String?, path: String?) {
        for candidate in runtimeFileCandidates() {
            guard let runtime = readRuntimeFile(candidate.url),
                  let port = runtime.port,
                  port > 0,
                  runtime.pid.map(processIsAlive) ?? true else { continue }
            // HudVoxLiveSession does not currently expose an auth-token field,
            // so authenticated Hudson capability files cannot be used safely yet.
            guard nonEmpty(runtime.authToken) == nil else { continue }

            let host = runtime.host
                ?? hostFromWebSocketURL(runtime.webSocketUrl)
                ?? "127.0.0.1"
            guard isLoopback(host) else { continue }

            return (
                host: host,
                port: port,
                source: candidate.source,
                pid: runtime.pid,
                authToken: nonEmpty(runtime.authToken),
                path: candidate.url.path
            )
        }

        let env = ProcessInfo.processInfo.environment
        if let rawPort = env["VOX_PORT"] ?? env["HUDSON_VOICE_VOX_PORT"],
           let port = UInt16(rawPort) {
            return (
                host: nonEmpty(env["VOX_HOST"]) ?? "127.0.0.1",
                port: port,
                source: "env",
                pid: nil,
                authToken: nonEmpty(env["VOX_AUTH_TOKEN"]),
                path: nil
            )
        }

        // Vox's current daemon default is 42137. HudsonVoice's older 42138
        // default is intentionally avoided here because it makes Lattices miss
        // a running Vox dev daemon and surface a fake transcription failure.
        return (
            host: "127.0.0.1",
            port: 42137,
            source: "vox-default",
            pid: nil,
            authToken: nil,
            path: nil
        )
    }

    private static func runtimeFileCandidates() -> [(url: URL, source: String)] {
        var candidates: [(URL, String)] = []
        let env = ProcessInfo.processInfo.environment

        if let path = nonEmpty(env["VOX_RUNTIME_PATH"]) {
            candidates.append((URL(fileURLWithPath: path), "vox"))
        }
        candidates.append((
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".vox", isDirectory: true)
                .appendingPathComponent("runtime.json"),
            "vox"
        ))

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        if let path = nonEmpty(env["HUDSON_VOICE_RUNTIME_PATH"]) {
            candidates.append((URL(fileURLWithPath: path), "hudson-voice"))
        }
        candidates.append((
            support
                .appendingPathComponent("Hudson", isDirectory: true)
                .appendingPathComponent("Vox", isDirectory: true)
                .appendingPathComponent("hudson-voice-runtime.json"),
            "hudson-voice"
        ))

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.0.standardizedFileURL.path
            return seen.insert(key).inserted
        }
    }

    private static func readRuntimeFile(_ url: URL) -> RuntimeFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RuntimeFile.self, from: data)
    }

    private static func hostFromWebSocketURL(_ raw: String?) -> String? {
        guard let raw, let url = URL(string: raw), let host = url.host else { return nil }
        return host
    }

    private static func isLoopback(_ host: String) -> Bool {
        let lowered = host.lowercased()
        return lowered == "localhost" || lowered == "127.0.0.1" || lowered == "::1"
    }

    private static func processIsAlive(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid_t(pid), 0) == 0 || errno == EPERM
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
