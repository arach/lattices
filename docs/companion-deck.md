# Companion Deck

This document defines the first extraction boundary for the Lattices
companion deck work.

## Goals

- Build the deck architecture in `lattices` first, without modifying
  `talkie`.
- Treat `talkie` as the donor and reference implementation, not the
  place where the first shared abstraction is born.
- Let `lattices` own Mac functionality.
- Let `talkie` continue to own Talkie-specific flows.
- Keep the transport and UI shell generic enough that both products can
  embed the same deck later.

## Product Ownership

### Lattices owns

- Voice agent control
- Layout and screen state
- Application, window, tab, and task switching
- Session and layer switching
- Desktop questions and agent follow-up
- Action history and undo-oriented playback

### Talkie owns

- Dictation
- Memo recording
- Scratchpad and compose flows
- Capture-specific flows
- Talkie-branded deck pages and follow-up actions

### Shared deck kit owns

- Page model
- Action model
- Runtime snapshot model
- Security mode model
- App and task switcher model
- History feed model
- Generic host protocol

## Security Modes

The deck must support two security modes.

### Standalone

Used by a future standalone `Lattices Companion`.

- Bonjour discovery
- Local network only
- No Tailscale or external relay dependency
- QR or code-based pairing on top of the local network path
- Per-device keypairs
- Signed requests with nonce and timestamp protection
- Local companion gateway with a reduced action surface

### Embedded

Used when the deck is embedded inside `talkie`.

- Pairing, trust, transport, and signing are delegated to Talkie
- Lattices focuses only on local functionality and state
- The Lattices deck host does not need to own remote security in this mode

## First Lattices Companion Scope

The first iPad/iPhone companion for Lattices should focus on these pages:

1. Voice
2. Layout
3. Switch
4. History

These pages cover the highest-value mobile control loops without pulling
Talkie-specific concepts into the new product.

## Module Plan

### `swift/DeckKit`

Cross-product contract incubated in the Lattices repo first.

- Shared deck schema
- Security mode model
- Runtime snapshot model
- Host protocol

### `LatticesDeckHost`

Mac-side adapter owned by Lattices.

- Publishes deck pages and runtime state
- Maps deck actions to the existing Lattices desktop APIs
- Uses the existing desktop model, layout engine, switcher logic, and
  voice agent surfaces

### `Lattices Companion`

Future iOS or iPadOS app that consumes `DeckKit` and the Lattices
companion gateway.

### `TalkieDeckHost`

Future Talkie-side adapter that adds Talkie-only pages on top of the
shared deck shell.

## Current Lattices Milestone

The first host-side integration now lives in the Lattices macOS app.

- `swift/DeckKit` continues to own the shared manifest, snapshot,
  action, and security contract.
- `app/Sources/LatticesDeckHost.swift` is the first concrete Mac host.
- The menu bar app daemon now exposes:
  - `deck.manifest`
  - `deck.snapshot`
  - `deck.perform`

That gives the future iPhone/iPad companion a stable local contract
before transport and pairing are finalized.

The current transport now runs as a local network bridge in the macOS
app with Bonjour discovery on port `5287` (`LATS` on a phone keypad).
Standalone mode now uses:

- local Mac approval for first-time device pairing
- per-device key agreement
- signed requests with nonce and timestamp checks
- encrypted deck payloads for snapshots, actions, and trackpad events
- pairing-time capability grants, enforced again on every protected route

The bridge still keeps `/health`, `/deck/manifest`, and pairing
bootstrap lightweight so a new companion can connect and establish trust
without an external relay or Tailscale dependency.

## Reference Security Pattern

The standalone bridge is the reference pattern we should share back to
Talkie and Scout:

1. Bonjour is discovery only. The TXT record exposes protocol version,
   fingerprint, security mode, and coarse capabilities, but no project
   names, sessions, commands, or tokens.
2. Local-network control is opt-in. The bridge is disabled by default;
   users enable it from Companion settings or the local
   `lattices://companion/enable` deep link.
3. Pairing is explicit Mac approval. A cryptographic handshake or public
   key exchange proves key possession; it does not automatically grant
   control.
4. Trust is scoped. Pairing records store granted capabilities such as
   `deck.read`, `deck.perform`, and `input.trackpad`.
5. Every protected request is signed with a timestamp and nonce, then
   checked for replay before the route runs.
6. Sensitive payloads are encrypted with per-device key agreement and
   route-bound additional authenticated data.
7. Authorization happens after authentication. A trusted device still
   needs the route's required capability before it can read state,
   perform actions, or proxy input.

That gives the family of apps one ergonomic model: discover nearby,
pair once, reconnect quietly, and keep control surfaces capability
scoped.

## Initial Action Surface

The first deck action IDs are intentionally small and map to existing
desktop behavior:

- `voice.toggle`
- `voice.cancel`
- `layout.activateLayer`
- `layout.optimize`
- `layout.placeFrontmost`
- `switch.focusItem`
- `history.undoLast`

This keeps the first bridge focused on real Mac control loops instead
of inventing a second execution stack.

## Rollout Sequence

1. Leave Talkie untouched and use it as the donor reference.
2. Incubate `DeckKit` in `lattices`.
3. Build a clean Lattices companion around `Voice`, `Layout`,
   `Switch`, and `History`.
4. Prove standalone local pairing and strong security for Lattices.
5. Harden the deck contract.
6. Retrofit the stabilized deck kit back into Talkie.

Embedded mode remains a first-class constraint throughout the rollout.
The standalone bridge must not leak into the shared deck contract in a
way that would make Talkie embedding awkward later.

## Vox

Vox is the preferred voice dependency for the Lattices companion path.

- Prefer direct embedding through `VoxCore` and `VoxEngine` for
  in-process ASR and TTS inside Apple apps.
- Keep `VoxBridge` available as an optional daemon-style path when a
  shared runtime is more appropriate than direct embedding.
- Keep the first contract in `DeckKit` voice-agnostic.
- Let `LatticesDeckHost` decide whether voice is served by embedded Vox
  or another local service surface.
