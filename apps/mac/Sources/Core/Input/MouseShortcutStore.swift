import AppKit
import Combine
import Foundation

final class MouseShortcutStore: ObservableObject {
    static let shared = MouseShortcutStore()

    /// Drives SwiftUI bindings; mutations always happen on main.
    @Published private(set) var config: MouseShortcutConfig

    let configURL: URL

    /// Lock-protected mirror of `config` for tap-thread reads. The mouse event
    /// tap fires on a non-main thread (EventTapThread) and reads
    /// `watchedButtonNumbers` to compute the consume-vs-pass verdict; mutating
    /// `config` (a struct) on main while reading from the tap thread is a
    /// torn-read race. All tap-thread accessors read this snapshot under
    /// `stateLock`.
    private let stateLock = NSLock()
    private var snapshot: MouseShortcutConfig
    private var lastLoadedModifiedDate: Date?

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lattices")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configURL = dir.appendingPathComponent("mouse-shortcuts.json")
        self.config = .defaults
        self.snapshot = .defaults
        ensureConfigFile()
        reload()
    }

    var tuning: MouseShortcutTuning {
        stateLock.lock(); defer { stateLock.unlock() }
        return snapshot.tuning
    }

    var enabledRules: [MouseShortcutRule] {
        stateLock.lock(); defer { stateLock.unlock() }
        return snapshot.rules.filter(\.enabled)
    }

    var watchedButtonNumbers: Set<Int64> {
        stateLock.lock(); defer { stateLock.unlock() }
        return Set(snapshot.rules.filter(\.enabled).map { Int64($0.trigger.button.rawButtonNumber) })
    }

    func hasEnabledRule(button: MouseShortcutButton, kind: MouseShortcutTriggerKind) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return snapshot.rules.contains { rule in
            rule.enabled
                && rule.trigger.button == button
                && rule.trigger.kind == kind
        }
    }

    var summaryLines: [String] {
        stateLock.lock(); defer { stateLock.unlock() }
        return snapshot.rules.filter(\.enabled).map { "\($0.trigger.triggerName) -> \($0.action.type.rawValue)" }
    }

    func visualHint(for button: MouseShortcutButton) -> MouseShortcutVisualDefinition? {
        stateLock.lock(); defer { stateLock.unlock() }
        return snapshot.rules.filter(\.enabled).first { $0.trigger.button == button && $0.visual != nil }?.visual
    }

    func ensureConfigFile() {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        write(config: .defaults)
    }

    func reload() {
        let newDate = modifiedDate()
        let newConfig: MouseShortcutConfig
        if let data = FileManager.default.contents(atPath: configURL.path) {
            do {
                newConfig = try JSONDecoder().decode(MouseShortcutConfig.self, from: data)
            } catch {
                DiagnosticLog.shared.error("MouseShortcutStore: failed to decode mouse-shortcuts.json - \(error.localizedDescription)")
                newConfig = .defaults
            }
        } else {
            newConfig = .defaults
        }
        stateLock.lock()
        snapshot = newConfig
        lastLoadedModifiedDate = newDate
        stateLock.unlock()
        // @Published mutation must happen on main.
        if Thread.isMainThread {
            config = newConfig
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.config = newConfig
            }
        }
    }

    func reloadIfNeeded() {
        // Called from the mouse event-tap thread (and from main paths). The
        // stat is cheap and thread-safe; we claim the new mtime up-front so
        // concurrent calls don't queue duplicate reloads while one is in
        // flight (if reload fails to decode, we'll retry on the next mtime
        // change).
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
        DiagnosticLog.shared.info("Mouse shortcuts restored to defaults")
    }

    func openConfiguration() {
        ensureConfigFile()
        NSWorkspace.shared.open(configURL)
    }

    func match(for event: MouseShortcutTriggerEvent) -> MouseShortcutMatchResult? {
        stateLock.lock()
        let rules = snapshot.rules.filter(\.enabled)
        stateLock.unlock()
        for rule in rules {
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
        let newDate = modifiedDate()
        stateLock.lock(); lastLoadedModifiedDate = newDate; stateLock.unlock()
    }

    private func modifiedDate() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: configURL.path)
        return attrs?[.modificationDate] as? Date
    }
}
