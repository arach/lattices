"use client";

/**
 * Deck Builder — interactive study for the companion cockpit editor.
 *
 * A span-aware grid editor in the Lats keycap / reticle visual language:
 * tap an empty cell to add a key, drag to move (cell-snapped, valid/invalid
 * ghost), drag the corner handle to span multiple cells, and edit the selected
 * key in the inspector (label / icon / tint / action / size). Grid shape is
 * 2–5 columns × 1–4 rows, ≤ 16 keys, gaps allowed. Pure design prototype — the
 * real editor is built on the Mac (see docs/companion-deck-builder-spec.md).
 */

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Mic, X, CornerDownLeft, ArrowLeft, ArrowRight, ArrowUp, ArrowDown,
  ChevronLeft, ChevronRight, Search, Command, LayoutGrid, Crosshair,
  MousePointer2, Space as SpaceIcon, PanelLeft, PanelRight,
  SquareDashed, Maximize2, Monitor, Terminal, Play, Hammer, GitBranch,
  Volume2, Sun, Camera, Sparkles, Home, Clock, Plus, Trash2, Rows3, Columns3,
} from "lucide-react";
import type { LatticesPage } from "@/studio/studioRegistry";

// ── palette (Lats design tokens) ─────────────────────────────────────────
const TINTS = {
  red: "#E1726B", amber: "#E8BC6B", green: "#81DD86", blue: "#7EAFE2",
  teal: "#6ECFCF", violet: "#BD97FC", pink: "#F593CE",
} as const;
type Tint = keyof typeof TINTS;
const TINT_KEYS = Object.keys(TINTS) as Tint[];

const INK = {
  pad: "#060607", well0: "#0a0b0d", well1: "#08090b", card: "#0c0c0e",
  brk: "#202024", fg: "#e2e2df", fg2: "#a0a09b", fg3: "#71716c", fg4: "#4a4a4d",
};

// ── icon registry ────────────────────────────────────────────────────────
const ICONS = {
  Mic, X, CornerDownLeft, ArrowLeft, ArrowRight, ArrowUp, ArrowDown,
  ChevronLeft, ChevronRight, Search, Command, LayoutGrid, Crosshair,
  MousePointer2, SpaceIcon, PanelLeft, PanelRight, SquareDashed, Maximize2,
  Monitor, Terminal, Play, Hammer, GitBranch, Volume2, Sun, Camera, Sparkles,
  Home, Clock,
} as const;
type IconName = keyof typeof ICONS;
const ICON_PICKER: IconName[] = [
  "Mic", "X", "CornerDownLeft", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown",
  "ChevronLeft", "ChevronRight", "Search", "Command", "LayoutGrid", "Crosshair",
  "MousePointer2", "SpaceIcon", "PanelLeft", "PanelRight", "Maximize2", "Monitor",
  "Terminal", "Play", "Hammer", "GitBranch", "Volume2", "Sun", "Camera",
  "Sparkles", "Home", "Clock", "SquareDashed",
];
function Icon({ name, size = 15, color }: { name: IconName; size?: number; color?: string }) {
  const C = ICONS[name] ?? SquareDashed;
  return <C size={size} color={color} strokeWidth={1.7} />;
}

