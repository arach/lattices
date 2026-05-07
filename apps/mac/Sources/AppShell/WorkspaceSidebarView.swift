import AppKit
import SwiftUI

final class WorkspaceSidebarWindow {
    static let shared = WorkspaceSidebarWindow()

    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let screen = Self.mouseScreen()
        let visible = screen.visibleFrame
        let height = min(max(560, visible.height - 32), 760)
        let width: CGFloat = 360

        let view = WorkspaceSidebarView { [weak self] in
            self?.dismiss()
        }
        .preferredColorScheme(.dark)

        let panel = OverlayPanelShell.makePanel(
            config: .init(
                size: NSSize(width: width, height: height),
                styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                title: "Workspace Sidebar",
                titleVisible: .hidden,
                titlebarAppearsTransparent: true,
                background: .material(.hudWindow),
                cornerRadius: 18,
                level: .floating,
                hidesOnDeactivate: false,
                isMovableByWindowBackground: true,
                minSize: NSSize(width: 320, height: 420),
                maxSize: NSSize(width: 460, height: 980),
                activatesOnMouseDown: true,
                appearance: NSAppearance(named: .darkAqua)
            ),
            rootView: view
        )

        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        position(panel, on: screen)
        OverlayPanelShell.present(panel)
        self.panel = panel
        AppDelegate.updateActivationPolicy()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        AppDelegate.updateActivationPolicy()
    }

    private static func mouseScreen() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(location) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    private func position(_ panel: NSWindow, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.minX + 14,
            y: visible.maxY - size.height - 14
        ))
    }
}

private enum WorkspaceSidebarScope: String, CaseIterable, Identifiable, Equatable {
    case live
    case projects
    case unmanaged

    var id: String { rawValue }

    var label: String {
        switch self {
        case .live: return "Live"
        case .projects: return "Projects"
        case .unmanaged: return "Loose"
        }
    }
}

private enum WorkspaceSidebarItem: Identifiable {
    case project(Project)
    case orphan(TmuxSession)

    var id: String {
        switch self {
        case .project(let project): return "project:\(project.id)"
        case .orphan(let session): return "orphan:\(session.name)"
        }
    }

    var title: String {
        switch self {
        case .project(let project): return project.name
        case .orphan(let session): return session.name
        }
    }

    var subtitle: String {
        switch self {
        case .project(let project):
            if !project.paneSummary.isEmpty { return project.paneSummary }
            if let command = project.devCommand, !command.isEmpty { return command }
            return project.hasConfig ? "\(project.paneCount) panes" : "No config"
        case .orphan(let session):
            let commands = session.panes.map(\.currentCommand).filter { !$0.isEmpty }
            return commands.isEmpty ? "\(session.panes.count) panes" : commands.prefix(3).joined(separator: " / ")
        }
    }

    var sessionName: String {
        switch self {
        case .project(let project): return project.sessionName
        case .orphan(let session): return session.name
        }
    }

    var isRunning: Bool {
        switch self {
        case .project(let project): return project.isRunning
        case .orphan: return true
        }
    }

    var isAttached: Bool {
        switch self {
        case .project: return false
        case .orphan(let session): return session.attached
        }
    }

    var path: String? {
        switch self {
        case .project(let project): return project.path
        case .orphan: return nil
        }
    }

    var paneLabels: [String] {
        switch self {
        case .project(let project): return project.paneNames
        case .orphan(let session):
            return session.panes.map { pane in
                pane.windowName.isEmpty ? pane.currentCommand : pane.windowName
            }
        }
    }

    var project: Project? {
        if case .project(let project) = self { return project }
        return nil
    }
}

private struct SidebarDockItem: Identifiable {
    let id: String
    let label: String
    let icon: String
    let tint: Color
    let command: String?
    let action: () -> Void
}

struct WorkspaceSidebarView: View {
    @ObservedObject private var scanner = ProjectScanner.shared
    @ObservedObject private var tmux = TmuxModel.shared
    @ObservedObject private var inventory = InventoryManager.shared
    @StateObject private var prefs = Preferences.shared

    @State private var scope: WorkspaceSidebarScope = .live
    @State private var query = ""
    @State private var selectedID: String?

    let onDismiss: () -> Void

    private var managedSessionNames: Set<String> {
        Set(scanner.projects.map(\.sessionName))
    }

    private var orphanSessions: [TmuxSession] {
        let sessions = inventory.allSessions.isEmpty ? tmux.sessions : inventory.allSessions
        return sessions.filter { !managedSessionNames.contains($0.name) }
    }

