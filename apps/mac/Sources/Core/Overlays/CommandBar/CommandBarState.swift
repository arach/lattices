import AppKit
import Combine
import Foundation

/// What committing a suggestion does.
enum CommandAction {
    case placeCurrent(PlacementSpec)                                   // tile captured window
    case runCommand(intent: String, slots: [String: JSON], subject: CommandSubject)
    case fillCommand(BarCommand)                                       // drill into a command's args
    case setQuery(String)                                              // advance the query (e.g. pick a display)
}

/// One row in the bar's suggestion list.
struct CommandSuggestion: Identifiable {
    let id = UUID()
    let label: String
    let detail: String
    let glyph: String
    let action: CommandAction
    var previewSpec: PlacementSpec?    // drives the ghost when this row is highlighted
    var previewScreen: NSScreen? = nil // screen the ghost draws on (defaults to the captured one)
    var section: String? = nil          // optional grouping header shown in the empty menu

    var isFill: Bool {
        switch action {
        case .fillCommand, .setQuery: return true
        default: return false
        }
    }
}

/// Drives the command bar: parses the query into either a command stage (pick a
/// verb) or an argument stage (fill the active command's next slot), producing
/// type-aware suggestions sourced from the engine's self-describing intents.
final class CommandBarState: ObservableObject {
    @Published var query: String = ""
    @Published var suggestions: [CommandSuggestion] = []
    @Published var selectedIndex: Int = 0
    /// Title of the command being filled (nil in the command-picking stage).
    @Published var contextLabel: String? = nil

    private let commands = CommandCatalog.all()
    private var cancellables = Set<AnyCancellable>()

    var selected: CommandSuggestion? {
        guard selectedIndex >= 0, selectedIndex < suggestions.count else { return nil }
        return suggestions[selectedIndex]
    }

    /// The post-"/" text that fully types out a suggestion (drives ⇥ completion).
    /// A bare command → its verb; a chosen slot value → "<verb> <value>"; a
    /// placement → its wire value. (Never the human description — that's the bug
    /// where "li" + ⇥ became "li List all visible windows".)
    func completion(for s: CommandSuggestion) -> String {
        func verb(_ intentName: String) -> String {
            guard let cmd = commands.first(where: { $0.name == intentName }) else { return intentName }
            return cmd.hint.aliases.first ?? cmd.keywords.first ?? cmd.name
        }
        switch s.action {
        case .fillCommand(let c):     return (c.hint.aliases.first ?? c.name) + " "
        case .setQuery(let q):        return q
        case .placeCurrent(let spec): return spec.wireValue
        case .runCommand(let intent, let slots, _):
            let v = verb(intent)
            return slots.isEmpty ? v : v + " " + s.detail
        }
    }

    /// Destination spec for the highlighted row, if it places a window.
    var previewSpec: PlacementSpec? { selected?.previewSpec }

    /// Screen the ghost should draw on for the highlighted row.
    var previewScreen: NSScreen? { selected?.previewScreen }

    private static let commonPositions: [TilePosition] = [
        .left, .right, .top, .bottom,
        .topLeft, .topRight, .bottomLeft, .bottomRight,
        .leftThird, .centerThird, .rightThird,
        .maximize, .center,
    ]

    /// A tight set shown under "Place" in the empty command menu.
    private static let menuPositions: [TilePosition] = [.left, .right, .top, .bottom, .maximize, .center]

    init() {
        rebuild(for: "")
        $query
            .removeDuplicates()
            .sink { [weak self] q in self?.rebuild(for: q) }
            .store(in: &cancellables)
    }

    // MARK: - Navigation / drill-in

    func moveSelection(_ delta: Int) {
        guard !suggestions.isEmpty else { return }
        if selectedIndex < 0 {                       // first move out of the neutral state
            selectedIndex = delta > 0 ? 0 : suggestions.count - 1
            return
        }
        selectedIndex = max(0, min(suggestions.count - 1, selectedIndex + delta))
    }

    /// Insert a command's verb and advance to its argument stage.
    func beginCommand(_ cmd: BarCommand) {
        query = (cmd.hint.aliases.first ?? cmd.name) + " "
    }

    // MARK: - Parse → suggestions

    private func rebuild(for raw: String) {
        let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let (cmd, arg) = resolveCommand(q) {
            contextLabel = cmd.title
            suggestions = stageArguments(cmd, arg: arg)
        } else {
            contextLabel = nil
            suggestions = stageCommands(prefix: q)
        }
        // Open as a neutral command bar: nothing selected (and no ghost) until
        // the user types or arrows down. Typed queries select the first match.
        selectedIndex = (q.isEmpty || suggestions.isEmpty) ? -1 : 0
    }

