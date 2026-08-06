# Connection lifecycle — review

**Scope:** connect · disconnect · refresh · status · remote logs
**Date:** 2026-07-30 · iPad companion + Mac bridge
**Occasion:** a revoked pairing left the iPad permanently stuck with no way out from the iPad alone. That class of bug — *a state the user cannot escape* — is what this review is looking for.

Findings are ordered by that test first, then by severity.

---

## 0. The one that already bit

Fixed today, recorded because the shape recurs below.

Trust is **two records, one per device**, and either side can drop its own silently. When the Mac revoked the iPad:

- `ensurePairing` opens `guard security.isTrusted(health: health) == false else { return }` — so the iPad never re-pairs while it holds a record. The record that would let it recover was the record blocking recovery.
- `disconnect()` cleared the session but not the trust, and `handleDiscoveryUpdate` reconnects to any trusted host whenever `activeEndpoint == nil`. Disconnect was undone by the next Bonjour update.
- Forget was `.swipeActions` on a `Button` inside a `VStack`. That modifier only works inside a `List`. Dead UI.

Three independent bugs, each survivable alone; together, a dead end. The Mac's own trusted-device store showed the iPad's last successful auth was two days before the user noticed.

---

## 1. Connect

### 1.1 Connect is fire-and-forget and can resolve out of order — **host ownership**

`DeckStore.connect(to:)` sets published state, then launches an **untracked** `Task { await loadConnection(...) }`. Nothing cancels a previous one.

`loadConnection` then mutates shared state at six points with `await`s between them: `health`, `activeEndpoint`, `manualHost/Port`, `manifest`, `snapshot`, `startPolling`. Two connects in flight interleave freely, and the **later-finishing** one wins — not the later-*requested* one.

Consequences: tap Mac A, then Mac B, and you can end up driving A. Worse, you can end up with A's `health` and B's `manifest`, because there is no atomicity across the sequence. Every protected request signs against `health.bridgePublicKey`, so a mismatched pair silently authenticates to the wrong Mac or fails in a way that reads as a network fault.

This is the same property the deck entry model was built to protect. It is unguarded one layer down.

**Fix:** a generation token checked after every `await`, or a retained `connectTask` cancelled on entry. The token is cheaper and survives cancellation races.

### 1.2 `performWithFallback` reassigns `activeEndpoint` from inside an action

`candidateEndpoints(for:)` walks alternatives and, on success, writes `activeEndpoint`, `manualHost`, `manualPort`. So a routine action can silently re-point the session while a connect is in flight. Combined with 1.1 there is no single owner of `activeEndpoint`.

### 1.3 Snapshot polling has no address fallback, but actions do

`performWithFallback` tries every candidate endpoint. `refreshSnapshot(endpoint:)` takes `preferredEndpoint(fallback:)` and nothing else. So when a Mac changes address, **actions keep working and the snapshot goes stale** — the UI freezes while the buttons still fire. Asymmetric by accident, and the wrong way round: stale state is more dangerous than a failed action, because it looks fine.

### 1.4 There is no reconnect path at all

If `/health` succeeded once and later fails, nothing ever re-runs `loadConnection`. `startPolling` only ever calls `refreshSnapshot`, which only calls `client.snapshot`. A Mac that restarts its bridge, changes address, or re-keys is never re-handshaked — the session just fails forever at 1–5s intervals.

---

## 2. Disconnect

### 2.1 `autoConnectSuppressed` does not survive relaunch — **escapable, but only just**

The flag added today is in-memory. Quit the app and the iPad reconnects to a host the user deliberately disconnected. Disconnect currently means "until you next launch."

If a deliberate disconnect is meant to be durable it should persist, keyed on `bridgePublicKey` — the same identity trust uses, not host:port.

### 2.2 Forgetting a Mac does not stop its secondary session — **leak**

`DeckStore.forget(publicKey:)` removes the trust record and disconnects *the primary* if it matches. Secondary stores are untouched.

`DeckFleetStore.synchronize` is what reaps untrusted stores, and it only runs from `ContentView.onChange(of: store.discoveredBridges)` / `.onChange(of: store.activeEndpoint)`. Forgetting changes neither. So **a forgotten secondary Mac keeps polling on its 1–5s loop** until discovery happens to change — signing requests against a Mac the user just told us to drop.

### 2.3 `DeckFleetStore.release(_:)` is dead code

Written this morning, never called. Either wire it to forget or delete it; an unused disconnect path is a maintenance trap.

### 2.4 Secondary Macs cannot be disconnected individually

Settings manages the primary only. The only way to drop a fleet member is Forget, which is a heavier action (it destroys the pairing). There is no "disconnect this one for now."

---

## 3. Refresh

### 3.1 No backoff — a dead host is hammered forever

```swift
while !Task.isCancelled {
    try? await Task.sleep(for: .seconds(interval))
    await self.refreshSnapshot(endpoint: endpoint)
}
```

`currentPollInterval` is 1–5s and derived only from *desired liveness*, never from *observed health*. An unreachable Mac is retried every 1–5 seconds indefinitely, each attempt paying a 6s connect timeout.

Worse: `currentPollInterval` returns **1.0** when `snapshot?.questions` is non-empty. A snapshot that went stale while holding a question pins the loop at 1Hz against a host that is not answering — the failure state is the most expensive state.

### 3.2 Every failure overwrites one shared `errorMessage`

Eight write sites, every severity into one `String?`. A rejected trackpad gesture overwrites "the bridge is unreachable." This is also what made the revocation invisible: a 403 read the same as any transient error.

