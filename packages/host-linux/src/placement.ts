// Placement math, matching the Mac's TilePosition table
// (apps/mac/Sources/Core/Desktop/WindowTiler.swift) and grid syntax
// (docs/api.md, windows.place).

import type { Json } from "./router.ts";

/** Fractions of a display's visible frame. */
export interface Fractions {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

const grid = (cols: number, rows: number, col: number, row: number): Fractions => ({
  x: col / cols,
  y: row / rows,
  w: 1 / cols,
  h: 1 / rows,
});

const TILES: Record<string, Fractions> = {
  maximize: { x: 0, y: 0, w: 1, h: 1 },
  center: { x: 0.1, y: 0.1, w: 0.8, h: 0.8 },
  left: grid(2, 1, 0, 0),
  right: grid(2, 1, 1, 0),
  top: grid(1, 2, 0, 0),
  bottom: grid(1, 2, 0, 1),
  "top-left": grid(2, 2, 0, 0),
  "top-right": grid(2, 2, 1, 0),
  "bottom-left": grid(2, 2, 0, 1),
  "bottom-right": grid(2, 2, 1, 1),
  "left-third": grid(3, 1, 0, 0),
  "center-third": grid(3, 1, 1, 0),
  "right-third": grid(3, 1, 2, 0),
  "top-left-third": grid(3, 2, 0, 0),
  "top-center-third": grid(3, 2, 1, 0),
  "top-right-third": grid(3, 2, 2, 0),
  "bottom-left-third": grid(3, 2, 0, 1),
  "bottom-center-third": grid(3, 2, 1, 1),
  "bottom-right-third": grid(3, 2, 2, 1),
  "first-fourth": grid(4, 1, 0, 0),
  "second-fourth": grid(4, 1, 1, 0),
  "third-fourth": grid(4, 1, 2, 0),
  "last-fourth": grid(4, 1, 3, 0),
  "top-third": grid(1, 3, 0, 0),
  "middle-third": grid(1, 3, 0, 1),
  "bottom-third": grid(1, 3, 0, 2),
  "left-quarter": grid(4, 1, 0, 0),
  "right-quarter": grid(4, 1, 3, 0),
  "top-quarter": grid(1, 4, 0, 0),
  "bottom-quarter": grid(1, 4, 0, 3),
};

const SYNONYMS: Record<string, string> = {
  max: "maximize",
  full: "maximize",
  "upper-third": "top-third",
  "lower-third": "bottom-third",
};

export const PLACEMENT_NAMES = Object.keys(TILES);

/** Parse a placement shorthand or typed object into fractions, or throw. */
export function parsePlacement(placement: Json | undefined): Fractions {
  if (typeof placement === "string") return parsePlacementString(placement);
  if (placement && typeof placement === "object" && !Array.isArray(placement)) {
    const kind = placement.kind;
    if (kind === "tile" || kind === "named" || kind === "position") {
      return parsePlacementString(String(placement.value ?? ""));
    }
    if (kind === "grid") {
      const n = (k: string) => Number(placement[k]);
      return checkedGrid(n("columns"), n("rows"), n("column"), n("row"));
    }
    if (kind === "fractions") {
      const f = { x: Number(placement.x), y: Number(placement.y), w: Number(placement.w), h: Number(placement.h) };
      if (![f.x, f.y, f.w, f.h].every(Number.isFinite) || f.w <= 0 || f.h <= 0 || f.x < 0 || f.y < 0 || f.x + f.w > 1.0001 || f.y + f.h > 1.0001) {
        throw new Error(`Invalid fractions placement: ${JSON.stringify(placement)}`);
      }
      return f;
    }
  }
  throw new Error(`Unknown placement: ${JSON.stringify(placement ?? null)}`);
}

function parsePlacementString(raw: string): Fractions {
  const name = raw.trim().toLowerCase();
  const tile = TILES[SYNONYMS[name] ?? name];
  if (tile) return tile;
  // grid:CxR:C,R is 0-indexed; the compact CxR:C,R form is 1-indexed.
  const canonical = /^grid:(\d+)x(\d+):(\d+),(\d+)$/.exec(name);
  if (canonical) {
    const [, c, r, col, row] = canonical.map(Number);
    return checkedGrid(c, r, col, row);
  }
  const compact = /^(\d+)x(\d+):(\d+),(\d+)$/.exec(name);
  if (compact) {
    const [, c, r, col, row] = compact.map(Number);
    return checkedGrid(c, r, col - 1, row - 1);
  }
  throw new Error(`Unknown placement: ${raw}`);
}

function checkedGrid(cols: number, rows: number, col: number, row: number): Fractions {
  if (![cols, rows, col, row].every(Number.isInteger) || cols < 1 || rows < 1 || col < 0 || row < 0 || col >= cols || row >= rows) {
    throw new Error(`Invalid grid placement: ${cols}x${rows} at ${col},${row}`);
  }
  return grid(cols, rows, col, row);
}

/** Pixel rect for fractions of a visible frame, rounded to whole pixels. */
export function rectFor(fractions: Fractions, visible: Rect): Rect {
  const x = Math.round(visible.x + fractions.x * visible.w);
  const y = Math.round(visible.y + fractions.y * visible.h);
  const right = Math.round(visible.x + (fractions.x + fractions.w) * visible.w);
  const bottom = Math.round(visible.y + (fractions.y + fractions.h) * visible.h);
  return { x, y, w: right - x, h: bottom - y };
}
