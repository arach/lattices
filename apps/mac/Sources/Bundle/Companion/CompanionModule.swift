import Combine
import DeckKit
import SwiftUI

/// The Mac side of the iPad companion: the paired bridge server, the deck
/// host and its `deck.*` endpoints, and the Companion and Deck settings.
final class CompanionModule: BundleModule {
    let id = "companion"

    private var bridgePreference: AnyCancellable?

    func startServices() {
        bridgePreference = Preferences.shared.$companionBridgeEnabled
            .removeDuplicates()
            .sink { enabled in
                if enabled {
                    LatticesCompanionBridgeServer.shared.start()
                } else {
                    LatticesCompanionBridgeServer.shared.stop()
                    DiagnosticLog.shared.info("CompanionBridge: disabled by preference")
                }
            }
    }

    func stop() {
        bridgePreference = nil
        LatticesCompanionBridgeServer.shared.stop()
    }

    func settingsPane(section: String) -> AnyView? {
        switch section {
        case "companion": return AnyView(CompanionSettingsPane())
        case "deck": return AnyView(CompanionDeckPane())
        default: return nil
        }
    }

    func registerEndpoints(_ api: LatticesApi) {
        api.register(Endpoint(
            method: "deck.manifest",
            description: "Get the shared companion deck manifest exposed by the macOS app",
            access: .read,
            params: [],
            returns: .custom("DeckKit manifest for the Lattices companion surface"),
            handler: { _ in
                try Self.encodeDeckValue(LatticesDeckHost.shared.manifestSync())
            }
        ))

        api.register(Endpoint(
            method: "deck.snapshot",
            description: "Get the current companion deck runtime snapshot",
            access: .read,
            params: [],
            returns: .custom("DeckKit runtime snapshot with voice, layout, switcher, and history state"),
            handler: { _ in
                try Self.encodeDeckValue(LatticesDeckHost.shared.runtimeSnapshotSync())
            }
        ))

        api.register(Endpoint(
            method: "deck.perform",
            description: "Perform a companion deck action and return the updated runtime snapshot",
            access: .mutate,
            params: [
                Param(name: "pageID", type: "string", required: false, description: "Deck page ID"),
                Param(name: "actionID", type: "string", required: true, description: "Deck action identifier"),
                Param(name: "payload", type: "object", required: false, description: "Deck action payload"),
            ],
            returns: .custom("DeckKit action result"),
            handler: { params in
                let request = try Self.decodeDeckActionRequest(from: params)
                let result = try LatticesDeckHost.shared.performSync(request)
                return try Self.encodeDeckValue(result)
            }
        ))
    }

    private static func decodeDeckActionRequest(from json: JSON?) throws -> DeckActionRequest {
        guard let json else {
            throw RouterError.missingParam("actionID")
        }
        guard case .object(var object) = json else {
            throw RouterError.custom("Invalid deck action request: params must be an object")
        }
        object["payload"] = object["payload"] ?? .object([:])
        let data = try JSONEncoder().encode(JSON.object(object))
        do {
            return try JSONDecoder().decode(DeckActionRequest.self, from: data)
        } catch {
            throw RouterError.custom("Invalid deck action request: \(error.localizedDescription)")
        }
    }

    private static func encodeDeckValue<T: Encodable>(_ value: T) throws -> JSON {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSON.self, from: data)
    }
}
