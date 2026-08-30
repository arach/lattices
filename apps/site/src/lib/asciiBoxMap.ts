/**
 * Deterministic Unicode box-drawing renderer.
 *
 * The hero's `lattices — map` used to be a hand-authored string literal, so its
 * corners, T-junctions and crossings drifted out of sync with the window frames
 * they were supposed to describe: outlines stopped mid-run, a `┬` sat where a
 * `┘` belonged, and overlaps were faked with gaps. This module removes the class
 * of bug instead of patching glyphs — rectangles go in, a character grid comes
 * out, and every junction glyph is *derived* from which of its four neighbours
 * an edge actually continues into.
 *
 * The invariant that makes it correct: a cell's glyph encodes a set of
 * directions, and for every direction it claims, the neighbouring cell must
 * claim the opposite direction back. `validateBoxGrid` checks exactly that, so
 * a broken outline is a test failure rather than something you have to spot by
 * eye.
 */

/** Direction bits, in the order used by the glyph table below. */
const UP = 1;
const RIGHT = 2;
const DOWN = 4;
const LEFT = 8;

const BLANK = " ";

/** Light box-drawing glyph for each direction mask. Index === mask. */
const GLYPH_BY_MASK: readonly string[] = [
  BLANK, // 0  ────
  "╵", // 1  U    (stub — only produced by malformed input)
  "╶", // 2  R    (stub)
  "└", // 3  U R
  "╷", // 4  D    (stub)
  "│", // 5  U D
  "┌", // 6  R D
  "├", // 7  U R D
  "╴", // 8  L    (stub)
  "┘", // 9  U L
  "─", // 10 R L
  "┴", // 11 U R L
  "┐", // 12 D L
  "┤", // 13 U D L
  "┬", // 14 R D L
  "┼", // 15 U R D L
];

const MASK_BY_GLYPH = new Map<string, number>();
GLYPH_BY_MASK.forEach((glyph, mask) => {
  if (mask !== 0) MASK_BY_GLYPH.set(glyph, mask);
});

/** A cell whose glyph carries exactly one direction is a dangling line end. */
const STUB_MASKS = new Set([UP, RIGHT, DOWN, LEFT]);

export type BoxRect = {
  /** Left column, inclusive. */
  x: number;
  /** Top row, inclusive. */
  y: number;
  /** Total width in cells, including both vertical edges. */
  w: number;
  /** Total height in cells, including both horizontal edges. */
  h: number;
  /** Optional caption stamped into the top edge, starting one cell in. */
  label?: string;
  /** Higher values stamp their label last, so the front window's title wins. */
  z?: number;
};

export type BoxGrid = {
  width: number;
  height: number;
  /** Direction mask per cell, row-major. */
  masks: Uint8Array;
  /** True where a label character occludes the frame, row-major. */
  labelled: Uint8Array;
};

export type BoxGridProblem = {
  x: number;
  y: number;
  message: string;
};

function idx(grid: { width: number }, x: number, y: number) {
  return y * grid.width + x;
}

function inBounds(grid: { width: number; height: number }, x: number, y: number) {
  return x >= 0 && y >= 0 && x < grid.width && y < grid.height;
}

/**
 * Rasterise rectangles into direction masks.
 *
 * Each edge contributes a *run* of connections rather than a per-cell glyph:
 * a horizontal run gives every cell RIGHT except its last and LEFT except its
 * first, so corners, tees and crossings all fall out of the accumulated mask
 * without a single special case.
 */
export function buildBoxGrid(rects: readonly BoxRect[], width: number, height: number): BoxGrid {
  if (width <= 0 || height <= 0) {
    throw new Error(`box grid must be non-empty, got ${width}×${height}`);
  }

  const grid: BoxGrid = {
    width,
    height,
    masks: new Uint8Array(width * height),
    labelled: new Uint8Array(width * height),
  };

  const connect = (x: number, y: number, bits: number) => {
    if (!inBounds(grid, x, y)) return;
    grid.masks[idx(grid, x, y)] |= bits;
  };

  for (const rect of rects) {
    if (rect.w < 2 || rect.h < 2) {
      throw new Error(`rect ${rect.label ?? "(untitled)"} must be at least 2×2, got ${rect.w}×${rect.h}`);
    }

    const x0 = rect.x;
    const y0 = rect.y;
    const x1 = rect.x + rect.w - 1;
    const y1 = rect.y + rect.h - 1;

    for (let x = x0; x <= x1; x += 1) {
      if (x > x0) {
        connect(x, y0, LEFT);
        connect(x, y1, LEFT);
      }
      if (x < x1) {
        connect(x, y0, RIGHT);
        connect(x, y1, RIGHT);
      }
    }

    for (let y = y0; y <= y1; y += 1) {
      if (y > y0) {
        connect(x0, y, UP);
        connect(x1, y, UP);
      }
      if (y < y1) {
        connect(x0, y, DOWN);
        connect(x1, y, DOWN);
      }
    }
  }

  // Labels are stamped after every outline exists, so a title only ever hides
  // junctions that were already drawn correctly underneath it.
  const labelled = [...rects]
    .map((rect, order) => ({ rect, order }))
    .sort((a, b) => (a.rect.z ?? 0) - (b.rect.z ?? 0) || a.order - b.order);

  for (const { rect } of labelled) {
    if (!rect.label) continue;
    // Leave the two corners and at least one trailing `─` so the top edge still
    // reads as an edge rather than as free-floating text.
    const room = rect.w - 3;
    if (room <= 0) continue;
    const text = [...rect.label].slice(0, room);
    text.forEach((char, i) => {
      const x = rect.x + 1 + i;
      if (!inBounds(grid, x, rect.y)) return;
      grid.labelled[idx(grid, x, rect.y)] = char.codePointAt(0) ?? 32;
    });
  }

  return grid;
}

