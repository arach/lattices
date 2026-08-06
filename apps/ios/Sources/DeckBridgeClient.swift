import DeckKit
import Foundation

struct BridgeEndpoint: Identifiable, Hashable {
    let name: String
    let host: String
    let port: Int
    let source: String
    var bridgeFingerprint: String?
    var securityMode: String?
    var capabilities: [String]

    init(
        name: String,
        host: String,
        port: Int,
        source: String,
        bridgeFingerprint: String? = nil,
        securityMode: String? = nil,
        capabilities: [String] = []
    ) {
        self.name = name
        self.host = host
        self.port = port
        self.source = source
        self.bridgeFingerprint = bridgeFingerprint
        self.securityMode = securityMode
        self.capabilities = capabilities
    }

    var id: String {
        "\(host):\(port)"
    }

    /// Carry the Mac's own identity onto this endpoint once `/health` has
    /// reported it.
    ///
    /// A manually-typed endpoint has no Bonjour `fp` record, so without this it
    /// would never match a trust record and would never dedupe against the same
    /// Mac discovered over Bonjour — it would live in the fleet twice, or not
    /// at all.
    func adoptingIdentity(from health: BridgeHealthResponse) -> BridgeEndpoint {
        let reportedName = health.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return BridgeEndpoint(
            name: reportedName.isEmpty ? name : reportedName,
            host: host,
            port: port,
            source: source,
            bridgeFingerprint: health.bridgeFingerprint,
            securityMode: securityMode ?? health.mode,
            capabilities: capabilities.isEmpty ? (health.capabilities ?? []) : capabilities
        )
    }
}

struct BridgeHealthResponse: Codable, Equatable {
    let ok: Bool
    let name: String
    let serviceType: String
    let hostName: String
    let port: UInt16
    let protocolVersion: String?
    let version: String
    let mode: String
    let bridgePublicKey: String
    let bridgeFingerprint: String
    let requestSigningRequired: Bool
    let payloadEncryptionRequired: Bool
    let capabilities: [String]?
}

enum DeckBridgeClientError: LocalizedError {
    case invalidResponse
    case badStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The Mac companion bridge returned an invalid response."
        case .badStatus(let status, let detail):
            return detail.isEmpty ? "Bridge request failed with status \(status)." : detail
        }
    }
}

struct DeckBridgeClient {
    private let security = DeckBridgeSecurityStore.shared
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()

    /// Pairing waits on a person, not on a network.
    ///
    /// It cannot share `session`: `timeoutIntervalForResource` caps the whole
    /// transfer regardless of the request's own timeout, so a 10s resource
    /// limit silently overrode the 90s we thought we were asking for and the
    /// iPad abandoned pairing ten seconds into a human decision — while the Mac
    /// went on to approve and store trust the iPad never received. Both limits
    /// have to be raised, not just one.
    private let pairingSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func health(endpoint: BridgeEndpoint) async throws -> BridgeHealthResponse {
        try await get(path: "/health", endpoint: endpoint)
    }

    func manifest(endpoint: BridgeEndpoint) async throws -> DeckManifest {
        try await get(path: "/deck/manifest", endpoint: endpoint)
    }

    /// Ask the Mac to pair. Returns the Mac's answer — including a refusal.
    ///
    /// A denial is an answer, not a transport failure, so it must not be thrown:
    /// the Mac replies `403` *with* a `DeckPairingResponse` body, and the
    /// generic `send` path threw on the status before ever decoding it, which
    /// made `.denied` unreachable for callers and surfaced refusals as raw JSON.
    func pair(endpoint: BridgeEndpoint) async throws -> DeckPairingResponse {
        var request = URLRequest(url: try makeURL(path: "/pairing/request", endpoint: endpoint))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(security.pairingRequest())

        let (data, response) = try await pairingSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeckBridgeClientError.invalidResponse
        }

        if (200..<300).contains(http.statusCode) || http.statusCode == 403 {
            if let pairing = try? decoder.decode(DeckPairingResponse.self, from: data) {
                return pairing
            }
        }

