import AppKit
import SwiftUI

final class WindowPreviewStore: ObservableObject {
    static let shared = WindowPreviewStore()

    @Published private var images: [UInt32: NSImage] = [:]
    @Published private var loading: Set<UInt32> = []

    private var lastAttemptAt: [UInt32: Date] = [:]
    private var accessOrder: [UInt32] = []
    private var lastFront: UInt32?
    private let maxCached = 28            // enough to cover a full Exposé survey
    private let queue = DispatchQueue(label: "dev.lattices.app.window-preview", qos: .userInitiated)
    private let previewMaxSize = NSSize(width: 360, height: 190)

    private init() {
        // Keep the cache warm off the desktop poll, frugally: the frontmost window
        // (the dynamic layer) re-captures only when focus moves to it; the static
        // back layer is captured once and kept. Steady state ≈ zero captures.
        EventBus.shared.subscribe { [weak self] event in
            if case .windowsChanged = event {
                DispatchQueue.main.async { self?.warmTick() }
            }
        }
    }

    func image(for wid: UInt32) -> NSImage? {
        if images[wid] != nil {
            touchLRU(wid)
        }
        return images[wid]
    }

    func hasSettled(_ wid: UInt32) -> Bool {
        images[wid] != nil || (lastAttemptAt[wid] != nil && !loading.contains(wid))
    }

    func isLoading(_ wid: UInt32) -> Bool {
        loading.contains(wid)
    }

    func prewarm(windows: [WindowEntry], limit: Int = 4) {
        for window in windows.prefix(limit) {
            load(window: window)
        }
    }

    func load(window: WindowEntry) {
        if images[window.wid] != nil || loading.contains(window.wid) {
            return
        }

        let now = Date()
        if let lastAttemptAt = lastAttemptAt[window.wid], now.timeIntervalSince(lastAttemptAt) < 1.0 {
            return
        }
        lastAttemptAt[window.wid] = now

        loading.insert(window.wid)
        let wid = window.wid
        let frame = window.frame
        let startedAt = Date()

        queue.async { [weak self] in
            guard let self else { return }

            Task { [weak self] in
                guard let self else { return }

                let cgImage = await WindowCapture.image(
                    listOption: .optionIncludingWindow,
                    windowID: CGWindowID(wid),
                    imageOption: [.boundsIgnoreFraming, .nominalResolution]
                )

                let image = cgImage.map {
                    NSImage(
                        cgImage: $0,
                        size: self.previewSize(for: frame)
                    )
                }

                DispatchQueue.main.async {
                    self.loading.remove(wid)
                    let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    if let image {
                        self.images[wid] = image
                        self.touchLRU(wid)
                        self.evictIfNeeded()
                        if elapsedMs >= 80 {
                            DiagnosticLog.shared.info("HUDPreview: captured wid=\(wid) in \(elapsedMs)ms")
                        }
                    } else {
                        DiagnosticLog.shared.info("HUDPreview: capture unavailable wid=\(wid) after \(elapsedMs)ms")
                    }
                }
            }
        }
    }

    // MARK: - Sharing & freshness

    /// Drop a window's cached shot so it re-captures fresh next time. Used for the
    /// frontmost/active window — the one that actually changed.
    func invalidate(_ wid: UInt32) {
        images.removeValue(forKey: wid)
        loading.remove(wid)
        lastAttemptAt.removeValue(forKey: wid)
        accessOrder.removeAll { $0 == wid }
    }

    /// Write back a capture taken elsewhere (e.g. the Exposé survey) so the survey
    /// and HUD share one warm pool. Downscaled to the standard preview size.
    func ingest(cgImage: CGImage, for wid: UInt32, frame: WindowFrame) {
        images[wid] = NSImage(cgImage: cgImage, size: previewSize(for: frame))
        lastAttemptAt[wid] = Date()
        touchLRU(wid)
        evictIfNeeded()
    }

    /// One frugal warming pass, driven by the desktop poll. Reuses `load` — no new
    /// capture path. The frontmost (dynamic) window refreshes only when focus moves
    /// to it; the static back layer is captured once, a couple per tick.
    private func warmTick() {
        let windows = DesktopModel.shared.allWindows()
            .filter { $0.app != "Lattices" && $0.isOnScreen && !$0.title.isEmpty }
        guard !windows.isEmpty else { return }

        if let front = windows.min(by: { $0.zIndex < $1.zIndex }) {
            if lastFront != front.wid {
                invalidate(front.wid)
                lastFront = front.wid
            }
            load(window: front)
        }

        var filled = 0
        for w in windows where images[w.wid] == nil && !loading.contains(w.wid) {
            load(window: w)
            filled += 1
            if filled >= 2 { break }
        }
    }

    private func touchLRU(_ wid: UInt32) {
        accessOrder.removeAll { $0 == wid }
        accessOrder.append(wid)
    }

    private func evictIfNeeded() {
        while images.count > maxCached, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            images.removeValue(forKey: oldest)
            lastAttemptAt.removeValue(forKey: oldest)
        }
    }

    private func previewSize(for frame: WindowFrame) -> NSSize {
        let width = max(CGFloat(frame.w), CGFloat(1))
        let height = max(CGFloat(frame.h), CGFloat(1))
        let scale = min(
            previewMaxSize.width / width,
            previewMaxSize.height / height,
            CGFloat(1)
        )
        return NSSize(
            width: max(CGFloat(1), width * scale),
            height: max(CGFloat(1), height * scale)
        )
    }
}
