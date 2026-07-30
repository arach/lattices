#if LATTICES_VOICE && canImport(HudsonVoice)
import HudsonVoice
import XCTest
@testable import Lattices

final class LatticesVoiceRuntimeTests: XCTestCase {
    func testEmbeddedRuntimeAcceptsAuthenticatedHealthProbe() async throws {
        LatticesVoiceRuntime.stop()
        LatticesVoiceRuntime.start()
        defer { LatticesVoiceRuntime.stop() }

        let runtime = try XCTUnwrap(
            HudsonVoiceRuntimeResolver.resolve(clientId: "lattices-tests")
        )
        XCTAssertEqual(runtime.source, "lattices-embedded")
        XCTAssertFalse(runtime.options.authToken?.isEmpty ?? true)

        let health = try await HudVoxProbe.health(
            endpoint: runtime.endpoint,
            clientId: runtime.options.clientId,
            authToken: runtime.options.authToken
        )
        XCTAssertEqual(health.service, "Vox")
        XCTAssertEqual(health.port, Int(runtime.endpoint.port))
    }

    func testEmbeddedRuntimeRejectsMissingAndIncorrectTokens() async throws {
        LatticesVoiceRuntime.stop()
        LatticesVoiceRuntime.start()
        defer { LatticesVoiceRuntime.stop() }

        let runtime = try XCTUnwrap(
            HudsonVoiceRuntimeResolver.resolve(clientId: "lattices-tests")
        )

        await assertHealthProbeRejected(endpoint: runtime.endpoint, authToken: nil)
        await assertHealthProbeRejected(endpoint: runtime.endpoint, authToken: "not-the-capability-token")
    }

    func testEmbeddedRuntimeExposesAuthenticatedTTSModels() async throws {
        LatticesVoiceRuntime.stop()
        LatticesVoiceRuntime.start()
        defer { LatticesVoiceRuntime.stop() }

        let runtime = try XCTUnwrap(
            HudsonVoiceRuntimeResolver.resolve(clientId: "lattices-tests")
        )
        let result = try await call(
            endpoint: runtime.endpoint,
            method: "synthesize.models",
            authToken: runtime.options.authToken
        )
        let models = try XCTUnwrap(result["models"] as? [[String: Any]])
        XCTAssertTrue(models.contains { $0["id"] as? String == "avspeech:system" })
    }

    private func assertHealthProbeRejected(
        endpoint: HudVoxEndpoint,
        authToken: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await HudVoxProbe.health(
                endpoint: endpoint,
                clientId: "lattices-tests",
                authToken: authToken
            )
            XCTFail("Expected the runtime to reject an invalid capability token.", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? HudVoxError, .provider("Unauthorized"), file: file, line: line)
        }
    }

    private func call(
        endpoint: HudVoxEndpoint,
        method: String,
        authToken: String?
    ) async throws -> [String: Any] {
        let socket = URLSession.shared.webSocketTask(with: endpoint.url)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        var params: [String: Any] = ["clientId": "lattices-tests"]
        if let authToken {
            params["authToken"] = authToken
        }
        let request: [String: Any] = [
            "id": UUID().uuidString,
            "method": method,
            "params": params,
        ]
        let requestData = try JSONSerialization.data(withJSONObject: request)
        try await socket.send(.data(requestData))

        let response = try await socket.receive()
        let responseData: Data
        switch response {
        case .data(let data):
            responseData = data
        case .string(let text):
            responseData = Data(text.utf8)
        @unknown default:
            throw TestRPCError.invalidResponse
        }
        guard let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw TestRPCError.invalidResponse
        }
        if let message = object["error"] as? String {
            throw TestRPCError.server(message)
        }
        guard let result = object["result"] as? [String: Any] else {
            throw TestRPCError.invalidResponse
        }
        return result
    }

    private enum TestRPCError: Error {
        case invalidResponse
        case server(String)
    }
}
#endif
