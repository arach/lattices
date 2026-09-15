import Foundation
#if SPEECH_FORWARDING_TESTS
@testable import SpeechAppRuntime
#endif

/// Persistent per-caller connection. Socket closure releases that caller's
/// playback reservation, while enqueued jobs remain owned by Speech.
actor SpeechCompanionConnection {
    static let capabilityURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Speech/RPC/capability")
    static let tokenHeader = "x-lattices-speech-token"
    private let endpoint: URL
    private let tokenFile: URL
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiver: Task<Void, Never>?
    private var pending: Set<String> = []
    private let response: (DaemonResponse) -> Void
    private let event: (DaemonEvent) -> Void

    init(endpoint: URL = LatticesLocalEndpoints.speechCompanionURL, tokenFile: URL = SpeechCompanionConnection.capabilityURL, response: @escaping (DaemonResponse) -> Void, event: @escaping (DaemonEvent) -> Void) {
        self.endpoint = endpoint; self.tokenFile = tokenFile
        self.response = response; self.event = event
    }
    nonisolated static func authorizes(handshake: String, tokenFile: URL = capabilityURL) -> Bool {
        guard let expected = try? Data(contentsOf: tokenFile), !expected.isEmpty else { return false }
        var tokens: [String] = []
        for line in handshake.components(separatedBy: "\r\n").dropFirst() {
            if line.isEmpty { break }
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return false }
            let header = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
            if header == "origin" { return false }
            if header == tokenHeader { tokens.append(pair[1].trimmingCharacters(in: .whitespaces)) }
        }
        guard tokens.count == 1 else { return false }
        let supplied = Data(tokens[0].utf8)
        guard supplied.count == expected.count else { return false }
        return zip(supplied, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    func forward(_ request: DaemonRequest) async {
        guard !pending.contains(request.id) else {
            response(DaemonResponse(id: request.id, result: nil, error: "Duplicate in-flight request id")); return
        }
        pending.insert(request.id)
        var sendingConnection: URLSessionWebSocketTask?
        do {
            if socket == nil {
                let token = try String(contentsOf: tokenFile, encoding: .utf8)
                var urlRequest = URLRequest(url: endpoint)
                urlRequest.setValue(token, forHTTPHeaderField: Self.tokenHeader)
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 15
                let session = URLSession(configuration: configuration)
                let connection = session.webSocketTask(with: urlRequest)
                self.session = session; socket = connection
                connection.resume()
                receiver = Task { [weak self, connection] in
                    do {
                        while !Task.isCancelled {
                            let message = try await connection.receive()
                            await self?.receive(message, from: connection)
                        }
                    } catch { await self?.failed(for: connection) }
                }
            }
            let data = try JSONEncoder().encode(request)
            sendingConnection = socket
            try await sendingConnection?.send(.string(String(decoding: data, as: UTF8.self)))
        } catch { failed(for: sendingConnection) }
    }
    private func receive(_ message: URLSessionWebSocketTask.Message, from connection: URLSessionWebSocketTask) {
        guard socket === connection else { return }
        let data: Data
        switch message { case .data(let bytes): data = bytes; case .string(let text): data = Data(text.utf8); @unknown default: return }
        if let result = try? JSONDecoder().decode(DaemonResponse.self, from: data) {
            guard pending.remove(result.id) != nil else { return }
            response(result)
        } else if let update = try? JSONDecoder().decode(DaemonEvent.self, from: data) { event(update) }
    }
    private func failed(for connection: URLSessionWebSocketTask? = nil) {
        if let connection, socket !== connection { return }
        let ids = pending; pending.removeAll()
        close()
        for id in ids { response(DaemonResponse(id: id, result: nil, error: "Speech is unavailable. Open Speech from Apps and retry.")) }
    }
    #if SPEECH_FORWARDING_TESTS
    func testConnection() -> URLSessionWebSocketTask? { socket }
    func testLateFailure(from connection: URLSessionWebSocketTask) { failed(for: connection) }
    #endif
    func close() {
        receiver?.cancel(); receiver = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        pending.removeAll()
    }
}
