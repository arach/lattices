# design

Where Action gets designed. Three pieces, one source of truth.

| Path | What it is |
| --- | --- |
| `tokens/action.css` | Action's palette and type scale for the web, transcribed from `native/engine/Sources/ActionThemeBuiltin.swift` and `ActionTypography.swift`. Nothing generates it — when a value changes in Swift, change it here. |
| `studio/` | The studio. A Next.js app on the shared `studio` package: every design study lives here, beside the code it argues about. This is the central place. |
| `kit/` | The component previews pushed to the **Action — Design System** project in Claude Design. `bun design/kit/build.ts` inlines the tokens and writes `kit/dist`. |

## Running the studio

```bash
cd design/studio
bun dev              # http://localhost:3070/studio
```

Or register it with the shared local edge from `~/dev/studio`:
`bun run local ensure ~/dev/action/design/studio` → `http://action.studio.local`.

## Adding a study

1. Add an entry to `studio/src/studio/studioRegistry.ts` — `href`, `label`, `bucket`,
   `status`, `blurb`, and the `source` files it argues about.
2. Write the component in `studio/src/studio/studies/`, wrapped in `StudyShell`.
3. Route it in `studio/src/studio/StudioPages.tsx`.

Draw the app's own surfaces with the primitives in `studio/src/studio/action/Surface.tsx`
rather than re-deriving geometry: the column widths, the row tints and the button states
are stated once, in the tokens, in the same numbers the Swift uses.

## The window study

`studio/src/studio/studies/AppStudy.tsx` is the master study: the whole launcher at true
pixel geometry (1100 / 1240 / 1600 wide), navigable across all five sections, with the rail
collapse live in its own title bar. `action/Window.tsx` is the chrome, `action/sections/*`
are the pages, `action/fixtures.ts` is the populated app.

Judge a change here before judging it anywhere else. A surface drawn alone on a white page
is how a heading ends up right at 760px and wrong in the window it ships in.

## The one rule

**A study marked `SHIPPED` draws only what the app actually records.** Anything that needs
data the runtime does not write yet is a separate study marked `CONCEPT` — see
*Step telemetry*. A studio that mocks telemetry it does not have stops describing the app
and starts wishing at it, and then nobody can trust any page in it.

## Pushing the design system

```bash
bun design/kit/build.ts
```

Then sync `design/kit/dist` to the Claude Design project (`Action — Design System`,
`2a1f6099-6ff2-49d8-9854-c777afa78b69`). Cards carry their group and title in the
first-line `@dsCard` marker, so the Design System pane indexes them without registration.
