import Foundation

struct CreateLayerIntent: LatticeIntent {
    static let name = "create_layer"
    static let title = "Save the current layout as a named layer"

    static let phrases = [
        // create
        "create a layer called {name}",
        "create layer called {name}",
        "create a layer {name}",
        "create layer {name}",
        "create new layer {name}",
        // make
        "make a layer called {name}",
        "make layer called {name}",
        "make a layer {name}",
        "make layer {name}",
        "make a new layer {name}",
        // save
        "save this layout as {name}",
        "save layout as {name}",
        "save as layer {name}",
        "save as {name}",
        // name / snapshot
        "name this layer {name}",
        "new layer called {name}",
        "new layer {name}",
        // No-arg variants
        "create a layer",
        "create layer",
        "save this layout",
        "save layout",
        "snapshot",
        "snapshot this",
        "remember this layout",
        "save this workspace",
    ]

    static let slots = [
        SlotDef(name: "name", type: .string, required: false),
    ]

    func perform(slots: [String: JSON]) throws -> JSON {
        var params: [String: JSON] = [:]
        if let name = slots["name"]?.stringValue {
            params["name"] = .string(name)
        }
        return try LatticesApi.shared.dispatch(
            method: "layer.create",
            params: .object(params)
        )
    }
}
