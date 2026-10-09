import { expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, rmSync } from "node:fs";
import { createServer, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { initialEventHealth, subscribeEvents, type EventStreamHealth } from "../src/hyprland-events.ts";
import { probeCapabilities, capabilities, capabilityHealth, updateEventHealth } from "../src/host-capabilities.ts";
import { registerEndpoints } from "../src/endpoints.ts";
import { Router } from "../src/router.ts";

const globals = ["wl_seat", "zwlr_screencopy_manager_v1", "zwp_virtual_keyboard_manager_v1", "zwlr_virtual_pointer_manager_v1"];
const probes = { command: () => true, desktop: async () => ({}), wayland: async () => globals };

// Test-only deadline. Production recovery is driven by filesystem/socket events.
async function until(predicate: () => boolean) {
  const deadline = Date.now() + 2000;
  while (!predicate()) {
    if (Date.now() > deadline) throw new Error("Test condition not reached");
    await Bun.sleep(5);
  }
}

test("missing session variables are explicit and logged once, not silent no-ops", async () => {
  for (const env of [{}, { HYPRLAND_INSTANCE_SIGNATURE: "x" }, { XDG_RUNTIME_DIR: "/x" }]) {
    const logs: string[] = [];
    const health: EventStreamHealth[] = [];
    const stream = subscribeEvents(() => { throw new Error("Unexpected event"); }, { env, log: (line) => logs.push(line), onHealth: (h) => health.push(h) });
    await stream.ready;
    expect(stream.health().state).toBe("unavailable");
    expect(stream.health().reason).toContain("Missing ");
    expect(logs.length).toBe(1);
    expect(health.length).toBe(1);
    stream.stop();
    stream.stop();
    expect(logs.length).toBe(1);
  }
  expect(initialEventHealth({ HYPRLAND_INSTANCE_SIGNATURE: "x", XDG_RUNTIME_DIR: "/x" }).state).toBe("not_started");
});

test("socket loss, fragmented events and file-driven reconnection update health", async () => {
  const dir = mkdtempSync(join(tmpdir(), "lats-events-"));
  const instance = join(dir, "hypr", "test");
  mkdirSync(instance, { recursive: true });
  const path = join(instance, ".socket2.sock");
  const events: string[] = [];
  const logs: string[] = [];
  const sockets = new Set<Socket>();
  const servers: ReturnType<typeof createServer>[] = [];
  const start = async () => {
    const server = createServer((socket) => {
      sockets.add(socket);
      socket.on("close", () => sockets.delete(socket));
      socket.on("error", () => {});
      socket.write("activewin");
      setImmediate(() => socket.write("dow>>first\nworkspace>>2\npartial"));
    });
    servers.push(server);
    await new Promise<void>((resolve) => server.listen(path, resolve));
    return server;
  };
  const stream = subscribeEvents((e, data) => events.push(e + ":" + data), {
    env: { XDG_RUNTIME_DIR: dir, HYPRLAND_INSTANCE_SIGNATURE: "test" },
    log: (line) => logs.push(line),
  });
  try {
    await stream.ready;
    expect(stream.health().state).toBe("unavailable");
    expect(stream.health().reason).toContain("ENOENT");
    const first = await start();
    await until(() => events.length >= 2);
    expect(stream.health().state).toBe("connected");
    expect(stream.health().lastEventAt).not.toBeNull();
    expect(events.slice(0, 2)).toEqual(["activewindow:first", "workspace:2"]);
    for (const socket of sockets) socket.end();
    await until(() => stream.health().state === "disconnected");
    await new Promise<void>((resolve) => first.close(() => resolve()));
    await start();
    await until(() => events.length >= 4);
    expect(stream.health().state).toBe("connected");
    expect(events.slice(2, 4)).toEqual(["activewindow:first", "workspace:2"]);
    expect(logs.filter((line) => line === "event stream: connected").length).toBe(1);
    stream.stop();
    expect(stream.health().state).toBe("stopped");
  } finally {
    stream.stop();
    for (const socket of sockets) socket.destroy();
    for (const server of servers) if (server.listening) await new Promise<void>((resolve) => server.close(() => resolve()));
    rmSync(dir, { recursive: true, force: true });
  }
});

test("missing tools and protocols remove capabilities and their dependents", async () => {
  const all = await probeCapabilities(probes);
  expect(Object.values(all).every((h) => h.available)).toBe(true);
  const tools = await probeCapabilities({ ...probes, command: (name) => !["grim", "wtype"].includes(name) });
  for (const name of ["capture.still", "capture.live", "ocr", "capture.record"]) expect(tools[name]).toEqual({ available: false, reason: "Missing command: grim" });
  expect(tools["input.keys"]).toEqual({ available: false, reason: "Missing command: wtype" });
  const missing = await probeCapabilities({ ...probes, wayland: async () => ["wl_seat"] });
  expect(missing["capture.still"].reason).toContain("screencopy");
  expect(missing["input.keys"].reason).toContain("virtual_keyboard");
  expect(missing["input.pointer"].reason).toContain("virtual_pointer");
});

test("a set signature or installed binary is not enough: desktop/Wayland must respond", async () => {
  const broken = await probeCapabilities({
    ...probes,
    desktop: async () => { throw new Error("command socket refused"); },
    wayland: async () => { throw new Error("Wayland unavailable"); },
  });
  for (const name of ["windows.read", "windows.place", "spaces.read", "apps.open", "capture.still", "input.pointer"]) expect(broken[name].available).toBe(false);
  expect(broken["input.keys"].reason).toBe("Wayland unavailable");
  expect(broken["sessions.tmux"].available).toBe(true);
});

test("event capability tracks health; describe stays readable with missing dependencies", async () => {
  capabilities.clear();
  const router = new Router(() => capabilities);
  registerEndpoints(router, { bindHost: "127.0.0.1", startedAt: 0, clientCount: () => 0 });
  updateEventHealth({ source: "hyprland", state: "connected", reason: null, lastEventAt: null });
  expect(capabilities.has("events.desktop")).toBe(true);
  updateEventHealth({ source: "hyprland", state: "disconnected", reason: "Event socket closed", lastEventAt: null });
  expect(capabilities.has("events.desktop")).toBe(false);
  expect(capabilityHealth["events.desktop"].reason).toBe("Event socket closed");
  const result = await router.dispatch("host.describe", {}) as Record<string, unknown>;
  expect(result.eventStream).toBeDefined();
  expect(result.capabilityHealth).toBeDefined();
  expect(result.displays).toEqual([]);
  const methods = router.available().map((e) => e.method);
  expect(methods).toContain("events.subscribe");
  expect(methods).not.toContain("computer.typeText");
  expect(methods).not.toContain("capture.still");
});
