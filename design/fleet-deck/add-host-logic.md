# Add a Mac — the logic

**Status:** implementation-ready design · 2026-07-30
**Companion to:** [add-host-workflow.md](add-host-workflow.md) (the why, the screens)

Deliberately small: one new file, one new sheet, four edits to existing files.

---

## 0. The simplification

The workflow doc proposed `DeckFleetStore.adopt(endpoint:)` that **bypasses** the `guard isTrusted else { continue }` in `synchronize`, so a Mac could be adopted while still untrusted. That created a hard problem — keeping an in-flight adoptee alive across the `discoveredBridges` churn that happens *during* pairing, when `synchronize` rebuilds `secondaryStores` wholesale and reaps by key diff.

The problem disappears if you **pair first and adopt second**:

```
health → pair → store trust → adopt
                    ↑
            endpoint is trusted from here on
```

By the time anything is adopted, the Mac *is* trusted, so it passes the existing guard unchanged. No bypass, no holding area, no flag. `adopt` shrinks to "insert this now-trusted endpoint immediately instead of waiting for the next discovery tick" — which is still worth having, because a manually-entered Mac may never appear on Bonjour at all.

This also moves pairing out of `loadConnection`, where it is currently an invisible side effect (`ensurePairing`), and into a place where each step has a name and a screen.

---

## 1. New file: `apps/ios/Sources/Home/AddHostController.swift`

```swift
import DeckKit
import SwiftUI

/// Why pairing ended without a Mac being added.
enum AddHostFailure: Equatable {
    /// The Mac declined. An answer, not an error — no red.
    case denied
    /// We never got far enough to be declined.
    case unreachable(String)
}

/// One sheet, five phases. Each has exactly one screen.
enum AddHostPhase: Equatable {
    case picking
    case confirming(BridgeEndpoint)
    case waiting(BridgeEndpoint)
    case added(BridgeEndpoint, withheld: [String])
    case failed(BridgeEndpoint, AddHostFailure)
}

@MainActor
final class AddHostController: ObservableObject {
    @Published private(set) var phase: AddHostPhase = .picking
    /// Set while `.waiting` has run long enough to be worth explaining.
    @Published private(set) var isTakingAWhile = false

    private let client = DeckBridgeClient()
    private var pairingTask: Task<Void, Never>?

    /// This iPad's own fingerprint, in the derivation the Mac's approval alert
    /// prints (`LatticesCompanionSecurityCoordinator.swift:357`). The same
    /// string appears on both screens — that is the entire point of showing it.
    let deviceCode = DeckBridgeSecurityStore.shared.deviceFingerprint

    // MARK: Navigation

    func choose(_ endpoint: BridgeEndpoint) { phase = .confirming(endpoint) }

    func backToPicking() {
        pairingTask?.cancel()
        pairingTask = nil
        isTakingAWhile = false
        phase = .picking
    }

    // MARK: The handshake

    /// Pair, then hand the trusted endpoint to `onPaired`.
    ///
    /// Order matters: trust is stored *before* any session is created, so the
    /// new Mac passes `DeckFleetStore`'s existing trust guard on its own and
    /// nothing has to be held open across discovery churn.
    func pair(
        with endpoint: BridgeEndpoint,
        onPaired: @escaping (BridgeEndpoint) -> Void
    ) {
        phase = .waiting(endpoint)
        isTakingAWhile = false

        pairingTask = Task {
            // Explain the wait before the user starts inventing reasons for it.
            let nudge = Task {
                try? await Task.sleep(for: .seconds(25))
                if !Task.isCancelled { self.isTakingAWhile = true }
            }
            defer { nudge.cancel() }

            let health: BridgeHealthResponse
            do {
                health = try await client.health(endpoint: endpoint)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(endpoint, .unreachable(error.localizedDescription))
                return
            }

            // Carry the Mac's identity onto the endpoint. A manually-typed
            // endpoint has no Bonjour `fp` record, and without this it would
            // never match a trust record or dedupe against the same Mac
            // discovered over Bonjour.
            let canonical = endpoint.adoptingIdentity(from: health)

            do {
                let response = try await client.pair(endpoint: canonical)
                guard !Task.isCancelled else { return }

                switch response.disposition {
                case .approved, .alreadyTrusted:
                    DeckBridgeSecurityStore.shared.storePairing(
                        response,
                        lastKnownHost: canonical.host,
                        lastKnownPort: canonical.port
                    )
                    onPaired(canonical)
                    phase = .added(canonical, withheld: withheld(from: response))
                case .denied:
                    phase = .failed(canonical, .denied)
                }
            } catch let DeckBridgeClientError.badStatus(status, detail) where status == 403 {
                guard !Task.isCancelled else { return }
                phase = .failed(canonical, .denied)
                _ = detail
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(canonical, .unreachable(error.localizedDescription))
            }
        }
    }

    /// Capabilities we asked for and did not get. Told once, here, rather than
    /// surfacing as `insufficientCapability` mid-gesture three days later.
    private func withheld(from response: DeckPairingResponse) -> [String] {
        let granted = Set(response.grantedCapabilities ?? DeckBridgeCapability.defaultCompanionCapabilities)
        return DeckBridgeCapability.defaultCompanionCapabilities
            .filter { !granted.contains($0) }
    }
}

// MARK: - Candidates

extension AddHostController {
    /// Macs on the network this device has never paired with. Trusted Macs are
    /// deliberately absent — they are already in the roster.
    static func candidates(from store: DeckStore) -> [BridgeEndpoint] {
        store.discoveredBridges.filter { !DeckBridgeSecurityStore.shared.isTrusted(endpoint: $0) }
    }
}
```

