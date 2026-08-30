# Blink Mobile Design — Index Tape

Blink Mobile is the carbon copy of a spatial desktop: a chronological note log
that remains trustworthy when the Mac is gone. Chronology supplies the
structure; ledger discipline supplies the geometry.

## Visual world

- Warm paper in light mode, neutral graphite in dark mode. Never forest green.
- The phone log stays flat and full-bleed, separated by rules. On iPad, native
  material earns its place by making notes read as windows over a desktop plane;
  glass is spatial structure, never decorative frosting.
- Signal blue marks the one live thing on screen. Amber means degraded or stale
  data, never ordinary offline use.
- System typography carries interface copy; monospaced text carries indices,
  timestamps, state, and measurement; the system serif carries reader titles.

## Signature components

- The workspace name is the large navigation title. The Blink mark opens scope.
- Sync is a two-point rule plus a square pip and terse state: update age in the
  normal case, Mac name while connected, and action language only when stale or
  blocked.
- First connection is one iPhone request followed by one Mac approval. Blink
  remembers the approved device until the Mac revokes it; pairing codes never
  enter the interface.
- The top-right complication opens local Settings. Connection, appearance, and
  on-device notes are separate pages built from Hudson settings primitives.
- Index Tape is the default theme. Field, Deck, Scope, Focus, and Console are
  app-generic treatments adapted from proven palettes across the Arach app
  family. Theme and light/system/dark mode persist locally.
- Every row has one continuous machine rail: a zero-padded index above a static
  time stamp. A pin square replaces the index.
- Compact search grows from the bottom rail into a real SwiftUI field. At
  regular width, search uses the native sidebar placement.
- The reader repeats the indexed gutter and stays flat, sharp, and read-only.

## Tokens

Light: canvas `#F2F0EC`, surface `#FCFAF6`, raised `#FFFFFF`, rail `#EBE7DF`,
rule `#DAD5CB`, ink `#17130F`, secondary `#5C554F`, faint `#6F695F`, signal
`#2D5DAF`, amber `#7E6029`.

Dark: canvas `#0A0B0C`, surface `#121416`, raised `#17191C`, rail `#0E1012`,
rule `#2A2E31`, ink `#FBEEE8`, secondary `#9AA0A2`, faint `#7A7F81`, signal
`#83B4FF`, amber `#D6B96C`.

## Native adaptation

The Studio study is a direction, not a point-size contract. SwiftUI controls
retain Dynamic Type, VoiceOver grouping, keyboard avoidance, 44-point targets,
native navigation, and interactive keyboard dismissal. Rail metadata collapses
before clipping at accessibility sizes. State is always stated in text as well
as color.

## iPad desk

- Regular-width iPad layouts become a spatial nine-slot desk instead of a
  stretched phone log. A note's portable `blink.slot` value chooses its place;
  exact Mac window frames remain local to that Mac.
- The desk uses Blink's blue-violet-teal desktop drape and a quiet alignment
  grid. It reflects the Mac app's atmosphere without copying desktop pixels,
  requesting Screen Recording access, or adding wallpaper data to replication.
- On iPadOS 26, resting notes and compact chrome use clear interactive Liquid
  Glass while the raised reader uses regular glass for contrast. Earlier
  systems use native materials; Reduce Transparency produces opaque semantic
  surfaces and removes the atmospheric drape.
- Unplaced notes and slot collisions fill the next open cells in chronological
  order. More than nine notes create additional swipeable desks, preserving a
  predictable grid rather than shrinking notes into thumbnails.
- Opening a note raises a readable panel above the desk, keeping nearby notes
  visible as spatial context. Closing it returns to the same desk and place.
- Search, workspace scope, sync, settings, and themes are shared with iPhone.
  Compact multitasking widths and accessibility Dynamic Type deliberately fall
  back to the chronological log.
