import Foundation

/// UserDefaults keys for per-machine WORKSPACE state (window geometry, open
/// panels, per-note modes). App configuration and theme live in the
/// agent-first config file instead — see BlinkConfig / docs/config.md.
enum ConfigKeys {
    static let restoreSession = "blink.restoreSession"  // legacy; migrated into config.json
    static let defaultMode = "blink.defaultMode"        // legacy; migrated into config.json
    static let activeWorkspaceScope = "blink.activeWorkspaceScope"
    static func noteMode(_ id: String) -> String { "blink.noteMode.\(id)" }
}
