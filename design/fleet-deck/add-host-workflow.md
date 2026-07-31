# Adding a Mac — workflow design

**Status:** design, not built · 2026-07-30
**Scope:** iPad companion (`apps/ios`), with two small Mac-side notes
**Related:** [token-spec-v7.md](token-spec-v7.md) for type/colour, `ContentView.swift` for the entry model

---

## 1. What exists today

There is no add-host workflow. There is a side effect that sometimes produces one.

**The only automatic path** is in `DeckStore.handleDiscoveryUpdate` (`DeckStore.swift:310`):

```swift
if activeEndpoint == nil, let first = bridges.first {
    connect(to: first)
    return
}
```

On first launch the iPad browses Bonjour, sorts by name, takes `[0]`, and pairs with it. `connect` → `loadConnection` → `ensurePairing` → `POST /pairing/request` → the Mac raises a **modal `NSAlert`** asking the human to approve. The user chose nothing. If three Macs are on the network, the alphabetically-first one gets the prompt.

**The only manual path** is Settings → `macsCard` → tap an online row → `store.connect(to:)`. That is the *primary* store, the one Home renders from. So adding a second Mac **re-points the surface you are looking at**: Mac 1 leaves Home, Mac 2 arrives. Adding is a swap.

**The fleet can't add.** `DeckFleetStore.synchronize` (`DeckStore.swift:511`) has

```swift
guard isTrusted else { continue }
```

which is correct as an automatic policy — Fleet Deck must not spray approval prompts across every Bonjour peer — but it means an untrusted Mac can *only* enter the fleet by first hijacking the primary store. The bottleneck is structural.

**Nothing on the iPad acknowledges pairing.** No "waiting for approval" state, no fingerprint, no denial copy, no cancel. `loadConnection` awaits, and on failure writes `error.localizedDescription` into a red card.

---

## 2. Four states, three of them actionable

Every Mac the app can know about is in exactly one of these. Today the UI conflates them.

| # | State | Known by | Where it belongs | Action |
|---|---|---|---|---|
| 1 | Discovered, untrusted | Bonjour, no matching trust record | **Add sheet** | Add |
| 2 | Discovered, trusted | Bonjour + fingerprint match | **Home roster** | Open |
| 3 | Trusted, not discovered | Trust record only | **Home roster**, dimmed | Reconnect |
| 4 | Unknown | Nothing | **Add sheet**, manual | Enter address |

State 3 is currently a dead card: `makeTrustedOffline` builds it with `host: "paired"` and `status: .offline`, and `onEnterDeck` bails on `.offline`. `StoredBridgeTrust` stores no address, so there is nothing to reconnect *to*. Fixing that is a one-field change (§6).

---

## 3. Principles

**Adding is additive.** Pairing a Mac must never move the Mac you are currently on. This is the same host-ownership property that governs the deck: the surface you are looking at answers to the machine you picked. A new Mac joins the roster; it does not take the throne. Only exception: if there is no primary at all, the first Mac you add becomes it.

**Discovery is not intent.** Finding a Mac on the network is an observation. Pairing with it is a decision, and it fires a modal alert on someone's desk. The app should never make that decision on the user's behalf.

**Both screens show the same number.** Right now the Mac's alert shows the *iPad's* device fingerprint and the iPad (if it showed anything) would have the *Mac's* bridge fingerprint. Different values — nothing to compare. See §5.

**Pairing is slow and that is normal.** The human has to walk to the Mac, find the alert, and read it. The waiting state should be built for minutes, not for a spinner.

---

## 4. The flow

### Entry point: Home, not Settings

Home is the roster. The roster gets one more cell.

```
Machines                          [ Fleet Deck ↗ ]  3

┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│ Mac mini      │ │ Studio        │ │ ⊕             │
│ …             │ │ …             │ │ Add a Mac     │
│               │ │               │ │ 1 found       │
└───────────────┘ └───────────────┘ └───────────────┘
```

