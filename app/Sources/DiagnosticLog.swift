import AppKit
import SwiftUI

// MARK: - Log Store

final class DiagnosticLog: ObservableObject {
    static let shared = DiagnosticLog()

    struct Entry: Identifiable {
        let id = UUID()
        let time: Date
        let message: String
        let level: Level

        enum Level { case info, success, warning, error }

        var icon: String {
            switch level {
            case .info:    return "›"
            case .success: return "✓"
            case .warning: return "⚠"
            case .error:   return "✗"
            }
        }
    }

    @Published var entries: [Entry] = []
    private let maxEntries = 80

    func log(_ message: String, level: Entry.Level = .info) {
        let entry = Entry(time: Date(), message: message, level: level)
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func info(_ msg: String)    { log(msg, level: .info) }
    func success(_ msg: String) { log(msg, level: .success) }
    func warn(_ msg: String)    { log(msg, level: .warning) }
    func error(_ msg: String)   { log(msg, level: .error) }
    func clear()                { DispatchQueue.main.async { self.entries.removeAll() } }
}

// MARK: - Diagnostic Window

final class DiagnosticWindow {
    static let shared = DiagnosticWindow()

    private var window: NSWindow?
    private let log = DiagnosticLog.shared

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        if let w = window, w.isVisible {
            w.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        if let w = window {
            w.orderFrontRegardless()
            return
        }

        let view = DiagnosticOverlayView()

        let hosting = NSHostingController(rootView: view)
        let screen = NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = max(600, floor(screenFrame.height * 0.55))
        hosting.preferredContentSize = NSSize(width: panelWidth, height: panelHeight)

        let w = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        w.contentViewController = hosting
        w.title = "Lattice Diagnostics"
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.level = .floating
        w.isOpaque = false
        w.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        w.hasShadow = true
        w.alphaValue = 1.0
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position: right edge, vertically centered
        let x = screenFrame.maxX - panelWidth - 12
        let y = screenFrame.minY + floor((screenFrame.height - panelHeight) / 2)
        w.setFrameOrigin(NSPoint(x: x, y: y))

        w.orderFrontRegardless()
        window = w

        // Startup log
        let diag = DiagnosticLog.shared
        diag.info("Diagnostics opened")
        diag.info("Terminal: \(Preferences.shared.terminal.rawValue) (\(Preferences.shared.terminal.bundleId))")
        diag.info("Installed: \(Terminal.installed.map(\.rawValue).joined(separator: ", "))")

        // Show running sessions
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/tmux")
        task.arguments = ["list-sessions", "-F", "#{session_name}"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        let sessions = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "none"
        diag.info("tmux sessions: \(sessions)")
    }
}

// MARK: - SwiftUI Overlay

struct DiagnosticOverlayView: View {
    @StateObject private var log = DiagnosticLog.shared
    @State private var autoScroll = true
    @State private var refreshTick = 0

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // Fallback timer to catch any missed updates
    private let refreshTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("DIAGNOSTICS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.green.opacity(0.8))
                Spacer()
                let _ = refreshTick  // force re-render on timer
                Text("\(log.entries.count) events")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Button("Copy") {
                    let text = log.entries.map { entry in
                        let t = Self.timeFmt.string(from: entry.time)
                        return "\(t) \(entry.icon) \(entry.message)"
                    }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .buttonStyle(.plain)
                Button("Clear") { log.clear() }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.3))
            .onReceive(refreshTimer) { _ in refreshTick += 1 }

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(log.entries) { entry in
                            logRow(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: log.entries.count) { _ in
                    if autoScroll, let last = log.entries.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 400, idealHeight: 600)
        .background(Color.black.opacity(0.75))
    }

    private func logRow(_ entry: DiagnosticLog.Entry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.timeFmt.string(from: entry.time))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))

            Text(entry.icon)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(iconColor(entry.level))
                .frame(width: 10)

            Text(entry.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(textColor(entry.level))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 1)
    }

    private func iconColor(_ level: DiagnosticLog.Entry.Level) -> Color {
        switch level {
        case .info:    return .white.opacity(0.5)
        case .success: return .green
        case .warning: return .yellow
        case .error:   return .red
        }
    }

    private func textColor(_ level: DiagnosticLog.Entry.Level) -> Color {
        switch level {
        case .info:    return .white.opacity(0.7)
        case .success: return .green.opacity(0.9)
        case .warning: return .yellow.opacity(0.9)
        case .error:   return .red.opacity(0.9)
        }
    }
}
