import AppKit
import Combine
import Foundation

final class KeyboardRemapStore: ObservableObject {
    static let shared = KeyboardRemapStore()

    @Published private(set) var config: KeyboardRemapConfig

    let configURL: URL
    private let stateLock = NSLock()
    private var lastLoadedModifiedDate: Date?

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lattices")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configURL = dir.appendingPathComponent("keyboard-remaps.json")
        self.config = .defaults
        ensureConfigFile()
        reload()
    }

    var enabledRules: [KeyboardRemapRule] {
        config.rules.filter(\.enabled)
    }

    var summaryLines: [String] {
        enabledRules.map(\.summaryLine)
    }

    var capsLockRule: KeyboardRemapRule? {
        enabledRules.first { $0.from == .capsLock }
    }

    func ensureConfigFile() {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        write(config: .defaults)
    }

    func reload() {
        // @Published mutation must run on main; hop if called off-main.
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.reload() }
            return
        }
        let newDate = modifiedDate()
        guard let data = FileManager.default.contents(atPath: configURL.path) else {
            config = .defaults
            stateLock.lock(); lastLoadedModifiedDate = newDate; stateLock.unlock()
            return
        }

        do {
            config = try JSONDecoder().decode(KeyboardRemapConfig.self, from: data)
            stateLock.lock(); lastLoadedModifiedDate = newDate; stateLock.unlock()
        } catch {
            DiagnosticLog.shared.error("KeyboardRemapStore: failed to decode keyboard-remaps.json - \(error.localizedDescription)")
            config = .defaults
        }
    }

    func reloadIfNeeded() {
        // Called from the keyboard event-tap thread on every key event. The
        // `stat` is cheap and thread-safe; the @Published mutation is hopped
        // to main inside reload(). We claim the new mtime up-front so
        // concurrent calls don't queue duplicate reloads while one is in
        // flight (if reload fails, we'll retry on the next mtime change).
        let currentModifiedDate = modifiedDate()
        stateLock.lock()
        let needsReload = currentModifiedDate != lastLoadedModifiedDate
        if needsReload {
            lastLoadedModifiedDate = currentModifiedDate
        }
        stateLock.unlock()
        guard needsReload else { return }
        reload()
    }

    func restoreDefaults() {
        write(config: .defaults)
        reload()
        DiagnosticLog.shared.info("Keyboard remaps restored to defaults")
    }

    func openConfiguration() {
        ensureConfigFile()
        NSWorkspace.shared.open(configURL)
    }

    private func write(config: KeyboardRemapConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
        let newDate = modifiedDate()
        stateLock.lock(); lastLoadedModifiedDate = newDate; stateLock.unlock()
    }

    private func modifiedDate() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: configURL.path)
        return attrs?[.modificationDate] as? Date
    }
}
