# Companion Deck Builder — implementation spec

**Status:** proposed / for review — implementation on hold (owner is reviewing this doc first).
**Architecture owner decisions (confirmed):**
- **The builder lives on the Mac.** The Mac owns the cockpit layout + the shortcut catalog and is the source of truth.
- **The iPad just receives the layout and renders it.** The only iPad change is a span-capable renderer; no iOS editor, no on-device deck store.
- **Mac-defined shortcuts are the standard model.** ("The Mac defining its shortcuts is a somewhat standard idea.") The iPad defining *its own* decks is a possible future bonus — explicitly **out of scope** for this work.

This is an **upgrade of the existing Mac cockpit editor**, not a greenfield build. The Mac already ships a functional-but-basic editor and a positional layout model; this spec extends both to support variable grid shapes and spanning keys, and replaces the per-slot dropdown UI with a real visual grid builder.

---

## 0. What already exists (ground truth)

- **Layout model** — `apps/mac/Sources/Core/Companion/LatticesCompanionCockpit.swift`
  - `LatticesCompanionCockpitLayout { pages: [Page] }`; `Page { id, title, subtitle, columns: Int = 4, slotIDs: [String] }` (Codable/Equatable).
  - Positional flat slots: exactly `slotCount = 16` per page; slot index *i* ⇒ row `i / columns`, col `i % columns`; `""` = empty slot (gap). `normalizedSlots` pads/trims to 16.
  - `LatticesCompanionCockpitCatalog`: `defaultLayout` (blueprint pages: `command`, `talkie`, …), a static shortcut catalog (`shortcuts`, `definition(for:)`), 9 categories (`LatticesCompanionShortcutCategory`) with tint tokens, and per-shortcut `actionID`+`payload` templates (keyboard / placement / resize / voice / mouse / switching / media).
  - `normalized(_:)` maps the persisted layout onto the blueprint pages — **it currently drops any non-blueprint page id** and clamps `columns >= 2`.
  - `renderedState(layout:voice:desktop:layoutState:talkie:) -> DeckCockpitState` builds the `DeckCockpitPage`/`DeckCockpitTile` payload sent to the iPad, hydrating live state (e.g. voice-toggle → "Stop Voice"/`isActive`).
- **Persistence** — `apps/mac/Sources/AppShell/Preferences.swift`
  - `companionCockpitLayout` (`didSet → persistCompanionCockpitLayout()`, UserDefaults JSON); `resetCompanionCockpitLayout()`; `updateCompanionCockpitSlot(pageID:index:shortcutID:)`.
- **Editor UI (basic)** — `apps/mac/Sources/AppShell/SettingsView.swift`
  - `companionCockpitCard` (line ~3820): page `Picker` + a 16-slot grid where each slot is a `companionCockpitSlotMenu` (a dropdown to assign a catalog shortcut or clear the slot), plus a reset button. `@State selectedCompanionCockpitPageID`.
- **Serving** — `apps/mac/Sources/Core/Companion/LatticesDeckHost.swift` `manifest()` / snapshot path serves `DeckCockpitState` over the secure bridge.
- **iPad renderer** — `apps/ios/Sources/LatsDeckScreen.swift`
  - `LatsShortcutGrid` renders a flat `[LatsShortcut]` into equal rows of `columns` (fill-vs-scroll via GeometryReader, spacing 9, minRowHeight 96). `liveShortcuts()` maps `DeckCockpitTile` → `LatsShortcut`. `LatsShortcutTile` = keycap. No span/position support anywhere yet.
- **Shared package** — `swift/Sources/DeckKit/DeckCockpit.swift`: `DeckCockpitPage { columns, tiles }`, `DeckCockpitTile { …, no layout fields }`. Compiled by **both** the Mac app and the iOS app.

---

## 1. Summary

Extend the Mac's cockpit layout so each key can be a rectangular block with explicit position and span (`col,row,colSpan,rowSpan`), grow the grid to a variable shape (2–5 columns × 1–4 rows, ≤16 keys, gaps allowed), and replace the dropdown editor with a **visual grid builder** in Mac Settings (tap-to-add, drag-to-move, resize-to-span, catalog-backed action picker, deck management). The layout continues to render through `renderedState()` into `DeckCockpitState`; `DeckCockpitTile` gains **optional** layout fields so the span/position rides the existing bridge to the iPad. The iPad's only change is generalizing `LatsShortcutGrid` into a span-aware renderer. No new endpoint is required — the layout already flows Mac → iPad through the manifest/snapshot.

