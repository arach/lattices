import AppKit
import BlinkCore
import HudsonObservability

/// A top-left, display-local panel frame requested by the live agent surface.
/// It stays inside the app target because only PanelManager can realize it.
struct DeskFrameRequest: Sendable {
    let x: CGFloat?
    let y: CGFloat?
    let width: CGFloat?
    let height: CGFloat?
    let display: Int?
}

/// Owns every floating note panel: one panel per note (opening an open note
/// focuses it), debounced saves with mandatory flushes on close and quit, and
/// reopening the last session's panels on launch.
@MainActor
final class PanelManager: NSObject, NSWindowDelegate {
    private let store: NoteStore
    private var panels: [String: NotePanel] = [:]
    private var pendingText: [String: String] = [:]
    /// What each open panel currently displays — the tell between "our own
    /// save came back around" and a genuine external edit to push in.
    private var panelContent: [String: String] = [:]
    /// The grid slot each open panel was last placed in, so a changed
    /// `blink.slot` (e.g. `blink present --slot`) can move the panel live and an
    /// unchanged one never re-snaps. Absent = the note declares no slot.
    private var panelSlot: [String: Int] = [:]
    private var observers: [NSObjectProtocol] = []
    private var saveTasks: [String: Task<Void, Never>] = [:]
    private var revealCompletionTasks: [String: Task<Void, Never>] = [:]
    private var revealSoundTasks: [String: Task<Void, Never>] = [:]
    private var revealSounds: [String: NSSound] = [:]
    private var revealOrderings: [String: RevealOrdering] = [:]
    private var isTerminating = false
    private var blinkHidden = false
    private var workspaceScope: WorkspaceScope = .all
    private var panelWorkspaces: [String: String] = [:]
    private var workspaceSuppressedPanelIDs: Set<String> = []
    private lazy var focusOverlay = FocusOverlay()
    private lazy var drapeOverlay = DrapeOverlay()
    private var gridOverlay: GridOverlay?
    private var mostRecentKeyPanelID: String?
    private let log = HudLogger(category: "blink.panels")

    /// Linked-note navigation originates inside a panel, below AppModel. Ask the
    /// model to move the durable UI selection before realizing a cross-workspace
    /// target, so every launcher converges on the same active scope.
    var onWorkspaceScopeRequested: ((WorkspaceScope) -> Void)?
    var onPlacementChanged: ((String, String) -> Void)?

    func deskLayout(named name: String) -> DeskLayout {
        let order = Dictionary(uniqueKeysWithValues: NSApp.orderedWindows.enumerated().compactMap {
            index, window in (window as? NotePanel).map { ($0.noteID, index) }
        })
        let snapshots = panels.values.map { panel -> DeskPanel in
            let display = (NSScreen.screens.firstIndex(where: { $0 === panel.screen }) ?? 0) + 1
            let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let frame = panel.frame
            return DeskPanel(
                id: panel.noteID, slot: panelSlot[panel.noteID] ?? nil, mode: panel.currentMode,
                frame: DeskFrame(x: frame.minX - visible.minX, y: visible.maxY - frame.maxY,
                    width: frame.width, height: frame.height), display: display
            )
        }.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
        return DeskLayout(name: name, panels: snapshots)
    }

    func placementList() -> [[String: Any]] {
        let ordered = NSApp.orderedWindows.compactMap { $0 as? NotePanel }
        return panels.values.map { panel in
            let screen = (NSScreen.screens.firstIndex(where: { $0 === panel.screen }) ?? 0) + 1
            var dict: [String: Any] = [
                "id": panel.noteID,
                "frame": [
                    "x": panel.frame.minX,
                    "y": panel.frame.minY,
                    "width": panel.frame.width,
                    "height": panel.frame.height
                ],
                "screen": screen,
                "mode": panel.currentMode,
                "shaded": panel.isShaded,
                "focused": panel.isKeyWindow,
                "z": ordered.firstIndex(where: { $0 === panel }) ?? ordered.count
            ]
            if let slot = panelSlot[panel.noteID] {
                dict["slot"] = slot
            } else {
                dict["slot"] = NSNull()
            }
            return dict
        }
    }

    func restoreDesk(_ layout: DeskLayout) async {
        await flushAll()
        let wanted = Set(layout.panels.map(\.id))
        for id in Array(panels.keys) where !wanted.contains(id) { _ = closePanel(noteID: id) }
        for entry in layout.panels.reversed() {
            guard let note = await store.note(id: entry.id),
                  let panel = openPanel(for: note, initialMode: entry.mode, playEntrance: false)
            else { continue }
            panel.selectMode(entry.mode)
            _ = applyDeskFrame(noteID: entry.id, x: entry.frame.x, y: entry.frame.y,
                width: entry.frame.width, height: entry.frame.height,
                display: entry.display, animated: false)
            panel.orderFront(nil)
        }
        persistOpenList()
    }

    private static let openNotesKey = "blink.openNotes"
    private static let saveDebounce: Duration = .seconds(1)
    private static let typeOnCharactersPerSecond = 180.0

    /// The two neighboring windows that bracketed a panel before a reveal
    /// briefly ordered it front. Keeping both gives restoration a fallback if
    /// one closes during the reveal.
    private struct RevealOrdering {
        let windowInFront: Int?
        let windowBehind: Int?
        let wasKey: Bool
    }

    init(store: NoteStore) {
        self.store = store
    }

    // MARK: - Lifecycle

