import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var scanner: ProjectScanner
    let onDismiss: () -> Void

    @State private var selectedTab = "general"

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 2) {
                sidebarItem(icon: "gearshape", label: "General", id: "general")
                sidebarItem(icon: "keyboard", label: "Shortcuts", id: "shortcuts")
                sidebarItem(icon: "book", label: "Docs", id: "docs")

                Spacer()

                Text("v0.1.0")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .padding(.top, 12)
            .frame(width: 140)
            .frame(maxHeight: .infinity)
            .background(Palette.surface.opacity(0.5))

            Rectangle()
                .fill(Palette.border)
                .frame(width: 0.5)

            // Content
            VStack(spacing: 0) {
                switch selectedTab {
                case "general":   generalContent
                case "shortcuts": shortcutsContent
                case "docs":      docsContent
                default:          generalContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(minWidth: 460, minHeight: 320)
        .background(PanelBackground())
    }

    // MARK: - Sidebar

    private func sidebarItem(icon: String, label: String, id: String) -> some View {
        Button {
            selectedTab = id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(selectedTab == id ? Palette.text : Palette.textMuted)
                    .frame(width: 16)
                Text(label)
                    .font(Typo.heading(12))
                    .foregroundColor(selectedTab == id ? Palette.text : Palette.textDim)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(selectedTab == id ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: - Sticky section header

    private func stickyHeader(_ title: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(Typo.pixel(14))
                    .foregroundColor(Palette.textDim)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Palette.bg)

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)
        }
    }

    // MARK: - General

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    Section(header: stickyHeader("General")) {
                        VStack(alignment: .leading, spacing: 20) {
                            settingsRow("Terminal") {
                                Picker("", selection: $prefs.terminal) {
                                    ForEach(Terminal.installed) { t in
                                        Text(t.rawValue).tag(t)
                                    }
                                }
                                .pickerStyle(.radioGroup)
                                .labelsHidden()
                            }

                            separator

                            settingsRow("Mode") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Picker("", selection: $prefs.mode) {
                                        Text("Learning").tag(InteractionMode.learning)
                                        Text("Auto").tag(InteractionMode.auto)
                                    }
                                    .pickerStyle(.radioGroup)
                                    .labelsHidden()

                                    Text(prefs.mode == .learning
                                        ? "Shows tmux keybinding hints on detach"
                                        : "Detaches sessions automatically")
                                        .font(Typo.caption(10))
                                        .foregroundColor(Palette.textMuted)
                                }
                            }

                            separator

                            settingsRow("Scan root") {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        TextField("~/dev", text: $prefs.scanRoot)
                                            .textFieldStyle(.plain)
                                            .font(Typo.mono(12))
                                            .foregroundColor(Palette.text)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 3)
                                                    .fill(Color.black.opacity(0.3))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 3)
                                                            .strokeBorder(Palette.border, lineWidth: 0.5)
                                                    )
                                            )

                                        Button {
                                            let panel = NSOpenPanel()
                                            panel.canChooseDirectories = true
                                            panel.canChooseFiles = false
                                            panel.allowsMultipleSelection = false
                                            if !prefs.scanRoot.isEmpty {
                                                panel.directoryURL = URL(fileURLWithPath: prefs.scanRoot)
                                            }
                                            if panel.runModal() == .OK, let url = panel.url {
                                                prefs.scanRoot = url.path
                                            }
                                        } label: {
                                            Text("Browse")
                                                .font(Typo.caption(11))
                                                .foregroundColor(Palette.textDim)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
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

                                    Text("Scans for .lattice.json configs")
                                        .font(Typo.caption(10))
                                        .foregroundColor(Palette.textMuted)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
            }

            Spacer(minLength: 0)

            separator

            HStack {
                Spacer()
                Button {
                    scanner.updateRoot(prefs.scanRoot)
                    scanner.scan()
                    onDismiss()
                } label: {
                    Text("Save")
                        .font(Typo.monoBold(11))
                        .foregroundColor(Palette.bg)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 3).fill(Palette.text)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Shortcuts

    private var shortcutsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Section(header: stickyHeader("App")) {
                    VStack(alignment: .leading, spacing: 12) {
                        shortcutRow("Command palette", keys: ["Cmd", "Shift", "M"])
                        shortcutRow("Layer 1/2/3...", keys: ["Cmd", "Option", "1/2/3"])
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                Section(header: stickyHeader("Inside tmux")) {
                    VStack(alignment: .leading, spacing: 10) {
                        shortcutRow("Detach", keys: ["Ctrl+B", "D"])
                        shortcutRow("Kill pane", keys: ["Ctrl+B", "X"])
                        shortcutRow("Pane left", keys: ["Ctrl+B", "\u{2190}"])
                        shortcutRow("Pane right", keys: ["Ctrl+B", "\u{2192}"])
                        shortcutRow("Zoom toggle", keys: ["Ctrl+B", "Z"])
                        shortcutRow("Scroll mode", keys: ["Ctrl+B", "["])
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func shortcutRow(_ label: String, keys: [String]) -> some View {
        HStack {
            Text(label)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textDim)
                .frame(width: 100, alignment: .trailing)

            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    keyBadge(key)
                }
            }
            .padding(.leading, 16)

            Spacer()
        }
    }

    // MARK: - Docs

    private var docsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Section(header: stickyHeader("What is lattice?")) {
                    Text("A developer workspace launcher. It creates pre-configured terminal layouts for your projects using tmux \u{2014} go from \u{201C}I want to work on X\u{201D} to a full environment in one click.")
                        .font(Typo.caption(11))
                        .foregroundColor(Palette.textDim)
                        .lineSpacing(3)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }

                Section(header: stickyHeader("Glossary")) {
                    VStack(alignment: .leading, spacing: 12) {
                        glossaryItem("Session",
                            "A persistent workspace that lives in the background. Survives terminal crashes, disconnects, even closing your laptop.")
                        glossaryItem("Pane",
                            "A single terminal view inside a session. A typical setup has two panes \u{2014} Claude Code on the left, dev server on the right.")
                        glossaryItem("Attach",
                            "Connect your terminal window to an existing session. The session was already running \u{2014} you\u{2019}re just viewing it.")
                        glossaryItem("Detach",
                            "Disconnect your terminal but keep the session alive. Your dev server keeps running, Claude keeps thinking.")
                        glossaryItem("tmux",
                            "Terminal multiplexer \u{2014} the engine behind lattice. It manages sessions, panes, and layouts. lattice configures it so you don\u{2019}t have to.")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                Section(header: stickyHeader("How it works")) {
                    VStack(alignment: .leading, spacing: 8) {
                        flowStep("1", "Create a .lattice.json in your project root")
                        flowStep("2", "lattice reads the config and builds a tmux session")
                        flowStep("3", "Each pane gets its command (claude, dev server, etc.)")
                        flowStep("4", "Session persists in the background until you kill it")
                        flowStep("5", "Attach and detach from any terminal, any time")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                Section(header: stickyHeader("Reference")) {
                    HStack(spacing: 8) {
                        docsLinkButton(icon: "doc.text", label: "Config format", file: "config.md")
                        docsLinkButton(icon: "book", label: "Full concepts", file: "concepts.md")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Docs helpers

    private func glossaryItem(_ term: String, _ definition: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(term)
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.text)
            Text(definition)
                .font(Typo.caption(10.5))
                .foregroundColor(Palette.textMuted)
                .lineSpacing(2)
        }
    }

    private func flowStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(Typo.monoBold(10))
                .foregroundColor(Palette.running)
                .frame(width: 14)
            Text(text)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textDim)
        }
    }

    private func docsLinkButton(icon: String, label: String, file: String) -> some View {
        Button {
            let path = resolveDocsFile(file)
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(Typo.caption(11))
            }
            .foregroundColor(Palette.textDim)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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

    private func resolveDocsFile(_ file: String) -> String {
        let devPath = "/Users/arach/dev/lattice/docs/\(file)"
        if FileManager.default.fileExists(atPath: devPath) { return devPath }
        let bundle = Bundle.main.bundlePath
        let appDir = (bundle as NSString).deletingLastPathComponent
        let docsPath = ((appDir as NSString).appendingPathComponent("../docs/\(file)") as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: docsPath) { return docsPath }
        return devPath
    }

    // MARK: - Shared helpers

    private var separator: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 0.5)
    }

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textDim)
                .frame(width: 80, alignment: .trailing)
                .padding(.top, 2)

            content()
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func keyBadge(_ key: String) -> some View {
        Text(key)
            .font(Typo.geistMonoBold(10))
            .foregroundColor(Palette.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
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