---

## 2. Data model

### 2a. DeckKit (shared — `swift/Sources/DeckKit/DeckCockpit.swift`)

Add **optional** layout fields (nil-default ⇒ Codable back-compat; both builds recompile with no source changes elsewhere):

```swift
// DeckCockpitTile
public var col: Int?      // 0-based anchor column
public var row: Int?      // 0-based anchor row
public var colSpan: Int?  // nil ⇒ 1
public var rowSpan: Int?  // nil ⇒ 1

// DeckCockpitPage
public var rows: Int?     // nil ⇒ legacy behavior (derive rows from tiles/columns)
```

Rebuild **both** targets after this change (`cd apps/mac && swift build -c release`, plus the iOS scheme). Any non-optional addition or init-parameter reorder breaks the Mac build.

### 2b. Mac layout model (`LatticesCompanionCockpit.swift`)

Replace the flat `slotIDs: [String]` with a positional slot list that carries span, while keeping a lossless migration from the old format:

```swift
struct Slot: Codable, Equatable {
    var shortcutID: String   // "" ⇒ empty
    var col: Int
    var row: Int
    var colSpan: Int = 1
    var rowSpan: Int = 1
}
struct Page: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var columns: Int         // 2...5
    var rows: Int            // 1...4  (NEW; default 4)
    var slots: [Slot]        // replaces slotIDs
}
```

**Migration:** implement a custom `Page` decoder that reads legacy `slotIDs: [String]` (16 entries) when `slots` is absent, mapping slot index *i* ⇒ `Slot(shortcutID: id, col: i % columns, row: i / columns, 1×1)` and dropping `""` entries. Bump a `schemaVersion` on the layout for headroom. This keeps every persisted UserDefaults blob and the `defaultLayout` blueprint valid.

`normalized(_:)` must be updated to (a) validate/repair spans (clamp into bounds, resolve overlaps deterministically by dropping the later slot), and (b) **stop dropping non-blueprint pages** if deck add/remove is in scope (see Phasing P3) — today it hard-maps to blueprint ids.

`renderedState()` / `renderedTile()` set the new `DeckCockpitTile.col/row/colSpan/rowSpan` from each slot; `DeckCockpitPage.rows` from the page. `slotCount = 16` becomes a max-keys cap, not a fixed length.

---

## 3. Layout engine

**Placement model: explicit anchors, gaps allowed.** Grid is ≤ 5×4 = 20 cells, so an explicit canvas is trivially editable and matches the existing positional slot model; no auto-flow reflow (surprising on resize). Legacy flat pages already map by slot index (§2b).

**Validation** (pure functions, shared by the Mac store + editor):
1. `2 ≤ columns ≤ 5`, `1 ≤ rows ≤ 4`.
2. `keys.count ≤ 16` (non-empty slots).
3. Per key: `colSpan ≥ 1`, `rowSpan ≥ 1`, `col ≥ 0`, `row ≥ 0`, `col + colSpan ≤ columns`, `row + rowSpan ≤ rows`.
4. No overlap: paint each key's rect into a `rows × columns` occupancy grid; any double-paint is an error naming both keys.
5. Gaps are legal (render as empty pad) — full tiling not required.

**Rendering geometry (shared iPad + Mac canvas): pure cell-rect math + absolute positioning**, not a `Layout` conformance (the editor reuses the same rects for hit-testing, drag ghosts, drop validation):

```
cellW = (width  - (columns-1)*spacing) / columns
rowH  = fill ? (height - (rows-1)*spacing) / rows : minRowHeight
rect(key) = (x: col*(cellW+spacing), y: row*(rowH+spacing),
             w: colSpan*cellW + (colSpan-1)*spacing,
             h: rowSpan*rowH + (rowSpan-1)*spacing)
```

Implement once as `DeckGridGeometry` (candidate for DeckKit so Mac + iPad share it; if kept per-platform, keep the two copies identical). Keep the iPad's existing fill-vs-scroll rule (spacing 9, minRowHeight 96) and point→cell inverse for editor hit-testing.

---

## 4. iPad renderer (the only iPad change)

