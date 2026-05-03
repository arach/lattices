import Foundation

struct SwitchLayerIntent: LatticeIntent {
    static let name = "switch_layer"
    static let title = "Switch to a workspace layer"

    static let phrases = [
        // Primary: layer
        "layer {layer}",
        // switch to
        "switch to layer {layer}",
        "switch to the {layer} layer",
        "switch to {layer}",
        // go to
        "go to layer {layer}",
        "go to the {layer} layer",
        "go to {layer} layer",
        // activate / change
        "activate layer {layer}",
        "activate the {layer} layer",
        "change to layer {layer}",
        "change layer to {layer}",
        // numbered
        "layer one",
        "layer two",
        "layer three",
        "layer 1",
        "layer 2",
        "layer 3",
        "first layer",
        "second layer",
        "third layer",
        "next layer",
        "previous layer",
    ]

    static let slots = [
        SlotDef(name: "layer", type: .layer, required: true),
    ]

    func perform(slots: [String: JSON]) throws -> JSON {
        guard let layer = slots["layer"]?.stringValue else {
            throw IntentError.missingSlot("layer")
        }
        return try LatticesApi.shared.dispatch(
            method: "layer.switch",
            params: .object(["name": .string(layer)])
        )
    }
}
