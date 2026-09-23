import Foundation

/// Manages the Mission Control "Move left/right a space" symbolic hotkeys
/// (com.apple.symbolichotkeys 79/80 = Ctrl+←/→) while Instant Space Switching
/// is active.
///
/// These shortcuts are dispatched inside the WindowServer *before* the event
/// reaches any session event tap, so the tap cannot suppress the slide
/// animation — the hotkeys must be unregistered for
/// `SpaceSwitchInterceptor` to own the chord. The original `enabled` flags
/// are backed up in app preferences and restored when the feature turns off
/// or the app quits. If the app dies first, the System Settings toggle or a
/// `defaults write` restores them.
enum SpaceSwitchHotkeys {
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let dictKey = "AppleSymbolicHotKeys" as CFString
    private static let hotkeyIDs = ["79", "80"]
    private static let backupKey = "spaceSwitchKeys.hotkeyBackup"

    /// Whether this process currently holds the hotkeys disabled. Prevents
    /// repeated plist churn on every preference/permission re-emission.
    private static var applied = false

    /// True while Lattices holds the Mission Control Ctrl+arrow hotkeys
    /// unregistered — a synthetic Ctrl+arrow does nothing then.
    static var isHoldingSystemHotkeys: Bool { applied }

    static func disable() {
        guard !applied else { return }
        applied = true

        var dict = currentDict()
        var backup = UserDefaults.standard.dictionary(forKey: backupKey) ?? [:]
        var changed = false

        for id in hotkeyIDs {
            let entry = dict[id] as? [String: Any]
            // Backup only the original enabled flag — `value` is never touched.
            // An absent entry means the default binding, which is enabled.
            if backup[id] == nil {
                backup[id] = (entry?["enabled"] as? Int ?? 1) != 0
            }
            if (entry?["enabled"] as? Int ?? 1) != 0 {
                var newEntry = entry ?? [:]
                newEntry["enabled"] = 0
                dict[id] = newEntry
                changed = true
            }
        }

        UserDefaults.standard.set(backup, forKey: backupKey)
        if changed {
            writeDict(dict)
            applySettings()
            DiagnosticLog.shared.info("SpaceSwitch: Mission Control Ctrl+arrow hotkeys disabled")
        }
    }

    static func restore() {
        guard applied else { return }
        applied = false

        guard let backup = UserDefaults.standard.dictionary(forKey: backupKey), !backup.isEmpty else { return }
        var dict = currentDict()
        var changed = false

        for id in hotkeyIDs {
            guard let wasEnabled = backup[id] as? Bool else { continue }
            var newEntry = dict[id] as? [String: Any] ?? [:]
            let target = wasEnabled ? 1 : 0
            if (newEntry["enabled"] as? Int ?? 1) != target {
                newEntry["enabled"] = target
                dict[id] = newEntry
                changed = true
            }
        }

        UserDefaults.standard.removeObject(forKey: backupKey)
        if changed {
            writeDict(dict)
            applySettings()
            DiagnosticLog.shared.info("SpaceSwitch: Mission Control Ctrl+arrow hotkeys restored")
        }
    }

    private static func currentDict() -> [String: Any] {
        CFPreferencesCopyAppValue(dictKey, domain) as? [String: Any] ?? [:]
    }

    private static func writeDict(_ dict: [String: Any]) {
        CFPreferencesSetValue(dictKey, dict as CFPropertyList, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesAppSynchronize(domain)
    }

    /// Reloads per-user settings (including symbolic hotkeys) without logout.
    private static func applySettings() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        task.arguments = ["-u"]
        try? task.run()
    }
}
