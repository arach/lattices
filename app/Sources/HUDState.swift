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

    private var selectionAnchorID: String?

    var effectiveSelectionIDs: Set<String> {
        if selectedItems.isEmpty {
            if let selectedItem {
                return [selectedItem.id]
            }
            return []
        }

        var ids = selectedItems
        if let selectedItem {
            ids.insert(selectedItem.id)
        }
        return ids
    }

    var multiSelectionCount: Int {
        let count = effectiveSelectionIDs.count
        return count > 1 ? count : 0
    }

    func clearMultiSelection() {
        selectedItems = []
        if let selectedItem {
            selectionAnchorID = selectedItem.id
        } else {
            selectionAnchorID = nil
        }
    }

    func selectSingle(_ item: HUDItem, index: Int) {
        selectedItem = item
        selectedIndex = index
        selectedItems = []
        selectionAnchorID = item.id
    }

    func toggleSelection(_ item: HUDItem, index: Int, in items: [HUDItem]) {
        let anchorID = selectionAnchorID ?? selectedItem?.id ?? item.id

        if selectedItems.isEmpty, let current = selectedItem {
            selectedItems = [current.id]
        }

        if selectedItems.contains(item.id) {
            selectedItems.remove(item.id)
        } else {
            selectedItems.insert(item.id)
        }

        if selectedItems.isEmpty {
            selectSingle(item, index: index)
            return
        }

        if selectedItems.count == 1,
           let remainingID = selectedItems.first,
           let remainingIndex = items.firstIndex(where: { $0.id == remainingID }),
           let remainingItem = items[safe: remainingIndex] {
            selectSingle(remainingItem, index: remainingIndex)
            return
        }

        selectedItem = item
        selectedIndex = index
        selectionAnchorID = anchorID
    }

    func selectRange(to item: HUDItem, index: Int, in items: [HUDItem]) {
        guard !items.isEmpty else { return }

        let anchorID = selectionAnchorID ?? selectedItem?.id ?? item.id
        guard let anchorIndex = items.firstIndex(where: { $0.id == anchorID }) else {
            selectSingle(item, index: index)
            return
        }

        let lower = min(anchorIndex, index)
        let upper = max(anchorIndex, index)
        let ids = Set(items[lower...upper].map(\.id))

        selectedItem = item
        selectedIndex = index
        selectedItems = ids.count > 1 ? ids : []
        selectionAnchorID = anchorID
    }

    func moveSelection(by delta: Int, extend: Bool) {
        let items = flatItems
        guard !items.isEmpty else { return }

        let currentIndex: Int
        if let selectedItem,
           let idx = items.firstIndex(of: selectedItem) {
            currentIndex = idx
        } else {
            currentIndex = max(0, min(items.count - 1, selectedIndex))
        }

        let nextIndex = max(0, min(items.count - 1, currentIndex + delta))
        guard let nextItem = items[safe: nextIndex] else { return }

        if extend {
            selectRange(to: nextItem, index: nextIndex, in: items)
        } else {
            selectSingle(nextItem, index: nextIndex)
        }
    }

    func reconcileSelection(with items: [HUDItem]) {
        let validIDs = Set(items.map(\.id))

        selectedItems = selectedItems.intersection(validIDs)
        if let selectedItem, !validIDs.contains(selectedItem.id) {
            self.selectedItem = nil
        }
        if let selectionAnchorID, !validIDs.contains(selectionAnchorID) {
            self.selectionAnchorID = selectedItem?.id
        }

        guard !items.isEmpty else {
            selectedItem = nil
            selectedIndex = 0
            selectedItems = []
            selectionAnchorID = nil
            return
        }

        if selectedItem == nil {
            let clampedIndex = max(0, min(items.count - 1, selectedIndex))
            if let fallback = items[safe: clampedIndex] {
                selectedItem = fallback
                selectedIndex = clampedIndex
                if selectionAnchorID == nil {
                    selectionAnchorID = fallback.id
                }
            }
            return
        }

        if let selectedItem,
           let itemIndex = items.firstIndex(of: selectedItem) {
            selectedIndex = itemIndex
        } else {
            selectedIndex = max(0, min(items.count - 1, selectedIndex))
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
