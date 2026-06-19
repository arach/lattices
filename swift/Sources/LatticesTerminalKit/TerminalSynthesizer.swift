import Foundation

public enum TerminalSynthesizer {
    public static func synthesize(
        processTable: [Int: ProcessEntry],
        interesting: [ProcessEntry],
        tmuxSessions: [TmuxSession],
        terminalTabs: [TerminalTab],
        terminalWindows: [TerminalWindow],
        paneCaptureByPaneId: [String: TerminalPaneCapture] = [:],
        observedAt: Date = Date()
    ) -> [TerminalInstance] {
        let allProcessesByTTY = groupProcessesByTTY(Array(processTable.values))
        let interestingByTTY = groupProcessesByTTY(interesting)
        let tmuxByTTY = buildTmuxLookup(processTable: processTable, tmuxSessions: tmuxSessions)
        let tabByTTY = Dictionary(uniqueKeysWithValues: terminalTabs.map { ($0.tty, $0) })
        let windowsByApp = buildWindowsByApp(terminalWindows)
        let windowsByTTY = buildWindowsByTTY(processTable: processTable, terminalWindows: terminalWindows)

        var allTTYs = Set(interestingByTTY.keys)
        allTTYs.formUnion(tmuxByTTY.keys)
        allTTYs.formUnion(tabByTTY.keys)
        allTTYs.formUnion(windowsByTTY.keys)

        var instances: [TerminalInstance] = []
        for tty in allTTYs.sorted() {
            let procs = interestingByTTY[tty] ?? []
            let ttyProcs = allProcessesByTTY[tty] ?? []
            let ttyPids = Set(ttyProcs.map(\.pid))
            let shellPid = ttyProcs.first { !ttyPids.contains($0.ppid) }?.pid
            let cwdEntry = procs.last(where: { $0.cwd != nil })
            let shellCwd = shellPid.flatMap { processTable[$0]?.cwd }
            let cwd = cwdEntry?.cwd ?? shellCwd
            let cwdSource: TerminalCWDSource? = cwdEntry?.cwd != nil ? .interestingProcess : (shellCwd != nil ? .shell : nil)

            let tab = tabByTTY[tty]
            let tmux = tmuxByTTY[tty]
            let resolvedWindow = resolveWindow(
                tmuxSession: tmux?.session,
                tab: tab,
                tty: tty,
                windowsByApp: windowsByApp,
                allWindows: terminalWindows,
                windowsByTTY: windowsByTTY
            )

            let window = resolvedWindow?.window
            let app = tab?.app ?? window.flatMap { TerminalApp.named($0.app) }
            let appName = tab?.app.rawValue ?? window?.app
            let detectedHarnesses = detectHarnesses(in: procs)
            let stableKey = makeStableKey(
                tty: tty,
                appName: appName,
                appPid: window?.pid,
                terminalSessionId: tab?.sessionId,
                tmuxSession: tmux?.session,
                tmuxPaneId: tmux?.paneId
            )
            let focusHandle = makeFocusHandle(
                window: window,
                terminalSessionId: tab?.sessionId,
                tmuxSession: tmux?.session,
                tmuxPaneId: tmux?.paneId
            )
            let placementHandle = window.map { "cg-window:\($0.wid)" }
            let capabilities = makeCapabilities(
                app: app,
                window: window,
                tab: tab,
                tmuxPaneId: tmux?.paneId,
                cwd: cwd
            )
            let provenance = makeProvenance(
                cwdSource: cwdSource,
                windowResolution: resolvedWindow?.resolution,
                hasTmux: tmux != nil,
                hasHarness: !detectedHarnesses.isEmpty
            )
            let paneCapture = tmux.flatMap { paneCaptureByPaneId[$0.paneId] }

            instances.append(TerminalInstance(
                observedAt: observedAt,
                stableKey: stableKey,
                tty: tty,
                app: app,
                appName: appName,
                appBundleIdentifier: window?.bundleIdentifier ?? app?.bundleIdentifier,
                appPid: window?.pid,
                windowIndex: tab?.windowIndex,
                tabIndex: tab?.tabIndex,
                isActiveTab: tab?.isActiveTab ?? false,
                tabTitle: tab?.title,
                terminalSessionId: tab?.sessionId,
                processes: procs,
                detectedHarnesses: detectedHarnesses,
                shellPid: shellPid,
                cwd: cwd,
                cwdSource: cwdSource,
                tmuxSession: tmux?.session,
                tmuxPaneId: tmux?.paneId,
                windowId: window?.wid,
                windowTitle: window?.title,
                windowResolution: resolvedWindow?.resolution,
                focusHandle: focusHandle,
                placementHandle: placementHandle,
                capabilities: capabilities,
                provenance: provenance,
                paneCapture: paneCapture
            ))
        }

        return instances.sorted { a, b in
            if a.hasClaude != b.hasClaude { return a.hasClaude }
            if a.isActiveTab != b.isActiveTab { return a.isActiveTab }
            if (a.appName ?? "") != (b.appName ?? "") { return (a.appName ?? "") < (b.appName ?? "") }
            return a.tty < b.tty
        }
    }

