import { hasCommand, run } from "./exec.ts";
import type { HyprMonitor } from "./hyprland.ts";

export interface MouseClient {
  id: string;
  host: string;
  position: string;
  active: boolean;
}

/** lan-mouse 0.11's CLI output. Keep IDs as strings (Rust uses u64). */
export function parseLanMouseClients(output: string): MouseClient[] {
  const clients: MouseClient[] = [];
  for (const line of output.split(/\r?\n/)) {
    if (!line.trim()) continue;
    const match = /^id (\d+): (.+):\d+ \((left|right|top|bottom)\) active: (true|false), ips: \{.*\}$/.exec(line.trim());
    if (!match) throw new Error("Unrecognised lan-mouse client list");
    if (clients.some((c) => c.id === match[1])) throw new Error("Duplicate lan-mouse client ID");
    clients.push({ id: match[1], host: match[2], position: match[3], active: match[4] === "true" });
  }
  return clients;
}

type Monitor = HyprMonitor & { disabled?: boolean; mirrorOf?: string; physicalWidth?: number; physicalHeight?: number };

export function pickHomeMonitor(monitors: Monitor[]): Monitor {
  const real = monitors.filter((m) => !m.disabled && (!m.mirrorOf || m.mirrorOf === "none")
    && !/^(LATS(?:-|$)|HEADLESS|WL-|VIRTUAL|Virtual-|RDP-)/i.test(m.name)
    && !/headless|virtual output/i.test(m.description)
    && !(m.physicalWidth === 0 && m.physicalHeight === 0 && !m.description)
    && Number.isFinite(m.x) && Number.isFinite(m.y) && m.width > 0 && m.height > 0 && m.scale > 0);
  const monitor = real.find((m) => m.focused) ?? real[0];
  if (!monitor) throw new Error("No real monitor available");
  return monitor;
}

export function monitorCentre(monitor: HyprMonitor): { x: number; y: number } {
  const rotated = monitor.transform % 2 === 1;
  return {
    x: Math.round(monitor.x + (rotated ? monitor.height : monitor.width) / monitor.scale / 2),
    y: Math.round(monitor.y + (rotated ? monitor.width : monitor.height) / monitor.scale / 2),
  };
}

export interface MouseDependencies {
  run: typeof run;
  hasLanMouse: () => boolean;
  serviceState: () => Promise<string>;
  restartService: () => Promise<void>;
}

const defaults: MouseDependencies = {
  run,
  hasLanMouse: () => hasCommand("lan-mouse"),
  serviceState: async () => {
    const { withUserBus, unitState } = await import("./systemd.ts");
    return withUserBus((bus) => unitState(bus, "lan-mouse.service"));
  },
  restartService: async () => {
    const { withUserBus, changeUnit } = await import("./systemd.ts");
    await withUserBus((bus) => changeUnit(bus, "lan-mouse.service", "RestartUnit"));
  },
};

const CLI_TIMEOUT = 800;
const listOutput = (deps: MouseDependencies) => deps.run("lan-mouse", ["cli", "list"], { timeoutMs: CLI_TIMEOUT });

export async function pointerState(deps = defaults) {
  if (!deps.hasLanMouse()) return { available: false, sharing: false, clients: [] as MouseClient[] };
  try {
    const clients = parseLanMouseClients(await listOutput(deps));
    return { available: true, sharing: clients.some((c) => c.active), clients };
  } catch {
    return { available: false, sharing: false, clients: [] as MouseClient[] };
  }
}

export async function sharePointer(active: boolean, deps = defaults) {
  if (!deps.hasLanMouse()) throw new Error("lan-mouse unavailable");
  const clients = parseLanMouseClients(await listOutput(deps));
  if (!clients.length && active) throw new Error("No lan-mouse clients");
  await Promise.all(clients.map((client) => deps.run("lan-mouse", ["cli", active ? "activate" : "deactivate", client.id], { timeoutMs: CLI_TIMEOUT })));
  return pointerState(deps);
}

export async function releasePointer(deps = defaults) {
  const result = { available: false, released: [] as string[], restarted: false, errors: [] as string[] };
  if (!deps.hasLanMouse()) return result;

  const deactivate = async (output: string) => {
    // A format change is not evidence that the daemon is unreachable.
    const clients = parseLanMouseClients(output);
    result.available = true;
    const outcomes = await Promise.allSettled(clients.map(async (client) => {
      await deps.run("lan-mouse", ["cli", "deactivate", client.id], { timeoutMs: CLI_TIMEOUT });
      result.released.push(client.id);
    }));
    return outcomes.filter((o) => o.status === "rejected");
  };

  let unreachable = false;
  let output: string | undefined;
  try { output = await listOutput(deps); } catch { unreachable = true; }
  if (output !== undefined) {
    try {
      const failures = await deactivate(output);
      for (const failure of failures) result.errors.push(String(failure.reason));
      // A stale client is not a reason to restart a responsive daemon.
      if (failures.length) {
        try { await listOutput(deps); } catch { unreachable = true; }
      }
    } catch (error) { result.errors.push(String(error)); }
  }

  if (unreachable) {
    try {
      // A stopped or absent service stays stopped. Only a running, unreachable
      // daemon gets the fallback restart, and startup clients are released too.
      if (await deps.serviceState() === "active") {
        await deps.restartService();
        result.restarted = true;
        const failures = await deactivate(await listOutput(deps));
        for (const failure of failures) result.errors.push(String(failure.reason));
      }
    } catch (error) { result.errors.push(String(error)); }
  }
  return result;
}

/** Recovery primitive: release first; warp even if lan-mouse or systemd fails. */
export async function bringCursorHome(deps = defaults) {
  const release = await releasePointer(deps).catch((error) => ({ available: false, released: [], restarted: false, errors: [String(error)] }));
  const monitors = JSON.parse(await deps.run("hyprctl", ["monitors", "-j"], { timeoutMs: 1500 })) as Monitor[];
  const monitor = pickHomeMonitor(monitors);
  const point = monitorCentre(monitor);
  let response = await deps.run("hyprctl", ["dispatch", "movecursor", String(point.x), String(point.y)], { timeoutMs: 1500 }).catch(() => "");
  // Hyprland 0.55+ uses Lua dispatchers. Support both without shell execution.
  if (response.trim() !== "ok") {
    response = await deps.run("hyprctl", ["dispatch", `hl.dsp.cursor.move({ x = ${point.x}, y = ${point.y} })`], { timeoutMs: 1500 });
  }
  if (response.trim() !== "ok") throw new Error(`hyprctl: ${response.trim()}`);
  return { ok: true, monitor: monitor.name, ...point, release };
}
