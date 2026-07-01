import Foundation

public struct LatticesWindows: Sendable {
    let transport: LatticesTransport

    public func list() async throws -> [LatticesWindow] {
        try await decode("windows.list", as: [LatticesWindow].self)
    }

    public func get(wid: Int) async throws -> LatticesWindow {
        try await decode("windows.get", params: jsonObject(("wid", .int(wid))), as: LatticesWindow.self)
    }

    public func search(_ query: String, includeOCR: Bool = true, limit: Int? = nil) async throws -> [LatticesWindow] {
        try await decode(
            "windows.search",
            params: jsonObject(
                ("query", .string(query)),
                ("ocr", .bool(includeOCR)),
                ("limit", limit.map { .int($0) })
            ),
            as: [LatticesWindow].self
        )
    }

    @discardableResult
    public func focus(_ target: LatticesWindowTarget) async throws -> JSONValue {
        try await call("window.focus", params: target.json)
    }

    @discardableResult
    public func focus(wid: Int) async throws -> JSONValue {
        try await focus(.window(wid))
    }

    @discardableResult
    public func focus(session: String) async throws -> JSONValue {
        try await focus(.session(session))
    }

    @discardableResult
    public func tile(session: String, position: LatticesTilePosition) async throws -> JSONValue {
        try await call(
            "window.tile",
            params: jsonObject(
                ("session", .string(session)),
                ("position", .string(position.rawValue))
            )
        )
    }

    @discardableResult
    public func place(
        _ target: LatticesWindowTarget,
        placement: String,
        display: Int? = nil,
        dryRun: Bool? = nil
    ) async throws -> JSONValue {
        var fields = target.jsonFields
        fields["placement"] = .string(placement)
        fields.set("display", display.map { .int($0) })
        fields.set("dryRun", dryRun.map { .bool($0) })
        return try await call("window.place", params: .object(fields))
    }

    @discardableResult
    public func present(
        wid: Int,
        position: LatticesTilePosition? = nil
    ) async throws -> JSONValue {
        try await call(
            "window.present",
            params: jsonObject(
                ("wid", .int(wid)),
                ("position", position.map { .string($0.rawValue) })
            )
        )
    }

    public func resolve(
        _ target: LatticesWindowTarget,
        placement: String? = nil,
        display: Int? = nil
    ) async throws -> JSONValue {
        var fields = target.jsonFields
        fields.set("placement", placement.map { .string($0) })
        fields.set("display", display.map { .int($0) })
        return try await call("window.resolve", params: .object(fields))
    }

    @discardableResult
    public func assignLayer(wid: Int, layer: String) async throws -> JSONValue {
        try await call(
            "window.assignLayer",
            params: jsonObject(("wid", .int(wid)), ("layer", .string(layer)))
        )
    }

    @discardableResult
    public func removeLayer(wid: Int) async throws -> JSONValue {
        try await call("window.removeLayer", params: jsonObject(("wid", .int(wid))))
    }

    public func layerMap() async throws -> JSONValue {
        try await call("window.layerMap")
    }

    private func call(_ method: String, params: JSONValue? = nil, timeout: TimeInterval? = nil) async throws -> JSONValue {
        try await transport.call(method, params: params, timeout: timeout)
    }

    private func decode<T: Decodable>(_ method: String, params: JSONValue? = nil, as type: T.Type) async throws -> T {
        let result = try await call(method, params: params)
        return try result.decoded(as: type)
    }
}

public struct LatticesProjects: Sendable {
    let transport: LatticesTransport

    public func list() async throws -> [LatticesProject] {
        let result = try await transport.call("projects.list", params: nil, timeout: nil)
        return try result.decoded(as: [LatticesProject].self)
    }

    @discardableResult
    public func scan() async throws -> JSONValue {
        try await transport.call("projects.scan", params: nil, timeout: 30)
    }
}

public struct LatticesTmux: Sendable {
    let transport: LatticesTransport

    public func sessions() async throws -> [LatticesTmuxSession] {
        let result = try await transport.call("tmux.sessions", params: nil, timeout: nil)
        return try result.decoded(as: [LatticesTmuxSession].self)
    }

    public func inventory() async throws -> JSONValue {
        try await transport.call("tmux.inventory", params: nil, timeout: nil)
    }
}

public struct LatticesSessions: Sendable {
    let transport: LatticesTransport

    @discardableResult
    public func launch(path: String) async throws -> JSONValue {
        try await transport.call("session.launch", params: jsonObject(("path", .string(path))), timeout: 30)
    }

