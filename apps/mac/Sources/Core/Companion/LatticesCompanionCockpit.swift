import DeckKit
import Foundation

struct LatticesCompanionCockpitLayout: Codable, Equatable {
    /// Span-aware placement for a single key. `shortcutID == ""` marks an empty
    /// cell (a gap).
    struct Slot: Codable, Equatable {
        var shortcutID: String
        var col: Int
        var row: Int
        var colSpan: Int
        var rowSpan: Int
        /// Optional visual overrides authored in the Mac deck builder. The
        /// action remains catalog-backed; these fields only customize how the
        /// key is presented on companion devices.
        var customLabel: String?
        var customBuilderIcon: String?
        var customTint: String?
        var customCategory: String?

        init(
            shortcutID: String,
            col: Int,
            row: Int,
            colSpan: Int = 1,
            rowSpan: Int = 1,
            customLabel: String? = nil,
            customBuilderIcon: String? = nil,
            customTint: String? = nil,
            customCategory: String? = nil
        ) {
            self.shortcutID = shortcutID
            self.col = col
            self.row = row
            self.colSpan = colSpan
            self.rowSpan = rowSpan
            self.customLabel = customLabel
            self.customBuilderIcon = customBuilderIcon
            self.customTint = customTint
            self.customCategory = customCategory
        }
    }

    struct Page: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var subtitle: String?
        var columns: Int
        /// Explicit row count for span-aware pages; `nil` for legacy flat pages.
        var rows: Int?
        /// Legacy flat 16-slot layout (row-major into `columns`). Retained for
        /// back-compat and used as the fallback when `slots` is nil.
        var slotIDs: [String]
        /// Span-aware placement. When present it is authoritative — the deck
        /// renders keys by (col,row,colSpan,rowSpan); the web builder writes this.
        var slots: [Slot]?

        init(
            id: String,
            title: String,
            subtitle: String? = nil,
            columns: Int = 4,
            rows: Int? = nil,
            slotIDs: [String] = [],
            slots: [Slot]? = nil
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.columns = columns
            self.rows = rows
            self.slotIDs = slotIDs
            self.slots = slots
        }
    }

    var pages: [Page]
}

enum LatticesCompanionShortcutCategory: String, CaseIterable, Identifiable {
    case voice
    case agent
    case system
    case switching
    case layout
    case mouse
    case dev
    case media
    case talkie

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice:
            return "Voice"
        case .agent:
            return "Agent"
        case .system:
            return "System"
        case .switching:
            return "Switching"
        case .layout:
            return "Layout"
        case .mouse:
            return "Mouse"
        case .dev:
            return "Dev"
        case .media:
            return "Media"
        case .talkie:
            return "Talkie"
        }
    }

    var tintToken: String {
        switch self {
        case .voice:
            return "red"
        case .agent:
            return "violet"
        case .system:
            return "amber"
        case .switching, .layout:
            return "blue"
        case .mouse:
            return "teal"
        case .dev:
            return "green"
        case .media:
            return "pink"
        case .talkie:
            return "violet"
        }
    }
}

struct LatticesCompanionShortcutDefinition: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let iconSystemName: String
    let accentToken: String?
    let category: LatticesCompanionShortcutCategory
    let deckID: String? = nil
}

enum LatticesCompanionCockpitCatalog {
    private struct RenderedShortcut {
        var title: String
        var subtitle: String?
        var iconSystemName: String
        var accentToken: String?
        var deckID: String? = nil
        var categoryTint: String? = nil
        var actionID: String?
        var payload: [String: DeckValue]
        var isEnabled: Bool
        var isActive: Bool
    }

    static let slotCount = 16

    /// The original six-way starter is retained only so Preferences can tell an
    /// untouched deck from a personalized one during the v3 migration.
    static let legacyDefaultLayoutV2 = LatticesCompanionCockpitLayout(
        pages: [
            .init(
                id: "command",
                title: "Command",
                subtitle: "Core voice, system, and workspace moves",
                columns: 4,
                slotIDs: [
                    "voice-toggle", "voice-cancel", "key-escape", "key-enter",
                    "switch-app-prev", "switch-app-next", "switch-window-prev", "switch-window-next",
                    "layout-optimize", "mouse-find", "mouse-summon", "key-space",
                    "place-left", "place-right", "place-center", "place-maximize"
                ]
            ),
            .init(
                id: "talkie",
                title: "Talkie",
                subtitle: "Talkie capture, app switching, and companion actions",
                columns: 4,
                slotIDs: TalkieDeckProvider.talkiePageSlotIDs
            ),
            .init(
                id: "dev",
                title: "Dev",
                subtitle: "Clipboard, terminal, navigation, and edit shortcuts",
                columns: 4,
                slotIDs: [
                    "paste-device", "key-copy", "key-paste", "key-undo",
                    "key-escape", "key-enter", "key-up", "key-down",
                    "switch-window-prev", "switch-window-next", "switch-app-prev", "switch-app-next",
                    "layout-optimize", "mouse-joystick", "place-left", "place-right"
                ]
            ),
            .init(
                id: "media",
                title: "Media",
                subtitle: "Media-friendly window and keyboard controls",
                columns: 4,
                slotIDs: [
                    "key-space", "key-escape", "key-left", "key-right",
                    "place-center", "place-maximize", "resize-grow", "resize-shrink",
                    "switch-app-prev", "switch-app-next", "mouse-summon", "mouse-find",
                    "place-top-left", "place-top-right", "place-bottom-left", "place-bottom-right"
                ]
            ),
            .init(
                id: "windows",
                title: "Windows",
                subtitle: "Placement and resize macros for the frontmost window",
                columns: 4,
                slotIDs: [
                    "place-top-left", "place-top-right", "place-bottom-left", "place-bottom-right",
                    "place-left-third", "place-center-third", "place-right-third", "place-center",
                    "resize-wider", "resize-narrower", "resize-taller", "resize-shorter",
                    "resize-grow", "resize-shrink", "place-left", "place-right"
                ]
            ),
            .init(
                id: "voice",
                title: "Voice",
                subtitle: "Hands-off voice and transcript controls",
                columns: 4,
                slotIDs: [
                    "voice-toggle", "voice-cancel", "key-escape", "key-enter",
                    "layout-optimize", "switch-app-prev", "switch-app-next", "mouse-find",
                    "place-left", "place-right", "place-center", "place-maximize",
                    "key-copy", "key-paste", "key-undo", "key-space"
                ]
            ),
        ]
    )

