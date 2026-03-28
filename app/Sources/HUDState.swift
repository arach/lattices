import Combine
import CoreGraphics
import Foundation

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
    private static let leftSidebarWidthKey = "hud.leftSidebarWidth"
    private static let defaultLeftSidebarWidth: CGFloat = 320
    private static let minLeftSidebarWidth: CGFloat = 260
    private static let maxLeftSidebarWidth: CGFloat = 420

    @Published var selectedItem: HUDItem?
    @Published var pinnedItem: HUDItem?
    @Published var hoveredPreviewItem: HUDItem?
    @Published var feedbackMessage: String?
    @Published var query: String = ""
    @Published var selectedIndex: Int = 0
    @Published var focus: HUDFocus = .search
    @Published var voiceActive: Bool = false
    @Published var expandedSections: Set<Int> = [2]
    @Published var leftSidebarWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: HUDState.leftSidebarWidthKey)
        if saved > 0 {
            return min(max(CGFloat(saved), HUDState.minLeftSidebarWidth), HUDState.maxLeftSidebarWidth)
        }
        return HUDState.defaultLeftSidebarWidth
    }()

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

    var hoverPreviewAnchorScreenY: CGFloat?
    var previewInteractionActive: Bool = false

    /// Section offsets for number-key jumping (1=Projects, 2=Terminals, 3=Chrome, 4=Claude)
    var sectionOffsets: [Int: Int] = [:]

    private var selectionAnchorID: String?
    private var touchedSections: Set<Int> = []
    private var feedbackClearWorkItem: DispatchWorkItem?

    var leftSidebarWidthRange: ClosedRange<CGFloat> {
        Self.minLeftSidebarWidth...Self.maxLeftSidebarWidth
    }

    func setLeftSidebarWidth(_ width: CGFloat) {
        let clamped = min(max(width, Self.minLeftSidebarWidth), Self.maxLeftSidebarWidth)
        guard abs(clamped - leftSidebarWidth) > 0.5 else { return }
        leftSidebarWidth = clamped
        UserDefaults.standard.set(Double(clamped), forKey: Self.leftSidebarWidthKey)
    }

    func isSectionExpanded(_ key: Int) -> Bool {
        expandedSections.contains(key)
    }

    func toggleSection(_ key: Int) {
        if expandedSections.contains(key) {
            expandedSections.remove(key)
        } else {
            expandedSections.insert(key)
        }
        touchedSections.insert(key)
    }

    func resetSectionDefaults(hasRunningProjects: Bool) {
        expandedSections = [2]
        if hasRunningProjects {
            expandedSections.insert(1)
        }
        touchedSections = []
    }

    func syncAutoSectionDefaults(hasRunningProjects: Bool) {
        if !touchedSections.contains(2) {
            expandedSections.insert(2)
        }
        if !touchedSections.contains(1) {
            if hasRunningProjects {
                expandedSections.insert(1)
            } else {
                expandedSections.remove(1)
            }
        }
    }

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

    var transientPreviewItem: HUDItem? {
        if let hoveredPreviewItem {
            return hoveredPreviewItem
        }
        if pinnedItem == nil && focus == .list {
            return selectedItem
        }
        return nil
    }

    var inspectorCandidateItem: HUDItem? {
        if let pinnedItem {
            return pinnedItem
        }
        if let hoveredPreviewItem {
            return hoveredPreviewItem
        }
        return selectedItem
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

    func showFeedback(_ message: String, autoClearAfter delay: TimeInterval = 0.9) {
        feedbackClearWorkItem?.cancel()
        feedbackMessage = message

        let clearWorkItem = DispatchWorkItem { [weak self] in
            guard self?.feedbackMessage == message else { return }
            self?.feedbackMessage = nil
        }
        feedbackClearWorkItem = clearWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: clearWorkItem)
    }

    func pinInspector(_ item: HUDItem, source: String = "selection") {
        let timed = AppFeedback.shared.beginTimed(
            "HUD inspect (\(source))",
            state: self,
            feedback: "Inspecting \(item.displayName)"
        )
        if let idx = flatItems.firstIndex(of: item) {
            selectedIndex = idx
        }
        selectedItem = item
        pinnedItem = item
        hoveredPreviewItem = nil
        selectedItems = []
        selectionAnchorID = item.id
        focus = .inspector
        DispatchQueue.main.async {
            AppFeedback.shared.finish(timed)
        }
    }

    func pinInspectorCandidate(source: String = "preview") {
        guard let item = inspectorCandidateItem else { return }
        pinInspector(item, source: source)
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
        if let pinnedItem, !validIDs.contains(pinnedItem.id) {
            self.pinnedItem = nil
        }
        if let hoveredPreviewItem, !validIDs.contains(hoveredPreviewItem.id) {
            self.hoveredPreviewItem = nil
        }
        if let selectionAnchorID, !validIDs.contains(selectionAnchorID) {
            self.selectionAnchorID = selectedItem?.id
        }

        guard !items.isEmpty else {
            selectedItem = nil
            pinnedItem = nil
            hoveredPreviewItem = nil
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
