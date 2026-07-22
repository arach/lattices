import AppKit

/// Installed-app index backing the command bar's launch results. Lazily scans
/// the standard Applications folders once, then serves fuzzy name matches;
/// running apps are flagged so callers can activate instead of relaunch.
final class AppIndex {
    static let shared = AppIndex()

    struct Entry {
        let name: String
        let url: URL
    }

    struct Match {
        let entry: Entry
        let score: Int
        let isRunning: Bool
    }

    private var cached: [Entry]?

    private var apps: [Entry] {
        if let cached { return cached }
        let scanned = Self.scan()
        cached = scanned
        return scanned
    }

    private static let roots = [
        "/Applications",
        "/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    private static func scan() -> [Entry] {
        var out: [Entry] = []
        var seen = Set<String>()
        func add(_ path: String) {
            guard path.hasSuffix(".app") else { return }
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { return }
            out.append(Entry(name: name, url: URL(fileURLWithPath: path)))
        }
        let fm = FileManager.default
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items { add(root + "/" + item) }
        }
        // Spotlight is the system-wide app index — it covers nested and
        // relocated apps (Xcode's bundled tools, ~/Applications elsewhere)
        // that the shallow folder scan misses. Skipped silently when
        // indexing is unavailable.
        for path in spotlightApps() { add(path) }
        return out
    }

    private static func spotlightApps() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemKind == 'Application'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        // Drain fully before waiting so a large index can't fill the pipe.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
    }

    func match(_ query: String, limit: Int = 5) -> [Match] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap {
            $0.localizedName?.lowercased()
        })
        return apps
            .compactMap { entry in
                let s = FuzzyScore.score(query: query, candidate: entry.name)
                guard s > 0 else { return nil }
                return Match(entry: entry, score: s, isRunning: running.contains(entry.name.lowercased()))
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    func launch(_ entry: Entry) {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased() == entry.name.lowercased()
        }) {
            running.activate(options: [.activateAllWindows])
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }
}
