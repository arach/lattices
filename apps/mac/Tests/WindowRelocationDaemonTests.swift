import Foundation
import XCTest
@testable import Lattices

/// Isolated ephemeral-port servers with fake handlers: never the installed
/// daemon, AX, Mission Control, or real windows.
final class WindowRelocationDaemonTests: XCTestCase {
    private func connect(_ server: DaemonServer, session: URLSession) -> URLSessionWebSocketTask {
        let url = URL(string: "ws://127.0.0.1:\(server.listeningPort)")!
        let socket = session.webSocketTask(with: url)
        socket.resume()
        return socket
    }

    private func response(_ socket: URLSessionWebSocketTask) async throws -> DaemonResponse {
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .string(let value): data = Data(value.utf8)
        case .data(let value): data = value
        @unknown default: throw NSError(domain: "fixture", code: 1)
        }
        return try JSONDecoder().decode(DaemonResponse.self, from: data)
    }

    func testBlockingRelocationMethodsDoNotBlockSocketAndPreserveErrors() async throws {
        for method in ["window.move", "window.place", "actions.execute", "actions.undo"] {
            let entered = expectation(description: "\(method) entered")
            let server = DaemonServer(port: 0, requestHandler: { request in
                if request.method == method {
                    XCTAssertFalse(Thread.isMainThread)
                    entered.fulfill()
                    Thread.sleep(forTimeInterval: 0.35)
                    return DaemonResponse(id: request.id, result: nil, error: "Fixture relocation refused; original position restored")
                }
                return DaemonResponse(id: request.id, result: .string("responsive"), error: nil)
            })
            server.start()
            defer { server.stop() }
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let socket = connect(server, session: session)
            defer { socket.cancel(with: .normalClosure, reason: nil) }
            try await socket.send(.string("{\"id\":\"slow\",\"method\":\"\(method)\"}"))
            await fulfillment(of: [entered], timeout: 2)
            try await socket.send(.string("{\"id\":\"fast\",\"method\":\"fixture.ping\"}"))
            let fast = try await response(socket)
            XCTAssertEqual(fast.id, "fast", "\(method) must not block the socket queue")
            let failed = try await response(socket)
            XCTAssertEqual(failed.id, "slow")
            XCTAssertEqual(failed.error, "Fixture relocation refused; original position restored")
        }
    }

    func testDisconnectedSlowClientDoesNotBreakAnotherClient() async throws {
        let entered = expectation(description: "slow handler")
        let finished = expectation(description: "slow handler completes without a client")
        let server = DaemonServer(port: 0, requestHandler: { request in
            if request.method == "window.move" {
                entered.fulfill()
                Thread.sleep(forTimeInterval: 0.25)
                finished.fulfill()
            }
            return DaemonResponse(id: request.id, result: .string("ok"), error: nil)
        })
        server.start()
        defer { server.stop() }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let abandoned = connect(server, session: session)
        try await abandoned.send(.string("{\"id\":\"abandoned\",\"method\":\"window.move\"}"))
        await fulfillment(of: [entered], timeout: 2)
        abandoned.cancel(with: .goingAway, reason: nil)
        let next = connect(server, session: session)
        defer { next.cancel(with: .normalClosure, reason: nil) }
        try await next.send(.string("{\"id\":\"new\",\"method\":\"fixture.ping\"}"))
        let reply = try await response(next)
        XCTAssertEqual(reply.id, "new")
        await fulfillment(of: [finished], timeout: 2)
    }

    func testRealMoveHandlerReturnsParameterErrorWithoutWindowAccess() async throws {
        await MainActor.run { LatticesApi.setup() }
        let server = DaemonServer(port: 0)
        server.start()
        defer { server.stop() }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let socket = connect(server, session: session)
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        try await socket.send(.string("{\"id\":\"bad\",\"method\":\"window.move\",\"params\":{}}"))
        let reply = try await response(socket)
        XCTAssertEqual(reply.id, "bad")
        XCTAssertTrue(reply.error?.contains("wid or session") == true, reply.error ?? "missing error")
        XCTAssertNil(reply.result)
    }
}