        let detail = decodeErrorDetail(from: data) ?? String(data: data, encoding: .utf8) ?? ""
        throw DeckBridgeClientError.badStatus(http.statusCode, detail)
    }

    func snapshot(
        endpoint: BridgeEndpoint,
        health: BridgeHealthResponse
    ) async throws -> DeckRuntimeSnapshot {
        try await protectedGet(path: "/deck/snapshot", endpoint: endpoint, health: health)
    }

    func perform(
        endpoint: BridgeEndpoint,
        health: BridgeHealthResponse,
        request: DeckActionRequest
    ) async throws -> DeckActionResult {
        try await protectedPost(path: "/deck/perform", endpoint: endpoint, health: health, body: request)
    }

    func trackpad(
        endpoint: BridgeEndpoint,
        health: BridgeHealthResponse,
        request: DeckTrackpadEventRequest
    ) async throws -> DeckTrackpadEventResult {
        try await protectedPost(path: "/deck/trackpad", endpoint: endpoint, health: health, body: request)
    }

    func desktopPreview(
        endpoint: BridgeEndpoint,
        health: BridgeHealthResponse,
        request: DeckDesktopPreviewRequest
    ) async throws -> DeckDesktopPreviewFrame {
        try await protectedPost(path: "/deck/preview", endpoint: endpoint, health: health, body: request)
    }
}

private extension DeckBridgeClient {
    func get<T: Decodable>(path: String, endpoint: BridgeEndpoint) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path, endpoint: endpoint))
        request.httpMethod = "GET"
        return try await send(request)
    }

    func post<T: Decodable, Body: Encodable>(
        path: String,
        endpoint: BridgeEndpoint,
        body: Body
    ) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path, endpoint: endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await send(request)
    }

    func protectedGet<T: Decodable>(
        path: String,
        endpoint: BridgeEndpoint,
        health: BridgeHealthResponse
    ) async throws -> T {
        let prepared = try security.prepareRequest(
            method: "GET",
            path: path,
            plaintextBody: nil,
            health: health
        )
        var request = URLRequest(url: try makeURL(path: path, endpoint: endpoint))
        request.httpMethod = "GET"
        prepared.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await sendProtected(request, type: T.self, path: path, requestNonce: prepared.requestNonce, health: health)
    }

    func protectedPost<T: Decodable, Body: Encodable>(
        path: String,
        endpoint: BridgeEndpoint,
        health: BridgeHealthResponse,
        body: Body
    ) async throws -> T {
        let plaintext = try encoder.encode(body)
        let prepared = try security.prepareRequest(
            method: "POST",
            path: path,
            plaintextBody: plaintext,
            health: health
        )
        var request = URLRequest(url: try makeURL(path: path, endpoint: endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        prepared.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = prepared.body
        return try await sendProtected(request, type: T.self, path: path, requestNonce: prepared.requestNonce, health: health)
    }

    func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeckBridgeClientError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let detail = decodeErrorDetail(from: data) ?? String(data: data, encoding: .utf8) ?? ""
            throw DeckBridgeClientError.badStatus(http.statusCode, detail)
        }

        return try decoder.decode(T.self, from: data)
    }

    func sendProtected<T: Decodable>(
        _ request: URLRequest,
        type: T.Type,
        path: String,
        requestNonce: String,
        health: BridgeHealthResponse
    ) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeckBridgeClientError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let detail = decodeErrorDetail(from: data) ?? String(data: data, encoding: .utf8) ?? ""
            throw DeckBridgeClientError.badStatus(http.statusCode, detail)
        }

        return try security.openProtectedResponse(
            type,
            data: data,
            status: http.statusCode,
            path: path,
            requestNonce: requestNonce,
            health: health
        )
    }

    func makeURL(path: String, endpoint: BridgeEndpoint) throws -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = path
        guard let url = components.url else {
            throw DeckBridgeClientError.invalidResponse
        }
        return url
    }

    func decodeErrorDetail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // `sendError` writes `error`; the pairing response carries `detail`.
        // Reading only the first turned every refusal into a wall of JSON.
        return (object["error"] as? String) ?? (object["detail"] as? String)
    }
}
