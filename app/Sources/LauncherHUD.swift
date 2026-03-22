import AppKit
import SwiftUI

// MARK: - LauncherHUD (singleton window controller)

final class LauncherHUD {
    static let shared = LauncherHUD()

    private var panel: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { dismiss() } else { show() }
    }

    func show() {
        guard panel == nil else { return }

        // Ensure projects are fresh
        ProjectScanner.shared.scan()

        let view = LauncherView(dismiss: { [weak self] in self?.dismiss() })
            .preferredColorScheme(.dark)

        let hosting = NSHostingView(rootView: view)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = false
        p.contentView = hosting

        // Center on mouse screen
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - 210
        let y = screenFrame.midY - 240 + (screenFrame.height * 0.08)
        p.setFrameOrigin(NSPoint(x: x, y: y))

        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 1.0
        }

        self.panel = p
        installMonitors()
    }

    func dismiss() {
        guard let p = panel else { return }
        removeMonitors()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 0
        }) { [weak self] in
            p.orderOut(nil)
            self?.panel = nil
        }
    }

    // MARK: - Event monitors

    private func installMonitors() {
        localMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.dismiss()
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Don't dismiss if clicking inside the panel
            guard let panel = self?.panel else { return }
            let loc = event.locationInWindow
            if !panel.frame.contains(NSEvent.mouseLocation) {
                self?.dismiss()
            }
        }
    }

    private func removeMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }
}

// MARK: - LauncherView

struct LauncherView: View {
    var dismiss: () -> Void

    @ObservedObject private var scanner = ProjectScanner.shared
    @ObservedObject private var tmux = TmuxModel.shared
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var hoveredId: String?

    private var filtered: [Project] {
        if query.isEmpty { return scanner.projects }
        let q = query.lowercased()
        return scanner.projects.filter {
            $0.name.lowercased().contains(q) ||
            ($0.paneSummary ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(Palette.textMuted)

                ZStack(alignment: .leading) {
                    if query.isEmpty {
                        Text("Launch a project...")
                            .font(Typo.mono(13))
                            .foregroundColor(Palette.textMuted)
                    }
                    TextField("", text: $query)
                        .font(Typo.mono(13))
                        .foregroundColor(Palette.text)
                        .textFieldStyle(.plain)
                        .onSubmit { launchSelected() }
                }

                if !query.isEmpty {
                    Button {
                        query = ""
                        selectedIndex = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Palette.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            // Project list
            if filtered.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 24))
                        .foregroundColor(Palette.textMuted)
                    Text(scanner.projects.isEmpty ? "No projects found" : "No matches")
                        .font(Typo.mono(12))
                        .foregroundColor(Palette.textMuted)
                    if scanner.projects.isEmpty {
                        Text("Add .lattices.json to your projects")
                            .font(Typo.mono(10))
                            .foregroundColor(Palette.textMuted.opacity(0.6))
                    }
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, project in
                                projectRow(project, index: index)
                                    .id(project.id)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                    }
                    .onChange(of: selectedIndex) { newVal in
                        if let project = filtered[safe: newVal] {
                            proxy.scrollTo(project.id, anchor: .center)
                        }
                    }
                }
            }

            Rectangle().fill(Palette.border).frame(height: 0.5)

            // Footer
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    keyBadge("↑↓")
                    Text("Navigate")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                }
                HStack(spacing: 4) {
                    keyBadge("↵")
                    Text("Launch")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                }
                HStack(spacing: 4) {
                    keyBadge("ESC")
                    Text("Close")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                }
                Spacer()
                Text("\(filtered.count) project\(filtered.count == 1 ? "" : "s")")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 420, height: 480)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Palette.borderLit, lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: query) { _ in selectedIndex = 0 }
    }

    // MARK: - Project row

    private func projectRow(_ project: Project, index: Int) -> some View {
        let isSelected = index == selectedIndex
        let isHovered = hoveredId == project.id

        return Button {
            launch(project)
        } label: {
            HStack(spacing: 10) {
                // Status dot
                Circle()
                    .fill(project.isRunning ? Palette.running : Palette.textMuted.opacity(0.3))
                    .frame(width: 7, height: 7)

                // Name + pane info
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(Typo.monoBold(12))
                        .foregroundColor(Palette.text)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if !project.paneSummary.isEmpty {
                            let summary = project.paneSummary
                            Text(summary)
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Status badge
                if project.isRunning {
                    Text("running")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.running)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.running.opacity(0.10))
                        )
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundColor(isSelected || isHovered ? Palette.text : Palette.textMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Palette.surfaceHov : (isHovered ? Palette.surface : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isSelected ? Palette.borderLit : Color.clear, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { over in hoveredId = over ? project.id : nil }
    }

    // MARK: - Actions

    private func moveSelection(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func launchSelected() {
        guard let project = filtered[safe: selectedIndex] else { return }
        launch(project)
    }

    private func launch(_ project: Project) {
        SessionManager.launch(project: project)
        dismiss()
    }

    private func keyBadge(_ key: String) -> some View {
        Text(key)
            .font(Typo.geistMonoBold(9))
            .foregroundColor(Palette.text)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
