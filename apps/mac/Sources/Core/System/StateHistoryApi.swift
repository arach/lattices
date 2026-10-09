import Foundation

extension StateHistory {
    static func registerEndpoints(_ api: LatticesApi) {
        api.register(Endpoint(
            method: "states.list",
            description: "Recorded desktop maps, newest first: one after each change settles, kept for 72 hours",
            access: .read,
            params: [
                Param(name: "since", type: "string", required: false, description: "Only maps newer than this: seconds, or a duration like 30m, 2h, 1d"),
                Param(name: "limit", type: "int", required: false, description: "At most this many (default 50)"),
                Param(name: "named", type: "bool", required: false, description: "Only maps saved with a name"),
            ],
            returns: .custom("Object with 'states' (id, taken, name, displays, desktops, windows) and 'total'"),
            handler: { params in
                let history = StateHistory.shared
                var ids = history.ids()
                let total = ids.count
                if let since = params?["since"]?.stringValue ?? params?["since"]?.intValue.map(String.init) {
                    guard let seconds = duration(since) else { throw RouterError.custom("since: expected seconds or 30m, 2h, 1d") }
                    let floor = StateMap.id(for: Date().addingTimeInterval(-seconds))
                    ids = ids.filter { String($0.prefix(19)) >= floor }
                }
                if params?["named"]?.boolValue == true { ids = ids.filter { $0.count > 19 } }
                ids = Array(ids.prefix(params?["limit"]?.intValue ?? 50))
                return .object([
                    "total": .int(total),
                    "states": .array(ids.compactMap { id in
                        guard let map = try? history.load(id) else { return nil }
                        return summary(map)
                    }),
                ])
            }
        ))

        api.register(Endpoint(
            method: "states.get",
            description: "One recorded desktop map in full: displays, their desktops, and every window's frame and desktop",
            access: .read,
            params: [Param(name: "id", type: "string", required: false, description: "A map id from states.list (default: the latest)")],
            returns: .custom("StateMap object"),
            handler: { params in
                let history = StateHistory.shared
                let map: StateMap
                if let id = params?["id"]?.stringValue {
                    guard let found = try? history.load(id) else { throw RouterError.notFound("state \(id)") }
                    map = found
                } else {
                    guard let found = try? history.latest() else { throw RouterError.notFound("no states recorded") }
                    map = found
                }
                return try json(map)
            }
        ))

        api.register(Endpoint(
            method: "states.save",
            description: "Record the desktop now under a name, e.g. before a risky change. Named maps are never dropped to make room, only after 72 hours",
            access: .mutate,
            params: [Param(name: "name", type: "string", required: true, description: "A short name")],
            returns: .custom("The new map's summary"),
            handler: { params in
                guard let name = params?["name"]?.stringValue, !name.isEmpty else { throw RouterError.missingParam("name") }
                let map = Thread.isMainThread
                    ? StateHistory.shared.record(name: name)
                    : DispatchQueue.main.sync { StateHistory.shared.record(name: name) }
                guard let map else { throw RouterError.custom("could not record") }
                return summary(map)
            }
        ))
    }

    static func summary(_ map: StateMap) -> JSON {
        .object([
            "id": .string(map.id),
            "taken": .string(ISO8601DateFormatter().string(from: map.taken)),
            "name": map.name.map(JSON.string) ?? .null,
            "displays": .int(map.displays.count),
            "desktops": .int(map.displays.reduce(0) { $0 + $1.desktops.count }),
            "windows": .int(map.windows.count),
        ])
    }

    static func json(_ map: StateMap) throws -> JSON {
        try decoder.decode(JSON.self, from: encoder.encode(map))
    }

    /// "90", "30m", "2h", "1d" → seconds.
    static func duration(_ text: String) -> TimeInterval? {
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard let unit = text.last else { return nil }
        let scale: Double
        switch unit {
        case "s": scale = 1
        case "m": scale = 60
        case "h": scale = 3600
        case "d": scale = 86400
        default: return Double(text)
        }
        return Double(text.dropLast()).map { $0 * scale }
    }
}
