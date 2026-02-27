import SwiftUI

struct TabGroupRow: View {
    let group: TabGroup
    @ObservedObject var workspace: WorkspaceManager

    @State private var isHovered = false
    @State private var isExpanded = false

    private var isRunning: Bool { workspace.isGroupRunning(group) }

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 10) {
                // Status bar
                RoundedRectangle(cornerRadius: 1)
                    .fill(isRunning ? Palette.running : Palette.border)
                    .frame(width: 3, height: 32)

                // Expand chevron
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Palette.textMuted)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(group.label)
                            .font(Typo.heading(13))
                            .foregroundColor(Palette.text)
                            .lineLimit(1)

                        Text("\(group.tabs.count) tabs")
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.textMuted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Palette.surface)
                            )
                    }

                    Text(group.tabs.map { $0.label ?? ($0.path as NSString).lastPathComponent }.joined(separator: " \u{00B7} "))
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                // Actions
                HStack(spacing: 4) {
                    if isRunning {
                        Button {
                            workspace.killGroup(group)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                ProjectScanner.shared.refreshStatus()
                            }
                        } label: {
                            Text("Kill")
                                .angularButton(Palette.kill, filled: false)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        if isRunning {
                            // Focus the first tab's session
                            if let firstTab = group.tabs.first {
                                let session = WorkspaceManager.sessionName(for: firstTab.path)
                                let terminal = Preferences.shared.terminal
                                terminal.focusOrAttach(session: session)
                            }
                        } else {
                            workspace.launchGroup(group)
                        }
                    } label: {
                        Text(isRunning ? "Attach" : "Launch")
                            .angularButton(isRunning ? Palette.running : Palette.launch)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassCard(hovered: isHovered)

            // Expanded tab list
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(Array(group.tabs.enumerated()), id: \.offset) { idx, tab in
                        tabRow(tab: tab, index: idx)
                    }
                }
                .padding(.leading, 36)
                .padding(.trailing, 10)
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            if isRunning {
                Button("Attach") {
                    if let firstTab = group.tabs.first {
                        let session = WorkspaceManager.sessionName(for: firstTab.path)
                        let terminal = Preferences.shared.terminal
                        terminal.focusOrAttach(session: session)
                    }
                }
                Divider()
                ForEach(Array(group.tabs.enumerated()), id: \.offset) { idx, tab in
                    Button("Go to: \(tab.label ?? (tab.path as NSString).lastPathComponent)") {
                        workspace.focusTab(group: group, tabIndex: idx)
                    }
                }
                Divider()
                Button("Kill Group") {
                    workspace.killGroup(group)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        ProjectScanner.shared.refreshStatus()
                    }
                }
            } else {
                Button("Launch") {
                    workspace.launchGroup(group)
                }
            }
        }
    }

    private func tabRow(tab: TabGroupTab, index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: 9))
                .foregroundColor(isRunning ? Palette.running.opacity(0.7) : Palette.textMuted)

            Text(tab.label ?? (tab.path as NSString).lastPathComponent)
                .font(Typo.mono(11))
                .foregroundColor(Palette.text)
                .lineLimit(1)

            Spacer()

            if isRunning {
                Button {
                    workspace.focusTab(group: group, tabIndex: index)
                } label: {
                    Text("Go")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                        .padding(.horizontal, 6)
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
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
