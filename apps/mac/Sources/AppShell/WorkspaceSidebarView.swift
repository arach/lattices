import AppKit
import SwiftUI

private final class WorkspaceSidebarPanel: NSPanel {
    var resizeAnimationDuration: TimeInterval = 0.24
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
        resizeAnimationDuration
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class WorkspaceSidebarContainerView: NSVisualEffectView {
    override var allowsVibrancy: Bool {
        true
    }
}

final class WorkspaceSidebarWindow {
    static let shared = WorkspaceSidebarWindow()

    private var panel: WorkspaceSidebarPanel?

    private let panelWidth: CGFloat = 282
    private let sideInset: CGFloat = 12
    private let topInset: CGFloat = 54
    private let bottomInset: CGFloat = 54

    var isVisible: Bool { (panel?.alphaValue ?? 0) > 0.5 }

    func warmUp() {
        guard panel == nil else { return }
        let screen = Self.mouseScreen()
        let panel = makePanel(on: screen)
        position(panel, on: screen, revealed: true)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        let screen = Self.mouseScreen()
        let panel = panel ?? makePanel(on: screen)
        self.panel = panel

        position(panel, on: screen, revealed: true)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        panel.makeKey()
        AppDelegate.updateActivationPolicy()
    }

    func dismiss() {
        guard let panel, isVisible else { return }
        let hiddenFrame = frame(for: Self.mouseScreen(), revealed: false)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(hiddenFrame, display: false)
        } completionHandler: {
            panel.ignoresMouseEvents = true
            AppDelegate.updateActivationPolicy()
        }
    }

    private func makePanel(on screen: NSScreen) -> WorkspaceSidebarPanel {
        let frame = frame(for: screen, revealed: false)
        let panel = WorkspaceSidebarPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onEscape = { [weak self] in self?.dismiss() }

        let view = WorkspaceSidebarView(
            onDismiss: { [weak self] in self?.dismiss() },
            onAfterPrimaryAction: { [weak self] in self?.dismiss() }
        )
        .preferredColorScheme(.dark)

        let container = WorkspaceSidebarContainerView()
        container.appearance = NSAppearance(named: .darkAqua)
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.isEmphasized = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 26
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        panel.contentView = container
        panel.title = "Workspace Sidebar"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.minSize = NSSize(width: 240, height: 380)
        panel.maxSize = NSSize(width: 360, height: screen.visibleFrame.height)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.sharingType = .readOnly
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func position(_ panel: NSWindow, on screen: NSScreen, revealed: Bool) {
        panel.setFrame(frame(for: screen, revealed: revealed), display: false)
    }

    private func frame(for screen: NSScreen, revealed: Bool) -> NSRect {
        let visible = screen.visibleFrame
        let width = panel?.frame.width ?? panelWidth
        let height = max(380, visible.height - topInset - bottomInset)
        let x = visible.minX + sideInset + (revealed ? 0 : -24)
        return NSRect(
            x: x,
            y: visible.minY + bottomInset,
            width: width,
            height: height
        )
    }

    private static func mouseScreen() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(location) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }
}

private enum WorkspaceSidebarScope: String, CaseIterable, Identifiable, Equatable {
    case live
    case projects
    case unmanaged

    var id: String { rawValue }

    var label: String {
        switch self {
        case .live: return "live"
        case .projects: return "projects"
        case .unmanaged: return "loose"
        }
    }
}

private enum WorkspaceSidebarTint: String, CaseIterable, Identifiable {
    case vapor
    case lagoon
    case ember
    case graphite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vapor: return "Vapor"
        case .lagoon: return "Lagoon"
        case .ember: return "Ember"
        case .graphite: return "Graphite"
        }
    }

    var accent: Color {
        switch self {
        case .vapor: return Color(red: 0.16, green: 0.86, blue: 0.61)
        case .lagoon: return Color(red: 0.24, green: 0.56, blue: 1.0)
        case .ember: return Color(red: 1.0, green: 0.46, blue: 0.24)
        case .graphite: return Color.white.opacity(0.58)
        }
    }

    var base: Color {
        switch self {
        case .vapor: return Color(red: 0.045, green: 0.060, blue: 0.055)
        case .lagoon: return Color(red: 0.038, green: 0.050, blue: 0.070)
        case .ember: return Color(red: 0.070, green: 0.050, blue: 0.042)
        case .graphite: return Color(red: 0.052, green: 0.054, blue: 0.058)
        }
    }
}

