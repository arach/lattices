import { describe, expect, test } from "bun:test";
import type { HyprMonitor } from "../src/hyprland.ts";
import { bringCursorHome, monitorCentre, parseLanMouseClients, pickHomeMonitor, releasePointer, sharePointer, type MouseDependencies } from "../src/mouse.ts";
import { Router } from "../src/router.ts";
import { registerEndpoints } from "../src/endpoints.ts";

const monitor = (over: Partial<HyprMonitor> = {}): HyprMonitor => ({
  id: 1, name: "HDMI-A-1", description: "Dell", x: 1920, y: 0,
  width: 3440, height: 1440, scale: 1, transform: 0, reserved: [0, 24, 0, 0],
  activeWorkspace: { id: 1, name: "1" }, focused: true, ...over,
});
const listing = "id 0: mini:4242 (left) active: true, ips: {100.123.16.74, 192.168.18.14}\n";

describe("home monitor", () => {
  test("focused virtual output never wins over the Dell", () => {
    const dell = monitor({ focused: false });
    expect(pickHomeMonitor([monitor({ name: "LATS-1", x: 0, description: "" }), dell])).toBe(dell);
    expect(monitorCentre(dell)).toEqual({ x: 3640, y: 720 });
  });
  test("prefers focused real monitor, otherwise first real monitor", () => {
    const first = monitor({ focused: false });
    const focused = monitor({ name: "DP-1" });
    expect(pickHomeMonitor([first, focused])).toBe(focused);
    expect(pickHomeMonitor([first, monitor({ focused: false })])).toBe(first);
  });
  test("skips headless, disabled and mirrored outputs; refuses virtual-only layouts", () => {
    const dell = monitor();
    expect(pickHomeMonitor([
      monitor({ name: "HEADLESS-1" }), { ...monitor(), disabled: true },
      { ...monitor(), mirrorOf: "DP-1" }, { ...monitor({ description: "" }), physicalWidth: 0, physicalHeight: 0 }, dell,
    ])).toBe(dell);
    expect(() => pickHomeMonitor([monitor({ name: "LATS-1" })])).toThrow("No real monitor");
    expect(() => pickHomeMonitor([])).toThrow("No real monitor");
  });
  test("uses logical coordinates on scaled, rotated and negative-position monitors", () => {
    expect(monitorCentre(monitor({ x: -1920, y: -100, width: 3840, height: 2160, scale: 2 }))).toEqual({ x: -960, y: 440 });
    expect(monitorCentre(monitor({ x: 0, width: 1920, height: 1080, transform: 1 }))).toEqual({ x: 540, y: 960 });
  });
});

describe("lan-mouse CLI parsing", () => {
  test("parses multiple clients, IPv6 and large IDs without losing precision", () => {
    expect(parseLanMouseClients(listing + "id 18446744073709551615: fe80::1:4242 (right) active: false, ips: {}\r\n")).toEqual([
      { id: "0", host: "mini", position: "left", active: true },
      { id: "18446744073709551615", host: "fe80::1", position: "right", active: false },
    ]);
  });
  test("empty list is valid; malformed and duplicate IDs are refused", () => {
    expect(parseLanMouseClients("\n ")).toEqual([]);
    expect(() => parseLanMouseClients("could not connect")).toThrow();
    expect(() => parseLanMouseClients(listing.replace("active: true", "active: unknown"))).toThrow();
    expect(() => parseLanMouseClients(listing + listing)).toThrow("Duplicate");
  });
});

function fake(over: Partial<MouseDependencies> = {}) {
  const calls: string[][] = [];
  let restarts = 0;
  const deps: MouseDependencies = {
    hasLanMouse: () => true,
    serviceState: async () => "active",
    startService: async () => {},
    trial: { arm: async () => {}, cancel: async () => {}, until: async () => null },
    sleep: async () => {},
    log: () => {},
    restartService: async () => { restarts++; },
    run: async (cmd, args, options) => {
      calls.push([cmd, ...args]);
      expect(options?.timeoutMs).toBeGreaterThan(0);
      if (cmd === "lan-mouse") return args[1] === "list" ? listing : "";
      if (args[0] === "monitors") return JSON.stringify([monitor({ name: "LATS-1", description: "" }), monitor()]);
      return "ok\n";
    },
    ...over,
  };
  return { deps, calls, restarts: () => restarts };
}

