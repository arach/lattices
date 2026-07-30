import Foundation

#if LATTICES_VOICE && canImport(HudsonVoice)
import HudsonVoice
import Security
import VoxService
#endif

enum LatticesVoiceRuntime {
    static func start() {
        #if LATTICES_VOICE && canImport(HudsonVoice)
        EmbeddedHost.shared.start()
        #else
        DiagnosticLog.shared.info("HudsonVoice: runtime host skipped because HudsonVoice is not compiled into this build")
        #endif
    }

    static func stop() {
        #if LATTICES_VOICE && canImport(HudsonVoice)
        EmbeddedHost.shared.stop()
        #endif
    }

    #if LATTICES_VOICE && canImport(HudsonVoice)
    struct Connection {
        let endpoint: HudVoxEndpoint
        let options: HudVoxLiveSessionOptions
        let source: String
        let pid: Int?
        let authToken: String
        let runtimePath: String
    }

    static func connection(
        clientId: String,
        mode: HudVoiceMode?
    ) -> Connection? {
        EmbeddedHost.shared.connection(clientId: clientId, mode: mode)
    }

    private final class EmbeddedHost: @unchecked Sendable {
        static let shared = EmbeddedHost()

        private struct RunningHost {
            let service: VoxRuntimeService
            let endpoint: HudVoxEndpoint
            let authToken: String
            let runtimePath: String
        }

        private let lock = NSLock()
        private var running: RunningHost?
        private var isStarting = false
        private var lastFailure: String?

        private init() {}

        func start() {
            lock.lock()
            guard running == nil, !isStarting else {
                lock.unlock()
                return
            }
            isStarting = true
            lock.unlock()

            let result = Result { try startService() }

            lock.lock()
            isStarting = false
            switch result {
            case .success(let host):
                running = host
                lastFailure = nil
            case .failure(let error):
                lastFailure = error.localizedDescription
            }
            lock.unlock()

            switch result {
            case .success(let host):
                DiagnosticLog.shared.success(
                    "HudsonVoice: embedded runtime started at \(host.endpoint.url.absoluteString)"
                )
            case .failure(let error):
                DiagnosticLog.shared.error(
                    "HudsonVoice: embedded runtime failed to start — \(error.localizedDescription)"
                )
            }
        }

        func stop() {
            lock.lock()
            let host = running
            running = nil
            lastFailure = nil
            lock.unlock()

            host?.service.stop()
            if host != nil {
                DiagnosticLog.shared.info("HudsonVoice: embedded runtime stopped")
            }
        }

        func connection(clientId: String, mode: HudVoiceMode?) -> Connection? {
            start()

            lock.lock()
            let host = running
            let failure = lastFailure
            lock.unlock()

            guard let host else {
                if let failure {
                    DiagnosticLog.shared.warn("HudsonVoice: embedded runtime unavailable — \(failure)")
                }
                return nil
            }

            let preferences = (try? HudsonVoicePreferences.load()) ?? HudsonVoicePreferences()
            let options = HudVoxLiveSessionOptions(
                clientId: clientId,
                modelId: preferences.preferredTranscriptionModelId,
                language: preferences.preferredLanguage,
                mode: mode ?? preferences.mode,
                metadata: ["hostApp": "lattices"],
                authToken: host.authToken,
                deviceId: preferences.preferredInputDeviceId
            )
            return Connection(
                endpoint: host.endpoint,
                options: options,
                source: "lattices-embedded",
                pid: Int(getpid()),
                authToken: host.authToken,
                runtimePath: host.runtimePath
            )
        }

        private func startService() throws -> RunningHost {
            let runtimeHome = try Self.prepareRuntimeHome()
            let runtimeURL = runtimeHome.appendingPathComponent("vox-runtime.json")
            let authToken = try Self.generateCapabilityToken()

            setenv("VOX_HOME", runtimeHome.path, 1)
            setenv("VOX_RUNTIME_PATH", runtimeURL.path, 1)

            var lastError: Error?
            for _ in 0..<8 {
                let port = UInt16.random(in: 49_152...65_535)
                let service = VoxRuntimeService(
                    port: port,
                    bindAddress: "127.0.0.1",
                    authToken: authToken
                )
                do {
                    try service.start()
                    return RunningHost(
                        service: service,
                        endpoint: HudVoxEndpoint(host: "127.0.0.1", port: port),
                        authToken: authToken,
                        runtimePath: runtimeURL.path
                    )
                } catch {
                    service.stop()
                    lastError = error
                }
            }

            throw lastError ?? NSError(
                domain: "LatticesVoiceRuntime",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No local port was available for the embedded voice service."]
            )
        }

        private static func prepareRuntimeHome() throws -> URL {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let url = base
                .appendingPathComponent("Lattices", isDirectory: true)
                .appendingPathComponent("Voice", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        }

        private static func generateCapabilityToken() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            let status = bytes.withUnsafeMutableBytes { buffer in
                SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
            }
            guard status == errSecSuccess else {
                throw NSError(
                    domain: "LatticesVoiceRuntime",
                    code: Int(status),
                    userInfo: [NSLocalizedDescriptionKey: "Could not create a voice runtime capability token."]
                )
            }
            return Data(bytes)
                .base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
    }
    #endif
}
