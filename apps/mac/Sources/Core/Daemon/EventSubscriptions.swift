import Foundation

/// Per-connection event filters (LAT-013 phase 4).
///
/// A client receives every event until it sends `events.subscribe`. The
/// methods act on the connection, so `DaemonServer` answers them itself;
/// `registerSchema` lists them in `api.schema`. Linux hosts running
/// lattices-host implement the same two methods.
enum EventSubscriptions {
    static let subscribe = "events.subscribe"
    static let unsubscribe = "events.unsubscribe"
    static let methods: Set<String> = [subscribe, unsubscribe]

    /// Events the daemon broadcasts, used to expand "all" before an unsubscribe.
    static let known: Set<String> = [
        "windows.changed", "tmux.changed", "layer.switched", "processes.changed",
        "ocr.scanComplete", "voice.command",
    ]

    /// The filter after `method`; nil means every event.
    static func apply(method: String, params: JSON?, to current: Set<String>?) -> Set<String>? {
        let names = eventNames(params)
        switch method {
        case subscribe:
            guard let names, !names.contains("*") else { return nil }
            return Set(names)
        case unsubscribe:
            guard let names else { return [] }
            return (current ?? known).subtracting(names)
        default:
            return current
        }
    }

    static func wants(_ filter: Set<String>?, event: String) -> Bool {
        filter?.contains(event) ?? true
    }

    static func result(_ filter: Set<String>?) -> JSON {
        .object([
            "ok": .bool(true),
            "events": .array((filter.map { $0.sorted() } ?? ["*"]).map { .string($0) }),
        ])
    }

    static func registerSchema(on api: LatticesApi) {
        let unavailable: (JSON?) throws -> JSON = { _ in
            throw RouterError.custom("events.* acts on a WebSocket connection; send it over one")
        }
        api.register(Endpoint(
            method: subscribe,
            description: "Receive only these events on this connection; [\"*\"] for all, the default",
            access: .read,
            params: [Param(name: "events", type: "[string]", required: false, description: "Event names, or [\"*\"]")],
            returns: .custom("Object with ok and the connection's events"),
            handler: unavailable
        ))
        api.register(Endpoint(
            method: unsubscribe,
            description: "Stop receiving these events on this connection; no list stops all",
            access: .read,
            params: [Param(name: "events", type: "[string]", required: false, description: "Event names; omit for all")],
            returns: .custom("Object with ok and the connection's events"),
            handler: unavailable
        ))
    }

    private static func eventNames(_ params: JSON?) -> [String]? {
        guard case .array(let items)? = params?["events"] else { return nil }
        return items.compactMap { $0.stringValue }
    }
}