describe("pointer recovery", () => {
  test("deactivates every client before warping, including inactive clients", async () => {
    const { deps, calls, restarts } = fake();
    const base = deps.run;
    deps.run = async (cmd, args, options) => args[1] === "list" ? listing + "id 2: other:4242 (top) active: false, ips: {}\n" : base(cmd, args, options);
    const result = await bringCursorHome(deps);
    expect(result).toMatchObject({ ok: true, monitor: "HDMI-A-1", x: 3640, y: 720 });
    expect(result.release.released.sort()).toEqual(["0", "2"]);
    expect(calls.slice(0, 2)).toEqual([["lan-mouse", "cli", "deactivate", "0"], ["lan-mouse", "cli", "deactivate", "2"]]);
    expect(calls.at(-1)).toEqual(["hyprctl", "dispatch", "movecursor", "3640", "720"]);
    expect(restarts()).toBe(0);
  });
  test("absent binary only warps", async () => {
    const { deps, calls, restarts } = fake({ hasLanMouse: () => false });
    await bringCursorHome(deps);
    expect(calls.every(([cmd]) => cmd === "hyprctl")).toBe(true);
    expect(restarts()).toBe(0);
  });
  test("stopped daemon stays stopped and still warps", async () => {
    const { deps, restarts } = fake({ serviceState: async () => "inactive" });
    const base = deps.run;
    deps.run = (cmd, args, options) => cmd === "lan-mouse" ? Promise.reject(new Error("could not connect")) : base(cmd, args, options);
    expect((await bringCursorHome(deps)).ok).toBe(true);
    expect(restarts()).toBe(0);
  });
  test("unreachable running daemon gets one restart and releases startup clients", async () => {
    const { deps, restarts } = fake();
    const base = deps.run;
    let lists = 0;
    deps.run = (cmd, args, options) => cmd === "lan-mouse" && args[1] === "list" && lists++ === 0
      ? Promise.reject(new Error("timed out")) : base(cmd, args, options);
    const result = await bringCursorHome(deps);
    expect(result.release).toMatchObject({ restarted: true, released: ["0"], errors: [] });
    expect(restarts()).toBe(1);
  });
  test("release or fallback errors still warp; responsive daemon is never restarted", async () => {
    const { deps, restarts } = fake();
    const base = deps.run;
    deps.run = (cmd, args, options) => args[1] === "deactivate" ? Promise.reject(new Error("NoSuchClient")) : base(cmd, args, options);
    expect((await bringCursorHome(deps)).release.errors).toHaveLength(1);
    expect(restarts()).toBe(0);
    deps.run = (cmd, args, options) => cmd === "lan-mouse" ? Promise.reject(new Error("hung")) : base(cmd, args, options);
    deps.restartService = async () => { throw new Error("systemd unavailable"); };
    expect((await bringCursorHome(deps)).ok).toBe(true);
  });
  test("malformed list does not trigger a restart", async () => {
    const { deps, restarts } = fake();
    deps.run = async () => "changed format";
    expect((await releasePointer(deps)).errors).toHaveLength(1);
    expect(restarts()).toBe(0);
  });
  test("Hyprland Lua fallback handles legacy dispatch rejection", async () => {
    const { deps, calls } = fake();
    const base = deps.run;
    deps.run = (cmd, args, options) => args[1] === "movecursor" ? Promise.reject(new Error("unknown dispatcher")) : base(cmd, args, options);
    await bringCursorHome(deps);
    expect(calls.at(-1)).toEqual(["hyprctl", "dispatch", "hl.dsp.cursor.move({ x = 3640, y = 720 })"]);
  });
  test("Share Pointer changes all clients through the CLI", async () => {
    const { deps, calls } = fake();
    let armed = false;
    deps.trial = { arm: async () => { armed = true; }, cancel: async () => { armed = false; }, until: async () => armed ? "2026-10-09T21:00:00.000Z" : null };
    await sharePointer(true, deps);
    expect(calls).toContainEqual(["lan-mouse", "cli", "activate", "0"]);
    await sharePointer(false, deps);
    expect(calls).toContainEqual(["lan-mouse", "cli", "deactivate", "0"]);
  });
  test("mouse.home is a discoverable mutation on Hyprland hosts", () => {
    const router = new Router(() => new Set(["spaces.read"]));
    registerEndpoints(router, { bindHost: "127.0.0.1", startedAt: Date.now(), clientCount: () => 0 });
    expect(router.available().find((entry) => entry.method === "mouse.home")?.access).toBe("mutate");
  });
});
