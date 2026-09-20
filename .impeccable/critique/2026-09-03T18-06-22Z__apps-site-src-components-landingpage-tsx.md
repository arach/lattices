---
target: landing
total_score: 24
max_score: 32
na_heuristics: 7,9
p0_count: 0
p1_count: 2
timestamp: 2026-09-03T18-06-22Z
slug: apps-site-src-components-landingpage-tsx
---
## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Desktop state pill, live driver indicator ("you" vs "agent"), and tab indicators provide clear system feedback; minor gaps in feedback during video hover. |
| 2 | Match System / Real World | 4 | Fluent Mac-native vernacular (⌃⌥G, Caps Lock Hyper, .lattices.json, tmux, Apple Silicon dmg). |
| 3 | User Control and Freedom | 3 | Interactive toggles for 1/2/3 pane layouts and "Without/With Lattices", though hero auto-play can feel runaway on desktop. |
| 4 | Consistency and Standards | 3 | Cohesive dark-chassis surface language, though CTA styles and button padding diverge between hero and install chooser. |
| 5 | Error Prevention | 3 | Clear "Apple Silicon · .dmg" architecture tagging avoids wrong downloads; explicit macOS-only positioning. |
| 6 | Recognition Rather Than Recall | 3 | Visual diagrams of pane layouts, key chord visualizer, and keyboard-plus-gesture comparison table. |
| 7 | Flexibility and Efficiency | n/a | Persuade mode (landing page): visitors evaluate value propositions rather than execute repetitive expert workflows. |
| 8 | Aesthetic and Minimalist Design | 2 | Content inflation: page dilutes core identity by pitching Lattices, Action, and Lats.dev while repeating window manager copy 3 times. |
| 9 | Error Recovery | n/a | Persuade mode (landing page): purely static informational presentation with no destructive actions or transaction forms. |
| 10 | Help and Documentation | 3 | Prominent links to Overview, Quickstart, API Reference, and GitHub. |
| **Total** | | **24/32** | **Good (75%)** |

## Design Specificity Verdict

**Authored Core vs. Category-Interchangeable Bloat**

- **LLM Assessment**: Lattices has an unmistakably authentic hardware/software aesthetic: the tactile 3×3 matrix logo, the retro-modern plinth with the blinking pixel cat mascot, the simulated macOS Terminal/Vite desktop, and the dual-operator paradigm (human keycasts alternating with agent WebSocket toolcalls). However, the page loses this sharp conviction in its midsection. It succumbs to generic AI tooling clichés: repetitive "kicker chips" above every heading, three-column feature cards with numbers (`01 Window manager`, `02 Computer use`, `03 Collaboration`), and a full sub-product detour into "Action" that distracts from Lattices' own identity.
- **Deterministic Scan**:
  - Raw AST JSX scan (`LandingPage.tsx`): **0 errors**.
  - Live DOM overlay scan: **84 anti-patterns flagged** across 14 rules:
    - `undersized-ui-text`: 34 instances of text < 11px (badges, kickers, transport labels at 9px–10.5px).
    - `low-contrast`: 13 instances failing WCAG AA (e.g. 3.4:1 on `#1a9d52` kicker text and `--text-dim`/`--text-muted` on `#111113`).
    - `dark-glow`: 6 instances of ungrounded 0-offset neon green drop-shadows.
    - `kicker-above-heading`: 6 redundant uppercase eyebrow tags.
    - `ai-color-palette`: 6 instances of electric violet code highlighting on pitch dark.
    - `gpt-thin-border-wide-shadow`: 3 instances of 1px border + 44px blur radius on simulated windows.
    - `em-dash-overuse`: 19 em-dashes throughout marketing copy.
    - `line-length`: 4 paragraphs stretching to ~97 characters per line.
- **Visual Overlays**: Live overlay injection was verified in headless Chromium. Overlays highlighted 66 distinct DOM nodes, particularly the dense clusters of sub-11px labels, low-contrast kicker chips, and oversized blur halos.

## Overall Impression

Lattices has one of the coolest, most culturally grounded hero sections in developer tools—the alternating human/agent keycast apparatus and pixel mascot are memorable and differentiated. But the landing page currently suffers from an identity crisis: it tries to be a window manager pitch, a computer-use safety platform, an iPad companion teaser, an API documentation guide, and a CLI package page all at once. Trimming the product dilution and elevating typographical craft will make it world-class.

## What's Working