- `LatsShortcut` (`LatsDeckScreen.swift`) gains `var placement: DeckGridPlacement? = nil` (small Equatable struct: col/row/colSpan/rowSpan).
- `liveShortcuts()` copies the tile's `col/row/colSpan/rowSpan` into `placement`.
- `LatsShortcutGrid` gains `var rows: Int? = nil` and branches: if **any** shortcut has a placement → new positioned path (`ZStack` + `DeckGridGeometry`, reusing `LatsShortcutTile` verbatim; compute `act.NN` index by `(row, col)` order); else the **existing chunked flow path unchanged** (mocks, legacy live pages, and the App Store screenshot harness in `LatticesCompanionApp.swift` render byte-identically).
- In `gridColumns` (`LatsDeckScreen.swift`), the compact clamp `min(3, columns)` **must not** apply to placed pages — explicit placement depends on the true column count; compact devices get smaller cells / scroll instead of reflow.
- No iOS editor, no `CompanionDeckStore`, no source-mode toggle. The iPad renders whatever `DeckCockpitState` the Mac sends.

---

## 5. Mac editor UX (the builder)

Rebuild `companionCockpitCard` (`SettingsView.swift:3820`) from a per-slot dropdown list into a visual grid builder. Keep it inside the existing Settings surface (a card that can expand, or a dedicated sheet/tab if it needs room).