/** Glyph for a mask, ignoring labels. */
function glyphForMask(mask: number): string {
  return GLYPH_BY_MASK[mask & 15] ?? BLANK;
}

/**
 * Check that the grid is geometrically continuous.
 *
 * Reports a problem when a cell claims a direction its neighbour does not claim
 * back (a broken outline or a mismatched junction), or when a cell carries a
 * single direction (a dangling line end). Labels are ignored: they occlude, they
 * do not connect.
 */
export function validateBoxGrid(grid: BoxGrid): BoxGridProblem[] {
  const problems: BoxGridProblem[] = [];
  const neighbours: Array<[number, number, number, number]> = [
    // [bit, dx, dy, opposite bit]
    [UP, 0, -1, DOWN],
    [RIGHT, 1, 0, LEFT],
    [DOWN, 0, 1, UP],
    [LEFT, -1, 0, RIGHT],
  ];

  for (let y = 0; y < grid.height; y += 1) {
    for (let x = 0; x < grid.width; x += 1) {
      const mask = grid.masks[idx(grid, x, y)];
      if (mask === 0) continue;

      if (STUB_MASKS.has(mask)) {
        problems.push({ x, y, message: `dangling line end "${glyphForMask(mask)}"` });
      }

      for (const [bit, dx, dy, opposite] of neighbours) {
        if ((mask & bit) === 0) continue;
        const nx = x + dx;
        const ny = y + dy;
        if (!inBounds(grid, nx, ny)) {
          problems.push({ x, y, message: `"${glyphForMask(mask)}" runs off the grid` });
          continue;
        }
        const ni = idx(grid, nx, ny);
        // A label hides the frame beneath it; the line still runs underneath,
        // so a connection into a caption is not a break.
        if (grid.labelled[ni]) continue;
        const neighbour = grid.masks[ni];
        if ((neighbour & opposite) === 0) {
          problems.push({
            x,
            y,
            message: `"${glyphForMask(mask)}" connects to "${glyphForMask(neighbour)}" at ${nx},${ny} which does not connect back`,
          });
        }
      }
    }
  }

  return problems;
}

/** Render the grid to text. Every row is padded to the full grid width. */
export function gridToText(grid: BoxGrid): string {
  const rows: string[] = [];
  for (let y = 0; y < grid.height; y += 1) {
    let row = "";
    for (let x = 0; x < grid.width; x += 1) {
      const i = idx(grid, x, y);
      const label = grid.labelled[i];
      row += label ? String.fromCodePoint(label) : glyphForMask(grid.masks[i]);
    }
    rows.push(row);
  }
  return rows.join("\n");
}

/**
 * Throw if the grid is not continuous, naming the offending cells.
 *
 * Callers use this at module load so a layout that tears the diagram fails
 * loudly in dev instead of shipping a broken outline to the page.
 */
export function assertBoxGrid(grid: BoxGrid, context: string): BoxGrid {
  const problems = validateBoxGrid(grid);
  if (problems.length > 0) {
    const detail = problems
      .slice(0, 8)
      .map((p) => `  (${p.x},${p.y}) ${p.message}`)
      .join("\n");
    throw new Error(`${context} is not continuous:\n${detail}`);
  }
  return grid;
}

/** Parse rendered text back into masks, for validating strings from elsewhere. */
export function parseBoxMap(text: string): BoxGrid {
  const rows = text.split("\n");
  const height = rows.length;
  const width = Math.max(...rows.map((row) => [...row].length));
  const grid: BoxGrid = {
    width,
    height,
    masks: new Uint8Array(width * height),
    labelled: new Uint8Array(width * height),
  };
  rows.forEach((row, y) => {
    [...row].forEach((char, x) => {
      const mask = MASK_BY_GLYPH.get(char);
      if (mask) grid.masks[idx(grid, x, y)] = mask;
      else if (char !== BLANK) grid.labelled[idx(grid, x, y)] = char.codePointAt(0) ?? 32;
    });
  });
  return grid;
}

/**
 * Place a rectangle given as percentages of a container into the cell grid.
 *
 * The hero desktop stores window frames as CSS percentages; this keeps the map
 * and the rendered windows reading off the same numbers instead of drifting.
 *
 * Both *edges* are snapped independently rather than snapping the origin and
 * then adding a rounded extent: two windows that share a percentage boundary
 * (a tiled column, a common bottom) then land on the same cell instead of
 * missing each other by one row and rendering as a near-miss.
 */
export function rectFromPercent(
  frame: { left: number; top: number; width: number; height: number },
  area: { x: number; y: number; w: number; h: number },
  extras: { label?: string; z?: number } = {},
): BoxRect {
  const maxX = area.x + area.w - 1;
  const maxY = area.y + area.h - 1;

  const snap = (percent: number, origin: number, span: number, limit: number) =>
    Math.min(limit, Math.max(origin, origin + Math.round((percent / 100) * (span - 1))));

  let x0 = snap(frame.left, area.x, area.w, maxX);
  let y0 = snap(frame.top, area.y, area.h, maxY);
  const x1 = Math.max(x0 + 1, snap(frame.left + frame.width, area.x, area.w, maxX));
  const y1 = Math.max(y0 + 1, snap(frame.top + frame.height, area.y, area.h, maxY));
  x0 = Math.min(x0, x1 - 1);
  y0 = Math.min(y0, y1 - 1);

  return { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1, ...extras };
}