**Cancel semantics.** `backToPicking` cancels the task, which abandons the request on the iPad. It cannot retract the alert on the Mac — if the user approves after cancelling, the Mac holds a trust record the iPad does not. That state is self-healing: a retry gets `.alreadyTrusted` and the iPad stores it then. Worth one line of copy, not a protocol.

---

## 2. Edit: `DeckBridgeSecurityStore.swift`

Three additions.

```swift
/// This device's fingerprint, derived exactly as the Mac derives it for its
/// approval alert, so the two screens show the same string.
var deviceFingerprint: String {
    let digest = SHA256.hash(data: Data(devicePublicKeyBase64.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return String(hex.prefix(12)).uppercased().chunked(into: 4).joined(separator: "-")
}

/// One definition of "have we paired with this Mac". The same fingerprint
/// comparison is currently written out by hand in `ContentView.prepareConnection`
/// and `DeckFleetStore.synchronize`; both should call this.
func isTrusted(endpoint: BridgeEndpoint) -> Bool {
    guard let fingerprint = endpoint.bridgeFingerprint, !fingerprint.isEmpty else { return false }
    return trustedBridges.values.contains {
        $0.bridgeFingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame
    }
}
```

And `StoredBridgeTrust` remembers where the Mac was:

```swift
struct StoredBridgeTrust: Codable, Equatable, Sendable {
    …
    var lastKnownHost: String?
    var lastKnownPort: Int?
}
```

Both optional, so the JSON already in `UserDefaults` decodes unchanged — no migration. This is what turns a paired-but-offline Mac from a dead card into a Reconnect. `storePairing` gains the two parameters; every successful `loadConnection` should also refresh them, since Macs change address.

---

## 3. Edit: `DeckStore.swift`

**Auto-connect only to Macs we already trust.** `handleDiscoveryUpdate:310` becomes:

```swift
// Discovery is an observation, not an intent. Reconnecting to a Mac this
// device already paired with is silent and correct; pairing with a stranger
// raises a modal alert on someone's desk and must be the user's decision.
if activeEndpoint == nil,
   let known = bridges.first(where: { DeckBridgeSecurityStore.shared.isTrusted(endpoint: $0) }) {
    connect(to: known)
    return
}
```

