import XCTest
import DeckKit
@testable import Lattices

final class CompanionCockpitMappingTests: XCTestCase {
    func testSpaceTargetUsesSelectedDisplayAndZeroBasedIndex() throws {
        let displays = [
            DisplaySpaces(
                displayIndex: 0,
                displayId: "primary",
                spaces: [
                    SpaceInfo(id: 10, index: 1, display: 0, isCurrent: true),
                ],
                currentSpaceId: 10
            ),
            DisplaySpaces(
                displayIndex: 1,
                displayId: "secondary",
                spaces: [
                    SpaceInfo(id: 20, index: 1, display: 1, isCurrent: true),
                    SpaceInfo(id: 21, index: 2, display: 1, isCurrent: false),
                ],
                currentSpaceId: 20
            ),
        ]

        let target = try XCTUnwrap(
            LatticesDeckHost.resolveSpaceTarget(
                displays: displays,
                displayIndex: 1,
                index: 1
            )
        )
        XCTAssertEqual(target.display.displayIndex, 1)
        XCTAssertEqual(target.space.id, 21)
        XCTAssertEqual(target.space.index, 2)
        XCTAssertNil(
            LatticesDeckHost.resolveSpaceTarget(
                displays: displays,
                displayIndex: 0,
                index: 1
            )
        )
    }

    func testLegacyTrustedDeviceDoesNotGainScreenPreviewCapability() throws {
        let json = """
        {
          "id": "legacy-ipad",
          "name": "Legacy iPad",
          "publicKey": "public-key",
          "fingerprint": "ABCD-1234",
          "platform": "iPadOS",
          "pairedAt": 0,
          "lastSeenAt": 0
        }
        """.data(using: .utf8)!

        let record = try JSONDecoder().decode(LatticesCompanionTrustedDeviceRecord.self, from: json)
        XCTAssertEqual(record.effectiveCapabilities, DeckBridgeCapability.legacyCompanionCapabilities)
        XCTAssertFalse(record.effectiveCapabilities.contains(DeckBridgeCapability.screenPreview))
    }

    func testExistingExplicitPairingRequiresApprovalForScreenPreviewUpgrade() {
        let existing = DeckBridgeCapability.legacyCompanionCapabilities
        let requested = DeckBridgeCapability.defaultCompanionCapabilities
        XCTAssertEqual(
            LatticesCompanionSecurityCoordinator.additionalCapabilities(
                existing: existing,
                requested: requested
            ),
            [DeckBridgeCapability.screenPreview]
        )
        XCTAssertEqual(
            LatticesCompanionSecurityCoordinator.capabilitiesAfterPairingRequest(
                existing: existing,
                requested: requested,
                upgradeApproved: false
            ),
            existing.sorted()
        )
        XCTAssertTrue(
            LatticesCompanionSecurityCoordinator.capabilitiesAfterPairingRequest(
                existing: existing,
                requested: requested,
                upgradeApproved: true
            ).contains(DeckBridgeCapability.screenPreview)
        )
    }

    func testPairingDisclosureNamesScreenAndPointerAccess() {
        XCTAssertEqual(
            LatticesCompanionSecurityCoordinator.userFacingCapabilityName(
                DeckBridgeCapability.screenPreview
            ),
            "View this Mac's screen"
        )
        XCTAssertEqual(
            LatticesCompanionSecurityCoordinator.userFacingCapabilityName(
                DeckBridgeCapability.inputTrackpad
            ),
            "Move, click, and scroll the pointer"
        )

        let legacyEmptyRequestDisclosure = LatticesCompanionSecurityCoordinator
            .grantedCapabilities(for: [])
            .map(LatticesCompanionSecurityCoordinator.userFacingCapabilityName)
        XCTAssertTrue(legacyEmptyRequestDisclosure.contains("View this Mac's screen"))
        XCTAssertTrue(legacyEmptyRequestDisclosure.contains("Move, click, and scroll the pointer"))
    }

    func testDesktopPreviewIsNativeCompanionNavigation() throws {
        let state = LatticesCompanionCockpitCatalog.renderedState(
            layout: LatticesCompanionCockpitCatalog.defaultLayout,
            voice: nil,
            desktop: nil,
            layoutState: nil,
            talkie: .unavailable
        )

        let page = try XCTUnwrap(state.pages.first(where: { $0.id == "command" }))
        let tile = try XCTUnwrap(page.tiles.first(where: { $0.shortcutID == "mac-windows" }))
        let definition = try XCTUnwrap(LatticesCompanionCockpitCatalog.definition(for: "mac-windows"))

        XCTAssertEqual(tile.title, "Desktop Preview")
        XCTAssertEqual(tile.actionID, "desktop.preview.open")
        XCTAssertTrue(tile.payload.isEmpty)
        XCTAssertEqual(definition.category.id, "layout")
        XCTAssertNil(TalkieDeckProvider.shortcut(for: "mac-windows"))
    }

