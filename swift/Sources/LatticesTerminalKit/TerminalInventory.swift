import Foundation

public enum TerminalInventory {
    public static func snapshot(options: TerminalInventoryOptions = TerminalInventoryOptions()) -> TerminalInventorySnapshot {
        let observedAt = Date()
        let processSnapshot = ProcessQuery.snapshotWithCWDs(commands: options.interestingCommands)
        let tmuxSessions = TmuxQuery.listSessions()
        let terminalTabs = TerminalQuery.queryAll(apps: options.apps)
        let terminalWindows = TerminalWindowQuery.listTerminalWindows(
            apps: options.apps,
            additionalAppNames: options.additionalTerminalAppNames
        )

        let capturedContent = options.includePaneContent
            ? capturePaneContent(tmuxSessions: tmuxSessions, lineLimit: options.paneContentLineLimit)
            : [:]

        let terminals = TerminalSynthesizer.synthesize(
            processTable: processSnapshot.table,
            interesting: processSnapshot.interesting,
            tmuxSessions: tmuxSessions,
            terminalTabs: terminalTabs,
            terminalWindows: terminalWindows,
            paneCaptureByPaneId: capturedContent,
            observedAt: observedAt
        )

        return TerminalInventorySnapshot(
            snapshotId: UUID().uuidString,
            observedAt: observedAt,
            timestamp: observedAt,
            terminals: terminals,
            tmuxSessions: tmuxSessions,
            terminalTabs: terminalTabs,
            terminalWindows: terminalWindows
        )
    }

    private static func capturePaneContent(tmuxSessions: [TmuxSession], lineLimit: Int) -> [String: TerminalPaneCapture] {
        var result: [String: TerminalPaneCapture] = [:]
        let observedAt = Date()
        let clampedLimit = max(1, min(lineLimit, 2_000))
        for pane in tmuxSessions.flatMap(\.panes) {
            if let content = TmuxQuery.capturePane(paneId: pane.id, lineLimit: clampedLimit) {
                let lineCount = content.split(separator: "\n", omittingEmptySubsequences: false).count
                result[pane.id] = TerminalPaneCapture(
                    text: content,
                    observedAt: observedAt,
                    lineLimit: clampedLimit,
                    lineCount: lineCount,
                    truncated: lineCount >= clampedLimit
                )
            }
        }
        return result
    }
}
