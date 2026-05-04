import AppKit
import Combine
import Foundation

final class KeyboardRemapStore: ObservableObject {
    static let shared = KeyboardRemapStore()

    @Published private(set) var config: KeyboardRemapConfig

    let configURL: URL
    /// Lock-protected mirror of `config` for tap-thread reads. The keyboard
    /// event tap runs on EventTapThread and must not read the @Published
    /// SwiftUI-facing config directly while main may be mutating it.
    private let stateLock = NSLock()
    private var snapshot: KeyboardRemapConfig
    private var lastLoadedModifiedDate: Date?
    private var lastReloadCheckAt: Date = .distantPast
    private var reloadCheckInFlight = false
    private let reloadCheckInterval: TimeInterval = 1.0

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lattices")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configURL = dir.appendingPathComponent("keyboard-remaps.json")
        self.config = .defaults
        self.snapshot = .defaults
        ensureConfigFile()
        reload()
    }

    var enabledRules: [KeyboardRemapRule] {
        stateLock.lock(); defer { stateLock.unlock() }
        return snapshot.rules.filter(\.enabled)
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
        let newConfig: KeyboardRemapConfig
        guard let data = FileManager.default.contents(atPath: configURL.path) else {
            newConfig = .defaults
            stateLock.lock()
            snapshot = newConfig
            lastLoadedModifiedDate = newDate
            stateLock.unlock()
            config = newConfig
            return
        }

        do {
            newConfig = try JSONDecoder().decode(KeyboardRemapConfig.self, from: data)
        } catch {
            DiagnosticLog.shared.error("KeyboardRemapStore: failed to decode keyboard-remaps.json - \(error.localizedDescription)")
            newConfig = .defaults
        }

        stateLock.lock()
        snapshot = newConfig
        lastLoadedModifiedDate = newDate
        stateLock.unlock()
        config = newConfig
    }

    func scheduleReloadCheckIfNeeded() {
        // Called from the keyboard event-tap thread. Keep this path to memory
        // bookkeeping only; filesystem work runs off the tap callback.
        let now = Date()
        stateLock.lock()
        guard !reloadCheckInFlight,
              now.timeIntervalSince(lastReloadCheckAt) >= reloadCheckInterval else {
            stateLock.unlock()
            return
        }
        reloadCheckInFlight = true
        lastReloadCheckAt = now
        stateLock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.reloadIfNeeded()
        }
    }

    private func reloadIfNeeded() {
        let currentModifiedDate = modifiedDate()
        stateLock.lock()
        let needsReload = currentModifiedDate != lastLoadedModifiedDate
        if needsReload {
            lastLoadedModifiedDate = currentModifiedDate
        }
        reloadCheckInFlight = false
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
        stateLock.lock()
        snapshot = config
        lastLoadedModifiedDate = newDate
        stateLock.unlock()
    }

    private func modifiedDate() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: configURL.path)
        return attrs?[.modificationDate] as? Date
    }
}
