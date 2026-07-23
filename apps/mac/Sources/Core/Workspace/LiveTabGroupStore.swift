import AppKit

// MARK: - Live cross-app tabs

extension Notification.Name {
    /// Posted immediately before a live tab activates one of its real windows.
    /// Hyper-3 uses it to ignore the synthetic focus click that some apps need.
    static let liveTabGroupWillFocusWindow = Notification.Name("liveTabGroupWillFocusWindow")

    /// Posted after a group operation that can change native window geometry.
    /// Selection-only changes deliberately do not post this: the HUD can swap
    /// the active tab immediately without paying for another desktop inventory.
    static let liveTabGroupGeometryDidChange = Notification.Name("liveTabGroupGeometryDidChange")
}

struct LiveTabMember: Identifiable {
    let id: UInt32
    var pid: Int32
    var app: String
    var title: String

    var label: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? app : trimmed
    }
}

struct LiveTabGroup: Identifiable {
    let id: String
    var name: String
    var members: [LiveTabMember]
    var selectedIndex: Int
    var isExpanded: Bool
    var placement: PlacementSpec
    var screen: NSScreen
}

/// Runtime-only tab stacks created from live windows. Hyperspace, the in-app
/// assistant, and daemon agents all write through this store so every entry
/// point has identical stack/grid/select behavior.
final class LiveTabGroupStore: ObservableObject {
    static let shared = LiveTabGroupStore()

    @Published private(set) var groups: [LiveTabGroup] = []
    @Published private(set) var activeGroupID: String?
    @Published private(set) var candidateWindowIDs: [UInt32] = []

    /// Optional reserved space for experiments that alter native layout. The
    /// persistent group guide is an overlay and leaves this at zero.
    private var hudChromeInset: CGFloat = 0
    private var expectedFocusedWindowID: UInt32?
    private var suppressFocusSyncUntil: Date = .distantPast

    private init() {}

    var activeGroup: LiveTabGroup? {
        guard let activeGroupID else { return nil }
        return groups.first(where: { $0.id == activeGroupID })
    }

    func captureCandidateSelection(_ windowIDs: [UInt32]) {
        var seen = Set<UInt32>()
        candidateWindowIDs = windowIDs.filter { seen.insert($0).inserted }
    }

    @discardableResult
    func createFromCandidate(
        name: String? = nil,
        placement: PlacementSpec = .tile(.topLeft),
        screen: NSScreen? = nil
    ) -> LiveTabGroup? {
        create(windowIDs: candidateWindowIDs, name: name, placement: placement, screen: screen)
    }

