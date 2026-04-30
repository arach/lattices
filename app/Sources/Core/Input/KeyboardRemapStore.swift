import AppKit
import Combine
import Foundation

final class KeyboardRemapStore: ObservableObject {
    static let shared = KeyboardRemapStore()

    @Published private(set) var config: KeyboardRemapConfig

    let configURL: URL
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
        guard let data = FileManager.default.contents(atPath: configURL.path) else {
            config = .defaults
            return
        }

        do {
            config = try JSONDecoder().decode(KeyboardRemapConfig.self, from: data)
            lastLoadedModifiedDate = modifiedDate()
        } catch {
            DiagnosticLog.shared.error("KeyboardRemapStore: failed to decode keyboard-remaps.json - \(error.localizedDescription)")
            config = .defaults
        }
    }

    func reloadIfNeeded() {
        let currentModifiedDate = modifiedDate()
        guard currentModifiedDate != lastLoadedModifiedDate else { return }
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
        lastLoadedModifiedDate = modifiedDate()
    }

    private func modifiedDate() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: configURL.path)
        return attrs?[.modificationDate] as? Date
    }
}
