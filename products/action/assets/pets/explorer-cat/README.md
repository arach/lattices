# Explorer Cat Pet Pack

Initial Action desktop-pet asset pack built from the generated explorer-cat
mascot.

Runtime files:

- `pet.json`
- `sprites/explorer-cat.sheet.webp`

Source/debug files:

- `source/explorer-cat.reference.chromakey.png`
- `source/explorer-cat.reference.alpha.png`
- `source/explorer-cat.generated-4frame.chromakey.png`
- `source/explorer-cat.generated-4frame.alpha.png`
- `sprites/explorer-cat.sheet.png`
- `sprites/explorer-cat.v0.frames.png`
- `masks/alpha-debug.png`
- `explorer-cat.preview.gif`

This v0 sheet uses a stable row-per-state contract with 192x208 cells. It is
good enough to wire a renderer and prove the desktop-pet loop, but it still uses
repeated frames in several rows. Future art passes should replace those rows
with hand-cleaned animation frames while preserving the same `pet.json` shape.
