import Foundation

public protocol DeckHost: Sendable {
    func manifest() async throws -> DeckManifest
    func runtimeSnapshot() async throws -> DeckRuntimeSnapshot
    func perform(_ request: DeckActionRequest) async throws -> DeckActionResult
}