    private var runningProjects: [Project] {
        scanner.projects.filter(\.isRunning)
    }

    private var items: [WorkspaceSidebarItem] {
        switch scope {
        case .live:
            return scanner.projects.filter(\.isRunning).map(WorkspaceSidebarItem.project)
                + orphanSessions.map(WorkspaceSidebarItem.orphan)
        case .projects:
            return scanner.projects.map(WorkspaceSidebarItem.project)
        case .unmanaged:
            return orphanSessions.map(WorkspaceSidebarItem.orphan)
        }
    }

    private var filteredItems: [WorkspaceSidebarItem] {
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(query)
                || item.subtitle.localizedCaseInsensitiveContains(query)
                || item.sessionName.localizedCaseInsensitiveContains(query)
                || (item.path?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var selectedItem: WorkspaceSidebarItem? {
        if let selectedID, let match = filteredItems.first(where: { $0.id == selectedID }) {
            return match
        }
        return filteredItems.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            DividerLine()

            VStack(spacing: 10) {
                dock
                searchField
                scopeControl
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            DividerLine()

            sessionList

            DividerLine()

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Palette.bg.opacity(0.78)
                LinearGradient(
                    colors: [Color.white.opacity(0.055), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .onAppear {
            refresh()
            if selectedID == nil {
                selectedID = filteredItems.first?.id
            }
        }
        .onChange(of: scope) { _ in
            selectedID = filteredItems.first?.id
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Palette.running.opacity(0.15))
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.running)
            }
            .frame(width: 30, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Workspace")
                    .font(Typo.geistMonoBold(12))
                    .foregroundColor(Palette.text)
                Text("\(runningProjects.count) live · \(tmux.sessions.count) tmux")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
            }

            Spacer()

            headerIcon("arrow.clockwise", help: "Refresh", action: refresh)
            headerIcon("xmark", help: "Close", action: onDismiss)
        }
        .padding(.horizontal, 13)
        .padding(.top, 14)
        .padding(.bottom, 11)
    }

    private var dock: some View {
        SidebarAgentDock(items: dockItems)
            .frame(height: 52)
    }

    private var dockItems: [SidebarDockItem] {
        [
            SidebarDockItem(
                id: "lattices",
                label: "Launch selected",
                icon: "square.grid.2x2",
                tint: Palette.running,
                command: nil,
                action: launchSelectedProject
            ),
            SidebarDockItem(
                id: "claude",
                label: "Claude",
                icon: "sparkles",
                tint: Color(red: 0.95, green: 0.55, blue: 0.34),
                command: "claude",
                action: { launchCommandInSelectedProject("claude") }
            ),
            SidebarDockItem(
                id: "codex",
                label: "Codex",
                icon: "chevron.left.forwardslash.chevron.right",
                tint: Color(red: 0.38, green: 0.62, blue: 1.0),
                command: "codex",
                action: { launchCommandInSelectedProject("codex") }
            ),
            SidebarDockItem(
                id: "pi",
                label: "Assistant",
                icon: "bubble.left.and.bubble.right",
                tint: Palette.detach,
                command: nil,
                action: { ScreenMapWindowController.shared.showPage(.pi) }
            ),
            SidebarDockItem(
                id: "palette",
                label: "Command palette",
                icon: "command",
                tint: Palette.textDim,
                command: nil,
                action: { CommandPaletteWindow.shared.toggle() }
            ),
        ]
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Palette.textMuted)
            TextField("Search workspaces", text: $query)
                .textFieldStyle(.plain)
                .font(Typo.body(12))
                .foregroundColor(Palette.text)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Palette.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        )
    }

    private var scopeControl: some View {
        HStack(spacing: 5) {
            ForEach(WorkspaceSidebarScope.allCases) { item in
                scopeButton(item)
            }
        }
    }

