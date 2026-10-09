import AppKit

/// A ⌘⌥ browse that moves nothing until it's let go. While ⌘⌥ is held, the
/// arrows and digits aim at a layer: the pad lights its slot and lists its
/// windows, where they are now, and no window moves. Letting go of ⌘⌥
/// switches to the layer aimed at, once. Escape, the middle slot, or
/// someone else's ⌘⌥ shortcut drops the aim and leaves every window be.
///
/// Space mid-browse freezes on the layer aimed at (`LayerPreview`), which
/// takes the aim over; its Enter switches.
final class LayerAim {
    static let shared = LayerAim()

    /// The layer aimed at, while ⌘⌥ is held.
    private(set) var target: Int?
    /// How many keys aimed in this hold. Aiming at the layer you're on as
    /// the only key reconciles it, as ⌘⌥N always has; browsing back to it
    /// leaves it be.
    private var steps = 0
    private var watch: Timer?

    private init() {}

    /// Where the next arrow steps from: the layer aimed at, else the one
    /// you're on.
    func origin(in workspace: WorkspaceManager) -> Int {
        let count = workspace.layers.count
        return min(max(target ?? workspace.activeLayerIndex, 0), max(count - 1, 0))
    }

    /// Aims at layer `index` and shows it on the pad. With ⌘⌥ already up,
    /// it switches at once.
    func aim(at index: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        let workspace = WorkspaceManager.shared
        let layers = workspace.layers
        guard layers.indices.contains(index) else { return }
        target = index
        steps += 1
        guard Self.chordHeld() else {
            commit()
            return
        }
        workspace.showBezel(for: index, in: layers)
        watchRelease()
    }

    /// ⌘⌥ came up: switch to the layer aimed at. A freeze owns the aim
    /// instead, and switches on its own Enter.
    func commit() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let index = target, !LayerPreview.shared.isFrozen else { return }
        let reconcile = steps == 1
        reset()
        let workspace = WorkspaceManager.shared
        guard workspace.layers.indices.contains(index) else { return }
        if index == workspace.activeLayerIndex, !reconcile {
            workspace.showBezel(for: index, in: workspace.layers)
            return
        }
        workspace.focusLayer(index: index)
    }

    /// Drops the aim: no window moves.
    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard target != nil else { return }
        reset()
        DiagnosticLog.shared.info("LayerAim: cancelled; nothing moved")
    }

    /// Hands the aim to a freeze, which shows that layer.
    func take() -> Int? {
        defer { reset() }
        return target
    }

    private func reset() {
        target = nil
        steps = 0
        watch?.invalidate()
        watch = nil
    }

    /// A release the chord monitor misses (no tap, a key that came in after
    /// its release) still commits.
    private func watchRelease() {
        guard watch == nil else { return }
        watch = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self, !Self.chordHeld() else { return }
            self.commit()
            if self.target != nil, LayerPreview.shared.isFrozen {
                // The freeze has it now.
                self.watch?.invalidate()
                self.watch = nil
            }
        }
    }

    private static func chordHeld() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(.maskCommand) && flags.contains(.maskAlternate)
    }
}