// ── action catalog (mirrors the Mac shortcut catalog) ────────────────────
type CatalogItem = { id: string; label: string; icon: IconName; tint: Tint; category: string };
const CATALOG: { group: string; items: CatalogItem[] }[] = [
  { group: "Voice", items: [
    { id: "voice.toggle", label: "Start Voice", icon: "Mic", tint: "red", category: "voice" },
    { id: "voice.cancel", label: "Cancel Voice", icon: "X", tint: "red", category: "voice" },
  ]},
  { group: "System", items: [
    { id: "key.escape", label: "Escape", icon: "CornerDownLeft", tint: "amber", category: "system" },
    { id: "key.enter", label: "Enter", icon: "CornerDownLeft", tint: "amber", category: "system" },
    { id: "key.space", label: "Space", icon: "SpaceIcon", tint: "amber", category: "system" },
  ]},
  { group: "Switching", items: [
    { id: "switch.appPrev", label: "Prev App", icon: "ChevronLeft", tint: "blue", category: "system" },
    { id: "switch.appNext", label: "Next App", icon: "ChevronRight", tint: "blue", category: "system" },
    { id: "switch.winPrev", label: "Prev Window", icon: "ArrowLeft", tint: "blue", category: "window" },
    { id: "switch.winNext", label: "Next Window", icon: "ArrowRight", tint: "blue", category: "window" },
  ]},
  { group: "Layout", items: [
    { id: "layout.optimize", label: "Optimize", icon: "LayoutGrid", tint: "blue", category: "window" },
    { id: "layout.left", label: "Left", icon: "PanelLeft", tint: "blue", category: "window" },
    { id: "layout.right", label: "Right", icon: "PanelRight", tint: "blue", category: "window" },
    { id: "layout.center", label: "Center", icon: "SquareDashed", tint: "blue", category: "window" },
    { id: "layout.maximize", label: "Maximize", icon: "Maximize2", tint: "blue", category: "window" },
    { id: "layout.monitorL", label: "L Monitor", icon: "Monitor", tint: "teal", category: "window" },
    { id: "layout.monitorR", label: "R Monitor", icon: "Monitor", tint: "teal", category: "window" },
  ]},
  { group: "Mouse", items: [
    { id: "mouse.find", label: "Find Mouse", icon: "Crosshair", tint: "green", category: "system" },
    { id: "mouse.summon", label: "Summon Mouse", icon: "MousePointer2", tint: "green", category: "system" },
  ]},
  { group: "Dev", items: [
    { id: "dev.terminal", label: "Terminal", icon: "Terminal", tint: "green", category: "dev" },
    { id: "dev.run", label: "Run", icon: "Play", tint: "green", category: "dev" },
    { id: "dev.build", label: "Build", icon: "Hammer", tint: "amber", category: "dev" },
    { id: "dev.git", label: "Git", icon: "GitBranch", tint: "amber", category: "dev" },
  ]},
  { group: "Media", items: [
    { id: "media.play", label: "Play", icon: "Play", tint: "violet", category: "system" },
    { id: "media.vol", label: "Volume", icon: "Volume2", tint: "teal", category: "system" },
    { id: "media.bright", label: "Brightness", icon: "Sun", tint: "amber", category: "system" },
    { id: "media.shot", label: "Screenshot", icon: "Camera", tint: "pink", category: "system" },
  ]},
  { group: "Agent", items: [
    { id: "agent.claude", label: "Claude", icon: "Sparkles", tint: "violet", category: "agent" },
    { id: "agent.home", label: "Home", icon: "Home", tint: "pink", category: "system" },
    { id: "agent.recents", label: "Recents", icon: "Clock", tint: "violet", category: "system" },
  ]},
];
const CATALOG_BY_ID = new Map(CATALOG.flatMap((g) => g.items).map((i) => [i.id, i]));

// ── model ────────────────────────────────────────────────────────────────
export type Key = {
  id: string; label: string; icon: IconName; tint: Tint; category: string;
  actionID: string; col: number; row: number; colSpan: number; rowSpan: number;
};
export type Deck = { id: string; name: string; tint: Tint; columns: number; rows: number; keys: Key[] };

let uid = 0;
const nid = () => `k${++uid}`;
function keyFrom(item: CatalogItem, col: number, row: number, colSpan = 1, rowSpan = 1): Key {
  return { id: nid(), label: item.label, icon: item.icon, tint: item.tint,
    category: item.category, actionID: item.id, col, row, colSpan, rowSpan };
}
const c = (id: string) => CATALOG_BY_ID.get(id)!;

const SEED: Deck[] = [
  { id: "command", name: "Command", tint: "green", columns: 4, rows: 4, keys: [
    { ...keyFrom(c("voice.toggle"), 0, 0, 2, 2) },
    keyFrom(c("key.escape"), 2, 0), keyFrom(c("key.enter"), 3, 0),
    keyFrom(c("voice.cancel"), 2, 1), keyFrom(c("key.space"), 3, 1),
    { ...keyFrom(c("layout.optimize"), 0, 2, 2, 1) },
    keyFrom(c("mouse.find"), 2, 2), keyFrom(c("mouse.summon"), 3, 2),
    keyFrom(c("layout.left"), 0, 3), keyFrom(c("layout.right"), 1, 3),
    keyFrom(c("layout.center"), 2, 3), keyFrom(c("layout.maximize"), 3, 3),
  ]},
  { id: "windows", name: "Windows", tint: "blue", columns: 4, rows: 3, keys: [
    { ...keyFrom(c("layout.optimize"), 0, 0, 4, 1) },
    keyFrom(c("layout.left"), 0, 1), keyFrom(c("layout.right"), 1, 1),
    keyFrom(c("layout.center"), 2, 1), keyFrom(c("layout.maximize"), 3, 1),
    { ...keyFrom(c("layout.monitorL"), 0, 2, 2, 1) },
    { ...keyFrom(c("layout.monitorR"), 2, 2, 2, 1) },
  ]},
  { id: "dev", name: "Dev", tint: "green", columns: 4, rows: 2, keys: [
    keyFrom(c("dev.terminal"), 0, 0), keyFrom(c("dev.run"), 1, 0),
    keyFrom(c("dev.build"), 2, 0), keyFrom(c("dev.git"), 3, 0),
    { ...keyFrom(c("layout.optimize"), 0, 1, 2, 1) },
    keyFrom(c("switch.winPrev"), 2, 1), keyFrom(c("switch.winNext"), 3, 1),
  ]},
  { id: "media", name: "Media", tint: "violet", columns: 3, rows: 2, keys: [
    { ...keyFrom(c("media.play"), 0, 0, 1, 2) },
    keyFrom(c("media.vol"), 1, 0), keyFrom(c("media.bright"), 2, 0),
    keyFrom(c("media.shot"), 1, 1), keyFrom(c("agent.home"), 2, 1),
  ]},
  { id: "voice", name: "Voice", tint: "red", columns: 3, rows: 2, keys: [
    { ...keyFrom(c("voice.toggle"), 0, 0, 2, 1) },
    keyFrom(c("voice.cancel"), 2, 0),
    keyFrom(c("agent.claude"), 0, 1), keyFrom(c("agent.recents"), 1, 1),
    keyFrom(c("mouse.summon"), 2, 1),
  ]},
];

