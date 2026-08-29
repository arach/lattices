@testable import ActionCore
import Foundation
import XCTest

final class ActionPreferenceMigrationTests: XCTestCase {
    func testCopiesOnlyAllowlistedPreferencesAndPreservesTheirTypes() {
        withDomains { defaults, legacyDomain, destinationDomain in
            defaults.setPersistentDomain(
                [
                    "Action.AppearanceMode": "dark",
                    "Action.ThemeID": "legacy-theme",
                    "Action.LauncherSidebarIconsOnly": true,
                    "Action.LauncherSidebarLabelWidth": 184.5,
                    "Action.LibraryLayout": "gallery",
                    "Action.SettingsPane": "appearance",
                    "Action.SupervisionOverlay.Frame": "{{10, 20}, {300, 400}}",
                    "Action.SupervisionOverlay.Minimized": false,
                    "NSWindow Frame ActionLauncherWindow": "10 20 900 700 0 0 1512 982",
                    "ActionEditorialFont": "New York",
                    "AppleActionOnDoubleClick": "Minimize",
                    "Action.UnknownPreference": "do not copy",
                ],
                forName: legacyDomain
            )

            let result = ActionPreferenceMigration.migrateIfNeeded(
                defaults: defaults,
                legacyDomainName: legacyDomain,
                destinationDomainName: destinationDomain
            )
            let destination = defaults.persistentDomain(forName: destinationDomain)

            XCTAssertTrue(result.didRun)
            XCTAssertTrue(result.hadLegacyDomain)
            XCTAssertEqual(
                Set(result.migratedKeys),
                Set(ActionPreferenceMigration.allowedPreferenceKeys)
            )
            XCTAssertEqual(destination?["Action.AppearanceMode"] as? String, "dark")
            XCTAssertEqual(destination?["Action.LauncherSidebarIconsOnly"] as? Bool, true)
            XCTAssertEqual(destination?["Action.LauncherSidebarLabelWidth"] as? Double, 184.5)
            XCTAssertEqual(
                destination?["Action.SupervisionOverlay.Frame"] as? String,
                "{{10, 20}, {300, 400}}"
            )
            XCTAssertEqual(destination?["ActionEditorialFont"] as? String, "New York")
            XCTAssertNil(destination?["AppleActionOnDoubleClick"])
            XCTAssertNil(destination?["Action.UnknownPreference"])
            XCTAssertEqual(
                destination?[ActionPreferenceMigration.completionMarkerKey] as? Bool,
                true
            )
            XCTAssertEqual(
                destination?[ActionPreferenceMigration.hadLegacyDomainMarkerKey] as? Bool,
                true
            )
            XCTAssertEqual(
                destination?[ActionPreferenceMigration.permissionRegrantPendingMarkerKey] as? Bool,
                true
            )
        }
    }

    func testDestinationValuesWinDuringPartialMigration() {
        withDomains { defaults, legacyDomain, destinationDomain in
            defaults.setPersistentDomain(
                [
                    "Action.AppearanceMode": "light",
                    "Action.ThemeID": "legacy-theme",
                    "Action.SettingsPane": "appearance",
                ],
                forName: legacyDomain
            )
            defaults.setPersistentDomain(
                [
                    "Action.AppearanceMode": "system",
                    "Action.SettingsPane": "",
                ],
                forName: destinationDomain
            )

            let result = ActionPreferenceMigration.migrateIfNeeded(
                defaults: defaults,
                legacyDomainName: legacyDomain,
                destinationDomainName: destinationDomain
            )
            let destination = defaults.persistentDomain(forName: destinationDomain)

            XCTAssertEqual(destination?["Action.AppearanceMode"] as? String, "system")
            XCTAssertEqual(destination?["Action.ThemeID"] as? String, "legacy-theme")
            XCTAssertEqual(destination?["Action.SettingsPane"] as? String, "")
            XCTAssertEqual(result.migratedKeys, ["Action.ThemeID"])
        }
    }

    func testSecondRunIsNoOpEvenWhenLegacyValuesChange() {
        withDomains { defaults, legacyDomain, destinationDomain in
            defaults.setPersistentDomain(
                ["Action.LibraryLayout": "gallery"],
                forName: legacyDomain
            )
            let firstResult = ActionPreferenceMigration.migrateIfNeeded(
                defaults: defaults,
                legacyDomainName: legacyDomain,
                destinationDomainName: destinationDomain
            )
            defaults.setPersistentDomain(
                ["Action.LibraryLayout": "list"],
                forName: legacyDomain
            )

            let secondResult = ActionPreferenceMigration.migrateIfNeeded(
                defaults: defaults,
                legacyDomainName: legacyDomain,
                destinationDomainName: destinationDomain
            )
            let destination = defaults.persistentDomain(forName: destinationDomain)

            XCTAssertTrue(firstResult.didRun)
            XCTAssertFalse(secondResult.didRun)
            XCTAssertTrue(secondResult.hadLegacyDomain)
            XCTAssertTrue(secondResult.migratedKeys.isEmpty)
            XCTAssertEqual(destination?["Action.LibraryLayout"] as? String, "gallery")
        }
    }

