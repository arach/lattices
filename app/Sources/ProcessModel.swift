import Foundation

final class ProcessModel: ObservableObject {
    static let shared = ProcessModel()

    @Published private(set) var processTable: [Int: ProcessEntry] = [:]
    @Published private(set) var childrenMap: [Int: [Int]] = [:]       // ppid → [child pids]
    @Published private(set) var interesting: [ProcessEntry] = []

    private var timer: DispatchSourceTimer?
    private var lastInterestingPids: Set<Int> = []

    // Terminal tab cache — refreshed lazily when terminals are queried
    private var cachedTerminalTabs: [TerminalTab] = []
    private var lastTabQueryTime: Date = .distantPast
    private static let tabCacheTTL: TimeInterval = 300.0  // 5 minutes

    /// Background queue for process polling — avoids blocking the main thread
    /// with posix_spawn calls (waitUntilExit deadlocks on macOS 26 main run loop).
    private let pollQueue = DispatchQueue(label: "lattice.process-poll", qos: .userInitiated)

    func start(interval: TimeInterval = 5.0) {
        guard timer == nil else { return }
        DiagnosticLog.shared.info("ProcessModel: starting (interval=\(interval)s)")

        let source = DispatchSource.makeTimerSource(queue: pollQueue)
        source.schedule(deadline: .now(), repeating: interval)
        source.setEventHandler { [weak self] in
            self?.poll()
        }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Query Methods

    /// All interesting developer processes with CWDs resolved.
    func interestingProcesses() -> [ProcessEntry] {
        interesting
    }

    /// BFS walk all descendants of a given PID.
    func descendants(of pid: Int) -> [ProcessEntry] {
        var result: [ProcessEntry] = []
        var queue = childrenMap[pid] ?? []
        var visited: Set<Int> = [pid]

        while !queue.isEmpty {
            let childPid = queue.removeFirst()
            guard !visited.contains(childPid) else { continue }
            visited.insert(childPid)
            if let entry = processTable[childPid] {
                result.append(entry)
            }
            if let grandchildren = childrenMap[childPid] {
                queue.append(contentsOf: grandchildren)
            }
        }
        return result
    }

    /// BFS descendants filtered to interesting commands only.
    func interestingDescendants(of pid: Int) -> [ProcessEntry] {
        descendants(of: pid).filter { ProcessQuery.interestingCommands.contains($0.comm) }
    }

    // MARK: - Enrichment

    struct Enrichment {
        let process: ProcessEntry
        let tmuxSession: String?
        let tmuxPaneId: String?
        let windowId: UInt32?
    }

    /// Walk ppid chain from a process upward until we find a tmux pane_pid.
    /// Returns (sessionName, paneId) or nil.
    func tmuxLinkage(for entry: ProcessEntry) -> (session: String, paneId: String)? {
        let paneLookup = buildPaneLookup()
        var current = entry.pid
        // Walk up at most 10 hops (typically 2-3)
        for _ in 0..<10 {
            if let match = paneLookup[current] {
                return match
            }
            guard let parent = processTable[current]?.ppid, parent != current, parent > 1 else {
                break
            }
            current = parent
        }
        return nil
    }

    /// Enrich a single process with tmux + window linkage.
    func enrich(_ entry: ProcessEntry) -> Enrichment {
        if let link = tmuxLinkage(for: entry) {
            let win = DesktopModel.shared.windowForSession(link.session)
            return Enrichment(
                process: entry,
                tmuxSession: link.session,
                tmuxPaneId: link.paneId,
                windowId: win?.wid
            )
        }
        return Enrichment(process: entry, tmuxSession: nil, tmuxPaneId: nil, windowId: nil)
    }

    /// Enrich all interesting processes.
    func enrichedProcesses() -> [Enrichment] {
        interesting.map { enrich($0) }
    }

    // MARK: - Terminal Synthesis (on-demand)

    /// Synthesize terminal instances on demand. Merges the current process table,
    /// tmux sessions, terminal tabs (cached), and window list into a unified view.
    /// Called by API endpoints — no background polling needed.
    func synthesizeTerminals() -> [TerminalInstance] {
        // Refresh tab cache if stale
        let now = Date()
        if now.timeIntervalSince(lastTabQueryTime) >= Self.tabCacheTTL {
            cachedTerminalTabs = TerminalQuery.queryAll()
            lastTabQueryTime = now
        }

        return TerminalSynthesizer.synthesize(
            processTable: processTable,
            interesting: interesting,
            tmuxSessions: TmuxModel.shared.sessions,
            terminalTabs: cachedTerminalTabs,
            windows: DesktopModel.shared.windows
        )
    }

    /// Force-refresh the terminal tab cache (e.g. on first query or explicit refresh).
    func refreshTerminalTabs() {
        cachedTerminalTabs = TerminalQuery.queryAll()
        lastTabQueryTime = Date()
    }

    // MARK: - Polling (runs on pollQueue)

    func poll() {
        // 1. Full process snapshot
        var table = ProcessQuery.snapshot()

        // 2. Build parent → children map
        var children: [Int: [Int]] = [:]
        for (pid, entry) in table {
            children[entry.ppid, default: []].append(pid)
        }

        // 3. Filter interesting, batch-resolve CWDs
        let interestingEntries = ProcessQuery.filterInteresting(table)
        let pids = interestingEntries.map(\.pid)
        let cwds = ProcessQuery.batchCWD(pids: pids)

        // 4. Merge CWDs back into table
        for (pid, cwd) in cwds {
            table[pid]?.cwd = cwd
        }

        let freshInteresting = pids.compactMap { table[$0] }
        let freshPidSet = Set(pids)

        // 5. Detect change
        let changed = freshPidSet != lastInterestingPids

        DispatchQueue.main.async {
            self.processTable = table
            self.childrenMap = children
            self.interesting = freshInteresting
        }

        lastInterestingPids = freshPidSet

        if changed {
            EventBus.shared.post(.processesChanged(interesting: Array(freshPidSet)))
        }
    }

    // MARK: - Private

    /// Build [pane_pid: (sessionName, paneId)] from current TmuxModel state.
    private func buildPaneLookup() -> [Int: (session: String, paneId: String)] {
        var lookup: [Int: (session: String, paneId: String)] = [:]
        for session in TmuxModel.shared.sessions {
            for pane in session.panes {
                lookup[pane.pid] = (session: session.name, paneId: pane.id)
            }
        }
        return lookup
    }
}
