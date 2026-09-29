# SEO audit

Crawler view of `apps/site/dist` after `bun run build` on 2026-09-29. No JavaScript. Origin is `https://lattices.dev` (`public/CNAME`, the canonical in `index.html`, and `SITE_URL` in `scripts/export-static.mjs`).

`robots.txt` allows all crawlers and points at `https://lattices.dev/sitemap.xml`. `sitemap.xml` is generated at build with that origin. It lists the home page, product pages, `/action/agents`, `/blink/agents.md`, `/blog`, each published post, and each `/docs/<slug>` page. It omits `/docs`, the `/docs/blog` aliases, and the noindex download URLs. `og.png`, `og-docs.png`, `og-action.png`, `og-blink.png`, and `og-speech.png` are real files. `og-api.png`, `og-cli.png`, and `og-site.png` are in `dist` and unused. No page has JSON-LD. Draft post `lats-dev-ipad-companion` is correctly omitted.

| Route | What a crawler gets |
| --- | --- |
| `/` | Title, description, canonical `https://lattices.dev/`, and OG/Twitter tags are unique and `og.png` exists. `#root` is empty: no `h1`, no body text. No JSON-LD. |
| `/experiment`, `/concept` | Not exported. GitHub Pages serves `404.html`. The SPA knows both paths. |
| `/action`, `/blink`, `/speech`, `/products`, `/family`, `/brand` | Unique title, description, canonical, and OG/Twitter. Image file exists. One `h1`. Prerendered body text. No JSON-LD. |
| `/blog`, `/blog/<slug>` | Same as the product pages. Descriptions come from post front matter. No JSON-LD. |
| `/docs/blog`, `/docs/blog/<slug>` | Same HTML as `/blog` and each post, with a different canonical (`https://lattices.dev/docs/blog/...`). Duplicate. Not in the sitemap. |
| `/docs` | Title `Docs — Lattices`, description `Lattices documentation`, `h1` `Overview`. Body duplicates `/docs/overview`. Not in the sitemap. No JSON-LD. |
| `/docs/overview` | Description is the short front matter line `What lattices is and who it's for`. One `h1`. No JSON-LD. |
| `/docs/agents`, `/docs/api`, `/docs/app`, `/docs/assistant-knowledge`, `/docs/concepts`, `/docs/config`, `/docs/embedded-sdk`, `/docs/layers`, `/docs/ocr`, `/docs/quickstart`, `/docs/release`, `/docs/voice`, `/docs/workspace-map` | Unique front matter descriptions. One `h1` except `/docs/mouse-gestures` (listed below). All use `og-docs.png`, including the API and CLI pages that already have `og-api.png` and `og-cli.png`. No JSON-LD. |
| `/docs/mouse-gestures` | Two `h1`s, both `Mouse Gestures` (page header plus the markdown heading). |
| `/docs/agent-execution-plan`, `/docs/agent-layer-guide`, `/docs/ai-chat-ux-review`, `/docs/companion-deck`, `/docs/companion-deck-builder-spec`, `/docs/component-extraction-roadmap`, `/docs/gesture-customization-proposal`, `/docs/handsoff-test-scenarios`, `/docs/hudson-overlay-alignment`, `/docs/hudson-overlay-next-steps`, `/docs/hyperspace-grid-snappiness`, `/docs/mcp`, `/docs/pi-lattices`, `/docs/presentation-execution-review`, `/docs/repo-structure`, `/docs/terminal-kit`, `/docs/tiling-reference`, `/docs/voice-command-protocol`, `/docs/voice-error-model` | Description is the shared fallback `Lattices documentation`. Two `h1`s (slug title plus the markdown title). `/docs/ai-chat-ux-review` has three. No JSON-LD. |
| `/action/agents` | Prerendered, with its own title and description. Canonical and `og:url` use a trailing slash; the sitemap entry does not. Twitter card is set, but `twitter:title`, `twitter:description`, and `twitter:image` are missing. No JSON-LD. |
| `/action/download`, `/blink/download` | `noindex`. No description, no `h1`. Not in the sitemap. |
| `/404.html` | Own title, description, and `h1`, with real suggestion links. Canonical, `og:url`, and OG/Twitter title and description are still the homepage. No `noindex`. |
| `/blink/agents.md` | Markdown file. In the sitemap. No HTML head. |

Image `alt` attributes are present on exported `<img>` tags (decorative images use an empty `alt`). The homepage download control is an icon with `aria-label="Download Lattices for macOS"`. No `click here` / `read more` links in the React pages. Pagefind indexes 47 pages and skips HTML without `data-pagefind-body` (home and product pages).