    /// The first job-based starter shipped briefly as v3. Retain it so an exact,
    /// untouched copy can move forward without changing personalized decks.
    static let legacyDefaultLayoutV3 = LatticesCompanionCockpitLayout(
        pages: [
            .init(
                id: "remote",
                title: "Remote",
                subtitle: "See and directly control this Mac",
                columns: 4,
                rows: 3,
                slots: [
                    .init(shortcutID: "mac-windows", col: 0, row: 0, colSpan: 2, rowSpan: 2),
                    .init(shortcutID: "mouse-joystick", col: 2, row: 0, colSpan: 2, rowSpan: 2),
                    .init(shortcutID: "talkie-search", col: 0, row: 2, colSpan: 2),
                    .init(shortcutID: "paste-device", col: 2, row: 2, colSpan: 2),
                ]
            ),
            .init(
                id: "move",
                title: "Move",
                subtitle: "Navigate apps and arrange the current window",
                columns: 4,
                rows: 4,
                slots: [
                    .init(shortcutID: "switch-app-prev", col: 0, row: 0, colSpan: 2),
                    .init(shortcutID: "switch-app-next", col: 2, row: 0, colSpan: 2),
                    .init(shortcutID: "switch-window-prev", col: 0, row: 1, colSpan: 2),
                    .init(shortcutID: "switch-window-next", col: 2, row: 1, colSpan: 2),
                    .init(shortcutID: "place-left", col: 0, row: 2),
                    .init(shortcutID: "place-center", col: 1, row: 2),
                    .init(shortcutID: "place-right", col: 2, row: 2),
                    .init(shortcutID: "place-maximize", col: 3, row: 2),
                    .init(shortcutID: "mouse-find", col: 0, row: 3),
                    .init(shortcutID: "mouse-summon", col: 1, row: 3),
                    .init(shortcutID: "layout-optimize", col: 2, row: 3, colSpan: 2),
                ]
            ),
            .init(
                id: "speak-run",
                title: "Speak & Run",
                subtitle: "Create, capture, and delegate",
                columns: 4,
                rows: 4,
                slots: [
                    .init(shortcutID: "talkie-dictate", col: 0, row: 0, colSpan: 2),
                    .init(shortcutID: "talkie-settings", col: 2, row: 0, colSpan: 2),
                    .init(shortcutID: "talkie-record", col: 0, row: 1, colSpan: 2),
                    .init(shortcutID: "talkie-keyboard", col: 2, row: 1, colSpan: 2),
                    .init(shortcutID: "voice-toggle", col: 0, row: 2),
                    .init(shortcutID: "voice-cancel", col: 1, row: 2),
                    .init(shortcutID: "talkie-memos", col: 2, row: 2),
                    .init(shortcutID: "mac-sessions", col: 3, row: 2),
                    .init(shortcutID: "mac-claude", col: 0, row: 3),
                    .init(shortcutID: "talkie-agent", col: 1, row: 3),
                    .init(shortcutID: "talkie-ssh", col: 2, row: 3),
                    .init(shortcutID: "talkie-command", col: 3, row: 3),
                ]
            ),
        ]
    )

