import AppKit

/// Installed-app index backing the command bar's launch results. A shallow scan
/// of the standard Applications folders gives an immediate baseline; a live
/// NSMetadataQuery (Spotlight's system-wide app index) then merges in nested
/// and relocated apps and keeps the index fresh as apps come and go — no
/// restart needed, and no synchronous query on the search keystroke path.
final class AppIndex: NSObject {
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

    /// Keyed by lowercased name for dedup across sources.
    private var entries: [String: Entry] = [:]
    /// Names currently sourced from Spotlight — replaced wholesale on updates.
    private var spotlightNames: Set<String> = []
    private var metadataQuery: NSMetadataQuery?
    private var started = false

    private override init() {
        super.init()
    }

    private var apps: [Entry] {
        startIfNeeded()
        return Array(entries.values)
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        for root in Self.roots { scanFolder(root) }
        startSpotlight()
    }

    // MARK: - Baseline folder scan

    private static let roots = [
        "/Applications",
        "/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    private func scanFolder(_ root: String) {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: root) else { return }
        for item in items { add(root + "/" + item, spotlight: false) }
    }

    private func add(_ path: String, spotlight: Bool) {
        guard path.hasSuffix(".app") else { return }
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        guard !name.isEmpty else { return }
        let key = name.lowercased()
        if entries[key] == nil {
            entries[key] = Entry(name: name, url: URL(fileURLWithPath: path))
        }
        if spotlight { spotlightNames.insert(key) }
    }

    // MARK: - Live Spotlight index

    private func startSpotlight() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemKind == 'Application'")
        NotificationCenter.default.addObserver(
            self, selector: #selector(spotlightResultsChanged(_:)),
            name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(
            self, selector: #selector(spotlightResultsChanged(_:)),
            name: .NSMetadataQueryDidUpdate, object: query)
        query.start()
        metadataQuery = query
    }

    @objc private func spotlightResultsChanged(_ note: Notification) {
        guard let query = note.object as? NSMetadataQuery else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        // Spotlight reports adds/removes/renames through the same note; the
        // result set is small (~hundreds), so rebuild its share of the index.
        for key in spotlightNames { entries.removeValue(forKey: key) }
        spotlightNames.removeAll()
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            add(path, spotlight: true)
        }
    }

    // MARK: - Query

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
