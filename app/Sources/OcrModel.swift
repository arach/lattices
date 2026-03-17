import AppKit
import CryptoKit
import Vision

// MARK: - Data Types

enum TextSource: String {
    case accessibility
    case ocr
}

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
    let source: TextSource
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
    private let axExtractor = AccessibilityTextExtractor()
    private var imageHashes: [UInt32: Data] = [:]
    private var lastAXHashes: [UInt32: Data] = [:]
    private var lastOCRTextHashes: [UInt32: Data] = [:]
    private var lastScanned: [UInt32: Date] = [:]
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
        DiagnosticLog.shared.info("OcrModel: starting (quick=\(self.interval)s/\(prefs.ocrQuickLimit)win, deep=\(deepInterval)s/\(prefs.ocrDeepLimit)win)")
        // Run initial scan immediately so search works right away
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.quickScan()
        }
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

    // MARK: - Single Window Scan

    /// Scan a single window by wid (AX extraction, instant).
    func scanSingle(wid: UInt32) {
        guard let entry = DesktopModel.shared.windows[wid] else { return }
        queue.async { [weak self] in
            guard let self else { return }
            if let axResult = self.axExtractor.extract(pid: entry.pid, wid: wid) {
                let blocks = axResult.texts.map { text in
                    OcrTextBlock(text: text, confidence: 1.0, boundingBox: .zero)
                }
                let result = OcrWindowResult(
                    wid: wid,
                    app: entry.app,
                    title: entry.title,
                    frame: entry.frame,
                    texts: blocks,
                    fullText: axResult.fullText,
                    timestamp: Date(),
                    source: .accessibility
                )
                OcrStore.shared.insert(results: [result])
                DispatchQueue.main.async {
                    self.results[wid] = result
                    DiagnosticLog.shared.info("OcrModel: single scan wid=\(wid) → \(axResult.texts.count) blocks")
                }
            }
        }
    }

    // MARK: - Scan

    /// Quick scan: AX-only text extraction for topmost windows (called every 60s).
    /// No screenshots, no Vision OCR — nearly free.
    func quickScan() {
        guard !isScanning else { return }
        DispatchQueue.main.async { self.isScanning = true }

        queue.async { [weak self] in
            guard let self else { return }
            let windows = Array(self.enumerateWindows().prefix(self.prefs.ocrQuickLimit))
            let previousResults = self.results
            var fresh = previousResults  // carry forward all existing results
            var changed = 0

            for win in windows {
                if let axResult = self.axExtractor.extract(pid: win.pid, wid: win.wid) {
                    let textHash = SHA256.hash(data: Data(axResult.fullText.utf8))
                    let hashData = Data(textHash)

                    if hashData == self.lastAXHashes[win.wid], previousResults[win.wid] != nil {
                        // Unchanged — carry forward cached result
                        continue
                    }

                    // Changed — build new result
                    self.lastAXHashes[win.wid] = hashData
                    changed += 1

                    let blocks = axResult.texts.map { text in
                        OcrTextBlock(text: text, confidence: 1.0, boundingBox: .zero)
                    }
                    let result = OcrWindowResult(
                        wid: win.wid,
                        app: win.app,
                        title: win.title,
                        frame: win.frame,
                        texts: blocks,
                        fullText: axResult.fullText,
                        timestamp: Date(),
                        source: .accessibility
                    )
                    fresh[win.wid] = result
                    OcrStore.shared.insert(results: [result])
                }
            }

            DiagnosticLog.shared.info("OcrModel: quick scan (AX) \(windows.count)/\(self.enumerateWindows().count) windows, \(changed) changed")

            DispatchQueue.main.async {
                self.results = fresh
                self.isScanning = false
            }

            EventBus.shared.post(.ocrScanComplete(
                windowCount: fresh.count,
                totalBlocks: fresh.values.reduce(0) { $0 + $1.texts.count }
            ))
        }
    }

    /// Deep scan: all visible windows (called every 2h, or manually via ocr.scan)
    /// Uses a budget to limit how many windows get OCR'd per tick.
    func scan() {
        guard !isScanning else { return }
        DispatchQueue.main.async { self.isScanning = true }
        scanGeneration += 1
        let generation = scanGeneration

        queue.async { [weak self] in
            guard let self else { return }
            var windows = self.enumerateWindows()
            let limit = self.prefs.ocrDeepLimit
            if windows.count > limit {
                windows = Array(windows.prefix(limit))
            }

            let previousResults = self.results
            var newHashes: [UInt32: Data] = [:]
            var changedWindows: [WindowEntry] = []
            var unchangedWindows: [WindowEntry] = []

            // Phase 1: capture + hash all windows (cheap)
            for win in windows {
                if let cgImage = CGWindowListCreateImage(
                    .null,
                    .optionIncludingWindow,
                    CGWindowID(win.wid),
                    [.boundsIgnoreFraming, .bestResolution]
                ) {
                    let hash = self.imageHash(cgImage)
                    newHashes[win.wid] = hash

                    if hash == self.imageHashes[win.wid], previousResults[win.wid] != nil {
                        unchangedWindows.append(win)
                    } else {
                        changedWindows.append(win)
                    }
                }
            }

            // Phase 2: budget which windows actually get OCR'd
            let budget = self.prefs.ocrDeepBudget
            let changedBudgeted = Array(changedWindows.prefix(budget))
            let remaining = max(0, budget - changedBudgeted.count)

            // Sort unchanged by lastScanned ascending (nil = stalest = highest priority)
            let stalestUnchanged = unchangedWindows.sorted { a, b in
                let aDate = self.lastScanned[a.wid] ?? .distantPast
                let bDate = self.lastScanned[b.wid] ?? .distantPast
                return aDate < bDate
            }
            let unchangedBudgeted = Array(stalestUnchanged.prefix(remaining))
            let toScan = changedBudgeted + unchangedBudgeted
            let toScanWids = Set(toScan.map(\.wid))

            // Carry forward cached results for non-budgeted windows
            var fresh: [UInt32: OcrWindowResult] = [:]
            var totalBlocks = 0
            for win in windows {
                if !toScanWids.contains(win.wid), let prev = previousResults[win.wid] {
                    fresh[win.wid] = prev
                    totalBlocks += prev.texts.count
                }
            }

            self.imageHashes = newHashes

            DiagnosticLog.shared.info("OcrModel: deep scan budget=\(budget), changed=\(changedWindows.count), scanning=\(toScan.count)/\(windows.count)")

            // Phase 3: OCR only the budgeted windows
            self.processNextWindow(
                windows: toScan,
                index: 0,
                generation: generation,
                previousResults: previousResults,
                fresh: fresh,
                newHashes: newHashes,
                totalBlocks: totalBlocks,
                changedResults: [],
                updateLastScanned: true
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
        changedResults: [OcrWindowResult],
        updateLastScanned: Bool = false
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
                    timestamp: Date(),
                    source: .ocr
                )
                fresh[win.wid] = result

                // Text-level dedup: if OCR text is identical to previous, skip store insert
                let textHash = Data(SHA256.hash(data: Data(fullText.utf8)))
                if textHash != lastOCRTextHashes[win.wid] {
                    changedResults.append(result)
                }
                lastOCRTextHashes[win.wid] = textHash
            }

            if updateLastScanned {
                self.lastScanned[win.wid] = Date()
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
                changedResults: changedResults,
                updateLastScanned: updateLastScanned
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
