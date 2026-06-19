import AppKit
import SwiftUI

struct RunsReviewView: View {
    @ObservedObject private var store = RunStore.shared
    @State private var selectedRunId: String?
    @State private var selectedArtifactId: String?

    private var selectedRun: RunSession? {
        guard let selectedRunId,
              let match = store.runs.first(where: { $0.id == selectedRunId }) else {
            return store.runs.first
        }
        return match
    }

    private var selectedArtifact: RunArtifact? {
        guard let run = selectedRun else { return nil }
        if let selectedArtifactId,
           let match = run.artifacts.first(where: { $0.id == selectedArtifactId }) {
            return match
        }
        return run.artifacts.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            if store.runs.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    runList
                        .frame(width: 280)

                    Rectangle()
                        .fill(Palette.border)
                        .frame(width: 0.5)

                    detailArea
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelBackground())
        .onAppear {
            ensureSelection()
            DiagnosticLog.shared.info("Runs review opened")
        }
        .onChange(of: store.runs.map(\.id)) { _, _ in
            ensureSelection()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.running)

            VStack(alignment: .leading, spacing: 2) {
                Text("Runs")
                    .font(Typo.heading(13))
                    .foregroundColor(Palette.text)
                Text("Trace and artifacts produced by Lattices captures and actions.")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textDim)
            }

            Spacer()

            Text("\(store.runs.count) run\(store.runs.count == 1 ? "" : "s")")
                .font(Typo.mono(10))
                .foregroundColor(Palette.textMuted)

            Button {
                Task.detached(priority: .userInitiated) {
                    do {
                        _ = try CaptureController.shared.screenshotWindow(params: .object([
                            "source": .string("review"),
                        ]))
                    } catch {
                        DiagnosticLog.shared.warn("Runs: screenshot failed — \(error.localizedDescription)")
                    }
                }
            } label: {
                Label("Capture", systemImage: "camera.viewfinder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var runList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("RECENT")
                    .font(Typo.geistMonoBold(9))
                    .foregroundColor(Palette.running)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.runs) { run in
                        RunListRow(
                            run: run,
                            isSelected: run.id == selectedRun?.id
                        ) {
                            selectedRunId = run.id
                            selectedArtifactId = run.artifacts.first?.id
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .background(Color.black.opacity(0.16))
    }

    @ViewBuilder
    private var detailArea: some View {
        if let run = selectedRun {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    runSummary(run)

                    Rectangle()
                        .fill(Palette.border)
                        .frame(height: 0.5)

                    artifactPreview(run)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Rectangle()
                    .fill(Palette.border)
                    .frame(width: 0.5)

                timeline(run)
                    .frame(width: 300)
            }
        } else {
            emptyState
        }
    }

    private func runSummary(_ run: RunSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        StatePill(state: run.state)
                        Text(run.title)
                            .font(Typo.heading(16))
                            .foregroundColor(Palette.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Text(run.id)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                HStack(spacing: 7) {
                    iconButton("arrow.clockwise", help: "Retry capture") {
                        retry(run)
                    }
                    iconButton("folder", help: "Reveal artifacts") {
                        reveal(run)
                    }
                    iconButton("doc.on.doc", help: "Copy artifact path") {
                        copyPath(selectedArtifact?.path ?? run.artifactDirectoryPath)
                    }
                    iconButton("trash", help: "Delete run", destructive: true) {
                        delete(run)
                    }
                }
            }

            HStack(spacing: 16) {
                summaryMetric("source", run.source)
                summaryMetric("started", shortTimestamp(run.startedAt))
                summaryMetric("completed", run.completedAt.map(shortTimestamp) ?? "open")
                summaryMetric("artifacts", "\(run.artifacts.count)")
                if let surface = run.surfaces.first {
                    summaryMetric("target", surface.app ?? surface.kind)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.12))
    }

    private func artifactPreview(_ run: RunSession) -> some View {
        VStack(spacing: 0) {
            artifactStrip(run)

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            if let artifact = selectedArtifact {
                VStack(spacing: 12) {
                    artifactCanvas(artifact)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    artifactMetadata(artifact)
                }
                .padding(14)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(Palette.textMuted)
                    Text("No artifacts")
                        .font(Typo.monoBold(12))
                        .foregroundColor(Palette.text)
                    Text("This run has trace data but did not produce a file.")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func artifactStrip(_ run: RunSession) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(run.artifacts) { artifact in
                    Button {
                        selectedArtifactId = artifact.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: artifact.kind == "screenshot" ? "photo" : "doc")
                                .font(.system(size: 11, weight: .semibold))
                            Text(artifact.relativePath)
                                .font(Typo.mono(10))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundColor(artifact.id == selectedArtifact?.id ? Palette.running : Palette.textMuted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(artifact.id == selectedArtifact?.id ? Palette.running.opacity(0.12) : Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(artifact.id == selectedArtifact?.id ? Palette.running.opacity(0.28) : Palette.border, lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 43)
    }

    @ViewBuilder
    private func artifactCanvas(_ artifact: RunArtifact) -> some View {
        if artifact.mimeType.hasPrefix("image/"),
           let image = NSImage(contentsOfFile: artifact.path) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.32))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )

                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(12)
            }
        } else {
            VStack(spacing: 9) {
                Image(systemName: "doc")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Palette.textMuted)
                Text(artifact.relativePath)
                    .font(Typo.mono(11))
                    .foregroundColor(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(artifact.mimeType)
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func artifactMetadata(_ artifact: RunArtifact) -> some View {
        HStack(spacing: 12) {
            metadataItem("kind", artifact.kind)
            metadataItem("mime", artifact.mimeType)
            if let width = artifact.metadata["width"]?.intValue,
               let height = artifact.metadata["height"]?.intValue {
                metadataItem("size", "\(width)x\(height)")
            }
            if let bytes = artifact.metadata["byteSize"]?.intValue {
                metadataItem("bytes", ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private func timeline(_ run: RunSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TRACE")
                    .font(Typo.geistMonoBold(9))
                    .foregroundColor(Palette.running)
                Spacer()
                Text("\(run.trace.count)")
                    .font(Typo.mono(9))
                    .foregroundColor(Palette.textDim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(run.trace) { event in
                        TraceRow(event: event)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(Color.black.opacity(0.16))
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: "record.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(Palette.textMuted)
            Text("No runs yet")
                .font(Typo.heading(15))
                .foregroundColor(Palette.text)
            Text("Use Capture to save the frontmost window as a Lattices run artifact.")
                .font(Typo.mono(10))
                .foregroundColor(Palette.textDim)
            Button {
                Task.detached(priority: .userInitiated) {
                    _ = try? CaptureController.shared.screenshotWindow(params: .object([
                        "source": .string("review"),
                    ]))
                }
            } label: {
                Label("Capture Current Window", systemImage: "camera.viewfinder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summaryMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(Typo.geistMonoBold(8))
                .foregroundColor(Palette.textDim)
            Text(value)
                .font(Typo.mono(10))
                .foregroundColor(Palette.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func metadataItem(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(Typo.geistMonoBold(8))
                .foregroundColor(Palette.textDim)
            Text(value)
                .font(Typo.mono(10))
                .foregroundColor(Palette.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func iconButton(
        _ symbol: String,
        help: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(destructive ? Palette.kill : Palette.textMuted)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func ensureSelection() {
        guard !store.runs.isEmpty else {
            selectedRunId = nil
            selectedArtifactId = nil
            return
        }

        if let selectedRunId,
           store.runs.contains(where: { $0.id == selectedRunId }) {
            let artifacts = selectedRun?.artifacts ?? []
            if let selectedArtifactId,
               artifacts.contains(where: { $0.id == selectedArtifactId }) {
                return
            }
            self.selectedArtifactId = artifacts.first?.id
            return
        }

        selectedRunId = store.runs.first?.id
        selectedArtifactId = store.runs.first?.artifacts.first?.id
    }

    private func retry(_ run: RunSession) {
        let surface = run.surfaces.first
        Task.detached(priority: .userInitiated) {
            var params: [String: JSON] = [
                "source": .string("review"),
                "title": .string("Retry \(run.title)"),
            ]
            if let wid = surface?.wid {
                params["wid"] = .int(Int(wid))
            } else if let app = surface?.app {
                params["app"] = .string(app)
                if let title = surface?.title { params["title"] = .string(title) }
            }
            do {
                _ = try CaptureController.shared.screenshotWindow(params: .object(params))
            } catch {
                DiagnosticLog.shared.warn("Runs: retry failed — \(error.localizedDescription)")
            }
        }
    }

    private func reveal(_ run: RunSession) {
        let url = selectedArtifact.map { URL(fileURLWithPath: $0.path) }
            ?? URL(fileURLWithPath: run.artifactDirectoryPath, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        DiagnosticLog.shared.success("Runs: copied path")
    }

    private func delete(_ run: RunSession) {
        do {
            try store.delete(id: run.id)
            DiagnosticLog.shared.success("Runs: deleted \(run.id)")
        } catch {
            DiagnosticLog.shared.warn("Runs: delete failed — \(error.localizedDescription)")
        }
    }

    private func shortTimestamp(_ timestamp: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: timestamp) else {
            return timestamp
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct RunListRow: View {
    let run: RunSession
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    StateDot(state: run.state)
                    Text(run.title)
                        .font(Typo.monoBold(11))
                        .foregroundColor(Palette.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text("\(run.artifacts.count)")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                }

                HStack(spacing: 7) {
                    Text(run.source)
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textMuted)
                    Text("·")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                    Text(shortTimestamp(run.startedAt))
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                    Spacer()
                }

                if let surface = run.surfaces.first {
                    Text(surface.app ?? surface.kind)
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Palette.running.opacity(0.12) : Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isSelected ? Palette.running.opacity(0.3) : Palette.border.opacity(0.7), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func shortTimestamp(_ timestamp: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: timestamp) else {
            return timestamp
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct StatePill: View {
    let state: String

    var body: some View {
        HStack(spacing: 5) {
            StateDot(state: state)
            Text(state.uppercased())
                .font(Typo.geistMonoBold(8))
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    private var color: Color {
        stateColor(state)
    }
}

private struct StateDot: View {
    let state: String

    var body: some View {
        Circle()
            .fill(stateColor(state))
            .frame(width: 7, height: 7)
    }
}

private struct TraceRow: View {
    let event: RunTraceEvent

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(spacing: 0) {
                Circle()
                    .fill(kindColor)
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                Rectangle()
                    .fill(Palette.border)
                    .frame(width: 1)
            }
            .frame(width: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.kind)
                        .font(Typo.geistMonoBold(9))
                        .foregroundColor(kindColor)
                        .lineLimit(1)
                    Spacer()
                    Text(shortTimestamp(event.time))
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                }

                Text(event.summary)
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if !event.data.isEmpty {
                    Text(event.data.map { "\($0.key)=\(jsonPreview($0.value))" }.sorted().joined(separator: "  "))
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.textDim)
                        .lineLimit(3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var kindColor: Color {
        if event.kind.contains("failed") { return Palette.kill }
        if event.kind.contains("completed") { return Palette.running }
        if event.kind.contains("artifact") { return Palette.textMuted }
        return Palette.textDim
    }

    private func shortTimestamp(_ timestamp: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: timestamp) else {
            return timestamp
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func jsonPreview(_ json: JSON) -> String {
        switch json {
        case .string(let value):
            return value
        case .int(let value):
            return "\(value)"
        case .double(let value):
            return String(format: "%.2f", value)
        case .bool(let value):
            return value ? "true" : "false"
        case .array(let values):
            return "[\(values.count)]"
        case .object(let object):
            return "{\(object.count)}"
        case .null:
            return "null"
        }
    }
}

private func stateColor(_ state: String) -> Color {
    switch state {
    case "completed":
        return Palette.running
    case "failed", "cancelled":
        return Palette.kill
    case "running":
        return Palette.detach
    default:
        return Palette.textDim
    }
}
