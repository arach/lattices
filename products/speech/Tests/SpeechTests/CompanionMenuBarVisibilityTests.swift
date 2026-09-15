import XCTest
@testable import SpeechAppRuntime

@MainActor
final class CompanionMenuBarVisibilityTests: XCTestCase {
    func testAutomaticTransitionsAndExplicitOverride() {
        XCTAssertTrue(CompanionMenuBarVisibility.visible(alwaysShow: false, runningBundleIDs: []))
        for id in CompanionMenuBarVisibility.latticesBundleIDs {
            XCTAssertFalse(CompanionMenuBarVisibility.visible(alwaysShow: false, runningBundleIDs: [id]))
            XCTAssertTrue(CompanionMenuBarVisibility.visible(alwaysShow: true, runningBundleIDs: [id]))
        }
        XCTAssertTrue(CompanionMenuBarVisibility.visible(alwaysShow: false, runningBundleIDs: ["unrelated.app"]))
        let suite = "speech-menu-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = CompanionMenuBarVisibility(defaults: defaults)
        visibility.alwaysShow = true
        XCTAssertTrue(visibility.isVisible)
        XCTAssertTrue(CompanionMenuBarVisibility(defaults: defaults).alwaysShow)
        visibility.alwaysShow = false
        XCTAssertFalse(defaults.bool(forKey: CompanionMenuBarVisibility.preferenceKey))
    }
}
