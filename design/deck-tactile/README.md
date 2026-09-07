# Deck tactile catalog

Declarative sound + haptic definitions for the Lattices SYS.01 deck controller.

## Canonical file

`swift/Sources/DeckKit/Resources/deck-tactile-catalog.json`

Copies are kept in sync for web consumption:

- `apps/site/src/lib/deck-tactile/catalog.json`
- `design/deck-tactile/catalog.json`

## Schema

- **`sounds`**: named synthesis patches (oscillator + noise layers, envelopes, filters)
- **`events`**: semantic bindings (`deck.key`, `deck.rotary`, …) → sound patch + haptic style

### Extensibility

1. **New sounds** — add a patch under `sounds`, reference it from an `events` entry
2. **Runtime params** — pass `id`, `accent`, etc. when firing an event; frequency detune uses `{ "base": 320, "detune": { "param": "id", "step": 20, "modulo": 3 } }`
3. **Theme overlays** — merge JSON at runtime:
   - iOS: `DeckTactileFeedback.shared.mergeTheme(from: url)`
   - Web: `theme.merge(overlayCatalog)`
   - Swift: `DeckTactileTheme.shared.merge(overlay)`

## Markup

### SwiftUI

```swift
Button("Approve") { approve() }
  .deckTactile(.deckDecisionApproved)

Button { } label: { Keycap() }
  .buttonStyle(FleetPressStyle(event: .deckKeyAccent, params: ["id": .int(3)]))
```

### React

```tsx
const { play } = useDeckTactile(soundEnabled)
// ...
onClick={() => play('deck.key.accent', { id: win.id })}
```

Or `data-deck-tactile="deck.button"` with a small attribute handler (hook exports `theme.resolve`).
