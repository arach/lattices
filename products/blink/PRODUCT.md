# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Blink is for people who use spatial notes as a working set on a Mac and need to
recall those notes away from the desk on an iPhone or iPad. The initial companion
is optimized for one person pairing their own devices.

## Product Purpose

Blink makes notes spatial on macOS: the note is the window and the desktop is the
workspace. Its mobile companion makes the same notes and workspace membership
available for quick, read-only recall without turning Blink into a document
library.

## Positioning

Markdown files remain the durable truth. Mobile access is a projection of that
file-backed workspace, not a second authoritative store or a proprietary note
format.

## Operating Context

On macOS, people capture, place, resize, shade, focus, and edit floating note
panels. On iOS, they discover and pair with their Mac, sync a coherent snapshot,
filter by workspace, search, and read from an offline cache.

## Capabilities and Constraints

- The first mobile transport is same-network LAN discovery.
- Pairing uses an end-to-end sealed channel inside the encrypted peer session;
  the device's reusable seed lives in non-migrating Keychain storage, never
  leaves the device, and derives a distinct credential for each Mac.
- The Mac's agreement private key and approved-device credentials also live in
  Keychain storage; neither side substitutes an ephemeral identity on failure.
- Mobile is read-only in the first version; edits and conflict resolution remain
  an open decision.
- Exact frontmattered Markdown, foreign metadata, stable note identity, and
  deletion evidence survive replication.
- LAN is the shipped route. The content model remains provider-agnostic so a
  future orchestrator can add Tailscale or managed relays without changing the
  snapshot format.
- Per-device macOS panel frames stay local and are not mobile document state.
- The replaceable mobile note cache is excluded from device backups and Remove
  Notes cancels pending sync before deleting it.

## Brand Commitments

The user-visible name is Blink. The macOS product's graphite-and-paper surfaces,
cool signal-blue accent, precise monospaced metadata, and quiet operational voice
are the incumbent identity. Native mobile conventions take priority over porting
desktop chrome literally.

## Evidence on Hand

The working macOS app, BlinkCore note/frontmatter tests, CLI documentation, and
the existing Capture Popover are the source material. No customer claims,
benchmarks, or third-party endorsements are available and none should be invented.

## Product Principles

- Keep Markdown as truth and caches replaceable.
- Make the common capture-to-recall loop immediate.
- Preserve identity and metadata before adding replication cleverness.
- Prefer local, comprehensible behavior with explicit secure escalation.
- Follow each Apple platform's native interaction model.

## Accessibility & Inclusion

The mobile companion uses Dynamic Type, semantic colors, native navigation and
controls, VoiceOver labels, 44-point minimum targets, and Reduce Motion-aware
transitions.
