import AppKit
import SwiftUI

struct HomeDashboardView: View {
    var onNavigate: ((AppPage) -> Void)? = nil

    @ObservedObject private var piSession = WorkspaceAssistantSession.shared
    @ObservedObject private var desktop = DesktopModel.shared

    var body: some View {
        VStack(spacing: 0) {
            hero

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            activeWindowsSection
        }
        .background(Palette.bg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            piSession.refreshBinaryAvailability()
            desktop.start()        // guarded — no-op if already polling
            desktop.forcePoll()    // fresh snapshot on open
        }
    }

    // MARK: - Hero (title + quick actions)

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lattices Home")
                    .font(Typo.heading(18))
                    .foregroundColor(Palette.text)

                Text("Layout, search, chat, and screen context in one place.")
                    .font(Typo.mono(11))
                    .foregroundColor(Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                homeActionCard(
                    title: "Chat",
                    subtitle: piSession.hasPiBinary
                        ? (piSession.needsProviderSetup || piSession.isAuthenticating
                            ? piSession.setupStatusSummary
                            : "Workspace assistant")
                        : "Install Pi to enable the assistant",
                    icon: "bubble.left.and.bubble.right",
                    tint: piSession.hasPiBinary ? Palette.textDim : Palette.kill
                ) {
                    if let onNavigate { onNavigate(.pi) } else { AssistantAccess.show() }
                }

                homeActionCard(
                    title: "Studio",
                    subtitle: "Arrange windows & layers",
                    icon: "rectangle.3.group",
                    tint: Palette.textDim
                ) { onNavigate?(.screenMap) }

                homeActionCard(
                    title: "Search",
                    subtitle: "Find workspace context",
                    icon: "magnifyingglass",
                    tint: Palette.textDim
                ) { onNavigate?(.desktopInventory) }

                homeActionCard(
                    title: "Runs",
                    subtitle: "Review artifacts",
                    icon: "record.circle",
                    tint: Palette.running
                ) { onNavigate?(.runs) }

                homeActionCard(
                    title: "Activity",
                    subtitle: "Logs and diagnostics",
                    icon: "list.bullet.rectangle",
                    tint: Palette.textDim
                ) { onNavigate?(.activity) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [Palette.running.opacity(0.08), Color.black.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func homeActionCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tint)
                    Spacer()
                    Circle().fill(tint.opacity(0.85)).frame(width: 6, height: 6)
                }
                Text(title)
                    .font(Typo.monoBold(12))
                    .foregroundColor(Palette.text)
                Text(subtitle)
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.surface.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(tint.opacity(0.18), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Active windows snapshot

    /// On-screen windows, most-recently-interacted first, then frontmost order.
    private var activeWindows: [WindowEntry] {
        let focusedWindowID = desktop.focusedWindowID
        return desktop.allWindows()
            .filter { $0.isOnScreen && !$0.title.isEmpty }
            .sorted { a, b in
                if let focusedWindowID, a.wid != b.wid {
                    if a.wid == focusedWindowID { return true }
                    if b.wid == focusedWindowID { return false }
                }
                let da = desktop.lastInteractionDate(for: a.wid)
                let db = desktop.lastInteractionDate(for: b.wid)
                switch (da, db) {
                case let (.some(x), .some(y)):
                    if x != y { return x > y }
                    return a.zIndex < b.zIndex
                case (.some, .none):           return true
                case (.none, .some):           return false
                case (.none, .none):           return a.zIndex < b.zIndex
                }
            }
    }

    private var activeWindowsSection: some View {
        let windows = activeWindows
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Active windows")
                    .font(Typo.monoBold(11))
                    .foregroundColor(Palette.textDim)
                Text("\(windows.count)")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
                Spacer()
                Button { onNavigate?(.desktopInventory) } label: {
                    Text("Search all")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if windows.isEmpty {
                emptyWindows
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(windows.prefix(14), id: \.wid) { window in
                            WindowSnapshotRow(
                                window: window,
                                lastActive: desktop.lastInteractionDate(for: window.wid)
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyWindows: some View {
        VStack(spacing: 6) {
            Image(systemName: "macwindow")
                .font(.system(size: 20, weight: .light))
                .foregroundColor(Palette.textMuted)
            Text("No active windows on screen")
                .font(Typo.mono(11))
                .foregroundColor(Palette.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }

    private func appIcon(pid: Int32) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}

// MARK: - Window snapshot row

/// One window in the Home "Active windows" snapshot. Left side is identity
/// (icon + app + title); the trailing area shows region · size · last-active,
/// and crossfades to quick actions (focus / tile left / tile right) on hover.
/// The trailing area is a fixed-width ZStack so the swap never shifts the row.
private struct WindowSnapshotRow: View {
    let window: WindowEntry
    let lastActive: Date?

    @State private var hovering = false

    var body: some View {
        Button(action: focus) {
            HStack(spacing: 10) {
                icon

                Text(window.app)
                    .font(Typo.monoBold(11))
                    .foregroundColor(Palette.text)
                    .lineLimit(1)
                    .layoutPriority(1)

                if !window.title.isEmpty, window.title != window.app {
                    Text(window.title)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                actions
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
                    .animation(.easeOut(duration: 0.12), value: hovering)

                metadata
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.05 : 0.02))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var icon: some View {
        if let img = NSRunningApplication(processIdentifier: window.pid)?.icon {
            Image(nsImage: img).resizable().frame(width: 18, height: 18)
        } else {
            RoundedRectangle(cornerRadius: 4).fill(Palette.surface).frame(width: 18, height: 18)
        }
    }

    private var metadata: some View {
        HStack(spacing: 5) {
            Text(regionLabel)
                .foregroundColor(Palette.textMuted)
            if let t = timeAgo {
                Text("·").foregroundColor(Palette.textMuted)
                Text(t).foregroundColor(Palette.textDim)
            }
        }
        .font(Typo.mono(9))
    }

    private var actions: some View {
        HStack(spacing: 6) {
            actionButton("arrow.up.left.and.arrow.down.right", "Focus", action: focus)
            actionButton("rectangle.lefthalf.filled", "Tile left") { tile("left") }
            actionButton("rectangle.righthalf.filled", "Tile right") { tile("right") }
        }
    }

    private func actionButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.textMuted)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func focus() {
        _ = WindowTiler.focusWindow(wid: window.wid, pid: window.pid)
        WindowTiler.highlightWindowById(wid: window.wid)
    }

    private func tile(_ position: String) {
        guard let placement = PlacementSpec(string: position) else { return }
        _ = WindowTiler.focusWindow(wid: window.wid, pid: window.pid)
        WindowTiler.tileWindowById(wid: window.wid, pid: window.pid, to: placement)
        WindowTiler.highlightWindowById(wid: window.wid)
    }

    private var sizeLabel: String { "\(Int(window.frame.w))×\(Int(window.frame.h))" }

    /// Coarse horizontal region from the window's centre across the full desktop.
    private var regionLabel: String {
        let centerX = window.frame.x + window.frame.w / 2
        let totalWidth = NSScreen.screens.map(\.frame.maxX).max()
            ?? NSScreen.main?.frame.width ?? 1
        let frac = totalWidth > 0 ? centerX / totalWidth : 0.5
        if frac < 0.34 { return "Left" }
        if frac < 0.66 { return "Center" }
        return "Right"
    }

    private var timeAgo: String? {
        guard let lastActive else { return nil }
        let s = Date().timeIntervalSince(lastActive)
        if s < 45 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }
}