const SIZE_PRESETS: { label: string; cs: number; rs: number }[] = [
  { label: "1×1", cs: 1, rs: 1 }, { label: "2×1", cs: 2, rs: 1 },
  { label: "1×2", cs: 1, rs: 2 }, { label: "2×2", cs: 2, rs: 2 },
];

// ── geometry + validation ────────────────────────────────────────────────
const CELL = 108;
const GAP = 10;
const canvasSize = (n: number) => n * CELL + (n - 1) * GAP;
const cellRect = (k: { col: number; row: number; colSpan: number; rowSpan: number }) => ({
  left: k.col * (CELL + GAP),
  top: k.row * (CELL + GAP),
  width: k.colSpan * CELL + (k.colSpan - 1) * GAP,
  height: k.rowSpan * CELL + (k.rowSpan - 1) * GAP,
});
const inBounds = (k: Key, cols: number, rows: number) =>
  k.col >= 0 && k.row >= 0 && k.col + k.colSpan <= cols && k.row + k.rowSpan <= rows;

const intersects = (
  a: Pick<Key, "col" | "row" | "colSpan" | "rowSpan">,
  b: Pick<Key, "col" | "row" | "colSpan" | "rowSpan">,
) =>
  a.col < b.col + b.colSpan && a.col + a.colSpan > b.col &&
  a.row < b.row + b.rowSpan && a.row + a.rowSpan > b.row;

function findFreeSpot(
  m: Key, occ: boolean[][], cols: number, rows: number, prefer: { col: number; row: number }[],
): { col: number; row: number } | null {
  const fits = (col: number, row: number) => {
    if (col < 0 || row < 0 || col + m.colSpan > cols || row + m.rowSpan > rows) return false;
    for (let r = 0; r < m.rowSpan; r++) for (let c = 0; c < m.colSpan; c++) if (occ[row + r][col + c]) return false;
    return true;
  };
  for (const p of prefer) if (fits(p.col, p.row)) return p;         // fill the vacated space first → swap feel
  for (let row = 0; row < rows; row++) for (let col = 0; col < cols; col++) if (fits(col, row)) return { col, row };
  return null;
}

/**
 * Resolve a move/resize: drop the dragged key at its new footprint and push any
 * keys it now overlaps into free cells — preferring the cells the dragged key
 * just vacated, so a same-size drop reads as a straight swap and a bigger move
 * shuffles the smaller keys into the freed space. Returns the full new layout,
 * or null when there genuinely isn't room.
 */
function resolve(
  keys: Key[],
  dragId: string,
  next: Partial<Pick<Key, "col" | "row" | "colSpan" | "rowSpan">>,
  cols: number,
  rows: number,
): Key[] | null {
  const dragged = keys.find((k) => k.id === dragId);
  if (!dragged) return null;
  const K: Key = { ...dragged, ...next };
  if (!inBounds(K, cols, rows)) return null;

  const originCells: { col: number; row: number }[] = [];
  for (let r = 0; r < dragged.rowSpan; r++)
    for (let c = 0; c < dragged.colSpan; c++) originCells.push({ col: dragged.col + c, row: dragged.row + r });

  const others = keys.filter((k) => k.id !== dragId);
  const displaced = others
    .filter((k) => intersects(K, k))
    .sort((a, b) => b.colSpan * b.rowSpan - a.colSpan * a.rowSpan); // place larger keys first
  const fixed = others.filter((k) => !intersects(K, k));

  const occ = Array.from({ length: rows }, () => Array<boolean>(cols).fill(false));
  const paint = (k: Key) => {
    for (let r = 0; r < k.rowSpan; r++) for (let c = 0; c < k.colSpan; c++) occ[k.row + r][k.col + c] = true;
  };
  fixed.forEach(paint);
  paint(K);

  const placed: Key[] = [];
  for (const m of displaced) {
    const spot = findFreeSpot(m, occ, cols, rows, originCells);
    if (!spot) return null; // no room to make space → invalid drop
    const m2 = { ...m, col: spot.col, row: spot.row };
    paint(m2);
    placed.push(m2);
  }
  return [...fixed, K, ...placed];
}

