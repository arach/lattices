import Foundation

public enum ActionAgentClientError: LocalizedError {
    case invalidURL
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Unable to create ActionAgent WebSocket URL"
        case .invalidResponse:
            return "ActionAgent returned an invalid response"
        }
    }
}

public final class ActionAgentDispatchHandle: @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    fileprivate init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    public func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }

    deinit {
        close()
    }
}

public actor ActionAgentClient {
    private let host: String
    private let port: UInt16
    private let session: URLSession

    public init(host: String = ActionAgentDefaults.host, port: UInt16 = ActionAgentDefaults.port, session: URLSession = .shared) {
        self.host = host
        self.port = port
        self.session = session
    }

    public func send(method: ActionAgentMethod, params: [String: String] = [:]) async throws -> ActionAgentResponse {
        try await send(request: ActionAgentRequest(method: method.rawValue, params: params))
    }

    public func dispatch(method: ActionAgentMethod, params: [String: String] = [:]) async throws {
        try await dispatch(request: ActionAgentRequest(method: method.rawValue, params: params))
    }

    public func open(method: ActionAgentMethod, params: [String: String] = [:]) async throws -> ActionAgentDispatchHandle {
        try await open(request: ActionAgentRequest(method: method.rawValue, params: params))
    }

    public func send(request: ActionAgentRequest) async throws -> ActionAgentResponse {
        guard let url = URL(string: "ws://\(host):\(port)") else {
            throw ActionAgentClientError.invalidURL
        }

        let task = session.webSocketTask(with: url)
        task.resume()
        defer {
            task.cancel(with: .normalClosure, reason: nil)
        }

        let payload = try JSONEncoder().encode(request)
        guard let text = String(data: payload, encoding: .utf8) else {
            throw ActionAgentClientError.invalidResponse
        }

        try await task.send(.string(text))
        let message = try await task.receive()

        switch message {
        case .string(let string):
            guard let data = string.data(using: .utf8) else {
                throw ActionAgentClientError.invalidResponse
            }
            return try JSONDecoder().decode(ActionAgentResponse.self, from: data)
        case .data(let data):
            return try JSONDecoder().decode(ActionAgentResponse.self, from: data)
        @unknown default:
            throw ActionAgentClientError.invalidResponse
        }
    }

    public func dispatch(request: ActionAgentRequest) async throws {
        let handle = try await open(request: request)
        handle.close()
    }

    public func open(request: ActionAgentRequest) async throws -> ActionAgentDispatchHandle {
        guard let url = URL(string: "ws://\(host):\(port)") else {
            throw ActionAgentClientError.invalidURL
        }

        let task = session.webSocketTask(with: url)
        task.resume()

        let payload = try JSONEncoder().encode(request)
        guard let text = String(data: payload, encoding: .utf8) else {
            throw ActionAgentClientError.invalidResponse
        }

        try await task.send(.string(text))
        return ActionAgentDispatchHandle(task: task)
    }
}
