import Foundation

enum LatticesRuntime {
    static var cliRoot: String? {
        if let idx = CommandLine.arguments.firstIndex(of: "--lattices-cli-root"),
           CommandLine.arguments.indices.contains(idx + 1) {
            let root = CommandLine.arguments[idx + 1]
            if hasAppHelper(in: root) { return root }
        }

        let bundleDerivedRoot = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        if hasAppHelper(in: bundleDerivedRoot) {
            return bundleDerivedRoot
        }

        let devRoot = NSHomeDirectory() + "/dev/lattices"
        if hasAppHelper(in: devRoot) {
            return devRoot
        }

        return nil
    }

    static var appHelperScriptPath: String? {
        guard let cliRoot else { return nil }
        let path = cliRoot + "/bin/lattices-app.ts"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    static var bunPath: String? {
        let candidates = [
            NSHomeDirectory() + "/.bun/bin/bun",
            "/usr/local/bin/bun",
            "/opt/homebrew/bin/bun",
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }

        let resolved = ProcessQuery.shell(["/bin/zsh", "-lc", "command -v bun 2>/dev/null"])
        if !resolved.isEmpty, FileManager.default.isExecutableFile(atPath: resolved) {
            return resolved
        }

        return nil
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleShortVersionString"] as? String)
            ?? (info?["CFBundleVersion"] as? String)
            ?? "unknown"
    }

    static var appDisplayVersion: String {
        let base = appVersion == "unknown" ? "unknown" : "v\(appVersion)"
        guard isDevBuild else { return base }

        let track = buildTrack ?? "latest"
        return "\(base)-dev.\(track)"
    }

    static var buildChannel: String {
        let raw = Bundle.main.infoDictionary?["LatticesBuildChannel"] as? String
        return raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "release"
    }

    static var buildTrack: String? {
        normalizedInfoValue("LatticesBuildTrack")
    }

    static var buildRevision: String? {
        normalizedInfoValue("LatticesBuildRevision")
    }

    static var buildTimestamp: String? {
        normalizedInfoValue("LatticesBuildTimestamp")
    }

    static var isDevBuild: Bool {
        buildChannel == "dev"
    }

    static var buildStatusLabel: String {
        isDevBuild ? "Latest local dev build" : "Signed release build"
    }

    private static func hasAppHelper(in root: String) -> Bool {
        FileManager.default.fileExists(atPath: root + "/bin/lattices-app.ts")
    }

    private static func normalizedInfoValue(_ key: String) -> String? {
        guard let raw = Bundle.main.infoDictionary?[key] as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value == "unknown" ? nil : value
    }
}
