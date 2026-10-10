import { hasCommand, run } from "./exec.ts";
import type { HyprMonitor } from "./hyprland.ts";
import { parsePointerDuration, systemdPointerTrial, type PointerTrial } from "./pointer-trial.ts";

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

export type Monitor = HyprMonitor & { disabled?: boolean; mirrorOf?: string; physicalWidth?: number; physicalHeight?: number };

/** The physical desktop shared by Bring Cursor Home and visiting cursors. */
export function realMonitors(monitors: Monitor[]): Monitor[] {
  return monitors.filter((m) => !m.disabled && (!m.mirrorOf || m.mirrorOf === "none")
    && !/^(LATS(?:-|$)|HEADLESS|WL-|VIRTUAL|Virtual-|RDP-)/i.test(m.name)
    && !/headless|virtual output/i.test(m.description)
    && !(m.physicalWidth === 0 && m.physicalHeight === 0 && !m.description)
    && Number.isFinite(m.x) && Number.isFinite(m.y) && Number.isFinite(m.width) && Number.isFinite(m.height)
    && Number.isFinite(m.scale) && m.width > 0 && m.height > 0 && m.scale > 0);
}

export function pickHomeMonitor(monitors: Monitor[]): Monitor {
  const real = realMonitors(monitors);
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
  startService: () => Promise<void>;
  restartService: () => Promise<void>;
  trial: PointerTrial;
  sleep: (ms: number) => Promise<void>;
  log: (line: string) => void;
}

const defaults: MouseDependencies = {
  run,
  hasLanMouse: () => hasCommand("lan-mouse"),
  trial: systemdPointerTrial,
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  log: (line) => console.error(`[lattices-pointer] ${line}`),
  serviceState: async () => {
    const { withUserBus, unitState } = await import("./systemd.ts");
    return withUserBus((bus) => unitState(bus, "lan-mouse.service"));
  },
  restartService: async () => {
    const { withUserBus, changeUnit } = await import("./systemd.ts");
    await withUserBus((bus) => changeUnit(bus, "lan-mouse.service", "RestartUnit"));
  },
  startService: async () => {
    const { withUserBus, changeUnit } = await import("./systemd.ts");
    await withUserBus((bus) => changeUnit(bus, "lan-mouse.service", "StartUnit"));
  },
};

const CLI_TIMEOUT = 800;
const listOutput = (deps: MouseDependencies) => deps.run("lan-mouse", ["cli", "list"], { timeoutMs: CLI_TIMEOUT });

export async function pointerState(deps = defaults) {
  const until = await deps.trial.until();
  if (!deps.hasLanMouse()) return { available: false, sharing: false, clients: [] as MouseClient[], until };
  try {
    const clients = parseLanMouseClients(await listOutput(deps));
    return { available: true, sharing: clients.some((c) => c.active), clients, until };
  } catch {
    // Share can start a stopped service; presence of the binary enables it.
    return { available: true, sharing: false, clients: [] as MouseClient[], until };
  }
}

export async function pointerStatus(deps = defaults) {
  const { sharing, clients, until } = await pointerState(deps);
  return { sharing, clients, until };
}

export async function sharePointer(active: boolean, deps = defaults) {
  if (active) return startPointerTrial("5m", deps);
  await bringCursorHome(deps);
  return pointerState(deps);
}

export async function startPointerTrial(duration = "5m", deps = defaults) {
  const durationMs = parsePointerDuration(duration);
  if (!deps.hasLanMouse()) throw new Error("lan-mouse unavailable");
  try {
    await deps.trial.cancel();
    let output: string;
    try { output = await listOutput(deps); }
    catch (error) {
      // A responsive unmanaged daemon is already running. Do not start a duplicate.
      if (await deps.serviceState() === "active") throw error;
      await deps.startService();
      for (let attempt = 0; ; attempt++) {
        try { output = await listOutput(deps); break; }
        catch (error) {
          if (attempt === 4) throw error;
          await deps.sleep(100);
        }
      }
    }
    const clients = parseLanMouseClients(output);
    if (!clients.length) throw new Error("No lan-mouse clients");
    await deps.trial.arm(durationMs);
    const until = await deps.trial.until();
    if (!until) throw new Error("Pointer trial deadline is not armed");
    const outcomes = await Promise.allSettled(clients.map((client) => deps.run("lan-mouse", ["cli", "activate", client.id], { timeoutMs: CLI_TIMEOUT })));
    const failed = outcomes.find((outcome) => outcome.status === "rejected");
    if (failed?.status === "rejected") throw failed.reason;
    const state = await pointerState(deps);
    if (!state.until || !state.sharing || state.clients.some((client) => !client.active))
      throw new Error("Pointer trial activation did not complete");
    deps.log(`start until=${state.until}`);
    return { sharing: state.sharing, until: state.until };
  } catch (error) {
    // Partial activation or arming must not leave unprotected sharing behind.
    await bringCursorHome(deps).catch(() => {});
    throw error;
  }
}

export async function keepPointerSharing(deps = defaults) {
  await deps.trial.cancel();
  deps.log("keep");
  const state = await pointerState(deps);
  return { sharing: state.sharing, until: state.until };
}

/** Runs only in the detached transient watchdog service. No files or tray timer. */
export async function watchPointerTrial(deps = defaults) {
  let failures = 0;
  while (await deps.trial.until()) {
    await deps.sleep(15_000);
    if (!await deps.trial.until()) return;
    try { parseLanMouseClients(await listOutput(deps)); failures = 0; }
    catch { failures++; }
    if (failures >= 2) {
      await bringCursorHome(deps, "watchdog");
      return;
    }
  }
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
export async function bringCursorHome(deps = defaults, reason?: "expiry" | "watchdog") {
  if (reason) deps.log(`${reason} revert`);
  const trialErrors: string[] = [];
  try { await deps.trial.cancel(); } catch (error) { trialErrors.push(String(error)); }
  const release = await releasePointer(deps).catch((error) => ({ available: false, released: [], restarted: false, errors: [String(error)] }));
  release.errors.push(...trialErrors);
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
