import AppKit
import SwiftUI

final class MouseInputEventViewer: ObservableObject {
    static let shared = MouseInputEventViewer()

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let phase: String
        let appName: String
        let bundleId: String
        let buttonNumber: Int
        let triggerCandidate: String
        let deltaText: String
        let modifiersText: String
        let deviceText: String
        let matchText: String
        let note: String
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isCaptureActive = false

    private let maxEntries = 120
    private var window: NSWindow?
    private var closeObserver: Any?

    private init() {}

    func show() {
        if let window {
            isCaptureActive = true
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = MouseInputEventViewerView()
        let window = AppWindowShell.makeWindow(
            config: .init(
                title: "Mouse Shortcut Event Viewer",
                initialSize: NSSize(width: 980, height: 620),
                minSize: NSSize(width: 840, height: 460),
                maxSize: NSSize(width: 1500, height: 1000)
            ),
            rootView: view
        )
        AppWindowShell.positionCentered(window)
        AppWindowShell.present(window)

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.teardownWindow()
        }

        self.window = window
        isCaptureActive = true
        DiagnosticLog.shared.info("Mouse shortcuts event viewer opened")
    }

    func dismiss() {
        window?.close()
        teardownWindow()
    }

    func clear() {
        entries.removeAll()
    }

    func record(_ observedEvent: MouseShortcutObservedEvent) {
        let entry = Entry(
            timestamp: observedEvent.timestamp,
            phase: observedEvent.phase,
            appName: observedEvent.frontmostAppName ?? "Unknown App",
            bundleId: observedEvent.frontmostBundleId ?? "unknown.bundle",
            buttonNumber: observedEvent.buttonNumber,
            triggerCandidate: observedEvent.candidateTrigger ?? "--",
            deltaText: "\(Int(observedEvent.delta.x)), \(Int(observedEvent.delta.y))",
            modifiersText: Self.modifierLabels(for: observedEvent.modifiers).joined(separator: "+").ifEmpty("--"),
            deviceText: observedEvent.device?.summary ?? "Unresolved device",
            matchText: observedEvent.matchedRuleSummary ?? (observedEvent.willFire ? "Would fire" : "No match"),
            note: observedEvent.note ?? ""
        )

        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    private func teardownWindow() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        window = nil
        isCaptureActive = false
    }

    private static func modifierLabels(for flags: NSEvent.ModifierFlags) -> [String] {
        var labels: [String] = []
        if flags.contains(.control) { labels.append("Ctrl") }
        if flags.contains(.option) { labels.append("Option") }
        if flags.contains(.shift) { labels.append("Shift") }
        if flags.contains(.command) { labels.append("Cmd") }
        return labels
    }
}

private struct MouseInputEventViewerView: View {
    @ObservedObject private var viewer = MouseInputEventViewer.shared
    @ObservedObject private var devices = MouseInputDeviceStore.shared

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(Color.white.opacity(0.08))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if devices.devices.isEmpty {
                        deviceStrip(text: "Devices: none detected")
                    } else {
                        deviceStrip(text: "Devices: " + devices.devices.map(\.summary).joined(separator: "  |  "))
                    }

                    ForEach(viewer.entries) { entry in
                        entryRow(entry)
                    }
                }
                .padding(14)
            }
            .background(Color.black.opacity(0.16))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mouse Shortcut Event Viewer")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.95))
                Text("Watching extra mouse buttons and drag candidates for configurable shortcuts.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Button("Copy") {
                let text = viewer.entries.map { entry in
                    [
                        Self.timestampFormatter.string(from: entry.timestamp),
                        entry.phase,
                        entry.appName,
                        entry.bundleId,
                        "button=\(entry.buttonNumber)",
                        "candidate=\(entry.triggerCandidate)",
                        "delta=\(entry.deltaText)",
                        "mods=\(entry.modifiersText)",
                        "device=\(entry.deviceText)",
                        "match=\(entry.matchText)",
                        entry.note,
                    ].filter { !$0.isEmpty }.joined(separator: " | ")
                }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.72))

            Button("Clear") {
                viewer.clear()
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.72))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
    }

    private func deviceStrip(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
            )
    }

    private func entryRow(_ entry: MouseInputEventViewer.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Self.timestampFormatter.string(from: entry.timestamp))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.82))

                Text(entry.phase.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.62, green: 0.84, blue: 1.0))

                Text(entry.triggerCandidate)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.94))

                Spacer()

                Text(entry.matchText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.68))
            }

            HStack(spacing: 14) {
                metadataPill("App", "\(entry.appName) (\(entry.bundleId))")
                metadataPill("Button", "\(entry.buttonNumber)")
                metadataPill("Delta", entry.deltaText)
                metadataPill("Mods", entry.modifiersText)
            }

            HStack(spacing: 14) {
                metadataPill("Device", entry.deviceText)
                if !entry.note.isEmpty {
                    metadataPill("Note", entry.note)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private func metadataPill(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.42))
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.82))
        }
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String {
        isEmpty ? replacement : self
    }
}
