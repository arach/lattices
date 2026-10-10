import dbus from "dbus-next";
import { fileURLToPath } from "node:url";
import { busCall, changeUnit, managerCall, unitJob, unitState, withUserBus } from "./systemd.ts";

export const POINTER_UNITS = {
  timer: "lattices-pointer-trial.timer",
  home: "lattices-pointer-trial.service",
  watch: "lattices-pointer-watch.service",
} as const;

/** Whole seconds, with an optional s/m/h suffix. Bare numbers mean seconds. */
export function parsePointerDuration(value: string): number {
  const match = /^(\d+)(s|m|h)?$/.exec(value);
  if (!match) throw new Error("Duration must look like 90, 30s, 5m or 1h");
  const seconds = Number(match[1]) * ({ s: 1, m: 60, h: 3600 }[match[2] ?? "s"]!);
  if (!Number.isSafeInteger(seconds) || seconds <= 0 || seconds > Number.MAX_SAFE_INTEGER / 1000)
    throw new Error("Duration must be positive and fit in milliseconds");
  return seconds * 1000;
}

type Property = [string, dbus.Variant];
const prop = (name: string, signature: string, value: unknown): Property => [name, new dbus.Variant(signature, value)];
export interface TrialCommand { executable: string; script: string; environment: Record<string, string | undefined> }

/** Direct D-Bus argv: no shell, specifier interpolation or environment expansion. */
export function pointerTrialUnits(durationMs: number, command: TrialCommand) {
  const environment = ["PATH", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"]
    .flatMap((name) => command.environment[name] === undefined ? [] : [`${name}=${command.environment[name]}`]);
  const service = (role: "expiry" | "watchdog", args: string[]): Property[] => [
    prop("Description", "s", `Lattices pointer ${role}`),
    prop("CollectMode", "s", "inactive-or-failed"),
    prop("Type", "s", role === "expiry" ? "oneshot" : "exec"),
    prop("ExecStartEx", "a(sasas)", [[command.executable, [command.executable, command.script, ...args], ["no-env-expand"]]]),
    prop("Environment", "as", [...environment, `LATTICES_POINTER_ROLE=${role}`]),
    prop("TimeoutStopUSec", "t", 2_000_000n),
    prop("StandardOutput", "s", "journal"),
    prop("StandardError", "s", "journal"),
  ];
  return {
    timer: [
      prop("Description", "s", "Lattices pointer trial deadline"),
      prop("CollectMode", "s", "inactive-or-failed"),
      prop("TimersMonotonic", "a(st)", [["OnActiveSec", BigInt(durationMs) * 1000n]]),
      prop("AccuracyUSec", "t", 100_000n),
      prop("RemainAfterElapse", "b", false),
    ],
    home: service("expiry", ["mouse-home", "--expired"]),
    watch: [
      ...service("watchdog", ["mouse-check"]),
      prop("Restart", "s", "on-failure"),
      prop("RestartUSec", "t", 1_000_000n),
    ],
  };
}

export interface PointerTrial {
  arm: (durationMs: number) => Promise<void>;
  cancel: () => Promise<void>;
  until: () => Promise<string | null>;
}

/** Use systemd's paired clocks. Bun's hrtime epoch is process-local. */
export function pointerTrialDeadline(nextUsec: bigint, activeUsec: bigint, activeMonotonicUsec: bigint): string | null {
  if (nextUsec === 0n || nextUsec === 18_446_744_073_709_551_615n || activeUsec === 0n) return null;
  return new Date(Number(activeUsec + nextUsec - activeMonotonicUsec) / 1000).toISOString();
}

const missingUnit = (error: unknown) => error instanceof dbus.DBusError && error.type === "org.freedesktop.systemd1.NoSuchUnit";

export const systemdPointerTrial: PointerTrial = {
  arm: async (durationMs) => withUserBus(async (bus) => {
    const units = pointerTrialUnits(durationMs, {
      executable: process.execPath,
      script: fileURLToPath(new URL("./main.ts", import.meta.url)),
      environment: process.env,
    });
    // Timer and recovery service are submitted together, before any activation.
    await unitJob(bus, POINTER_UNITS.timer, "StartTransientUnit", "ssa(sv)a(sa(sv))", [
      POINTER_UNITS.timer, "fail", units.timer, [[POINTER_UNITS.home, units.home]],
    ]);
    await unitJob(bus, POINTER_UNITS.watch, "StartTransientUnit", "ssa(sv)a(sa(sv))", [
      POINTER_UNITS.watch, "fail", units.watch, [],
    ]);
  }),
  cancel: async () => withUserBus(async (bus) => {
    const role = process.env.LATTICES_POINTER_ROLE;
    const units = [POINTER_UNITS.timer,
      ...(role === "watchdog" ? [] : [POINTER_UNITS.watch]),
      ...(role === "expiry" ? [] : [POINTER_UNITS.home])];
    const errors: unknown[] = [];
    for (const unit of units) {
      try { await changeUnit(bus, unit, "StopUnit"); }
      catch (error) { if (!missingUnit(error)) errors.push(error); }
    }
    if (errors.length) throw new AggregateError(errors, "Could not cancel pointer trial");
  }),
  until: async () => withUserBus(async (bus) => {
    if (await unitState(bus, POINTER_UNITS.timer) !== "active") return null;
    try {
      const [path] = await managerCall(bus, "GetUnit", "s", [POINTER_UNITS.timer]);
      const [[next], [timestamps]] = await Promise.all([
        busCall(bus, {
          destination: "org.freedesktop.systemd1", path, interface: "org.freedesktop.DBus.Properties",
          member: "Get", signature: "ss", body: ["org.freedesktop.systemd1.Timer", "NextElapseUSecMonotonic"],
        }),
        busCall(bus, {
          destination: "org.freedesktop.systemd1", path, interface: "org.freedesktop.DBus.Properties",
          member: "GetAll", signature: "s", body: ["org.freedesktop.systemd1.Unit"],
        }),
      ]);
      return pointerTrialDeadline(BigInt(next.value), BigInt(timestamps.ActiveEnterTimestamp.value), BigInt(timestamps.ActiveEnterTimestampMonotonic.value));
    } catch (error) { if (missingUnit(error)) return null; throw error; }
  }),
};