    /// Load the store and reopen the panels that were open last session.
    func restoreSession() async {
        do {
            _ = try await store.load()
        } catch {
            log.error("[BLINK] failed to load notes", metadata: ["error": "\(error)"])
            return
        }
        guard BlinkConfigStore.shared.config.behavior.restoreSession else {
            log.info("[BLINK] session restore disabled in settings")
            return
        }
        let openIDs = UserDefaults.standard.stringArray(forKey: Self.openNotesKey) ?? []
        var restored: [NotePanel] = []
        for id in openIDs {
            if let note = await store.note(id: id),
               // Restore silently — the staggered reveal below owns the motion.
               let panel = openPanel(
                    for: note,
                    playEntrance: false,
                    activateWorkspaceIfNeeded: false
               ), panel.isVisible {
                restored.append(panel)
            }
        }
        // Session restore: one entrance per panel, staggered `staggerMs` apart,
        // ordered left-to-right by on-screen x, so the desk assembles rather than
        // popping in all at once.
        staggerReveal(restored, motion: BlinkConfigStore.shared.config.motion)
        log.info("[BLINK] session restored", metadata: ["panels": "\(panels.count)"])
    }

    /// Play a staggered entrance across `panels`, ordered left-to-right by
    /// on-screen x, each delayed `staggerMs` after the previous. When motion is
    /// off (or Reduce Motion), every entrance resolves to `none` internally, so
    /// this collapses to instant with no visible stagger. `offset(for:)` lets the
    /// blink push each panel in from its screen-edge direction (compass reveal);
    /// session restore passes a zero offset.
    private func staggerReveal(
        _ panels: [NotePanel],
        motion: BlinkConfig.Motion,
        offset: @escaping (NotePanel) -> CGSize = { _ in .zero }
    ) {
        let ordered = panels.sorted { $0.frame.minX < $1.frame.minX }
        guard motion.enabled, !NotePanel.reduceMotion, motion.staggerMs > 0 else {
            // No stagger: land them all now (each entrance may still animate its
            // own alpha if motion is on but stagger is zero).
            for panel in ordered { panel.animateEntrance(motion: motion, fromOffset: offset(panel)) }
            return
        }
        for (index, panel) in ordered.enumerated() {
            let panelOffset = offset(panel)
            let delay = Double(index) * motion.staggerMs / 1000
            if delay <= 0 {
                panel.animateEntrance(motion: motion, fromOffset: panelOffset)
            } else {
                // Keep the panel hidden until its turn so it doesn't sit fully
                // opaque waiting — the entrance sets alpha 0 at its start too.
                panel.alphaValue = 0
                Task { @MainActor [weak panel] in
                    try? await Task.sleep(for: .seconds(delay))
                    panel?.animateEntrance(motion: motion, fromOffset: panelOffset)
                }
            }
        }
    }

    /// A note is being deleted: drop any pending edits for it (so the close
    /// flush doesn't resurrect them against a missing id) and close its panel.
    func handleNoteDeleted(id: String) {
        discardTypedReveal(id: id)
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        pendingText[id] = nil
        panels[id]?.close()
    }

