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

    private static func hasAppHelper(in root: String) -> Bool {
        FileManager.default.fileExists(atPath: root + "/bin/lattices-app.ts")
    }
}