Note `first(where:)`, not `first`: with three Macs on the network and one paired, the paired one is picked regardless of alphabetical order.

**`DeckFleetStore.adopt(endpoint:)`** — for responsiveness and for manual endpoints Bonjour will never report:

```swift
/// Insert a just-paired Mac as a secondary session immediately, rather than
/// waiting for the next discovery tick. Safe against the trust guard in
/// `synchronize` because the caller stores trust before adopting.
func adopt(_ endpoint: BridgeEndpoint) {
    let key = Self.endpointKey(endpoint)
    guard storesByEndpointKey[key] == nil else { return }
    let store = DeckStore(endpoint: endpoint, discoversBridges: false)
    storesByEndpointKey[key] = store
    secondaryStores.append(store)
}
```

One caveat to carry: `synchronize` rebuilds `secondaryStores` from `discoveredBridges`, so a manually-added Mac that Bonjour never reports gets reaped on the next tick. Either `synchronize` preserves keys it did not create, or manual Macs are re-seeded from `lastKnownHost`/`lastKnownPort`. **The second is better** — it is the same mechanism state 3 (trusted, not discovered) needs anyway, so one fix serves both.

---

## 4. Edit: `ContentView.swift`

```swift
@State private var showAddHost = false
```

```swift
onAddHost: { showAddHost = true },
```

```swift
.sheet(isPresented: $showAddHost) {
    AddHostSheet(store: store) { endpoint in
        // Additive: the Mac you are looking at does not move. The only
        // exception is having nothing to look at.
        if store.activeEndpoint == nil {
            store.connect(to: endpoint)
        } else {
            fleetStore.adopt(endpoint)
        }
    }
    .preferredColorScheme(.dark)
}
```

That `if` is the whole "adding is additive" decision, and it is three lines. Everything else in this document exists to make those three lines safe.

Also: `prepareConnection` should drop its hand-rolled fingerprint comparison in favour of `isTrusted(endpoint:)`.

---

## 5. Edit: `HomeTargetsRow.swift`

`onAddHost: (() -> Void)?`, and an add cell rendered as the last item of the grid — peer of the machine cards, same geometry, `card` surface, no accent. Subtitle is live:

```swift
let nearby = AddHostController.candidates(from: store).count
// "2 found nearby" / "Nothing found nearby"
```

That subtitle is the entire replacement for auto-connect: the app still tells you it can see something, it just no longer acts on it.

Open (kimi ruling requested): whether the cell belongs in the grid or in the section header beside the Fleet Deck door.

---

## 6. Blocking bugs

Neither is caused by this design; both prevent it from working. Verification requested from codex.

**Pairing times out in 10s, not 90s.** `DeckBridgeClient.swift:88` sets `request.timeoutInterval = 90`; the shared session config at line 71 sets `timeoutIntervalForResource = 10`, which caps the entire transfer. `.waiting` cannot outlive ten seconds until `/pairing/request` gets its own session:

```swift
private let pairingSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 120
    configuration.timeoutIntervalForResource = 180
    return URLSession(configuration: configuration)
}()
```

**Rescan destroys the fleet.** `BridgeDiscovery.refresh()` publishes `[]` before restarting the browser, which drives `synchronize` to drop every secondary store; rediscovery mints new `DeckStore`s with new `sessionID`s, and `FleetChannel.id` is that UUID, so channel identity resets. Rescan is exactly what a user taps while adding a Mac. Fix: re-browse without publishing the empty roster.

---

## 7. Scope

**In:** the five phases, the additive add, trusted-only auto-connect, the device code, `lastKnownHost`/`Port`, both bug fixes.

**Out:** QR pairing, pairing from the Fleet Deck, mutual SAS verification, reconnect-to-offline-Mac (needs `lastKnownHost` first, then it is a small follow-up).
