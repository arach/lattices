import AppKit
import Combine
import Foundation

// MARK: - Result Types

enum OmniResultKind: String {
    case window
    case project
    case session
    case process
    case ocrContent
}

struct OmniResult: Identifiable {
    let id = UUID()
    let kind: OmniResultKind
    let title: String
    let subtitle: String
    let icon: String
    let score: Int           // higher = better match
    let action: () -> Void

    /// Group label for display
    var groupLabel: String {
        switch kind {
        case .window:     return "Windows"
        case .project:    return "Projects"
        case .session:    return "Sessions"
        case .process:    return "Processes"
        case .ocrContent: return "Screen Text"
        }
    }
}

// MARK: - Activity Summary

struct ActivitySummary {
    struct AppWindowCount: Identifiable {
        let id: String
        let appName: String
        let count: Int
    }

    struct SessionInfo: Identifiable {
        let id: String
        let name: String
        let paneCount: Int
        let attached: Bool
    }

    let windowsByApp: [AppWindowCount]
    let totalWindows: Int
    let sessions: [SessionInfo]
    let interestingProcesses: [ProcessEntry]
    let lastOcrScan: Date?
    let ocrWindowCount: Int
}

// MARK: - State

final class OmniSearchState: ObservableObject {
    @Published var query: String = ""
    @Published var results: [OmniResult] = []
    @Published var selectedIndex: Int = 0
    @Published var activitySummary: ActivitySummary?

    private var cancellables = Set<AnyCancellable>()
    private var debounceTimer: AnyCancellable?

    init() {
        // Debounce search by 150ms
        debounceTimer = $query
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] q in
                if q.isEmpty {
                    self?.results = []
                    self?.refreshSummary()
                } else {
                    self?.search(q)
                }
            }

        refreshSummary()
    }

    // MARK: - Search

    private func search(_ query: String) {
        let q = query.lowercased()
        var all: [OmniResult] = []

        // Windows
        let desktop = DesktopModel.shared
        for win in desktop.allWindows() {
            let score = scoreMatch(q, against: [win.app, win.title])
            if score > 0 {
                let wid = win.wid
                let pid = win.pid
                all.append(OmniResult(
                    kind: .window,
                    title: win.app,
                    subtitle: win.title.isEmpty ? "Window \(win.wid)" : win.title,
                    icon: "macwindow",
                    score: score
                ) {
                    WindowTiler.focusWindow(wid: wid, pid: pid)
                })
            }
        }

        // Projects
        let scanner = ProjectScanner.shared
        for project in scanner.projects {
            let score = scoreMatch(q, against: [project.name, project.path])
            if score > 0 {
                let proj = project
                all.append(OmniResult(
                    kind: .project,
                    title: project.name,
                    subtitle: project.path,
                    icon: "folder",
                    score: score
                ) {
                    SessionManager.launch(project: proj)
                })
            }
        }

        // Tmux Sessions
        let tmux = TmuxModel.shared
        for session in tmux.sessions {
            let paneCommands = session.panes.map(\.currentCommand)
            let score = scoreMatch(q, against: [session.name] + paneCommands)
            if score > 0 {
                let name = session.name
                all.append(OmniResult(
                    kind: .session,
                    title: session.name,
                    subtitle: "\(session.windowCount) windows, \(session.panes.count) panes\(session.attached ? " (attached)" : "")",
                    icon: "terminal",
                    score: score
                ) {
                    let terminal = Preferences.shared.terminal
                    terminal.focusOrAttach(session: name)
                })
            }
        }

        // Processes
        let processes = ProcessModel.shared
        for proc in processes.interesting {
            let score = scoreMatch(q, against: [proc.comm, proc.args, proc.cwd ?? ""])
            if score > 0 {
                all.append(OmniResult(
                    kind: .process,
                    title: proc.comm,
                    subtitle: proc.cwd ?? proc.args,
                    icon: "gearshape",
                    score: score
                ) {
                    // No direct action for processes — just informational
                })
            }
        }

        // OCR content
        let ocr = OcrModel.shared
        for (_, result) in ocr.results {
            let ocrScore = scoreOcr(q, fullText: result.fullText)
            if ocrScore > 0 {
                let wid = result.wid
                let pid = desktop.windows[wid]?.pid ?? 0
                // Find matching line for subtitle
                let matchLine = result.texts
                    .first { $0.text.lowercased().contains(q) }?
                    .text ?? String(result.fullText.prefix(80))
                all.append(OmniResult(
                    kind: .ocrContent,
                    title: "\(result.app) — \(result.title)",
                    subtitle: matchLine,
                    icon: "doc.text.magnifyingglass",
                    score: ocrScore
                ) {
                    WindowTiler.focusWindow(wid: wid, pid: pid)
                })
            }
        }

        // Sort by score descending
        all.sort { $0.score > $1.score }

        results = all
        selectedIndex = 0
    }

    // MARK: - Scoring

    private func scoreMatch(_ query: String, against fields: [String]) -> Int {
        var best = 0
        for field in fields {
            let lower = field.lowercased()
            if lower == query {
                best = max(best, 100)  // exact
            } else if lower.hasPrefix(query) {
                best = max(best, 80)   // prefix
            } else if lower.contains(query) {
                best = max(best, 60)   // contains
            }
        }
        return best
    }

    private func scoreOcr(_ query: String, fullText: String) -> Int {
        let lower = fullText.lowercased()
        if lower.contains(query) { return 40 }
        return 0
    }

    // MARK: - Navigation

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
    }

    func activateSelected() {
        guard selectedIndex >= 0, selectedIndex < results.count else { return }
        results[selectedIndex].action()
    }

    // MARK: - Activity Summary

    func refreshSummary() {
        let desktop = DesktopModel.shared
        let windows = desktop.allWindows()

        // Group by app
        var appCounts: [String: Int] = [:]
        for win in windows {
            appCounts[win.app, default: 0] += 1
        }
        let windowsByApp = appCounts
            .sorted { $0.value > $1.value }
            .map { ActivitySummary.AppWindowCount(id: $0.key, appName: $0.key, count: $0.value) }

        // Sessions
        let sessions = TmuxModel.shared.sessions.map {
            ActivitySummary.SessionInfo(
                id: $0.id,
                name: $0.name,
                paneCount: $0.panes.count,
                attached: $0.attached
            )
        }

        // Processes
        let procs = ProcessModel.shared.interesting

        // OCR info
        let ocrResults = OcrModel.shared.results
        let lastScan: Date? = ocrResults.values.map(\.timestamp).max()

        activitySummary = ActivitySummary(
            windowsByApp: windowsByApp,
            totalWindows: windows.count,
            sessions: sessions,
            interestingProcesses: procs,
            lastOcrScan: lastScan,
            ocrWindowCount: ocrResults.count
        )
    }

    /// Grouped results for display
    var groupedResults: [(String, [OmniResult])] {
        let groups = Dictionary(grouping: results) { $0.groupLabel }
        let order: [String] = ["Windows", "Projects", "Sessions", "Processes", "Screen Text"]
        return order.compactMap { key in
            guard let items = groups[key], !items.isEmpty else { return nil }
            return (key, items)
        }
    }
}
