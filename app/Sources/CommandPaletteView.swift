import SwiftUI
import AppKit

struct CommandPaletteView: View {
    let commands: [PaletteCommand]
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var eventMonitor: Any?
    @FocusState private var isSearchFocused: Bool

    private var filtered: [PaletteCommand] {
        if query.isEmpty { return commands }
        return commands
            .map { ($0, $0.matchScore(query: query)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Group commands by category (only used when query is empty)
    private var grouped: [(PaletteCommand.Category, [PaletteCommand])] {
        let items = filtered
        var result: [(PaletteCommand.Category, [PaletteCommand])] = []
        for cat in PaletteCommand.Category.allCases {
            let group = items.filter { $0.category == cat }
            if !group.isEmpty {
                result.append((cat, group))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            searchField

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    if query.isEmpty {
                        groupedList
                    } else {
                        flatList
                    }
                }
                .onChange(of: selectedIndex) { idx in
                    let items = filtered
                    if idx >= 0 && idx < items.count {
                        proxy.scrollTo(items[idx].id, anchor: .center)
                    }
                }
            }
            .frame(minHeight: 280, maxHeight: 360)

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            // Footer hints
            footer
        }
        .frame(width: 540)
        .background(Palette.bg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.borderLit, lineWidth: 0.5)
        )
        .onAppear {
            installKeyHandler()
            // Delay focus slightly to ensure the panel is key
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onDisappear { removeKeyHandler() }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Palette.textMuted)
                .font(.system(size: 14))

            TextField("Search commands...", text: $query)
                .textFieldStyle(.plain)
                .font(Typo.body(14))
                .foregroundColor(Palette.text)
                .focused($isSearchFocused)
                .onChange(of: query) { _ in selectedIndex = 0 }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Grouped List (empty query)

    private var groupedList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(grouped, id: \.0) { category, items in
                sectionHeader(category)
                ForEach(items) { cmd in
                    let idx = flatIndex(of: cmd)
                    commandRow(cmd, isSelected: idx == selectedIndex)
                        .id(cmd.id)
                        .onTapGesture { executeCommand(cmd) }
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Flat List (with query)

    private var flatList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, cmd in
                commandRow(cmd, isSelected: idx == selectedIndex)
                    .id(cmd.id)
                    .onTapGesture { executeCommand(cmd) }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Section Header

    private func sectionHeader(_ category: PaletteCommand.Category) -> some View {
        HStack(spacing: 5) {
            Image(systemName: category.icon)
                .font(.system(size: 9))
            Text(category.rawValue.uppercased())
                .font(Typo.mono(9))
        }
        .foregroundColor(Palette.textMuted)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Command Row

    private func commandRow(_ cmd: PaletteCommand, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: cmd.icon)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? Palette.text : Palette.textDim)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(cmd.title)
                        .font(Typo.body(13))
                        .foregroundColor(isSelected ? Palette.text : Palette.text.opacity(0.85))
                        .lineLimit(1)

                    if let badge = cmd.badge {
                        Text(badge)
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.running)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Palette.running.opacity(0.12))
                            )
                    }
                }

                Text(cmd.subtitle)
                    .font(Typo.caption(10))
                    .foregroundColor(Palette.textMuted)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Palette.surface : Color.clear)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            footerHint(keys: ["\u{2191}\u{2193}"], label: "navigate")
            footerHint(keys: ["\u{21A9}"], label: "select")
            footerHint(keys: ["esc"], label: "close")
            Spacer()
            Text("\(filtered.count) command\(filtered.count == 1 ? "" : "s")")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.surface.opacity(0.4))
    }

    private func footerHint(keys: [String], label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.text)
                    .padding(.horizontal, 4)
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
            Text(label)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
    }

    // MARK: - Keyboard Navigation

    private func installKeyHandler() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isSearchActive = isSearchFocused

            switch Int(event.keyCode) {
            case 125: // Down arrow
                moveDown()
                return nil
            case 126: // Up arrow
                moveUp()
                return nil
            case 38 where !isSearchActive: // j (vim down) — only when not typing
                moveDown()
                return nil
            case 40 where !isSearchActive: // k (vim up) — only when not typing
                moveUp()
                return nil
            case 36: // Return
                let items = filtered
                if selectedIndex >= 0 && selectedIndex < items.count {
                    executeCommand(items[selectedIndex])
                }
                return nil
            case 53: // Escape
                onDismiss()
                return nil
            default:
                return event
            }
        }
    }

    private func moveDown() {
        let count = filtered.count
        if count > 0 {
            selectedIndex = min(selectedIndex + 1, count - 1)
        }
    }

    private func moveUp() {
        selectedIndex = max(selectedIndex - 1, 0)
    }

    private func removeKeyHandler() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Execution

    private func executeCommand(_ cmd: PaletteCommand) {
        let action = cmd.action
        onDismiss()
        // Small delay to let the palette dismiss before executing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            action()
        }
    }

    // MARK: - Helpers

    /// Get flat index of a command across all groups (for selection tracking)
    private func flatIndex(of cmd: PaletteCommand) -> Int {
        let items = filtered
        return items.firstIndex(where: { $0.id == cmd.id }) ?? -1
    }
}