    /// Resolve a leading verb (longest alias wins); returns the remaining argument.
    private func resolveCommand(_ q: String) -> (BarCommand, String)? {
        guard !q.isEmpty else { return nil }
        var best: (cmd: BarCommand, arg: String, len: Int)?
        for cmd in commands {
            for alias in cmd.keywords {
                if q == alias {
                    if best == nil || alias.count > best!.len { best = (cmd, "", alias.count) }
                } else if q.hasPrefix(alias + " ") {
                    let arg = String(q.dropFirst(alias.count + 1)).trimmingCharacters(in: .whitespaces)
                    if best == nil || alias.count > best!.len { best = (cmd, arg, alias.count) }
                }
            }
        }
        return best.map { ($0.cmd, $0.arg) }
    }

    // MARK: Stage 1 — pick a command (bare positions still mean "tile")

    private func stageCommands(prefix: String) -> [CommandSuggestion] {
        var out: [CommandSuggestion] = []
        var seen = Set<String>()

        func addPlacement(_ spec: PlacementSpec, _ label: String, _ glyph: String, section: String? = nil) {
            guard seen.insert("p:" + spec.wireValue).inserted else { return }
            out.append(.init(label: label, detail: spec.wireValue, glyph: glyph,
                             action: .placeCurrent(spec), previewSpec: spec, section: section))
        }
        func addCommand(_ cmd: BarCommand, section: String? = nil) {
            guard seen.insert("c:" + cmd.name).inserted else { return }
            let action: CommandAction = cmd.needsArgument
                ? .fillCommand(cmd)
                : .runCommand(intent: cmd.name, slots: [:], subject: cmd.subject)
            out.append(.init(label: cmd.title, detail: cmd.description, glyph: cmd.icon,
                             action: action, previewSpec: nil, section: section))
        }

        if prefix.isEmpty {
            // A curated starter menu on "/": common placements, then a few key
            // verbs by section. Typing filters the full catalog.
            for p in Self.menuPositions { addPlacement(.tile(p), p.label, p.arrowGlyph, section: "Place") }
            for group in CommandCatalog.featuredGroups {
                for name in group.names {
                    if let cmd = commands.first(where: { $0.name == name }) {
                        addCommand(cmd, section: group.section)
                    }
                }
            }
            return out
        }

        // Placement is the bar's primary job, so positions rank above commands
        // when a fragment matches both (e.g. "r" → Right before Search).
        if let spec = PlacementSpec(string: prefix) {
            addPlacement(spec, placementLabel(spec, fallback: prefix), "scope")
        }
        for p in TilePosition.allCases where positionMatches(p, prefix) {
            addPlacement(.tile(p), p.label, p.arrowGlyph)
        }
        for cmd in commands where commandMatches(cmd, prefix) { addCommand(cmd) }
        return out
    }

    // MARK: Stage 2 — fill the active command's slot

    private func stageArguments(_ cmd: BarCommand, arg: String) -> [CommandSuggestion] {
        // Two-step: pick a display, then a position previewed on that display
        // (a position is what actually relocates the window via window.present).
        if cmd.name == "move_to_display" {
            return moveToDisplaySuggestions(arg: arg)
        }
        guard let slot = cmd.activeSlot else {
            return [.init(label: "Run \(cmd.title)", detail: cmd.description, glyph: cmd.icon,
                          action: .runCommand(intent: cmd.name, slots: [:], subject: cmd.subject),
                          previewSpec: nil)]
        }
        return slotValues(slot, filter: arg).map { v in
            CommandSuggestion(label: v.label, detail: v.detail, glyph: v.glyph,
                              action: .runCommand(intent: cmd.name, slots: [slot.name: v.value], subject: cmd.subject),
                              previewSpec: v.spec)
        }
    }

    /// Step 1 lists displays (0-indexed value, 1-based label); choosing one
    /// advances the query to step 2, which lists positions on that display.
    private func moveToDisplaySuggestions(arg: String) -> [CommandSuggestion] {
        let screens = NSScreen.screens
        let tokens = arg.split(separator: " ", maxSplits: 1).map(String.init)

        if let first = tokens.first, let human = Int(first), human >= 1, human <= screens.count {
            let idx = human - 1
            let posFilter = tokens.count > 1 ? tokens[1] : ""
            return placementsForMove(displayIndex: idx, screen: screens[idx], filter: posFilter)
        }

        return screens.enumerated().map { i, screen in
            CommandSuggestion(
                label: "Display \(i + 1)" + (i == 0 ? " · Main" : ""),
                detail: "\(Int(screen.frame.width))×\(Int(screen.frame.height))",
                glyph: "display",
                action: .setQuery("display \(i + 1) "),
                previewSpec: nil,
                previewScreen: nil
            )
        }
    }

