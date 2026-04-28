import AppKit
import Combine
import Foundation

@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    @Published private(set) var isUpdating = false
    @Published private(set) var statusMessage: String?

    private init() {}

    var currentVersion: String { LatticesRuntime.appVersion }

    var canUpdate: Bool {
        LatticesRuntime.bunPath != nil && LatticesRuntime.appHelperScriptPath != nil
    }

    var unavailableReason: String? {
        if LatticesRuntime.bunPath == nil {
            return "Install Bun to enable in-app updates."
        }
        if LatticesRuntime.appHelperScriptPath == nil {
            return "Launch Lattices via `lattices app` so the updater can find the CLI bundle."
        }
        return nil
    }

    func promptForUpdate() {
        guard canUpdate else {
            presentAlert(
                title: "Update Unavailable",
                message: unavailableReason ?? "Lattices could not locate its updater."
            )
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Install the latest Lattices app update?"
        alert.informativeText = "Lattices will download the latest released app bundle, close, and relaunch when the update is ready."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        startDetachedUpdate()
    }

    private func startDetachedUpdate() {
        guard !isUpdating else { return }
        guard let bunPath = LatticesRuntime.bunPath,
              let scriptPath = LatticesRuntime.appHelperScriptPath else {
            presentAlert(
                title: "Update Unavailable",
                message: unavailableReason ?? "Lattices could not locate its updater."
            )
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bunPath)
        proc.arguments = [scriptPath, "update", "--detach", "--launch"]
        if let cliRoot = LatticesRuntime.cliRoot {
            proc.currentDirectoryURL = URL(fileURLWithPath: cliRoot)
        }

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        proc.environment = env

        do {
            try proc.run()
            isUpdating = true
            statusMessage = "Updating to the latest release. Lattices will relaunch when it's ready."
        } catch {
            presentAlert(
                title: "Update Failed",
                message: "Lattices could not start the updater.\n\n\(error.localizedDescription)"
            )
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