    func testStarterDeckFocusesOnFourCoreContexts() throws {
        let layout = LatticesCompanionCockpitCatalog.defaultLayout
        XCTAssertEqual(layout.pages.map(\.id), ["command", "dev", "media", "windows"])

        let shortcutIDs = layout.pages.flatMap { page in
            page.slots?.map(\.shortcutID) ?? page.slotIDs.filter { !$0.isEmpty }
        }
        XCTAssertEqual(shortcutIDs.count, 39)
        XCTAssertFalse(shortcutIDs.contains(where: { $0.hasPrefix("talkie-") }))
        XCTAssertFalse(shortcutIDs.contains(where: { $0.hasPrefix("voice-") }))
    }

    func testStarterDeckPositionedControlsStayInsideTheirPagesWithoutOverlap() throws {
        for page in LatticesCompanionCockpitCatalog.defaultLayout.pages {
            let rows = try XCTUnwrap(page.rows)
            let slots = try XCTUnwrap(page.slots)
            var occupied = Set<String>()

            for slot in slots {
                XCTAssertGreaterThanOrEqual(slot.col, 0)
                XCTAssertGreaterThanOrEqual(slot.row, 0)
                XCTAssertLessThanOrEqual(slot.col + slot.colSpan, page.columns)
                XCTAssertLessThanOrEqual(slot.row + slot.rowSpan, rows)

                for row in slot.row..<(slot.row + slot.rowSpan) {
                    for col in slot.col..<(slot.col + slot.colSpan) {
                        XCTAssertTrue(
                            occupied.insert("\(col),\(row)").inserted,
                            "\(page.id) overlaps at column \(col), row \(row)"
                        )
                    }
                }
            }
        }
    }

    func testStarterDeckRemainsFullyUsefulWithoutTalkieOrVoice() {
        let state = LatticesCompanionCockpitCatalog.renderedState(
            layout: LatticesCompanionCockpitCatalog.defaultLayout,
            voice: nil,
            desktop: nil,
            layoutState: nil,
            talkie: .unavailable
        )

        XCTAssertEqual(state.pages.map { $0.tiles.filter(\.isEnabled).count }, [8, 12, 7, 12])
        XCTAssertTrue(state.pages.flatMap(\.tiles).allSatisfy { $0.title != "Empty" })
        XCTAssertTrue(state.pages.flatMap(\.tiles).allSatisfy(\.isEnabled))
    }

    func testDeckBuilderLookupStartsWithPackagedAppResources() {
        let resources = URL(fileURLWithPath: "/Applications/Lattices.app/Contents/Resources")
        let roots = LatticesCompanionBridgeServer.deckBuilderResourceRoots(
            applicationResourceURL: resources,
            loadedBundles: []
        )

        XCTAssertEqual(roots.first, resources.appendingPathComponent("DeckBuilder", isDirectory: true))
    }

