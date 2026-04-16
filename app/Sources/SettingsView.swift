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

    private var currentTabLabel: String {
        switch selectedTab {
        case "general": return "General"
        case "search": return "Search & OCR"
        case "shortcuts": return "Shortcuts"
        default: return page.label
        }
    }

    private var backBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    onBack?()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Palette.textMuted)
                }
                .buttonStyle(.plain)
                .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

                Text(page == .docs ? "Docs" : currentTabLabel)
                    .font(Typo.heading(13))
                    .foregroundColor(Palette.text)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Rectangle().fill(Palette.border).frame(height: 0.5)
        }
    }

    // MARK: - Settings Body (General + Shortcuts tabs)

    private var settingsBody: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 2) {
                settingsTab(label: "General", id: "general")
                settingsTab(label: "AI", id: "ai")
                settingsTab(label: "Search & OCR", id: "search")
                settingsTab(label: "Shortcuts", id: "shortcuts")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            // Tab content
            switch selectedTab {
            case "shortcuts": shortcutsContent
            case "search":    searchOcrContent
            case "ai":        aiContent
            default:          generalContent
            }
        }
    }

    private func settingsTab(label: String, id: String) -> some View {
        let active = selectedTab == id
        return Button {
            selectedTab = id
        } label: {
            Text(label)
                .font(Typo.mono(11))
                .foregroundColor(active ? Palette.text : Palette.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    ZStack {
                        if active {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.5
                                )
                        }
                    }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // ── Terminal ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Terminal")
                            .font(Typo.mono(11))
                            .foregroundColor(Palette.text)

                        Picker("", selection: $prefs.terminal) {
                            ForEach(Terminal.installed) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text("Used for attaching to tmux sessions")
                            .font(Typo.caption(10))
                            .foregroundColor(Palette.textMuted)
                    }
                }

                // ── tmux ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("tmux")
                            .font(Typo.mono(11))
                            .foregroundColor(Palette.text)

                        // Mode
                        HStack {
                            Text("Detach mode")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                            Picker("", selection: $prefs.mode) {
                                Text("Learning").tag(InteractionMode.learning)
                                Text("Auto").tag(InteractionMode.auto)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 160)
                        }

                        Text(prefs.mode == .learning
                            ? "Shows keybinding hints on detach"
                            : "Detaches sessions silently")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.7))

                        cardDivider

                        // Project scan root
                        Text("Project scan root")
                            .font(Typo.mono(10))
                            .foregroundColor(Palette.textDim)

                        HStack(spacing: 6) {
                            TextField("~/dev", text: $prefs.scanRoot)
                                .textFieldStyle(.plain)
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.text)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
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
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                    .foregroundColor(Palette.textDim)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.white.opacity(0.06))
                                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        HStack {
                            Text("Scans for .lattices.json project configs")
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.textMuted.opacity(0.7))
                            Spacer()
                            Button {
                                scanner.updateRoot(prefs.scanRoot)
                                scanner.scan()
                            } label: {
                                Text("Rescan")
                                    .font(Typo.monoBold(10))
                                    .foregroundColor(Palette.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Palette.surfaceHov)
                                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - AI

    private var aiContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                // ── Claude CLI ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Palette.running)
                            Text("Claude CLI")
                                .font(Typo.mono(12))
                                .foregroundColor(Palette.text)
                        }

                        HStack(spacing: 6) {
                            TextField("Auto-detected", text: $prefs.claudePath)
                                .textFieldStyle(.plain)
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.text)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                                )

                            Button {
                                if let resolved = Preferences.resolveClaudePath() {
                                    prefs.claudePath = resolved
                                }
                            } label: {
                                Text("Detect")
                                    .font(Typo.monoBold(10))
                                    .foregroundColor(Palette.text)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Palette.surfaceHov)
                                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        let resolved = Preferences.resolveClaudePath()
                        if let path = resolved {
                            Text("Found: \(path)")
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.running.opacity(0.8))
                        } else {
                            Text("Not found — install with: npm i -g @anthropic-ai/claude-code")
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.detach)
                        }
                    }
                }

                // ── Advisor ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Voice advisor")
                            .font(Typo.mono(11))
                            .foregroundColor(Palette.text)

                        HStack {
                            Text("Model")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                            Picker("", selection: $prefs.advisorModel) {
                                Text("Haiku").tag("haiku")
                                Text("Sonnet").tag("sonnet")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 160)
                        }

                        Text("Haiku is fast and cheap. Sonnet is smarter but slower.")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.7))

                        cardDivider

                        HStack {
                            Text("Budget per session")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("$")
                                    .font(Typo.mono(11))
                                    .foregroundColor(Palette.textDim)
                                TextField("0.50", value: $prefs.advisorBudgetUSD, formatter: {
                                    let f = NumberFormatter()
                                    f.numberStyle = .decimal
                                    f.minimumFractionDigits = 2
                                    f.maximumFractionDigits = 2
                                    return f
                                }())
                                .textFieldStyle(.plain)
                                .font(Typo.monoBold(11))
                                .foregroundColor(Palette.text)
                                .multilineTextAlignment(.center)
                                .frame(width: 50)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                                )
                            }
                        }

                        Text("Max spend per Claude CLI invocation")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.7))

                        cardDivider

                        // Session stats
                        let stats = AgentPool.shared.haiku.sessionStats
                        HStack(spacing: 12) {
                            if stats.contextWindow > 0 {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(stats.contextUsage > 0.6 ? Palette.detach : Palette.running)
                                        .frame(width: 5, height: 5)
                                    Text("Context: \(Int(stats.contextUsage * 100))%")
                                        .font(Typo.mono(10))
                                        .foregroundColor(Palette.textMuted)
                                }
                            }
                            if stats.costUSD > 0 {
                                Text("Session cost: $\(String(format: "%.3f", stats.costUSD))")
                                    .font(Typo.mono(10))
                                    .foregroundColor(Palette.textMuted)
                            }

                            Spacer()

                            let learningCount = AdvisorLearningStore.shared.entryCount
                            if learningCount > 0 {
                                Text("\(learningCount) learned")
                                    .font(Typo.mono(9))
                                    .foregroundColor(Palette.textMuted.opacity(0.6))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Search & OCR

    private func ocrNumField(_ value: Binding<Double>, width: CGFloat = 50) -> some View {
        TextField("", value: value, formatter: NumberFormatter())
            .textFieldStyle(.plain)
            .font(Typo.monoBold(11))
            .foregroundColor(Palette.text)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
    }

    private func ocrIntField(_ value: Binding<Int>, width: CGFloat = 36) -> some View {
        TextField("", value: value, formatter: NumberFormatter())
            .textFieldStyle(.plain)
            .font(Typo.monoBold(11))
            .foregroundColor(Palette.text)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
    }

    private func ocrSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Typo.monoBold(10))
            .foregroundColor(Palette.textDim)
            .tracking(0.5)
    }

    private var searchOcrContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                // ── Screen Text Recognition Card ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        // Header row: label + toggle
                        HStack {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(prefs.ocrEnabled ? Palette.running.opacity(0.15) : Palette.surface)
                                    .overlay(
                                        Image(systemName: "text.viewfinder")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(prefs.ocrEnabled ? Palette.running : Palette.textMuted)
                                    )
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Screen text recognition")
                                        .font(Typo.mono(12))
                                        .foregroundColor(Palette.text)
                                    Text("Vision OCR on visible windows")
                                        .font(Typo.caption(10))
                                        .foregroundColor(Palette.textMuted)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { prefs.ocrEnabled },
                                set: { OcrModel.shared.setEnabled($0) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                        }

                        // Accuracy
                        HStack(spacing: 8) {
                            Text("Accuracy")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                            Picker("", selection: $prefs.ocrAccuracy) {
                                Text("Accurate").tag("accurate")
                                Text("Fast").tag("fast")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 140)
                            Spacer()
                        }
                        .padding(.leading, 32)
                    }
                }

                // ── Scan Schedule Card ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ocrSectionLabel("Schedule")

                        // Quick scan sentence
                        HStack(spacing: 0) {
                            Text("Quick scan top ")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            ocrIntField($prefs.ocrQuickLimit, width: 32)
                            Text(" windows every ")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            ocrNumField($prefs.ocrQuickInterval, width: 42)
                            Text("s")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                        }

                        cardDivider

                        // Deep scan sentence
                        HStack(spacing: 0) {
                            Text("Deep scan up to ")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            ocrIntField($prefs.ocrDeepLimit, width: 32)
                            Text(" windows every ")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            ocrNumField($prefs.ocrDeepInterval, width: 52)
                            Text("s")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                        }

                        HStack(spacing: 0) {
                            Text("OCR budget: ")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            ocrIntField($prefs.ocrDeepBudget, width: 32)
                            Text(" windows per scan")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                        }

                        // Human-readable deep interval
                        let h = Int(prefs.ocrDeepInterval / 3600)
                        let m = Int(prefs.ocrDeepInterval.truncatingRemainder(dividingBy: 3600) / 60)
                        if h > 0 || m > 0 {
                            Text("≈ \(h > 0 ? "\(h)h" : "")\(m > 0 ? " \(m)m" : "")")
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.textMuted.opacity(0.6))
                                .padding(.leading, 2)
                        }
                    }
                }

                // ── Status Card ──
                settingsCard {
                    HStack(spacing: 8) {
                        let ocrResults = OcrModel.shared.results
                        let isScanning = OcrModel.shared.isScanning

                        Circle()
                            .fill(isScanning ? Palette.detach : (prefs.ocrEnabled ? Palette.running : Palette.textMuted))
                            .frame(width: 6, height: 6)

                        Text(isScanning ? "Scanning..." : (prefs.ocrEnabled ? "\(ocrResults.count) windows cached" : "Disabled"))
                            .font(Typo.mono(10))
                            .foregroundColor(Palette.textMuted)

                        Spacer()

                        Button {
                            OcrModel.shared.scan()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("Scan Now")
                                    .font(Typo.monoBold(10))
                            }
                            .foregroundColor(prefs.ocrEnabled ? Palette.text : Palette.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(prefs.ocrEnabled ? Palette.surfaceHov : Palette.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!prefs.ocrEnabled)
                    }
                }

                // ── Recent Captures ──
                recentCapturesSection
            }
            .padding(16)
        }
    }

    // MARK: - Recent Captures Browser

    private var recentCapturesSection: some View {
        let ocrResults = OcrModel.shared.results
        let grouped = Dictionary(grouping: ocrResults.values, by: \.app)
            .sorted { $0.value.count > $1.value.count }

        return Group {
            if !grouped.isEmpty {
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        ocrSectionLabel("Recent Captures")

                        ForEach(grouped, id: \.key) { app, windows in
                            ocrAppGroup(app: app, windows: windows.sorted { $0.timestamp > $1.timestamp })
                        }
                    }
                }
            }
        }
    }

    private func ocrAppGroup(app: String, windows: [OcrWindowResult]) -> some View {
        let isCollapsed = collapsedOcrApps.contains(app)

        return VStack(alignment: .leading, spacing: 0) {
            // App header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isCollapsed {
                        collapsedOcrApps.remove(app)
                    } else {
                        collapsedOcrApps.insert(app)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Palette.textMuted)
                        .frame(width: 10)

                    Text(app)
                        .font(Typo.monoBold(11))
                        .foregroundColor(Palette.text)

                    Text("(\(windows.count))")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)

                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(windows, id: \.wid) { win in
                        ocrWindowRow(win)
                    }
                }
                .padding(.leading, 16)
            }
        }
    }

    private func ocrWindowRow(_ win: OcrWindowResult) -> some View {
        let isExpanded = expandedOcrWindow == win.wid
        let preview = String(win.fullText.prefix(80)).replacingOccurrences(of: "\n", with: " ")

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedOcrWindow = isExpanded ? nil : win.wid
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundColor(Palette.textMuted)
                        .frame(width: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(win.title.isEmpty ? "Untitled" : win.title)
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.text)
                                .lineLimit(1)

                            Spacer()

                            Text(ocrRelativeTime(win.timestamp))
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.textMuted)
                        }

                        if !isExpanded && !preview.isEmpty {
                            Text(preview)
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.textMuted.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ocrExpandedDetail(win)
                    .padding(.leading, 14)
                    .padding(.vertical, 4)
            }
        }
    }

    private func ocrExpandedDetail(_ win: OcrWindowResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Metadata row
            HStack(spacing: 10) {
                let avgConfidence = win.texts.isEmpty ? 0 : win.texts.map(\.confidence).reduce(0, +) / Float(win.texts.count)
                Text("\(win.texts.count) blocks")
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textMuted)
                Text("confidence: \(String(format: "%.0f%%", avgConfidence * 100))")
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textMuted)
                Spacer()
            }

            // Full text in scrollable monospaced area
            ScrollView {
                Text(win.fullText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Palette.textDim)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
        }
    }

    private func ocrRelativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    // MARK: - Settings Card

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass()
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.03), Color.white.opacity(0.08), Color.white.opacity(0.03)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.5)
            .padding(.vertical, 3)
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
                HStack(spacing: 8) {
                    footerActionButton(icon: "book", label: "Docs") {
                        ScreenMapWindowController.shared.showPage(.docs)
                    }

                    footerActionButton(icon: "stethoscope", label: "Diagnostics") {
                        DiagnosticWindow.shared.show()
                    }
                }

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

    @State private var expandedOcrWindow: UInt32?
    @State private var collapsedOcrApps: Set<String> = []

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

                Section(header: stickyHeader("Voice commands")) {
                    VStack(alignment: .leading, spacing: 8) {
                        flowStep("⌥", "Hold Option key to speak, release to stop")
                        flowStep("⇥", "Tab to arm/disarm the mic")
                        flowStep("⎋", "Escape to dismiss")

                        Text("Built-in commands: find, show, open, tile, kill, scan")
                            .font(Typo.caption(10.5))
                            .foregroundColor(Palette.textMuted)
                            .padding(.top, 4)

                        Text("When local matching fails, Claude Haiku advises with follow-up suggestions. Configure the AI model and budget in Settings → AI.")
                            .font(Typo.caption(10.5))
                            .foregroundColor(Palette.textMuted)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                Section(header: stickyHeader("Reference")) {
                    HStack(spacing: 8) {
                        docsLinkButton(icon: "doc.text", label: "Config format", file: "config.md")
                        docsLinkButton(icon: "book", label: "Full concepts", file: "concepts.md")
                        footerActionButton(icon: "stethoscope", label: "Diagnostics") {
                            DiagnosticWindow.shared.show()
                        }
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
            footerActionLabel(icon: icon, label: label)
        }
        .buttonStyle(.plain)
    }

    private func footerActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            footerActionLabel(icon: icon, label: label)
        }
        .buttonStyle(.plain)
    }

    private func footerActionLabel(icon: String, label: String) -> some View {
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

    private func resolveDocsFile(_ file: String) -> String {
        let bundle = Bundle.main.bundlePath
        let appDir = (bundle as NSString).deletingLastPathComponent
        let docsPath = ((appDir as NSString).appendingPathComponent("../docs/\(file)") as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: docsPath) { return docsPath }
        // Fallback: look relative to the repo root (dev builds)
        let repoGuess = ((appDir as NSString).appendingPathComponent("../../docs/\(file)") as NSString).standardizingPath
        return FileManager.default.fileExists(atPath: repoGuess) ? repoGuess : docsPath
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
