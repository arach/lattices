import AppKit

enum HotkeyBootstrap {
    static func registerHotkeys() {
        let store = HotkeyStore.shared
        store.register(action: .workspaceAssistant) { AssistantAccess.show() }
        store.register(action: .unifiedWindow) { ScreenMapWindowController.shared.toggle() }
        store.register(action: .screenMap) { ScreenMapWindowController.shared.showPage(.screenMap) }
        store.register(action: .bezel) { WorkspaceInspectorPresenter.show() }
        store.register(action: .cheatSheet) { SettingsWindowController.shared.show(section: "shortcuts") }
        store.register(action: .desktopInventory) {
            DiagnosticLog.shared.info("Hotkey: desktopInventory triggered")
            ScreenMapWindowController.shared.showPage(.desktopInventory)
        }
        store.register(action: .voiceCommand) {
            DiagnosticLog.shared.info("Hotkey: voiceCommand triggered")
            UnifiedCommandBarWindow.shared.toggle(mode: .voice)
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
        store.register(action: .overlayActors) { ScreenOverlayCanvasController.shared.toggleAgentActorsVisibility() }
        store.register(action: .gridPlacement) {
            TilePointerController.shared.cancelApply()
            GridPlacementWindow.shared.toggle()
        }
        // The single command-surface hotkey: opens the merged bar (browse +
        // search; "/" for slash commands).
        store.register(action: .commandBar) {
            TilePointerController.shared.cancelApply()
            UnifiedCommandBarWindow.shared.toggle(mode: .search)
        }
        store.register(action: .focusMode) { FocusModeController.shared.toggle() }
        store.register(action: .activityLog) {
            DiagnosticLog.shared.info("Hotkey: activityLog triggered")
            ScreenMapWindowController.shared.showPage(.activity)
        }

        registerLayerHotkeys(store: store)
        registerTilingHotkeys(store: store)
    }

    private static func registerLayerHotkeys(store: HotkeyStore) {
        store.register(action: .layerPrev) { stepLayer(.left) }
        store.register(action: .layerNext) { stepLayer(.right) }
        store.register(action: .layerUp) { stepLayer(.up) }
        store.register(action: .layerDown) { stepLayer(.down) }
        store.register(action: .layerTag) { SessionLayerStore.shared.tagFrontmostWindow() }

        for (offset, action) in HotkeyAction.layerActions.enumerated() {
            let slot = offset + 1
            store.register(action: action) { selectSlot(slot) }
        }
    }

    /// Cmd+Opt+N switches to the layer in slot N of the pad: a session layer
    /// when there's one at that index, else the workspace layer. The middle
    /// slot, and any slot without a layer, shows where you are instead.
    private static func selectSlot(_ slot: Int) {
        guard let index = LayerSlots.index(forSlot: slot) else {
            showCurrentLayer()
            return
        }
        let session = SessionLayerStore.shared
        let workspace = WorkspaceManager.shared
        if index < session.layers.count {
            session.switchTo(index: index)
        } else if index < (workspace.config?.layers ?? []).count {
            workspace.focusLayer(index: index)
        } else {
            showCurrentLayer()
            return
        }
        EventBus.shared.post(.layerSwitched(index: index))
    }

    /// Shows the bezel on the layer you're on, without switching.
    private static func showCurrentLayer() {
        let session = SessionLayerStore.shared
        if session.layers.indices.contains(session.activeIndex) {
            let index = session.activeIndex
            LayerBezel.shared.show(label: session.layers[index].name, index: index, total: session.layers.count)
            return
        }
        let workspace = WorkspaceManager.shared
        guard let layers = workspace.config?.layers, !layers.isEmpty else { return }
        let current = min(max(workspace.activeLayerIndex, 0), layers.count - 1)
        LayerBezel.shared.show(label: layers[current].label, index: current, total: layers.count)
    }

    /// Cmd+Opt+arrows move across the pad the way they point, through the
    /// session layers when there are any, else the workspace layers, the same
    /// fallback the numbered hotkeys use. They hop the middle and don't wrap:
    /// at the pad's edge, the bezel shows where you are.
    private static func stepLayer(_ direction: LayerSlots.Direction) {
        let session = SessionLayerStore.shared
        if !session.layers.isEmpty {
            session.step(direction)
            return
        }
        let workspace = WorkspaceManager.shared
        guard let layers = workspace.config?.layers, !layers.isEmpty else { return }
        let current = min(max(workspace.activeLayerIndex, 0), layers.count - 1)
        guard let index = LayerSlots.neighbour(of: current, direction, count: layers.count) else {
            LayerBezel.shared.show(label: layers[current].label, index: current, total: layers.count)
            return
        }
        workspace.focusLayer(index: index)
        EventBus.shared.post(.layerSwitched(index: index))
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
                guard !TilePointerController.shared.shouldSuppressTilingHotkey(action) else { return }
                TilePointerController.shared.cancelApply()
                if WindowMotionMode.shared.tileCurrentTarget(to: position) { return }
                let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                    ?? NSScreen.main
                TileZoneOverlay.shared.show(position: position, on: screen, autoHideAfter: 0.28)
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
        store.register(action: .tileOpenCell) {
            TilePointerController.shared.cancelApply()
            FrontWindowPlacer.fillOpenGridCell()
        }
        store.register(action: .motionMode) {
            TilePointerController.shared.cancelApply()
            WindowMotionMode.shared.toggleHyperspace()
        }
        store.register(action: .inPlaceMode) {
            TilePointerController.shared.cancelApply()
            WindowMotionMode.shared.toggleInPlace()
        }
        store.register(action: .chordHints) {
            TilePointerController.shared.cancelApply()
            InPlaceChordHintOverlay.shared.toggle()
        }
    }
}