    private func placementsForMove(displayIndex idx: Int, screen: NSScreen, filter: String) -> [CommandSuggestion] {
        let f = filter.lowercased()
        var out: [CommandSuggestion] = []
        var seen = Set<String>()
        func add(_ spec: PlacementSpec, _ label: String, _ glyph: String) {
            guard seen.insert(spec.wireValue).inserted else { return }
            out.append(.init(label: label, detail: spec.wireValue, glyph: glyph,
                             action: .runCommand(intent: "move_to_display",
                                                 slots: ["display": .int(idx), "position": .string(spec.wireValue)],
                                                 subject: .currentWindow),
                             previewSpec: spec, previewScreen: screen))
        }
        if let spec = PlacementSpec(string: f), !f.isEmpty { add(spec, placementLabel(spec, fallback: f), "scope") }
        let positions = f.isEmpty ? Self.commonPositions : TilePosition.allCases.filter { positionMatches($0, f) }
        for p in positions { add(.tile(p), p.label, p.arrowGlyph) }
        return out
    }

    private struct SlotValue {
        let label: String, detail: String, glyph: String
        let value: JSON
        let spec: PlacementSpec?
    }

    private func slotValues(_ slot: IntentSlot, filter raw: String) -> [SlotValue] {
        let f = raw.lowercased()

        if let vals = slot.enumValues, !vals.isEmpty {
            return vals.filter { f.isEmpty || $0.lowercased().contains(f) }
                .map { val in
                    // Placement enums read as direction arrows (with a ghost preview);
                    // anything else keeps a neutral dot.
                    if let pos = TilePosition(rawValue: val) {
                        return SlotValue(label: pos.label, detail: val, glyph: pos.arrowGlyph,
                                         value: .string(val), spec: .tile(pos))
                    }
                    return SlotValue(label: val.capitalized, detail: val, glyph: "circle",
                                     value: .string(val), spec: nil)
                }
        }

        switch slot.type {
        case "position":
            var out: [SlotValue] = []
            var seen = Set<String>()
            if let spec = PlacementSpec(string: f), !f.isEmpty {
                seen.insert(spec.wireValue)
                out.append(SlotValue(label: placementLabel(spec, fallback: f), detail: spec.wireValue,
                                     glyph: "scope", value: .string(spec.wireValue), spec: spec))
            }
            let positions = f.isEmpty ? Self.commonPositions : TilePosition.allCases.filter { positionMatches($0, f) }
            for p in positions where seen.insert(p.rawValue).inserted {
                out.append(SlotValue(label: p.label, detail: p.rawValue, glyph: p.arrowGlyph,
                                     value: .string(p.rawValue), spec: .tile(p)))
            }
            return out

        case "int":
            // move_to_display's "display" slot is handled by moveToDisplaySuggestions.
            guard let n = Int(f) else { return [] }
            return [SlotValue(label: "\(n)", detail: slot.name, glyph: "number", value: .int(n), spec: nil)]

        case "app":
            let apps = Set(DesktopModel.shared.allWindows().map(\.app)).sorted()
            return apps.filter { f.isEmpty || $0.lowercased().contains(f) }
                .map { SlotValue(label: $0, detail: "app", glyph: "macwindow", value: .string($0), spec: nil) }

        case "session":
            return TmuxModel.shared.sessions.map(\.name)
                .filter { f.isEmpty || $0.lowercased().contains(f) }
                .map { SlotValue(label: $0, detail: "session", glyph: "terminal", value: .string($0), spec: nil) }

        default:
            if slot.name == "project" {
                return ProjectScanner.shared.projects.map(\.name)
                    .filter { f.isEmpty || $0.lowercased().contains(f) }
                    .map { SlotValue(label: $0, detail: "project", glyph: "folder", value: .string($0), spec: nil) }
            }
            // query / layer / freeform string — echo what's typed.
            guard !raw.isEmpty else { return [] }
            return [SlotValue(label: raw, detail: slot.name, glyph: "text.cursor", value: .string(raw), spec: nil)]
        }
    }

    // MARK: - Matching helpers

    private func commandMatches(_ cmd: BarCommand, _ prefix: String) -> Bool {
        cmd.keywords.contains { $0.hasPrefix(prefix) || $0.contains(prefix) }
    }

    private func positionMatches(_ p: TilePosition, _ q: String) -> Bool {
        p.rawValue.contains(q)
            || p.rawValue.replacingOccurrences(of: "-", with: " ").contains(q)
            || p.label.lowercased().contains(q)
    }

    private func placementLabel(_ spec: PlacementSpec, fallback: String) -> String {
        if case .tile(let p) = spec { return p.label }
        return fallback
    }
}
