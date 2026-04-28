import SwiftUI

struct OmniSearchView: View {
    @ObservedObject var state: OmniSearchState
    var onDismiss: () -> Void
    var isEmbedded: Bool = false

    @ObservedObject private var ocrModel = OcrModel.shared
    @State private var expandedOcrWindow: UInt32?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Palette.textMuted)
                    .font(.system(size: 13))

                TextField("Search windows, projects, sessions...", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(Typo.mono(14))
                    .foregroundColor(Palette.text)
                    .focused($searchFocused)

                if !state.query.isEmpty {
                    Button { state.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Palette.textMuted)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Palette.surface)

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            // Content
            if state.query.isEmpty {
                summaryView
            } else if state.results.isEmpty {
                emptyResults
            } else {
                resultsView
            }
        }
        .frame(
            minWidth: isEmbedded ? 0 : 520,
            idealWidth: isEmbedded ? nil : 520,
            maxWidth: isEmbedded ? .infinity : 700,
            minHeight: isEmbedded ? 0 : 360,
            idealHeight: isEmbedded ? nil : 480,
            maxHeight: isEmbedded ? .infinity : 600,
            alignment: .top
        )
        .background {
            if isEmbedded {
                Palette.bg
            } else {
                PanelBackground()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            searchFocused = true
            state.refreshSummary()
        }
    }

    // MARK: - Results

    private var resultsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    var flatIndex = 0
                    ForEach(state.groupedResults, id: \.0) { group, items in
                        // Group header
                        Text(group.uppercased())
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                            .padding(.bottom, 2)

                        ForEach(items) { item in
                            let idx = flatIndex
                            let _ = { flatIndex += 1 }()
                            resultRow(item, index: idx)
                                .id(item.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: state.selectedIndex) { newVal in
                if newVal < state.results.count {
                    let item = state.results[newVal]
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                }
            }
        }
    }

    private func resultRow(_ item: OmniResult, index: Int) -> some View {
        let isSelected = index == state.selectedIndex
        return Button {
            item.action()
            onDismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? Palette.text : Palette.textDim)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(Typo.mono(12))
                        .foregroundColor(isSelected ? Palette.text : Palette.textDim)
                        .lineLimit(1)

                    Text(item.subtitle)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                Text(item.kind.rawValue)
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.surface)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Palette.surfaceHov : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty Results

    private var emptyResults: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(Palette.textMuted)
            Text("No results for \"\(state.query)\"")
                .font(Typo.mono(12))
                .foregroundColor(Palette.textDim)
            Spacer()
        }
    }

    // MARK: - Activity Summary

    private var summaryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let summary = state.activitySummary {
                    // Windows by app
                    summarySection("WINDOWS", icon: "macwindow", count: summary.totalWindows) {
                        ForEach(summary.windowsByApp) { app in
                            HStack {
                                Text(app.appName)
                                    .font(Typo.mono(11))
                                    .foregroundColor(Palette.textDim)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(app.count)")
                                    .font(Typo.monoBold(11))
                                    .foregroundColor(Palette.text)
                            }
                        }
                    }

                    // Sessions
                    if !summary.sessions.isEmpty {
                        summarySection("TMUX SESSIONS", icon: "terminal", count: summary.sessions.count) {
                            ForEach(summary.sessions) { session in
                                HStack {
                                    Circle()
                                        .fill(session.attached ? Palette.running : Palette.textMuted)
                                        .frame(width: 6, height: 6)
                                    Text(session.name)
                                        .font(Typo.mono(11))
                                        .foregroundColor(Palette.textDim)
                                    Spacer()
                                    Text("\(session.paneCount) panes")
                                        .font(Typo.mono(10))
                                        .foregroundColor(Palette.textMuted)
                                }
                            }
                        }
                    }

                    // Processes
                    if !summary.interestingProcesses.isEmpty {
                        summarySection("PROCESSES", icon: "gearshape", count: summary.interestingProcesses.count) {
                            ForEach(Array(summary.interestingProcesses.prefix(10).enumerated()), id: \.offset) { _, proc in
                                HStack {
                                    Text(proc.comm)
                                        .font(Typo.monoBold(11))
                                        .foregroundColor(Palette.textDim)
                                    if let cwd = proc.cwd {
                                        Text(cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                            .font(Typo.mono(10))
                                            .foregroundColor(Palette.textMuted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }

                    // OCR info
                    if summary.ocrWindowCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 10))
                                .foregroundColor(Palette.textMuted)
                            Text("OCR: \(summary.ocrWindowCount) windows scanned")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textMuted)
                            if let t = summary.lastOcrScan {
                                Spacer()
                                Text(relativeTime(t))
                                    .font(Typo.mono(9))
                                    .foregroundColor(Palette.textMuted)
                            }
                        }
                        .padding(.horizontal, 14)
                    }

                    if !recentOcrResults.isEmpty {
                        ocrResultsSection
                    }
                } else {
                    Text("Loading...")
                        .font(Typo.mono(11))
                        .foregroundColor(Palette.textMuted)
                        .padding(14)
                }
            }
            .padding(.vertical, 10)
        }
    }

    private var recentOcrResults: [OcrWindowResult] {
        Array(ocrModel.results.values.sorted { $0.timestamp > $1.timestamp }.prefix(10))
    }

    private var ocrResultsSection: some View {
        summarySection("SCREEN TEXT", icon: "doc.text.magnifyingglass", count: ocrModel.results.count) {
            ForEach(recentOcrResults, id: \.wid) { result in
                ocrResultRow(result)
            }
        }
    }

    private func ocrResultRow(_ result: OcrWindowResult) -> some View {
        let isExpanded = expandedOcrWindow == result.wid
        let title = result.title.isEmpty ? "Untitled" : result.title
        let preview = compactPreview(result.fullText)

        return VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    expandedOcrWindow = isExpanded ? nil : result.wid
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Palette.textMuted)
                            .frame(width: 9)

                        Text(result.app)
                            .font(Typo.monoBold(11))
                            .foregroundColor(Palette.textDim)
                            .lineLimit(1)

                        Text(sourceLabel(result.source))
                            .font(Typo.mono(8))
                            .foregroundColor(Palette.textMuted)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Palette.surface.opacity(0.8))
                            )

                        Spacer()

                        Text(relativeTime(result.timestamp))
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.textMuted)
                    }

                    Text(title)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)

                    if !isExpanded && !preview.isEmpty {
                        Text(preview)
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.textMuted.opacity(0.75))
                            .lineLimit(2)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Palette.surface.opacity(isExpanded ? 0.72 : 0.38))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.white.opacity(isExpanded ? 0.10 : 0.05), lineWidth: 0.5)
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView {
                    Text(result.fullText.isEmpty ? "No text captured." : result.fullText)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textDim)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.black.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                )
            }
        }
    }

    private func summarySection<Content: View>(
        _ title: String,
        icon: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Palette.textMuted)
                Text(title)
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textMuted)
                Text("\(count)")
                    .font(Typo.monoBold(9))
                    .foregroundColor(Palette.running)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.running.opacity(0.12))
                    )
                Spacer()
            }
            .padding(.horizontal, 14)

            VStack(spacing: 3) {
                content()
            }
            .padding(.horizontal, 14)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    private func sourceLabel(_ source: TextSource) -> String {
        switch source {
        case .accessibility: return "AX"
        case .ocr: return "OCR"
        }
    }

    private func compactPreview(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