// ── component ──────────────────────────────────────────────────────────────
type Drag =
  | { mode: "move"; id: string; col: number; row: number; ok: boolean; preview: Key[] | null }
  | { mode: "resize"; id: string; colSpan: number; rowSpan: number; ok: boolean; preview: Key[] | null };

/**
 * Reusable deck editor core. In the studio it's wrapped by `DeckBuilderStudy`;
 * in the Mac app it's loaded chrome-free at `/embed/deck-builder`, seeded with
 * `initialDecks` (the Mac's current layout) and reporting every change through
 * `onChange` → the JS↔Swift bridge, which persists to `companionCockpitLayout`.
 */
export function DeckBuilder({ initialDecks, onChange, className }: {
  initialDecks?: Deck[];
  onChange?: (decks: Deck[]) => void;
  className?: string;
}) {
  const [decks, setDecks] = useState<Deck[]>(initialDecks && initialDecks.length ? initialDecks : SEED);
  const [activeId, setActiveId] = useState(() => (initialDecks?.[0]?.id ?? "command"));
  const [selId, setSelId] = useState<string | null>(null);
  const [drag, setDrag] = useState<Drag | null>(null);
  const canvasRef = useRef<HTMLDivElement>(null);

  // Report layout changes to the host bridge; skip the initial mount so we don't
  // echo the seed/injected layout straight back to the Mac.
  const firstEmit = useRef(true);
  useEffect(() => {
    if (firstEmit.current) { firstEmit.current = false; return; }
    onChange?.(decks);
  }, [decks, onChange]);

  const deck = decks.find((d) => d.id === activeId) ?? decks[0];
  const sel = deck.keys.find((k) => k.id === selId) ?? null;

  const patchDeck = useCallback((fn: (d: Deck) => Deck) => {
    setDecks((ds) => ds.map((d) => (d.id === activeId ? fn(d) : d)));
  }, [activeId]);
  const patchKey = useCallback((id: string, fn: (k: Key) => Key) => {
    patchDeck((d) => ({ ...d, keys: d.keys.map((k) => (k.id === id ? fn(k) : k)) }));
  }, [patchDeck]);

  const pointerCell = useCallback((e: React.PointerEvent | PointerEvent) => {
    const rect = canvasRef.current!.getBoundingClientRect();
    const col = Math.floor((e.clientX - rect.left) / (CELL + GAP));
    const row = Math.floor((e.clientY - rect.top) / (CELL + GAP));
    return {
      col: Math.max(0, Math.min(deck.columns - 1, col)),
      row: Math.max(0, Math.min(deck.rows - 1, row)),
    };
  }, [deck.columns, deck.rows]);

  // occupancy grid for empty-cell affordances
  const occupied = useMemo(() => {
    const g = Array.from({ length: deck.rows }, () => Array<boolean>(deck.columns).fill(false));
    for (const k of deck.keys)
      for (let r = 0; r < k.rowSpan; r++)
        for (let cc = 0; cc < k.colSpan; cc++)
          if (g[k.row + r]) g[k.row + r][k.col + cc] = true;
    return g;
  }, [deck]);

  // ── drag / resize ────────────────────────────────────────────────────
  const startMove = (e: React.PointerEvent, k: Key) => {
    e.stopPropagation();
    const start = pointerCell(e);
    const grabCol = start.col - k.col, grabRow = start.row - k.row;
    const dragState: Drag = { mode: "move", id: k.id, col: k.col, row: k.row, ok: true, preview: null };
    setSelId(k.id);
    setDrag(dragState);
    const move = (ev: PointerEvent) => {
      const p = pointerCell(ev);
      const nc = Math.max(0, Math.min(deck.columns - k.colSpan, p.col - grabCol));
      const nr = Math.max(0, Math.min(deck.rows - k.rowSpan, p.row - grabRow));
      dragState.col = nc; dragState.row = nr;
      const layout = resolve(deck.keys, k.id, { col: nc, row: nr }, deck.columns, deck.rows);
      dragState.ok = !!layout; dragState.preview = layout;
      setDrag({ ...dragState });
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      const layout = dragState.preview;
      if (dragState.ok && layout) patchDeck((d) => ({ ...d, keys: layout }));
      setDrag(null);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };

  const startResize = (e: React.PointerEvent, k: Key) => {
    e.stopPropagation();
    const dragState: Drag = { mode: "resize", id: k.id, colSpan: k.colSpan, rowSpan: k.rowSpan, ok: true, preview: null };
    setSelId(k.id);
    setDrag(dragState);
    const move = (ev: PointerEvent) => {
      const p = pointerCell(ev);
      const cs = Math.max(1, Math.min(deck.columns - k.col, p.col - k.col + 1));
      const rs = Math.max(1, Math.min(deck.rows - k.row, p.row - k.row + 1));
      dragState.colSpan = cs; dragState.rowSpan = rs;
      const layout = resolve(deck.keys, k.id, { colSpan: cs, rowSpan: rs }, deck.columns, deck.rows);
      dragState.ok = !!layout; dragState.preview = layout;
      setDrag({ ...dragState });
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      const layout = dragState.preview;
      if (dragState.ok && layout) patchDeck((d) => ({ ...d, keys: layout }));
      setDrag(null);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };

  const addAt = (col: number, row: number) => {
    if (deck.keys.length >= 16) return;
    const item = c("layout.optimize");
    const k = keyFrom(item, col, row);
    patchDeck((d) => ({ ...d, keys: [...d.keys, k] }));
    setSelId(k.id);
  };

  const setGrid = (cols: number, rows: number) => {
    patchDeck((d) => ({
      ...d, columns: cols, rows,
      // drop keys that no longer fit within the new bounds
      keys: d.keys.filter((k) => k.col + k.colSpan <= cols && k.row + k.rowSpan <= rows),
    }));
  };

  const applySize = (cs: number, rs: number) => {
    if (!sel) return;
    const layout = resolve(
      deck.keys, sel.id,
      { colSpan: Math.min(cs, deck.columns - sel.col), rowSpan: Math.min(rs, deck.rows - sel.row) },
      deck.columns, deck.rows,
    );
    if (layout) patchDeck((d) => ({ ...d, keys: layout }));
  };

  const chooseAction = (item: CatalogItem) => {
    if (!sel) return;
    patchKey(sel.id, (k) => ({ ...k, actionID: item.id, label: item.label, icon: item.icon, tint: item.tint, category: item.category }));
  };

  const keyCount = deck.keys.length;

  return (
    <div className={className}>
      {/* deck tabs + grid shape */}
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex items-center gap-1.5">
          {decks.map((d) => (
            <button
              key={d.id}
              onClick={() => { setActiveId(d.id); setSelId(null); }}
              className="rounded-md px-3 py-1.5 font-mono text-[11px] tracking-wide transition-colors"
              style={{
                color: d.id === activeId ? INK.fg : INK.fg3,
                background: d.id === activeId ? "rgba(126,175,226,0.10)" : "transparent",
                border: `0.5px solid ${d.id === activeId ? "rgba(126,175,226,0.30)" : INK.brk}`,
              }}
            >
              {d.name.toLowerCase()}
            </button>
          ))}
        </div>
        <div className="ml-auto flex items-center gap-4">
          <Stepper icon={<Columns3 size={13} />} label="cols" value={deck.columns} min={2} max={5}
            onChange={(v) => setGrid(v, deck.rows)} />
          <Stepper icon={<Rows3 size={13} />} label="rows" value={deck.rows} min={1} max={4}
            onChange={(v) => setGrid(deck.columns, v)} />
          <span className="font-mono text-[11px]" style={{ color: keyCount >= 16 ? TINTS.amber : INK.fg3 }}>
            {keyCount}/16 keys
          </span>
        </div>
      </div>

      {/* builder: canvas + inspector */}
      <div className="mt-5 flex flex-wrap items-start gap-6">
        {/* canvas */}
        <div
          className="relative shrink-0 rounded-[14px] p-5"
          style={{
            background: `linear-gradient(160deg, ${INK.well0}, ${INK.well1} 60%, #090a0c)`,
            border: `1px solid rgba(255,255,255,0.07)`,
            boxShadow: "0 22px 60px -30px rgba(0,0,0,0.9)",
          }}
          onClick={() => setSelId(null)}
        >
          <Reticle />
          <div
            ref={canvasRef}
            className="relative"
            style={{ width: canvasSize(deck.columns), height: canvasSize(deck.rows) }}
          >
            {/* empty-cell add affordances (hidden while dragging) */}
            {!drag && occupied.map((rowArr, r) =>
              rowArr.map((occ, cc) =>
                occ ? null : (
                  <button
                    key={`e${r}-${cc}`}
                    onClick={(e) => { e.stopPropagation(); addAt(cc, r); }}
                    className="absolute flex items-center justify-center rounded-[10px] transition-colors"
                    style={{
                      left: cc * (CELL + GAP), top: r * (CELL + GAP), width: CELL, height: CELL,
                      border: `1px dashed ${INK.brk}`, color: INK.fg4,
                    }}
                  >
                    <Plus size={16} />
                  </button>
                )
              )
            )}

            {/* keys — during a drag every key lays out at its resolved position so
                the displaced keys visibly make room; the dragged one follows the cursor. */}
            {deck.keys.map((k) => {
              const dragging = drag?.id === k.id;
              const previewKey = drag?.preview?.find((p) => p.id === k.id);
              let rect;
              if (dragging && drag) {
                rect = drag.mode === "move"
                  ? cellRect({ ...k, col: drag.col, row: drag.row })
                  : cellRect({ ...k, colSpan: drag.colSpan, rowSpan: drag.rowSpan });
              } else if (previewKey) {
                rect = cellRect(previewKey);
              } else {
                rect = cellRect(k);
              }
              return (
                <KeyBlock
                  key={k.id}
                  k={k}
                  rect={rect}
                  selected={selId === k.id}
                  dragging={!!dragging}
                  dragOk={dragging ? drag!.ok : true}
                  animate={!!drag && !dragging}
                  onPointerDownMove={(e) => startMove(e, k)}
                  onPointerDownResize={(e) => startResize(e, k)}
                  onSelect={() => setSelId(k.id)}
                />
              );
            })}
          </div>
          <div className="mt-3 font-mono text-[10px]" style={{ color: INK.fg4 }}>
            tap empty cell to add · drag to move · pull the corner to span
          </div>
        </div>

        {/* inspector */}
        <div
          className="min-w-[300px] flex-1 rounded-[10px] p-4"
          style={{ background: INK.card, border: `1px solid ${INK.brk}` }}
        >
          {sel ? (
            <KeyInspector
              k={sel}
              onLabel={(v) => patchKey(sel.id, (k) => ({ ...k, label: v }))}
              onTint={(t) => patchKey(sel.id, (k) => ({ ...k, tint: t }))}
              onIcon={(ic) => patchKey(sel.id, (k) => ({ ...k, icon: ic }))}
              onSize={applySize}
              onAction={chooseAction}
              onDelete={() => { patchDeck((d) => ({ ...d, keys: d.keys.filter((x) => x.id !== sel.id) })); setSelId(null); }}
            />
          ) : (
            <DeckInspector deck={deck} onName={(v) => patchDeck((d) => ({ ...d, name: v }))} />
          )}
        </div>
      </div>

      <p className="mt-6 max-w-[70ch] font-mono text-[11px] leading-relaxed" style={{ color: INK.fg3 }}>
        Interactive prototype for the Mac-side companion deck builder. The grid, spans, keycap
        material, and reticle framing match the live Lats deck so this doubles as the visual spec.
        See <code>docs/companion-deck-builder-spec.md</code>.
      </p>
    </div>
  );
}

/** Studio wrapper — the deck builder under the studio page chrome. */
export function DeckBuilderStudy({ page }: { page: LatticesPage }) {
  return (
    <main className="w-full px-6 py-9 lg:px-7">
      <PageHeader page={page} />
      <DeckBuilder className="mt-6" />
    </main>
  );
}

// ── key block ──────────────────────────────────────────────────────────────
function KeyBlock({ k, rect, selected, dragging, dragOk, animate, onPointerDownMove, onPointerDownResize, onSelect }: {
  k: Key; rect: { left: number; top: number; width: number; height: number };
  selected: boolean; dragging: boolean; dragOk: boolean; animate: boolean;
  onPointerDownMove: (e: React.PointerEvent) => void;
  onPointerDownResize: (e: React.PointerEvent) => void;
  onSelect: () => void;
}) {
  const tint = TINTS[k.tint];
  const ring = dragging ? (dragOk ? TINTS.green : TINTS.red) : selected ? tint : "rgba(0,0,0,0.85)";
  return (
    <div
      onPointerDown={onPointerDownMove}
      onClick={(e) => { e.stopPropagation(); onSelect(); }}
      className="absolute flex select-none flex-col rounded-[11px] p-3"
      style={{
        left: rect.left, top: rect.top, width: rect.width, height: rect.height,
        background: "linear-gradient(180deg, #1a1a1e, #0f0f11 74%, #0c0c0e)",
        border: `${selected || dragging ? 1.5 : 0.5}px solid ${ring}`,
        boxShadow: dragging
          ? "0 18px 34px -12px rgba(0,0,0,0.85)"
          : "inset 0 1px 0 rgba(255,255,255,0.08), inset 0 -1px 1px rgba(0,0,0,0.6), 0 5px 12px -6px rgba(0,0,0,0.6)",
        cursor: dragging ? "grabbing" : "grab",
        opacity: dragging && !dragOk ? 0.7 : 1,
        zIndex: dragging ? 20 : selected ? 10 : 1,
        // displaced keys glide as they make room during a drag
        transition: animate ? "left 0.14s ease, top 0.14s ease, width 0.14s ease, height 0.14s ease" : undefined,
      }}
    >
      <span
        className="flex items-center justify-center rounded-[7px]"
        style={{ width: 26, height: 26, color: tint, background: `${tint}22`, border: `0.5px solid ${tint}66` }}
      >
        <Icon name={k.icon} />
      </span>
      <div className="mt-auto">
        <div className="text-[14px] font-medium" style={{ color: INK.fg }}>{k.label}</div>
        <div className="mt-1 flex items-center gap-1.5 font-mono text-[10px]" style={{ color: INK.fg4 }}>
          <span style={{ width: 5, height: 5, borderRadius: 999, background: tint, display: "inline-block" }} />
          {k.colSpan}×{k.rowSpan} · {k.category}
        </div>
      </div>
      {/* resize handle */}
      <span
        onPointerDown={onPointerDownResize}
        className="absolute bottom-0 right-0 cursor-nwse-resize"
        style={{ width: 18, height: 18 }}
      >
        <span className="absolute bottom-1.5 right-1.5 block" style={{
          width: 7, height: 7, borderRight: `1.5px solid ${INK.fg3}`, borderBottom: `1.5px solid ${INK.fg3}`,
        }} />
      </span>
    </div>
  );
}

// ── inspectors ───────────────────────────────────────────────────────────
function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div className="mb-2 font-mono text-[9px] font-bold uppercase tracking-[0.18em]" style={{ color: TINTS.amber }}>
      {children}
    </div>
  );
}

