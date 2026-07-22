import AppKit
import Foundation

struct LaunchIntent: LatticeIntent {
    static let name = "launch"
    static let title = "Launch a project or app"

    static let phrases = [
        // Primary operator: open
        "open {project}",
        "open up {project}",
        "open my {project}",
        "open the {project}",
        // launch
        "launch {project}",
        "launch the {project}",
        "launch my {project}",
        // start
        "start {project}",
        "start up {project}",
        "start the {project}",
        "start my {project}",
        "start working on {project}",
        // work on
        "work on {project}",
        "work on the {project}",
        "begin {project}",
        "begin working on {project}",
        // fire / spin / boot
        "fire up {project}",
        "spin up {project}",
        "boot up {project}",
        // load / run
        "load {project}",
        "load up {project}",
        "run {project}",
        "run the {project}",
    ]

    static let slots = [
        SlotDef(name: "project", type: .string, required: true),
    ]

    func perform(slots: [String: JSON]) throws -> JSON {
        guard let project = slots["project"]?.stringValue else {
            throw IntentError.missingSlot("project")
        }

        // Try to find the project by scanning known project paths
        let scanner = ProjectScanner.shared
        if let found = scanner.projects.first(where: {
            $0.name.lowercased().contains(project.lowercased())
        }) {
            // Launch via session manager
            DiagnosticLog.shared.info("LaunchIntent: matched scanned project '\(found.name)' at \(found.path)")
            let result = try LatticesApi.shared.dispatch(
                method: "session.launch",
                params: .object(["path": .string(found.path)])
            )
            return result
        }

        // Fallback: try as an app name via the shared app index. Require a
        // strong match (word-prefix or better) so a weak fuzzy hit never
        // launches the wrong app.
        if let match = AppIndex.shared.match(project, limit: 1).first, match.score >= 85 {
            DiagnosticLog.shared.info("LaunchIntent: no scanned project for '\(project)'; launching app '\(match.entry.name)'")
            AppIndex.shared.launch(match.entry)
            return .object(["ok": .bool(true), "launched": .string(match.entry.name)])
        }

        DiagnosticLog.shared.warn("LaunchIntent: no scanned project or launchable app matched '\(project)'")
        return .object([
            "ok": .bool(false),
            "reason": .string("No scanned project or launchable app matched '\(project)'. Try a project from the Lattices list or add a .lattices.json.")
        ])
    }
}