    /// The companion is a remote for the Mac in front of the user, not a
    /// catalog of the subsystems that happen to implement its commands. Keep
    /// the starter deliberately small and job-based; the complete catalog
    /// remains available in the Mac deck builder.
    static let defaultLayout = LatticesCompanionCockpitLayout(
        pages: [
            .init(
                id: "remote",
                title: "Remote",
                subtitle: "Couch controls that complement the live trackpad",
                columns: 4,
                rows: 2,
                slots: [
                    .init(shortcutID: "mac-windows", col: 0, row: 0, colSpan: 2),
                    .init(shortcutID: "paste-device", col: 2, row: 0, colSpan: 2),
                    .init(shortcutID: "mouse-find", col: 0, row: 1, colSpan: 2),
                    .init(shortcutID: "mouse-summon", col: 2, row: 1, colSpan: 2),
                ]
            ),
            .init(
                id: "move",
                title: "Move",
                subtitle: "Navigate apps and arrange the current window",
                columns: 4,
                rows: 4,
                slots: [
                    .init(shortcutID: "switch-app-prev", col: 0, row: 0, colSpan: 2),
                    .init(shortcutID: "switch-app-next", col: 2, row: 0, colSpan: 2),
                    .init(shortcutID: "switch-window-prev", col: 0, row: 1, colSpan: 2),
                    .init(shortcutID: "switch-window-next", col: 2, row: 1, colSpan: 2),
                    .init(shortcutID: "place-left", col: 0, row: 2),
                    .init(shortcutID: "place-center", col: 1, row: 2),
                    .init(shortcutID: "place-right", col: 2, row: 2),
                    .init(shortcutID: "place-maximize", col: 3, row: 2),
                    .init(shortcutID: "resize-grow", col: 0, row: 3),
                    .init(shortcutID: "resize-shrink", col: 1, row: 3),
                    .init(shortcutID: "layout-optimize", col: 2, row: 3, colSpan: 2),
                ]
            ),
            .init(
                id: "speak-run",
                title: "Speak & Run",
                subtitle: "Voice, capture, and repeatable work",
                columns: 4,
                rows: 3,
                slots: [
                    .init(shortcutID: "voice-toggle", col: 0, row: 0, colSpan: 2),
                    .init(shortcutID: "voice-cancel", col: 2, row: 0, colSpan: 2),
                    .init(shortcutID: "talkie-dictate", col: 0, row: 1, colSpan: 2),
                    .init(shortcutID: "talkie-record", col: 2, row: 1, colSpan: 2),
                    .init(shortcutID: "talkie-settings", col: 0, row: 2, colSpan: 2),
                    .init(shortcutID: "mac-sessions", col: 2, row: 2, colSpan: 2),
                ]
            ),
        ]
    )

