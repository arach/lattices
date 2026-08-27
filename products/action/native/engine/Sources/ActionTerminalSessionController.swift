import AppKit
import Darwin
import Foundation

@MainActor
final class ActionTerminalSessionController: NSObject, NSWindowDelegate {
    private let writer: ResponseWriter
    private let controlFile: String
    private let stopFile: String?
    private let shellPath: String
    private let workingDirectory: String?
    private let homeDirectory: String
    private var window: NSWindow?
    private var textView: NSTextView?
    private var process: Process?
    private var masterFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var pollTimer: Timer?
    private var inputPlaybackTimer: Timer?
    private var controlOffset: UInt64 = 0
    private var terminalBuffer = ""
    private var pendingInputBytes: [UInt8] = []
    private let soundPlayer = DemoCueSoundPlayer()

    init(
        writer: ResponseWriter,
        controlFile: String,
        stopFile: String?,
        shellPath: String,
        workingDirectory: String?,
        homeDirectory: String
    ) {
        self.writer = writer
        self.controlFile = controlFile
        self.stopFile = stopFile
        self.shellPath = shellPath
        self.workingDirectory = workingDirectory
        self.homeDirectory = homeDirectory
        super.init()
    }

    func run() throws {
        try prepareControlFile()
        try startPTY()
        createWindow()
        try writer.write(
            ActionHostResponse(
                status: "terminal-session-running",
                outputPath: nil,
                detail: String(ProcessInfo.processInfo.processIdentifier)
            )
        )
        startPolling()
        NSApplication.shared.run()
    }

    private func prepareControlFile() throws {
        let url = URL(fileURLWithPath: controlFile)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    private func startPTY() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var terminalSize = winsize(ws_row: 32, ws_col: 118, ws_xpixel: 0, ws_ypixel: 0)

        guard openpty(&master, &slave, nil, nil, &terminalSize) == 0 else {
            throw ActionHostError.captureFailed("Unable to create pseudo-terminal: \(String(cString: strerror(errno)))")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = shellPath.hasSuffix("zsh") ? ["-f"] : []
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: homeDirectory),
            withIntermediateDirectories: true
        )

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "ZDOTDIR")
        environment["TERM"] = "xterm-256color"
        environment["ACTION_TERMINAL_SESSION"] = "1"
        environment["HOME"] = homeDirectory
        environment["PS1"] = "action$ "
        environment["PROMPT"] = "action:%~ %# "
        environment["RPROMPT"] = ""
        process.environment = environment

        process.standardInput = FileHandle(fileDescriptor: dup(slave), closeOnDealloc: true)
        process.standardOutput = FileHandle(fileDescriptor: dup(slave), closeOnDealloc: true)
        process.standardError = FileHandle(fileDescriptor: dup(slave), closeOnDealloc: true)
        close(slave)

        try process.run()
        self.process = process
        self.masterFD = master

        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: .main)
        source.setEventHandler { [weak self] in
            self?.readAvailablePTYData()
        }
        source.setCancelHandler {
            close(master)
        }
        source.resume()
        self.readSource = source
    }

    private func createWindow() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? CGRect(x: 80, y: 80, width: 1280, height: 820)
        let width = min(1080, visible.width - 80)
        let height = min(680, visible.height - 120)
        let frame = CGRect(
            x: visible.maxX - width - 34,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )

        let window = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "Action Terminal Session"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.delegate = self

        let root = NSView(frame: CGRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.08, alpha: 1).cgColor

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor(calibratedWhite: 0.93, alpha: 1)
        textView.insertionPointColor = .clear
        textView.textContainerInset = CGSize(width: 14, height: 14)
        textView.autoresizingMask = [.width, .height]

        let scrollView = NSScrollView(frame: root.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        root.addSubview(scrollView)

        window.contentView = root
        window.orderFrontRegardless()

        self.window = window
        self.textView = textView
        appendDisplayText("Action terminal session ready\ncontrol: \(controlFile)\n\n")
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(
            timeInterval: 0.03,
            target: self,
            selector: #selector(pollControlFiles),
            userInfo: nil,
            repeats: true
        )
    }

    @objc
    private func pollControlFiles() {
        if let stopFile, FileManager.default.fileExists(atPath: stopFile) {
            shutdown()
            return
        }

        guard FileManager.default.fileExists(atPath: controlFile),
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: controlFile)) else {
            return
        }

        defer {
            try? handle.close()
        }

        do {
            try handle.seek(toOffset: controlOffset)
            let data = try handle.readToEnd() ?? Data()
            guard !data.isEmpty else {
                return
            }

            controlOffset += UInt64(data.count)
            enqueueControlInput(data)
        } catch {
            appendDisplayText("\n[action control read failed: \(error.localizedDescription)]\n")
        }
    }

    private func enqueueControlInput(_ data: Data) {
        guard !data.isEmpty else {
            return
        }
        pendingInputBytes.append(contentsOf: data)
        startInputPlaybackIfNeeded()
    }

    private func startInputPlaybackIfNeeded() {
        guard inputPlaybackTimer == nil else {
            return
        }

        inputPlaybackTimer = Timer.scheduledTimer(
            timeInterval: 0.046,
            target: self,
            selector: #selector(playNextControlInputByte),
            userInfo: nil,
            repeats: true
        )
        playNextControlInputByte()
    }

    @objc
    private func playNextControlInputByte() {
        guard masterFD >= 0, !pendingInputBytes.isEmpty else {
            inputPlaybackTimer?.invalidate()
            inputPlaybackTimer = nil
            return
        }

        var byte = pendingInputBytes.removeFirst()
        withUnsafeBytes(of: &byte) { bytes in
            _ = write(masterFD, bytes.baseAddress, 1)
        }

        if shouldPlayTypingSound(for: byte) {
            soundPlayer.playTyping()
        }
    }

    private func shouldPlayTypingSound(for byte: UInt8) -> Bool {
        byte == 0x09 || byte == 0x0A || byte == 0x7F || byte >= 0x20
    }

    private func readAvailablePTYData() {
        guard masterFD >= 0 else {
            return
        }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let count = read(masterFD, &buffer, buffer.count)
        guard count > 0 else {
            return
        }

        let data = Data(buffer.prefix(count))
        let text = String(decoding: data, as: UTF8.self)
        appendTerminalText(text)
    }

    private func appendTerminalText(_ text: String) {
        appendDisplayText(stripANSIEscapes(text))
    }

    private func appendDisplayText(_ text: String) {
        terminalBuffer += text
        if terminalBuffer.count > 20_000 {
            terminalBuffer = String(terminalBuffer.suffix(20_000))
        }
        textView?.string = terminalBuffer
        if let textView {
            textView.scrollRangeToVisible(NSRange(location: textView.string.count, length: 0))
        }
    }

    private func stripANSIEscapes(_ text: String) -> String {
        var result = text
        let escape = "\u{001B}"
        let patterns = [
            "\(escape)\\][^\u{0007}\(escape)]*(?:\u{0007}|\(escape)\\\\)",
            "\(escape)\\[[0-9;?]*[ -/]*[@-~]",
            "\(escape)[()][A-Za-z0-9]",
        ]

        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return result
            .replacingOccurrences(of: "\u{0007}", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }

    func windowWillClose(_ notification: Notification) {
        shutdown()
    }

    private func shutdown() {
        pollTimer?.invalidate()
        pollTimer = nil
        inputPlaybackTimer?.invalidate()
        inputPlaybackTimer = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        readSource?.cancel()
        readSource = nil
        NSApplication.shared.terminate(nil)
    }
}
