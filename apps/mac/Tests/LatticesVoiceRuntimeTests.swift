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
}
#endif