`FleetDeckAdapter` already had to work around it — it routes `errorMessage` to `fault` precisely so a bad swipe cannot masquerade as a channel needing attention.

### 3.3 `refreshDiscovery` is the only user-facing recovery, and it is indirect

The user's lever for "something is wrong" is Refresh, which restarts the Bonjour browse. It does not re-handshake, re-pair, or reset a session. For every failure in §1 and §2 it is the wrong tool, but it is the only one offered.

---

## 4. Status

### 4.1 The model cannot express what actually goes wrong

`HomeMachineStatus` is `active / online / standby / offline`.

- **`.standby` is never produced.** `HomeDataAdapter` emits only `.active`, `.online`, `.offline`.
- **`latencyMs` is hardcoded `nil`** at all three construction sites, while `HomeTargetCard` has a rendering branch for it.
- There is no **connecting**, **retrying**, **degraded**, or **trust lost**.

`isLoading` exists on the store and Home never reads it.

### 4.2 Status is derived from presence, not from health

`makeDiscovered` returns `.online` for anything Bonjour can see. A Mac that is advertising happily and 403ing every request shows as **ONLINE**. That is precisely today's failure rendered as a green light.

The honest minimum:

| State | Means |
|---|---|
| `active` | authenticated, snapshot fresh, foreground |
| `online` | authenticated, snapshot fresh |
| `connecting` | handshake in flight |
| `degraded` | authenticated once, last N polls failed |
| `untrusted` | reachable, but it refused us — **actionable: add again** |
| `offline` | paired, not reachable |

`untrusted` is the one that would have made today visible in a glance instead of a two-day silence.

### 4.3 There is no per-host error surface

`errorMessage` belongs to the store. Home shows machine cards. A secondary Mac's failure has nowhere to appear on Home at all.

---

## 5. Remote logs — what is actually possible

**Better than expected: the data already exists and is already structured.**

`DiagnosticLog` (`apps/mac/Sources/Core/System/DiagnosticLog.swift`) is a `HudLogStore` facade holding `Entry { id, time, message, level }` with levels info/success/warning/error. It is in-memory, published, and already carries exactly the events this review cares about — `CompanionPairing: approved device id=…`, `CompanionBridge: accept() failed`, and so on.

**It is not exposed over the bridge.** `LatticesCompanionBridgeServer` references `DiagnosticLog` only to *write* to it. There is no route.

The iPad's only view of the Mac is `snapshot.activityLog`, which is written in exactly one place — `LatticesDeckHost.swift:1493`, `tag: "DECK"`, `text: outcome.summary`. So it narrates deck actions and nothing else. (It is also why `FleetDeckAdapter.swift:59` names every channel "DECK": `agentName: log.first?.tag.uppercased()`.)

**Proposal — `GET /deck/diagnostics`, protected:**

- Under a **new capability**, `diagnostics.read`, not `deck.read`. Reading a Mac's internal log is a different grant from reading its deck state, and the capability mechanism already exists to say so — including letting a Mac withhold it.
- **Cursor semantics**: `?since=<entry id or ISO timestamp>&limit=200`, returning newest-first with a `nextCursor`. The ring is small but polling it whole every second would be silly.
- **Redaction before it leaves the Mac.** The log today carries device ids, key fingerprints, and host names. Pairing lines print the full device UUID. A companion showing a log should see events, not identifiers — truncate ids to the same 12-hex form the pairing code uses, and drop public keys entirely.
- **Not on the snapshot poll.** A separate, explicitly-opened surface, fetched only while a log view is on screen. Otherwise every iPad drags the Mac's log across the network at 1Hz forever.

This is worth doing precisely because of §0: when the connection is broken, `snapshot` is exactly what you cannot get. A diagnostics read that works while the deck is failing is the difference between "it doesn't work" and "the Mac revoked you at 21:13."

---

## 6. Ranked

**Escapability — a user stuck with no iPad-side way out:**
1. §2.2 forgotten secondary keeps polling and signing (leak, silent)
2. §1.4 no reconnect path — a session can only die, never recover
3. §2.1 disconnect does not survive relaunch

**Correctness:**
4. §1.1 connect races — wrong Mac, or a spliced session
5. §1.3 snapshot has no address fallback while actions do — stale UI that looks live
6. §1.2 actions re-point `activeEndpoint`

**Honesty:**
7. §4.2 `.online` for a Mac that is refusing us
8. §3.2 one `errorMessage` for every severity
9. §4.1 dead `.standby`, always-nil `latencyMs`

**Capability:**
10. §5 remote diagnostics — the thing that would have made §0 self-service

---

## 7. Proposed order

1. **403 coverage + disambiguation.** Wire revocation detection into `perform` and `sendTrackpad`. But `untrustedDevice` and `insufficientCapability` are *both* 403 on the Mac, so naive handling would delete a good pairing over a capability shortfall — needs a discriminator before it is safe to broaden. Fail closed: only forget on 403 when the request was `deck.read`, which every pairing grants.
2. **Forget must stop secondaries** — call `DeckFleetStore.release` and re-synchronize.
3. **Backoff** on consecutive failures, and stop letting a stale question pin a dead host at 1Hz.
4. **Connection generation token** in `loadConnection`.
5. **Status model** — add `connecting` / `degraded` / `untrusted`; delete `.standby` or produce it.
6. **`/deck/diagnostics`** behind `diagnostics.read`.
