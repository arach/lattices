import AppKit

/// Destination selection is independent of Dock's asynchronous transit.
/// Clamp every input, so reversing after holding at an edge responds at once.
struct SpaceSwitchSelection {
    let ordered: [Int]
    private(set) var index: Int
    private(set) var scrubbing = false
    var target: Int { ordered[index] }

    init?(ordered: [Int], current: Int) {
        guard let index = ordered.firstIndex(of: current) else { return nil }
        self.ordered = ordered
        self.index = index
    }

    mutating func press(_ offset: Int, repeated: Bool) {
        scrubbing = scrubbing || repeated
        index = min(max(index + offset, 0), ordered.count - 1)
    }

    mutating func release() { scrubbing = false }
}

/// Main owns selection/presentation; the existing serial worker owns Dock.
/// A held key never queues a switch for each repeated key-down.
final class SpaceSwitchNavigator {
    private var selection: SpaceSwitchSelection?
    private var basis: WindowTiler.SpaceSwitchPlan?
    private var running = false
    private var pending = false
    private var lastDirection = 1
    private var scrubSession = false
    private var epoch = 0
    private let queue: DispatchQueue

    init(queue: DispatchQueue) { self.queue = queue }

    func press(offset: Int, repeated: Bool, point: CGPoint?) {
        dispatchPrecondition(condition: .onQueue(.main))
        if selection == nil {
            guard let plan = WindowTiler.planAdjacentSpaceSwitch(offset: 0, from: point),
                  let state = SpaceSwitchSelection(ordered: plan.display.orderedSpaceIds, current: plan.currentSpaceId) else { return }
            basis = plan
            selection = state
        }
        let previous = selection?.target
        selection?.press(offset, repeated: repeated)
        if previous == selection?.target, selection?.scrubbing != true {
            if !running { selection = nil; basis = nil }
            return
        }
        lastDirection = offset
        pending = true
        guard let selection, let basis else { return }
        if selection.scrubbing {
            if !scrubSession {
                scrubSession = true
                DiagnosticLog.shared.info("SpaceScrub: begin target=\(selection.target)")
                SpaceSwitchBezel.shared.prepareTransitCover(on: WindowTiler.screen(for: basis))
            }
            present(scrubbing: true)
        } else {
            present(scrubbing: false)
            drain()
        }
    }

    func release() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard selection?.scrubbing == true else { return }
        selection?.release()
        DiagnosticLog.shared.info("SpaceScrub: release target=\(selection?.target ?? 0)")
        present(scrubbing: false)
        drain()
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        epoch &+= 1
        selection = nil
        basis = nil
        pending = false
        scrubSession = false
        SpaceSwitchBezel.shared.endTransitCover()
        SpaceSwitchBezel.shared.dismiss()
        // An already-posted Dock gesture cannot be withdrawn. Its completion
        // still releases `running`; epoch prevents it owning the new HUD.
    }

    private func present(scrubbing: Bool) {
        guard let basis, let selection else { return }
        let target = basis.display.spaces.first(where: { $0.id == selection.target })
        SpaceLandscape.shared.dismiss()
        SpaceSwitchBezel.shared.show(direction: lastDirection,
            targetIndex: target?.index, currentIndex: basis.currentIndex,
            display: basis.display, holding: true, scrubbing: scrubbing || target == nil,
            fullscreenOrdinal: target == nil ? selection.index + 1 : nil,
            on: WindowTiler.screen(for: basis))
    }

    private func drain() {
        guard !running, selection?.scrubbing != true, pending,
              let selection, let basis else { return }
        pending = false
        running = true
        let target = selection.target
        let mine = epoch
        let directJump = scrubSession
        // Mission Control selects by display geometry, independently of where
        // the pointer moves while the key is held.
        let bounds = basis.screenDisplayID.map(CGDisplayBounds)
        let point = bounds.map { CGPoint(x: $0.midX, y: $0.midY) }
        let complete: (Bool) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.running = false
                guard mine == self.epoch else { self.drain(); return }
                if self.selection?.scrubbing == true { return }
                if self.pending { self.drain(); return }
                DiagnosticLog.shared.info("SpaceScrub: settled target=\(target) landed=\(result)")
                self.selection = nil
                self.basis = nil
                self.scrubSession = false
                SpaceSwitchBezel.shared.endTransitCover()
                if result && !basis.display.spaces.contains(where: { $0.id == target }) {
                    SpaceSwitchBezel.shared.dismiss()
                } else {
                    SpaceSwitchBezel.shared.finishSwitch()
                }
                if !result { SpaceSwitchBezel.shared.settleOnCurrentSpace() }
            }
        }
        queue.async { [weak self] in
            guard let display = WindowTiler.getDisplaySpaces().first(where: { $0.displayId == basis.display.displayId }),
                  let from = display.orderedSpaceIds.firstIndex(of: display.currentSpaceId),
                  let to = display.orderedSpaceIds.firstIndex(of: target) else { complete(false); return }
            if from == to { complete(true); return }
            let plan = WindowTiler.SpaceSwitchPlan(offset: to - from, display: display,
                screenDisplayID: basis.screenDisplayID, activeSpaceId: display.currentSpaceId,
                currentSpaceId: display.currentSpaceId, targetSpaceId: target)
            let useMissionControl = directJump && abs(to - from) > 1 && point != nil
            let perform = {
                let switched = autoreleasepool {
                    WindowTiler.noteProgrammaticSwitch()
                    let started = ProcessInfo.processInfo.systemUptime
                    let result: Bool
                    if useMissionControl, let point {
                        result = WindowSpaceCarry.selectDesktop(target, on: display.displayId, at: point)
                    } else {
                        result = WindowTiler.performSpaceSwitch(plan)
                    }
                    DiagnosticLog.shared.info("SpaceScrub: transit direct=\(useMissionControl) ms=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000)) landed=\(result)")
                    WindowTiler.noteProgrammaticSwitch()
                    return result
                }
                complete(switched)
            }
            if useMissionControl {
                // Only the direct jump opens Mission Control. Adjacent cuts
                // must never flash covers on the non-participating displays.
                DispatchQueue.main.async {
                    guard let self, mine == self.epoch else { complete(false); return }
                    SpaceSwitchBezel.shared.withTransitCover {
                        guard mine == self.epoch else { complete(false); return }
                        self.queue.async(execute: perform)
                    }
                }
            } else {
                perform()
            }
        }
    }
}