    static let shortcuts: [LatticesCompanionShortcutDefinition] = [
        .init(id: "", title: "Empty", subtitle: "Leave this slot unused", iconSystemName: "square.dashed", accentToken: nil, category: .layout),
        // Keep the legacy `mac-windows` slot id so saved deck layouts remain
        // valid, but own the definition here. Desktop Preview is Lattices
        // navigation and must never inherit Talkie's perform/open fallback.
        .init(id: "mac-windows", title: "Desktop Preview", subtitle: "View this Mac's screen on your iPad", iconSystemName: "display", accentToken: "green", category: .layout),
    ] + TalkieDeckProvider.shortcuts.map {
        LatticesCompanionShortcutDefinition(
            id: $0.id,
            title: $0.title,
            subtitle: $0.subtitle,
            iconSystemName: $0.iconSystemName,
            accentToken: $0.accentToken,
            category: .talkie
        )
    } + [
        .init(id: "voice-toggle", title: "Voice Toggle", subtitle: "Start or stop hands-off voice", iconSystemName: "waveform.badge.mic", accentToken: "voice", category: .voice),
        .init(id: "voice-cancel", title: "Voice Cancel", subtitle: "Cancel the current voice turn", iconSystemName: "xmark.circle.fill", accentToken: "rose", category: .voice),
        .init(id: "switch-app-prev", title: "Previous App", subtitle: "Focus the prior visible application", iconSystemName: "chevron.left.square.fill", accentToken: "switch", category: .switching),
        .init(id: "switch-app-next", title: "Next App", subtitle: "Focus the next visible application", iconSystemName: "chevron.right.square.fill", accentToken: "switch", category: .switching),
        .init(id: "switch-window-prev", title: "Previous Window", subtitle: "Step backward through visible windows", iconSystemName: "rectangle.on.rectangle.circle.fill", accentToken: "switch", category: .switching),
        .init(id: "switch-window-next", title: "Next Window", subtitle: "Step forward through visible windows", iconSystemName: "rectangle.on.rectangle.circle", accentToken: "switch", category: .switching),
        .init(id: "layout-optimize", title: "Optimize", subtitle: "Retile visible windows", iconSystemName: "rectangle.3.group.fill", accentToken: "layout", category: .layout),
        .init(id: "place-left", title: "Place Left", subtitle: "Snap the frontmost window left", iconSystemName: "rectangle.leadinghalf.filled", accentToken: "layout", category: .layout),
        .init(id: "place-right", title: "Place Right", subtitle: "Snap the frontmost window right", iconSystemName: "rectangle.trailinghalf.filled", accentToken: "layout", category: .layout),
        .init(id: "place-top-left", title: "Top Left", subtitle: "Move to the upper-left quarter", iconSystemName: "rectangle.inset.topleft.filled", accentToken: "layout", category: .layout),
        .init(id: "place-top-right", title: "Top Right", subtitle: "Move to the upper-right quarter", iconSystemName: "rectangle.inset.topright.filled", accentToken: "layout", category: .layout),
        .init(id: "place-bottom-left", title: "Bottom Left", subtitle: "Move to the lower-left quarter", iconSystemName: "rectangle.inset.bottomleft.filled", accentToken: "layout", category: .layout),
        .init(id: "place-bottom-right", title: "Bottom Right", subtitle: "Move to the lower-right quarter", iconSystemName: "rectangle.inset.bottomright.filled", accentToken: "layout", category: .layout),
        .init(id: "place-center", title: "Center", subtitle: "Center the frontmost window", iconSystemName: "plus.rectangle.on.rectangle", accentToken: "layout", category: .layout),
        .init(id: "place-maximize", title: "Maximize", subtitle: "Expand to the visible screen", iconSystemName: "macwindow", accentToken: "layout", category: .layout),
        .init(id: "place-left-third", title: "Left Third", subtitle: "Move into the left third", iconSystemName: "rectangle.leadingthird.inset.filled", accentToken: "layout", category: .layout),
        .init(id: "place-center-third", title: "Center Third", subtitle: "Move into the center third", iconSystemName: "rectangle.center.inset.filled", accentToken: "layout", category: .layout),
        .init(id: "place-right-third", title: "Right Third", subtitle: "Move into the right third", iconSystemName: "rectangle.trailingthird.inset.filled", accentToken: "layout", category: .layout),
        .init(id: "resize-wider", title: "Wider", subtitle: "Increase width", iconSystemName: "arrow.left.and.right.circle.fill", accentToken: "layout", category: .layout),
        .init(id: "resize-narrower", title: "Narrower", subtitle: "Reduce width", iconSystemName: "arrow.left.and.right.circle", accentToken: "layout", category: .layout),
        .init(id: "resize-taller", title: "Taller", subtitle: "Increase height", iconSystemName: "arrow.up.and.down.circle.fill", accentToken: "layout", category: .layout),
        .init(id: "resize-shorter", title: "Shorter", subtitle: "Reduce height", iconSystemName: "arrow.up.and.down.circle", accentToken: "layout", category: .layout),
        .init(id: "resize-grow", title: "Grow", subtitle: "Expand both dimensions", iconSystemName: "plus.rectangle.fill.on.rectangle.fill", accentToken: "layout", category: .layout),
        .init(id: "resize-shrink", title: "Shrink", subtitle: "Reduce both dimensions", iconSystemName: "minus.rectangle", accentToken: "layout", category: .layout),
        .init(id: "mouse-find", title: "Find Mouse", subtitle: "Pulse the current cursor position", iconSystemName: "scope", accentToken: "mouse", category: .mouse),
        .init(id: "mouse-summon", title: "Summon Mouse", subtitle: "Bring the cursor to center screen", iconSystemName: "dot.scope", accentToken: "mouse", category: .mouse),
        .init(id: "mouse-joystick", title: "Joystick", subtitle: "Continuously steer the Mac pointer", iconSystemName: "circle.circle.fill", accentToken: "mouse", category: .mouse),
        .init(id: "paste-device", title: "Paste from iPhone", subtitle: "Send the phone clipboard through the secure bridge", iconSystemName: "rectangle.portrait.and.arrow.forward", accentToken: "dev", category: .dev),
        .init(id: "key-escape", title: "Escape", subtitle: "Send Escape", iconSystemName: "escape", accentToken: "system", category: .system),
        .init(id: "key-copy", title: "Copy", subtitle: "Send Command-C", iconSystemName: "doc.on.doc", accentToken: "system", category: .system),
        .init(id: "key-paste", title: "Paste", subtitle: "Send Command-V", iconSystemName: "doc.on.clipboard", accentToken: "system", category: .system),
        .init(id: "key-undo", title: "Undo", subtitle: "Send Command-Z", iconSystemName: "arrow.uturn.backward", accentToken: "system", category: .system),
        .init(id: "key-shift-tab", title: "Back Tab", subtitle: "Send Shift-Tab", iconSystemName: "arrowshape.turn.up.left", accentToken: "system", category: .system),
        .init(id: "key-space", title: "Space", subtitle: "Send Space", iconSystemName: "space", accentToken: "system", category: .system),
        .init(id: "key-enter", title: "Enter", subtitle: "Send Return", iconSystemName: "return", accentToken: "system", category: .system),
        .init(id: "key-left", title: "Left", subtitle: "Send Left Arrow", iconSystemName: "arrow.left", accentToken: "system", category: .system),
        .init(id: "key-right", title: "Right", subtitle: "Send Right Arrow", iconSystemName: "arrow.right", accentToken: "system", category: .system),
        .init(id: "key-up", title: "Up", subtitle: "Send Up Arrow", iconSystemName: "arrow.up", accentToken: "system", category: .system),
        .init(id: "key-down", title: "Down", subtitle: "Send Down Arrow", iconSystemName: "arrow.down", accentToken: "system", category: .system),
    ]

    static func definition(for shortcutID: String) -> LatticesCompanionShortcutDefinition? {
        shortcuts.first(where: { $0.id == shortcutID })
    }