function KeyInspector({ k, onLabel, onTint, onIcon, onSize, onAction, onDelete }: {
  k: Key;
  onLabel: (v: string) => void; onTint: (t: Tint) => void; onIcon: (i: IconName) => void;
  onSize: (cs: number, rs: number) => void; onAction: (i: CatalogItem) => void; onDelete: () => void;
}) {
  return (
    <div className="flex flex-col gap-4">
      <div>
        <SectionLabel>key</SectionLabel>
        <input
          value={k.label}
          onChange={(e) => onLabel(e.target.value)}
          className="w-full rounded-[6px] px-3 py-2 font-mono text-[12px] outline-none"
          style={{ background: "rgba(0,0,0,0.25)", border: `1px solid ${INK.brk}`, color: INK.fg }}
        />
      </div>

      <div>
        <SectionLabel>size</SectionLabel>
        <div className="flex flex-wrap gap-1.5">
          {SIZE_PRESETS.map((p) => {
            const on = k.colSpan === p.cs && k.rowSpan === p.rs;
            return (
              <button key={p.label} onClick={() => onSize(p.cs, p.rs)}
                className="rounded-[5px] px-2.5 py-1 font-mono text-[11px]"
                style={{ color: on ? INK.pad : INK.fg2, background: on ? TINTS.green : "rgba(255,255,255,0.04)", border: `1px solid ${on ? TINTS.green : INK.brk}` }}>
                {p.label}
              </button>
            );
          })}
          <button onClick={() => onSize(99, k.rowSpan)}
            className="rounded-[5px] px-2.5 py-1 font-mono text-[11px]"
            style={{ color: INK.fg2, background: "rgba(255,255,255,0.04)", border: `1px solid ${INK.brk}` }}>
            full row
          </button>
        </div>
      </div>

      <div>
        <SectionLabel>tint</SectionLabel>
        <div className="flex gap-2">
          {TINT_KEYS.map((t) => (
            <button key={t} onClick={() => onTint(t)}
              style={{ width: 22, height: 22, borderRadius: 6, background: TINTS[t],
                outline: k.tint === t ? `2px solid ${INK.fg}` : "none", outlineOffset: 1 }} />
          ))}
        </div>
      </div>

      <div>
        <SectionLabel>icon</SectionLabel>
        <div className="grid grid-cols-8 gap-1.5">
          {ICON_PICKER.map((ic) => {
            const on = k.icon === ic;
            return (
              <button key={ic} onClick={() => onIcon(ic)}
                className="flex items-center justify-center rounded-[6px] py-1.5"
                style={{ background: on ? `${TINTS[k.tint]}22` : "rgba(255,255,255,0.03)",
                  border: `0.5px solid ${on ? TINTS[k.tint] : INK.brk}`, color: on ? TINTS[k.tint] : INK.fg2 }}>
                <Icon name={ic} size={14} />
              </button>
            );
          })}
        </div>
      </div>

      <div>
        <SectionLabel>action</SectionLabel>
        <div className="max-h-[220px] overflow-y-auto rounded-[6px]" style={{ border: `1px solid ${INK.brk}` }}>
          {CATALOG.map((grp) => (
            <div key={grp.group}>
              <div className="px-3 py-1.5 font-mono text-[9px] uppercase tracking-wider" style={{ color: INK.fg4, background: "rgba(255,255,255,0.02)" }}>
                {grp.group}
              </div>
              {grp.items.map((it) => {
                const on = k.actionID === it.id;
                return (
                  <button key={it.id} onClick={() => onAction(it)}
                    className="flex w-full items-center gap-2.5 px-3 py-1.5 text-left"
                    style={{ background: on ? "rgba(126,175,226,0.10)" : "transparent" }}>
                    <span style={{ color: TINTS[it.tint] }}><Icon name={it.icon} size={13} /></span>
                    <span className="font-mono text-[11px]" style={{ color: on ? INK.fg : INK.fg2 }}>{it.label}</span>
                    <span className="ml-auto font-mono text-[9px]" style={{ color: INK.fg4 }}>{it.id}</span>
                  </button>
                );
              })}
            </div>
          ))}
        </div>
      </div>

      <button onClick={onDelete}
        className="flex items-center justify-center gap-2 rounded-[6px] py-2 font-mono text-[11px]"
        style={{ color: TINTS.red, background: "rgba(225,114,107,0.08)", border: `1px solid rgba(225,114,107,0.3)` }}>
        <Trash2 size={13} /> delete key
      </button>
    </div>
  );
}

