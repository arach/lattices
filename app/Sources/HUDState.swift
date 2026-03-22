import Foundation
import Combine

// MARK: - HUDItem

enum HUDItem: Identifiable, Equatable {
    case project(Project)
    case window(WindowEntry)

    var id: String {
        switch self {
        case .project(let p): return "project-\(p.id)"
        case .window(let w):  return "window-\(w.wid)"
        }
    }

    var displayName: String {
        switch self {
        case .project(let p): return p.name
        case .window(let w):  return w.title
        }
    }

    var appName: String? {
        switch self {
        case .project: return nil
        case .window(let w): return w.app
        }
    }

    static func == (lhs: HUDItem, rhs: HUDItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Focus target

enum HUDFocus: Equatable {
    case search       // typing into the left bar search field
    case list         // navigating the left bar item list
    case inspector    // tabbed over to the right bar
}

// MARK: - HUDState

final class HUDState: ObservableObject {
    @Published var selectedItem: HUDItem?
    @Published var query: String = ""
    @Published var selectedIndex: Int = 0
    @Published var focus: HUDFocus = .search
    @Published var voiceActive: Bool = false

    /// Multi-select for tiling — set of item IDs
    @Published var selectedItems: Set<String> = []

    enum MinimapMode: Equatable { case hidden, docked, expanded }
    @Published var minimapMode: MinimapMode = .docked

    // MARK: - Tile mode

    @Published var tileMode: Bool = false

    /// Snapshot of window positions taken when entering tile mode
    struct WindowSnapshot {
        let wid: UInt32
        let pid: Int32
        let frame: CGRect
    }
    var tileSnapshot: [WindowSnapshot] = []
    var tiledWindows: Set<UInt32> = []

    /// Pre-computed grid layout — calculated on HUD show, applied instantly on T press
    var precomputedGrid: [(wid: UInt32, pid: Int32, frame: CGRect)] = []

    /// Snapshot of the flat item list — set by HUDLeftBar so key handler can index into it
    var flatItems: [HUDItem] = []

    /// Section offsets for number-key jumping (1=Projects, 2=Terminals, 3=Chrome, 4=Claude)
    var sectionOffsets: [Int: Int] = [:]
}
