import AppKit
import Foundation

/// Locates, launches, and installs the Action product (Action.app) —
/// a sibling Lattices product distributed as `Action.dmg` on `action-v*`
/// GitHub releases. Install work is delegated to `lattices action` so the
/// DMG logic lives in one place (bin/lattices-action.ts).
enum ActionProduct {
    static let bundleIdentifier = "dev.lattices.Action"
    static let siteURL = URL(string: "https://lattices.dev/action")!

    static var installedAppURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url
        }
        let applications = URL(fileURLWithPath: "/Applications/Action.app")
        return FileManager.default.fileExists(atPath: applications.path) ? applications : nil
    }

    static var isInstalled: Bool { installedAppURL != nil }

    static func open() {
        guard let url = installedAppURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
    }

    /// Spawn `lattices action install --launch` detached. Returns false when
    /// no usable lattices CLI is available on this machine.
    @discardableResult
    static func install() -> Bool {
        let proc = Process()
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        proc.environment = env

        if let bunPath = LatticesRuntime.bunPath,
           let cliRoot = LatticesRuntime.cliRoot {
            let script = cliRoot + "/bin/lattices.ts"
            if FileManager.default.fileExists(atPath: script) {
                proc.executableURL = URL(fileURLWithPath: bunPath)
                proc.arguments = [script, "action", "install", "--launch"]
            }
        }

        if proc.executableURL == nil, let cli = LatticesRuntime.cliExecutablePath {
            proc.executableURL = URL(fileURLWithPath: cli)
            proc.arguments = ["action", "install", "--launch"]
        }

        guard proc.executableURL != nil else { return false }

        do {
            try proc.run()
            return true
        } catch {
            return false
        }
    }
}
