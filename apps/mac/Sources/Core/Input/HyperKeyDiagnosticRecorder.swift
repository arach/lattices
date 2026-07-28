import AppKit
import Combine
import Foundation

/// Opt-in, bounded diagnostic trace for the Caps Lock → F18 → Hyper pipeline.
///
/// This intentionally does not capture general keyboard traffic. Callers only
/// submit transport events, events handled while the Hyper layer is active,
/// and lifecycle/state transitions. Records contain key codes and modifier
/// masks, never characters or text.
final class HyperKeyDiagnosticRecorder: ObservableObject {
    static let shared = HyperKeyDiagnosticRecorder()

    @Published private(set) var isRecording: Bool

    let traceURL: URL

    private static let recordingDefaultsKey = "keyboardRemaps.hyperDiagnosticsEnabled"
    private static let maxTraceBytes: UInt64 = 2_000_000
    private let stateLock = NSLock()
    private let activityLock = NSLock()
    private let writerQueue = DispatchQueue(label: "dev.lattices.hyper-key-trace", qos: .utility)
    private var recording: Bool
    private var sequence: UInt64 = 0
    private var activityCounts: [String: Int] = [:]
    private var activityWindowStartedAt = ProcessInfo.processInfo.systemUptime

    private init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lattices", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        traceURL = directory.appendingPathComponent("hyper-key-trace.jsonl")

        let persisted = UserDefaults.standard.bool(forKey: Self.recordingDefaultsKey)
        recording = persisted
        isRecording = persisted
        if persisted {
            record(kind: "trace.resumed", fields: environmentFields())
        }
    }

    func start() {
        stateLock.lock()
        guard !recording else {
            stateLock.unlock()
            return
        }
        recording = true
        sequence = 0
        stateLock.unlock()

        activityLock.lock()
        activityCounts.removeAll()
        activityWindowStartedAt = ProcessInfo.processInfo.systemUptime
        activityLock.unlock()

        UserDefaults.standard.set(true, forKey: Self.recordingDefaultsKey)
        isRecording = true
        writerQueue.async { [weak self] in
            self?.rotateTraceForNewCapture()
        }
        record(kind: "trace.started", fields: environmentFields())
        DiagnosticLog.shared.info("HyperKeyTrace: recording to ~/.lattices/hyper-key-trace.jsonl")
    }

    func stop() {
        flushInputActivity()
        record(kind: "trace.stopped")
        stateLock.lock()
        recording = false
        stateLock.unlock()

        UserDefaults.standard.set(false, forKey: Self.recordingDefaultsKey)
        isRecording = false
        DiagnosticLog.shared.info("HyperKeyTrace: recording stopped")
    }

    func reveal() {
        writerQueue.async { [traceURL] in
            if !FileManager.default.fileExists(atPath: traceURL.path) {
                FileManager.default.createFile(atPath: traceURL.path, contents: nil)
            }
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([traceURL])
            }
        }
    }

    func record(kind: String, fields: [String: Any] = [:]) {
        stateLock.lock()
        guard recording else {
            stateLock.unlock()
            return
        }
        sequence += 1
        let recordSequence = sequence
        stateLock.unlock()

        let capturedAt = Date().timeIntervalSince1970
        let monotonic = ProcessInfo.processInfo.systemUptime
        writerQueue.async { [weak self] in
            guard let self else { return }
            var payload = fields
            payload["seq"] = recordSequence
            payload["time"] = capturedAt
            payload["uptime"] = monotonic
            payload["kind"] = kind

            guard JSONSerialization.isValidJSONObject(payload),
                  let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
                return
            }
            self.rotateIfNeeded(incomingBytes: UInt64(data.count + 1))
            self.append(data + Data([0x0A]))
        }
    }

    /// Counts all keyboard event-tap traffic without retaining key codes,
    /// modifier flags, characters, or source applications. This tells a trace
    /// whether the tap was alive when an expected F18 event went missing.
    func observeInputEvent(type: String) {
        stateLock.lock()
        let active = recording
        stateLock.unlock()
        guard active else { return }

        let now = ProcessInfo.processInfo.systemUptime
        var summary: [String: Int]?
        var durationMs = 0

        activityLock.lock()
        activityCounts[type, default: 0] += 1
        if now - activityWindowStartedAt >= 1 {
            summary = activityCounts
            durationMs = Int((now - activityWindowStartedAt) * 1_000)
            activityCounts.removeAll()
            activityWindowStartedAt = now
        }
        activityLock.unlock()

        if let summary {
            record(kind: "input.activity", fields: [
                "durationMs": durationMs,
                "counts": summary,
            ])
        }
    }

    private func flushInputActivity() {
        let now = ProcessInfo.processInfo.systemUptime
        var summary: [String: Int] = [:]
        var durationMs = 0

        activityLock.lock()
        if !activityCounts.isEmpty {
            summary = activityCounts
            durationMs = Int((now - activityWindowStartedAt) * 1_000)
            activityCounts.removeAll()
            activityWindowStartedAt = now
        }
        activityLock.unlock()

        guard !summary.isEmpty else { return }
        record(kind: "input.activity", fields: [
            "durationMs": durationMs,
            "counts": summary,
        ])
    }

    private func environmentFields() -> [String: Any] {
        let environment: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "bundle": Bundle.main.bundleIdentifier ?? "unknown",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
        ]
        return environment.merging(SecureEventInputDiagnostics.snapshot().traceFields) { _, new in new }
    }

    private func rotateTraceForNewCapture() {
        let previousURL = traceURL.deletingLastPathComponent()
            .appendingPathComponent("hyper-key-trace.previous.jsonl")
        try? FileManager.default.removeItem(at: previousURL)
        if FileManager.default.fileExists(atPath: traceURL.path) {
            try? FileManager.default.moveItem(at: traceURL, to: previousURL)
        }
        FileManager.default.createFile(atPath: traceURL.path, contents: nil)
    }

    private func rotateIfNeeded(incomingBytes: UInt64) {
        let size = ((try? FileManager.default.attributesOfItem(atPath: traceURL.path)[.size]) as? NSNumber)?.uint64Value ?? 0
        guard size + incomingBytes > Self.maxTraceBytes else { return }
        rotateTraceForNewCapture()
    }

    private func append(_ data: Data) {
        if !FileManager.default.fileExists(atPath: traceURL.path) {
            FileManager.default.createFile(atPath: traceURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: traceURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // The primary logger is deliberately avoided here: a disk error in
            // a diagnostic sink must not recurse or slow the event-tap thread.
        }
    }
}
