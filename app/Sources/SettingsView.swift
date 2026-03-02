import SwiftUI

/// Settings content with internal General / Shortcuts tabs.
/// Can also render the Docs page when `page == .docs`.
struct SettingsContentView: View {
    var page: AppPage = .settings
    @ObservedObject var prefs: Preferences
    @ObservedObject var scanner: ProjectScanner
    @ObservedObject var hotkeyStore: HotkeyStore = .shared
    var onBack: (() -> Void)? = nil

    @State private var selectedTab = "shortcuts"

    var body: some View {
        VStack(spacing: 0) {
            // Back bar
            backBar

            if page == .docs {
                docsContent
            } else {
                settingsBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(PanelBackground())
    }

    // MARK: - Back Bar

    private var backBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    onBack?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Screen Map")
                            .font(Typo.heading(11))
                    }
                    .foregroundColor(Palette.textDim)
                }
                .buttonStyle(.plain)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

                Spacer()

                Text(page.label.uppercased())
                    .font(Typo.pixel(11))
                    .foregroundColor(Palette.textMuted)
                    .tracking(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Rectangle().fill(Palette.border).frame(height: 0.5)
        }
    }

    // MARK: - Settings Body (General + Shortcuts tabs)

    private var settingsBody: some View {
        VStack(spacing: 0) {
            // Internal tab bar
            HStack(spacing: 0) {
                settingsTab(label: "General", id: "general")
                settingsTab(label: "Shortcuts", id: "shortcuts")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 4)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            // Tab content
            switch selectedTab {
            case "shortcuts": shortcutsContent
            default:          generalContent
            }
        }
    }

    private func settingsTab(label: String, id: String) -> some View {
        Button {
            selectedTab = id
        } label: {
            Text(label)
                .font(Typo.heading(11))
                .foregroundColor(selectedTab == id ? Palette.text : Palette.textDim)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selectedTab == id ? Color.white.opacity(0.06) : Color.clear)
                )
        }
        .buttonStyle(.plain)
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

                                    Text("Scans for .lattices.json configs")
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

    // MARK: - Shortcuts (Spatial Layout)

    private var shortcutsContent: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let spacing: CGFloat = 16
                let pad: CGFloat = 20
                let total = geo.size.width - pad * 2 - spacing * 2
                let leftW = total * 0.35
                let centerW = total * 0.35
                let rightW = total * 0.30

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: spacing) {
                            shortcutsLeftColumn
                                .frame(width: leftW, alignment: .leading)
                                .clipped()
                            shortcutsCenterColumn
                                .frame(width: centerW, alignment: .leading)
                                .clipped()
                            shortcutsRightColumn
                                .frame(width: rightW, alignment: .leading)
                                .clipped()
                        }
                        .padding(.horizontal, pad)
                        .padding(.vertical, 16)
                    }
                }
            }

            Spacer(minLength: 0)

            separator

            HStack {
                Spacer()
                Button {
                    hotkeyStore.resetAll()
                } label: {
                    Text("Reset All to Defaults")
                        .font(Typo.caption(11))
                        .foregroundColor(Palette.textDim)
                        .padding(.horizontal, 12)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Shortcuts: Left Column (App + Layers)

    private var shortcutsLeftColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            columnHeader("App & Layers")

            VStack(alignment: .leading, spacing: 2) {
                ForEach(HotkeyAction.allCases.filter { $0.group == .app }, id: \.rawValue) { action in
                    compactKeyRecorder(action: action)
                }
            }

            Rectangle().fill(Palette.border).frame(height: 0.5)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(HotkeyAction.layerActions, id: \.rawValue) { action in
                    compactKeyRecorder(action: action)
                }
            }
        }
    }

    // MARK: - Shortcuts: Center Column (Tiling)

    private var shortcutsCenterColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            columnHeader("Tiling")

            // Monitor visualization — 3x3 grid
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    tileCell(action: .tileTopLeft, label: "TL")
                    tileCell(action: .tileTop, label: "Top")
                    tileCell(action: .tileTopRight, label: "TR")
                }
                HStack(spacing: 2) {
                    tileCell(action: .tileLeft, label: "Left")
                    tileCell(action: .tileMaximize, label: "Max")
                    tileCell(action: .tileRight, label: "Right")
                }
                HStack(spacing: 2) {
                    tileCell(action: .tileBottomLeft, label: "BL")
                    tileCell(action: .tileBottom, label: "Bottom")
                    tileCell(action: .tileBottomRight, label: "BR")
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )

            // Thirds row
            HStack(spacing: 2) {
                tileCell(action: .tileLeftThird, label: "\u{2153}L")
                tileCell(action: .tileCenterThird, label: "\u{2153}C")
                tileCell(action: .tileRightThird, label: "\u{2153}R")
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )

            // Center + Distribute
            HStack(spacing: 4) {
                compactKeyRecorder(action: .tileCenter)
                compactKeyRecorder(action: .tileDistribute)
            }
        }
    }

    // MARK: - Shortcuts: Right Column (tmux)

    private var shortcutsRightColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            columnHeader("Inside tmux")

            VStack(alignment: .leading, spacing: 6) {
                shortcutRow("Detach", keys: ["Ctrl+B", "D"])
                shortcutRow("Kill pane", keys: ["Ctrl+B", "X"])
                shortcutRow("Pane left", keys: ["Ctrl+B", "\u{2190}"])
                shortcutRow("Pane right", keys: ["Ctrl+B", "\u{2192}"])
                shortcutRow("Zoom toggle", keys: ["Ctrl+B", "Z"])
                shortcutRow("Scroll mode", keys: ["Ctrl+B", "["])
            }
        }
    }

    // MARK: - Column header

    private func columnHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Typo.pixel(12))
            .foregroundColor(Palette.textDim)
            .tracking(1)
    }

    // MARK: - Tile cell (spatial grid item)

    private func tileCell(action: HotkeyAction, label: String) -> some View {
        let binding = hotkeyStore.bindings[action]
        let badgeText = binding?.displayParts.last ?? ""

        return Button {
            // Open inline key recorder for this action
        } label: {
            VStack(spacing: 3) {
                Text(label)
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textDim)
                Text(badgeText)
                    .font(Typo.geistMonoBold(9))
                    .foregroundColor(Palette.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: tileCellPopoverBinding(for: action)) {
            KeyRecorderView(action: action, store: hotkeyStore)
                .padding(12)
                .frame(width: 300)
        }
    }

    @State private var activeTilePopover: HotkeyAction?

    private func tileCellPopoverBinding(for action: HotkeyAction) -> Binding<Bool> {
        Binding(
            get: { activeTilePopover == action },
            set: { if !$0 { activeTilePopover = nil } }
        )
    }

    // MARK: - Compact key recorder

    private func compactKeyRecorder(action: HotkeyAction) -> some View {
        KeyRecorderView(action: action, store: hotkeyStore)
    }

    // MARK: - Shortcut row (read-only, for tmux)

    private func shortcutRow(_ label: String, keys: [String]) -> some View {
        HStack {
            Text(label)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textDim)
                .frame(width: 80, alignment: .trailing)

            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    keyBadge(key)
                }
            }
            .padding(.leading, 8)

            Spacer()
        }
    }

    // MARK: - Docs

    private var docsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Section(header: stickyHeader("What is lattices?")) {
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
                            "Terminal multiplexer \u{2014} the engine behind lattices. It manages sessions, panes, and layouts. lattices configures it so you don\u{2019}t have to.")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                Section(header: stickyHeader("How it works")) {
                    VStack(alignment: .leading, spacing: 8) {
                        flowStep("1", "Create a .lattices.json in your project root")
                        flowStep("2", "lattices reads the config and builds a tmux session")
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
                .frame(width: 100, alignment: .trailing)
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
