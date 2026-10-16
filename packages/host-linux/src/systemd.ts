import dbus from "dbus-next";
import type { MessageBus, MessageLike } from "dbus-next";

const DEST = "org.freedesktop.systemd1";
const PATH = "/org/freedesktop/systemd1";
const MANAGER = `${DEST}.Manager`;

export function deadline<T>(promise: Promise<T>, ms = 2500): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("D-Bus request timed out")), ms);
    promise.then(resolve, reject).finally(() => clearTimeout(timer));
  });
}

export async function busCall(bus: MessageBus, options: MessageLike) {
  const reply = await deadline(bus.call(new dbus.Message(options)));
  return reply?.body ?? [];
}

export async function withUserBus<T>(action: (bus: MessageBus) => Promise<T>): Promise<T> {
  const bus = dbus.sessionBus();
  bus.on("error", () => {});
  try { return await action(bus); } finally { bus.disconnect(); }
}

export const managerCall = (bus: MessageBus, member: string, signature = "", body: unknown[] = []) =>
  busCall(bus, { destination: DEST, path: PATH, interface: MANAGER, member, signature, body });

export async function unitState(bus: MessageBus, unit: string): Promise<string> {
  try {
    const [path] = await managerCall(bus, "GetUnit", "s", [unit]);
    const [state] = await busCall(bus, { destination: DEST, path, interface: "org.freedesktop.DBus.Properties", member: "Get", signature: "ss", body: [`${DEST}.Unit`, "ActiveState"] });
    return state.value;
  } catch (error) {
    if (error instanceof dbus.DBusError && error.type === `${DEST}.NoSuchUnit`) return "inactive";
    throw error;
  }
}

/** Await systemd's job receipt, including a daemon that is still stopping. */
export async function changeUnit(bus: MessageBus, unit: string, action: "StartUnit" | "StopUnit" | "RestartUnit"): Promise<void> {
  await unitJob(bus, unit, action, "ss", [unit, "replace"]);
}

/** Also used for transient units: do not activate clients until the timer is armed. */
export async function unitJob(bus: MessageBus, unit: string, member: string, signature: string, body: unknown[]): Promise<void> {
  await managerCall(bus, "Subscribe").catch(() => {});
  const rule = `type='signal',sender='${DEST}',interface='${MANAGER}',member='JobRemoved'`;
  await busCall(bus, { destination: "org.freedesktop.DBus", path: "/org/freedesktop/DBus", interface: "org.freedesktop.DBus", member: "AddMatch", signature: "s", body: [rule] });
  const jobs = new Map<string, string>();
  let jobPath: string | undefined;
  let settle: (result: string) => void = () => {};
  const completion = new Promise<string>((resolve) => { settle = resolve; });
  const listener = (message: dbus.Message) => {
    if (message.interface !== MANAGER || message.member !== "JobRemoved") return;
    const [, path, , result] = message.body;
    jobs.set(path, result);
    if (path === jobPath) settle(result);
  };
  bus.on("message", listener);
  try {
    [jobPath] = await managerCall(bus, member, signature, body);
    if (jobs.has(jobPath!)) settle(jobs.get(jobPath!)!);
    const result = await deadline(completion, 4000);
    if (result !== "done") throw new Error(`${unit}: ${result}`);
  } finally {
    bus.removeListener("message", listener);
    await busCall(bus, { destination: "org.freedesktop.DBus", path: "/org/freedesktop/DBus", interface: "org.freedesktop.DBus", member: "RemoveMatch", signature: "s", body: [rule] }).catch(() => {});
  }
}