    func testBuilderCatalogIncludesEveryAssignableShortcut() throws {
        let json = try XCTUnwrap(CompanionDeckBuilderView.builderCatalogJSON())
        let data = try XCTUnwrap(json.data(using: .utf8))
        let groups = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let actualIDs = Set(groups.flatMap { group in
            (group["items"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        })
        let expectedIDs = Set(
            LatticesCompanionCockpitCatalog.shortcuts.map(\.id).filter { !$0.isEmpty }
        )

        XCTAssertEqual(actualIDs, expectedIDs)
    }

    func testBuilderRoundTripPreservesPageMetadataAndVisualOverrides() throws {
        let layout = LatticesCompanionCockpitLayout(pages: [
            .init(
                id: "personal",
                title: "My Page",
                subtitle: "A carefully tuned remote",
                columns: 3,
                rows: 2,
                slots: [
                    .init(
                        shortcutID: "key-copy",
                        col: 0,
                        row: 0,
                        colSpan: 2,
                        customLabel: "Copy the Good Part",
                        customBuilderIcon: "Sparkles",
                        customTint: "pink",
                        customCategory: "personal"
                    ),
                    .init(shortcutID: "key-paste", col: 2, row: 0),
                ]
            )
        ])

        let json = try XCTUnwrap(CompanionDeckBuilderView.builderJSON(for: layout))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let imported = try XCTUnwrap(CompanionDeckBuilderView.liveLayout(from: data))
        let page = try XCTUnwrap(imported.pages.first)
        let slots = try XCTUnwrap(page.slots)

        XCTAssertEqual(page.subtitle, "A carefully tuned remote")
        XCTAssertEqual(slots[0].customLabel, "Copy the Good Part")
        XCTAssertEqual(slots[0].customBuilderIcon, "Sparkles")
        XCTAssertEqual(slots[0].customTint, "pink")
        XCTAssertEqual(slots[0].customCategory, "personal")
        XCTAssertNil(slots[1].customLabel)
        XCTAssertNil(slots[1].customBuilderIcon)
        XCTAssertNil(slots[1].customTint)
        XCTAssertNil(slots[1].customCategory)

        let rendered = LatticesCompanionCockpitCatalog.renderedState(
            layout: imported,
            voice: nil,
            desktop: nil,
            layoutState: nil,
            talkie: .unavailable
        )
        let tile = try XCTUnwrap(rendered.pages.first?.tiles.first)
        XCTAssertEqual(tile.title, "Copy the Good Part")
        XCTAssertEqual(tile.iconSystemName, "sparkles")
        XCTAssertEqual(tile.categoryTint, "pink")
    }

    func testNormalizationPreservesAUserDefinedPageSetAndOrder() {
        let custom = LatticesCompanionCockpitLayout(pages: [
            .init(id: "favorites", title: "Favorites", columns: 3, slotIDs: ["key-copy"]),
            .init(id: "remote", title: "My Remote", columns: 4, slotIDs: ["mac-windows"]),
        ])

        let normalized = LatticesCompanionCockpitCatalog.normalized(custom)
        XCTAssertEqual(normalized.pages.map(\.id), ["favorites", "remote"])
        XCTAssertEqual(normalized.pages.map(\.title), ["Favorites", "My Remote"])
        XCTAssertEqual(normalized.pages[0].slotIDs.first, "key-copy")
        XCTAssertEqual(normalized.pages[0].slotIDs.count, 16)
    }

    func testNormalizationRelocatesClampedSlotsWithoutOverlap() throws {
        let custom = LatticesCompanionCockpitLayout(pages: [
            .init(
                id: "oversized",
                title: "Oversized",
                columns: 6,
                rows: 6,
                slots: (0..<16).map { index in
                    .init(shortcutID: "key-\(index)", col: index % 6, row: index / 6)
                }
            ),
        ])

        let page = try XCTUnwrap(LatticesCompanionCockpitCatalog.normalized(custom).pages.first)
        let slots = try XCTUnwrap(page.slots)
        var occupied = Set<String>()
        XCTAssertEqual(page.columns, 5)
        XCTAssertEqual(page.rows, 4)
        XCTAssertEqual(slots.count, 16)

        for slot in slots {
            for row in slot.row..<(slot.row + slot.rowSpan) {
                for col in slot.col..<(slot.col + slot.colSpan) {
                    XCTAssertTrue(occupied.insert("\(col),\(row)").inserted)
                }
            }
        }
    }

    func testV5MigrationReplacesOnlyUntouchedStarters() {
        XCTAssertEqual(
            Preferences.migrateCompanionCockpitLayout(
                LatticesCompanionCockpitCatalog.legacyDefaultLayoutV2,
                fromVersion: 2
            ),
            LatticesCompanionCockpitCatalog.defaultLayout
        )

        XCTAssertEqual(
            Preferences.migrateCompanionCockpitLayout(
                LatticesCompanionCockpitCatalog.legacyDefaultLayoutV3,
                fromVersion: 3
            ),
            LatticesCompanionCockpitCatalog.defaultLayout
        )

        XCTAssertEqual(
            Preferences.migrateCompanionCockpitLayout(
                LatticesCompanionCockpitCatalog.legacyDefaultLayoutV4,
                fromVersion: 4
            ),
            LatticesCompanionCockpitCatalog.defaultLayout
        )

        var customized = LatticesCompanionCockpitCatalog.legacyDefaultLayoutV2
        customized.pages[0].title = "My Commands"
        XCTAssertEqual(
            Preferences.migrateCompanionCockpitLayout(customized, fromVersion: 2),
            customized
        )

        var customizedV3 = LatticesCompanionCockpitCatalog.legacyDefaultLayoutV3
        customizedV3.pages[0].title = "My Remote"
        XCTAssertEqual(
            Preferences.migrateCompanionCockpitLayout(customizedV3, fromVersion: 3),
            customizedV3
        )

        var customizedV4 = LatticesCompanionCockpitCatalog.legacyDefaultLayoutV4
        customizedV4.pages[0].title = "My Remote"
        XCTAssertEqual(
            Preferences.migrateCompanionCockpitLayout(customizedV4, fromVersion: 4),
            customizedV4
        )
    }

    func testV5MigrationAdvancesTheUntouchedV1StarterThroughEveryVersion() throws {
        var v1Starter = LatticesCompanionCockpitCatalog.legacyDefaultLayoutV2
        let devIndex = try XCTUnwrap(v1Starter.pages.firstIndex(where: { $0.id == "dev" }))
        v1Starter.pages[devIndex].slotIDs = [
            "key-copy", "key-paste", "key-undo", "key-shift-tab",
            "place-left", "place-right", "resize-wider", "resize-narrower",
            "switch-window-prev", "switch-window-next", "switch-app-prev", "switch-app-next",
            "layout-optimize", "mouse-find", "key-up", "key-down",
        ]

        XCTAssertEqual(
            Preferences.migrateCompanionCockpitLayout(v1Starter, fromVersion: 1),
            LatticesCompanionCockpitCatalog.defaultLayout
        )

        var renamed = v1Starter
        renamed.pages[devIndex].title = "My Development Keys"
        renamed.pages[devIndex].subtitle = "Keep this personal grouping"
        XCTAssertEqual(
            Preferences.migrateCompanionCockpitLayout(renamed, fromVersion: 1),
            renamed
        )
    }
}