    private func scopeButton(_ item: WorkspaceSidebarScope) -> some View {
        let isActive = scope == item
        let count: Int = {
            switch item {
            case .live: return runningProjects.count + orphanSessions.count
            case .projects: return scanner.projects.count
            case .unmanaged: return orphanSessions.count
            }
        }()

        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                scope = item
            }
        } label: {
            HStack(spacing: 4) {
                Text(item.label)
                    .font(Typo.monoBold(9))
                Text("\(count)")
                    .font(Typo.mono(8))
                    .foregroundColor(isActive ? Palette.text : Palette.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundColor(isActive ? Palette.text : Palette.textDim)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? Color.white.opacity(0.10) : Color.white.opacity(0.035))
            )
        }
        .buttonStyle(.plain)
    }

    private var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 6) {
                if filteredItems.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredItems) { item in
                        WorkspaceSidebarRow(
                            item: item,
                            isSelected: selectedItem?.id == item.id,
                            onPrimary: { focusOrLaunch(item) },
                            onSelect: { selectedID = item.id },
                            onTile: { tile(item, .right) },
                            onSync: { sync(item) },
                            onKill: { kill(item) }
                        )
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 18, weight: .light))
                .foregroundColor(Palette.textMuted)
            Text("No matching workspace")
                .font(Typo.mono(10))
                .foregroundColor(Palette.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerMetric("Live", runningProjects.count)
            footerMetric("Loose", orphanSessions.count)
            Spacer()
            Button {
                ScreenMapWindowController.shared.showPage(.home)
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Palette.textMuted)
                    .frame(width: 26, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.045))
                    )
            }
            .buttonStyle(.plain)
            .help("Open full workspace window")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private func footerMetric(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Typo.mono(8))
                .foregroundColor(Palette.textMuted)
            Text("\(value)")
                .font(Typo.monoBold(9))
                .foregroundColor(Palette.textDim)
        }
    }

    private func headerIcon(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Palette.textMuted)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.045))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func refresh() {
        scanner.updateRoot(prefs.scanRoot)
        scanner.scan()
        scanner.refreshStatus()
        tmux.poll()
        inventory.refresh()
    }

    private func delayedRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refresh()
        }
    }

    private func focusOrLaunch(_ item: WorkspaceSidebarItem) {
        selectedID = item.id
        switch item {
        case .project(let project):
            SessionManager.launch(project: project)
        case .orphan(let session):
            prefs.terminal.focusOrAttach(session: session.name)
        }
        delayedRefresh()
    }

    private func launchSelectedProject() {
        guard let project = selectedItem?.project ?? runningProjects.first ?? scanner.projects.first else {
            CliActionLauncher.launchProjectInTerminal()
            return
        }
        SessionManager.launch(project: project)
        delayedRefresh()
    }

    private func launchCommandInSelectedProject(_ command: String) {
        guard let project = selectedItem?.project ?? scanner.projects.first else {
            prefs.terminal.launch(command: command, in: NSHomeDirectory())
            return
        }
        prefs.terminal.launch(command: command, in: project.path)
    }

    private func tile(_ item: WorkspaceSidebarItem, _ position: TilePosition) {
        guard item.isRunning else { return }
        WindowTiler.tile(session: item.sessionName, terminal: prefs.terminal, to: position)
    }

    private func sync(_ item: WorkspaceSidebarItem) {
        guard let project = item.project else { return }
        SessionManager.sync(project: project)
        delayedRefresh()
    }

    private func kill(_ item: WorkspaceSidebarItem) {
        switch item {
        case .project(let project):
            SessionManager.kill(project: project)
        case .orphan(let session):
            SessionManager.killByName(session.name)
        }
        delayedRefresh()
    }
}

private struct WorkspaceSidebarRow: View {
    let item: WorkspaceSidebarItem
    let isSelected: Bool
    let onPrimary: () -> Void
    let onSelect: () -> Void
    let onTile: () -> Void
    let onSync: () -> Void
    let onKill: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onPrimary) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(item.isRunning ? Palette.running : Palette.borderLit)
                        .frame(width: 7, height: 7)

                    Text(item.title)
                        .font(Typo.heading(13))
                        .foregroundColor(item.isRunning ? Palette.text : Palette.textDim)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if item.isRunning {
                        Image(systemName: item.isAttached ? "link" : "bolt.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Palette.running.opacity(0.85))
                    }
                }

                Text(item.subtitle)
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
                    .lineLimit(1)

                if isSelected {
                    selectedDetails
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .contextMenu {
            Button("Select") { onSelect() }
            if item.isRunning {
                Button("Tile Right") { onTile() }
            }
            if item.project != nil {
                Button("Sync") { onSync() }
            }
            Divider()
            Button("Kill") { onKill() }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    private var selectedDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let path = item.path {
                Text(path)
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
                    .lineLimit(1)
            }

            if !item.paneLabels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(item.paneLabels.prefix(3).enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(Typo.mono(8))
                            .foregroundColor(Palette.textMuted)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.045)))
                    }
                    if item.paneLabels.count > 3 {
                        Text("+\(item.paneLabels.count - 3)")
                            .font(Typo.mono(8))
                            .foregroundColor(Palette.textMuted)
                    }
                }
            }

            HStack(spacing: 6) {
                rowAction(icon: item.isRunning ? "arrow.up.forward.app" : "play.fill", help: item.isRunning ? "Attach" : "Launch", action: onPrimary)
                rowAction(icon: "rectangle.split.2x1", help: "Tile right", action: onTile)
                    .disabled(!item.isRunning)
                rowAction(icon: "arrow.clockwise", help: "Sync", action: onSync)
                    .disabled(item.project == nil)
                rowAction(icon: "xmark", help: "Kill", action: onKill)
                    .foregroundColor(Palette.kill)
            }
        }
        .padding(.top, 2)
    }

    private func rowAction(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Palette.textDim)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.055))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 13)
            .fill(isSelected ? Color.white.opacity(0.105) : (isHovered ? Color.white.opacity(0.055) : Color.white.opacity(0.025)))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(isSelected ? Palette.borderLit : Palette.border.opacity(isHovered ? 1 : 0.45), lineWidth: 0.5)
            )
    }
}