function DeckInspector({ deck, onName }: { deck: Deck; onName: (v: string) => void }) {
  return (
    <div className="flex flex-col gap-4">
      <div>
        <SectionLabel>deck</SectionLabel>
        <input value={deck.name} onChange={(e) => onName(e.target.value)}
          className="w-full rounded-[6px] px-3 py-2 font-mono text-[12px] outline-none"
          style={{ background: "rgba(0,0,0,0.25)", border: `1px solid ${INK.brk}`, color: INK.fg }} />
      </div>
      <div className="font-mono text-[11px] leading-relaxed" style={{ color: INK.fg3 }}>
        {deck.columns}×{deck.rows} grid · {deck.keys.length} keys.
        <br />Select a key to edit it, or tap an empty cell to add one. Drag to move, pull the
        corner handle to make a key span multiple cells.
      </div>
      <div className="rounded-[6px] p-3 font-mono text-[10px]" style={{ background: "rgba(255,255,255,0.02)", border: `1px solid ${INK.brk}`, color: INK.fg4 }}>
        Empty cells stay as gaps — a deck doesn&apos;t have to fully tile.
      </div>
    </div>
  );
}

// ── small bits ─────────────────────────────────────────────────────────────
function Stepper({ icon, label, value, min, max, onChange }: {
  icon: React.ReactNode; label: string; value: number; min: number; max: number; onChange: (v: number) => void;
}) {
  return (
    <div className="flex items-center gap-2 font-mono text-[11px]" style={{ color: INK.fg3 }}>
      <span className="flex items-center gap-1">{icon}{label}</span>
      <div className="flex items-center overflow-hidden rounded-[5px]" style={{ border: `1px solid ${INK.brk}` }}>
        <button onClick={() => onChange(Math.max(min, value - 1))} className="px-2 py-0.5" style={{ color: INK.fg2 }}>−</button>
        <span className="min-w-[18px] text-center" style={{ color: INK.fg }}>{value}</span>
        <button onClick={() => onChange(Math.min(max, value + 1))} className="px-2 py-0.5" style={{ color: INK.fg2 }}>+</button>
      </div>
    </div>
  );
}

