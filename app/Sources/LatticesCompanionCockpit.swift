import DeckKit
import Foundation

struct LatticesCompanionCockpitLayout: Codable, Equatable {
    struct Page: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var subtitle: String?
        var columns: Int
        var slotIDs: [String]

        init(
            id: String,
            title: String,
            subtitle: String? = nil,
            columns: Int = 4,
            slotIDs: [String]
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.columns = columns
            self.slotIDs = slotIDs
        }
    }

    var pages: [Page]
}

enum LatticesCompanionShortcutCategory: String, CaseIterable, Identifiable {
    case voice
    case switching
    case layout
    case mouse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice:
            return "Voice"
        case .switching:
            return "Switching"
        case .layout:
            return "Layout"
        case .mouse:
            return "Mouse"
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
}

enum LatticesCompanionCockpitCatalog {
    private struct RenderedShortcut {
        var title: String
        var subtitle: String?
        var iconSystemName: String
        var accentToken: String?
        var actionID: String?
        var payload: [String: DeckValue]
        var isEnabled: Bool
        var isActive: Bool
    }

    static let slotCount = 16

    static let defaultLayout = LatticesCompanionCockpitLayout(
        pages: [
            .init(
                id: "main",
                title: "Cockpit",
                subtitle: "Voice, switching, and fast workspace moves",
                columns: 4,
                slotIDs: [
                    "voice-toggle", "voice-cancel", "switch-app-prev", "switch-app-next",
                    "switch-window-prev", "switch-window-next", "layout-optimize", "mouse-find",
                    "place-left", "place-right", "place-center", "place-maximize",
                    "resize-wider", "resize-taller", "mouse-summon", ""
                ]
            ),
            .init(
                id: "layout",
                title: "Layout",
                subtitle: "Placement and resize macros for the frontmost window",
                columns: 4,
                slotIDs: [
                    "place-top-left", "place-top-right", "place-bottom-left", "place-bottom-right",
                    "place-left-third", "place-center-third", "place-right-third", "place-center",
                    "resize-wider", "resize-narrower", "resize-taller", "resize-shorter",
                    "resize-grow", "resize-shrink", "place-left", "place-right"
                ]
            ),
        ]
    )

    static let shortcuts: [LatticesCompanionShortcutDefinition] = [
        .init(id: "", title: "Empty", subtitle: "Leave this slot unused", iconSystemName: "square.dashed", accentToken: nil, category: .layout),
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
    ]

    static func definition(for shortcutID: String) -> LatticesCompanionShortcutDefinition? {
        shortcuts.first(where: { $0.id == shortcutID })
    }

    static func normalized(_ layout: LatticesCompanionCockpitLayout) -> LatticesCompanionCockpitLayout {
        let blueprintPages = defaultLayout.pages
        let existing = Dictionary(uniqueKeysWithValues: layout.pages.map { ($0.id, $0) })

        return LatticesCompanionCockpitLayout(
            pages: blueprintPages.map { blueprint in
                let current = existing[blueprint.id]
                let slots = normalizedSlots(current?.slotIDs ?? blueprint.slotIDs)
                return .init(
                    id: blueprint.id,
                    title: current?.title ?? blueprint.title,
                    subtitle: current?.subtitle ?? blueprint.subtitle,
                    columns: max(2, current?.columns ?? blueprint.columns),
                    slotIDs: slots
                )
            }
        )
    }

    static func renderedState(
        layout: LatticesCompanionCockpitLayout,
        voice: DeckVoiceState?,
        desktop: DeckDesktopSummary?,
        layoutState: DeckLayoutState?
    ) -> DeckCockpitState {
        let normalizedLayout = normalized(layout)
        let focusName = layoutState?.frontmostWindow?.appName ?? desktop?.activeAppName ?? "Mac"
        let detail = desktop?.activeLayerName.map { "Layer: \($0)" } ?? "Quick controls for \(focusName)."

        return DeckCockpitState(
            title: focusName,
            detail: detail,
            pages: normalizedLayout.pages.map { page in
                DeckCockpitPage(
                    id: page.id,
                    title: page.title,
                    subtitle: page.subtitle,
                    columns: page.columns,
                    tiles: page.slotIDs.enumerated().map { index, shortcutID in
                        renderedTile(
                            shortcutID: shortcutID,
                            pageID: page.id,
                            slotIndex: index,
                            voice: voice,
                            desktop: desktop,
                            layoutState: layoutState
                        )
                    }
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
        voice: DeckVoiceState?,
        desktop: DeckDesktopSummary?,
        layoutState: DeckLayoutState?
    ) -> DeckCockpitTile {
        let rendered = renderedShortcut(
            for: shortcutID,
            voice: voice,
            desktop: desktop,
            layoutState: layoutState
        )

        return DeckCockpitTile(
            id: "\(pageID)-\(slotIndex)",
            shortcutID: shortcutID,
            title: rendered.title,
            subtitle: rendered.subtitle,
            iconSystemName: rendered.iconSystemName,
            accentToken: rendered.accentToken,
            actionID: rendered.actionID,
            payload: rendered.payload,
            isEnabled: rendered.isEnabled,
            isActive: rendered.isActive
        )
    }

    private static func renderedShortcut(
        for shortcutID: String,
        voice: DeckVoiceState?,
        desktop: DeckDesktopSummary?,
        layoutState: DeckLayoutState?
    ) -> RenderedShortcut {
        let frontmostWindow = layoutState?.frontmostWindow
        let activeAppName = desktop?.activeAppName ?? frontmostWindow?.appName

        switch shortcutID {
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
}
