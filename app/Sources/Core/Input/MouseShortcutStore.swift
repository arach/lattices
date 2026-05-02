import AppKit
import Combine
import Foundation

final class MouseShortcutStore: ObservableObject {
    static let shared = MouseShortcutStore()

    @Published private(set) var config: MouseShortcutConfig

    let configURL: URL
    private var lastLoadedModifiedDate: Date?

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lattices")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configURL = dir.appendingPathComponent("mouse-shortcuts.json")
        self.config = .defaults
        ensureConfigFile()
        reload()
    }

    var tuning: MouseShortcutTuning {
        config.tuning
    }

    var enabledRules: [MouseShortcutRule] {
        config.rules.filter(\.enabled)
    }

    var watchedButtonNumbers: Set<Int64> {
        Set(enabledRules.map { Int64($0.trigger.button.rawButtonNumber) })
    }

    var summaryLines: [String] {
        enabledRules.map { "\($0.trigger.triggerName) -> \($0.action.type.rawValue)" }
    }

    func visualHint(for button: MouseShortcutButton) -> MouseShortcutVisualDefinition? {
        enabledRules.first { $0.trigger.button == button && $0.visual != nil }?.visual
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
            config = try JSONDecoder().decode(MouseShortcutConfig.self, from: data)
            lastLoadedModifiedDate = modifiedDate()
        } catch {
            DiagnosticLog.shared.error("MouseShortcutStore: failed to decode mouse-shortcuts.json - \(error.localizedDescription)")
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
        DiagnosticLog.shared.info("Mouse shortcuts restored to defaults")
    }

    func openConfiguration() {
        ensureConfigFile()
        NSWorkspace.shared.open(configURL)
    }

    func match(for event: MouseShortcutTriggerEvent) -> MouseShortcutMatchResult? {
        for rule in enabledRules {
            guard rule.trigger.kind == event.kind,
                  rule.trigger.button == event.button,
                  rule.device.matches(event.device) else {
                continue
            }
            switch event.kind {
            case .drag:
                guard rule.trigger.direction == event.direction else { continue }
            case .shape:
                guard rule.trigger.shape == event.shape else { continue }
            case .click:
                break
            }

            return MouseShortcutMatchResult(
                rule: rule,
                action: rule.action,
                triggerName: rule.trigger.triggerName
            )
        }

        return nil
    }

    private func write(config: MouseShortcutConfig) {
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
