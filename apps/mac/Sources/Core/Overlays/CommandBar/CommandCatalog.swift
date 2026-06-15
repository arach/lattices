import Foundation

/// Who a command acts on. The bar captured the frontmost window on open;
/// `.currentWindow` commands inject that wid, `.target` commands need a typed
/// target (app/session/project/query/layer), `.global` commands need neither.
enum CommandSubject {
    case currentWindow
    case target
    case global
}

/// Bar-specific UX hints layered over an engine intent. The command *set* comes
/// from `IntentEngine.shared.definitions()`; this only adds typing niceties.
struct CommandHint {
    let aliases: [String]
    let icon: String
    let subject: CommandSubject
    /// The slot filled from the argument the user types after the verb.
    let primarySlot: String?
}

/// An engine intent presented as a typeable command.
struct BarCommand: Identifiable {
    let def: IntentDef
    let hint: CommandHint

    var id: String { def.name }
    var name: String { def.name }
    var title: String { CommandCatalog.title(for: def.name) }
    var description: String { def.description }
    var icon: String { hint.icon }
    var subject: CommandSubject { hint.subject }

    /// Lowercased tokens used to match what the user types.
    var keywords: [String] {
        ([name, title] + hint.aliases).map { $0.lowercased() }
    }

    /// Required slots that must be filled before the command can run.
    var requiredSlots: [IntentSlot] { def.slots.filter(\.required) }

    /// True when the command needs an argument before it can execute.
    var needsArgument: Bool {
        !requiredSlots.isEmpty || (subject == .target && hint.primarySlot != nil)
    }

    /// The slot the bar fills from typed input.
    var activeSlot: IntentSlot? {
        if let p = hint.primarySlot, let s = def.slots.first(where: { $0.name == p }) { return s }
        return requiredSlots.first ?? def.slots.first
    }
}

enum CommandCatalog {
    /// Per-intent hints. Intents absent here still appear with derived defaults.
    private static let hints: [String: CommandHint] = [
        "tile_window":     .init(aliases: ["tile", "place", "move", "snap", "put"], icon: "rectangle.righthalf.inset.filled", subject: .currentWindow, primarySlot: "position"),
        "move_to_display": .init(aliases: ["display", "screen", "monitor"],          icon: "display.2",                        subject: .currentWindow, primarySlot: "display"),
        "hide":            .init(aliases: ["hide", "minimize"],                       icon: "eye.slash",                        subject: .currentWindow, primarySlot: nil),
        "highlight":       .init(aliases: ["highlight", "flash"],                     icon: "sparkles",                         subject: .currentWindow, primarySlot: nil),
        "kill":            .init(aliases: ["close", "kill", "quit"],                  icon: "xmark.circle",                     subject: .currentWindow, primarySlot: nil),
        "focus":           .init(aliases: ["focus", "go", "show"],                    icon: "scope",                            subject: .target,        primarySlot: "app"),
        "launch":          .init(aliases: ["launch", "open", "start"],                icon: "play.circle",                      subject: .target,        primarySlot: "project"),
        "switch_layer":    .init(aliases: ["layer"],                                  icon: "square.stack.3d.up",               subject: .target,        primarySlot: "layer"),
        "search":          .init(aliases: ["search"],                                 icon: "magnifyingglass",                  subject: .target,        primarySlot: "query"),
        "distribute":      .init(aliases: ["distribute", "arrange"],                  icon: "rectangle.split.2x2",              subject: .target,        primarySlot: "region"),
        "undo":            .init(aliases: ["undo", "revert"],                         icon: "arrow.uturn.backward",             subject: .global,        primarySlot: nil),
        "scan":            .init(aliases: ["scan", "ocr"],                            icon: "doc.text.viewfinder",              subject: .global,        primarySlot: nil),
        "find_mouse":      .init(aliases: ["find mouse"],                             icon: "cursorarrow.rays",                 subject: .global,        primarySlot: nil),
        "summon_mouse":    .init(aliases: ["summon mouse"],                           icon: "cursorarrow.motionlines",          subject: .global,        primarySlot: nil),
    ]

    private static let defaultHint = CommandHint(aliases: [], icon: "command", subject: .global, primarySlot: nil)

    /// Curated, grouped commands for the empty command menu. Friendly verbs only
    /// — destructive ones (kill) stay typeable but unfeatured.
    static let featuredGroups: [(section: String, names: [String])] = [
        ("Window", ["move_to_display", "distribute", "hide"]),
        ("Workspace", ["focus", "launch", "switch_layer", "undo"]),
    ]

    static func all() -> [BarCommand] {
        IntentEngine.shared.definitions().map { BarCommand(def: $0, hint: hints[$0.name] ?? defaultHint) }
    }

    /// "move_to_display" → "Move To Display"
    static func title(for name: String) -> String {
        name.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
}
