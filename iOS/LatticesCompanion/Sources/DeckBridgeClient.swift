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

    func snapshot(endpoint: BridgeEndpoint) async throws -> DeckRuntimeSnapshot {
        try await get(path: "/deck/snapshot", endpoint: endpoint)
    }

    func perform(
        endpoint: BridgeEndpoint,
        request: DeckActionRequest
    ) async throws -> DeckActionResult {
        try await post(path: "/deck/perform", endpoint: endpoint, body: request)
    }

    func trackpad(
        endpoint: BridgeEndpoint,
        request: DeckTrackpadEventRequest
    ) async throws -> DeckTrackpadEventResult {
        try await post(path: "/deck/trackpad", endpoint: endpoint, body: request)
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
