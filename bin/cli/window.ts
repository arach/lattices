// `lattices window move` / `lattices window place` — CLI front-ends for the
// daemon's canonical window movement APIs (window.move / window.place).
//
// The CLI exposes slots: named positions and grid placements. Fractional typed
// placements stay available through the raw API (`lattices call window.place`).

/** Named placement slots, mirroring the daemon's TilePosition catalog. */
export const NAMED_PLACEMENTS = [
  "maximize", "center",
  "left", "right", "top", "bottom",
  "top-left", "top-right", "bottom-left", "bottom-right",
  "left-third", "center-third", "right-third",
  "top-third", "middle-third", "bottom-third",
  "top-left-third", "top-center-third", "top-right-third",
  "bottom-left-third", "bottom-center-third", "bottom-right-third",
  "first-fourth", "second-fourth", "third-fourth", "last-fourth",
  "top-first-fourth", "top-second-fourth", "top-third-fourth", "top-last-fourth",
  "bottom-first-fourth", "bottom-second-fourth", "bottom-third-fourth", "bottom-last-fourth",
  "left-quarter", "right-quarter", "top-quarter", "bottom-quarter",
] as const;

const PLACEMENT_ALIASES: Record<string, string> = {
  "max": "maximize",
  "left-half": "left",
  "right-half": "right",
  "top-half": "top",
  "bottom-half": "bottom",
  "upper-third": "top-third",
  "lower-third": "bottom-third",
};

const GRID_WIRE = /^grid:\d+x\d+:\d+,\d+(?:-\d+,\d+)?$/u;   // 0-based API form
const GRID_COMPACT = /^\d+x\d+:\d+,\d+(?:-\d+,\d+)?$/u;      // 1-based human form
const GRID_SHORTHAND = /^grid:\d+\.\d+$/u;                    // grid:N.K row-major

/**
 * Canonicalize a CLI placement token to what the daemon accepts, or return
 * undefined when the token is not a known slot.
 */
export function normalizePlacement(input: string): string | undefined {
  const token = input.trim().toLowerCase().replace(/[_\s]+/gu, "-");
  if ((NAMED_PLACEMENTS as readonly string[]).includes(token)) return token;
  const alias = PLACEMENT_ALIASES[token];
  if (alias) return alias;
  if (GRID_WIRE.test(token) || GRID_COMPACT.test(token) || GRID_SHORTHAND.test(token)) return token;
  return undefined;
}

export function placementSlotsHelp(): string {
  return `Slots:
  Named   ${NAMED_PLACEMENTS.slice(0, 10).join(", ")},
          ${NAMED_PLACEMENTS.slice(10, 22).join(", ")},
          ${NAMED_PLACEMENTS.slice(22, 30).join(", ")},
          ${NAMED_PLACEMENTS.slice(30).join(", ")}
  Grid    grid:CxR:c,r (0-based)   CxR:c,r (1-based)   grid:CxR:c0,r0-c1,r1 (span)   grid:N.K (N×N cell K)
  Fractional placements stay available via: lattices call window.place '{"wid":123,"placement":{"kind":"fractions","x":0.5,"y":0,"w":0.5,"h":1}}'`;
}

export type WindowMoveArgs = {
  wid: number;
  display?: number;
  placement?: string;
  json: boolean;
  dryRun: boolean;
};

/** Parse `--flag value` and `--flag=value` forms. Throws on malformed input. */
function parseFlags(args: string[]): { flags: Map<string, string | true>; positional: string[] } {
  const flags = new Map<string, string | true>();
  const positional: string[] = [];
  for (let index = 0; index < args.length; index++) {
    const argument = args[index]!;
    if (!argument.startsWith("--")) {
      positional.push(argument);
      continue;
    }
    const match = argument.match(/^--([^=]+)(?:=(.*))?$/u);
    if (!match) throw new Error(`Unknown option: ${argument}`);
    const name = match[1]!;
    if (match[2] !== undefined) {
      flags.set(name, match[2]);
      continue;
    }
    if (name === "json" || name === "dry-run") {
      flags.set(name, true);
      continue;
    }
    const next = args[index + 1];
    if (next === undefined || next.startsWith("--")) {
      throw new Error(`--${name} expects a value`);
    }
    flags.set(name, next);
    index++;
  }
  return { flags, positional };
}

/**
 * A window id must be an explicit positive integer. A malformed wid is an
 * error — it must never fall back to the frontmost window.
 */
function parseWid(raw: string | undefined): number {
  if (raw === undefined) throw new Error("A window id is required. Find one with: lattices map");
  if (!/^\d+$/u.test(raw)) throw new Error(`Invalid window id: ${raw} (expected a positive integer wid)`);
  const wid = Number(raw);
  if (wid <= 0 || !Number.isSafeInteger(wid)) {
    throw new Error(`Invalid window id: ${raw} (expected a positive integer wid)`);
  }
  return wid;
}

function parseDisplay(value: string | true | undefined): number | undefined {
  if (value === undefined) return undefined;
  if (value === true || !/^\d+$/u.test(value)) {
    throw new Error(`--display expects a non-negative display index`);
  }
  return Number(value);
}

function parsePlacementFlag(value: string | true | undefined): string | undefined {
  if (value === undefined) return undefined;
  if (value === true) throw new Error("--placement expects a slot name");
  const normalized = normalizePlacement(value);
  if (!normalized) {
    throw new Error(`Unknown placement slot: ${value}\n${placementSlotsHelp()}`);
  }
  return normalized;
}

