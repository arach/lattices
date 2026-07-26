import DeckKit
import Foundation

enum InteractionMode: String {
    case learning = "learning"
    case auto = "auto"
}

enum MouseGestureHUDStyle: String, CaseIterable, Identifiable {
    case technical
    case sober

    var id: String { rawValue }

    var label: String {
        switch self {
        case .technical:
            return "Technical"
        case .sober:
            return "Sober"
        }
    }
}

class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum CompanionDefaultsKey {
        static let bridgeEnabled = "companion.bridge.enabled"
        static let trackpadEnabled = "companion.trackpad.enabled"
        static let cockpitLayout = "companion.cockpit.layout"
        static let cockpitLayoutVersion = "companion.cockpit.layoutVersion"
    }

    private static let currentCockpitLayoutVersion = 2

    private static let dismissedCapabilitiesKey = "permissions.dismissed"

    @Published var terminal: Terminal {
        didSet { UserDefaults.standard.set(terminal.rawValue, forKey: "terminal") }
    }

    @Published var scanRoot: String {
        didSet { UserDefaults.standard.set(scanRoot, forKey: "scanRoot") }
    }

    @Published var mode: InteractionMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }

    @Published var dragSnapEnabled: Bool {
        didSet { UserDefaults.standard.set(dragSnapEnabled, forKey: "windowSnap.enabled") }
    }

    @Published var companionBridgeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(companionBridgeEnabled, forKey: CompanionDefaultsKey.bridgeEnabled)
            if companionBridgeEnabled {
                LatticesCompanionBridgeServer.shared.start()
            } else {
                LatticesCompanionBridgeServer.shared.stop()
            }
        }
    }

    @Published var companionTrackpadEnabled: Bool {
        didSet { UserDefaults.standard.set(companionTrackpadEnabled, forKey: CompanionDefaultsKey.trackpadEnabled) }
    }

    @Published var companionCockpitLayout: LatticesCompanionCockpitLayout {
        didSet { persistCompanionCockpitLayout() }
    }
    @Published var mouseGesturesEnabled: Bool {
        didSet { UserDefaults.standard.set(mouseGesturesEnabled, forKey: "mouseGestures.enabled") }
    }

    @Published var mouseGestureHUDVisualEnabled: Bool {
        didSet { UserDefaults.standard.set(mouseGestureHUDVisualEnabled, forKey: "mouseGestures.hud.visualEnabled") }
    }

    @Published var mouseGestureHUDAudioEnabled: Bool {
        didSet { UserDefaults.standard.set(mouseGestureHUDAudioEnabled, forKey: "mouseGestures.hud.audioEnabled") }
    }

    @Published var mouseGestureHUDStyle: MouseGestureHUDStyle {
        didSet { UserDefaults.standard.set(mouseGestureHUDStyle.rawValue, forKey: "mouseGestures.hud.style") }
    }

    @Published var cursorMarkerShape: CursorMarkerShape {
        didSet { UserDefaults.standard.set(cursorMarkerShape.rawValue, forKey: "cursorMarker.shape") }
    }

    @Published var cursorMarkerAngleDeg: Int {
        didSet { UserDefaults.standard.set(Self.normalizedCursorMarkerAngle(cursorMarkerAngleDeg), forKey: "cursorMarker.angleDeg") }
    }

    @Published var cursorMarkerSize: CursorMarkerSize {
        didSet { UserDefaults.standard.set(cursorMarkerSize.rawValue, forKey: "cursorMarker.size") }
    }

    @Published var keyboardRemapsEnabled: Bool {
        didSet { UserDefaults.standard.set(keyboardRemapsEnabled, forKey: "keyboardRemaps.enabled") }
    }

    // MARK: - Search & OCR

    @Published var ocrEnabled: Bool {
        didSet { UserDefaults.standard.set(!ocrEnabled, forKey: "ocr.disabled") }
    }

    @Published var ocrQuickInterval: Double {
        didSet { UserDefaults.standard.set(ocrQuickInterval, forKey: "ocr.interval") }
    }

    @Published var ocrDeepInterval: Double {
        didSet { UserDefaults.standard.set(ocrDeepInterval, forKey: "ocr.deepInterval") }
    }

    @Published var ocrQuickLimit: Int {
        didSet { UserDefaults.standard.set(ocrQuickLimit, forKey: "ocr.quickLimit") }
    }

    @Published var ocrDeepLimit: Int {
        didSet { UserDefaults.standard.set(ocrDeepLimit, forKey: "ocr.deepLimit") }
    }

    @Published var ocrDeepBudget: Int {
        didSet { UserDefaults.standard.set(ocrDeepBudget, forKey: "ocr.deepBudget") }
    }

    @Published var ocrAccuracy: String {
        didSet { UserDefaults.standard.set(ocrAccuracy, forKey: "ocr.accuracy") }
    }

    @Published var ocrRetentionDays: Int {
        didSet { UserDefaults.standard.set(ocrRetentionDays, forKey: "ocr.retentionDays") }
    }

    // MARK: - Permissions Assistant

    /// Capabilities the user has explicitly snoozed. Cleared per-capability when
    /// the user re-enters the relevant feature. Persisted as raw values.
    @Published var dismissedCapabilities: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(dismissedCapabilities), forKey: Self.dismissedCapabilitiesKey)
        }
    }

    func dismissCapability(_ rawValue: String) {
        dismissedCapabilities.insert(rawValue)
    }

    func clearDismissal(_ rawValue: String) {
        if dismissedCapabilities.contains(rawValue) {
            dismissedCapabilities.remove(rawValue)
        }
    }

    func isCapabilityDismissed(_ rawValue: String) -> Bool {
        dismissedCapabilities.contains(rawValue)
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "terminal"),
           let t = Terminal(rawValue: saved), t.isInstalled {
            self.terminal = t
        } else {
            self.terminal = Terminal.installed.first ?? .terminal
        }

        let savedRoot = UserDefaults.standard.string(forKey: "scanRoot") ?? ""
        if savedRoot.isEmpty {
            // Auto-detect a reasonable default
            let home = NSHomeDirectory()
            let candidates = ["\(home)/dev", "\(home)/Developer", "\(home)/projects", "\(home)/src"]
            self.scanRoot = candidates.first { FileManager.default.fileExists(atPath: $0) } ?? ""
        } else {
            self.scanRoot = savedRoot
        }

        if let saved = UserDefaults.standard.string(forKey: "mode"),
           let m = InteractionMode(rawValue: saved) {
            self.mode = m
        } else {
            self.mode = .learning
        }

        if UserDefaults.standard.object(forKey: "windowSnap.enabled") != nil {
            self.dragSnapEnabled = UserDefaults.standard.bool(forKey: "windowSnap.enabled")
        } else {
            self.dragSnapEnabled = true
        }

        if UserDefaults.standard.object(forKey: CompanionDefaultsKey.bridgeEnabled) != nil {
            self.companionBridgeEnabled = UserDefaults.standard.bool(forKey: CompanionDefaultsKey.bridgeEnabled)
        } else {
            self.companionBridgeEnabled = false
        }

        if UserDefaults.standard.object(forKey: CompanionDefaultsKey.trackpadEnabled) != nil {
            self.companionTrackpadEnabled = UserDefaults.standard.bool(forKey: CompanionDefaultsKey.trackpadEnabled)
        } else {
            self.companionTrackpadEnabled = false
        }

        self.companionCockpitLayout = Self.loadCompanionCockpitLayout()
        if UserDefaults.standard.object(forKey: "mouseGestures.enabled") != nil {
            self.mouseGesturesEnabled = UserDefaults.standard.bool(forKey: "mouseGestures.enabled")
        } else {
            self.mouseGesturesEnabled = true
        }

        if UserDefaults.standard.object(forKey: "mouseGestures.hud.visualEnabled") != nil {
            self.mouseGestureHUDVisualEnabled = UserDefaults.standard.bool(forKey: "mouseGestures.hud.visualEnabled")
        } else {
            self.mouseGestureHUDVisualEnabled = true
        }

        if UserDefaults.standard.object(forKey: "mouseGestures.hud.audioEnabled") != nil {
            self.mouseGestureHUDAudioEnabled = UserDefaults.standard.bool(forKey: "mouseGestures.hud.audioEnabled")
        } else {
            self.mouseGestureHUDAudioEnabled = true
        }

        if let savedStyle = UserDefaults.standard.string(forKey: "mouseGestures.hud.style"),
           let style = MouseGestureHUDStyle(rawValue: savedStyle) {
            self.mouseGestureHUDStyle = style
        } else {
            self.mouseGestureHUDStyle = .technical
        }

        if let savedShape = UserDefaults.standard.string(forKey: "cursorMarker.shape"),
           let shape = CursorMarkerShape(rawValue: savedShape),
           CursorMarkerShape.settingsOptions.contains(shape) {
            self.cursorMarkerShape = shape
        } else {
            self.cursorMarkerShape = .default
        }

        if UserDefaults.standard.object(forKey: "cursorMarker.angleDeg") != nil {
            self.cursorMarkerAngleDeg = Self.normalizedCursorMarkerAngle(UserDefaults.standard.integer(forKey: "cursorMarker.angleDeg"))
        } else {
            self.cursorMarkerAngleDeg = -8
        }

        if let savedSize = UserDefaults.standard.string(forKey: "cursorMarker.size"),
           let size = CursorMarkerSize(rawValue: savedSize),
           CursorMarkerSize.settingsOptions.contains(size) {
            self.cursorMarkerSize = size
        } else {
            self.cursorMarkerSize = .default
        }

        if UserDefaults.standard.object(forKey: "keyboardRemaps.enabled") != nil {
            self.keyboardRemapsEnabled = UserDefaults.standard.bool(forKey: "keyboardRemaps.enabled")
        } else {
            self.keyboardRemapsEnabled = true
        }
        // Search & OCR. Default off until the user explicitly enables it from
        // the Permissions Assistant or Search settings. Honors any explicit
        // ocr.disabled value already saved (true=off, false=on).
        if UserDefaults.standard.object(forKey: "ocr.disabled") != nil {
            self.ocrEnabled = !UserDefaults.standard.bool(forKey: "ocr.disabled")
        } else {
            self.ocrEnabled = false
        }

        let savedInterval = UserDefaults.standard.double(forKey: "ocr.interval")
        self.ocrQuickInterval = savedInterval > 0 ? savedInterval : 60

        let savedDeep = UserDefaults.standard.double(forKey: "ocr.deepInterval")
        self.ocrDeepInterval = savedDeep > 0 ? savedDeep : 7200

        let savedQL = UserDefaults.standard.integer(forKey: "ocr.quickLimit")
        self.ocrQuickLimit = savedQL > 0 ? savedQL : 5

        let savedDL = UserDefaults.standard.integer(forKey: "ocr.deepLimit")
        self.ocrDeepLimit = savedDL > 0 ? savedDL : 15

        let savedBudget = UserDefaults.standard.integer(forKey: "ocr.deepBudget")
        self.ocrDeepBudget = savedBudget > 0 ? savedBudget : 3

        let savedAcc = UserDefaults.standard.string(forKey: "ocr.accuracy") ?? "accurate"
        self.ocrAccuracy = savedAcc

        let savedRetention = UserDefaults.standard.integer(forKey: "ocr.retentionDays")
        self.ocrRetentionDays = savedRetention > 0 ? savedRetention : 7

        let dismissed = UserDefaults.standard.stringArray(forKey: Self.dismissedCapabilitiesKey) ?? []
        self.dismissedCapabilities = Set(dismissed)
    }

    func updateCompanionCockpitSlot(
        pageID: String,
        index: Int,
        shortcutID: String
    ) {
        var normalized = LatticesCompanionCockpitCatalog.normalized(companionCockpitLayout)
        guard let pageIndex = normalized.pages.firstIndex(where: { $0.id == pageID }),
              normalized.pages[pageIndex].slotIDs.indices.contains(index) else {
            return
        }
        normalized.pages[pageIndex].slotIDs[index] = shortcutID
        companionCockpitLayout = normalized
    }

    func resetCompanionCockpitLayout() {
        companionCockpitLayout = LatticesCompanionCockpitCatalog.defaultLayout
    }

    private static func loadCompanionCockpitLayout() -> LatticesCompanionCockpitLayout {
        if let data = UserDefaults.standard.data(forKey: CompanionDefaultsKey.cockpitLayout),
           let decoded = try? JSONDecoder().decode(LatticesCompanionCockpitLayout.self, from: data) {
            let normalized = LatticesCompanionCockpitCatalog.normalized(decoded)
            guard UserDefaults.standard.integer(forKey: CompanionDefaultsKey.cockpitLayoutVersion)
                    < currentCockpitLayoutVersion else {
                return normalized
            }

            let migrated = migrateCompanionCockpitLayout(normalized)
            if let encoded = try? JSONEncoder().encode(migrated) {
                UserDefaults.standard.set(encoded, forKey: CompanionDefaultsKey.cockpitLayout)
            }
            UserDefaults.standard.set(
                currentCockpitLayoutVersion,
                forKey: CompanionDefaultsKey.cockpitLayoutVersion
            )
            return migrated
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
                UserDefaults.standard.set(encoded, forKey: CompanionDefaultsKey.cockpitLayout)
            }
            UserDefaults.standard.set(
                currentCockpitLayoutVersion,
                forKey: CompanionDefaultsKey.cockpitLayoutVersion
            )
            return normalized
        }

        UserDefaults.standard.set(
            currentCockpitLayoutVersion,
            forKey: CompanionDefaultsKey.cockpitLayoutVersion
        )
        return LatticesCompanionCockpitCatalog.defaultLayout
    }

    /// Adds the phone-to-Mac gateway paste action to existing starter decks
    /// without replacing the user's other placements. The schema version makes
    /// this a one-time migration, so removing the tile later remains respected.
    private static func migrateCompanionCockpitLayout(
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
            if page.slotIDs == legacyStarter,
               let starter = LatticesCompanionCockpitCatalog.defaultLayout.pages.first(where: { $0.id == "dev" }) {
                page = starter
            }
        }

        page.subtitle = LatticesCompanionCockpitCatalog.defaultLayout.pages
            .first(where: { $0.id == "dev" })?.subtitle ?? page.subtitle
        migrated.pages[index] = page
        return migrated
    }

    private func persistCompanionCockpitLayout() {
        let normalized = LatticesCompanionCockpitCatalog.normalized(companionCockpitLayout)
        if normalized != companionCockpitLayout {
            companionCockpitLayout = normalized
            return
        }

        guard let data = try? JSONEncoder().encode(normalized) else { return }
        UserDefaults.standard.set(data, forKey: CompanionDefaultsKey.cockpitLayout)
    }

    static func normalizedCursorMarkerAngle(_ value: Int) -> Int {
        value <= -12 ? -16 : -8
    }
}