    private static func groupProcessesByTTY(_ processes: [ProcessEntry]) -> [String: [ProcessEntry]] {
        var grouped: [String: [ProcessEntry]] = [:]
        for entry in processes {
            let tty = TerminalQuery.normalizeTTY(entry.tty)
            guard tty != "??" else { continue }
            grouped[tty, default: []].append(entry)
        }
        for tty in grouped.keys {
            grouped[tty]?.sort { $0.pid < $1.pid }
        }
        return grouped
    }

    private static func detectHarnesses(in processes: [ProcessEntry]) -> [DetectedHarness] {
        var seen: Set<String> = []
        var harnesses: [DetectedHarness] = []

        for process in processes {
            let command = process.comm.lowercased()
            let args = process.args.lowercased()
            let kind: TerminalHarnessKind?
            if command == "claude" || args.contains("claude") {
                kind = .claude
            } else if command == "codex" || args.contains("codex") {
                kind = .codex
            } else {
                kind = nil
            }

            guard let kind else { continue }
            let key = "\(kind.rawValue):\(process.pid)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            harnesses.append(DetectedHarness(
                kind: kind,
                pid: process.pid,
                command: process.comm,
                args: process.args,
                evidence: "process:\(process.pid):\(process.comm)"
            ))
        }

        return harnesses
    }

    private static func makeStableKey(
        tty: String,
        appName: String?,
        appPid: Int32?,
        terminalSessionId: String?,
        tmuxSession: String?,
        tmuxPaneId: String?
    ) -> String {
        if let tmuxSession, let tmuxPaneId {
            return "tmux:\(tmuxSession):\(tmuxPaneId)"
        }
        if let terminalSessionId {
            return "terminal-session:\(terminalSessionId)"
        }
        if let appName, let appPid {
            return "terminal-window:\(appName):\(appPid):\(tty)"
        }
        return "tty:\(tty)"
    }

    private static func makeFocusHandle(
        window: TerminalWindow?,
        terminalSessionId: String?,
        tmuxSession: String?,
        tmuxPaneId: String?
    ) -> String? {
        if let window {
            return "cg-window:\(window.wid)"
        }
        if let terminalSessionId {
            return "terminal-session:\(terminalSessionId)"
        }
        if let tmuxSession, let tmuxPaneId {
            return "tmux:\(tmuxSession):\(tmuxPaneId)"
        }
        return nil
    }

    private static func makeCapabilities(
        app: TerminalApp?,
        window: TerminalWindow?,
        tab: TerminalTab?,
        tmuxPaneId: String?,
        cwd: String?
    ) -> TerminalCapabilities {
        let focusGranularity: TerminalFocusGranularity
        if tmuxPaneId != nil {
            focusGranularity = .pane
        } else if tab != nil {
            focusGranularity = .tab
        } else if window != nil {
            focusGranularity = .window
        } else {
            focusGranularity = .none
        }

        return TerminalCapabilities(
            canFocus: window != nil || tab != nil || tmuxPaneId != nil,
            canPlace: window != nil,
            canCapturePane: tmuxPaneId != nil,
            canResolveCwd: cwd != nil,
            focusGranularity: focusGranularity,
            requiresAutomation: app == .terminal || app == .iterm2
        )
    }

    private static func makeProvenance(
        cwdSource: TerminalCWDSource?,
        windowResolution: TerminalWindowResolution?,
        hasTmux: Bool,
        hasHarness: Bool
    ) -> TerminalJoinProvenance {
        let windowConfidence: TerminalConfidence?
        switch windowResolution {
        case .latticesTag:
            windowConfidence = .high
        case .appWindowIndex, .processTreeTTY:
            windowConfidence = .medium
        case nil:
            windowConfidence = nil
        }

        let notes = windowResolution == .processTreeTTY
            ? ["window joined by terminal owner process tree; tab identity may be unavailable"]
            : []

        return TerminalJoinProvenance(
            tty: .high,
            cwd: cwdSource == nil ? nil : .medium,
            window: windowConfidence,
            tmux: hasTmux ? .high : nil,
            harness: hasHarness ? .medium : nil,
            notes: notes
        )
    }

    private static func buildTmuxLookup(
        processTable: [Int: ProcessEntry],
        tmuxSessions: [TmuxSession]
    ) -> [String: (session: String, paneId: String)] {
        var tmuxByTTY: [String: (session: String, paneId: String)] = [:]
        for session in tmuxSessions {
            for pane in session.panes {
                guard let entry = processTable[pane.pid] else { continue }
                let tty = TerminalQuery.normalizeTTY(entry.tty)
                guard tty != "??" else { continue }
                tmuxByTTY[tty] = (session: session.name, paneId: pane.id)
            }
        }
        return tmuxByTTY
    }

    private static func buildWindowsByApp(_ windows: [TerminalWindow]) -> [String: [TerminalWindow]] {
        var result: [String: [TerminalWindow]] = [:]
        for window in windows {
            result[window.app, default: []].append(window)
        }
        for app in result.keys {
            result[app]?.sort {
                if $0.zIndex != $1.zIndex { return $0.zIndex < $1.zIndex }
                return $0.wid < $1.wid
            }
        }
        return result
    }

    private static func buildWindowsByTTY(
        processTable: [Int: ProcessEntry],
        terminalWindows: [TerminalWindow]
    ) -> [String: TerminalWindow] {
        var windowsByTTY: [String: TerminalWindow] = [:]

        for window in terminalWindows.sorted(by: { $0.zIndex < $1.zIndex }) {
            let rootPid = Int(window.pid)
            var candidates: [ProcessEntry] = []
            if let root = processTable[rootPid] {
                candidates.append(root)
            }
            candidates.append(contentsOf: ProcessQuery.descendants(of: rootPid, in: processTable))

            let ttys = Set(candidates.compactMap { entry -> String? in
                let tty = TerminalQuery.normalizeTTY(entry.tty)
                return tty.hasPrefix("ttys") ? tty : nil
            })

            for tty in ttys where windowsByTTY[tty] == nil {
                windowsByTTY[tty] = window
            }
        }

        return windowsByTTY
    }

    private static func resolveWindow(
        tmuxSession: String?,
        tab: TerminalTab?,
        tty: String,
        windowsByApp: [String: [TerminalWindow]],
        allWindows: [TerminalWindow],
        windowsByTTY: [String: TerminalWindow]
    ) -> (window: TerminalWindow, resolution: TerminalWindowResolution)? {
        if let session = tmuxSession {
            let tag = LatticesTerminalTag.windowTag(for: session)
            if let match = allWindows.first(where: { $0.latticesSession == session || $0.title.contains(tag) }) {
                return (match, .latticesTag)
            }
        }

        if let tab = tab,
           let appWindows = windowsByApp[tab.app.rawValue],
           tab.windowIndex < appWindows.count {
            return (appWindows[tab.windowIndex], .appWindowIndex)
        }

        if let window = windowsByTTY[tty] {
            return (window, .processTreeTTY)
        }

        return nil
    }
}
