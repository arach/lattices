# Add-host workflow — adversarial review

**Reviewer:** session-ms7uslma-sl5cki · 2026-07-30
**Target:** [add-host-workflow.md](add-host-workflow.md)
**Method:** every code claim in the doc was checked against source. All of them hold (bug 1, bug 2, the fingerprint derivation, the `isTrusted` guard, the `FleetChannel.id` churn). The problems below are things the doc *missed*, plus rulings on the five questions asked.

---

## Verdicts, one line each

1. **Fingerprint step:** not theater — it is the only unforgeable field in the approval alert — but as specified it doesn't work; it needs three conditions or it should be cut to plain copy.
2. **Additive:** correct, and the objection dissolves if the success screen offers "Open Studio" as its primary action.
3. **Five hosts:** the design's change list keeps the fleet roster *discovery-driven*; at five hosts that's the thing that breaks, and Change 1–5 don't fix it. Manual-entry Macs can't survive in the fleet at all.
4. **Waiting state:** pairing legitimately requires proving control of the Mac, but "control" ≠ "standing at it" — a CLI approval path (`lattices companion approve`) covers the couch case with zero new protocol.
5. **Biggest miss:** the doc claims "two small Mac-side notes." False. The Mac's pairing handler **blocks the entire bridge on a serial queue and holds the app's main thread in a modal session** for the whole wait. The design stretches that wait to minutes by intent. This is the finding that changes the design.

---

## F1 — The Mac side is not "two small notes" (blocking)

`LatticesCompanionBridgeServer` handles **every** connection on one serial queue (`LatticesCompanionBridgeServer.swift:13`, `:159`). `route()` calls `handlePairingRequest` synchronously (`:227`), which blocks on a semaphore until the human answers the modal alert (`LatticesCompanionSecurityCoordinator.swift:547-556`), and `runModal()` holds the Mac's **main thread** in a modal session the whole time (`:559-574`).

Consequences, all made worse by the design's own (correct) premise that waiting lasts minutes:

- **The whole bridge freezes while the alert is up.** `/health`, `/deck/snapshot`, `/deck/perform` from *already-trusted* devices stall behind the blocked queue. If any other device is paired to that Mac (an iPhone, a second iPad), its session goes red for the duration of the add.
- **Waiting manufactures "unreachable."** If the add flow (or roster liveness) pings `/health` on the candidate during step 3, that ping hangs — the iPad will read the Mac as unreachable *because* it is waiting. Implementation must use Bonjour presence only during waiting, and the doc should say so.
- **The Mac itself degrades.** Lattices is a window manager; hotkeys, tiling, HUD all live on the main thread. A modal session parked for minutes is a real cost on the machine being added.
- **Unauthenticated DoS.** `/pairing/request` requires no auth. Any LAN device can spam it; each request queues a modal alert *and* wedges the serial queue. The doc hardens the iPad's auto-connect and does nothing about the actual exposed surface. Also: after a **deny**, a queued retry from the iPad immediately raises the *next* alert — denial becomes whack-a-mole if the waiting state ever auto-retries.

**Required Mac-side changes** (this is Change 0, before any iPad work): handle pairing asynchronously off the route path with a pending-approval registry; dedupe concurrent requests per `deviceID` (concurrent requests join one pending decision instead of queueing alerts); rate-limit the endpoint. The bug-1 fix (minutes-long iPad timeout) is *harmful* until this lands — it converts a 10s wedge into a minutes-long one.

## F2 — A second add-path exists and the change list doesn't touch it

The doc says the only manual path is Settings → macsCard. Not true. `HomeDataAdapter.machines` puts **untrusted discovered Macs into the Home roster** with no trust filter (`HomeDataAdapter.swift:30-35`), and tapping one runs `ContentView.prepareConnection` (`ContentView.swift:165-181`), which calls `store.connect(to:)` on the untrusted endpoint — re-pointing the primary *and* firing the pairing prompt. That is exactly the swap-plus-unsolicited-prompt behavior the design exists to kill, one accidental tap away, and no Change 1–5 removes it. The §2 state table says state-1 Macs belong in the Add sheet only; the change list must include: filter untrusted out of `HomeDataAdapter.machines` (or render them as inert "candidate" cards that open the add sheet) and delete the pairing branch of `prepareConnection`.