    @discardableResult
    public func sync(path: String) async throws -> JSONValue {
        try await transport.call("session.sync", params: jsonObject(("path", .string(path))), timeout: 30)
    }

    @discardableResult
    public func restart(path: String, pane: String? = nil) async throws -> JSONValue {
        try await transport.call(
            "session.restart",
            params: jsonObject(("path", .string(path)), ("pane", pane.map { .string($0) })),
            timeout: 30
        )
    }

    @discardableResult
    public func kill(name: String) async throws -> JSONValue {
        try await transport.call("session.kill", params: jsonObject(("name", .string(name))), timeout: 30)
    }

    @discardableResult
    public func detach(name: String) async throws -> JSONValue {
        try await transport.call("session.detach", params: jsonObject(("name", .string(name))), timeout: 30)
    }

    public func layers() async throws -> JSONValue {
        try await transport.call("session.layers.list", params: nil, timeout: nil)
    }

    @discardableResult
    public func switchLayer(index: Int) async throws -> JSONValue {
        try await transport.call("session.layers.switch", params: jsonObject(("index", .int(index))), timeout: 15)
    }

    @discardableResult
    public func switchLayer(name: String) async throws -> JSONValue {
        try await transport.call("session.layers.switch", params: jsonObject(("name", .string(name))), timeout: 15)
    }
}

public struct LatticesAccessibility: Sendable {
    let transport: LatticesTransport

    public func windowState(
        target: LatticesWindowTarget,
        mode: String? = nil,
        capture: Bool? = nil,
        maxDepth: Int? = nil,
        maxElements: Int? = nil
    ) async throws -> JSONValue {
        var fields = target.jsonFields
        fields.set("mode", mode.map { .string($0) })
        fields.set("capture", capture.map { .bool($0) })
        fields.set("maxDepth", maxDepth.map { .int($0) })
        fields.set("maxElements", maxElements.map { .int($0) })
        return try await transport.call("computer.windowState", params: .object(fields), timeout: 30)
    }

    @discardableResult
    public func elementAction(
        snapshotId: String,
        elementId: String,
        action: String = "press",
        treatment: LatticesComputerTreatment? = nil
    ) async throws -> JSONValue {
        try await transport.call(
            "computer.elementAction",
            params: jsonObject(
                ("snapshotId", .string(snapshotId)),
                ("elementId", .string(elementId)),
                ("action", .string(action)),
                ("treatment", treatment.map { .string($0.rawValue) })
            ),
            timeout: 30
        )
    }

    @discardableResult
    public func typeElement(
        snapshotId: String,
        elementId: String,
        text: String,
        append: Bool? = nil,
        treatment: LatticesComputerTreatment? = nil
    ) async throws -> JSONValue {
        try await transport.call(
            "computer.typeElement",
            params: jsonObject(
                ("snapshotId", .string(snapshotId)),
                ("elementId", .string(elementId)),
                ("text", .string(text)),
                ("append", append.map { .bool($0) }),
                ("treatment", treatment.map { .string($0.rawValue) })
            ),
            timeout: 30
        )
    }

    @discardableResult
    public func setValue(
        snapshotId: String,
        elementId: String,
        value: String,
        append: Bool? = nil,
        treatment: LatticesComputerTreatment? = nil
    ) async throws -> JSONValue {
        try await transport.call(
            "computer.setValue",
            params: jsonObject(
                ("snapshotId", .string(snapshotId)),
                ("elementId", .string(elementId)),
                ("value", .string(value)),
                ("append", append.map { .bool($0) }),
                ("treatment", treatment.map { .string($0.rawValue) })
            ),
            timeout: 30
        )
    }

    public func call(_ computerMethod: String, params: JSONValue? = nil, timeout: TimeInterval? = 30) async throws -> JSONValue {
        let method = computerMethod.contains(".") ? computerMethod : "computer.\(computerMethod)"
        return try await transport.call(method, params: params, timeout: timeout)
    }
}

public struct LatticesInput: Sendable {
    let transport: LatticesTransport

    @discardableResult
    public func pressKey(
        _ key: String,
        target: LatticesWindowTarget = LatticesWindowTarget(),
        treatment: LatticesComputerTreatment? = nil,
        allowGlobal: Bool? = nil
    ) async throws -> JSONValue {
        var fields = target.jsonFields
        fields["key"] = .string(key)
        fields.set("treatment", treatment.map { .string($0.rawValue) })
        fields.set("allowGlobal", allowGlobal.map { .bool($0) })
        return try await transport.call("computer.pressKey", params: .object(fields), timeout: 30)
    }

