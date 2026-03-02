import Foundation

// MARK: - Unified Output

struct TerminalInstance {
    // Join key
    let tty: String

    // Tab info (from AppleScript)
    let app: Terminal?
    let windowIndex: Int?
    let tabIndex: Int?
    let isActiveTab: Bool
    let tabTitle: String?
    let terminalSessionId: String?     // iTerm2 unique ID

    // Process info (from ps)
    let processes: [ProcessEntry]
    let shellPid: Int?
    let cwd: String?

    // Tmux info
    let tmuxSession: String?
    let tmuxPaneId: String?

    // Window info (from CGWindowList)
    let windowId: UInt32?
    let windowTitle: String?

    // Computed
    var hasClaude: Bool {
        processes.contains { $0.comm == "claude" }
    }

    var displayName: String {
        if let session = tmuxSession { return session }
        if let title = tabTitle, !title.isEmpty { return title }
        if let title = windowTitle, !title.isEmpty { return title }
        return tty
    }
}

// MARK: - Synthesizer

enum TerminalSynthesizer {

    /// Pure-function merge: joins 5 slices by TTY into unified TerminalInstances.
    ///
    /// - Parameters:
    ///   - processTable: Full process table from ProcessQuery.snapshot()
    ///   - interesting: Filtered interesting processes
    ///   - tmuxSessions: Current tmux sessions with panes
    ///   - terminalTabs: AppleScript-enumerated tabs
    ///   - windows: CGWindowList entries
    static func synthesize(
        processTable: [Int: ProcessEntry],
        interesting: [ProcessEntry],
        tmuxSessions: [TmuxSession],
        terminalTabs: [TerminalTab],
        windows: [UInt32: WindowEntry]
    ) -> [TerminalInstance] {

        // 1. Single pass: index ALL processes by normalized TTY
        //    This avoids O(TTYs × processes) re-scans later.
        var allProcessesByTTY: [String: [ProcessEntry]] = [:]
        for entry in processTable.values {
            let tty = TerminalQuery.normalizeTTY(entry.tty)
            guard tty != "??" else { continue }
            allProcessesByTTY[tty, default: []].append(entry)
        }

        // 2. Group interesting processes by TTY (subset of above)
        var interestingByTTY: [String: [ProcessEntry]] = [:]
        for entry in interesting {
            let tty = TerminalQuery.normalizeTTY(entry.tty)
            guard tty != "??" else { continue }
            interestingByTTY[tty, default: []].append(entry)
        }

        // 3. Build tmux pane → TTY lookup
        var tmuxByTTY: [String: (session: String, paneId: String)] = [:]
        for session in tmuxSessions {
            for pane in session.panes {
                if let entry = processTable[pane.pid] {
                    let tty = TerminalQuery.normalizeTTY(entry.tty)
                    if tty != "??" {
                        tmuxByTTY[tty] = (session: session.name, paneId: pane.id)
                    }
                }
            }
        }

        // 4. Index terminal tabs by TTY
        var tabByTTY: [String: TerminalTab] = [:]
        for tab in terminalTabs {
            tabByTTY[tab.tty] = tab
        }

        // 5. Collect all known TTYs (union of all maps)
        var allTTYs = Set(interestingByTTY.keys)
        allTTYs.formUnion(tmuxByTTY.keys)
        allTTYs.formUnion(tabByTTY.keys)

        // 6. Build window lookup for positional matching
        let windowsByApp = buildWindowsByApp(windows)

        // 7. For each TTY, merge all slices
        var instances: [TerminalInstance] = []
        for tty in allTTYs {
            let procs = interestingByTTY[tty] ?? []
            let tab = tabByTTY[tty]
            let tmux = tmuxByTTY[tty]

            // Shell PID: process on this TTY whose parent is NOT on this TTY
            let ttyProcs = allProcessesByTTY[tty] ?? []
            let ttyPids = Set(ttyProcs.map(\.pid))
            let shellPid = ttyProcs.first { !ttyPids.contains($0.ppid) }?.pid

            // CWD: deepest interesting process's cwd, or shell's cwd
            let cwd = procs.last(where: { $0.cwd != nil })?.cwd
                ?? (shellPid.flatMap { processTable[$0]?.cwd })

            // Window: try lattices tag match first, then positional
            let windowMatch = resolveWindow(
                tmuxSession: tmux?.session,
                tab: tab,
                windowsByApp: windowsByApp,
                allWindows: windows
            )

            instances.append(TerminalInstance(
                tty: tty,
                app: tab?.app,
                windowIndex: tab?.windowIndex,
                tabIndex: tab?.tabIndex,
                isActiveTab: tab?.isActiveTab ?? false,
                tabTitle: tab?.title,
                terminalSessionId: tab?.sessionId,
                processes: procs,
                shellPid: shellPid,
                cwd: cwd,
                tmuxSession: tmux?.session,
                tmuxPaneId: tmux?.paneId,
                windowId: windowMatch?.wid,
                windowTitle: windowMatch?.title
            ))
        }

        // 7. Sort: Claude first, active tabs first, then by TTY
        instances.sort { a, b in
            if a.hasClaude != b.hasClaude { return a.hasClaude }
            if a.isActiveTab != b.isActiveTab { return a.isActiveTab }
            return a.tty < b.tty
        }

        return instances
    }

    // MARK: - Private Helpers

    /// Group windows by app name for positional matching.
    private static func buildWindowsByApp(_ windows: [UInt32: WindowEntry]) -> [String: [WindowEntry]] {
        var result: [String: [WindowEntry]] = [:]
        for w in windows.values {
            result[w.app, default: []].append(w)
        }
        // Sort each app's windows for consistent positional matching
        for key in result.keys {
            result[key]?.sort { $0.wid < $1.wid }
        }
        return result
    }

    /// Resolve a window for this TTY. Try lattices tag match first, then positional.
    private static func resolveWindow(
        tmuxSession: String?,
        tab: TerminalTab?,
        windowsByApp: [String: [WindowEntry]],
        allWindows: [UInt32: WindowEntry]
    ) -> WindowEntry? {
        // Strategy 1: lattices session tag match
        if let session = tmuxSession {
            let tag = Terminal.windowTag(for: session)
            if let match = allWindows.values.first(where: { $0.title.contains(tag) }) {
                return match
            }
        }

        // Strategy 2: positional match by app + window index
        if let tab = tab {
            let appName = tab.app.rawValue
            if let appWindows = windowsByApp[appName],
               tab.windowIndex < appWindows.count {
                return appWindows[tab.windowIndex]
            }
        }

        return nil
    }
}
