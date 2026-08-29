# Blink Studio

Design studio for **Blink** across macOS and iOS. Spatial panel, menubar, and
command studies live beside controlled companion-app comparisons and the
product's source documents.

Built on the shared [`studio`](https://github.com/arach/studio) primitives,
consumed via the studio repo's Bun workspace—the same shared shell and registry
model used by Hudson and OpenScout, without copying their project-specific
navigation.

## Run

```sh
# install once, from the shared studio workspace root
cd ~/dev/studio && bun install

# then
cd ~/dev/blink/design/studio
bun dev        # → http://localhost:3060/studio
```

## Layout

- `src/studio/studioRegistry.ts` — taxonomy (foundations / plans / studies) + pages
- `src/studio/studies/` — live macOS and iOS UI studies
- `src/studio/studies/IOSDesignDirectionsStudy.tsx` — controlled Opus / Grok / Kimi iOS comparison + Index Tape synthesis
- `specs/` — agent-authored design directions retained as source material
- `app/api/docs/` — serves `blink/docs/*.md` so plan pages render the real files
- `.studio/annotations/` — sidecars written by in-browser annotations (pins, dictation); terminal agents read these back
