// The Mac LayerLayout algorithm, in display-relative fractions.
import type { Fractions } from "./placement.ts";

export function layoutKind(name: unknown): string | null {
  if (name == null || name === "none" || name === "") return null;
  const aliases: Record<string, string> = { auto: "auto", smart: "auto", columns: "columns", cols: "columns", "master-stack": "master-stack", master: "master-stack", main: "master-stack" };
  const kind = typeof name === "string" && aliases[name.toLowerCase()];
  if (!kind) throw new Error(`Unknown layout: ${String(name)}`);
  return kind;
}

function lane(app: string): number {
  if (/ghostty|kitty|alacritty|foot|wezterm|terminal|konsole|slack|discord|telegram|signal/i.test(app)) return 0;
  if (/code|cursor|zed|neovim|sublime|idea|jetbrains|emacs|figma|inkscape|gimp|blender/i.test(app)) return 1;
  return 2;
}

export function layoutFrames(kind: string, apps: string[], aspect: number): Fractions[] {
  const whole = { x: 0, y: 0, w: 1, h: 1 };
  const wide = aspect >= 2;
  if (!apps.length) return [];
  if (apps.length === 1) return [wide ? { x: .25, y: 0, w: .5, h: 1 } : whole];
  const frames = apps.map(() => ({ ...whole }));
  const all = apps.map((_, i) => i);
  function stack(ids: number[], area: Fractions) {
    const rows = ids.length <= 3 ? ids.length : Math.ceil(ids.length / 2);
    ids.forEach((id, i) => {
      const grid = ids.length > 3;
      const alone = grid && i % 2 === 0 && i === ids.length - 1;
      frames[id] = { x: area.x + (grid ? i % 2 * area.w / 2 : 0), y: area.y + (grid ? Math.floor(i / 2) : i) * area.h / rows, w: grid && !alone ? area.w / 2 : area.w, h: area.h / rows };
    });
  }
  function columns(ids: number[], count: number) {
    count = Math.min(count, ids.length);
    let next = 0;
    for (let col = 0; col < count; col++) {
      const size = Math.floor(ids.length / count) + Number(col < ids.length % count);
      stack(ids.slice(next, next + size), { x: col / count, y: 0, w: 1 / count, h: 1 });
      next += size;
    }
  }
  if (kind === "columns") columns(all, wide ? 4 : 3);
  else if (kind === "master-stack") {
    frames[0] = { x: 0, y: 0, w: .62, h: 1 };
    stack(all.slice(1), { x: .62, y: 0, w: .38, h: 1 });
  } else {
    const lanes = [0, 1, 2].map(l => all.filter(i => lane(apps[i]) === l)).filter(ids => ids.length);
    if (!wide) {
      const main = all.find(i => lane(apps[i]) === 1) ?? lanes[0][0];
      frames[main] = { x: 0, y: 0, w: .5, h: 1 };
      stack(lanes.flat().filter(i => i !== main), { x: .5, y: 0, w: .5, h: 1 });
    } else if (lanes.length === 1) columns(lanes[0], 4);
    else {
      let x = 0;
      lanes.forEach((ids, i) => {
        const w = lanes.length === 2 ? .5 : [.3, .4, .3][i];
        stack(ids, { x, y: 0, w, h: 1 }); x += w;
      });
    }
  }
  return frames;
}
