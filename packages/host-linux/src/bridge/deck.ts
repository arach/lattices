// The deck a Linux host shows the iOS companion: DeckKit's manifest, runtime
// snapshot, actions, trackpad and preview (swift/Sources/DeckKit), filled from
// Hyprland. Field names and optionality follow the Swift Codable types, since
// the app's synthesized decoders reject anything missing.

import { readdirSync, readFileSync } from "node:fs";
import { hostname } from "node:os";
import * as capture from "../capture.ts";
import * as desktop from "../desktop.ts";
import * as hypr from "../hyprland.ts";
import * as input from "../input.ts";
import { parsePlacement } from "../placement.ts";
import * as tmux from "../tmux.ts";
import { PointerSession } from "../wayland.ts";

/** Swift's default JSONEncoder date: seconds since 2001-01-01T00:00:00Z. */
export const swiftDate = (d = new Date()) => d.getTime() / 1000 - 978_307_200;

type DeckValue = null | boolean | number | string | DeckValue[] | { [key: string]: DeckValue };

export interface DeckActionRequest {
  pageID?: string | null;
  actionID: string;
  payload?: Record<string, DeckValue>;
}

const itemID = (wid: number) => `window:${wid}`;
const widFromItem = (id: string) => {
  const match = /^window:(\d+)$/.exec(id);
  return match ? Number(match[1]) : undefined;
};

export function manifest(name: string) {
  return {
    product: { id: "dev.lattices.host.linux", displayName: name, owner: "lattices" },
    security: { mode: "standalone", pairingStrategy: "bonjour", requestSigningRequired: true, payloadEncryptionRequired: true },
    capabilities: ["trackpadProxy", "layoutControl", "appSwitching", "screenPreview", "systemTelemetry", "spaces", "keyboardForwarding"],
    pages: [
      { id: "command", title: "Command", iconSystemName: "circle.grid.2x2.fill", kind: "cockpit", accentToken: "lattices-cockpit", deckID: "command" },
      { id: "windows", title: "Windows", iconSystemName: "rectangle.3.group.fill", kind: "layout", accentToken: "lattices-layout", deckID: "windows" },
      { id: "dev", title: "Switch", iconSystemName: "terminal.fill", kind: "switch", accentToken: "lattices-dev", deckID: "dev" },
    ],
  };
}

const PLACEMENT_TILES: [string, string, string][] = [
  ["left", "Left", "rectangle.lefthalf.inset.filled"],
  ["right", "Right", "rectangle.righthalf.inset.filled"],
  ["maximize", "Maximize", "rectangle.inset.filled"],
  ["center", "Center", "rectangle.center.inset.filled"],
  ["top-left", "Top Left", "rectangle.inset.topleft.filled"],
  ["top-right", "Top Right", "rectangle.inset.topright.filled"],
  ["bottom-left", "Bottom Left", "rectangle.inset.bottomleft.filled"],
  ["bottom-right", "Bottom Right", "rectangle.inset.bottomright.filled"],
];

function cockpit() {
  return {
    title: "Windows",
    detail: "Place the focused window",
    pages: [
      {
        id: "command",
        title: "Place",
        subtitle: "Focused window",
        columns: 4,
        rows: 2,
        tiles: PLACEMENT_TILES.map(([placement, title, icon]) => ({
          id: `place.${placement}`,
          shortcutID: `place.${placement}`,
          title,
          iconSystemName: icon,
          accentToken: "lattices-layout",
          actionID: "layout.placeFrontmost",
          payload: { placement },
          isEnabled: true,
          isActive: false,
        })),
      },
    ],
  };
}

// CPU load from /proc/stat deltas between snapshots.
let lastCpu: { idle: number; total: number } | null = null;
function cpuLoadPercent(): number | null {
  try {
    const fields = readFileSync("/proc/stat", "utf8").split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
    const idle = fields[3] + (fields[4] ?? 0);
    const total = fields.reduce((a, b) => a + b, 0);
    const prev = lastCpu;
    lastCpu = { idle, total };
    if (!prev || total === prev.total) return null;
    return Math.round((1 - (idle - prev.idle) / (total - prev.total)) * 1000) / 10;
  } catch {
    return null;
  }
}

function memoryUsedPercent(): number | null {
  try {
    const info = Object.fromEntries(
      readFileSync("/proc/meminfo", "utf8").split("\n").filter(Boolean).map((l) => {
        const [k, v] = l.split(":");
        return [k, Number.parseInt(v, 10)];
      })
    );
    return Math.round((1 - info.MemAvailable / info.MemTotal) * 1000) / 10;
  } catch {
    return null;
  }
}

