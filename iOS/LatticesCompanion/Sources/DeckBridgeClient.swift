import DeckKit
import Foundation

struct BridgeEndpoint: Identifiable, Hashable {
    let name: String
    let host: String
    let port: Int
    let source: String

    var id: String {
        "\(host):\(port)"
    }
}

struct BridgeHealthResponse: Codable, Equatable {
    let ok: Bool
    let name: String
    let serviceType: String
    let hostName: String
    let port: UInt16
    let version: String
    let mode: String
    let bridgePublicKey: String
    let bridgeFingerprint: String
    let requestSigningRequired: Bool
    let payloadEncryptionRequired: Bool
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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func health(endpoint: BridgeEndpoint) async throws -> BridgeHealthResponse {
        try await get(path: "/health", endpoint: endpoint)
    }

    func manifest(endpoint: BridgeEndpoint) async throws -> DeckManifest {
        try await get(path: "/deck/manifest", endpoint: endpoint)
    }

    func pair(endpoint: BridgeEndpoint) async throws -> DeckPairingResponse {
        var request = URLRequest(url: try makeURL(path: "/pairing/request", endpoint: endpoint))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(security.pairingRequest())
        return try await send(request)
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
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? String
        else {
            return nil
        }
        return error
    }
}
