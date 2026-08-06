import Foundation
import Security

#if LATTICES_VOICE && canImport(HudsonVoice)
import HudsonVoice
import VoxService
#endif

/// Boot/shutdown owner for Lattices' embedded voice runtime.
///
/// Lattices is the permission and lifecycle owner: the menu bar process starts
/// an in-process Vox live-session server on a **deterministic** loopback port
/// (`LatticesLocalEndpoints.voiceRuntimePort`, default **9398**), writes a
/// private Hudson capability file, and tears it down on quit.
///
/// Clients (Workspace Assistant mic, Hands-Off, voice commands) resolve through
/// `HudsonVoiceRuntimeResolver` → that capability file — they do not depend on
/// an external `voxd` being up.
enum LatticesVoiceRuntime {
    static func start() {
        #if LATTICES_VOICE && canImport(HudsonVoice)
        do {
            try Host.shared.start()
            let endpoint = Host.shared.endpointURL
            DiagnosticLog.shared.success(
                "HudsonVoice: embedded runtime started at \(endpoint) (capability \(Host.shared.capabilityURL.path))"
            )
        } catch {
            DiagnosticLog.shared.warn(
                "HudsonVoice: embedded runtime failed to start — \(error.localizedDescription)"
            )
        }
        #else
        DiagnosticLog.shared.info(
            "HudsonVoice: runtime host skipped because HudsonVoice is not compiled into this build"
        )
        #endif
    }

    /// Start if needed (e.g. boot failed earlier, or first capture after idle).
    /// Safe to call repeatedly; no-ops when already hosting.
    @discardableResult
    static func ensureRunning() -> Bool {
        #if LATTICES_VOICE && canImport(HudsonVoice)
        if Host.shared.isRunning { return true }
        start()
        return Host.shared.isRunning
        #else
        return false
        #endif
    }

    static func stop() {
        #if LATTICES_VOICE && canImport(HudsonVoice)
        Host.shared.stop()
        DiagnosticLog.shared.info("HudsonVoice: embedded runtime stopped")
        #endif
    }

    #if LATTICES_VOICE && canImport(HudsonVoice)
    /// True when this process is currently hosting the voice WebSocket.
    static var isRunning: Bool { Host.shared.isRunning }

    static var endpointDescription: String? {
        guard Host.shared.isRunning else { return nil }
        return Host.shared.endpointURL
    }
    #else
    static var isRunning: Bool { false }
    #endif
}

#if LATTICES_VOICE && canImport(HudsonVoice)

// MARK: - In-process host

/// Lattices-owned Vox host. Modeled on the former HudsonKit
/// `HudsonVoiceRuntimeHost`, but with a fixed Lattices port family instead of
/// a random ephemeral port.
private final class Host: @unchecked Sendable {
    static let shared = Host()

    private let lock = NSRecursiveLock()
    private let bindAddress = LatticesLocalEndpoints.loopbackHost
    private let port: UInt16
    private let runtimeHomeURL: URL
    private let runtimeCapabilityURL: URL
    private let voxRuntimeURL: URL
    private var runtimeService: VoxRuntimeService?

    private(set) var isRunning = false

    var capabilityURL: URL { runtimeCapabilityURL }

    var endpointURL: String {
        "ws://\(bindAddress):\(port)"
    }

    private init() {
        let home = Self.defaultRuntimeHomeURL()
        runtimeHomeURL = home
        runtimeCapabilityURL = home.appendingPathComponent("hudson-voice-runtime.json")
        voxRuntimeURL = home.appendingPathComponent("vox-runtime.json")
        port = LatticesLocalEndpoints.resolvedVoiceRuntimePort
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }

        if runtimeService != nil, isRunning, HudsonVoiceRuntime.isAvailable() {
            return
        }

        // Tear down a half-started previous attempt before retrying.
        runtimeService?.stop()
        runtimeService = nil
        removeRuntimeCapability()

        let authToken = try Self.generateCapabilityToken()
        try configureEnvironment(authToken: authToken)
        try persistPreferences()

        let service = VoxRuntimeService(
            port: port,
            bindAddress: bindAddress,
            authToken: authToken
        )
        do {
            try service.start()
            try writeRuntimeCapability(authToken: authToken, startedAt: Date())
            runtimeService = service
            isRunning = true
        } catch {
            service.stop()
            removeRuntimeCapability()
            isRunning = false
            throw error
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        runtimeService?.stop()
        runtimeService = nil
        removeRuntimeCapability()
        isRunning = false
    }

    private func configureEnvironment(authToken: String) throws {
        try FileManager.default.createDirectory(at: runtimeHomeURL, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: runtimeHomeURL.path
        )
        setenv("VOX_HOME", runtimeHomeURL.path, 1)
        setenv("VOX_RUNTIME_PATH", voxRuntimeURL.path, 1)
        setenv("VOX_HOST", bindAddress, 1)
        setenv("VOX_PORT", String(port), 1)
        setenv("VOX_AUTH_TOKEN", authToken, 1)
        // Point HudsonVoice's capability reader at Lattices' file (not Hudson Menu's).
        setenv(HudsonVoiceRuntime.runtimePathEnvironmentKey, runtimeCapabilityURL.path, 1)
        setenv("LATTICES_VOICE_PORT", String(port), 1)
    }

    private func persistPreferences() throws {
        let preferences = (try? HudsonVoicePreferences.load()) ?? HudsonVoicePreferences()
        try preferences.normalized().save()
    }

    private func writeRuntimeCapability(authToken: String, startedAt: Date) throws {
        let document = RuntimeCapabilityDocument(
            host: bindAddress,
            port: port,
            authToken: authToken,
            pid: getpid(),
            startedAt: ISO8601DateFormatter().string(from: startedAt),
            voxRuntimePath: voxRuntimeURL.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: runtimeCapabilityURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: runtimeCapabilityURL.path
        )
    }

    private func removeRuntimeCapability() {
        if FileManager.default.fileExists(atPath: runtimeCapabilityURL.path) {
            try? FileManager.default.removeItem(at: runtimeCapabilityURL)
        }
    }

    private static func defaultRuntimeHomeURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        // Lattices-owned home — separate from Hudson Menu's Application Support/Hudson/Vox.
        return base
            .appendingPathComponent("Lattices", isDirectory: true)
            .appendingPathComponent("Voice", isDirectory: true)
    }

    private static func generateCapabilityToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let byteCount = bytes.count
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw NSError(
                domain: "LatticesVoiceRuntime",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Could not generate voice capability token."]
            )
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Wire format expected by `HudsonVoiceRuntime` (schemaVersion 1, service hudson-voice).
private struct RuntimeCapabilityDocument: Encodable {
    let schemaVersion = 1
    let service = "hudson-voice"
    let transport = "ws+json-rpc"
    let host: String
    let port: UInt16
    let webSocketUrl: String
    let authToken: String
    let pid: Int32
    let startedAt: String
    let voxRuntimePath: String

    init(
        host: String,
        port: UInt16,
        authToken: String,
        pid: Int32,
        startedAt: String,
        voxRuntimePath: String
    ) {
        self.host = host
        self.port = port
        self.webSocketUrl = "ws://\(host):\(port)"
        self.authToken = authToken
        self.pid = pid
        self.startedAt = startedAt
        self.voxRuntimePath = voxRuntimePath
    }
}

#endif
