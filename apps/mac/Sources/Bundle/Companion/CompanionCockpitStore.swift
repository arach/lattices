import Foundation

/// The companion cockpit deck layout the Mac serves to paired iPads,
/// persisted in UserDefaults under the same keys Preferences used.
final class CompanionCockpitStore: ObservableObject {
    static let shared = CompanionCockpitStore()

    private enum DefaultsKey {
        static let cockpitLayout = "companion.cockpit.layout"
        static let cockpitLayoutVersion = "companion.cockpit.layoutVersion"
    }

    private static let currentCockpitLayoutVersion = 5

    @Published var layout: LatticesCompanionCockpitLayout {
        didSet { persistLayout() }
    }

    private init() {
        self.layout = Self.loadLayout()
    }

    func updateSlot(
        pageID: String,
        index: Int,
        shortcutID: String
    ) {
        var normalized = LatticesCompanionCockpitCatalog.normalized(layout)
        guard let pageIndex = normalized.pages.firstIndex(where: { $0.id == pageID }),
              normalized.pages[pageIndex].slotIDs.indices.contains(index) else {
            return
        }
        normalized.pages[pageIndex].slotIDs[index] = shortcutID
        layout = normalized
    }

    func reset() {
        layout = LatticesCompanionCockpitCatalog.defaultLayout
    }

    private static func loadLayout() -> LatticesCompanionCockpitLayout {
        if let data = UserDefaults.standard.data(forKey: DefaultsKey.cockpitLayout),
           let decoded = try? JSONDecoder().decode(LatticesCompanionCockpitLayout.self, from: data) {
            let savedVersion = UserDefaults.standard.integer(
                forKey: DefaultsKey.cockpitLayoutVersion
            )
            guard savedVersion < currentCockpitLayoutVersion else {
                return LatticesCompanionCockpitCatalog.normalized(decoded)
            }

            let migrated = migrateLayout(decoded, fromVersion: savedVersion)
            let normalized = LatticesCompanionCockpitCatalog.normalized(migrated)
            if let encoded = try? JSONEncoder().encode(normalized) {
                UserDefaults.standard.set(encoded, forKey: DefaultsKey.cockpitLayout)
            }
            UserDefaults.standard.set(
                currentCockpitLayoutVersion,
                forKey: DefaultsKey.cockpitLayoutVersion
            )
            return normalized
        }

        // One-time migration from the original web-builder draft. Early builds
        // wrote the editor JSON but did not promote it to the live cockpit
        // preference, so companions continued to receive the default deck.
        let draftURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".lattices/companion-deck-draft.json")
        if let draft = try? Data(contentsOf: draftURL),
           let imported = CompanionDeckBuilderView.importedLayout(fromBuilderDraft: draft) {
            let normalized = LatticesCompanionCockpitCatalog.normalized(imported)
            if let encoded = try? JSONEncoder().encode(normalized) {
                UserDefaults.standard.set(encoded, forKey: DefaultsKey.cockpitLayout)
            }
            UserDefaults.standard.set(
                currentCockpitLayoutVersion,
                forKey: DefaultsKey.cockpitLayoutVersion
            )
            return normalized
        }

        UserDefaults.standard.set(
            currentCockpitLayoutVersion,
            forKey: DefaultsKey.cockpitLayoutVersion
        )
        return LatticesCompanionCockpitCatalog.defaultLayout
    }

    /// Advances old deck layouts without replacing anything the user authored.
    /// Only exact untouched starter layouts advance; every renamed, reordered,
    /// added, removed, or repositioned page remains the user's layout.
    static func migrateLayout(
        _ layout: LatticesCompanionCockpitLayout,
        fromVersion: Int
    ) -> LatticesCompanionCockpitLayout {
        var migrated = layout
        if fromVersion < 2 {
            migrated = migratePasteDeviceIntoCompanionCockpit(migrated)
        }
        if fromVersion < 3,
           migrated == LatticesCompanionCockpitCatalog.legacyDefaultLayoutV2 {
            migrated = LatticesCompanionCockpitCatalog.legacyDefaultLayoutV3
        }
        if fromVersion < 4,
           migrated == LatticesCompanionCockpitCatalog.legacyDefaultLayoutV3 {
            migrated = LatticesCompanionCockpitCatalog.legacyDefaultLayoutV4
        }
        if fromVersion < 5,
           migrated == LatticesCompanionCockpitCatalog.legacyDefaultLayoutV4 {
            migrated = LatticesCompanionCockpitCatalog.defaultLayout
        }
        return migrated
    }

    /// Adds the phone-to-Mac gateway paste action to the v1 starter deck
    /// without replacing the user's other placements.
    private static func migratePasteDeviceIntoCompanionCockpit(
        _ layout: LatticesCompanionCockpitLayout
    ) -> LatticesCompanionCockpitLayout {
        var migrated = layout
        guard let index = migrated.pages.firstIndex(where: { $0.id == "dev" }) else {
            return migrated
        }

        var page = migrated.pages[index]
        let alreadyPresent = page.slotIDs.contains("paste-device")
            || page.slots?.contains(where: { $0.shortcutID == "paste-device" }) == true
        guard !alreadyPresent else { return migrated }

        if var slots = page.slots {
            let columns = max(2, page.columns)
            var rows = min(4, max(1, page.rows ?? 1))

            func intersects(_ candidate: LatticesCompanionCockpitLayout.Slot) -> Bool {
                slots.contains { slot in
                    candidate.col < slot.col + slot.colSpan
                        && candidate.col + candidate.colSpan > slot.col
                        && candidate.row < slot.row + slot.rowSpan
                        && candidate.row + candidate.rowSpan > slot.row
                }
            }

            var placement: LatticesCompanionCockpitLayout.Slot?
            while placement == nil && rows <= 4 {
                for span in [2, 1] where span <= columns {
                    for row in 0..<rows {
                        for col in 0...(columns - span) {
                            let candidate = LatticesCompanionCockpitLayout.Slot(
                                shortcutID: "paste-device",
                                col: col,
                                row: row,
                                colSpan: span
                            )
                            if !intersects(candidate) {
                                placement = candidate
                                break
                            }
                        }
                        if placement != nil { break }
                    }
                    if placement != nil { break }
                }
                if placement == nil && rows < 4 { rows += 1 } else { break }
            }

            if let placement {
                slots.append(placement)
                page.slots = slots
                page.rows = rows
            }
        } else {
            // The original flat starter occupied all 16 cells. Upgrade that
            // exact legacy page to today's starter; leave custom flat decks alone.
            let legacyStarter = [
                "key-copy", "key-paste", "key-undo", "key-shift-tab",
                "place-left", "place-right", "resize-wider", "resize-narrower",
                "switch-window-prev", "switch-window-next", "switch-app-prev", "switch-app-next",
                "layout-optimize", "mouse-find", "key-up", "key-down"
            ]
            if let starter = LatticesCompanionCockpitCatalog.legacyDefaultLayoutV2.pages.first(where: { $0.id == "dev" }) {
                var exactLegacyPage = starter
                exactLegacyPage.slotIDs = legacyStarter
                if page == exactLegacyPage {
                    page = starter
                }
            }
        }

        migrated.pages[index] = page
        return migrated
    }

    private func persistLayout() {
        let normalized = LatticesCompanionCockpitCatalog.normalized(layout)
        if normalized != layout {
            layout = normalized
            return
        }

        guard let data = try? JSONEncoder().encode(normalized) else { return }
        UserDefaults.standard.set(data, forKey: DefaultsKey.cockpitLayout)
    }
}