export function parseWindowMoveArgs(args: string[]): WindowMoveArgs {
  const { flags, positional } = parseFlags(args);
  for (const name of flags.keys()) {
    if (!["display", "placement", "json", "dry-run"].includes(name)) {
      throw new Error(`Unknown option: --${name}`);
    }
  }
  if (positional.length > 1) throw new Error(`Unexpected argument: ${positional[1]}`);
  const wid = parseWid(positional[0]);
  const display = parseDisplay(flags.get("display"));
  const placement = parsePlacementFlag(flags.get("placement"));
  if (display === undefined && placement === undefined) {
    throw new Error("window move requires --display <n> and/or --placement <slot>");
  }
  return {
    wid,
    display,
    placement,
    json: flags.get("json") === true,
    dryRun: flags.get("dry-run") === true,
  };
}

export function parseWindowPlaceArgs(args: string[]): WindowMoveArgs {
  const { flags, positional } = parseFlags(args);
  for (const name of flags.keys()) {
    if (!["display", "json", "dry-run"].includes(name)) {
      throw new Error(`Unknown option: --${name}`);
    }
  }
  if (positional.length > 2) throw new Error(`Unexpected argument: ${positional[2]}`);
  const wid = parseWid(positional[0]);
  const rawSlot = positional[1];
  if (rawSlot === undefined) {
    throw new Error(`window place requires a slot.\n${placementSlotsHelp()}`);
  }
  const placement = normalizePlacement(rawSlot);
  if (!placement) {
    throw new Error(`Unknown placement slot: ${rawSlot}\n${placementSlotsHelp()}`);
  }
  return {
    wid,
    display: parseDisplay(flags.get("display")),
    placement,
    json: flags.get("json") === true,
    dryRun: flags.get("dry-run") === true,
  };
}

export function windowMoveUsage(): string {
  return `Usage:
  lattices window move <wid> --display <n> [--placement <slot>] [--dry-run] [--json]
  lattices window place <wid> <slot> [--display <n>] [--dry-run] [--json]

Move a specific window (CGWindowID) to another display and/or placement slot.
--display alone preserves the window's normalized size/position on the target
display. Adding a placement snaps it into that slot instead.

${placementSlotsHelp()}

Find wids with: lattices map  ·  lattices windows --json  ·  lattices search <q> --wid`;
}

type FrameJSON = { x?: number; y?: number; w?: number; h?: number };

function formatFrame(frame: FrameJSON | undefined): string {
  if (!frame) return "?";
  const round = (value: number | undefined) => (value === undefined ? "?" : Math.round(value));
  return `${round(frame.w)}×${round(frame.h)} @ ${round(frame.x)},${round(frame.y)}`;
}

/** Render an execution receipt from window.move / window.place for humans. */
export function describeMoveReceipt(receipt: any): string {
  const lines: string[] = [];
  const status = receipt?.status ?? (receipt?.ok ? "ok" : "failed");
  const app = receipt?.app ? ` ${receipt.app}` : "";
  const wid = receipt?.wid !== undefined ? ` (wid:${receipt.wid})` : "";
  const displayName = receipt?.display?.name ? ` on ${receipt.display.name}` : "";
  const mutation = receipt?.mutations?.[0];
  const before = mutation?.from as FrameJSON | undefined;
  const target = mutation?.to as FrameJSON | undefined;
  const after = mutation?.after as FrameJSON | undefined;

  if (status === "planned") {
    lines.push(`Planned${app}${wid}${displayName}: ${formatFrame(before)} → ${formatFrame(target)} (dry run, not executed)`);
  } else if (status === "ok") {
    lines.push(`Moved${app}${wid}${displayName}: ${formatFrame(before)} → ${formatFrame(after ?? target)}${receipt?.verified ? " · verified" : ""}`);
  } else if (status === "blocked") {
    lines.push(`Blocked${app}${wid}: ${receipt?.blockedReason ?? "unknown reason"}`);
    if (Array.isArray(receipt?.requiredPermissions) && receipt.requiredPermissions.length) {
      lines.push(`  Grant: ${receipt.requiredPermissions.join(", ")} (System Settings → Privacy & Security)`);
    }
  } else {
    lines.push(`Move did not verify${app}${wid}${displayName}: wanted ${formatFrame(target)}, saw ${formatFrame(after)}`);
  }
  if (receipt?.receiptId) lines.push(`  receipt ${receipt.receiptId} · undo with: lattices call action.undo '{}'`);
  return lines.join("\n");
}

type DaemonCallFn = (method: string, params?: Record<string, unknown> | null) => Promise<unknown>;

/** Execute already-parsed move/place args against the daemon. */
export async function runWindowMovement(
  method: "move" | "place",
  parsed: WindowMoveArgs,
  daemonCall: DaemonCallFn,
): Promise<void> {
  const params: Record<string, unknown> = { wid: parsed.wid };
  if (parsed.placement !== undefined) params.placement = parsed.placement;
  if (parsed.display !== undefined) params.display = parsed.display;
  if (parsed.dryRun) params.dryRun = true;
  const receipt = await daemonCall(method === "move" ? "window.move" : "window.place", params);
  if (parsed.json) {
    console.log(JSON.stringify(receipt, null, 2));
    return;
  }
  console.log(describeMoveReceipt(receipt));
}