function battery(): { percent: number; charging: boolean } | null {
  try {
    const bat = readdirSync("/sys/class/power_supply").find((d) => d.startsWith("BAT"));
    if (!bat) return null;
    const base = `/sys/class/power_supply/${bat}`;
    return {
      percent: Number(readFileSync(`${base}/capacity`, "utf8")),
      charging: readFileSync(`${base}/status`, "utf8").trim() === "Charging",
    };
  } catch {
    return null;
  }
}

export async function runtimeSnapshot(trackpadAvailable: boolean, hasTmux: boolean) {
  const snap = await desktop.snapshot();
  const [cursor, sessions] = await Promise.all([hypr.cursorPos().catch(() => null), hasTmux ? tmux.listSessions().catch(() => []) : []]);
  const extent = input.layoutExtent(snap.displays);
  const front = snap.windows.find((w) => w.isFocused) ?? null;
  const frontDisplay = front ? snap.displays[front.displayIndex] : snap.displays[0];
  const focusedMonitor = snap.monitors.find((m) => m.focused)?.name;
  const currentDisplay = snap.displays.find((d) => d.displayId === focusedMonitor) ?? snap.displays[0];
  const currentSpace = currentDisplay?.spaces.find((s) => s.isCurrent);
  const visible = snap.windows.filter((w) => w.isOnScreen);
  const normalize = (f: { x: number; y: number; w: number; h: number }) => ({
    x: (f.x - extent.x) / extent.w,
    y: (f.y - extent.y) / extent.h,
    w: f.w / extent.w,
    h: f.h / extent.h,
  });
  const pointerDisplay = cursor
    ? snap.displays.find((d) => cursor.x >= d.frame.x && cursor.x < d.frame.x + d.frame.w && cursor.y >= d.frame.y && cursor.y < d.frame.y + d.frame.h)
    : undefined;
  const bat = battery();

  return {
    updatedAt: swiftDate(),
    cockpit: cockpit(),
    trackpad: {
      isEnabled: true,
      isAvailable: trackpadAvailable,
      statusTitle: trackpadAvailable ? "Trackpad Ready" : "Pointer Unavailable",
      statusDetail: trackpadAvailable
        ? `Move, scroll, click, and drag on ${hostname()} from this surface.`
        : "This compositor does not offer the Wayland virtual pointer protocol.",
      pointerScale: 1.6,
      scrollScale: 1.0,
      supportsDragLock: true,
      pointerX: cursor ? (cursor.x - extent.x) / extent.w : null,
      pointerY: cursor ? (cursor.y - extent.y) / extent.h : null,
      pointerDisplayIndex: pointerDisplay?.displayIndex ?? null,
      displayCount: snap.displays.length,
    },
    desktop: {
      activeLayerName: null,
      activeAppName: front?.app ?? null,
      screenCount: snap.displays.length,
      visibleWindowCount: visible.length,
      sessionCount: sessions.length,
      currentSpaceIndex: currentSpace?.index ?? null,
      currentSpaceName: currentSpace?.name ?? null,
    },
    layout: {
      screenName: frontDisplay?.name ?? null,
      frontmostWindow: front
        ? {
            id: String(front.wid),
            itemID: itemID(front.wid),
            appName: front.app,
            title: front.title,
            frame: front.frame,
            normalizedFrame: normalize(front.frame),
            placement: null,
          }
        : null,
      preview: {
        aspectRatio: extent.w / extent.h,
        displayCount: snap.displays.length,
        windows: visible.map((w) => ({
          id: String(w.wid),
          itemID: itemID(w.wid),
          title: w.title || w.app,
          subtitle: w.app,
          normalizedFrame: normalize(w.frame),
          isFrontmost: w.isFocused,
          displayIndex: w.displayIndex,
        })),
      },
    },
    switcher: {
      items: snap.windows.map((w) => ({
        id: itemID(w.wid),
        title: w.title || w.app,
        subtitle: w.app,
        kind: "window",
        isFrontmost: w.isFocused,
      })),
    },
    telemetry: {
      sampledAt: swiftDate(),
      cpuLoadPercent: cpuLoadPercent(),
      memoryUsedPercent: memoryUsedPercent(),
      batteryPercent: bat?.percent ?? null,
      isCharging: bat?.charging ?? null,
      powerSource: bat ? (bat.charging ? "AC" : "Battery") : "AC",
      windowCount: snap.windows.length,
      sessionCount: sessions.length,
    },
    spaces: {
      currentSpaceIndex: currentSpace?.index ?? null,
      currentSpaceName: currentSpace?.name ?? null,
      displays: snap.displays.map((d) => {
        const current = d.spaces.find((s) => s.isCurrent);
        return {
          id: d.displayId,
          displayIndex: d.displayIndex,
          currentSpaceID: d.currentSpaceId,
          currentSpaceIndex: current?.index ?? null,
          currentSpaceName: current?.name ?? null,
          spaces: d.spaces.map((s) => ({ id: s.id, index: s.index, name: s.name, isCurrent: s.isCurrent })),
        };
      }),
    },
    history: [],
    questions: [],
  };
}