Same door, different room: Settings "reconnect" presumably remains `store.connect(to:)` — which swaps the primary for a *trusted* Mac too. If reconnect doesn't route through `adopt()`, the swap bug survives in Settings after being fixed everywhere else.

## F3 — Q1: the fingerprint is not theater, but as specced it won't do its job

What the code says: the alert's headline and body are built from `deviceName`, `deviceID`, `platform` — **all attacker-chosen** (`LatticesCompanionSecurityCoordinator.swift:562-571`). An attacker on the LAN can raise "Allow Art's iPad to pair?" that is pixel-identical to the real one *except* the fingerprint, which they cannot forge: replaying the iPad's public key produces a trust record only the real iPad can use, so a matching fingerprint genuinely proves the request came from the device in your hand. The threat it defends is precise and realistic: the user initiates an add, an attacker's request lands at the same moment, the user approves reflexively. With auto-connect killed, *unexpected* prompts become self-evidently suspicious — the fingerprint is the tiebreaker for *expected* ones. That's a real outcome change, in a narrow but load-bearing scenario. Keep it — under three conditions:

1. **The Mac alert must be redesigned** so the fingerprint is the primary element and the forgeable fields are demoted (today it's one line buried between Device ID and Platform in `informativeText`). Without this, "check that it shows this code" points the user at small grey text under a big bold attacker-controlled title. This is a third Mac-side change — the doc's "no Mac change needed" claim is what's theater.
2. **The confirm screen must say what to do on mismatch** ("If the code is different, tap Deny — another device is asking"). A comparison with no failure action is ritual by definition.
3. **Note the limit:** 12 hex = 48 bits, and the fingerprint is `SHA256` of the *base64 string* (`:357-361`) sent in a plaintext POST — an observer can learn the target value and grind ~2^47 keys offline for a colliding prefix. Acceptable for v1; it makes the SAS upgrade path a real item, not a someday. (Also fragile: hashing the encoding rather than key bytes means any future re-encoding silently changes every displayed fingerprint.)

If the team won't fund condition 1, cut the code display and keep only the plain-language line ("Your Mac will ask you to allow this iPad") — an unprominent code teaches users that hex is skippable, which is worse than no code.

## F4 — Q2: additive is right; give intent its one tap

Auto-switching would violate the host-ownership invariant the rest of the app is built on, and it punishes the user who was mid-task on Mac 1. But the counter-argument ("you just spent four screens on Studio") is real and cheaply satisfied: the **approved** state's primary action should be **"Open Studio"** (enter its deck / make it the hot host), secondary "Done" → Home. Intent continues in one tap; nothing is stolen. This also closes §8's first open question without a policy fight.

The deeper smell: the design keeps entrenching the primary/secondary asymmetry (primary owns discovery, Home renders from it, secondaries live in `DeckFleetStore`). At five hosts "primary" is a load-bearing accident — primary goes offline and Home error-states while four healthy Macs sit in the fleet; "forget the primary" is undefined. The end-state model is N peer sessions + a selection pointer + one discovery service owned by nobody. The doc doesn't have to build that now, but it should *name* it, or `adopt()` becomes another buttress on the wrong spine.

## F5 — Q3: what actually breaks at five hosts

- **The roster is discovery-driven and must become trust-driven.** `DeckFleetStore.synchronize` builds the fleet from `primaryStore.discoveredBridges` and **reaps any store not currently discovered** (`DeckStore.swift:535-538`). mDNS at five hosts flaps routinely; every transient disappearance tears down a live session and rebuilds it with a fresh `sessionID`, so `FleetChannel.id` churns (`FleetDeckAdapter.swift:49`) and the deck's channels shuffle. Bug 2 is just the loudest instance of this; fixing `refresh()` while keeping reap-on-absence fixes the symptom and keeps the disease. The fix the doc's own §2 table implies but the change list never states: **trust records are the roster; discovery only annotates address and liveness.**
- **Manual-entry Macs cannot exist in this fleet at all.** A state-4 Mac (Bonjour blocked — the doc's own justification for manual entry) is never in `discoveredBridges`, so `synchronize` reaps it on the next discovery update, forever. Change 1's "don't reap while pairing is in flight" is too weak — adopted stores must survive on trust, permanently. As written, the manual path adds a Mac that evaporates seconds later.
- **Polling doesn't scale as wired.** Deck open → `setUIPriority(.fast)` on *all* stores → five 1 Hz snapshot streams of fat payloads; and `currentPollInterval` pins any Mac with a pending question at 1 Hz even ambient (`DeckStore.swift:383-391`) — five agent-running Macs means several permanent 1 Hz pollers on Home. Each transient failure writes `errorMessage` → red cards flapping. Needs a visibility budget (focused host fast, rest slow). Not add-flow scope, but the add flow is what makes five hosts reachable, so it belongs in the doc as a named follow-up, not silence.
- **Old-build edge:** a trusted Mac whose Bonjour TXT lacks `fp` fails the fingerprint match → shows up as a *candidate* in the add sheet → user re-adds → `alreadyTrusted`. Harmless but confusing; worth one line of copy or a version gate.

## F6 — Q4: pairing must prove control of the Mac, not proximity to it

Approving from the iPad would be self-approval — no. But this is a developer tool: the couch user almost certainly has SSH or screen sharing to that Mac already, and *that is the same trust anchor* (you can run commands on it). The cheap, in-grain escape hatch is a CLI: `lattices companion pending` / `lattices companion approve <fingerprint>` — approve over SSH, fingerprint comparison intact, zero new protocol, and it fixes the fact that a modal NSAlert is invisible over SSH today. Bonus: it survives the alert being unanswerable (locked screen, other Space). Reject the "accept pairings for 10 minutes" pre-auth window — it reopens the exact reflexive-approval hole the fingerprint closes. Also reframe expectations: the natural pairing moment is Mac setup — the user is already there installing Lattices; the empty-state copy already assumes it.

## F7 — Smaller kills

- **Pick-step rows show the Mac's fingerprint** — §5 argues at length that the user has nothing to compare it against; then don't print it. It's noise that trains users to skim hex, which F3 needs them not to do. Name + host is enough; fingerprints live in Settings.
- **"The prompt may be behind another window" is the wrong 25s hint.** The alert code calls `NSApp.activate(ignoringOtherApps: true)` before `runModal` (`:560`) — it fronts itself. The actual stall modes: Mac asleep/locked, alert on another Space, or the queue wedged behind an earlier pairing alert (F1). Copy should say "Make sure the Mac is awake."
- **First-run regression, unowned.** Change 2 means a fresh install shows an empty Home instead of auto-connecting. Right trade, but the doc must own it: on an empty roster the add cell is the hero state, not one cell among none.
- **Cancel/deny race copy.** Serialization on the Mac means a retry sent after a deny raises a fresh alert immediately. The denied state's "Try again" is fine; any *automatic* retry in waiting is not. Say explicitly: waiting never auto-retries.

---

*Verified in code this pass: bug 1 (`DeckBridgeClient.swift:71` vs `:88`), bug 2 (`BridgeDiscovery.swift:21-27` → `ContentView.swift:152-155`), fingerprint derivation match (`LatticesCompanionSecurityCoordinator.swift:357-362` vs alert `:569`), serial bridge queue (`LatticesCompanionBridgeServer.swift:13,159,227`), semaphore/modal blocking (`:542-575`), untrusted-in-roster path (`HomeDataAdapter.swift:30-35`, `ContentView.swift:165-181`), fleet reap (`DeckStore.swift:502-541`), channel-id churn (`FleetDeckAdapter.swift:49`).*