    static func normalized(_ layout: LatticesCompanionCockpitLayout) -> LatticesCompanionCockpitLayout {
        let sourcePages = layout.pages.isEmpty ? defaultLayout.pages : layout.pages
        var usedPageIDs = Set<String>()

        let pages: [LatticesCompanionCockpitLayout.Page] = sourcePages.enumerated().map { index, page in
            let columns = min(5, max(2, page.columns))
            let inferredRows = page.slots?.map { $0.row + max(1, $0.rowSpan) }.max() ?? 1
            let rows = min(4, max(1, page.rows ?? inferredRows))

            let baseID = page.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackID = baseID.isEmpty ? "page-\(index + 1)" : baseID
            var pageID = fallbackID
            var suffix = 2
            while usedPageIDs.contains(pageID) {
                pageID = "\(fallbackID)-\(suffix)"
                suffix += 1
            }
            usedPageIDs.insert(pageID)

            let positioned = page.slots.map { slots in
                var occupied = Set<Int>()

                func cells(col: Int, row: Int, colSpan: Int, rowSpan: Int) -> [Int] {
                    (row..<(row + rowSpan)).flatMap { cellRow in
                        (col..<(col + colSpan)).map { cellCol in
                            cellRow * columns + cellCol
                        }
                    }
                }

                func firstOpenPosition(colSpan: Int, rowSpan: Int) -> (col: Int, row: Int)? {
                    guard colSpan <= columns, rowSpan <= rows else { return nil }
                    for row in 0...(rows - rowSpan) {
                        for col in 0...(columns - colSpan) {
                            if cells(col: col, row: row, colSpan: colSpan, rowSpan: rowSpan)
                                .allSatisfy({ !occupied.contains($0) }) {
                                return (col, row)
                            }
                        }
                    }
                    return nil
                }

                let normalizedSlots: [LatticesCompanionCockpitLayout.Slot] = slots
                    .prefix(slotCount)
                    .compactMap { slot -> LatticesCompanionCockpitLayout.Slot? in
                    let preferredCol = min(columns - 1, max(0, slot.col))
                    let preferredRow = min(rows - 1, max(0, slot.row))
                    var colSpan = min(columns - preferredCol, max(1, slot.colSpan))
                    var rowSpan = min(rows - preferredRow, max(1, slot.rowSpan))
                    let preferredCells = cells(
                        col: preferredCol,
                        row: preferredRow,
                        colSpan: colSpan,
                        rowSpan: rowSpan
                    )

                    var position: (col: Int, row: Int)?
                    if preferredCells.allSatisfy({ !occupied.contains($0) }) {
                        position = (preferredCol, preferredRow)
                    } else {
                        position = firstOpenPosition(colSpan: colSpan, rowSpan: rowSpan)
                    }

                    // A custom layout can become denser when an oversized grid
                    // is clamped to the supported 5×4 canvas. Keep every action
                    // reachable by relaxing its span before ever overlapping it.
                    if position == nil {
                        colSpan = 1
                        rowSpan = 1
                        position = firstOpenPosition(colSpan: 1, rowSpan: 1)
                    }
                    guard let position else { return nil }

                    occupied.formUnion(cells(
                        col: position.col,
                        row: position.row,
                        colSpan: colSpan,
                        rowSpan: rowSpan
                    ))
                    return LatticesCompanionCockpitLayout.Slot(
                        shortcutID: slot.shortcutID,
                        col: position.col,
                        row: position.row,
                        colSpan: colSpan,
                        rowSpan: rowSpan,
                        customLabel: slot.customLabel,
                        customBuilderIcon: slot.customBuilderIcon,
                        customTint: slot.customTint,
                        customCategory: slot.customCategory
                    )
                }
                return normalizedSlots
            }

            return .init(
                id: pageID,
                title: page.title,
                subtitle: page.subtitle,
                columns: columns,
                rows: page.slots == nil ? page.rows : rows,
                slotIDs: normalizedSlots(page.slotIDs),
                slots: positioned
            )
        }

        return LatticesCompanionCockpitLayout(pages: pages)
    }

    static func renderedState(
        layout: LatticesCompanionCockpitLayout,
        voice: DeckVoiceState?,
        desktop: DeckDesktopSummary?,
        layoutState: DeckLayoutState?,
        talkie: TalkieDeckSnapshot
    ) -> DeckCockpitState {
        let normalizedLayout = normalized(layout)
        let focusName = layoutState?.frontmostWindow?.appName ?? desktop?.activeAppName ?? "Mac"
        let detail = desktop?.activeLayerName.map { "Layer: \($0)" } ?? "Quick controls for \(focusName)."

        return DeckCockpitState(
            title: focusName,
            detail: detail,
            pages: normalizedLayout.pages.map { page in
                let tiles: [DeckCockpitTile]
                if let slots = page.slots {
                    // Span-aware page (authored in the web builder): render each
                    // non-empty slot at its explicit placement.
                    tiles = slots.enumerated().compactMap { index, slot in
                        slot.shortcutID.isEmpty ? nil : renderedTile(
                            shortcutID: slot.shortcutID,
                            pageID: page.id,
                            slotIndex: index,
                            col: slot.col,
                            row: slot.row,
                            colSpan: slot.colSpan,
                            rowSpan: slot.rowSpan,
                            customLabel: slot.customLabel,
                            customBuilderIcon: slot.customBuilderIcon,
                            customTint: slot.customTint,
                            voice: voice,
                            desktop: desktop,
                            layoutState: layoutState,
                            talkie: talkie
                        )
                    }
                } else {
                    // Legacy flat page: row-major flow into `columns` (unchanged).
                    tiles = page.slotIDs.enumerated().map { index, shortcutID in
                        renderedTile(
                            shortcutID: shortcutID,
                            pageID: page.id,
                            slotIndex: index,
                            voice: voice,
                            desktop: desktop,
                            layoutState: layoutState,
                            talkie: talkie
                        )
                    }
                }
                return DeckCockpitPage(
                    id: page.id,
                    title: page.title,
                    subtitle: page.subtitle,
                    columns: page.columns,
                    rows: page.rows,
                    tiles: tiles
                )
            }
        )
    }

    private static func normalizedSlots(_ slots: [String]) -> [String] {
        let trimmed = Array(slots.prefix(slotCount))
        if trimmed.count == slotCount {
            return trimmed
        }
        return trimmed + Array(repeating: "", count: slotCount - trimmed.count)
    }