    @discardableResult
    func create(
        windowIDs: [UInt32],
        name: String? = nil,
        placement: PlacementSpec = .tile(.topLeft),
        screen: NSScreen? = nil
    ) -> LiveTabGroup? {
        DesktopModel.shared.forcePoll()
        let members = resolvedMembers(windowIDs)
        guard members.count >= 2 else { return nil }

        if let existing = groups.first(where: { Set($0.members.map(\.id)) == Set(members.map(\.id)) }) {
            activeGroupID = existing.id
            collapse(id: existing.id)
            return groups.first(where: { $0.id == existing.id })
        }

        let firstEntry = DesktopModel.shared.windows[members[0].id]
        let targetScreen = screen
            ?? firstEntry.map { WindowTiler.screenForWindowFrame($0.frame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let targetScreen else { return nil }

        let group = LiveTabGroup(
            id: UUID().uuidString,
            name: normalizedName(name, members: members),
            members: members,
            selectedIndex: 0,
            isExpanded: false,
            placement: placement,
            screen: targetScreen
        )
        groups.append(group)
        activeGroupID = group.id
        collapse(id: group.id)
        DiagnosticLog.shared.info("Live tabs: created '\(group.name)' with \(members.count) windows")
        return groups.first(where: { $0.id == group.id })
    }

    @discardableResult
    func addCandidate(to groupID: String? = nil) -> Int {
        add(windowIDs: candidateWindowIDs, to: groupID)
    }

    @discardableResult
    func add(windowIDs: [UInt32], to groupID: String? = nil) -> Int {
        guard let id = groupID ?? activeGroupID,
              let index = groups.firstIndex(where: { $0.id == id }) else { return 0 }
        let existing = Set(groups[index].members.map(\.id))
        let additions = resolvedMembers(windowIDs).filter { !existing.contains($0.id) }
        guard !additions.isEmpty else { return 0 }
        groups[index].members.append(contentsOf: additions)
        activeGroupID = id
        collapse(id: id)
        DiagnosticLog.shared.info("Live tabs: added \(additions.count) window(s) to '\(groups[index].name)'")
        return additions.count
    }

    func select(groupID: String, index: Int) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
              index >= 0, index < groups[groupIndex].members.count else { return }
        groups[groupIndex].selectedIndex = index
        activeGroupID = groupID
        let group = groups[groupIndex]
        let selectedMember = group.members[index]

        // A tab switch normally changes only z-order. Re-running collapse here
        // used to poll the desktop, resize every member, raise the whole stack,
        // and then focus this member twice. Keep a correctness fallback for a
        // group that has drifted from its intended tile, but make the common
        // path one exact-window focus operation.
        if group.isExpanded || collapsedLayoutIsCurrent(group) {
            focus(selectedMember)
        } else {
            collapse(id: groupID)
        }
    }

    func select(groupID: String, windowID: UInt32) {
        guard let group = groups.first(where: { $0.id == groupID }),
              let index = group.members.firstIndex(where: { $0.id == windowID }) else { return }
        select(groupID: groupID, index: index)
    }

    /// Pull one native window out of a live group and place it beneath the drop
    /// point. If that leaves fewer than two members, dissolve the group entirely.
    /// The detached window is focused last so it wins the native z-order race.
    func detach(groupID: String, windowID: UInt32, at dropPoint: NSPoint) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
              let memberIndex = groups[groupIndex].members.firstIndex(where: { $0.id == windowID })
        else { return }

        DesktopModel.shared.forcePoll()
        let originalGroup = groups[groupIndex]
        let detachedMember = originalGroup.members[memberIndex]
        let currentFrame: CGRect
        if let frame = DesktopModel.shared.windows[windowID]?.frame {
            currentFrame = CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
        } else {
            currentFrame = collapsedFrame(for: originalGroup)
        }
        let targetFrame = detachedFrame(
            current: currentFrame,
            dropPoint: dropPoint,
            fallbackScreen: originalGroup.screen
        )

        groups[groupIndex].members.remove(at: memberIndex)
        if groups[groupIndex].members.count < 2 {
            let remaining = groups[groupIndex].members
            let restoredFrame = WindowTiler.tileFrame(
                for: originalGroup.placement,
                on: originalGroup.screen
            )
            if !remaining.isEmpty {
                WindowTiler.batchMoveWindows(
                    remaining.map { (wid: $0.id, pid: $0.pid, frame: restoredFrame) }
                )
            }
            groups.remove(at: groupIndex)
            activeGroupID = groups.last?.id
        } else {
            if memberIndex < originalGroup.selectedIndex {
                groups[groupIndex].selectedIndex = originalGroup.selectedIndex - 1
            } else if memberIndex == originalGroup.selectedIndex {
                groups[groupIndex].selectedIndex = min(
                    memberIndex,
                    groups[groupIndex].members.count - 1
                )
            }
            activeGroupID = groupID
            collapse(id: groupID)
        }

        WindowTiler.batchMoveAndRaiseWindows([
            (wid: detachedMember.id, pid: detachedMember.pid, frame: targetFrame),
        ])
        focus(detachedMember)
        DesktopModel.shared.forcePoll()
        notifyGeometryChanged()
        DiagnosticLog.shared.info(
            "Live tabs: detached \(detachedMember.app) from '\(originalGroup.name)'"
        )
    }

    /// Keep the visual tab selection honest when a grouped window was focused
    /// outside the rail before (or while) Hyper-3 is open.
    func syncSelection(toFocusedWindow windowID: UInt32?) {
        guard let windowID else { return }
        // Activation can briefly report the previously-frontmost app while AX
        // and WindowServer settle. Do not let that transient observation make
        // the selected tab flicker backward after an explicit tab action.
        if Date() < suppressFocusSyncUntil,
           let expectedFocusedWindowID,
           windowID != expectedFocusedWindowID {
            return
        }
        for groupIndex in groups.indices {
            guard let memberIndex = groups[groupIndex].members.firstIndex(where: { $0.id == windowID }) else { continue }
            guard groups[groupIndex].selectedIndex != memberIndex else { return }
            groups[groupIndex].selectedIndex = memberIndex
            activeGroupID = groups[groupIndex].id
            return
        }
    }

