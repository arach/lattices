import SwiftUI

struct OmniSearchView: View {
    @ObservedObject var state: OmniSearchState
    var onDismiss: () -> Void

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
        .frame(minWidth: 520, idealWidth: 520, maxWidth: 700, minHeight: 360, idealHeight: 480, maxHeight: 600)
        .background(PanelBackground())
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
}
