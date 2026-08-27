# Action landing materials

This set turns the recent visual references into a coherent landing-page system for Action: warm technical paper, graphite machinery, coral recording nodes, restrained cyan signals, and Mira as a field companion rather than a mascot pasted on top.

## Assets

### `landing-hero-observe-act-record.png`

Canonical hero art for the main landing page. Use it as a full-bleed visual with copy over the quiet left side. Keep the application window and the recording rings visible on desktop. On mobile, crop around the app window and companion rather than centering the whole image. Do not reuse it deeper in the page; letting it belong to the opening gives the site a clear signature.

Suggested copy:

- Eyebrow: `NATIVE MACOS AUTOMATION`
- Headline: `Action gives agents an API to record and share their work.`
- Body: `Each macOS run can include video, screenshots, accessibility context, and traces.`
- Primary CTA: `Build Action.app`
- Secondary CTA: `Watch the capture`

### `landing-trace-field.png`

Modular section or page art. It is designed to hold HTML content in the center, with the visual system concentrated at the edges. On the main long-form landing page, use it behind the four runtime primitives or the session-artifact story. It can also lead a dedicated runtime, inspection, or architecture page.

Suggested center sequence:

1. Observe the surface.
2. Resolve a stable target.
3. Act through native controls.
4. Record the result and trace.

### `landing-mira-field-companion.png`

Modular feature or page art for Mira and the inspection workflow. On the main long-form landing page, use it in a two-column section with copy on the left and the art on the right. It can also become the lead visual for a dedicated Mira, inspection, or guided-capture page. Mira should be framed as a compact operator companion who watches the runtime, not as the product itself.

Suggested copy:

- Eyebrow: `FIELD COMPANION`
- Headline: `A second set of eyes on every take.`
- Body: `Mira follows the session, surfaces what changed, and helps turn raw capture into an inspectable handoff.`

## Visual system

Each illustration is available as a lossless PNG source and a compressed WebP for the site. Prefer WebP in production and retain PNG for future crops or export work.

| Asset | PNG | WebP |
| --- | ---: | ---: |
| Hero | `landing-hero-observe-act-record.png` | `landing-hero-observe-act-record.webp` |
| Trace field | `landing-trace-field.png` | `landing-trace-field.webp` |
| Mira | `landing-mira-field-companion.png` | `landing-mira-field-companion.webp` |

Use the existing typography already loaded by `docs/index.html`:

- Editorial display and body: EB Garamond
- Controls, labels, paths, and metadata: JetBrains Mono

Core palette:

- Paper: `#F3EBDD`
- Paper shadow: `#DCCFB9`
- Graphite: `#20282B`
- Slate: `#596261`
- Coral: `#EF6A47`
- Signal cyan: `#1FB9C6`
- Field tan: `#A77850`

Coral is the runtime-truth color: recording state, selected trace event, current target, or primary CTA. Cyan is a small secondary signal and should never compete with coral.

## Recommended page order

1. Hero: headline, two CTAs, hero illustration.
2. Proof rail: `AppKit lifecycle / ScreenCaptureKit / AX + OCR / CLI + MCP`.
3. Real demo: keep the existing Mira logo capture video near the top.
4. Runtime loop: place four short steps over `landing-trace-field.png`.
5. Durable output: show the session artifact contract - video, screenshot, AX snapshot, trace, manifest.
6. Mira: use `landing-mira-field-companion.png` as a warm character break.
7. Developer close: three commands, platform requirements, GitHub link.

## Layout notes

- Use warm paper as the main page canvas. Reserve dark graphite panels for the app, terminal, and artifact previews.
- Keep real copy in HTML. None of the images should contain text.
- Let drafting lines cross section boundaries sparingly so the page feels like one system.
- Use square corners with small chamfers or 6-10px radii; avoid soft generic SaaS cards.
- Grain should come from the artwork, not a noisy CSS texture over every element.
- Keep generous negative space. The technical detail works because it has room to breathe.

## Generation record

The assets were created with the built-in image-generation workflow using the three relevant recent downloads as references. The business statement PDF and Bing verification XML file were intentionally excluded.

### Hero prompt

Original wide editorial illustration of a native Mac capture workstation, nested recording rings, crop marks, trace paths, timeline rails, and a small field-companion silhouette. Warm ivory, graphite, slate, coral, and minimal cyan. Quiet left 38 percent for copy. No text, logos, phone, browser chrome, glossy 3D, or photorealism.

### Trace-field prompt

Restrained panoramic technical field diagram representing observe, act, record, and review through concentric arcs, coral nodes, sparse rails, crop corners, graphite blocks, and trace paths. Quiet central 55 percent for HTML content. No literal device, screen, character, text, or border.

### Mira prompt

Editorial technical-manual reinterpretation of the downloaded cat field engineer beside a compact capture console. Preserve the cat silhouette, goggles, scarf, compact proportions, and curious personality while translating realistic materials into ink, paper, and flat geometric shading. No text, logo, photorealism, fantasy scene, or extra characters.