    func toggleLayout(id: String? = nil) {
        guard let id = id ?? activeGroupID,
              let group = groups.first(where: { $0.id == id }) else { return }
        group.isExpanded ? collapse(id: id) : expand(id: id)
    }

    func setHUDChromeInset(_ height: CGFloat) {
        let next = max(0, height)
        guard abs(next - hudChromeInset) > 0.5 else { return }
        hudChromeInset = next

        var moves: [(wid: UInt32, pid: Int32, frame: CGRect)] = []
        for group in groups where !group.isExpanded {
            let frame = collapsedFrame(for: group)
            moves.append(contentsOf: group.members.map { (wid: $0.id, pid: $0.pid, frame: frame) })
        }
        WindowTiler.batchMoveWindows(moves)
        DesktopModel.shared.forcePoll()
        notifyGeometryChanged()
    }

    func expand(id: String? = nil) {
        guard let id = id ?? activeGroupID,
              let index = groups.firstIndex(where: { $0.id == id }) else { return }
        let windows = liveWindows(for: groups[index])
        guard !windows.isEmpty else { return }
        groups[index].isExpanded = true
        activeGroupID = id
        WindowTiler.batchRaiseAndDistribute(
            windows: windows.map { (wid: $0.wid, pid: $0.pid) },
            reactivateLattices: false
        )
        notifyGeometryChanged()
    }

    func collapse(id: String? = nil) {
        guard let id = id ?? activeGroupID,
              let index = groups.firstIndex(where: { $0.id == id }) else { return }
        refreshMembers(at: index)
        let group = groups[index]
        let windows = orderedLiveWindows(for: group)
        guard !windows.isEmpty else { return }
        let frame = collapsedFrame(for: group)
        WindowTiler.batchMoveAndRaiseWindows(
            windows.map { (wid: $0.wid, pid: $0.pid, frame: frame) }
        )
        groups[index].isExpanded = false
        activeGroupID = id
        if group.selectedIndex < group.members.count {
            focus(group.members[group.selectedIndex])
        }
        notifyGeometryChanged()
    }

    func delete(id: String? = nil) {
        guard let id = id ?? activeGroupID else { return }
        if let group = groups.first(where: { $0.id == id }), !group.isExpanded {
            let restoredFrame = WindowTiler.tileFrame(for: group.placement, on: group.screen)
            WindowTiler.batchMoveWindows(
                group.members.map { (wid: $0.id, pid: $0.pid, frame: restoredFrame) }
            )
        }
        groups.removeAll { $0.id == id }
        activeGroupID = groups.last?.id
        DesktopModel.shared.forcePoll()
        notifyGeometryChanged()
    }

    func assistantContextPayload() -> [String: Any] {
        [
            "candidateWindowIds": candidateWindowIDs.map(Int.init),
            "activeGroupId": (activeGroupID as Any?) ?? NSNull(),
            "groups": groups.map { group in
                [
                    "id": group.id,
                    "name": group.name,
                    "mode": group.isExpanded ? "grid" : "tabs",
                    "placement": group.placement.wireValue,
                    "selectedIndex": group.selectedIndex,
                    "members": group.members.map { member in
                        ["wid": Int(member.id), "app": member.app, "title": member.title] as [String: Any]
                    },
                ] as [String: Any]
            },
        ]
    }

    private func resolvedMembers(_ windowIDs: [UInt32]) -> [LiveTabMember] {
        var seen = Set<UInt32>()
        return windowIDs.compactMap { wid in
            guard seen.insert(wid).inserted,
                  let entry = DesktopModel.shared.windows[wid] else { return nil }
            return LiveTabMember(id: wid, pid: entry.pid, app: entry.app, title: entry.title)
        }
    }