1. **The Alternating "You vs. Agent" Hero Apparatus**: Alternating between human keyboard chords (`⌃⌥G`) and agent toolcalls (`space.optimize`) within an authentic macOS desktop preview instantly communicates the product's unique value proposition.
2. **Tactile Hardware Brand Accents**: The 3×3 LED matrix mark, the live state pill (`state: synced`), and the pixel mascot leaning with cursor movement create a distinctive Teenage Engineering meets Dieter Rams industrial vibe.
3. **Interactive Layout and Gesture Showcases**: Allowing developers to click between 1, 2, and 3-pane configurations to preview the exact `.lattices.json` configuration provides immediate tangibility.

## Priority Issues

- **[P1] Product & Brand Dilution**: The page tries to sell Lattices (window manager), Action (CUA safety framework), and Lats.dev (iPad deck) simultaneously. Section `#cua` introduces a 4-step loop that belongs on `/action`, distracting from Lattices' primary conversion funnel.
  - *Why it matters*: Users are left confused about what Lattices actually is: an app, an agent runtime, a computer-use model, or an iPad remote.
  - *Fix*: Move the deep computer-use staging loop to `/action`. Focus Lattices squarely on the macOS workspace & agent control plane.
  - *Suggested command*: `/impeccable distill`

- **[P1] Accessibility & Readability Deficits**: 34 instances of sub-11px text and 13 low-contrast elements (e.g., `--text-dim` at 50% opacity and `--text-muted` at 30% opacity on `#111113` background yield contrast ratios below 3.5:1).
  - *Why it matters*: Critical explanatory copy, kicker labels, and shortcut hints are nearly unreadable for users with low vision or in bright ambient light.
  - *Fix*: Raise minimum UI text floor to 12px; increase opacity tokens to 72% for dim text and 52% for muted text to pass WCAG AA (4.5:1).
  - *Suggested command*: `/impeccable audit`

- **[P2] Above-the-Fold Cognitive Overload**: The hero presents six competing interactive and visual focal points simultaneously: primary/secondary CTA buttons, 4 install badges, a 12-second video preview card, two "Without/With" desktop buttons, moving window animations, and an agent terminal stream.
  - *Why it matters*: Visitors do not know where to look first; working memory is overwhelmed, reducing CTA conversion.
  - *Fix*: Subordinate the 12-second video link into a secondary link below the CTA; give the interactive comparison stage clear breathing room.
  - *Suggested command*: `/impeccable layout`

- **[P2] Category-Saturated SaaS Clichés**: The page leans on generic AI tooling patterns: 6 kicker chips with dash-prefixes, 19 em-dashes, 44px neon green blur glows, and repetitive 3-column numbered articles (`01`, `02`, `03`).
  - *Why it matters*: Erodes the premium, bespoke industrial hardware feel of the brand and makes it blend into generic YC SaaS templates.
  - *Fix*: Replace kicker chips with typographic hierarchy; ground box-shadows in directional ambient lighting rather than uniform neon glows.
  - *Suggested command*: `/impeccable bolder`

## Persona Red Flags

- **Jordan (Confused First-Timer)**: Gets stuck at the "Action · a Lattices product" section. Jordan wonders: *"Did I click onto a different product? Do I need to buy Action to use Lattices, or is Action what runs the computer?"* Jordan also struggles with technical shorthand like `AX snapshot` and `CUA` without tooltips.
- **Riley (Deliberate Stress Tester)**: Switches the theme toggle to light mode and discovers that several terminal blocks, syntax highlight colors (`.hl-kw`, `.hl-str`), and window titlebars maintain dark-mode hardcoded styles (`#111113`), causing visual clipping and unstyled contrast breaks.
- **Casey (Distracted Mobile User)**: Views the landing page on an iPhone 14/15. The complex simulated macOS desktop stage squishes to 360px wide, compressing the four tiled windows and agent harness into unreadable vertical text slivers that push the actual download buttons off the screen.

## Minor Observations

- The `.hero-meta` list (`5,500+ installs`, `Local first`, `API driven`, `Built for macOS`) uses plain bullet points that feel like an afterthought under the CTA buttons.
- The `Middle-drag for Spaces, Screen Map, and dictation` feature in the app list assumes a three-button mouse, which most trackpad Mac users don't have.
- Code blocks inside interactive tabs use raw HTML strings via `dangerouslySetInnerHTML` rather than a unified syntax highlighting component.
- The footer lists "macOS only. tmux optional." which is punchy and great—more of this personality should permeate the midsection copy.

## Questions to Consider

- What if the entire page was structured like a physical control deck, using the industrial warm archival paper / slate styling from the SYS.01 concept rather than dark mode SaaS cards?
- Does the computer-use "Action" section belong on this page at all, or should it be a dedicated showcase on `/action` with only a 1-sentence integration mention here?
- How much faster would developers convert if the very first thing below the hero was a copyable `brew install lattices` or `curl` command alongside the DMG download?