The add cell is a peer of the machine cards, same geometry, same `card` surface, no accent. Its subtitle is live: `1 found nearby` / `Nothing found nearby`. That subtitle is the entire replacement for auto-connect — the app still tells you it sees something, it just doesn't act.

Settings keeps only *management*: forget a Mac, review granted capabilities, see fingerprints. Adding leaves Settings.

### Step 1 — Pick

A sheet (`raised`), listing state-1 Macs only. Each row: name, `host` in `textSecondary`, and the Mac's short fingerprint in `textTertiary`. Trusted Macs are deliberately absent — they are already home.

Below the list, one quiet row: **Enter an address manually** → host + port fields, for state 4 and for networks where Bonjour is blocked.

Empty case: *"No new Macs nearby. Open Lattices on the Mac and put both devices on the same Wi-Fi."* — plus a Rescan button that must not clear the roster (§6, bug 2).

### Step 2 — Confirm

The step that does not exist today, and the reason the whole flow is worth building.

```
        Add Studio?

  Your Mac will ask you to allow this iPad.
  Check that it shows this code:

           A3F2-9B41-C0DE

  Studio · studio.local:5287

        [ Ask to pair ]   Cancel
```

That code is **this iPad's own device fingerprint** — `SHA256(devicePublicKeyBase64).prefix(12)`, chunked in fours, exactly the derivation at `LatticesCompanionSecurityCoordinator.swift:357`. The Mac's alert already prints it as `Device Fingerprint`. Showing it here costs no protocol change and no Mac change, and it answers the question the user actually has when an alert pops: *is this me?*

Type: `DeckTheme.title()` at 17pt for the code, grouped in fours. Three groups of four hex characters compare fine chunk-by-chunk in SF Pro; if it reads badly on device, this is the one screen in the app where a mono exception would be earned — comparing a checksum across two devices is columnar data, not terminal cosplay. Judge it on the iPad, not here.

### Step 3 — Waiting

```
        Waiting for Studio

     Approve the prompt on your Mac.

              ● ● ●

              Cancel
```

Patient by construction: a slow three-dot cycle, no progress bar, no percentage. After ~25 seconds add one line — *"Still waiting. The prompt may be behind another window."* — because that is the actual failure mode of a modal `NSAlert` on a busy desktop.

Cancel abandons the request on the iPad. Note honestly: it cannot retract the alert on the Mac. If the user approves after cancelling, the Mac holds a trust record the iPad doesn't — recoverable, because a retry returns `.alreadyTrusted` and the iPad stores it then. Worth a line of copy on the pick step for a Mac in that state, not worth a protocol.

### Step 4 — Outcome

Three distinct endings. They are currently one red card.

**Approved.** Store the trust, keep the session as a **secondary**, dismiss to Home with the new card present. Do not steal the primary. If `grantedCapabilities` is narrower than requested, say it once, here: *"Trackpad control wasn't granted. You can change this on the Mac."* — better than surfacing `insufficientCapability` mid-gesture three days later.

**Denied.** *"Studio declined the request."* with **Try again**. This is an answer, not an error — no red, no warning triangle.

**Unreachable.** *"Couldn't reach Studio."* + *"Make sure Lattices is running and both devices are on the same Wi-Fi."* Distinct from denied, and it must be reachable — see bug 1.

---

## 5. Why the fingerprint is the iPad's, not the Mac's

The instinct is to show the Mac's fingerprint (it's right there in the Bonjour `fp` TXT record and in `health.bridgeFingerprint`). But the user has nothing to check it against — the Mac's alert doesn't print its own fingerprint, and even if it did, an attacker impersonating the Mac would simply print theirs.

Showing the iPad's own fingerprint verifies the direction that actually matters here: *this alert on my Mac was raised by the device in my hand.* It defends the realistic case — a second device on the network triggering a prompt the user approves reflexively.

