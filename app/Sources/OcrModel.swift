import AppKit
import CryptoKit
import Vision

// MARK: - Data Types

struct OcrTextBlock {
    let text: String
    let confidence: Float         // 0.0–1.0
    let boundingBox: CGRect       // normalized coordinates within window
}

struct OcrWindowResult {
    let wid: UInt32
    let app: String
    let title: String
    let frame: WindowFrame
    let texts: [OcrTextBlock]
    let fullText: String
    let timestamp: Date
}

// MARK: - OCR Scanner

final class OcrModel: ObservableObject {
    static let shared = OcrModel()

    @Published private(set) var results: [UInt32: OcrWindowResult] = [:]
    @Published private(set) var isScanning: Bool = false
    @Published var interval: TimeInterval = 60
    @Published var enabled: Bool = true

    private var timer: Timer?
    private var deepTimer: Timer?
    private let queue = DispatchQueue(label: "com.arach.lattices.ocr", qos: .background)
    private var imageHashes: [UInt32: Data] = [:]
    private var scanGeneration: Int = 0

    private let myPid = ProcessInfo.processInfo.processIdentifier

    private var prefs: Preferences { Preferences.shared }

    func start(interval: TimeInterval? = nil) {
        guard timer == nil else { return }
        if let interval { self.interval = interval }
        self.interval = prefs.ocrQuickInterval
        self.enabled = prefs.ocrEnabled
        guard enabled else {
            DiagnosticLog.shared.info("OcrModel: disabled by user preference")
            return
        }
        let deepInterval = prefs.ocrDeepInterval
        // Defer initial scan — let the first timer tick handle it (grace period on launch)
        DiagnosticLog.shared.info("OcrModel: starting (quick=\(self.interval)s/\(prefs.ocrQuickLimit)win, deep=\(deepInterval)s/\(prefs.ocrDeepLimit)win)")
        timer = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: true) { [weak self] _ in
            guard let self, self.enabled else { return }
            self.quickScan()
        }
        // Deep scan on a slower cadence
        deepTimer = Timer.scheduledTimer(withTimeInterval: deepInterval, repeats: true) { [weak self] _ in
            guard let self, self.enabled else { return }
            self.scan()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        deepTimer?.invalidate()
        deepTimer = nil
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        prefs.ocrEnabled = on
        if on && timer == nil {
            start()
        } else if !on {
            stop()
        }
    }

    // MARK: - Scan

    /// Quick scan: only the topmost frontmost windows (called every 60s)
    func quickScan() {
        scanWithLimit(prefs.ocrQuickLimit)
    }

    /// Deep scan: all visible windows (called every 2h, or manually via ocr.scan)
    func scan() {
        scanWithLimit(prefs.ocrDeepLimit)
    }

    private func scanWithLimit(_ limit: Int) {
        guard !isScanning else { return }
        DispatchQueue.main.async { self.isScanning = true }
        scanGeneration += 1
        let generation = scanGeneration

        queue.async { [weak self] in
            guard let self else { return }
            var windows = self.enumerateWindows()

            // Cap windows — CGWindowList returns front-to-back order,
            // so prefix gives us the topmost/frontmost windows first
            if windows.count > limit {
                windows = Array(windows.prefix(limit))
            }

            // For quick scans, merge new results into existing rather than replacing
            let previousResults = self.results
            let fresh: [UInt32: OcrWindowResult] = limit < self.prefs.ocrDeepLimit ? previousResults : [:]
            let newHashes: [UInt32: Data] = [:]
            let totalBlocks = 0

            self.processNextWindow(
                windows: windows,
                index: 0,
                generation: generation,
                previousResults: previousResults,
                fresh: fresh,
                newHashes: newHashes,
                totalBlocks: totalBlocks,
                changedResults: []
            )
        }
    }

    /// Process one window at a time, yielding back to the queue between each.
    /// This lets GCD schedule higher-priority work between windows.
    private func processNextWindow(
        windows: [WindowEntry],
        index: Int,
        generation: Int,
        previousResults: [UInt32: OcrWindowResult],
        fresh: [UInt32: OcrWindowResult],
        newHashes: [UInt32: Data],
        totalBlocks: Int,
        changedResults: [OcrWindowResult]
    ) {
        // Stale scan — a newer one started, abandon this one
        guard generation == scanGeneration else {
            DispatchQueue.main.async { self.isScanning = false }
            return
        }

        // All windows processed — publish results & persist diffs
        guard index < windows.count else {
            self.imageHashes = newHashes

            if !changedResults.isEmpty {
                OcrStore.shared.insert(results: changedResults)
            }

            DispatchQueue.main.async {
                self.results = fresh
                self.isScanning = false
            }

            EventBus.shared.post(.ocrScanComplete(
                windowCount: fresh.count,
                totalBlocks: totalBlocks
            ))
            return
        }

        var fresh = fresh
        var newHashes = newHashes
        var totalBlocks = totalBlocks
        var changedResults = changedResults

        let win = windows[index]

        if let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(win.wid),
            [.boundsIgnoreFraming, .bestResolution]
        ) {
            let hash = imageHash(cgImage)
            newHashes[win.wid] = hash

            if hash == imageHashes[win.wid], let prev = previousResults[win.wid] {
                // Unchanged — reuse cached result
                fresh[win.wid] = prev
                totalBlocks += prev.texts.count
            } else {
                // Changed — run OCR
                let blocks = recognizeText(in: cgImage)
                let fullText = blocks.map(\.text).joined(separator: "\n")
                totalBlocks += blocks.count

                let result = OcrWindowResult(
                    wid: win.wid,
                    app: win.app,
                    title: win.title,
                    frame: win.frame,
                    texts: blocks,
                    fullText: fullText,
                    timestamp: Date()
                )
                fresh[win.wid] = result
                changedResults.append(result)
            }
        }

        // Throttle: 100ms delay between windows to reduce CPU bursts
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.processNextWindow(
                windows: windows,
                index: index + 1,
                generation: generation,
                previousResults: previousResults,
                fresh: fresh,
                newHashes: newHashes,
                totalBlocks: totalBlocks,
                changedResults: changedResults
            )
        }
    }

    // MARK: - Window Enumeration

    private func enumerateWindows() -> [WindowEntry] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        var entries: [WindowEntry] = []

        for info in list {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary
            else { continue }

            // Skip own windows
            guard pid != myPid else { continue }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect),
                  rect.width >= 50, rect.height >= 50 else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }

            let frame = WindowFrame(
                x: Double(rect.origin.x),
                y: Double(rect.origin.y),
                w: Double(rect.width),
                h: Double(rect.height)
            )

            entries.append(WindowEntry(
                wid: wid,
                app: ownerName,
                pid: pid,
                title: title,
                frame: frame,
                spaceIds: [],
                isOnScreen: true,
                latticesSession: nil
            ))
        }

        return entries
    }

    // MARK: - Image Hashing

    private func imageHash(_ image: CGImage) -> Data {
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data as Data? else {
            return Data()
        }
        let digest = SHA256.hash(data: data as Data)
        return Data(digest)
    }

    // MARK: - Vision OCR

    private func recognizeText(in image: CGImage) -> [OcrTextBlock] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = prefs.ocrAccuracy == "fast" ? .fast : .accurate
        request.usesLanguageCorrection = true

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }

        return observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            return OcrTextBlock(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: obs.boundingBox
            )
        }
    }
}
