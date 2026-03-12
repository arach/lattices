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
            let result = try LatticesApi.shared.dispatch(
                method: "session.launch",
                params: .object(["path": .string(found.path)])
            )
            return result
        }

        // Fallback: try as an app name
        let app = project.prefix(1).uppercased() + project.dropFirst()
        NSWorkspace.shared.launchApplication(app)
        return .object(["ok": .bool(true), "launched": .string(app)])
    }
}
