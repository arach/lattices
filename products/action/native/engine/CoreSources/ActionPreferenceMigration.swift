import Foundation

public struct ActionPreferenceMigrationResult: Equatable, Sendable {
    public let didRun: Bool
    public let hadLegacyDomain: Bool
    public let migratedKeys: [String]

    public init(didRun: Bool, hadLegacyDomain: Bool, migratedKeys: [String]) {
        self.didRun = didRun
        self.hadLegacyDomain = hadLegacyDomain
        self.migratedKeys = migratedKeys
    }
}

public enum ActionPreferenceMigration {
    public static let completionMarkerKey =
        "Action.PreferenceMigration.dev.action.Action.v1.completed"
    public static let hadLegacyDomainMarkerKey =
        "Action.PreferenceMigration.dev.action.Action.v1.hadLegacyDomain"
    public static let permissionRegrantPendingMarkerKey =
        "Action.PreferenceMigration.dev.action.Action.v1.permissionRegrantPending"

    public static let allowedPreferenceKeys = [
        "Action.AppearanceMode",
        "Action.ThemeID",
        "Action.LauncherSidebarIconsOnly",
        "Action.LauncherSidebarLabelWidth",
        "Action.LibraryLayout",
        "Action.SettingsPane",
        "Action.SupervisionOverlay.Frame",
        "Action.SupervisionOverlay.Minimized",
        "NSWindow Frame ActionLauncherWindow",
        "ActionEditorialFont",
    ]

    /// Copies Action-owned preferences from the previous app identity once.
    ///
    /// Existing values in the new domain always win. The legacy domain is left
    /// intact so downgrades remain safe and migration never becomes destructive.
    @discardableResult
    public static func migrateIfNeeded(
        defaults: UserDefaults = .standard,
        legacyDomainName: String = ActionAppIdentity.legacyMainBundleIdentifier,
        destinationDomainName: String = ActionAppIdentity.mainBundleIdentifier
    ) -> ActionPreferenceMigrationResult {
        var destination = defaults.persistentDomain(forName: destinationDomainName) ?? [:]
        if destination[completionMarkerKey] as? Bool == true {
            return ActionPreferenceMigrationResult(
                didRun: false,
                hadLegacyDomain: destination[hadLegacyDomainMarkerKey] as? Bool == true,
                migratedKeys: []
            )
        }

        let legacy = defaults.persistentDomain(forName: legacyDomainName) ?? [:]
        let hadLegacyDomain = !legacy.isEmpty
        var migratedKeys: [String] = []

        for key in allowedPreferenceKeys where destination[key] == nil {
            guard let value = legacy[key] else {
                continue
            }
            destination[key] = value
            migratedKeys.append(key)
        }

        destination[hadLegacyDomainMarkerKey] = hadLegacyDomain
        destination[permissionRegrantPendingMarkerKey] = hadLegacyDomain
        destination[completionMarkerKey] = true
        defaults.setPersistentDomain(destination, forName: destinationDomainName)

        return ActionPreferenceMigrationResult(
            didRun: true,
            hadLegacyDomain: hadLegacyDomain,
            migratedKeys: migratedKeys
        )
    }

    /// Clears the one-shot migration warning after both new identities have
    /// the permissions Action needs. Later manual revocations should use the
    /// ordinary missing-permission copy, not be attributed to this migration.
    @discardableResult
    public static func completePermissionRegrantIfReady(
        accessibilityGranted: Bool,
        screenRecordingGranted: Bool,
        defaults: UserDefaults = .standard,
        destinationDomainName: String = ActionAppIdentity.mainBundleIdentifier
    ) -> Bool {
        guard accessibilityGranted, screenRecordingGranted else {
            return false
        }

        var destination = defaults.persistentDomain(forName: destinationDomainName) ?? [:]
        guard destination[permissionRegrantPendingMarkerKey] as? Bool == true else {
            return false
        }

        destination[permissionRegrantPendingMarkerKey] = false
        defaults.setPersistentDomain(destination, forName: destinationDomainName)
        return true
    }
}
