import CryptoKit
import DeckKit
import Foundation

/// This Mac as a device paired with other hosts' companion bridges, so it can
/// visit them (docs/visit.md). The key is a 0600 file under ~/.lattices/visit,
/// like the bridge's own key, so ad-hoc rebuilds never prompt for the keychain.
final class VisitTrust {
    static let shared = VisitTrust()

    struct Host: Codable, Equatable {
        var name: String
        /// host:port of the bridge.
        var address: String
        /// The side of this Mac's screens the host sits on.
        var side: Side
        var bridgePublicKey: String
        var bridgeFingerprint: String
        var capabilities: [String]
        var pairedAt: Date
    }

    enum Side: String, Codable, CaseIterable {
        case left, right, top, bottom

        /// The host's edge a visitor comes in by.
        var opposite: Side {
            switch self {
            case .left: return .right
            case .right: return .left
            case .top: return .bottom
            case .bottom: return .top
            }
        }
    }

    enum Failure: Error, CustomStringConvertible {
        case unreachable(String)
        case denied(String)
        case noTrackpad
        case bad(String)

        var description: String {
            switch self {
            case .unreachable(let detail): return "Couldn't reach the bridge: \(detail)"
            case .denied(let detail): return "Pairing denied: \(detail)"
            case .noTrackpad: return "The host didn't grant input.trackpad"
            case .bad(let detail): return detail
            }
        }
    }

    private struct Stored: Codable {
        var deviceID: String
        var hosts: [Host]
    }

    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lattices/visit", isDirectory: true)
    private var keyFile: URL { Self.directory.appendingPathComponent("device-key") }
    private var hostsFile: URL { Self.directory.appendingPathComponent("hosts.json") }

    private let lock = NSLock()
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    let deviceID: String
    private var hosts: [Host]

    private init() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let keyFile = Self.directory.appendingPathComponent("device-key")
        if let raw = try? Data(contentsOf: keyFile), let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) {
            privateKey = key
        } else {
            privateKey = Curve25519.KeyAgreement.PrivateKey()
            FileManager.default.createFile(atPath: keyFile.path, contents: privateKey.rawRepresentation, attributes: [.posixPermissions: 0o600])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Self.directory.appendingPathComponent("hosts.json")),
           let stored = try? decoder.decode(Stored.self, from: data) {
            deviceID = stored.deviceID
            hosts = stored.hosts
        } else {
            deviceID = UUID().uuidString.lowercased()
            hosts = []
        }
        persist()
    }

    var publicKeyBase64: String { privateKey.publicKey.rawRepresentation.base64EncodedString() }
    var fingerprint: String { DeckBridgeClientCrypto.fingerprint(publicKeyBase64: publicKeyBase64) }

    func list() -> [Host] {
        lock.lock(); defer { lock.unlock() }
        return hosts
    }

    func host(named name: String) -> Host? {
        list().first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func host(on side: Side) -> Host? {
        list().first { $0.side == side }
    }

    func crypto(for host: Host) throws -> DeckBridgeClientCrypto {
        try DeckBridgeClientCrypto(privateKey: privateKey, deviceID: deviceID, bridgePublicKey: host.bridgePublicKey)
    }

    func forget(_ name: String) -> Bool {
        lock.lock()
        let before = hosts.count
        hosts.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let removed = hosts.count != before
        lock.unlock()
        if removed { persist() }
        return removed
    }

    /// Pairs with a host's bridge. Blocks until someone approves or denies it
    /// on the host (the bridge waits up to two minutes); call off main.
    func pair(name: String, address: String, side: Side) -> Result<Host, Failure> {
        guard let base = URL(string: "http://\(address)") else { return .failure(.bad("Bad address \(address)")) }
        var health = URLRequest(url: base.appendingPathComponent("health"))
        health.timeoutInterval = 4
        guard case .success(let (data, _)) = Self.fetch(health),
              let info = try? JSONDecoder().decode(Health.self, from: data) else {
            return .failure(.unreachable(address))
        }

        let request = DeckPairingRequest(
            deviceID: deviceID,
            deviceName: Host.localName,
            devicePublicKey: publicKeyBase64,
            platform: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            requestedCapabilities: [DeckBridgeCapability.inputTrackpad, DeckBridgeCapability.deckPerform]
        )
        var post = URLRequest(url: base.appendingPathComponent("pairing/request"))
        post.httpMethod = "POST"
        post.timeoutInterval = 150
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.httpBody = try? JSONEncoder().encode(request)
        DiagnosticLog.shared.info("Visit: pairing with \(name) — approve code \(fingerprint) there")
        guard case .success(let (body, _)) = Self.fetch(post) else { return .failure(.unreachable(address)) }
        guard let response = try? JSONDecoder().decode(DeckPairingResponse.self, from: body) else {
            return .failure(.bad(String(decoding: body.prefix(200), as: UTF8.self)))
        }
        guard response.disposition != .denied else { return .failure(.denied(response.detail ?? "")) }
        guard response.bridgePublicKey == info.bridgePublicKey else { return .failure(.bad("The bridge key changed during pairing")) }
        guard response.grantedCapabilities.contains(DeckBridgeCapability.inputTrackpad) else { return .failure(.noTrackpad) }

        let host = Host(
            name: name, address: address, side: side,
            bridgePublicKey: response.bridgePublicKey,
            bridgeFingerprint: response.bridgeFingerprint,
            capabilities: response.grantedCapabilities,
            pairedAt: self.host(named: name)?.pairedAt ?? Date()
        )
        lock.lock()
        hosts.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.side == side }
        hosts.append(host)
        lock.unlock()
        persist()
        DiagnosticLog.shared.success("Visit: paired with \(name) (\(response.bridgeFingerprint)) on the \(side.rawValue)")
        return .success(host)
    }

    private struct Health: Decodable {
        var bridgePublicKey: String
    }

    private func persist() {
        lock.lock()
        let stored = Stored(deviceID: deviceID, hosts: hosts)
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(stored) else { return }
        try? data.write(to: hostsFile, options: .atomic)
    }

    static func fetch(_ request: URLRequest) -> Result<(Data, Int), Error> {
        let done = DispatchSemaphore(value: 0)
        var outcome: Result<(Data, Int), Error> = .failure(URLError(.timedOut))
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { outcome = .failure(error) }
            else { outcome = .success((data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0)) }
            done.signal()
        }.resume()
        done.wait()
        return outcome
    }
}

extension VisitTrust.Host {
    /// How this Mac names itself to the host, e.g. "mini".
    static var localName: String {
        let name = ProcessInfo.processInfo.hostName
        return name.components(separatedBy: ".").first.flatMap { $0.isEmpty ? nil : $0 } ?? Foundation.Host.current().localizedName ?? "mac"
    }
}
