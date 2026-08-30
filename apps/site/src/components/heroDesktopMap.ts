/**
 * The hero desktop's four windows, in one place.
 *
 * Both surfaces that describe this fictional desktop read from here: the styled
 * window chrome in `LandingPage`, and the `lattices — map` transcript below it.
 * The map used to be a hand-drawn string literal, which is why its outlines and
 * junctions drifted away from the frames they claimed to describe. Now it is
 * rasterised from these same percentages, so the two can no longer disagree.
 */
import {
  assertBoxGrid,
  buildBoxGrid,
  gridToText,
  rectFromPercent,
  type BoxGrid,
  type BoxRect,
} from "../lib/asciiBoxMap";

export type HeroDesktopPhase = "messy" | "organized";
export type HeroWindowId = "agent" | "editor" | "browser" | "terminal";

export type HeroWindowLayout = {
  left: number;
  top: number;
  width: number;
  height: number;
  z: number;
};

export const heroWindowLayouts: Record<HeroWindowId, Record<HeroDesktopPhase, HeroWindowLayout>> = {
  agent: {
    messy: { left: 18, top: 22, width: 49, height: 56, z: 6 },
    organized: { left: 1.6, top: 10.5, width: 58, height: 86, z: 6 },
  },
  editor: {
    messy: { left: 6, top: 14, width: 35, height: 29, z: 3 },
    organized: { left: 61, top: 10.5, width: 37.4, height: 28, z: 3 },
  },
  browser: {
    messy: { left: 54, top: 11, width: 41, height: 42, z: 2 },
    organized: { left: 61, top: 41.5, width: 37.4, height: 32, z: 2 },
  },
  terminal: {
    messy: { left: 46, top: 55, width: 38, height: 29, z: 4 },
    organized: { left: 61, top: 76.5, width: 37.4, height: 20, z: 4 },
  },
};

export const heroWindowMeta: Record<
  HeroWindowId,
  { app: string; title: string; tint: string; focused?: boolean; mapLabel: string }
> = {
  agent: { app: "Terminal", title: "atlas — codex", tint: "#d277ff", focused: true, mapLabel: "1 Terminal · codex" },
  editor: { app: "Code", title: "session.ts — atlas", tint: "#62a0ff", mapLabel: "3 Code · session.ts" },
  browser: { app: "Browser", title: "localhost:5173", tint: "#f3c969", mapLabel: "4 Browser · localhost" },
  terminal: { app: "Terminal", title: "atlas — bun dev", tint: "#34d399", mapLabel: "2 Terminal · bun dev" },
};

/** Character dimensions of the rendered map, including the display border. */
const MAP_WIDTH = 68;
const MAP_HEIGHT = 15;

/** The area inside the display border that windows are placed into. */
const SCREEN_AREA = { x: 1, y: 1, w: MAP_WIDTH - 2, h: MAP_HEIGHT - 2 };

const DISPLAY_LABEL = " Display 0 · MacBook Pro · Space 1";

function buildHeroDesktopGrid(phase: HeroDesktopPhase): BoxGrid {
  const windows = (Object.keys(heroWindowLayouts) as HeroWindowId[]).map((id) => {
    const frame = heroWindowLayouts[id][phase];
    return rectFromPercent(frame, SCREEN_AREA, { label: heroWindowMeta[id].mapLabel, z: frame.z });
  });

  const display: BoxRect = { x: 0, y: 0, w: MAP_WIDTH, h: MAP_HEIGHT, label: DISPLAY_LABEL, z: -1 };

  return assertBoxGrid(buildBoxGrid([display, ...windows], MAP_WIDTH, MAP_HEIGHT), `hero desktop map "${phase}"`);
}

export const heroDesktopGrids: Record<HeroDesktopPhase, BoxGrid> = {
  messy: buildHeroDesktopGrid("messy"),
  organized: buildHeroDesktopGrid("organized"),
};

export const heroDesktopMaps: Record<HeroDesktopPhase, string> = {
  messy: gridToText(heroDesktopGrids.messy),
  organized: gridToText(heroDesktopGrids.organized),
};
