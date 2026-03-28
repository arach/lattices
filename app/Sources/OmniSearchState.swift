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

    // MARK: - Search (delegates to unified lattices.search API)

    private func search(_ query: String) {
        let q = query.lowercased()
        var all: [OmniResult] = []

        // ── Daemon search: windows, terminals, OCR — single source of truth ──
        // This is synchronous on the daemon's in-process API, not a network call.
        if let json = try? LatticesApi.shared.dispatch(
            method: "lattices.search",
            params: .object(["query": .string(q)])
        ), case .array(let hits) = json {
            let desktop = DesktopModel.shared
            for hit in hits {
                guard let wid = hit["wid"]?.uint32Value else { continue }
                let app = hit["app"]?.stringValue ?? ""
                let title = hit["title"]?.stringValue ?? ""
                let score = hit["score"]?.intValue ?? 0
                let pid = desktop.windows[wid]?.pid ?? 0
                let sources = (hit["matchSources"]?.arrayValue ?? []).compactMap(\.stringValue)

                // Determine kind from match sources
                let hasOcr = sources.contains("ocr")
                let hasTerminal = !Set(sources).isDisjoint(with: ["cwd", "tab", "tmux", "process"])
                let kind: OmniResultKind = hasOcr ? .ocrContent : hasTerminal ? .session : .window

                let icon: String
                let subtitle: String
                switch kind {
                case .ocrContent:
                    icon = "doc.text.magnifyingglass"
                    subtitle = hit["ocrSnippet"]?.stringValue ?? title
                case .session:
                    icon = "terminal"
                    let tabs = hit["terminalTabs"]?.arrayValue ?? []
                    let cwds = tabs.compactMap { $0["cwd"]?.stringValue }
                    subtitle = cwds.first ?? title
                default:
                    icon = "macwindow"
                    subtitle = title.isEmpty ? "Window \(wid)" : title
                }

                all.append(OmniResult(
                    kind: kind,
                    title: app,
                    subtitle: subtitle,
                    icon: icon,
                    score: score
                ) {
                    WindowTiler.focusWindow(wid: wid, pid: pid)
                })
            }
        }

        // ── Projects: local-only (not window-centric, so not in daemon search) ──
        for project in ProjectScanner.shared.projects {
            let score = scoreProjectMatch(q, name: project.name, path: project.path)
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

        all.sort { $0.score > $1.score }
        results = all
        selectedIndex = 0
    }

    // MARK: - Project scoring (local — projects aren't windows)

    private func scoreProjectMatch(_ query: String, name: String, path: String) -> Int {
        let lowerName = name.lowercased()
        let lowerPath = path.lowercased()
        if lowerName == query { return 100 }
        if lowerName.hasPrefix(query) { return 80 }
        if lowerName.contains(query) { return 60 }
        if lowerPath.contains(query) { return 40 }
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
