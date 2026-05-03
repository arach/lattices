import AppKit

enum HotkeyBootstrap {
    static func registerHotkeys() {
        let scanner = ProjectScanner.shared
        CommandPaletteWindow.shared.configure(scanner: scanner)

        let store = HotkeyStore.shared
        store.register(action: .palette) { CommandPaletteWindow.shared.toggle() }
        store.register(action: .unifiedWindow) { ScreenMapWindowController.shared.toggle() }
        store.register(action: .bezel) { WorkspaceInspectorPresenter.show() }
        store.register(action: .cheatSheet) { SettingsWindowController.shared.show() }
        store.register(action: .desktopInventory) {
            DiagnosticLog.shared.info("Hotkey: desktopInventory triggered")
            ScreenMapWindowController.shared.showPage(.desktopInventory)
        }
        store.register(action: .voiceCommand) {
            DiagnosticLog.shared.info("Hotkey: voiceCommand triggered")
            VoiceCommandWindow.shared.toggle()
        }
        store.register(action: .handsOff) {
            DiagnosticLog.shared.info("Hotkey: handsOff triggered")
            HandsOffSession.shared.toggle()
            if HandsOffSession.shared.state != .idle {
                HUDController.shared.showVoiceBar()
            } else {
                HUDController.shared.hideVoiceBar()
            }
        }
        store.register(action: .hud) { HUDController.shared.toggle() }
        store.register(action: .mouseFinder) { MouseFinder.shared.find() }
        store.register(action: .omniSearch) { OmniSearchWindow.shared.toggle() }

        registerLayerHotkeys(store: store)
        registerTilingHotkeys(store: store)
    }

    private static func registerLayerHotkeys(store: HotkeyStore) {
        store.register(action: .layerNext) { SessionLayerStore.shared.cycleNext() }
        store.register(action: .layerPrev) { SessionLayerStore.shared.cyclePrev() }
        store.register(action: .layerTag) { SessionLayerStore.shared.tagFrontmostWindow() }

        let workspace = WorkspaceManager.shared
        let configLayerCount = (workspace.config?.layers ?? []).count
        let maxLayers = max(configLayerCount, 9)
        for (index, action) in HotkeyAction.layerActions.prefix(maxLayers).enumerated() {
            store.register(action: action) {
                let session = SessionLayerStore.shared
                if !session.layers.isEmpty && index < session.layers.count {
                    session.switchTo(index: index)
                } else {
                    workspace.focusLayer(index: index)
                }
                EventBus.shared.post(.layerSwitched(index: index))
            }
        }
    }

    private static func registerTilingHotkeys(store: HotkeyStore) {
        let tileMap: [(HotkeyAction, TilePosition)] = [
            (.tileLeft, .left), (.tileRight, .right),
            (.tileMaximize, .maximize), (.tileCenter, .center),
            (.tileTopLeft, .topLeft), (.tileTopRight, .topRight),
            (.tileBottomLeft, .bottomLeft), (.tileBottomRight, .bottomRight),
            (.tileTop, .top), (.tileBottom, .bottom),
            (.tileLeftThird, .leftThird), (.tileCenterThird, .centerThird),
            (.tileRightThird, .rightThird),
        ]
        for (action, position) in tileMap {
            store.register(action: action) {
                WindowTiler.tileFrontmostViaAX(to: position)
            }
        }
        store.register(action: .tileDistribute) {
            WindowTiler.distributeVisible(reactivateLattices: false)
        }
        store.register(action: .tileTypeGrid) {
            WindowTiler.distributeVisibleByFrontmostType(reactivateLattices: false)
        }
        store.register(action: .tileOrganize) {
            let appName = DesktopModel.shared.frontmostWindow()?.app
                ?? NSWorkspace.shared.frontmostApplication?.localizedName
            CommandModeWindow.shared.show(launchMode: .organize(appName: appName))
        }
    }
}