function Reticle() {
  const L = 11, T = 1, o = 10, col = "rgba(255,255,255,0.34)";
  const bar = (s: React.CSSProperties) => <span className="pointer-events-none absolute" style={{ background: col, ...s }} />;
  return (
    <>
      {bar({ left: o, top: o, width: L, height: T })} {bar({ left: o, top: o, width: T, height: L })}
      {bar({ right: o, top: o, width: L, height: T })} {bar({ right: o, top: o, width: T, height: L })}
      {bar({ left: o, bottom: o, width: L, height: T })} {bar({ left: o, bottom: o, width: T, height: L })}
      {bar({ right: o, bottom: o, width: L, height: T })} {bar({ right: o, bottom: o, width: T, height: L })}
    </>
  );
}

function PageHeader({ page }: { page: LatticesPage }) {
  return (
    <header className="max-w-[980px] border-b border-studio-rule pb-7">
      <div className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
        {page.bucket} / {page.surface}
      </div>
      <h1 className="mt-4 text-[36px] font-medium leading-tight text-studio-ink-strong">{page.label}</h1>
      {page.blurb ? (
        <p className="mt-4 max-w-[66ch] text-[15px] leading-[1.7] text-studio-ink">{page.blurb}</p>
      ) : null}
    </header>
  );
}
