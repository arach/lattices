# Blink v2 Editor Surface

A vanilla [CodeMirror 6](https://codemirror.net/) markdown editor **plus a
rendered read mode**, built to a single self-contained `dist/editor.html` and
hosted inside a native macOS NSPanel via `WKWebView`. By default the page paints
no surface of its own — the native glass panel behind the web view provides the
background, blur, and shadow. A reusable treatment may opt into an exact sheet
canvas with `--blink-sheet-bg`; every editor/reader content layer remains
transparent over it.

Two surfaces flip **in place** on the same glass:

- **edit** — the CM6 markdown editor (single `EditorView`, always alive).
- **read** — the current note rendered as markdown typography in `.blink-reader`
  via [`marked`](https://marked.js.org/) (GFM on).

Flipping hides one surface and shows the other; the `EditorView` is never
destroyed. Scroll position is preserved proportionally between surfaces (best
effort). Initial mode is **edit**.

## Build

```bash
bun install
bun run typecheck   # tsc --noEmit, must be clean
bun run build       # esbuild -> dist/editor.html (single file, guardrailed)
```

`bun run build` bundles `src/main.ts` (iife, minified) and inlines it into
`dist/editor.html` alongside the page/reader CSS. Guardrails reject any external
`<script src>` / `<link href>`, an oversized output (> 1.5 MB), and a missing
read-mode surface (`#reader` element, `.blink-reader` styles, empty-note
placeholder).

## Native bridge contract

Two directions. `JS -> native` posts to the WKWebView message handler; when that
handler is absent (plain browser during dev) posting is a harmless no-op that
logs to the console.

### native -> JS: `window.blink`

| Method | Signature | Behavior |
| --- | --- | --- |
| `setContent` | `(text: string) => void` | Replace the whole document. Dispatches with **no** user event, so it never echoes `contentChanged` (the v1 stale-feedback bug). Preserves scroll; places caret at end only on the first set. Re-renders the reader if currently in read mode. |
| `getContent` | `() => string` | Current document text. |
| `focus` | `() => void` | Focus the editor. |
| `setMode` | `(mode: "edit" \| "read") => void` | **Programmatic** flip. Does **not** post `modeChanged` (native is the source of truth — same no-echo discipline as `setContent`). |
| `getMode` | `() => "edit" \| "read"` | Current surface. |
| `setTheme` | `(vars: Record<string, string>) => void` | Apply theme overrides. For each entry, `document.documentElement.style.setProperty(key, value)` — keys arrive as **full** var names (e.g. `"--blink-font-size": "14px"`). Unknown keys are set anyway (harmless). Calling with `{}` is a no-op. No echo message. |
| `resetTheme` | `() => void` | Remove all inline `--blink-*` properties from `:root`, restoring the stylesheet defaults. No echo message. |
| `setSheet` | `(name: string) => void` | Select the sheet template — the note's whole visual identity (see **Sheet templates** below). Sets `data-sheet` on `<body>`. **Idempotent**; unknown names fall back to `"glass"`. No echo message (same no-echo discipline as `setContent`/`setMode`/`setTheme`). |
| `enter` | `(kind: string, durationMs: number) => void` | Play a content entrance effect (see **Entrances** below): `"shimmer"` \| `"drop"` \| `"draw"` \| `"none"`. Sets a transient `data-enter` on `<body>` that the CSS animates, self-clearing after the run. Unknown kinds and `"none"` are instant no-ops. No echo message. |
| `typeOn` | `(base: string, suffix: string, source?: string \| null) => void` | Install `base + suffix` as the complete document immediately, then reveal only `suffix` at ~180 characters/sec with a blinking caret. **Never** echoes `contentChanged`. `source` shows `✳ source · just now` during the reveal and for four seconds after. A new call snaps and supersedes the old reveal. |
| `finishTypeOn` | `() => void` | Snap an in-flight typed reveal to the already-installed complete document. Silent and idempotent. Real user edits invoke this before their `contentChanged` message is posted. |

### JS -> native: `postMessage`

| Message | Shape | Posted when |
| --- | --- | --- |
| `ready` | `{ type: "ready" }` | Editor mounted and focused. |
| `contentChanged` | `{ type: "contentChanged"; text }` | **User** edits only (never programmatic `setContent`). |
| `saveRequested` | `{ type: "saveRequested" }` | User presses ⌘S / Ctrl-S. |
| `modeChanged` | `{ type: "modeChanged"; mode }` | **User-initiated** flip only: double-click on the reader, or ⌘⇧P (Mod-Shift-p) in either mode. Programmatic `setMode` is silent. |

## Theming

Every visual value in **both** the CM6 editor theme (`src/theme.ts`) and the
reader typography (`build.mjs` `PAGE_CSS`) resolves to a CSS custom property
declared on `:root` in the bundled stylesheet. Defaults equal the original
hard-coded values. Native code overrides them at runtime via
`window.blink.setTheme({...})` (full var names as keys) and clears overrides via
`window.blink.resetTheme()`.

| Variable | Default | Controls |
| --- | --- | --- |
| `--blink-font-family` | `-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif` | Body/UI font (editor + reader). |
| `--blink-mono-family` | `ui-monospace, "SF Mono", SFMono-Regular, Menlo, Monaco, "Cascadia Code", monospace` | Monospace font (inline + block code). |
| `--blink-title-family` | `var(--blink-font-family)` | Heading/title font in editor and reader. |
| `--blink-font-size` | `13px` | Base text size (editor, reader, marker reset, empty placeholder). |
| `--blink-line-height` | `1.75` | Base line height (editor scroller + reader). |
| `--blink-pad-x` | `20px` | Horizontal content padding (editor + reader + placeholder). |
| `--blink-pad-y` | `16px` | Vertical content padding (editor + reader + placeholder). |
| `--blink-sheet-bg` | `transparent` | Optional exact sheet canvas; transparent preserves native glass. |
| `--blink-text` | `rgba(255,255,255,0.85)` | Body text; also editor emphasis (`em`). |
| `--blink-text-strong` | `rgba(255,255,255,0.96)` | Headings, `strong`, table headers. |
| `--blink-text-muted` | `rgba(255,255,255,0.45)` | List content + markers, `del`/strikethrough, gutter. |
| `--blink-marker` | `rgba(255,255,255,0.35)` | Markdown formatting markers (`#`, `*`, `` ` ``, `>`, brackets); empty placeholder. |
| `--blink-accent` | `rgba(158,203,255,0.9)` | Link text. |
| `--blink-accent-dim` | `rgba(158,203,255,0.55)` | Link URL/target (editor source view). |
| `--blink-code-bg` | `rgba(255,255,255,0.07)` | Code chip / block background. |
| `--blink-code-text` | `rgba(255,255,255,0.8)` | Code text (inline + block). |
| `--blink-caret` | `#ffffff` | Text caret / cursor. |
| `--blink-selection` | `rgba(255,255,255,0.18)` | Editor and reader selection highlight (+ selection match); light mode supplies a stronger blue wash. |
| `--blink-h1-size` | `20px` | H1 size (reader). Editor derives `calc(… - 3px)` → 17px. |
| `--blink-h2-size` | `17px` | H2 size (reader). Editor derives `calc(… - 3px)` → 14px. |
| `--blink-h3-size` | `15px` | H3–H6 size (reader). Editor derives `calc(… - 3px)` → 12px. |
| `--blink-quote-text` | `rgba(255,255,255,0.65)` | Blockquote text. |
| `--blink-quote-border` | `rgba(255,255,255,0.2)` | Blockquote left border. |
| `--blink-rule` | `rgba(255,255,255,0.15)` | Horizontal rule + table cell borders. |

Heading sizes use **one** set of variables: `--blink-hN-size` are the **reader**
sizes; the editor (which renders markdown *source*) derives its heading sizes as
`calc(var(--blink-hN-size) - 3px)`. Font weights are hard-coded (not themable
this pass).

The build guardrails statically verify the `:root` block declares all of these
variables, that no raw accent literal (`rgba(158,203,255,…)`) survives outside
those defaults, and that `setTheme`/`resetTheme` exist in the bundle.

## Sheet templates

A note's whole visual identity is a **sheet**, drawn by the web layer. The
native panel is an invisible carrier. A sheet is selected via `data-sheet` on
`<body>` (set by `window.blink.setSheet(name)`, or configured natively from the
`panel.sheet` config field / a per-note `sheet:` frontmatter key). The per-sheet
CSS lives in `build.mjs` `PAGE_CSS`, keyed off that attribute; `src/sheet.ts`
owns the name set and the idempotent, validated DOM write.

| Sheet | Surface | Look |
| --- | --- | --- |
| `glass` | native glass ON | The default — transparent editor over the native glass panel. **Byte-for-byte the original look**; zero visual change for existing users. |
| `card` | native glass ON | An index card: near-opaque warm dark paper (`--blink-card-bg`, `#1c1917`) with a subtle asset-free grain, printed-feeling serif reader type (`--blink-card-serif`, Charter/Georgia), generous padding. |
| `dotted` | **flat** (glass OFF) | A cut-out: transparent page, a 1.5px dotted outline inset ~4px with ~8px radius, ink text. |
| `bracket` | **flat** (glass OFF) | Architect's framing: transparent, four corner brackets (~18px arms, 2px stroke); text floats free. |
| `marginalia` | **flat** (glass OFF) | Barest: transparent, a single 2px vertical rule down the left edge; text hangs off it. |

Both surfaces (editor **and** reader) honor the sheet — writing on a dotted
cut-out looks the same as reading one.

### Legibility floor (flat sheets)

The three **flat** sheets (`dotted`/`bracket`/`marginalia`) put ink directly on
the user's wallpaper, which can be any color. So every flat sheet's text carries
a dark halo, exposed as a themable CSS var:

```
--blink-halo: 0 0 1px rgba(0,0,0,.9), 0 1px 2px rgba(0,0,0,.7), 0 0 12px rgba(0,0,0,.45);
```

White ink + this halo must survive a **white** wallpaper. The frame chrome
(dotted outline / corner brackets / margin rule) additionally gets a faint dark
`drop-shadow` beneath it for the same reason. All existing `--blink-*` vars keep
working inside every sheet; `--blink-frame` tints the flat-sheet chrome.

The build guardrails verify each non-glass sheet has a `data-sheet` CSS block,
that the flat-sheet halo (`var(--blink-halo)`) is present, and that
`setSheet` exists in the bundle.

## Entrances (Arrival)

Notes don't appear — they land. The **native** panel animates its own window
(alpha `0→1`, and for `drop` a downward frame drift with a spring settle); this
web layer choreographs the **content**, keyed off a transient
`body[data-enter="<kind>"]` attribute set by `window.blink.enter(kind, ms)` and
cleared after the run. `--blink-enter-ms` carries the configured base duration.

| Kind | Content choreography |
| --- | --- |
| `shimmer` | The type layers fade up from 0 while a soft highlight sweep (a `body::after` overlay) crosses the sheet left→right. |
| `drop` | The type layers fade in; the window's scale/drift/settle is the native half. |
| `draw` | **Flat sheets only:** the frame chrome (`body::before` — dotted outline / brackets / margin rule) strokes itself on via a left→right clip wipe, then the text fades in behind it. On `glass`/`card` the native side substitutes `shimmer` (there's no frame to draw). |
| `none` | Instant — no `data-enter`, no animation. |

Only the content type layers and (for `draw`) the flat-sheet frame are touched —
never geometry. With no `data-enter` present the page is in its resting,
fully-visible state, so a disabled entrance / **Reduce Motion** / `"none"` looks
exactly like today. A `@media (prefers-reduced-motion: reduce)` rule additionally
disables the animations web-side even if a `data-enter` slips through.

The build guardrails verify each entrance (`shimmer`/`drop`/`draw`) has a
`data-enter` CSS block, that the `@keyframes blink-enter-*` exist, and that the
entrance runtime (`data-enter` + `--blink-enter-ms`) is in the bundle.

## Typed external appends (Visible Hand)

`window.blink.typeOn(base, suffix, source)` treats animation as garnish over
already-applied state: CodeMirror receives the complete `base + suffix` in a
programmatic, non-user transaction on frame zero. A state-field decoration
replaces only the unrevealed tail with a blinking caret, advancing by grapheme
at roughly 180 characters/sec. Thus `getContent()` is always complete, and a
user edit cannot race a partial document. If the old selection was exactly at
the append point, its real (temporarily hidden) caret moves after the full
suffix so a mid-reveal keystroke follows the append in order.

Read mode keeps the rendered markdown base in place and types the suffix into
a lightweight plain-text overlay; completion performs one full markdown
render. A real user edit, a non-append `setContent`, or another `typeOn` snaps
the old reveal instantly. All reveal dispatches have no user event and never
post `contentChanged`.

When `source` is non-empty, a pointer-inert bottom-left attribution chip reads
`✳ <source> · just now`; it remains for four seconds after the reveal ends.
The build guardrails require the typed-reveal runtime/styles and chip mount.

## Read mode interactions

- **Double-click** anywhere on the reader → switch to edit and focus the editor
  (posts `modeChanged`).
- **⌘⇧P** (Mod-Shift-p) → toggle mode in **both** directions. In edit mode this is
  a CM keymap entry; in read mode a window `keydown` listener (guarded to fire
  only when read is visible) handles it. Both `preventDefault`.

## Security note

`marked` does **not** sanitize raw HTML — any HTML embedded in the markdown is
rendered as-is. This is an accepted tradeoff: read mode only ever renders the
user's **own local notes** (no remote or third-party content reaches this
surface), so no sanitizer dependency is pulled in. If this surface is ever
repurposed to render untrusted content, add DOMPurify (or equivalent) first.
