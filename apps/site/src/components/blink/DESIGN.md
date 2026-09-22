---
name: Blink landing within Lattices
description: The existing Blink spatial-notes identity with a scoped Lattices family header.
colors:
  parchment: "#efe8d8"
  panel: "#f8f3e8"
  panel-raised: "#fdfaf3"
  ink: "#181711"
  secondary-ink: "#4d493c"
  muted-ink: "#6d6452"
  line: "#d1c5ae"
  strong-line: "#b7a88f"
  bottle-green: "#2f6447"
  on-accent: "#fbf6e9"
  dark-background: "#09090b"
  dark-panel: "#141417"
  dark-ink: "#f4f4f5"
  dark-accent: "#8fb4ff"
typography:
  display:
    fontFamily: '"Cormorant Garamond", Georgia, serif'
    fontWeight: 600
  section-heading:
    fontFamily: '"Cormorant Garamond", Georgia, serif'
    fontSize: "clamp(32px, 3vw, 42px)"
    fontWeight: 600
  introduction:
    fontFamily: '"Space Grotesk", -apple-system, sans-serif'
    fontSize: "16px"
    lineHeight: 1.7
  body:
    fontFamily: '"JetBrains Mono", monospace, ui-monospace, SFMono-Regular, Menlo, monospace'
  label:
    fontSize: "11px"
    fontWeight: 500
    letterSpacing: "0.18em"
rounded:
  chip: "4px"
  keycap: "5px"
  button: "6px"
  demo: "8px"
components:
  button-primary:
    backgroundColor: "{colors.bottle-green}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.button}"
    height: "44px"
    padding: "0 20px"
  button-secondary:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.secondary-ink}"
    rounded: "{rounded.button}"
    height: "44px"
    padding: "0 20px"
---

# Design System: Blink landing

## Overview

This document describes only the implemented `/blink` landing inside `#blink-landing`. Preserve the original blink.arach.dev composition, parchment and green identity, serif headings, artwork, real film, spatial demonstrations, sheet previews, and interactions. The Lattices integration adds family navigation and selective typography; it does not define a new site-wide design system.

Implementation authority: the components in this directory, `../../styles/blink-integration.css`, and `../../styles/blink.generated.css`. The generated stylesheet is built from the original Blink landing source; regenerate it with `bun run blink:styles` rather than editing it directly. The frontmatter records a compact set of implemented values, with light-theme component colors; the CSS remains authoritative for all theme variants.

## Colors

Bottle green marks primary actions and emphasis on warm parchment. Near-black ink, secondary ink, muted ink, and two border strengths establish hierarchy. Panel tones provide small surface shifts without turning each section into a card.

The existing dark variant uses neutral black surfaces, pale ink, and a blue accent. Preserve that variant independently of the light palette. Theme changes remain scoped to the Blink root and use the existing Light, Dark, and Auto controls.

## Typography

Cormorant Garamond carries the Blink wordmark, hero statement, and section headings. The wordmark scales from 66px to 86px; the hero statement scales from 32px to 40px. Keep their compact leading and existing line breaks.

JetBrains Mono remains the inherited page voice for detail, demonstrations, shortcuts, and technical content. Space Grotesk is selectively applied to family navigation, the first hero paragraph, and paragraphs immediately following section headings. Do not expand this override to all copy: the shared section-header supporting text is currently a div and retains its existing typography. Small uppercase section labels use wide tracking and an adjacent divider.

## Layout

The page uses a centered 1024px content width, with 16px narrow-screen and 24px wider-screen gutters. The hero becomes a two-column introduction and spatial-demo layout at the large breakpoint; preserve the original section order and spacing.

The fixed family header contains Lattices / Blink branding, Products, agent access, theme controls, Download, and a second row of Blink section anchors. Sections have a 110px scroll offset. Below 640px, the top row can wrap, agent and theme controls are hidden, and section anchors scroll horizontally.

## Elevation & Depth

Depth belongs to the product demonstration: dark translucent note panels use blur, fine highlights, and layered shadows over a softly lit desktop. The light page uses warm washes, the original hero art, dither, and subtle framing. Keycaps have a small raised edge. The header uses a nearly opaque page-colored surface with 12px backdrop blur.

The dark theme retains its existing screen treatment, including square corner framing. Keep reduced-motion overrides and the existing reveal behavior; do not add new motion as part of family integration.

## Shapes

Use compact rounded rectangles for controls and keycaps, with slightly larger corners on demo chrome. Preserve the actual note, sheet, and desktop shapes rather than replacing them with generic marketing cards. Dark-theme corner framing is intentionally different from the warm rounded light frame.

## Components

- Primary and secondary links share a 44px height. Primary hover brightens and adds a green shadow; secondary hover changes its panel fill and text. Both depress by 1px when active.
- Key chords show the diamond Hyper glyph and final key, with the full modifier sequence in the accessible label.
- The theme switcher is a keyboard-operable radio group with a tinted selected state.
- Shared mock title bars and desktop chrome keep small labels, restrained borders, and existing status details.
- The spatial demo, real video, agent walkthrough, and sheet previews are defining content. Retain their current controls, state transitions, and media.
- Keyboard focus uses a 1px accent outline with a 3px offset.

## Do's and Don'ts

- Do preserve original Blink assets and composition when making integration changes.
- Do keep family navigation consistent with the existing Lattices Products menu.
- Do scope styling and theme state to Blink.
- Do regenerate compiled styles after changing utility classes.
- Don't substitute new artwork or synthetic demo footage for the original media.
- Don't replace Blink's serif and monospace identity with global site typography.
- Don't promote this scoped document into a root design system or redesign other products from it.