private struct SidebarAgentDock: View {
    let items: [SidebarDockItem]
    @State private var hoverX: CGFloat?

    private let baseSize: CGFloat = 30
    private let maxSize: CGFloat = 46
    private let restingSpacing: CGFloat = -12
    private let activeSpacing: CGFloat = 7
    private let trailingPadding: CGFloat = 4
    private let hoverBuffer: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let layout = computeLayout(containerWidth: geo.size.width)

            ZStack {
                ForEach(Array(items.enumerated()).reversed(), id: \.element.id) { index, item in
                    Button(action: item.action) {
                        dockIcon(item, size: layout.sizes[index])
                    }
                    .buttonStyle(.plain)
                    .help(item.command.map { "\(item.label): \($0)" } ?? item.label)
                    .position(x: layout.centers[index], y: geo.size.height / 2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    let bounds = clusterBounds(containerWidth: geo.size.width)
                    if location.x < bounds.left - hoverBuffer || location.x > bounds.right + hoverBuffer {
                        hoverX = nil
                    } else {
                        hoverX = location.x
                    }
                case .ended:
                    hoverX = nil
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: hoverX)
    }

    private func dockIcon(_ item: SidebarDockItem, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(item.tint.opacity(0.20))
            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            Image(systemName: item.icon)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundColor(item.tint)
        }
        .frame(width: size, height: size)
        .shadow(color: item.tint.opacity(0.18), radius: 8, y: 3)
    }

    private func clusterBounds(containerWidth: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let restingStride = baseSize + restingSpacing
        let clusterWidth = baseSize + CGFloat(items.count - 1) * restingStride
        let right = containerWidth - trailingPadding
        return (right - clusterWidth, right)
    }

    private func computeLayout(containerWidth: CGFloat) -> (sizes: [CGFloat], centers: [CGFloat]) {
        let n = items.count
        guard n > 0 else { return ([], []) }

        let bounds = clusterBounds(containerWidth: containerWidth)
        let restingStride = baseSize + restingSpacing

        guard let hoverX else {
            let sizes = Array(repeating: baseSize, count: n)
            let centers = (0..<n).map { index in
                bounds.left + baseSize / 2 + CGFloat(index) * restingStride
            }
            return (sizes, centers)
        }

        let clampedX = max(bounds.left, min(bounds.right, hoverX))
        let restingClusterWidth = max(bounds.right - bounds.left, 1)
        let focusF = ((clampedX - bounds.left) / restingClusterWidth) * CGFloat(n - 1)

        let sizes = (0..<n).map { index -> CGFloat in
            let distance = abs(CGFloat(index) - focusF)
            let factor = exp(-pow(distance / 1.35, 2))
            return baseSize + (maxSize - baseSize) * factor
        }

        var localCenters: [CGFloat] = []
        var cursor: CGFloat = 0
        for index in 0..<n {
            localCenters.append(cursor + sizes[index] / 2)
            cursor += sizes[index] + activeSpacing
        }

        let lo = Int(floor(focusF))
        let hi = min(lo + 1, n - 1)
        let frac = focusF - CGFloat(lo)
        let focusCenter = localCenters[lo] * (1 - frac) + localCenters[hi] * frac
        let focusRight =
            (localCenters[lo] + sizes[lo] / 2) * (1 - frac)
            + (localCenters[hi] + sizes[hi] / 2) * frac
        let maxShift = (containerWidth - trailingPadding) - focusRight
        let shift = min(clampedX - focusCenter, maxShift)
        return (sizes, localCenters.map { $0 + shift })
    }
}

private struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 0.5)
    }
}