private enum WorkspaceSidebarDensity: String, CaseIterable, Identifiable {
    case airy
    case compact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .airy: return "Airy"
        case .compact: return "Compact"
        }
    }

    var icon: String {
        switch self {
        case .airy: return "rectangle.compress.vertical"
        case .compact: return "line.3.horizontal.decrease"
        }
    }

    var rowHeight: CGFloat {
        switch self {
        case .airy: return 38
        case .compact: return 31
        }
    }

    var selectedBottomPadding: CGFloat {
        switch self {
        case .airy: return 8
        case .compact: return 5
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
            return project.hasConfig ? "\(project.paneCount) panes" : "no config"
        case .orphan(let session):
            let commands = session.panes.map(\.currentCommand).filter { !$0.isEmpty }
            return commands.isEmpty ? "\(session.panes.count) panes" : commands.prefix(2).joined(separator: " · ")
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

    var statusLabel: String {
        switch self {
        case .project(let project): return project.isRunning ? "running" : "ready"
        case .orphan(let session): return session.attached ? "attached" : "tmux"
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
    let glyph: String?
    let symbolName: String?
    let tint: Color
    let foreground: Color
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
    @State private var isSearching = false
    @State private var isStyling = true
    @State private var visualTint: WorkspaceSidebarTint = .vapor
    @State private var density: WorkspaceSidebarDensity = .airy

    let onDismiss: () -> Void
    let onAfterPrimaryAction: () -> Void

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
        let source = items
        guard !query.isEmpty else { return source }
        return source.filter { item in
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
        ZStack(alignment: .topTrailing) {
            railContent
            closeButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(sidebarBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            visualTint.accent.opacity(0.12),
                            Color.black.opacity(0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
        .overlay(alignment: .topLeading) {
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .allowsHitTesting(false)
        }
        .onAppear {
            refresh()
            if selectedID == nil {
                selectedID = filteredItems.first?.id
            }
        }
        .onChange(of: scope) { _ in
            selectedID = filteredItems.first?.id
        }
        .onChange(of: filteredItems.map(\.id)) { _ in
            if let selectedID, filteredItems.contains(where: { $0.id == selectedID }) {
                return
            }
            selectedID = filteredItems.first?.id
        }
    }

    private var railContent: some View {
        VStack(spacing: 8) {
            topShelf

            if isSearching {
                searchField
                    .padding(.horizontal, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            sessionTools
                .padding(.top, 2)

            if isStyling {
                styleControls
                    .padding(.horizontal, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            sessionList
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var topShelf: some View {
        ZStack(alignment: .leading) {
            scopeMenu
                .padding(.leading, 4)

            SidebarAgentDock(items: dockItems)
                .frame(height: 54)
        }
        .padding(.top, 40)
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.46))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close")
        .padding(.top, 13)
        .padding(.trailing, 12)
    }

    private var scopeMenu: some View {
        Menu {
            ForEach(WorkspaceSidebarScope.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.16)) {
                        scope = item
                        query = ""
                    }
                } label: {
                    if item == scope {
                        Label(scopeTitle(for: item), systemImage: "checkmark")
                    } else {
                        Text(scopeTitle(for: item))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(scope.label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(Palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: 112)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.095))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Workspace scope")
    }

    private func scopeTitle(for item: WorkspaceSidebarScope) -> String {
        switch item {
        case .live: return "live (\(runningProjects.count + orphanSessions.count))"
        case .projects: return "projects (\(scanner.projects.count))"
        case .unmanaged: return "loose (\(orphanSessions.count))"
        }
    }

    private var dockItems: [SidebarDockItem] {
        [
            SidebarDockItem(
                id: "pi",
                label: "Pi",
                glyph: "π",
                symbolName: nil,
                tint: Color(red: 0.14, green: 0.73, blue: 0.58),
                foreground: .black.opacity(0.82),
                command: nil,
                action: { ScreenMapWindowController.shared.showPage(.pi) }
            ),
            SidebarDockItem(
                id: "claude",
                label: "Claude",
                glyph: "C",
                symbolName: nil,
                tint: Color(red: 0.92, green: 0.46, blue: 0.26),
                foreground: .white.opacity(0.92),
                command: "claude",
                action: { launchCommandInSelectedProject("claude") }
            ),
            SidebarDockItem(
                id: "codex",
                label: "Codex",
                glyph: nil,
                symbolName: "chevron.left.forwardslash.chevron.right",
                tint: Color(red: 0.29, green: 0.54, blue: 1.0),
                foreground: .white.opacity(0.92),
                command: "codex",
                action: { launchCommandInSelectedProject("codex") }
            ),
            SidebarDockItem(
                id: "palette",
                label: "Palette",
                glyph: nil,
                symbolName: "command",
                tint: Color.white.opacity(0.12),
                foreground: Palette.textDim,
                command: nil,
                action: { CommandPaletteWindow.shared.toggle() }
            ),
        ]
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Palette.textMuted)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .rounded))
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
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.20))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private var sessionTools: some View {
        HStack(spacing: 6) {
            Menu {
                Button {
                    tileSelected(.left)
                } label: {
                    Label("Tile Left", systemImage: "rectangle.leadinghalf.filled")
                }
                Button {
                    tileSelected(.right)
                } label: {
                    Label("Tile Right", systemImage: "rectangle.trailinghalf.filled")
                }
                Button {
                    tileSelected(.maximize)
                } label: {
                    Label("Maximize", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Divider()
                Button {
                    syncSelected()
                } label: {
                    Label("Sync", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    killSelected()
                } label: {
                    Label("Kill", systemImage: "xmark")
                }
            } label: {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Palette.textDim)
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help("Session actions")

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Palette.textDim)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("Refresh")

            Spacer(minLength: 0)

            Button {
                withAnimation(.snappy(duration: 0.16)) {
                    isStyling.toggle()
                }
            } label: {
                Image(systemName: isStyling ? "paintpalette.fill" : "paintpalette")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isStyling ? Palette.text : Palette.textDim)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("Style")

            Button {
                withAnimation(.snappy(duration: 0.16)) {
                    isSearching.toggle()
                    if !isSearching { query = "" }
                }
            } label: {
                Image(systemName: isSearching ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSearching ? Palette.text : Palette.textDim)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("Search")
        }
        .padding(.horizontal, 10)
    }

    private var styleControls: some View {
        HStack(spacing: 7) {
            ForEach(WorkspaceSidebarTint.allCases) { tint in
                Button {
                    withAnimation(.snappy(duration: 0.16)) {
                        visualTint = tint
                    }
                } label: {
                    Circle()
                        .fill(tint.accent)
                        .frame(width: visualTint == tint ? 16 : 13, height: visualTint == tint ? 16 : 13)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(visualTint == tint ? 0.72 : 0.20), lineWidth: 1)
                        )
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .help(tint.label)
            }

            Spacer(minLength: 0)

            ForEach(WorkspaceSidebarDensity.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.16)) {
                        density = item
                    }
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(density == item ? Palette.text : Palette.textMuted)
                        .frame(width: 24, height: 22)
                        .background(
                            Capsule(style: .continuous)
                                .fill(density == item ? Color.white.opacity(0.11) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(item.label)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.12))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.075), lineWidth: 0.5)
                )
        )
    }

    private var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 4) {
                if filteredItems.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredItems) { item in
                        workspaceRow(item)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func workspaceRow(_ item: WorkspaceSidebarItem) -> some View {
        Button {
            focusOrLaunch(item)
        } label: {
            WorkspaceSidebarRow(
                item: item,
                isSelected: selectedItem?.id == item.id,
                accent: visualTint.accent,
                density: density
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { selectedID = item.id })
        .contextMenu {
            Button(item.isRunning ? "Attach" : "Launch") {
                focusOrLaunch(item)
            }
            if item.isRunning {
                Button("Tile Left") { tile(item, .left) }
                Button("Tile Right") { tile(item, .right) }
                Button("Maximize") { tile(item, .maximize) }
            }
            if item.project != nil {
                Divider()
                Button("Sync") { sync(item) }
            }
            Divider()
            Button("Kill") { kill(item) }
        }
        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
    }

    private var emptyState: some View {
        Spacer()
            .frame(maxWidth: .infinity, minHeight: 260)
    }

    private var sidebarBackground: some View {
        ZStack {
            visualTint.base.opacity(0.80)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.035),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [
                    visualTint.accent.opacity(0.14),
                    Color.clear,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
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
        onAfterPrimaryAction()
    }

    private func launchCommandInSelectedProject(_ command: String) {
        guard let project = selectedItem?.project ?? runningProjects.first ?? scanner.projects.first else {
            prefs.terminal.launch(command: command, in: NSHomeDirectory())
            onAfterPrimaryAction()
            return
        }
        prefs.terminal.launch(command: command, in: project.path)
        onAfterPrimaryAction()
    }

    private func tileSelected(_ position: TilePosition) {
        guard let selectedItem else { return }
        tile(selectedItem, position)
    }

    private func syncSelected() {
        guard let selectedItem else { return }
        sync(selectedItem)
    }

    private func killSelected() {
        guard let selectedItem else { return }
        kill(selectedItem)
    }

    private func tile(_ item: WorkspaceSidebarItem, _ position: TilePosition) {
        guard item.isRunning else { return }
        WindowTiler.tile(session: item.sessionName, terminal: prefs.terminal, to: position)
        onAfterPrimaryAction()
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
    let accent: Color
    let density: WorkspaceSidebarDensity
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                statusDot

                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundColor(item.isRunning ? Palette.text : Palette.textDim)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Text(item.statusLabel)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(height: density.rowHeight)

            if isSelected {
                selectedDetails
                    .padding(.bottom, density.selectedBottomPadding)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(rowBackground)
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.16), value: isHovered)
        .animation(.snappy(duration: 0.16), value: isSelected)
        .accessibilityLabel(item.title)
    }

    private var statusDot: some View {
        Circle()
            .fill(item.isRunning ? accent : Palette.textMuted.opacity(0.45))
            .frame(width: isSelected ? 7 : 5, height: isSelected ? 7 : 5)
            .shadow(color: item.isRunning ? accent.opacity(0.42) : .clear, radius: 4, y: 1)
    }

    private var selectedDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Palette.textMuted)
                .lineLimit(1)

            if !item.paneLabels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(item.paneLabels.prefix(3).enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(Palette.textMuted)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.055)))
                    }
                }
            }
        }
        .padding(.leading, 13)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isSelected ? Color.white.opacity(0.13) : (isHovered ? Color.white.opacity(0.055) : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? accent.opacity(0.20) : Color.clear, lineWidth: 0.5)
            )
    }
}

private struct SidebarAgentDock: View {
    let items: [SidebarDockItem]
    @State private var hoverX: CGFloat?

    private let baseSize: CGFloat = 28
    private let maxSize: CGFloat = 44
    private let falloffSlots: CGFloat = 1.4
    private let restingSpacing: CGFloat = -14
    private let activeSpacing: CGFloat = 6
    private let trailingPadding: CGFloat = 7
    private let hoverBuffer: CGFloat = 24

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
        .frame(height: maxSize + 8)
        .frame(maxWidth: .infinity)
        .mask(edgeMask)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: hoverX)
    }

    private func dockIcon(_ item: SidebarDockItem, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(item.tint)
            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1.1)

            if let glyph = item.glyph {
                Text(glyph)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundColor(item.foreground)
            } else if let symbolName = item.symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundColor(item.foreground)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: Color.black.opacity(0.22), radius: 7, y: 3)
    }

    private var edgeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.18),
                .init(color: .black, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
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
            let factor = exp(-pow(distance / falloffSlots, 2))
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