    private static func renderedTile(
        shortcutID: String,
        pageID: String,
        slotIndex: Int,
        col: Int? = nil,
        row: Int? = nil,
        colSpan: Int? = nil,
        rowSpan: Int? = nil,
        customLabel: String? = nil,
        customBuilderIcon: String? = nil,
        customTint: String? = nil,
        voice: DeckVoiceState?,
        desktop: DeckDesktopSummary?,
        layoutState: DeckLayoutState?,
        talkie: TalkieDeckSnapshot
    ) -> DeckCockpitTile {
        let rendered = renderedShortcut(
            for: shortcutID,
            voice: voice,
            desktop: desktop,
            layoutState: layoutState,
            talkie: talkie
        )

        // Stable id: position-based for span slots (indices can shift when empty
        // slots are dropped), slot-index-based for legacy flat pages.
        let id = (col != nil && row != nil) ? "\(pageID)-\(col!)-\(row!)" : "\(pageID)-\(slotIndex)"

        return DeckCockpitTile(
            id: id,
            shortcutID: shortcutID,
            title: nonBlank(customLabel) ?? rendered.title,
            subtitle: rendered.subtitle,
            iconSystemName: customBuilderIcon.map(builderSystemIcon) ?? rendered.iconSystemName,
            accentToken: rendered.accentToken,
            deckID: rendered.deckID ?? pageID,
            categoryTint: customTint ?? rendered.categoryTint ?? definition(for: shortcutID)?.category.tintToken,
            actionID: rendered.actionID,
            payload: rendered.payload,
            isEnabled: rendered.isEnabled,
            isActive: rendered.isActive,
            controlKind: shortcutID == "mouse-joystick" ? .joystick : nil,
            col: col,
            row: row,
            colSpan: colSpan,
            rowSpan: rowSpan
        )
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func builderSystemIcon(_ icon: String) -> String {
        let icons: [String: String] = [
            "Mic": "mic.fill", "X": "xmark", "CornerDownLeft": "return",
            "ArrowLeft": "arrow.left", "ArrowRight": "arrow.right",
            "ArrowUp": "arrow.up", "ArrowDown": "arrow.down",
            "ChevronLeft": "chevron.left", "ChevronRight": "chevron.right",
            "Search": "magnifyingglass", "Command": "command",
            "LayoutGrid": "rectangle.3.group.fill", "Crosshair": "scope",
            "MousePointer2": "cursorarrow", "SpaceIcon": "space",
            "PanelLeft": "rectangle.leadinghalf.filled",
            "PanelRight": "rectangle.trailinghalf.filled",
            "SquareDashed": "square.dashed", "Maximize2": "macwindow",
            "Monitor": "display", "Terminal": "terminal", "Play": "play.fill",
            "Hammer": "hammer.fill", "GitBranch": "arrow.triangle.branch",
            "Volume2": "speaker.wave.2.fill", "Sun": "sun.max.fill",
            "Camera": "camera.fill", "Sparkles": "sparkles", "Home": "house.fill",
            "Clock": "clock", "Joystick": "circle.circle.fill",
            "ClipboardPaste": "rectangle.portrait.and.arrow.forward"
        ]
        return icons[icon] ?? "square.dashed"
    }

    private static func renderedShortcut(
        for shortcutID: String,
        voice: DeckVoiceState?,
        desktop: DeckDesktopSummary?,
        layoutState: DeckLayoutState?,
        talkie: TalkieDeckSnapshot
    ) -> RenderedShortcut {
        let frontmostWindow = layoutState?.frontmostWindow
        let activeAppName = desktop?.activeAppName ?? frontmostWindow?.appName

        if let keyShortcut = keyboardShortcut(for: shortcutID) {
            return keyShortcut
        }

        // Desktop Preview belongs to the Lattices companion itself. It is a
        // read-only view of this Mac's current screen, not a Talkie launch
        // action, even though the slot originated in Talkie's deck layout.
        if shortcutID == "mac-windows" {
            return RenderedShortcut(
                title: "Desktop Preview",
                subtitle: "View this Mac's screen on your iPad",
                iconSystemName: "display",
                accentToken: "green",
                categoryTint: LatticesCompanionShortcutCategory.layout.tintToken,
                actionID: "desktop.preview.open",
                payload: [:],
                isEnabled: true,
                isActive: false
            )
        }

        if let talkieShortcut = talkieShortcut(for: shortcutID, snapshot: talkie) {
            return talkieShortcut
        }

        switch shortcutID {
        case "paste-device":
            return RenderedShortcut(
                title: "Paste Phone",
                subtitle: "Send this device's clipboard to the Mac",
                iconSystemName: "rectangle.portrait.and.arrow.forward",
                accentToken: "dev",
                categoryTint: LatticesCompanionShortcutCategory.dev.tintToken,
                actionID: "clipboard.pasteFromDevice",
                payload: [:],
                isEnabled: true,
                isActive: false
            )

        case "voice-toggle":
            let listening = voice?.phase == .listening
            return RenderedShortcut(
                title: listening ? "Stop Voice" : "Start Voice",
                subtitle: listening ? "Stop the current voice capture" : "Begin a hands-off voice turn",
                iconSystemName: listening ? "stop.fill" : "mic.fill",
                accentToken: "voice",
                actionID: "voice.toggle",
                payload: [:],
                isEnabled: true,
                isActive: listening
            )

        case "voice-cancel":
            return RenderedShortcut(
                title: "Cancel Voice",
                subtitle: "Dismiss the current voice turn",
                iconSystemName: "xmark.circle.fill",
                accentToken: "rose",
                actionID: "voice.cancel",
                payload: [:],
                isEnabled: true,
                isActive: false
            )

        case "switch-app-prev":
            return RenderedShortcut(
                title: "Prev App",
                subtitle: activeAppName.map { "Now: \($0)" } ?? "Focus the previous visible app",
                iconSystemName: "chevron.left.square.fill",
                accentToken: "switch",
                actionID: "switch.cycleApplication",
                payload: ["direction": .string("previous")],
                isEnabled: true,
                isActive: false
            )

        case "switch-app-next":
            return RenderedShortcut(
                title: "Next App",
                subtitle: activeAppName.map { "Now: \($0)" } ?? "Focus the next visible app",
                iconSystemName: "chevron.right.square.fill",
                accentToken: "switch",
                actionID: "switch.cycleApplication",
                payload: ["direction": .string("next")],
                isEnabled: true,
                isActive: false
            )

        case "switch-window-prev":
            return RenderedShortcut(
                title: "Prev Window",
                subtitle: frontmostWindow?.title ?? activeAppName ?? "Focus the previous visible window",
                iconSystemName: "rectangle.on.rectangle.circle.fill",
                accentToken: "switch",
                actionID: "switch.cycleWindow",
                payload: ["direction": .string("previous")],
                isEnabled: true,
                isActive: false
            )

        case "switch-window-next":
            return RenderedShortcut(
                title: "Next Window",
                subtitle: frontmostWindow?.title ?? activeAppName ?? "Focus the next visible window",
                iconSystemName: "rectangle.on.rectangle.circle",
                accentToken: "switch",
                actionID: "switch.cycleWindow",
                payload: ["direction": .string("next")],
                isEnabled: true,
                isActive: false
            )

        case "layout-optimize":
            return RenderedShortcut(
                title: "Optimize",
                subtitle: desktop?.activeLayerName ?? "Retile the visible workspace",
                iconSystemName: "rectangle.3.group.fill",
                accentToken: "layout",
                actionID: "layout.optimize",
                payload: [:],
                isEnabled: true,
                isActive: false
            )

        case "place-left":
            return placementShortcut(title: "Left", subtitle: "Snap left", icon: "rectangle.leadinghalf.filled", placement: "left")
        case "place-right":
            return placementShortcut(title: "Right", subtitle: "Snap right", icon: "rectangle.trailinghalf.filled", placement: "right")
        case "place-top-left":
            return placementShortcut(title: "Top Left", subtitle: "Upper-left quarter", icon: "rectangle.inset.topleft.filled", placement: "top-left")
        case "place-top-right":
            return placementShortcut(title: "Top Right", subtitle: "Upper-right quarter", icon: "rectangle.inset.topright.filled", placement: "top-right")
        case "place-bottom-left":
            return placementShortcut(title: "Bottom Left", subtitle: "Lower-left quarter", icon: "rectangle.inset.bottomleft.filled", placement: "bottom-left")
        case "place-bottom-right":
            return placementShortcut(title: "Bottom Right", subtitle: "Lower-right quarter", icon: "rectangle.inset.bottomright.filled", placement: "bottom-right")
        case "place-center":
            return placementShortcut(title: "Center", subtitle: "Center on screen", icon: "plus.rectangle.on.rectangle", placement: "center")
        case "place-maximize":
            return placementShortcut(title: "Maximize", subtitle: "Fill visible screen", icon: "macwindow", placement: "maximize")
        case "place-left-third":
            return placementShortcut(title: "Left Third", subtitle: "Left column", icon: "rectangle.leadingthird.inset.filled", placement: "left-third")
        case "place-center-third":
            return placementShortcut(title: "Center Third", subtitle: "Middle column", icon: "rectangle.center.inset.filled", placement: "center-third")
        case "place-right-third":
            return placementShortcut(title: "Right Third", subtitle: "Right column", icon: "rectangle.trailingthird.inset.filled", placement: "right-third")

        case "resize-wider":
            return resizeShortcut(title: "Wider", subtitle: "Increase width", icon: "arrow.left.and.right.circle.fill", dimension: "width", direction: "grow")
        case "resize-narrower":
            return resizeShortcut(title: "Narrower", subtitle: "Reduce width", icon: "arrow.left.and.right.circle", dimension: "width", direction: "shrink")
        case "resize-taller":
            return resizeShortcut(title: "Taller", subtitle: "Increase height", icon: "arrow.up.and.down.circle.fill", dimension: "height", direction: "grow")
        case "resize-shorter":
            return resizeShortcut(title: "Shorter", subtitle: "Reduce height", icon: "arrow.up.and.down.circle", dimension: "height", direction: "shrink")
        case "resize-grow":
            return resizeShortcut(title: "Grow", subtitle: "Expand both axes", icon: "plus.rectangle.fill.on.rectangle.fill", dimension: "both", direction: "grow")
        case "resize-shrink":
            return resizeShortcut(title: "Shrink", subtitle: "Reduce both axes", icon: "minus.rectangle", dimension: "both", direction: "shrink")

        case "mouse-find":
            return RenderedShortcut(
                title: "Find Mouse",
                subtitle: "Pulse the cursor position",
                iconSystemName: "scope",
                accentToken: "mouse",
                actionID: "mouse.find",
                payload: [:],
                isEnabled: true,
                isActive: false
            )

        case "mouse-summon":
            return RenderedShortcut(
                title: "Summon Mouse",
                subtitle: "Bring cursor to center",
                iconSystemName: "dot.scope",
                accentToken: "mouse",
                actionID: "mouse.summon",
                payload: [:],
                isEnabled: true,
                isActive: false
            )

        case "mouse-joystick":
            return RenderedShortcut(
                title: "Joystick",
                subtitle: "Steer the Mac pointer",
                iconSystemName: "circle.circle.fill",
                accentToken: "mouse",
                actionID: nil,
                payload: [:],
                isEnabled: true,
                isActive: false
            )

        default:
            return RenderedShortcut(
                title: "Empty",
                subtitle: "Assign an action on the Mac",
                iconSystemName: "square.dashed",
                accentToken: nil,
                actionID: nil,
                payload: [:],
                isEnabled: false,
                isActive: false
            )
        }
    }

    private static func placementShortcut(
        title: String,
        subtitle: String,
        icon: String,
        placement: String
    ) -> RenderedShortcut {
        RenderedShortcut(
            title: title,
            subtitle: subtitle,
            iconSystemName: icon,
            accentToken: "layout",
            actionID: "layout.placeFrontmost",
            payload: ["placement": .string(placement)],
            isEnabled: true,
            isActive: false
        )
    }

    private static func resizeShortcut(
        title: String,
        subtitle: String,
        icon: String,
        dimension: String,
        direction: String
    ) -> RenderedShortcut {
        RenderedShortcut(
            title: title,
            subtitle: subtitle,
            iconSystemName: icon,
            accentToken: "layout",
            actionID: "layout.resizeFrontmost",
            payload: [
                "dimension": .string(dimension),
                "direction": .string(direction)
            ],
            isEnabled: true,
            isActive: false
        )
    }

    private static func keyboardShortcut(for shortcutID: String) -> RenderedShortcut? {
        let shortcuts: [String: (title: String, subtitle: String, icon: String, key: String, modifiers: [String])] = [
            "key-escape": ("Escape", "Send Escape", "escape", "escape", []),
            "key-copy": ("Copy", "Send Command-C", "doc.on.doc", "c", ["command"]),
            "key-paste": ("Paste", "Send Command-V", "doc.on.clipboard", "v", ["command"]),
            "key-undo": ("Undo", "Send Command-Z", "arrow.uturn.backward", "z", ["command"]),
            "key-shift-tab": ("Back Tab", "Send Shift-Tab", "arrowshape.turn.up.left", "tab", ["shift"]),
            "key-space": ("Space", "Send Space", "space", "space", []),
            "key-enter": ("Enter", "Send Return", "return", "enter", []),
            "key-left": ("Left", "Send Left Arrow", "arrow.left", "left", []),
            "key-right": ("Right", "Send Right Arrow", "arrow.right", "right", []),
            "key-up": ("Up", "Send Up Arrow", "arrow.up", "up", []),
            "key-down": ("Down", "Send Down Arrow", "arrow.down", "down", []),
        ]

        guard let shortcut = shortcuts[shortcutID] else { return nil }
        return RenderedShortcut(
            title: shortcut.title,
            subtitle: shortcut.subtitle,
            iconSystemName: shortcut.icon,
            accentToken: "system",
            categoryTint: LatticesCompanionShortcutCategory.system.tintToken,
            actionID: "keys.send",
            payload: [
                "key": .string(shortcut.key),
                "modifiers": .array(shortcut.modifiers.map { .string($0) })
            ],
            isEnabled: true,
            isActive: false
        )
    }

    private static func talkieShortcut(
        for shortcutID: String,
        snapshot: TalkieDeckSnapshot
    ) -> RenderedShortcut? {
        guard let shortcut = TalkieDeckProvider.shortcut(for: shortcutID) else { return nil }

        let isActive = snapshot.activeShortcutIDs.contains(shortcut.id)
        let detail = snapshot.detailByShortcutID[shortcut.id]
            ?? snapshot.recentResultByShortcutID[shortcut.id]
        let subtitle: String
        if let detail, !detail.isEmpty {
            subtitle = detail
        } else if snapshot.isReachable {
            subtitle = shortcut.subtitle
        } else if snapshot.isRunning {
            subtitle = snapshot.lastError ?? "Voice controls are starting."
        } else {
            subtitle = "Unavailable until the voice companion is running."
        }

        let canOpenProvider = shortcut.id == "talkie-home"
        return RenderedShortcut(
            title: !snapshot.isReachable && canOpenProvider ? "Open Talkie" : shortcut.title,
            subtitle: subtitle,
            iconSystemName: shortcut.iconSystemName,
            accentToken: shortcut.accentToken,
            categoryTint: shortcut.accentToken,
            actionID: snapshot.isReachable ? "talkie.perform" : (canOpenProvider ? "talkie.open" : nil),
            payload: snapshot.isReachable ? ["shortcutID": .string(shortcut.id)] : [:],
            isEnabled: snapshot.isReachable || canOpenProvider,
            isActive: isActive
        )
    }
}
