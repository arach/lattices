import dbus from "dbus-next";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { bringCursorHome, keepPointerSharing, pointerState, sharePointer } from "../mouse.ts";
import { POINTER_UNITS } from "../pointer-trial.ts";
import { busCall, changeUnit, deadline, managerCall, unitState } from "../systemd.ts";
import { watchLanMouse } from "./events.ts";
import { TrayItem } from "./item.ts";
import { pointerMenu, TrayMenu } from "./menu.ts";

const NAME = "org.kde.StatusNotifierItem.Lattices";
const WATCHER = "org.kde.StatusNotifierWatcher";
const SYSTEMD = "org.freedesktop.systemd1";

async function hostRunning(): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = new WebSocket("ws://127.0.0.1:9399");
    const finish = (running: boolean) => { clearTimeout(timer); socket.close(); resolve(running); };
    const timer = setTimeout(() => finish(false), 700);
    socket.onopen = () => socket.send(JSON.stringify({ id: "tray-health", method: "daemon.status" }));
    socket.onmessage = (event) => {
      try {
        const reply = JSON.parse(String(event.data));
        if (reply.id === "tray-health") finish(!reply.error && reply.result?.platform === "linux");
      } catch { finish(false); }
    };
    socket.onerror = () => finish(false);
    socket.onclose = () => { clearTimeout(timer); resolve(false); };
  });
}

async function paired(): Promise<boolean | null> {
  try {
    const devices: unknown = JSON.parse(await readFile(join(homedir(), ".lattices/host/bridge-devices.json"), "utf8"));
    return Array.isArray(devices) ? devices.length > 0 : null;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "ENOENT" ? false : null;
  }
}

export async function startTray() {
  if (!process.env.DBUS_SESSION_BUS_ADDRESS) throw new Error("Start the tray inside your graphical session");
  const bus = dbus.sessionBus();
  const fail = (error: unknown) => { console.error(`[lattices-tray] ${String(error)}`); };
  bus.on("error", (error) => { fail(error); shutdown(1); });
  let refreshPending: Promise<void> | undefined;
  let sharing = false;
  let host = false;
  let unit = "inactive";
  let busy = false;
  let queued: ReturnType<typeof setTimeout> | undefined;
  let stopMouse = () => {};
  let stopping = false;

  const shutdown = (code = 0) => {
    if (stopping) return;
    stopping = true;
    clearTimeout(queued);
    stopMouse();
    bus.disconnect();
    process.exit(code);
  };
  const refresh = (): Promise<void> => {
    if (refreshPending) return refreshPending;
    refreshPending = (async () => {
      const [pointer, running, service, pairing] = await Promise.all([
        pointerState(), hostRunning(), unitState(bus, "lattices-host.service").catch(() => "unknown"), paired(),
      ]);
      sharing = pointer.sharing;
      host = running;
      unit = service;
      item.update(sharing);
      const status = host ? "On" : unit === "activating" ? "Starting" : "Off";
      menu.update([
        ...pointerMenu(pointer, busy),
        { id: 6, separator: true },
        { id: 3, label: `Host: ${status} · ${pairing === null ? "Unknown" : pairing ? "Paired" : "Unpaired"}`, enabled: false },
        { id: 4, label: host || unit === "active" || unit === "activating" ? "Stop Host" : "Start Host", enabled: !busy && unit !== "unknown" && !(host && unit !== "active" && unit !== "activating") },
        { id: 7, separator: true },
        { id: 5, label: "Quit" },
      ]);
    })().finally(() => { refreshPending = undefined; });
    return refreshPending;
  };
  const queueRefresh = () => {
    if (stopping || queued) return;
    queued = setTimeout(() => { queued = undefined; void refresh().catch(fail); }, 50);
  };
  const activate = (id: number) => {
    if (id === 5) { setTimeout(() => shutdown(), 0); return; }
    if (busy) return;
    busy = true;
    const action = async () => {
      if (id === 1) console.log(`[lattices-tray] mouse.home ${JSON.stringify(await bringCursorHome())}`);
      else if (id === 2) await sharePointer(!sharing);
      else if (id === 8) await keepPointerSharing();
      else if (id === 4) {
        if (host && unit !== "active" && unit !== "activating") throw new Error("Host is running outside lattices-host.service");
        await changeUnit(bus, "lattices-host.service", host || unit === "active" || unit === "activating" ? "StopUnit" : "StartUnit");
      }
    };
    void action().catch(async (error) => {
      fail(error);
      // A short error notification is visible even after the menu closes.
      const { run } = await import("../exec.ts");
      await run("notify-send", ["Lattices", String(error).slice(0, 180)], { timeoutMs: 1000 }).catch(() => {});
    }).finally(async () => { busy = false; await refresh().catch(fail); });
  };
  const item = new TrayItem(refresh);
  const menu = new TrayMenu(refresh, activate);
  const register = async () => {
    try {
      await busCall(bus, { destination: WATCHER, path: "/StatusNotifierWatcher", interface: WATCHER, member: "RegisterStatusNotifierItem", signature: "s", body: [NAME] });
      console.log("[lattices-tray] registered");
    } catch (error) {
      if (!(error instanceof dbus.DBusError) || error.type !== "org.freedesktop.DBus.Error.ServiceUnknown") fail(error);
    }
  };

  try {
    const owner = await deadline(bus.requestName(NAME, dbus.NameFlag.DO_NOT_QUEUE));
    if (owner !== dbus.RequestNameReply.PRIMARY_OWNER) throw new Error("Lattices tray already running");
    bus.export("/StatusNotifierItem", item);
    bus.export("/Menu", menu);
    for (const rule of [
      "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged'",
      `type='signal',sender='${SYSTEMD}',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'`,
      `type='signal',sender='${SYSTEMD}',interface='${SYSTEMD}.Manager'`,
    ]) {
      await busCall(bus, { destination: "org.freedesktop.DBus", path: "/org/freedesktop/DBus", interface: "org.freedesktop.DBus", member: "AddMatch", signature: "s", body: [rule] });
    }
    bus.on("message", (message) => {
      if (message.interface === "org.freedesktop.DBus" && message.member === "NameOwnerChanged") {
        if (message.body[0] === WATCHER && message.body[2]) void register();
      } else if (message.path?.includes("/unit/lan_2dmouse_2eservice") || message.path?.includes("/unit/lattices_2dhost_2eservice") || message.path?.includes("/unit/lattices_2dpointer_2d")) queueRefresh();
      else if (message.interface === `${SYSTEMD}.Manager` && ["lan-mouse.service", "lattices-host.service", ...Object.values(POINTER_UNITS)].includes(message.body[0])) queueRefresh();
    });
    await managerCall(bus, "Subscribe").catch(fail);
    await refresh();
    stopMouse = watchLanMouse(queueRefresh);
    await register();
    process.on("SIGINT", () => shutdown());
    process.on("SIGTERM", () => shutdown());
  } catch (error) { bus.disconnect(); throw error; }
}
