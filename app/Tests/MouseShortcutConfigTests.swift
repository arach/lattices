import XCTest
@testable import Lattices

final class MouseShortcutConfigTests: XCTestCase {
    func testDefaultsIncludeMiddleClickPaste() throws {
        let pasteRule = try XCTUnwrap(MouseShortcutConfig.defaults.rules.first(where: { $0.id == "paste" }))

        XCTAssertEqual(MouseShortcutConfig.defaults.version, MouseShortcutConfig.currentVersion)
        XCTAssertTrue(pasteRule.enabled)
        XCTAssertEqual(pasteRule.trigger.button, .middle)
        XCTAssertEqual(pasteRule.trigger.kind, .click)
        XCTAssertNil(pasteRule.trigger.direction)
        XCTAssertEqual(pasteRule.action.type, .shortcutSend)
        XCTAssertEqual(pasteRule.action.shortcut?.key, "v")
        XCTAssertEqual(pasteRule.action.shortcut?.modifiers, [.command])
    }

    func testLegacyConfigMigrationAppendsPasteRule() {
        let legacy = MouseShortcutConfig(
            version: 1,
            tuning: .defaults,
            rules: [
                MouseShortcutRule(
                    id: "space-next",
                    enabled: true,
                    device: .any,
                    trigger: MouseShortcutTrigger(button: .middle, kind: .drag, direction: .right),
                    action: MouseShortcutActionDefinition(type: .spaceNext, shortcut: nil)
                ),
                MouseShortcutRule(
                    id: "custom",
                    enabled: true,
                    device: .any,
                    trigger: MouseShortcutTrigger(button: .button4, kind: .drag, direction: .left),
                    action: MouseShortcutActionDefinition(type: .spacePrevious, shortcut: nil)
                ),
            ]
        )

        let migrated = legacy.normalizedForCurrentVersion()

        XCTAssertEqual(migrated.version, MouseShortcutConfig.currentVersion)
        XCTAssertEqual(migrated.rules.prefix(2).map { $0.id }, ["space-next", "custom"])
        XCTAssertTrue(migrated.rules.contains(where: { $0.id == "paste" }))
        XCTAssertEqual(migrated.rules.filter { $0.id == "space-next" }.count, 1)
        XCTAssertEqual(migrated.rules.filter { $0.id == "custom" }.count, 1)
    }
}
