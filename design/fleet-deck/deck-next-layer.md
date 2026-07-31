# Deck — the next layer

**Direction from the operator, 2026-07-30.** Three things: bigger touch targets and tighter chrome; application-aware controls (Chrome tabs, Ghostty/iTerm and the multiplexer class); and a spatial window map projected into the trackpad region so you can *see* a window and jump to it.

This document establishes what already exists before anything gets designed on top of it, because the answer turns out to change the plan.

---

## 1. What is already there

Checked, not assumed.

| Capability | Status |
|---|---|
| Frontmost app on the Mac | **Live** — `layout.frontmostWindow.appName`, `desktop.activeAppName` |
| Window geometry, normalized | **Live** — `DeckLayoutPreviewWindow`, emitted at `LatticesDeckHost.swift:900` |
| Tapping a window to focus it | **Built** — `LatsLayoutSurface.previewCard` → `switch.focusItem` |
| Tabs | **Protocol slot, no producer** — `DeckSwitcherItemKind.tab` is declared and the Mac never emits it |
| Terminal / tmux knowledge on the Mac | **Exists, unreachable** — lives in OmniSearch / CommandMode / assistant layers, nothing reaches the bridge |
| Control sizing knobs | `minimumControlHeight = 80` (`:1485`), positioned-grid `rowHeight = 96` (`:1504`), grid spacing 10 |

### The finding that matters

**The window map is roughly 80% built and is in the wrong place.**

`DeckLayoutPreviewWindow` already carries `normalizedFrame`, `title`, `subtitle`, `appCategory`, `appCategoryTint`, `isFrontmost`, `displayIndex`, and `itemID`. The Mac emits it on every snapshot. And `LatsSurfaceDetailView` → `LatsLayoutSurface.previewCard` *already draws it* — normalized frames as rectangles, tinted by app category, frontmost highlighted, each one tappable to focus via `switch.focusItem`.

It works today. It is buried in a legacy "surfaces" list that the deck entry model no longer routes anyone to. The work is not building this feature; it is **moving it into the deck and making it small enough to live there**.

That reorders the three asks by cost: density is cheap, the map is cheap-and-already-working, and app-awareness is the only one that needs new protocol.

---

## 2. Density

Nothing here is blocked. Knobs exist; the numbers are simply phone numbers on a desk device.

Current: control min height 80, positioned rows 96, grid spacing 10, chrome strips 26.

The 44pt guidance everyone quotes is a *floor for a phone held in one hand*. A 13" iPad on a desk, operated with a thumb while looking at a different screen, wants targets well above it — and the deck has the room, currently spent on chrome.

Squeeze candidates, in order: the 26pt chrome strips, inter-tile spacing, and the trackpad (the operator explicitly offered this one back). Awaiting kimi's target numbers rather than inventing them, since this is exactly the call that spec exists to make.

---

## 3. The window map

**Design question is not "can we" but "where does it live and how does it read at 8 points wide".**

Open, with kimi:

- **Does the map share the trackpad's rectangle?** Tempting, and I suspect wrong: one surface that means both *relative pointer* and *absolute window position* is two mental models on one control. Alternatives are stacked regions, or the map as the default with the trackpad as a mode.
- **Colour.** `appCategoryTint` is live data and reintroduces a palette the v7 spec deliberately removed. A window map may be the one place a category palette earns its way back — or identity has to come from position and frontmost-ness alone.
- **Multi-display.** `displayIndex` and `displayCount` exist. Two displays side by side halve an already tiny window.

---

## 4. Application-aware controls

The only one of the three that needs new protocol, and the only one with a real design risk.

**What exists:** the frontmost app name, on every snapshot. That is enough to *switch* a control set. It is not enough to *populate* one.

**What is missing:**

- **Tabs.** `.tab` is declared in `DeckSwitcherItemKind` and never produced. Chrome tab navigation needs the Mac to enumerate tabs and expose a focus-by-index action. Nothing in the deck host does this today.
- **Terminal/multiplexer state.** The Mac knows about tmux sessions and terminal tabs — the CLI's `terminals.search` exposes cwd, tab titles, tmux sessions, running commands — but that lives in the daemon and assistant layers. The companion deck host does not surface any of it.

**The risk I want challenged before building** (out with fable): every special-cased app is a contract with somebody else's UI. Chrome renames a menu item, iTerm changes a binding, and a button on the iPad silently does the wrong thing to a live session. There is also a targeting problem specific to the multiplexer case — tmux inside Ghostty inside a window means a keystroke has three possible recipients, chosen by state the iPad cannot see.

And one question about the premise itself: "jump to the seventh tab" requires already knowing it is seventh, which implies looking at the Mac — while the app's whole premise is operating a Mac you are not looking at. The feature may be real, but the framing that makes it real is probably *"show me the tabs, let me pick one"* rather than *"go to tab seven"*.

---

## 5. Order

1. **Density.** No dependencies, immediate benefit, reversible.
2. **Window map into the deck.** The renderer exists; this is placement, scale, and legibility.
3. **Tabs as a producer.** `.tab` already exists in the protocol — emit it, render a list, focus by `itemID`. This gets the Chrome and terminal cases *without* per-app keybinding contracts, because picking from a list the Mac supplied is app-agnostic.
4. **Per-app control sets** — only if 3 proves insufficient, and only for a set small enough to maintain honestly.

Step 3 before step 4 is the important ordering: it may make step 4 unnecessary, and it cannot rot the way a keybinding table can.
