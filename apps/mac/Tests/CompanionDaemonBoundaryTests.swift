import Foundation
import XCTest
@testable import Lattices

final class CompanionDaemonBoundaryTests: XCTestCase {
    func testRealLegacySocketRejectsSpeechWithoutCapability() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("fixture-capability".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let server = DaemonServer(port: 0, speechCapabilityURL: file)
        server.start()
        defer { server.stop() }
        XCTAssertGreaterThan(server.listeningPort, 0)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let socket = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(server.listeningPort)")!)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        try await socket.send(.string("{\"id\":\"denied\",\"method\":\"speech.status\"}"))
        let message = try await socket.receive()
        let data: Data
        switch message { case .string(let string): data = Data(string.utf8); case .data(let bytes): data = bytes; @unknown default: fatalError() }
        let response = try JSONDecoder().decode(DaemonResponse.self, from: data)
        XCTAssertEqual(response.id, "denied")
        XCTAssertNotNil(response.error)
        XCTAssertTrue(response.error?.contains("authorization") == true)
    }
}
