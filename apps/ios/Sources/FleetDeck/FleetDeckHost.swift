import Combine
import DeckKit
import SwiftUI

/// Keeps a `FleetDeckModel` fed from live `DeckStore`s.
///
/// The stores are independent `ObservableObject`s, one per Mac, so the host
/// subscribes to each and re-projects the deck whenever any of them lands a new
/// snapshot. Re-projection happens on the next run loop turn — `objectWillChange`
/// fires *before* the store mutates — so the model always reads settled values.
@MainActor
final class FleetDeckController: ObservableObject {
    let model = FleetDeckModel()

    private var stores: [DeckStore] = []
    private var cancellables: [AnyCancellable] = []
    private var modelCancellables: [AnyCancellable] = []

    init() {
        // Selection lives on the model, but the host reads per-host values off
        // `currentStore` (voice phase, busy, which console actions the Mac can
        // service). Without forwarding, picking a channel invalidates the deck
        // body but not the host that computes those, so they keep describing
        // the Mac you just left.
        modelCancellables.append(
            model.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        )
        // Command sets belong to the Mac on deck; re-derive them whenever the
        // deck changes hands.
        modelCancellables.append(
            model.$currentIndex
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.syncSets() }
        )
    }

    func bind(stores: [DeckStore], initialMachineID: String? = nil) {
        let sameStores = stores.count == self.stores.count
            && zip(stores, self.stores).allSatisfy { $0.sessionID == $1.sessionID }
        guard !sameStores else {
            requestHost(machineID: initialMachineID, in: stores)
            refresh()
            return
        }

        self.stores = stores
        cancellables = stores.map { store in
            store.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() }
        }
        requestHost(machineID: initialMachineID, in: stores)
        refresh()
    }

    /// Translate the presenter's `BridgeEndpoint.id` into the channel identity
    /// the model speaks — a store's `sessionID`.
    ///
    /// One-shot. `bind` runs again on every roster change, and an opening
    /// preference must not survive as standing policy: otherwise any Mac
    /// appearing or dropping would drag the user back to wherever they entered.
    private var didApplyInitialHost = false

    private func requestHost(machineID: String?, in stores: [DeckStore]) {
        guard !didApplyInitialHost, let machineID else { return }
        guard let match = stores.first(where: { $0.activeEndpoint?.id == machineID }) else {
            // Its store may still be connecting; try again on the next roster change.
            return
        }
        didApplyInitialHost = true
        model.requestHost(match.sessionID.uuidString)
    }

    func refresh() {
        let channels = FleetDeckAdapter.channels(from: stores)
        model.ingest(channels: channels)
        // After ingest, never before: ingest can move the selection.
        syncSets()
    }

    private func syncSets() {
        // Always reassign. Two Macs can advertise pages with identical ids, so
        // there is no cheap equality check that is also correct — and getting
        // this wrong means dispatching one Mac's tile to another.
        model.sets = FleetDeckAdapter.sets(from: currentStore)
    }

    /// The store backing whatever channel is on deck.
    ///
    /// Resolved by identity rather than position. Indexing `stores` with
    /// `model.currentIndex` happens to work — the adapter builds one channel per
    /// store, in order — but nothing enforces that, and every control on the
    /// deck routes through here. If the two collections ever diverge, the
    /// failure is keystrokes and trackpad input landing on the wrong Mac, which
    /// is both silent and the worst outcome this screen has.
    var currentStore: DeckStore? {
        guard let hostID = model.currentHostID else { return stores.first }
        return stores.first { $0.sessionID.uuidString == hostID } ?? stores.first
    }

}

// MARK: - Host

/// Binds the deck to a set of live Macs and wires every control to the Mac that
/// is on deck.
struct FleetDeckHost: View {
    let stores: [DeckStore]
    /// `BridgeEndpoint.id` of the Mac the deck should open on, when the caller
    /// knows which one the user meant.
    var initialMachineID: String?
    var onClose: (() -> Void)?

    @StateObject private var controller = FleetDeckController()

    var body: some View {
        FleetDeckView(
            model: controller.model,
            voicePhase: controller.currentStore?.snapshot?.voice?.phase,
            voiceTranscript: controller.currentStore?.snapshot?.voice?.transcript ?? "",
            isBusy: controller.currentStore?.isPerformingAction ?? false,
            isOnline: !stores.isEmpty && stores.contains { $0.snapshot != nil },
            onClose: onClose,
            onPushToTalk: { controller.currentStore?.toggleVoice() },
            onTile: { tile in
                guard let actionID = tile.actionID else { return }
                controller.currentStore?.perform(
                    actionID: actionID,
                    pageID: controller.model.activeSet?.id ?? "cockpit",
                    payload: tile.payload,
                    label: tile.title
                )
            },
            onKey: { key, modifiers in
                controller.currentStore?.perform(
                    actionID: "keys.send",
                    pageID: "cockpit",
                    payload: [
                        "key": .string(key),
                        "modifiers": .array(modifiers.map { .string($0) })
                    ],
                    label: (modifiers + [key.uppercased()]).joined()
                )
            },
            onChoose: { option in
                guard let actionID = option.actionID else { return }
                controller.currentStore?.perform(
                    actionID: actionID,
                    pageID: "cockpit",
                    label: option.title
                )
            },
            onSendText: { text in
                controller.currentStore?.perform(
                    actionID: "keys.type",
                    pageID: "cockpit",
                    payload: ["text": .string(text)],
                    label: "Type text"
                )
            },
            onTrackpad: { event, dx, dy in
                controller.currentStore?.sendTrackpad(event: event, dx: dx, dy: dy)
            },
            onWindowDrag: { dx, dy in
                controller.currentStore?.perform(
                    actionID: "window.dragBy",
                    pageID: "cockpit",
                    payload: ["dx": .double(dx), "dy": .double(dy)],
                    label: "Drag window"
                )
            }
        )
        .onAppear { controller.bind(stores: stores, initialMachineID: initialMachineID) }
        .onChange(of: stores.map(\.sessionID)) { _, _ in
            // Keep passing the requested host: it may only now have connected.
            controller.bind(stores: stores, initialMachineID: initialMachineID)
        }
    }
}

#if DEBUG
/// Renders the deck against the design's own fixture data — no Macs required.
struct FleetDeckFixtureHost: View {
    @StateObject private var model = FleetDeckModel()
    var onClose: (() -> Void)?

    var body: some View {
        FleetDeckView(
            model: model,
            voicePhase: .listening,
            voiceTranscript: "run the simulator suite again, then post the diff for review",
            isOnline: true,
            onClose: onClose
        )
        .onAppear {
            if model.channels.isEmpty {
                model.loadFixture()
            }
        }
    }
}
#endif
