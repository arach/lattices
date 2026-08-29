/**
 * Geometry checks for the box-drawing renderer. Run with `bun test` from
 * `apps/site` (or `bun test src/lib/asciiBoxMap.test.ts` for just this file).
 */
import { describe, expect, test } from "bun:test";

import { assertBoxGrid, buildBoxGrid, gridToText, parseBoxMap, validateBoxGrid } from "./asciiBoxMap";
import { heroDesktopGrids, heroDesktopMaps } from "../components/heroDesktopMap";

const rowsOf = (text: string) => text.split("\n");

/** Build, assert continuity, and render — the same path the hero map takes. */
const render = (rects: Parameters<typeof buildBoxGrid>[0], w: number, h: number) =>
  gridToText(assertBoxGrid(buildBoxGrid(rects, w, h), "test map"));

describe("box grid rendering", () => {
  test("draws a lone rectangle with the four corner glyphs", () => {
    expect(render([{ x: 0, y: 0, w: 5, h: 3 }], 5, 3)).toBe(["┌───┐", "│   │", "└───┘"].join("\n"));
  });

  test("resolves a vertical edge crossing a horizontal edge as ┼", () => {
    // A tall box straddles a wide box, so both of the wide box's horizontal
    // edges are pierced twice.
    const text = render(
      [
        { x: 0, y: 1, w: 7, h: 3 },
        { x: 2, y: 0, w: 3, h: 5 },
      ],
      7,
      5,
    );
    expect(rowsOf(text)).toEqual(["  ┌─┐  ", "┌─┼─┼─┐", "│ │ │ │", "└─┼─┼─┘", "  └─┘  "]);
  });

  test("resolves a box hanging below another box's edge as ┬", () => {
    const text = render(
      [
        { x: 0, y: 0, w: 7, h: 3 },
        { x: 2, y: 2, w: 3, h: 3 },
      ],
      7,
      5,
    );
    expect(rowsOf(text)).toEqual(["┌─────┐", "│     │", "└─┬─┬─┘", "  │ │  ", "  └─┘  "]);
  });

  test("resolves a box sitting above another box's edge as ┴", () => {
    const text = render(
      [
        { x: 0, y: 2, w: 7, h: 3 },
        { x: 2, y: 0, w: 3, h: 3 },
      ],
      7,
      5,
    );
    expect(rowsOf(text)).toEqual(["  ┌─┐  ", "  │ │  ", "┌─┴─┴─┐", "│     │", "└─────┘"]);
  });

  test("keeps a stacked column joined with ├ and ┤", () => {
    const text = render(
      [
        { x: 0, y: 0, w: 6, h: 3 },
        { x: 0, y: 2, w: 6, h: 3 },
      ],
      6,
      5,
    );
    expect(rowsOf(text)[2]).toBe("├────┤");
  });

  test("refuses a grid that is not continuous", () => {
    const grid = buildBoxGrid([{ x: 0, y: 0, w: 4, h: 3 }], 4, 3);
    // Sever the top edge by hand; the validator must notice both sides.
    grid.masks[1] = 0;
    expect(validateBoxGrid(grid).length).toBeGreaterThan(0);
    expect(() => render([{ x: 0, y: 0, w: 1, h: 3 }], 4, 3)).toThrow();
  });

  test("labels occlude the top edge without disturbing the geometry", () => {
    const grid = buildBoxGrid([{ x: 0, y: 0, w: 12, h: 3, label: "atlas" }], 12, 3);
    expect(validateBoxGrid(grid)).toEqual([]);
    expect(rowsOf(gridToText(grid))[0]).toBe("┌atlas─────┐");
  });

  test("clips a label that cannot fit inside its box", () => {
    const grid = buildBoxGrid([{ x: 0, y: 0, w: 6, h: 3, label: "far too long" }], 6, 3);
    expect(rowsOf(gridToText(grid))[0]).toBe("┌far─┐");
    expect(validateBoxGrid(grid)).toEqual([]);
  });
});

describe("hero desktop maps", () => {
  for (const [phase, text] of Object.entries(heroDesktopMaps)) {
    test(`${phase}: every row is the same width`, () => {
      const rows = rowsOf(text);
      const widths = new Set(rows.map((row) => [...row].length));
      expect([...widths]).toHaveLength(1);
    });

    test(`${phase}: every junction connects to a neighbour that connects back`, () => {
      expect(validateBoxGrid(heroDesktopGrids[phase as keyof typeof heroDesktopGrids])).toEqual([]);
    });

    test(`${phase}: the rendered text re-parses to the same continuous geometry`, () => {
      // Reading the shipped string back proves the glyph table round-trips —
      // no junction is drawn as a character that means something else.
      const problems = validateBoxGrid(parseBoxMap(text)).filter(
        // The display caption opens with a space, which reads as blank on the
        // way back in; every other cell must still connect.
        (p) => !(p.y === 0 && p.x <= 1),
      );
      expect(problems).toEqual([]);
    });

    test(`${phase}: the display frame is closed on all four sides`, () => {
      const rows = rowsOf(text);
      const last = rows.length - 1;
      const width = [...rows[0]].length;
      expect(rows[0][0]).toBe("┌");
      expect(rows[0][width - 1]).toBe("┐");
      expect(rows[last][0]).toBe("└");
      expect(rows[last][width - 1]).toBe("┘");
      expect(rows[last]).toBe(`└${"─".repeat(width - 2)}┘`);
      for (const row of rows.slice(1, last)) {
        expect(row[0]).toBe("│");
        expect(row[width - 1]).toBe("│");
      }
    });
  }
});