    private func refreshMembers(at index: Int) {
        DesktopModel.shared.forcePoll()
        for memberIndex in groups[index].members.indices {
            let wid = groups[index].members[memberIndex].id
            guard let entry = DesktopModel.shared.windows[wid] else { continue }
            groups[index].members[memberIndex].pid = entry.pid
            groups[index].members[memberIndex].app = entry.app
            groups[index].members[memberIndex].title = entry.title
        }
        groups[index].selectedIndex = min(
            groups[index].selectedIndex,
            max(0, groups[index].members.count - 1)
        )
    }

    private func liveWindows(for group: LiveTabGroup) -> [WindowEntry] {
        DesktopModel.shared.forcePoll()
        return group.members.compactMap { DesktopModel.shared.windows[$0.id] }
    }

    private func orderedLiveWindows(for group: LiveTabGroup) -> [WindowEntry] {
        var windows: [WindowEntry] = []
        for (index, member) in group.members.enumerated() where index != group.selectedIndex {
            if let entry = DesktopModel.shared.windows[member.id] { windows.append(entry) }
        }
        if group.selectedIndex < group.members.count,
           let entry = DesktopModel.shared.windows[group.members[group.selectedIndex].id] {
            windows.append(entry)
        }
        return windows
    }

    private func collapsedFrame(for group: LiveTabGroup) -> CGRect {
        let base = WindowTiler.tileFrame(for: group.placement, on: group.screen)
        guard hudChromeInset > 0 else { return base }
        return CGRect(
            x: base.minX,
            y: base.minY + hudChromeInset,
            width: base.width,
            height: max(240, base.height - hudChromeInset)
        )
    }

    /// Uses the already-polled desktop snapshot as a cheap drift guard. A
    /// missing or visibly moved member takes the slower repair path in
    /// `collapse`; ordinary tab changes avoid a synchronous CG/AX inventory.
    private func collapsedLayoutIsCurrent(_ group: LiveTabGroup) -> Bool {
        let target = collapsedFrame(for: group)
        let tolerance: CGFloat = 3
        return group.members.allSatisfy { member in
            guard let frame = DesktopModel.shared.windows[member.id]?.frame else { return false }
            return abs(CGFloat(frame.x) - target.minX) <= tolerance
                && abs(CGFloat(frame.y) - target.minY) <= tolerance
                && abs(CGFloat(frame.w) - target.width) <= tolerance
                && abs(CGFloat(frame.h) - target.height) <= tolerance
        }
    }

    private func notifyGeometryChanged() {
        NotificationCenter.default.post(name: .liveTabGroupGeometryDidChange, object: self)
    }

    private func detachedFrame(
        current: CGRect,
        dropPoint: NSPoint,
        fallbackScreen: NSScreen
    ) -> CGRect {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(dropPoint) })
            ?? fallbackScreen
        let visible = screen.visibleFrame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? visible.maxY
        let visibleAX = CGRect(
            x: visible.minX,
            y: primaryHeight - visible.maxY,
            width: visible.width,
            height: visible.height
        )

        let width = min(max(480, current.width), visibleAX.width)
        let height = min(max(320, current.height), visibleAX.height)
        let desiredX = dropPoint.x - min(150, width * 0.22)
        let desiredY = primaryHeight - dropPoint.y - 18
        let x = min(max(desiredX, visibleAX.minX), visibleAX.maxX - width)
        let y = min(max(desiredY, visibleAX.minY), visibleAX.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func focus(_ member: LiveTabMember) {
        guard let entry = DesktopModel.shared.windows[member.id] else { return }
        expectedFocusedWindowID = member.id
        suppressFocusSyncUntil = Date().addingTimeInterval(0.8)
        NotificationCenter.default.post(name: .liveTabGroupWillFocusWindow, object: member.id)
        _ = WindowTiler.focusWindow(wid: entry.wid, pid: entry.pid)
        WindowTiler.highlightWindowById(wid: entry.wid)
    }

    private func normalizedName(_ provided: String?, members: [LiveTabMember]) -> String {
        if let provided {
            let trimmed = provided.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        var apps: [String] = []
        for member in members where !apps.contains(member.app) { apps.append(member.app) }
        switch apps.count {
        case 0: return "Live Tabs"
        case 1: return apps[0]
        case 2: return "\(apps[0]) + \(apps[1])"
        default: return "\(apps[0]) +\(apps.count - 1)"
        }
    }
}
