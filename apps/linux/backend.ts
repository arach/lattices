import { createInterface } from "node:readline";
import { homedir } from "node:os";
import { daemonCallTo } from "../../bin/daemon-client.ts";
import { changeUnit, withUserBus } from "../../packages/host-linux/src/systemd.ts";
import type { Display, Window } from "../../packages/host-linux/src/desktop.ts";

const port = Number(process.env.LATTICES_LINUX_PORT ?? 9399);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("Invalid local host port");
const endpoint = { host: "127.0.0.1", port };
process.env.LATTICES_CLIENT = "linux-app";
const call = <T>(method: string, params?: Record<string, unknown>) => daemonCallTo(endpoint, method, params, 5000) as Promise<T>;
const emit = (value: unknown) => process.stdout.write(JSON.stringify(value) + "\n");
interface Describe {
  hostname: string; capabilities: string[]; methods: string[]; displays: Display[];
  build?: { version: string; commit: string | null; dirty: boolean | null };
  eventStream?: { state: string }; capabilityHealth?: Record<string, { available: boolean; reason: string | null }>;
}
interface Client { id: string; name: string; scope?: string; capabilities?: string[]; node?: string }
interface Pending { deviceID: string; deviceName: string; fingerprint: string; capabilities: string[] }
let events: WebSocket | undefined;
let refreshing = false;
let refreshAgain = false;
let debounce: ReturnType<typeof setTimeout> | undefined;

function watchEvents() {
  if (events && events.readyState < WebSocket.CLOSING) return;
  const socket = new WebSocket(`ws://${endpoint.host}:${port}`);
  events = socket;
  socket.onopen = () => socket.send(JSON.stringify({ id: "linux-app-events", method: "events.subscribe", params: { events: ["windows.changed", "spaces.changed", "host.healthChanged"] } }));
  socket.onmessage = (event) => {
    try {
      if (!JSON.parse(String(event.data)).event || debounce) return;
      debounce = setTimeout(() => { debounce = undefined; void refresh(); }, 180);
    } catch { /* Ignore non-event frames. */ }
  };
  socket.onerror = () => {};
  socket.onclose = () => {
    if (events !== socket) return;
    events = undefined;
    emit({ type: "offline", message: "The local host disconnected. Refresh to reconnect." });
  };
}

async function refresh() {
  if (refreshing) { refreshAgain = true; return; }
  refreshing = true;
  try {
    const describe = await call<Describe>("host.describe");
    const methods = new Set(describe.methods);
    const [desktop, daemon, companion] = await Promise.all([
      methods.has("desktop.snapshot") ? call<{ windows: Window[]; displays: Display[]; sessions: unknown[] }>("desktop.snapshot")
        : Promise.resolve({ windows: [], displays: describe.displays, sessions: methods.has("tmux.list") ? await call<unknown[]>("tmux.list") : [] }),
      methods.has("clients.list") ? call<{ clients: Client[]; pending: Pending[] }>("clients.list") : Promise.resolve({ clients: [], pending: [] }),
      methods.has("bridge.status") ? call<{ devices: Client[]; pending: Pending[] }>("bridge.status") : Promise.resolve({ devices: [], pending: [] }),
    ]);
    desktop.windows = desktop.windows.filter(window => window.pid !== process.ppid);
    emit({ type: "state", online: true, describe, ...desktop, pairingSupported: methods.has("clients.list"),
      clients: [...daemon.clients.map((client) => ({ ...client, kind: "daemon" })), ...companion.devices.map((client) => ({ ...client, kind: "companion", scope: client.capabilities?.join(", ") }))],
      pending: [...daemon.pending.map((request) => ({ ...request, kind: "daemon" })), ...companion.pending.map((request) => ({ ...request, kind: "companion" }))],
    });
    watchEvents();
  } catch (error) { emit({ type: "offline", message: (error as Error).message }); }
  finally {
    refreshing = false;
    if (refreshAgain) { refreshAgain = false; void refresh(); }
  }
}

const allowed = new Set(["windows.focus", "windows.place", "sessions.launch", "clients.approve", "clients.deny", "clients.revoke", "bridge.pairing.approve", "bridge.pairing.deny", "bridge.devices.revoke"]);
const input = createInterface({ input: process.stdin });
let queue = Promise.resolve();
input.on("line", (line) => {
  queue = queue.then(async () => {
    try {
      const request = JSON.parse(line) as { method: string; params?: Record<string, unknown> };
      if (request.method === "refresh") { await refresh(); return; }
      if (request.method === "host.start") {
        await withUserBus((bus) => changeUnit(bus, "lattices-host.service", "StartUnit"));
      } else {
        if (!allowed.has(request.method)) throw new Error("Unsupported app action");
        const params = request.params ?? {};
        if (request.method === "sessions.launch" && typeof params.path === "string") {
          params.path = params.path === "~" ? homedir() : params.path.startsWith("~/") ? homedir() + params.path.slice(1) : params.path;
        }
        await call(request.method, params);
      }
      emit({ type: "done" });
      await refresh();
    } catch (error) { emit({ type: "error", message: (error as Error).message }); }
  });
});
input.on("close", () => { events?.close(); process.exit(0); });
process.on("SIGTERM", () => { events?.close(); process.exit(0); });
void refresh();