    func testAbsentLegacyDomainStillCompletesMigration() {
        withDomains { defaults, legacyDomain, destinationDomain in
            let result = ActionPreferenceMigration.migrateIfNeeded(
                defaults: defaults,
                legacyDomainName: legacyDomain,
                destinationDomainName: destinationDomain
            )
            let destination = defaults.persistentDomain(forName: destinationDomain)

            XCTAssertTrue(result.didRun)
            XCTAssertFalse(result.hadLegacyDomain)
            XCTAssertTrue(result.migratedKeys.isEmpty)
            XCTAssertEqual(
                destination?[ActionPreferenceMigration.completionMarkerKey] as? Bool,
                true
            )
            XCTAssertEqual(
                destination?[ActionPreferenceMigration.hadLegacyDomainMarkerKey] as? Bool,
                false
            )
            XCTAssertEqual(
                destination?[ActionPreferenceMigration.permissionRegrantPendingMarkerKey] as? Bool,
                false
            )
        }
    }

    func testLegacyDomainIsNotRemoved() {
        withDomains { defaults, legacyDomain, destinationDomain in
            let legacy = ["Action.ThemeID": "legacy-theme"]
            defaults.setPersistentDomain(legacy, forName: legacyDomain)

            ActionPreferenceMigration.migrateIfNeeded(
                defaults: defaults,
                legacyDomainName: legacyDomain,
                destinationDomainName: destinationDomain
            )

            XCTAssertEqual(
                defaults.persistentDomain(forName: legacyDomain)?["Action.ThemeID"] as? String,
                "legacy-theme"
            )
        }
    }

    func testPermissionRegrantWarningCompletesOnlyWhenBothPermissionsAreGranted() {
        withDomains { defaults, legacyDomain, destinationDomain in
            defaults.setPersistentDomain(
                ["Action.ThemeID": "legacy-theme"],
                forName: legacyDomain
            )
            ActionPreferenceMigration.migrateIfNeeded(
                defaults: defaults,
                legacyDomainName: legacyDomain,
                destinationDomainName: destinationDomain
            )

            XCTAssertFalse(
                ActionPreferenceMigration.completePermissionRegrantIfReady(
                    accessibilityGranted: true,
                    screenRecordingGranted: false,
                    defaults: defaults,
                    destinationDomainName: destinationDomain
                )
            )
            XCTAssertEqual(
                defaults.persistentDomain(forName: destinationDomain)?[
                    ActionPreferenceMigration.permissionRegrantPendingMarkerKey
                ] as? Bool,
                true
            )

            XCTAssertTrue(
                ActionPreferenceMigration.completePermissionRegrantIfReady(
                    accessibilityGranted: true,
                    screenRecordingGranted: true,
                    defaults: defaults,
                    destinationDomainName: destinationDomain
                )
            )
            XCTAssertEqual(
                defaults.persistentDomain(forName: destinationDomain)?[
                    ActionPreferenceMigration.permissionRegrantPendingMarkerKey
                ] as? Bool,
                false
            )

            XCTAssertFalse(
                ActionPreferenceMigration.completePermissionRegrantIfReady(
                    accessibilityGranted: true,
                    screenRecordingGranted: true,
                    defaults: defaults,
                    destinationDomainName: destinationDomain
                )
            )
        }
    }

    func testIdentityConstantsDescribeTheLatticesMove() {
        XCTAssertEqual(ActionAppIdentity.mainBundleIdentifier, "dev.lattices.Action")
        XCTAssertEqual(ActionAppIdentity.agentBundleIdentifier, "dev.lattices.ActionAgent")
        XCTAssertEqual(ActionAppIdentity.legacyMainBundleIdentifier, "dev.action.Action")
        XCTAssertEqual(ActionAppIdentity.urlTypeIdentifier, "dev.lattices.Action.links")
    }

    private func withDomains(
        _ body: (UserDefaults, String, String) throws -> Void
    ) rethrows {
        let identifier = UUID().uuidString
        let suiteName = "ActionPreferenceMigrationTests.\(identifier)"
        let legacyDomain = "\(suiteName).legacy"
        let destinationDomain = "\(suiteName).destination"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: legacyDomain)
            defaults.removePersistentDomain(forName: destinationDomain)
            defaults.removePersistentDomain(forName: suiteName)
        }

        try body(defaults, legacyDomain, destinationDomain)
    }
}