Proper mutual verification is a short authentication string over both public keys, and it needs Mac-side work. Not now; noted as the upgrade path.

---

## 6. What has to change

Ordered by whether it blocks the flow.

**Bug 1 — pairing times out in 10s, not 90s.** `DeckBridgeClient.pair` sets `request.timeoutInterval = 90` (`DeckBridgeClient.swift:88`), but the shared session config sets `timeoutIntervalForResource = 10` (line 71). The resource timeout caps the whole transfer, so it wins. Today the iPad gives up ten seconds into a human decision. **This makes step 3 impossible as designed** and probably explains any "pairing failed but the Mac says it worked" behaviour already seen. Fix: a dedicated `URLSession` for `/pairing/request` with a resource timeout in the minutes.

**Bug 2 — rescan destroys the fleet.** `BridgeDiscovery.refresh()` calls `onUpdate?([])` before restarting the browser. That fires `ContentView.onChange(of: store.discoveredBridges)` → `synchronize` with zero endpoints → every secondary store is disconnected and dropped. Rediscovery then builds **new** `DeckStore`s with new `sessionID`s, and since `FleetChannel.id = store.sessionID.uuidString` (`FleetDeckAdapter.swift:49`), the deck's channel identity resets. Rescan is exactly what a user taps while adding a Mac. Fix: re-browse without publishing an empty roster, or debounce the empty publish.

**Change 1 — `DeckFleetStore.adopt(endpoint:)`.** A deliberate add mints a secondary store for an *untrusted* endpoint, bypassing the `isTrusted` guard, and `synchronize` must not reap it while pairing is in flight. This is the change that makes adding additive instead of a swap. The `isTrusted` guard stays exactly as-is for the automatic path — it is doing its job.

**Change 2 — auto-connect only to trusted Macs.** In `handleDiscoveryUpdate`, qualify the `activeEndpoint == nil` branch with a fingerprint match against `trustedBridgeList()`. A previously-paired Mac still reconnects silently on launch, which is right. An unknown Mac lands in the roster as a candidate.

**Change 3 — `StoredBridgeTrust` remembers where.** Add `lastKnownHost: String?` and `lastKnownPort: Int?`, written on every successful connection. Both optional, so existing persisted JSON decodes unchanged — no migration. This turns state 3 from a dead card into a Reconnect.

**Change 4 — a pairing state machine.** Something like `enum PairingPhase { idle, confirming(BridgeEndpoint), waiting(BridgeEndpoint), approved(…), denied(String), unreachable(String) }`, owned by whatever backs the add sheet. Today the outcome is inferred from a thrown error's `localizedDescription`, which is why denied and unreachable look identical.

**Change 5 — manual connects inherit identity.** `connectManually` builds an endpoint with no fingerprint, so `DeckFleetStore.endpointKey` falls back to `service:<host>:<port>` and can never dedupe against the same Mac seen over Bonjour. `canonicalEndpoint(from:health:)` already backfills the fingerprint from `health` — the manual path just needs to persist the canonical endpoint rather than the typed one.

---

## 7. Deliberately not doing

- **QR / camera pairing.** Faster, but it needs a Mac-side display surface and it removes the moment where the user reads what they are approving. Revisit if manual entry proves painful.
- **Pairing from the Fleet Deck.** The deck is for operating machines that are already yours. Roster management belongs to Home.
- **Auto-adding every trusted Mac to the fleet.** Already the behaviour, already correct.
- **Mutual SAS verification.** The right endpoint, gated on Mac-side work.

---

## 8. Open

- Should a newly added Mac ever become the primary when one already exists? Designed as no. The counter-argument is that you just expressed intent about that machine — but you expressed intent to *add* it, and the deck is one tap away.
- Does the add cell belong in the roster grid, or in the section header next to Fleet Deck? Grid, because it's a machine-shaped thing; but the header keeps the grid honest at 4+ machines.
- Fingerprint face — SF Pro or the one mono exception. On-device call.