class Unsupported extends Error {}

async function performAction(request: DeckActionRequest): Promise<{ summary: string; detail?: string }> {
  const payload = request.payload ?? {};
  const str = (k: string) => (typeof payload[k] === "string" ? (payload[k] as string) : undefined);
  const num = (k: string) => (typeof payload[k] === "number" ? (payload[k] as number) : undefined);
  const need = <T>(value: T | undefined, name: string): T => {
    if (value === undefined) throw new Error(`Missing payload field: ${name}`);
    return value;
  };

  switch (request.actionID) {
    case "layout.placeFrontmost": {
      const placement = need(str("placement"), "placement");
      const { window, snap } = await desktop.resolveTarget({});
      await desktop.place(window, parsePlacement(placement), snap.displays[window.displayIndex]);
      return { summary: "Placed the frontmost window", detail: `Applied the ${placement} placement to ${window.app}.` };
    }
    case "switch.focusItem": {
      const wid = widFromItem(need(str("itemID"), "itemID"));
      if (wid === undefined) throw new Error("Unknown switcher item");
      const { window } = await desktop.resolveTarget({ wid });
      await hypr.apply([{ op: "focus", address: window.address }]);
      return { summary: `Focused ${window.app}`, detail: window.title };
    }
    case "keys.send":
    case "key.send": {
      const key = need(str("key"), "key");
      const modifiers = Array.isArray(payload.modifiers) ? payload.modifiers.map(String) : [];
      await input.pressKey(key, modifiers);
      return { summary: `Sent ${[...modifiers, key].join("+")}`, detail: "Forwarded the key chord to the focused window." };
    }
    case "keys.type":
    case "clipboard.pasteFromDevice": {
      const text = need(str("text"), "text");
      if (Buffer.byteLength(text) > 200_000) throw new Error("Text is too large to send");
      await input.typeText(text);
      return { summary: request.actionID === "keys.type" ? "Typed text" : "Pasted from the phone", detail: `Sent ${text.length} characters.` };
    }
    case "window.dragBy": {
      const { window } = await desktop.resolveTarget({});
      const dx = num("dx") ?? 0;
      const dy = num("dy") ?? 0;
      const ops: hypr.Op[] = [];
      if (!window.isFloating) ops.push({ op: "float", address: window.address });
      ops.push({ op: "move", address: window.address, x: window.frame.x + dx, y: window.frame.y + dy });
      await hypr.apply(ops);
      return { summary: `Moved ${window.app}` };
    }
    case "spaces.focusIndex": {
      const index = need(num("index"), "index");
      const snap = await desktop.snapshot();
      const display = snap.displays[num("displayIndex") ?? 0] ?? snap.displays[0];
      const space = display?.spaces.find((s) => s.index === index);
      await hypr.apply([{ op: "focusWorkspace", workspace: space?.id ?? index }]);
      return { summary: `Switched to workspace ${space?.name ?? index}` };
    }
    case "spaces.focusRelative": {
      const direction = (num("direction") ?? 1) > 0 ? 1 : -1;
      const snap = await desktop.snapshot();
      const focusedMonitor = snap.monitors.find((m) => m.focused)?.name;
      const display = snap.displays[num("displayIndex") ?? -1] ?? snap.displays.find((d) => d.displayId === focusedMonitor) ?? snap.displays[0];
      const ids = display.spaces.map((s) => s.id);
      const at = ids.indexOf(display.currentSpaceId);
      const next = ids.length > 0 ? ids[(at + direction + ids.length) % ids.length] : display.currentSpaceId + direction;
      await hypr.apply([{ op: "focusWorkspace", workspace: Math.max(1, next) }]);
      return { summary: `Switched to workspace ${next}` };
    }
    case "displays.focus":
    case "display.focus": {
      const snap = await desktop.snapshot();
      const display = snap.displays[need(num("displayIndex"), "displayIndex")];
      if (!display) throw new Error("Unknown display");
      await hypr.apply([{ op: "focusMonitor", monitor: display.displayId }]);
      return { summary: `Focused ${display.name}` };
    }
    default:
      throw new Unsupported(`${request.actionID} is not available on this Linux host.`);
  }
}

