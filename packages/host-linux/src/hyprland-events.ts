// A passive socket2 subscription. Reconnect on socket-file changes, not a
// periodic timer; all unavailable/disconnected states stay observable.
import { statSync, watch, type FSWatcher } from "node:fs";
import { connect, type Socket } from "node:net";
import { join } from "node:path";

export interface EventStreamHealth {
  source: "hyprland";
  state: "not_started" | "connecting" | "connected" | "unavailable" | "disconnected" | "stopped";
  reason: string | null;
  lastEventAt: string | null;
}

export function initialEventHealth(env: NodeJS.ProcessEnv = process.env): EventStreamHealth {
  const missing = ["HYPRLAND_INSTANCE_SIGNATURE", "XDG_RUNTIME_DIR"].filter((name) => !env[name]);
  return {
    source: "hyprland",
    state: missing.length ? "unavailable" : "not_started",
    reason: missing.length ? "Missing " + missing.join(", ") : "Event subscription has not started",
    lastEventAt: null,
  };
}

export function subscribeEvents(
  listener: (event: string, data: string) => void,
  options: { env?: NodeJS.ProcessEnv; onHealth?: (health: EventStreamHealth) => void; log?: (line: string) => void } = {}
) {
  const env = options.env ?? process.env;
  let health = initialEventHealth(env);
  let stopped = false;
  let socket: Socket | null = null;
  const watchers = new Map<string, { watcher: FSWatcher; identity: string }>();
  const identity = (path: string) => { try { const s = statSync(path); return s.dev + ":" + s.ino; } catch { return null; } };
  const logged = new Set<string>();
  let resolveReady!: () => void;
  const ready = new Promise<void>((resolve) => { resolveReady = resolve; });
  const transition = (state: EventStreamHealth["state"], reason: string | null) => {
    if (health.state === state && health.reason === reason) return;
    health = { ...health, state, reason };
    options.onHealth?.({ ...health });
    if (state !== "connecting" && state !== "stopped") {
      const line = "event stream: " + state + (reason ? " (" + reason + ")" : "");
      if (!logged.has(line)) { logged.add(line); (options.log ?? console.error)(line); }
    }
  };

  if (health.state === "unavailable") {
    options.onHealth?.({ ...health });
    (options.log ?? console.error)("event stream: unavailable (" + health.reason + ")");
    resolveReady();
  } else {
    const runtime = env.XDG_RUNTIME_DIR!;
    const root = join(runtime, "hypr");
    const instance = join(root, env.HYPRLAND_INSTANCE_SIGNATURE!);
    const path = join(instance, ".socket2.sock");

    let socketIdentity: string | null = null;
    const open = () => {
      if (stopped || socket) return;
      transition("connecting", null);
      let buffer = "";
      let failed = false;
      const current = connect(path);
      socket = current;
      socketIdentity = identity(path);
      current.setEncoding("utf8");
      current.once("connect", () => {
        if (stopped) return;
        transition("connected", null);
        resolveReady();
      });
      current.on("data", (chunk: string) => {
        if (stopped) return;
        buffer += chunk;
        let newline: number;
        while ((newline = buffer.indexOf("\n")) !== -1) {
          const line = buffer.slice(0, newline);
          buffer = buffer.slice(newline + 1);
          const split = line.indexOf(">>");
          if (split > 0) {
            health = { ...health, lastEventAt: new Date().toISOString() };
            listener(line.slice(0, split), line.slice(split + 2));
          }
        }
        if (buffer.length > 1024 * 1024) current.destroy(new Error("event line exceeded 1 MiB"));
      });
      current.once("error", (error) => {
        failed = true;
        if (!stopped && socket === current) transition("unavailable", error.message);
        resolveReady();
      });
      current.once("close", () => {
        if (socket !== current) return;
        socket = null;
        if (!stopped && !failed) transition("disconnected", "Event socket closed");
        resolveReady();
        // Wait for a filesystem event. Never spin or silently poll/retry.
      });
    };

    const watchDirectories = () => {
      for (const dir of [runtime, root, instance]) {
        const dirIdentity = identity(dir);
        const previous = watchers.get(dir);
        if (previous && previous.identity === dirIdentity) continue;
        if (previous) { watchers.delete(dir); previous.watcher.close(); }
        if (!dirIdentity) continue;
        try {
          const watcher = watch(dir, (_, filename) => {
            if (stopped) return;
            const name = String(filename ?? "");
            if (dir === instance && name && name !== ".socket2.sock") return;
            if (dir === root && name && name !== env.HYPRLAND_INSTANCE_SIGNATURE) return;
            if (dir === runtime && name && name !== "hypr") return;
            watchDirectories();
            if (socket && identity(path) !== socketIdentity) {
              const old = socket;
              socket = null;
              old.destroy();
            }
            open();
          });
          watcher.on("error", (error) => {
            watcher.close();
            watchers.delete(dir);
            if (!stopped && health.state !== "connected") transition("unavailable", "Cannot watch event socket: " + error.message);
          });
          watchers.set(dir, { watcher, identity: dirIdentity });
        } catch { /* Parents watch for not-yet-created directories; socket errors are reported by open. */ }
      }
    };
    watchDirectories();
    open();
  }

  return {
    ready,
    health: () => ({ ...health }),
    stop: () => {
      if (stopped) return;
      stopped = true;
      for (const { watcher } of watchers.values()) watcher.close();
      watchers.clear();
      socket?.destroy();
      transition("stopped", "Event subscription stopped");
      resolveReady();
    },
  };
}