    /// React to store notifications so *external* writers (the blink CLI, an
    /// agent editing files) reach open panels live. In-app mutations flow
    /// through here too but no-op: our own save leaves panelContent equal to
    /// the store, and in-app deletes already closed the panel.
    func startObservingStore() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .blinkNoteUpdated, object: nil, queue: .main
            ) { [weak self] notification in
                guard let id = notification.userInfo?["id"] as? String else { return }
                Task { @MainActor in await self?.applyExternalUpdate(id: id) }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .blinkNoteDeleted, object: nil, queue: .main
            ) { [weak self] notification in
                guard let id = notification.userInfo?["id"] as? String else { return }
                Task { @MainActor in self?.handleNoteDeleted(id: id) }
            }
        )
    }

    /// Push an externally changed note into its open panel — unless the user
    /// has unsaved edits in flight, in which case the user wins (their next
    /// flush merges metadata from disk either way).
    private func applyExternalUpdate(id: String) async {
        guard let panel = panels[id], pendingText[id] == nil else { return }
        guard let note = await store.note(id: id) else { return }
        recordPanelWorkspace(note)

        // Presentation is part of the live note, not launch-only decoration.
        // Merge the legacy sheet alias exactly as openPanel does, then update
        // both the rendered treatment and the bottom metadata rail.
        var presentation = note.presentation
        if presentation.sheet == nil, let legacy = note.extraFrontmatterValue(for: "sheet") {
            presentation.sheet = legacy
        }
        panel.applyPresentation(presentation)

        // Presentation intent must reach an open panel even when the body is
        // unchanged: `blink present --slot N` moves the panel into its grid cell.
        reconcileSlot(id: id, note: note, panel: panel)

        guard note.content != panelContent[id] else { return }
        let previous = panelContent[id] ?? ""
        // State becomes truthful before presentation begins. Saves and a user
        // edit arriving on frame zero therefore see the COMPLETE external text.
        panelContent[id] = note.content

        if let prefix = note.content.range(of: previous, options: [.anchored, .literal]),
           prefix.lowerBound == note.content.startIndex,
           prefix.upperBound < note.content.endIndex {
            let suffix = String(note.content[prefix.upperBound...])
            panel.editor.typeOn(
                base: previous,
                suffix: suffix,
                source: note.extraFrontmatterValue(for: "source")
            )
            beginTypedReveal(id: id, panel: panel, suffixCount: suffix.count)
            log.info(
                "[BLINK] external append revealing in open panel",
                metadata: ["id": id, "characters": "\(suffix.count)"]
            )
        } else {
            // A replacement/middle edit silently supersedes any reveal. The
            // bridge's setContent also clears the web-side mask without echo.
            finishTypedReveal(id: id, snapWeb: false)
            panel.editor.setContent(note.content)
            log.info("[BLINK] external edit applied to open panel", metadata: ["id": id])
        }
        if panel.title != note.title { panel.title = note.title }
    }

    // MARK: - Grid placement

    /// Realize a note's `blink.slot` on its open panel when the slot first
    /// appears or changes. Absent/unchanged slots are no-ops, so a plain content
    /// edit never disturbs a panel's position.
    private func reconcileSlot(id: String, note: Note, panel: NotePanel) {
        let newSlot = note.presentation.slot
        guard newSlot != panelSlot[id] else { return }
        panelSlot[id] = newSlot
        if let newSlot {
            placeInSlot(panel, slot: newSlot, animated: true)
            log.info("[BLINK] placed panel in grid slot", metadata: ["id": id, "slot": "\(newSlot)"])
        }
    }

    /// Snap `panel` into desk-grid cell `slot` (1…9) on its current screen. A
    /// live change animates with the lock snap so the move reads; a fresh open
    /// sets the frame directly and lets the entrance land into it.
    private func placeInSlot(_ panel: NotePanel, slot: Int, animated: Bool) {
        guard let screen = panel.screen ?? NSScreen.main,
              let target = BlinkGrid.frame(forSlot: slot, in: screen.visibleFrame) else { return }
        if animated, !panel.frame.equalTo(target) {
            panel.animateLock(to: target)
        } else {
            panel.setFrame(target, display: false)
            panel.saveFrame(usingName: "blink.note.\(panel.noteID)")
        }
    }

    // MARK: - Visible Hand: native reveal garnish

    /// Start the native half of a typed reveal: low-volume debounced Tink
    /// ticks, plus a temporary front ordering that never makes the panel key.
    /// A second append preserves the original z-order target while replacing
    /// every timer from the first.
    private func beginTypedReveal(id: String, panel: NotePanel, suffixCount: Int) {
        supersedeTypedReveal(id: id)
        bringForwardForRevealIfVisible(id: id, panel: panel)
        playRevealTicks(id: id, suffixCount: suffixCount)

        let seconds = max(Double(suffixCount) / Self.typeOnCharactersPerSecond, 1 / 60)
        revealCompletionTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            // Ensure a background-throttled WKWebView also lands fully. Let an
            // already-playing final tick ring out; no future ticks survive.
            self?.finishTypedReveal(id: id, snapWeb: true, stopCurrentSound: false)
        }
    }

    /// Cancel the old timers/sound for a superseding append, but deliberately
    /// keep its original z-order bracket for the eventual final reveal.
    private func supersedeTypedReveal(id: String) {
        revealCompletionTasks[id]?.cancel()
        revealCompletionTasks[id] = nil
        revealSoundTasks[id]?.cancel()
        revealSoundTasks[id] = nil
        revealSounds.removeValue(forKey: id)?.stop()
    }

    /// Finish (or abort) the presentation layer. This never touches note state
    /// or save order — it only snaps web garnish, silences ticks, and restores
    /// a panel's prior place among Blink windows.
    private func finishTypedReveal(
        id: String, snapWeb: Bool, stopCurrentSound: Bool = true
    ) {
        let wasActive = revealCompletionTasks[id] != nil
            || revealSoundTasks[id] != nil
            || revealSounds[id] != nil
            || revealOrderings[id] != nil
        guard wasActive else { return }
        revealCompletionTasks[id]?.cancel()
        revealCompletionTasks[id] = nil
        revealSoundTasks[id]?.cancel()
        revealSoundTasks[id] = nil
        if let sound = revealSounds.removeValue(forKey: id), stopCurrentSound {
            sound.stop()
        }
        if snapWeb { panels[id]?.editor.finishTypeOn() }
        restoreOrderingAfterReveal(id: id)
    }

    /// Teardown variant for a deleted/closed panel. Ordering a disappearing
    /// window would risk showing it again, so discard rather than restore.
    private func discardTypedReveal(id: String) {
        revealCompletionTasks[id]?.cancel()
        revealCompletionTasks[id] = nil
        revealSoundTasks[id]?.cancel()
        revealSoundTasks[id] = nil
        revealSounds.removeValue(forKey: id)?.stop()
        revealOrderings[id] = nil
    }

    private func playRevealTicks(id: String, suffixCount: Int) {
        // Subtle single arrival cue instead of noisy rapid typewriter clicks
        guard suffixCount >= 20 else { return }
        if let sound = NSSound(named: NSSound.Name("Pop")) {
            sound.volume = 0.08
            if !sound.isPlaying {
                sound.play()
            }
        }
    }

    private func bringForwardForRevealIfVisible(id: String, panel: NotePanel) {
        // An existing ordering means a rapid second append already has a home
        // to return to. Do not accidentally record the temporarily-front state.
        guard revealOrderings[id] == nil,
              !blinkHidden,
              panel.isVisible,
              panel.isOnActiveSpace,
              panel.occlusionState.contains(.visible),
              let screen = panel.screen,
              !panel.frame.intersection(screen.visibleFrame).isEmpty
        else { return }

        let ordered = NSApp.orderedWindows
        guard let index = ordered.firstIndex(where: { $0 === panel }) else { return }
        let inFront = index > 0 ? ordered[index - 1].windowNumber : nil
        let behind = index + 1 < ordered.count ? ordered[index + 1].windowNumber : nil
        guard inFront != nil else { return }  // already front: nothing to restore
        revealOrderings[id] = RevealOrdering(
            windowInFront: inFront, windowBehind: behind, wasKey: panel.isKeyWindow
        )
        panel.orderFront(nil)  // never makeKey; the user's current focus remains untouched
    }

    private func restoreOrderingAfterReveal(id: String) {
        guard let ordering = revealOrderings.removeValue(forKey: id),
              let panel = panels[id],
              panel.isVisible
        else { return }
        // If the user explicitly focused this panel during the reveal, that
        // action wins over our stale ordering snapshot.
        if panel.isKeyWindow, !ordering.wasKey { return }

        if let number = ordering.windowInFront,
           NSApp.windows.contains(where: { $0.windowNumber == number && $0.isVisible }) {
            panel.order(.below, relativeTo: number)
        } else if let number = ordering.windowBehind,
                  NSApp.windows.contains(where: { $0.windowNumber == number && $0.isVisible }) {
            panel.order(.above, relativeTo: number)
        }
    }

    /// One panel per note: if it's already open, focus it.
    /// `initialMode` overrides mode resolution (new notes pass "edit").
    /// `playEntrance` is `false` only for session restore, which runs its own
    /// staggered entrance across all reopened panels afterward.
    @discardableResult
    func openPanel(
        for note: Note,
        initialMode: String? = nil,
        playEntrance: Bool = true,
        activateWorkspaceIfNeeded: Bool = true,
        deskFrame: DeskFrameRequest? = nil
    ) -> NotePanel? {
        recordPanelWorkspace(note)
        if activateWorkspaceIfNeeded,
           !workspaceScope.includes(workspace: note.presentation.workspace) {
            onWorkspaceScopeRequested?(
                .containing(workspace: note.presentation.workspace)
            )
        }
        let shouldPresent = workspaceScope.includes(workspace: note.presentation.workspace)
        // Opening a note while blinked-away: the new panel is visible, so the
        // next Hyper+B should hide everything again.
        if shouldPresent { blinkHidden = false }
        if let existing = panels[note.id] {
            if let deskFrame {
                applyDeskFrame(noteID: note.id, request: deskFrame, animated: false)
            }
            if shouldPresent {
                workspaceSuppressedPanelIDs.remove(note.id)
                mostRecentKeyPanelID = note.id
                existing.makeKeyAndOrderFront(nil)
            } else {
                workspaceSuppressedPanelIDs.insert(note.id)
                existing.orderOut(nil)
            }
            return existing
        }

        // Presentation: the note's `blink:` block drives sheet/tint/radius/theme.
        // Merge the legacy top-level `sheet:` alias in for resolution only — the
        // file keeps that key (no silent migration).
        var presentation = note.presentation
        if presentation.sheet == nil, let legacy = note.extraFrontmatterValue(for: "sheet") {
            presentation.sheet = legacy
        }
        let panel = NotePanel(
            noteID: note.id,
            initialContent: note.content,
            title: note.title,
            presentation: presentation
        )
        panel.delegate = self
        panels[note.id] = panel
        panelContent[note.id] = note.content

        // The panel's context menu copies the truthful in-memory document,
        // including edits that have not reached the debounced disk save yet.
        panel.markdownProvider = { [weak self] in
            guard let self else { return nil }
            return self.pendingText[note.id] ?? self.panelContent[note.id] ?? note.content
        }

        // Style picked from the panel's context menu — persist to frontmatter
        // (the panel already applied it live). Flows through the store so the
        // canvas and any other surface see the change.
        panel.onSheetChanged = { [weak self] sheet in
            Task { @MainActor in
                guard let self else { return }
                do {
                    try await self.store.updateSheet(id: note.id, sheet: sheet, writer: "user")
                } catch {
                    self.log.error(
                        "[BLINK] failed to persist sheet",
                        metadata: ["id": note.id, "error": "\(error)"]
                    )
                }
            }
        }

        // Hiding a note from its context menu changes how many notes are on
        // screen, which the drape depends on — re-evaluate its backdrops.
        panel.onVisibilityChanged = { [weak self] in self?.updateFocusOverlay() }

        panel.editor.onContentChanged = { [weak self] text in
            // User input is the reveal's hard stop. Web already unmasks its
            // complete doc before posting; native mirrors that cancellation so
            // sound/z-order cannot linger.
            self?.finishTypedReveal(id: note.id, snapWeb: true)
            self?.panelContent[note.id] = text
            self?.scheduleSave(noteID: note.id, text: text)
        }
        panel.editor.onSaveRequested = { [weak self] in
            Task { await self?.flush(noteID: note.id) }
        }
        // A rendered [[wiki-link]] was clicked: open or focus the target note.
        panel.editor.onOpenNote = { [weak self] id in
            guard let self else { return }
            Task { @MainActor in
                if let target = await self.store.note(id: id) {
                    self.openPanel(for: target)
                }
            }
        }

        // Mode: explicit (new notes open in edit) > per-note memory > default.
        let mode = initialMode
            ?? UserDefaults.standard.string(forKey: ConfigKeys.noteMode(note.id))
            ?? BlinkConfigStore.shared.config.behavior.defaultMode
        panel.editor.setMode(mode)
        panel.editor.setTheme(
            BlinkConfigStore.shared.config
                .resolved(for: presentation)
                .editorThemeVars(scheme: AppearanceManager.shared.scheme)
        )
        panel.reflectMode(mode)
        panel.editor.onReady = { [weak panel] in
            if mode == "edit" { panel?.editor.focus() }
        }
        let persistMode = { (newMode: String) in
            UserDefaults.standard.set(newMode, forKey: ConfigKeys.noteMode(note.id))
        }
        // Flips from the webview (double-click): update the toggle + persist.
        panel.editor.onModeChanged = { [weak self, weak panel] newMode in
            panel?.reflectMode(newMode)
            persistMode(newMode)
            self?.updateFocusOverlay()
        }
        // Flips from native chrome (toggle click, ⌘⇧P): persist.
        panel.onUserModeChange = { [weak self] newMode in
            persistMode(newMode)
            self?.updateFocusOverlay()
        }
        panel.onFocusModeChange = { [weak self] in
            self?.updateFocusOverlay()
        }

        // Grid home: a note's `blink.slot` (written by `blink present --slot N`)
        // is its declarative cell in the desk grid. Track it so a later change
        // moves the panel; and on a fresh open (not session restore, which must
        // restore exact geometry) set the frame now so the entrance lands into
        // the cell instead of at the last-saved position.
        panelSlot[note.id] = presentation.slot
        if playEntrance, let slot = presentation.slot {
            placeInSlot(panel, slot: slot, animated: false)
        }
        if let deskFrame {
            // Apply before the entrance captures its home frame; otherwise a
            // drop animation could restore the panel to its pre-command screen.
            applyDeskFrame(noteID: note.id, request: deskFrame, animated: false)
        }

        // Land the panel with its configured entrance (a new note, popover open,
        // or a reveal). Set alpha 0 BEFORE ordering front so the window never
        // flashes fully opaque for a frame; then order in and animate up.
        if shouldPresent {
            workspaceSuppressedPanelIDs.remove(note.id)
            let motion = BlinkConfigStore.shared.config.motion
            if playEntrance {
                panel.animateEntrance(motion: motion)
            }
            panel.makeKeyAndOrderFront(nil)
            mostRecentKeyPanelID = note.id
            if mode == "edit" {
                // Give the webview native key focus so typing and shortcuts work
                // immediately (JS focus alone doesn't set the first responder).
                panel.makeFirstResponder(panel.editor.webView)
            }
        } else {
            workspaceSuppressedPanelIDs.insert(note.id)
        }
        persistOpenList()
        updateFocusOverlay()
        gridOverlay?.refresh()
        return panel
    }

    /// Focus overlay is active exactly when the key window is a panel with
    /// focus mode on (edit or read) and the blink hasn't hidden everything.
    private func updateFocusOverlay() {
        let keyPanel = panels.values.first { $0.isKeyWindow }
        if gridOverlay?.isVisible != true,
           !blinkHidden,
           let keyPanel,
           keyPanel.focusEnabled {
            focusOverlay.show(behind: keyPanel)
        } else {
            focusOverlay.hide()
        }
        updateFocusRecede(keyPanel: keyPanel)
        updateDrape()
    }

    /// The drape (config.json → drape) parks behind every note whenever notes are
    /// on screen and neither the blink nor the grid has taken over — the same
    /// gates as the focus overlay, so the two backdrops never fight.
    private func updateDrape() {
        let drape = BlinkConfigStore.shared.config.drape
        let visiblePanels = panels.values.filter { $0.isVisible && $0.isOnActiveSpace }
        let noteScreens = visiblePanels.compactMap { $0.screen }
        // A lone note stays clean over the desktop; the drape earns its keep only
        // once the notes form a set (config.drape.soloSuppressed, default on).
        let soloOK = !drape.soloSuppressed || visiblePanels.count >= 2
        if drape.enabled,
           soloOK,
           !noteScreens.isEmpty,
           !blinkHidden,
           gridOverlay?.isVisible != true {
            drapeOverlay.show(on: noteScreens)
        } else {
            drapeOverlay.hide()
        }
    }

    /// Focus recede: while a panel has focus mode on, its non-key peers get a
    /// subtle depth cue (contentView layer scale + alpha), so the focused note
    /// stands proud of the others. This is TRANSFORM-only — geometry persistence
    /// is never touched. Restored the moment focus turns off or key focus moves.
    private func updateFocusRecede(keyPanel: NotePanel?) {
        let motion = BlinkConfigStore.shared.config.motion
        let receding = !blinkHidden
            && gridOverlay?.isVisible != true
            && (keyPanel?.focusEnabled ?? false)
        for panel in panels.values {
            if receding, panel !== keyPanel {
                panel.recede(enabled: motion.enabled)
            } else {
                panel.unrecede()
            }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let panel = notification.object as? NotePanel {
            mostRecentKeyPanelID = panel.noteID
        }
        updateFocusOverlay()
    }

    func windowDidResignKey(_ notification: Notification) {
        updateFocusOverlay()
    }

    /// A drape is display-scoped. Moving a note across a screen boundary must
    /// move the backing surface with it, even when key focus does not change.
    func windowDidChangeScreen(_ notification: Notification) {
        updateFocusOverlay()
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NotePanel else { return }
        onPlacementChanged?(panel.noteID, "panel.moved")
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? NotePanel else { return }
        onPlacementChanged?(panel.noteID, "panel.resized")
    }

    // MARK: - Read surface for overlays (grid, constellation)

    /// Snapshot of open panels in the active workspace by note id. The grid is
    /// a live view of the current desktop, not a way to leak suppressed groups.
    var openPanelsByID: [String: NotePanel] {
        panels.filter { panelMatchesWorkspace(noteID: $0.key) }
    }

    /// The panel that currently has key focus, if any.
    var keyNotePanel: NotePanel? { panels.values.first { $0.isKeyWindow } }

    /// The note panel an app-level command should act on. Opening an interstitial
    /// palette makes that palette key, so commands must fall back to the most
    /// recently focused note instead of losing their target during presentation.
    var commandNotePanel: NotePanel? {
        keyNotePanel
            ?? mostRecentKeyPanelID.flatMap { id in
                panelMatchesWorkspace(noteID: id) ? panels[id] : nil
            }
            ?? NSApp.orderedWindows.compactMap { $0 as? NotePanel }.first { panel in
                panels[panel.noteID] === panel && panelMatchesWorkspace(noteID: panel.noteID)
            }
    }

    /// Apply a top-left, display-local frame from the agent-facing CLI. The
    /// panel's current display is the coordinate space; omitted values preserve
    /// the existing geometry. Programmatic moves use the same lock animation
    /// and autosave path as grid placement.
    @discardableResult
    func applyDeskFrame(
        noteID: String,
        x: CGFloat?,
        y: CGFloat?,
        width: CGFloat?,
        height: CGFloat?,
        display: Int?,
        animated: Bool
    ) -> Bool {
        applyDeskFrame(
            noteID: noteID,
            request: DeskFrameRequest(
                x: x, y: y, width: width, height: height, display: display
            ),
            animated: animated
        )
    }

    @discardableResult
    private func applyDeskFrame(
        noteID: String,
        request: DeskFrameRequest,
        animated: Bool
    ) -> Bool {
        guard let panel = panels[noteID] else { return false }
        let priorScreen = panel.screen ?? NSScreen.main
        let screen: NSScreen?
        if let display = request.display {
            guard NSScreen.screens.indices.contains(display - 1) else { return false }
            screen = NSScreen.screens[display - 1]
        } else {
            screen = priorScreen
        }
        guard let screen else { return false }

        let visible = screen.visibleFrame
        let prior = panel.frame
        let priorVisible = priorScreen?.visibleFrame ?? visible
        let priorLocalX = prior.minX - priorVisible.minX
        let priorLocalY = priorVisible.maxY - prior.maxY
        var target = prior
        target.size.width = min(
            max(request.width ?? prior.width, panel.minSize.width), visible.width
        )
        target.size.height = min(
            max(request.height ?? prior.height, panel.minSize.height), visible.height
        )

        // Omitted coordinates preserve the panel's display-local top-left
        // offset, including when moving it to another display.
        target.origin.x = visible.minX + (request.x ?? priorLocalX)
        target.origin.y = visible.maxY - (request.y ?? priorLocalY) - target.height

        target.origin.x = min(max(target.minX, visible.minX), visible.maxX - target.width)
        target.origin.y = min(max(target.minY, visible.minY), visible.maxY - target.height)

        if animated, !target.equalTo(prior) {
            panel.animateLock(to: target)
        } else {
            panel.setFrame(target, display: true)
            panel.saveFrame(usingName: "blink.note.\(noteID)")
        }
        updateFocusOverlay()
        gridOverlay?.refresh()
        onPlacementChanged?(noteID, "panel.moved")
        return true
    }

    /// Close through the panel's normal delegate path so pending text still
    /// flushes before the live window disappears.
    @discardableResult
    func closePanel(noteID: String) -> Bool {
        guard let panel = panels[noteID] else { return false }
        panel.close()
        return true
    }

    // MARK: - Workspace plane

    /// Set before session restore so off-scope panels can be rebuilt in memory
    /// without flashing onto the desktop.
    func configureWorkspaceScope(_ scope: WorkspaceScope) {
        workspaceScope = scope
    }

    /// Switch the live desktop boundary without closing a panel. Every panel
    /// keeps its editor, pending save, exact frame, and membership in the open
    /// set; only AppKit visibility changes. Activating a scope is an explicit
    /// recall action, so it also clears a previous global blink-away state.
    func applyWorkspaceScope(
        _ scope: WorkspaceScope,
        notes: [Note],
        animated: Bool,
        activate: Bool = false
    ) {
        for note in notes { recordPanelWorkspace(note) }
        workspaceScope = scope

        if activate {
            blinkHidden = false
            blinkGeneration += 1
            for task in blinkRevealTasks { task.cancel() }
            blinkRevealTasks.removeAll()
        }

        let matching = panels.filter { panelMatchesWorkspace(noteID: $0.key) }
        let outgoing = panels.filter { !panelMatchesWorkspace(noteID: $0.key) }
        for (id, panel) in outgoing where panel.isVisible {
            workspaceSuppressedPanelIDs.insert(id)
            panel.orderOut(nil)
        }

        guard !blinkHidden else {
            for panel in matching.values where panel.isVisible { panel.orderOut(nil) }
            updateFocusOverlay()
            gridOverlay?.refresh()
            return
        }

        let incoming = matching.filter { id, panel in
            !panel.isVisible && (activate || workspaceSuppressedPanelIDs.contains(id))
        }
        let motion = BlinkConfigStore.shared.config.motion
        let shouldAnimate = animated && motion.enabled && !NotePanel.reduceMotion
        for (id, panel) in incoming {
            workspaceSuppressedPanelIDs.remove(id)
            if shouldAnimate { panel.alphaValue = 0 }
            panel.orderFrontRegardless()
        }
        if shouldAnimate {
            staggerReveal(Array(incoming.values), motion: motion)
        } else {
            for panel in incoming.values { panel.alphaValue = 1 }
        }

        log.info(
            "[BLINK] workspace scope applied",
            metadata: [
                "scope": scope.storageValue,
                "visible": "\(matching.values.filter(\.isVisible).count)",
                "suppressed": "\(outgoing.count)",
            ]
        )
        updateFocusOverlay()
        gridOverlay?.refresh()
    }

    private func recordPanelWorkspace(_ note: Note) {
        if let workspace = note.presentation.workspace {
            panelWorkspaces[note.id] = workspace
        } else {
            panelWorkspaces.removeValue(forKey: note.id)
        }
    }

    private func panelMatchesWorkspace(noteID: String) -> Bool {
        workspaceScope.includes(workspace: panelWorkspaces[noteID])
    }

    var hasCommandNotePanel: Bool { commandNotePanel != nil }

    func toggleCommandNoteMode() {
        guard let panel = commandNotePanel else { return }
        panel.selectMode(panel.currentMode == "edit" ? "read" : "edit")
    }

    func toggleCommandNoteFocus() {
        commandNotePanel?.toggleFocus()
    }

    func hideCommandNote() {
        guard let panel = commandNotePanel else { return }
        panel.orderOut(nil)
        panel.onVisibilityChanged?()
    }

    /// Uses the panel's normal close path. `windowWillClose` still owns the
    /// mandatory pending-save flush, so invoking Close from the palette cannot
    /// bypass Blink's data-safety invariant.
    func closeCommandNote() {
        commandNotePanel?.close()
    }

    func chooseCommandNoteStyle() { commandNotePanel?.showCommandStylePicker() }
    func copyCommandNoteID() { commandNotePanel?.copyCommandNoteID() }
    func copyCommandNoteMarkdown() { commandNotePanel?.copyCommandMarkdown() }
    func copyCommandNoteFilePath() { commandNotePanel?.copyCommandFilePath() }
    func openCommandNoteFile() { commandNotePanel?.openCommandMarkdownFile() }
    func revealCommandNoteInFinder() { commandNotePanel?.revealCommandNoteInFinder() }

    /// Turn the desk into one drawn page. The overlay owns its scoped key
    /// registrations; this manager supplies the live panel set and remembers
    /// which panel should move after Blink (or another app) takes key focus.
    func toggleGridOverlay() {
        if gridOverlay == nil {
            gridOverlay = GridOverlay(
                store: store,
                panels: { [weak self] in self?.openPanelsByID ?? [:] },
                placementPanel: { [weak self] in self?.placementPanel },
                onHide: { [weak self] in self?.updateFocusOverlay() }
            )
        }
        if gridOverlay?.isVisible == false {
            focusOverlay.hide()
            drapeOverlay.hide()
        }
        gridOverlay?.toggle()
        log.info(
            "[BLINK] grid overlay toggled",
            metadata: ["visible": "\(gridOverlay?.isVisible == true)"]
        )
    }

    private var placementPanel: NotePanel? {
        commandNotePanel
    }

    /// Hot-apply a config change to every live surface.
    func applyTheme(_ config: BlinkConfig) {
        for panel in panels.values {
            panel.applyTheme(config)
        }
        focusOverlay.applyTheme(dim: config.focus.dim)
        drapeOverlay.applyTheme(
            dim: config.drape.dim,
            material: config.drape.visualEffectMaterial,
            opacity: config.drape.opacity
        )
        updateDrape()
        // Motion changes (e.g. disabling it) can flip whether peers should be
        // receded — re-evaluate against the live key panel.
        updateFocusRecede(keyPanel: panels.values.first { $0.isKeyWindow })
    }

    /// Tracks the staggered-reveal delay tasks so a rapid re-toggle cancels
    /// them — otherwise a pending reveal could fire after a hide and leave a
    /// panel stuck visible/mid-fade. Exhale animations self-cancel inside
    /// NotePanel when a new entrance/exhale starts on the same panel.
    private var blinkRevealTasks: [Task<Void, Never>] = []
    /// Bumped on every blink toggle. An exhale's async completion checks it and
    /// no-ops if a newer toggle superseded it — so a hide's `orderOut` can never
    /// fire against a panel that a subsequent reveal already brought back.
    private var blinkGeneration = 0

    /// The blink: see every note, then none. Hides/shows all open panels
    /// without closing them — the open list and pending saves are untouched.
    /// State flips instantly; motion is garnish. Rapid toggles cancel any
    /// in-flight motion so a panel is always left fully visible or fully hidden.
    func toggleBlink() {
        let all = panels.filter { panelMatchesWorkspace(noteID: $0.key) }.map(\.value)
        guard !all.isEmpty else { return }
        blinkHidden.toggle()
        blinkGeneration += 1
        let generation = blinkGeneration

        // Cancel any in-flight reveal stagger from a previous toggle so a late
        // entrance can't fight this transition.
        for task in blinkRevealTasks { task.cancel() }
        blinkRevealTasks.removeAll()

        let motion = BlinkConfigStore.shared.config.motion
        let animate = motion.enabled && !NotePanel.reduceMotion
        if blinkHidden {
            if animate {
                // Synchronized exhale: every panel fades + drifts 6px outward
                // together over ~180ms, THEN orderOut. The state is already
                // flipped, so the effect is instantaneous even mid-animation.
                let exhaleMs = min(180, max(80, motion.durationMs * 0.7))
                for panel in all {
                    let drift = Self.outwardDrift(for: panel, distance: 6)
                    panel.animateExhale(direction: drift, durationMs: exhaleMs) { [weak self] in
                        // Superseded by a newer toggle (a reveal): do NOT order
                        // out — the reveal owns this panel's visibility now.
                        guard let self, self.blinkGeneration == generation, self.blinkHidden
                        else { return }
                        panel.orderOut(nil)
                        panel.resetAfterExhale()
                    }
                }
            } else {
                for panel in all { panel.orderOut(nil) }
            }
        } else {
            // Reveal: staggered compass entrances. Order the panels in first
            // (behind alpha 0), then run the stagger with a per-panel inward
            // offset from the panel's screen-edge direction.
            for panel in all {
                if animate { panel.alphaValue = 0 }
                panel.orderFrontRegardless()
            }
            if animate {
                revealWithStagger(all, motion: motion)
            }
        }
        log.info("[BLINK] blink toggled", metadata: ["hidden": "\(blinkHidden)"])
        updateFocusOverlay()
    }

    /// Staggered compass reveal used by the blink: each panel enters from a few
    /// px toward its screen-edge direction and settles into place, `staggerMs`
    /// apart, left-to-right. Delay tasks are tracked so a re-toggle cancels them.
    private func revealWithStagger(_ panels: [NotePanel], motion: BlinkConfig.Motion) {
        let ordered = panels.sorted { $0.frame.minX < $1.frame.minX }
        let stagger = max(0, motion.staggerMs) / 1000
        for (index, panel) in ordered.enumerated() {
            let inward = Self.compassOffset(for: panel, distance: 10)
            let delay = Double(index) * stagger
            if delay <= 0 {
                panel.animateEntrance(motion: motion, fromOffset: inward)
            } else {
                panel.alphaValue = 0
                let task = Task { @MainActor [weak panel] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    panel?.animateEntrance(motion: motion, fromOffset: inward)
                }
                blinkRevealTasks.append(task)
            }
        }
    }

    /// The direction from screen center toward the panel's nearest screen edge,
    /// scaled to `distance`. Used to push a panel *out* on the exhale.
    private static func outwardDrift(for panel: NotePanel, distance: CGFloat) -> CGSize {
        guard let screen = panel.screen ?? NSScreen.main else { return .zero }
        let v = panel.frame
        let center = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        var dx = v.midX - center.x
        var dy = v.midY - center.y
        let len = max(hypot(dx, dy), 0.001)
        dx = dx / len * distance
        dy = dy / len * distance
        return CGSize(width: dx, height: dy)
    }

    /// The inverse of `outwardDrift`: a compass offset pointing *toward* the
    /// screen edge the panel sits nearest to, so a reveal starts pushed out and
    /// settles inward. (Same direction as outwardDrift — the entrance animates
    /// from origin+offset back to the resting origin.)
    private static func compassOffset(for panel: NotePanel, distance: CGFloat) -> CGSize {
        outwardDrift(for: panel, distance: distance)
    }

    /// Quit is imminent: stop treating window closes as the user closing notes.
    /// Without this, termination teardown fires windowWillClose for every panel
    /// and persists an EMPTY open-notes list — killing session restore.
    func prepareForTermination() {
        isTerminating = true
        for id in Array(revealCompletionTasks.keys) { discardTypedReveal(id: id) }
        gridOverlay?.hide()
        focusOverlay.hide()
        drapeOverlay.hide()
    }

    /// Flush every pending save. Called before quit.
    func flushAll() async {
        for id in Array(pendingText.keys) {
            await flush(noteID: id)
        }
    }

    // MARK: - Save policy: debounce, but NEVER drop (v1's data-loss lesson)

    private func scheduleSave(noteID: String, text: String) {
        pendingText[noteID] = text
        saveTasks[noteID]?.cancel()
        saveTasks[noteID] = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            await self?.flush(noteID: noteID)
        }
    }

    private func flush(noteID: String) async {
        saveTasks[noteID]?.cancel()
        saveTasks[noteID] = nil
        guard let text = pendingText.removeValue(forKey: noteID) else { return }
        do {
            let updated = try await store.update(id: noteID, content: text, writer: "user")
            if let panel = panels[noteID], panel.title != updated.title {
                panel.title = updated.title
            }
        } catch {
            // Keep the text pending so a later flush can retry — never drop edits.
            pendingText[noteID] = text
            log.error("[BLINK] save failed", metadata: ["id": noteID, "error": "\(error)"])
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NotePanel else { return }
        let id = panel.noteID
        discardTypedReveal(id: id)
        panel.editor.teardown()
        panels[id] = nil
        panelContent[id] = nil
        panelSlot[id] = nil
        panelWorkspaces[id] = nil
        workspaceSuppressedPanelIDs.remove(id)
        if mostRecentKeyPanelID == id {
            mostRecentKeyPanelID = nil
        }
        gridOverlay?.refresh()
        if !isTerminating {
            persistOpenList()
            Task { await flush(noteID: id) }
            updateFocusOverlay()
        }
    }

    private func persistOpenList() {
        UserDefaults.standard.set(Array(panels.keys).sorted(), forKey: Self.openNotesKey)
    }
}
