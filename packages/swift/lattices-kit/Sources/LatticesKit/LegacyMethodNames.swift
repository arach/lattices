import Foundation

/// LAT-012 renamed the daemon's methods into domains (`window.place` ->
/// `windows.place`). The daemon still accepts the old names, but a daemon from
/// before the rename does not know the new ones. When one answers
/// `Unknown method:` for a new name, the client retries once with the old name.
enum LegacyMethodNames {
    static let table: [String: String] = [
        "windows.focus": "window.focus",
        "windows.move": "window.move",
        "windows.place": "window.place",
        "windows.present": "window.present",
        "windows.resolve": "window.resolve",
        "windows.pick": "window.pick.start",
        "layers.activate": "layer.activate",
        "layers.switch": "layer.switch",
        "spaces.optimize": "space.optimize",
        "sessions.launch": "session.launch",
        "sessions.kill": "session.kill",
        "sessions.detach": "session.detach",
        "sessions.sync": "session.sync",
        "sessions.restart": "session.restart",
        "groups.launch": "group.launch",
        "groups.kill": "group.kill",
        "tabs.list": "tabStacks.list",
        "tabs.stack": "tabStacks.create",
        "tabs.add": "tabStacks.add",
        "tabs.select": "tabStacks.select",
        "tabs.layout": "tabStacks.layout",
        "tabs.unstack": "tabStacks.delete",
        "search.query": "lattices.search",
        "solo.status": "focus.status",
        "solo.enter": "focus.enter",
        "solo.exit": "focus.exit",
        "solo.toggle": "focus.toggle",
        "intents.run": "intents.execute",
        "history.list": "actions.history",
        "history.undo": "actions.undo",
    ]

    /// The old name to retry `method` under, or nil when there is none.
    static func fallback(for method: String, params: JSONValue?) -> String? {
        var fields: [String: JSONValue] = [:]
        if case .object(let object) = params { fields = object }
        switch method {
        case "tmux.list":
            return fields["includeOrphans"] == .bool(true) ? "tmux.inventory" : "tmux.sessions"
        case "ocr.history":
            return fields["wid"] == nil ? "ocr.recent" : nil
        default:
            return table[method]
        }
    }

    static func isUnknownMethod(_ error: Error, method: String) -> Bool {
        guard case LatticesError.daemonError(let message) = error else { return false }
        return message == "Unknown method: \(method)"
    }
}