- **Deck selector:** the current page `Picker` → a segmented/list selector over the layout's pages; add rename + (P3) add/reorder/delete. `columns` stepper (2–5) and `rows` stepper (1–4) with an inline guard when shrinking would orphan keys (block + "remove N affected keys" confirmation).
- **Canvas:** render the deck exactly as the iPad would (the same `DeckGridGeometry` cell math) so the editor preview *is* the renderer. Empty cells show a dashed add-affordance; keys show icon + label + tint.
  - Tap empty cell → create a slot there → open the inspector (action-first; a slot with no action is inert).
  - Tap key → select (ring in the key's tint); resize handle → change span (snap to cells, reject overlap/out-of-bounds); drag → move (cell-snapped ghost, green valid / red invalid).
  - Delete key (context menu / inspector).
- **Inspector** (selected key): label, icon (SF Symbol picker over the catalog's icons + free-form field), tint (category tokens), size presets (1×1 / 2×1 / 1×2 / 2×2 / full-row) + span steppers, and **action** — a browser over `LatticesCompanionCockpitCatalog.shortcuts` grouped by `LatticesCompanionShortcutCategory`; choosing one fills actionID/payload/title/icon/tint. An "advanced" disclosure exposes raw `actionID` + a payload editor (round-trip through `DeckValue`), plus a key-combo sub-builder emitting `keys.send` payloads.
- Reuse the existing `prefs.updateCompanionCockpitSlot`-style mutation surface, extended to span/position (`updateSlot(pageID:slotID:…)`, `addSlot`, `removeSlot`, `setGridShape`). Keep `resetCompanionCockpitLayout()`.

AppKit/SwiftUI: this is the Mac app's existing SwiftUI settings stack — build with its current components; a drag/resize canvas is the main new UI work.

---

## 5b. Editor implementation — embed the web builder (recommended)

Rather than reimplement the span grid, drag/move, resize, make-room displacement, inspector, and catalog in SwiftUI, **host the already-built React `DeckBuilder` (`design/studio/src/studio/studies/DeckBuilder.tsx`) in a `WKWebView`** inside Mac Settings. The interactive editor is done and proven; a native rebuild would re-solve drag/drop, span geometry, and the displacement algorithm from scratch. This turns the prototype into the product and collapses most of the editor phases into "wire the bridge + persist."

- **Stays native, unchanged by this choice:** the DeckKit span extension (§2), `renderedState()` carrying spans (§6), persistence in `Preferences` (§0/§9), and the iPad spanning renderer (§4). The web view only replaces the *editor UI*.
- **Packaging:** build the builder into a small static bundle (extract it into a standalone Vite `index.html`, or a Next static export of the single route) and embed it in the app bundle; load via `WKWebView.loadFileURL`. A tiny build step keeps the embedded bundle in sync with the studio study (one source of UI).
- **JS ↔ Swift bridge:**
  - *Init* — Swift injects the current layout (`Preferences.companionCockpitLayout`, normalized) + the shortcut catalog (`LatticesCompanionCockpitCatalog` → JSON) into the page, so the catalog stays single-source on the Mac and the builder drops its hardcoded `CATALOG`/`SEED`.
  - *Save* — the page posts changes via `window.webkit.messageHandlers.deck.postMessage(layout)`; a `WKScriptMessageHandler` decodes them into the layout model and writes `companionCockpitLayout` (→ `renderedState()` → bridge → iPad, live).
  - *Theme/size* — pass the dark theme + a content size; the study already renders dark.
- **Trade-offs:** ➕ reuse the finished editor, ship fast, iterate in the browser, web is ideal for canvas/drag UI. ➖ a `WKWebView` island in native Settings (sizing/focus/theming polish), a build-and-embed step to keep in sync, and the JS↔Swift bridge for persistence + catalog. The native SwiftUI editor (§5) stays the fallback if the embed feels wrong.
- **Recommendation:** start with the embedded web view. The `DeckBuilder` study is the editor; the remaining work is the DeckKit/render span plumbing (needed either way) plus a thin persistence bridge.

---

## 6. Serving / data flow

No new endpoint. Mac layout (persisted) → `renderedState()` (now carrying spans) → `DeckCockpitState` → existing `LatticesDeckHost.manifest()`/snapshot → bridge → iPad `liveSnapshot.cockpit.pages` → `liveShortcuts()` → span-aware `LatsShortcutGrid`. Because `DeckCockpitTile` layout fields are optional, older iPad builds ignore them (flat render) and newer builds honor them — forward/backward compatible.

---

## 7. Action catalog

Already exists Mac-side (`LatticesCompanionCockpitCatalog.shortcuts`, 9 categories, actionID/payload templates). The builder's action picker reads it directly; no port needed (unlike the earlier iOS-first plan). Free-form actionID/payload stays available for power users. Talkie category behavior is Mac-state-dependent (`talkieShortcut`) — keep as-is.

---

## 8. Phasing

- **P1 — model + spanning render end-to-end.** DeckKit optional layout fields; Mac `Page.slots` + migration + `normalized()`/`renderedState()` carrying spans; iPad `DeckGridGeometry` + positioned path in `LatsShortcutGrid`. *Accept:* hand-author a page with a 2×2 and a 2×1 slot (even via the existing/temporary editing surface), and the iPad renders the spans correctly; legacy pages and the screenshot harness render unchanged; both targets build.
- **P2 — visual builder.** Replace `companionCockpitCard` with the canvas + inspector: tap-add, tap-select, drag-move, resize-span, catalog action picker, grid-shape steppers. *Accept:* build a deck visually on the Mac, it persists, and it appears on a connected iPad.
- **P3 — deck management + polish.** Add/rename/reorder/delete pages (update `normalized()` to preserve non-blueprint pages); free-form payload + key-combo builder; icon picker polish; validation UX. *Accept:* create a 6th deck; iPad deck pill/swipe cycling follows it.
- **P4 (later / bonus) — iPad-authored decks.** Only if the owner wants the "iPad defines its own too" bonus: an on-device layer + a signed `/deck/layout` write endpoint. Out of scope now.

---

## 9. Decisions table

| Question | Decision |
|---|---|
| Where does the builder live? | **Mac app** (extends the existing `companionCockpitCard` + layout model + catalog). |
| iPad role | **Receives `DeckCockpitState` and renders it**; only change is a span-aware `LatsShortcutGrid`. No editor/store. |
| Placement model | **Explicit `(col,row,colSpan,rowSpan)` anchors, gaps allowed.** Grid ≤ 5×4; matches existing positional slots; legacy flat pages migrate by index. |
| Model change shape | Replace `Page.slotIDs: [String]` with `Page.slots: [Slot]` (+`rows`) with a legacy decoder; add **optional** `col/row/colSpan/rowSpan` to `DeckCockpitTile` and `rows` to `DeckCockpitPage` (Codable back-compat). |
| Spanning render | Shared `DeckGridGeometry` cell-rect math + absolute positioning; keep iPad fill-vs-scroll (spacing 9, minRowHeight 96). |
| Action catalog | Reuse the existing Mac `LatticesCompanionCockpitCatalog` + free-form advanced. |
| Persistence | Existing `Preferences.companionCockpitLayout` (UserDefaults JSON), extended + `schemaVersion` + migration. |
| Bounds | Decks (P3) up to ~8; columns 2–5 (default 4); rows 1–4 (default 4); ≤16 keys; any in-bounds rectangle (UI presets 1×1/2×1/1×2/2×2/full-row); gaps allowed. |
| iPad-authored decks | Deferred bonus (P4), not now. |

---

## 10. Risks / verify before starting

1. **DeckKit is shared by both apps** — rebuild the Mac app *and* the iOS scheme after the model change; keep additions optional / append-only to avoid breaking the Mac build.
2. **Legacy migration** — every persisted `companionCockpitLayout` and the `defaultLayout` blueprint use the old flat `slotIDs`; the custom decoder must decode them losslessly (write a test in `swift/Tests/DeckKitTests` and a Mac-side layout test).
3. **`normalized()` drops non-blueprint pages** today — fine until P3, but deck add/remove requires rewriting it to preserve custom pages while still repairing spans.
4. **`gridColumns` compact clamp** (`LatsDeckScreen.swift`) reflowing to 3 columns would corrupt explicit placement — bypass for placed pages; verify iPhone falls back to scroll acceptably.
5. **Screenshot harness** (`LatticesCompanionApp.swift`, `--app-store-deck=`) builds `LatsDeckScreen(deckID:)` with no live snapshot — must keep rendering mocks via the flat path.
6. **Perform routing** — the Mac's `/deck/perform` handler routes on `actionID`; confirm span/position changes don't affect action dispatch (they shouldn't — layout is presentation only).
7. **Dirty tree** — `apps/ios/Sources/*` currently has an open PR (`ipad-cockpit-redesign`); land or coordinate before touching `LatsDeckScreen.swift` to avoid conflicts. This feature is a **new, separate branch**.
8. **Owner confirmations still open:** deck cap (8?), whether P3 deck add/remove is in the first delivery or later, and whether the builder stays an expandable Settings card vs a dedicated window/sheet.

---

## 11. Prior art — Talkie's deck editor (`~/dev/talkie`)

Talkie has a mature deck configurator that independently arrived at the **same architecture we chose**, which is a strong validation signal — but it is a **fixed-grid, per-slot editor with no spans**, so it's a reference for the *inspector/UX*, not the *layout engine*.

**What it is**
- `apps/ios/Talkie iOS/Views/Configurator/KeyboardGridView.swift` — a WYSIWYG grid (3×4 + a dictate row) where each cell is a `SlotButtonPreview`; tap a slot → open the editor. The **editor preview is the real render** (the pattern we want). Its only "span" is a hardcoded 2×-wide DICTATE button — not user-editable.
- `apps/ios/Talkie iOS/Views/Configurator/SlotEditorSheet.swift` (604 lines) — the rich per-slot editor: a **kind selector** (`text / snippet / action / space / empty`), per-kind dynamic fields, an action picker, a default-vs-custom summary, live keyboard-context preview, and Save/Cancel → `buildConfig()`. This is the most borrowable piece.
- Model `apps/ios/Talkie iOS/Models/DeckBoardSnapshot.swift`: `DeckBoardSnapshot → [DeckSpace] → tiles: [DeckTile]` ("16 entries for the canonical 4×4"). `DeckTile { id, slotID?, label, icon, hint? }` — **no position/span/size**. `DeckMirrorStore` renders the Mac's board and fires `slotID` back to the Mac.

**Architecture (identical to Lattices, validates the Mac-side decision)**
> "iOS-side mirror of the macOS Command Deck … Mac resolves [label] from its shortcut catalog; iOS just renders it." A `DeckBoardSnapshot` ships Mac→iOS over the bridge; iOS renders and fires `slotID`; the Mac dispatches. This is exactly `DeckCockpitState` + `store.perform` in Lattices, and exactly the owner's "Mac owns, iPad renders" call.

**Borrow for our Mac builder**
1. The `SlotEditorSheet` structure for our key inspector — a **kind selector** is nicer than "pick one catalog shortcut": e.g. `action (catalog) / key-combo / advanced`, with per-kind fields + live preview.
2. The **override + "customized" + reset-to-default** slot model (maps onto Lattices' existing `updateCompanionCockpitSlot` / `resetCompanionCockpitLayout`).
3. **Editor preview = the renderer** (WYSIWYG), already in §5.

**What Talkie does NOT solve (our net-new work):** user-defined **spans + variable grid shape**. Both Talkie and today's Lattices editor are fixed 16-slot 4×4. The spanning/variable-shape layer (§2–§3) is the genuinely new contribution — we design it; we can't lift it from Talkie.