    @discardableResult
    public func hotkey(
        shortcut: String,
        target: LatticesWindowTarget = LatticesWindowTarget(),
        treatment: LatticesComputerTreatment? = nil,
        allowGlobal: Bool? = nil
    ) async throws -> JSONValue {
        var fields = target.jsonFields
        fields["shortcut"] = .string(shortcut)
        fields.set("treatment", treatment.map { .string($0.rawValue) })
        fields.set("allowGlobal", allowGlobal.map { .bool($0) })
        return try await transport.call("computer.hotkey", params: .object(fields), timeout: 30)
    }

    @discardableResult
    public func click(
        target: LatticesWindowTarget,
        xRatio: Double? = nil,
        yRatio: Double? = nil,
        axLabel: String? = nil,
        transport clickTransport: String? = nil,
        treatment: LatticesComputerTreatment? = nil,
        noFocus: Bool? = nil
    ) async throws -> JSONValue {
        var fields = target.jsonFields
        fields.set("xRatio", xRatio.map { .double($0) })
        fields.set("yRatio", yRatio.map { .double($0) })
        fields.set("axLabel", axLabel.map { .string($0) })
        fields.set("transport", clickTransport.map { .string($0) })
        fields.set("treatment", treatment.map { .string($0.rawValue) })
        fields.set("noFocus", noFocus.map { .bool($0) })
        return try await transport.call("computer.click", params: .object(fields), timeout: 30)
    }

    @discardableResult
    public func typeWindowText(
        _ text: String,
        target: LatticesWindowTarget,
        enter: Bool? = nil,
        treatment: LatticesComputerTreatment? = nil
    ) async throws -> JSONValue {
        var fields = target.jsonFields
        fields["text"] = .string(text)
        fields.set("enter", enter.map { .bool($0) })
        fields.set("treatment", treatment.map { .string($0.rawValue) })
        return try await transport.call("computer.typeWindowText", params: .object(fields), timeout: 30)
    }

    @discardableResult
    public func typeText(
        _ text: String,
        wid: Int? = nil,
        tty: String? = nil,
        app: String? = nil,
        enter: Bool? = nil,
        treatment: LatticesComputerTreatment? = nil,
        transport textTransport: String? = nil
    ) async throws -> JSONValue {
        try await transport.call(
            "computer.typeText",
            params: jsonObject(
                ("wid", wid.map { .int($0) }),
                ("tty", tty.map { .string($0) }),
                ("app", app.map { .string($0) }),
                ("text", .string(text)),
                ("enter", enter.map { .bool($0) }),
                ("treatment", treatment.map { .string($0.rawValue) }),
                ("transport", textTransport.map { .string($0) })
            ),
            timeout: 30
        )
    }

    @discardableResult
    public func mouseFind() async throws -> JSONValue {
        try await transport.call("mouse.find", params: nil, timeout: 10)
    }

    @discardableResult
    public func mouseSummon(x: Int? = nil, y: Int? = nil) async throws -> JSONValue {
        try await transport.call(
            "mouse.summon",
            params: jsonObject(("x", x.map { .int($0) }), ("y", y.map { .int($0) })),
            timeout: 10
        )
    }

    public func mouseShortcuts() async throws -> JSONValue {
        try await transport.call("mouse.shortcuts.get", params: nil, timeout: nil)
    }

    @discardableResult
    public func reloadMouseShortcuts() async throws -> JSONValue {
        try await transport.call("mouse.shortcuts.reload", params: nil, timeout: 10)
    }

    public func call(_ method: String, params: JSONValue? = nil, timeout: TimeInterval? = 30) async throws -> JSONValue {
        try await transport.call(method, params: params, timeout: timeout)
    }
}

public struct LatticesLayout: Sendable {
    let transport: LatticesTransport

    @discardableResult
    public func distribute(
        app: String? = nil,
        type: String? = nil,
        region: LatticesTilePosition? = nil
    ) async throws -> JSONValue {
        try await transport.call(
            "layout.distribute",
            params: jsonObject(
                ("app", app.map { .string($0) }),
                ("type", type.map { .string($0) }),
                ("region", region.map { .string($0.rawValue) })
            ),
            timeout: 30
        )
    }

    @discardableResult
    public func optimize(params: JSONValue? = nil) async throws -> JSONValue {
        try await transport.call("space.optimize", params: params, timeout: 30)
    }
}
