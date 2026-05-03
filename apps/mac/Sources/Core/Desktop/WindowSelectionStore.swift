import Combine
import Foundation

struct SelectedWindowSummary: Identifiable, Equatable {
    let wid: UInt32
    let app: String
    let title: String
    let latticesSession: String?

    var id: UInt32 { wid }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let latticesSession, !latticesSession.isEmpty { return latticesSession }
        return app
    }
}

final class WindowSelectionStore: ObservableObject {
    static let shared = WindowSelectionStore()

    @Published private(set) var windows: [SelectedWindowSummary] = []
    @Published private(set) var source: String?
    @Published private(set) var updatedAt: Date?

    private init() {}

    var isActive: Bool { !windows.isEmpty }
    var windowIds: [UInt32] { windows.map(\.wid) }
    var count: Int { windows.count }
    var sourceLabel: String? {
        switch source {
        case "desktop-inventory": return "window selector"
        case "screen-map": return "screen map"
        case let value?: return value
        case nil: return nil
        }
    }

    func setSelection(_ windows: [SelectedWindowSummary], source: String) {
        let unique = Array(
            Dictionary(uniqueKeysWithValues: windows.map { ($0.wid, $0) }).values
        ).sorted { lhs, rhs in
            if lhs.app == rhs.app { return lhs.wid < rhs.wid }
            return lhs.app.localizedCaseInsensitiveCompare(rhs.app) == .orderedAscending
        }

        DispatchQueue.main.async {
            self.windows = unique
            self.source = source
            self.updatedAt = Date()
        }
    }

    func clear(source: String? = nil) {
        DispatchQueue.main.async {
            if let source, let current = self.source, current != source {
                return
            }
            self.windows = []
            self.source = source ?? self.source
            self.updatedAt = Date()
        }
    }

    func summary(maxItems: Int = 3) -> String {
        guard !windows.isEmpty else { return "No selection" }
        let titles = windows.prefix(maxItems).map { item in
            item.app == item.displayTitle ? item.app : "\(item.app): \(item.displayTitle)"
        }
        if windows.count > maxItems {
            return titles.joined(separator: " • ") + " +\(windows.count - maxItems)"
        }
        return titles.joined(separator: " • ")
    }
}