export async function perform(request: DeckActionRequest, snapshot: () => Promise<unknown>) {
  try {
    const outcome = await performAction(request);
    return { ok: true, summary: outcome.summary, detail: outcome.detail ?? null, runtimeSnapshot: await snapshot(), suggestedActions: [] };
  } catch (err) {
    return {
      ok: false,
      summary: err instanceof Unsupported ? "Not available on Linux" : "Action failed",
      detail: (err as Error).message,
      runtimeSnapshot: await snapshot().catch(() => null),
      suggestedActions: [],
    };
  }
}

// ── Trackpad ───────────────────────────────────────────────────────────

export interface TrackpadEvent {
  event: "move" | "click" | "rightClick" | "scroll" | "mouseDown" | "mouseUp" | "drag";
  dx: number;
  dy: number;
}

/** Relative pointer control. A held button keeps one pointer open until mouseUp. */
export class Trackpad {
  private held: PointerSession | null = null;

  async perform(request: TrackpadEvent) {
    const snap = await desktop.snapshot();
    const extent = input.layoutExtent(snap.displays);
    const cursor = await hypr.cursorPos();
    const target = { x: cursor.x + (request.dx || 0), y: cursor.y + (request.dy || 0) };
    let ok = true;
    try {
      switch (request.event) {
        case "move":
          if (this.held) await this.held.move(target.x, target.y, extent);
          else await input.moveCursor(target.x, target.y, extent);
          break;
        case "drag":
          if (!this.held) {
            this.held = await PointerSession.open();
            await this.held.move(cursor.x, cursor.y, extent);
            await this.held.button("left", true);
          }
          await this.held.move(target.x, target.y, extent);
          break;
        case "click":
          await input.click(cursor.x, cursor.y, extent, "left");
          break;
        case "rightClick":
          await input.click(cursor.x, cursor.y, extent, "right");
          break;
        case "scroll":
          await input.scroll(undefined, undefined, request.dx || 0, request.dy || 0, extent);
          break;
        case "mouseDown":
          if (!this.held) {
            this.held = await PointerSession.open();
            await this.held.move(cursor.x, cursor.y, extent);
            await this.held.button("left", true);
          }
          break;
        case "mouseUp":
          if (this.held) {
            await this.held.button("left", false);
            await this.held.close();
            this.held = null;
          }
          break;
        default:
          ok = false;
      }
    } catch {
      ok = false;
    }
    const after = await hypr.cursorPos().catch(() => target);
    const display = snap.displays.find((d) => after.x >= d.frame.x && after.x < d.frame.x + d.frame.w && after.y >= d.frame.y && after.y < d.frame.y + d.frame.h);
    return {
      ok,
      pointerX: (after.x - extent.x) / extent.w,
      pointerY: (after.y - extent.y) / extent.h,
      pointerDisplayIndex: display?.displayIndex ?? null,
    };
  }
}

// ── Preview ────────────────────────────────────────────────────────────

export interface PreviewRequest {
  displayIndex?: number | null;
  maxPixelWidth?: number;
  scope?: "display" | "frontmostWindow";
}

export async function preview(request: PreviewRequest) {
  const snap = await desktop.snapshot();
  const maxWidth = Math.max(160, Math.min(4096, request.maxPixelWidth ?? 1440));
  const focusedMonitor = snap.monitors.find((m) => m.focused)?.name;
  const display =
    (request.displayIndex != null ? snap.displays[request.displayIndex] : undefined) ??
    snap.displays.find((d) => d.displayId === focusedMonitor) ??
    snap.displays[0];
  if (!display) throw new Error("No display to preview");
  const front = snap.windows.find((w) => w.isFocused && w.isOnScreen);
  const useWindow = request.scope === "frontmostWindow" && front;
  const sourceWidth = useWindow ? front.frame.w : display.frame.w * display.scale;
  const bytes = await capture.grab({
    region: useWindow ? front.frame : undefined,
    output: useWindow ? undefined : display.displayId,
    format: "jpeg",
    quality: 70,
    scale: Math.min(1, maxWidth / Math.max(1, sourceWidth)),
  });
  const size = capture.imageSize(bytes) ?? { width: maxWidth, height: Math.round(maxWidth * 0.6) };
  return {
    capturedAt: swiftDate(),
    displayIndex: display.displayIndex,
    displays: snap.displays.map((d) => ({
      displayIndex: d.displayIndex,
      name: d.name,
      pixelWidth: Math.round(d.frame.w * d.scale),
      pixelHeight: Math.round(d.frame.h * d.scale),
    })),
    pixelWidth: size.width,
    pixelHeight: size.height,
    jpegBase64: bytes.toString("base64"),
  };
}

