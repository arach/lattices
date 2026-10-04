import AppKit
import SwiftUI

/// Own the menu and its action targets for the entire AppKit tracking loop.
/// Desktop refreshes may update the SwiftUI view, but never replace this snapshot.
final class OverviewLayerMenu: NSMenu {
    private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func invoke(_ sender: Any?) { run() }
    }
    private var actions: [Action] = []
    init() { super.init(title: "Layer"); autoenablesItems = false }
    required init(coder: NSCoder) { fatalError("Not used") }
    func command(_ title: String, enabled: Bool = true, run: @escaping () -> Void) {
        let action = Action(run)
        actions.append(action)
        let item = NSMenuItem(title: title, action: #selector(Action.invoke(_:)), keyEquivalent: "")
        item.target = action
        item.isEnabled = enabled
        addItem(item)
    }
    static func make(model: OverviewModel, row: OverviewRow) -> OverviewLayerMenu {
        let menu = OverviewLayerMenu()
        let member = model.layers.filter { row.layerIds.contains($0.id) }
        menu.command(member.isEmpty ? "In no layer" : "In " + member.map(\.label).joined(separator: ", "), enabled: false) {}
        let add = NSMenuItem(title: "Add to", action: nil, keyEquivalent: "")
        let submenu = OverviewLayerMenu()
        for layer in model.layers where !row.layerIds.contains(layer.id) {
            submenu.command(layer.label) { model.addComposition([row.wid], to: layer.id) }
        }
        add.submenu = submenu
        menu.addItem(add)
        for layer in member {
            if model.canRemoveComposition(row.wid, from: layer.id) {
                menu.command("Remove from \(layer.label)") { model.removeComposition(row.wid, from: layer.id) }
            } else {
                menu.command("Held by an app or project rule in \(layer.label)", enabled: false) {}
            }
        }
        menu.command("New layer with this window…") { model.compose([row.wid]) }
        if model.editing == nil {
            let scoped = model.scope.layerId.flatMap { id in model.layers.first { $0.id == id } }
            for layer in (scoped.map { [$0] } ?? []) + member.filter({ $0.id != scoped?.id }) {
                menu.command("Edit \(layer.label)…") { model.beginEditing(layer); model.membershipShown = true }
            }
        }
        return menu
    }
}

struct OverviewLayerPicker: NSViewRepresentable {
    let model: OverviewModel
    let row: OverviewRow
    final class Coordinator: NSObject {
        var make: () -> OverviewLayerMenu
        init(make: @escaping () -> OverviewLayerMenu) { self.make = make }
        @objc func open(_ sender: NSButton) {
            let menu = make()
            DiagnosticLog.shared.info("Overview Layer picker: tracking snapshot")
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator { OverviewLayerMenu.make(model: model, row: row) } }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Layer ▾", target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.bezelStyle = .roundRect
        button.font = .systemFont(ofSize: 12, weight: .medium)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.make = { OverviewLayerMenu.make(model: model, row: row) }
    }
}
