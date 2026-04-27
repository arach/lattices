import DeckKit
import Foundation

final class CompanionActivityLog {
    static let shared = CompanionActivityLog()

    private let lock = NSLock()
    private var entries: [DeckActivityLogEntry] = []
    private let maxEntries = 120

    private init() {
        EventBus.shared.subscribe { [weak self] event in
            self?.record(event)
        }
    }

    func record(tag: String, tint: String?, text: String) {
        let entry = DeckActivityLogEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            tag: tag,
            tint: tint,
            text: text
        )

        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()
    }

    func snapshot(limit: Int = 80) -> [DeckActivityLogEntry] {
        lock.lock()
        let copy = entries
        lock.unlock()

        return Array(copy.suffix(limit).reversed())
    }
}

private extension CompanionActivityLog {
    func record(_ event: ModelEvent) {
        switch event {
        case .windowsChanged(let windows, let added, let removed):
            let delta = [added.isEmpty ? nil : "+\(added.count)", removed.isEmpty ? nil : "-\(removed.count)"]
                .compactMap { $0 }
                .joined(separator: " ")
            let suffix = delta.isEmpty ? "" : " (\(delta))"
            record(tag: "WIN", tint: "blue", text: "\(windows.count) desktop windows\(suffix)")

        case .tmuxChanged(let sessions):
            record(tag: "TMUX", tint: "green", text: "\(sessions.count) tmux sessions indexed")

        case .layerSwitched(let index):
            record(tag: "LAYER", tint: "violet", text: "Switched workspace layer \(index + 1)")

        case .processesChanged(let interesting):
            record(tag: "PROC", tint: "amber", text: "\(interesting.count) terminal processes changed")

        case .ocrScanComplete(let windowCount, let totalBlocks):
            record(tag: "OCR", tint: "teal", text: "Scanned \(totalBlocks) text blocks across \(windowCount) windows")

        case .voiceCommand(let text, let confidence):
            let pct = Int((confidence * 100).rounded())
            record(tag: "VOICE", tint: "red", text: "\"\(text)\" · \(pct)%")
        }
    }
}
