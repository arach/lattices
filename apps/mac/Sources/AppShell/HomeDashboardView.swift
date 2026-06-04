import AppKit
import SwiftUI

struct HomeDashboardView: View {
    var onNavigate: ((AppPage) -> Void)? = nil

    @ObservedObject private var scanner = ProjectScanner.shared
    @ObservedObject private var piSession = PiChatSession.shared
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var permChecker = PermissionChecker.shared

    private var discoveredCount: Int { scanner.projects.count }
    private var runningCount: Int { scanner.projects.filter(\.isRunning).count }
    private var isStartingOut: Bool { discoveredCount == 0 && runningCount == 0 }

    var body: some View {
        VStack(spacing: 0) {
            hero

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            MainView(scanner: scanner, layout: .embedded)
        }
        .background(Palette.bg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            piSession.refreshBinaryAvailability()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isStartingOut ? "Start with your desktop" : "Lattices Home")
                        .font(Typo.heading(18))
                        .foregroundColor(Palette.text)

                    Text(isStartingOut
                         ? "See what is open, arrange it quickly, and give local agents useful workspace context."
                         : "Workspace status, layout, search, chat, and project launch in one place.")
                        .font(Typo.mono(11))
                        .foregroundColor(Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            if isStartingOut {
                firstRunPanel
            } else {
                workspaceSummary
            }

            HStack(spacing: 10) {
                homeActionCard(
                    title: "Chat",
                    subtitle: piSession.hasPiBinary
                        ? (piSession.needsProviderSetup || piSession.isAuthenticating
                            ? piSession.setupStatusSummary
                            : "Standalone conversation surface")
                        : "Install Pi to enable the assistant",
                    icon: "bubble.left.and.bubble.right",
                    tint: piSession.hasPiBinary ? Palette.text : Palette.kill
                ) {
                    if let onNavigate {
                        onNavigate(.pi)
                    } else {
                        AssistantAccess.show()
                    }
                }

                homeActionCard(
                    title: "Layout",
                    subtitle: "Arrange windows",
                    icon: "rectangle.3.group",
                    tint: Palette.running
                ) {
                    onNavigate?(.screenMap)
                }

                homeActionCard(
                    title: "Search",
                    subtitle: "Find workspace context",
                    icon: "magnifyingglass",
                    tint: Palette.detach
                ) {
                    onNavigate?(.desktopInventory)
                }

                homeActionCard(
                    title: "Activity",
                    subtitle: "Logs and diagnostics",
                    icon: "list.bullet.rectangle",
                    tint: Palette.textDim
                ) {
                    onNavigate?(.activity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [
                    Palette.running.opacity(0.08),
                    Color.black.opacity(0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var firstRunPanel: some View {
        HStack(alignment: .top, spacing: 10) {
            startStep(
                index: "1",
                title: "Map your windows",
                detail: "Open the visual layout surface for everything on screen.",
                status: permChecker.isGranted(.windowControl) ? "Ready" : "Optional",
                statusColor: permChecker.isGranted(.windowControl) ? Palette.running : Palette.textMuted,
                actionTitle: "Open Layout",
                action: { onNavigate?(.screenMap) }
            )

            startStep(
                index: "2",
                title: "Search context",
                detail: "Inspect visible apps, titles, and screen text when OCR is enabled.",
                status: permChecker.isGranted(.screenSearch) ? "Enabled" : "Optional",
                statusColor: permChecker.isGranted(.screenSearch) ? Palette.running : Palette.textMuted,
                actionTitle: "Open Search",
                action: { onNavigate?(.desktopInventory) }
            )

            startStep(
                index: "3",
                title: "Use the assistant",
                detail: "Chat with a local workspace-aware surface and route into app actions.",
                status: piSession.hasPiBinary ? "Ready" : "Setup",
                statusColor: piSession.hasPiBinary ? Palette.running : Palette.detach,
                actionTitle: "Open Chat",
                action: { onNavigate?(.pi) }
            )
        }
    }

    private var workspaceSummary: some View {
        HStack(spacing: 8) {
            summaryPill(icon: "folder", label: "\(discoveredCount) projects", color: Palette.textDim)
            summaryPill(icon: "play.circle", label: "\(runningCount) running", color: runningCount > 0 ? Palette.running : Palette.textMuted)
            if !prefs.scanRoot.isEmpty {
                summaryPill(icon: "location", label: abbreviatePath(prefs.scanRoot), color: Palette.textMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private func summaryPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(Typo.mono(10))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Palette.surface.opacity(0.65))
                .overlay(
                    Capsule().strokeBorder(Palette.border, lineWidth: 0.5)
                )
        )
    }

    private func startStep(
        index: String,
        title: String,
        detail: String,
        status: String,
        statusColor: Color,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(index)
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.bg)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Palette.textDim))

                Text(status)
                    .font(Typo.monoBold(9))
                    .foregroundColor(statusColor)

                Spacer(minLength: 0)
            }

            Text(title)
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.text)

            Text(detail)
                .font(Typo.mono(10))
                .foregroundColor(Palette.textMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(action: action) {
                Text(actionTitle)
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.text)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Palette.surfaceHov)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Palette.borderLit, lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Palette.surface.opacity(0.68))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
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

                    Circle()
                        .fill(tint.opacity(0.85))
                        .frame(width: 6, height: 6)
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

    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
