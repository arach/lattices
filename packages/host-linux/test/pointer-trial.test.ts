import { describe, expect, test } from "bun:test";
import { registerEndpoints } from "../src/endpoints.ts";
import { bringCursorHome, keepPointerSharing, pointerState, sharePointer, startPointerTrial, watchPointerTrial, type MouseDependencies } from "../src/mouse.ts";
import { parseMouseCommand, runMouseCommand } from "../src/mouse-cli.ts";
import { parsePointerDuration, pointerTrialDeadline, pointerTrialUnits, POINTER_UNITS } from "../src/pointer-trial.ts";
import { Router } from "../src/router.ts";
import { pointerMenu } from "../src/tray/menu.ts";

const deadline = "2026-10-09T21:00:00.000Z";
function fake() {
  const calls: string[][] = [];
  const logs: string[] = [];
  const sleeps: number[] = [];
  let until: string | null = null;
  let active = false;
  let running = true;
  const deps: MouseDependencies = {
    hasLanMouse: () => true,
    serviceState: async () => running ? "active" : "inactive",
    startService: async () => { running = true; calls.push(["start"]); },
    restartService: async () => { calls.push(["restart"]); },
    trial: {
      arm: async (ms) => { calls.push(["arm", String(ms)]); until = deadline; },
      cancel: async () => { calls.push(["cancel"]); until = null; },
      until: async () => until,
    },
    sleep: async (ms) => { sleeps.push(ms); },
    log: (line) => { logs.push(line); },
    run: async (cmd, args, options) => {
      calls.push([cmd, ...args]);
      expect(options?.timeoutMs).toBeGreaterThan(0);
      if (cmd === "lan-mouse") {
        expect(options?.timeoutMs).toBe(800);
        if (!running) throw new Error("not running");
        if (args[1] === "list") return `id 0: mini:4242 (left) active: ${active}, ips: {}\nid 2: other:4242 (right) active: ${active}, ips: {}\n`;
        if (args[1] === "activate") active = true;
        if (args[1] === "deactivate") active = false;
        return "";
      }
      if (args[0] === "monitors") return JSON.stringify([{ name: "HDMI-A-1", description: "Dell", x: 1920, y: 0, width: 3440, height: 1440, scale: 1, transform: 0, focused: true }]);
      return "ok\n";
    },
  };
  return { deps, calls, logs, sleeps, setRunning: (value: boolean) => { running = value; }, setUntil: (value: string | null) => { until = value; } };
}

describe("pointer trial duration and commands", () => {
  test("seconds and s/m/h durations", () => {
    for (const [value, expected] of [["90", 90_000], ["30s", 30_000], ["5m", 300_000], ["1h", 3_600_000], ["01s", 1000]] as const)
      expect(parsePointerDuration(value)).toBe(expected);
    for (const value of ["", "0", "0m", "-1", "1.5m", "5M", " 5m", "5m ", "1d", "1m;reboot", "Infinity", "9007199254740992h"])
      expect(() => parsePointerDuration(value)).toThrow();
  });
  test("CLI defaults and strict arguments", async () => {
    expect(parseMouseCommand(["mouse-share"])).toEqual({ command: "mouse-share", duration: "5m" });
    expect(parseMouseCommand(["mouse-share", "--for", "1m"]).duration).toBe("1m");
    for (const args of [["mouse-share", "--for"], ["mouse-share", "--for", "1m", "extra"], ["mouse-keep", "extra"], ["mouse-unknown"]])
      expect(() => parseMouseCommand(args)).toThrow();
    const { deps, calls } = fake();
    await runMouseCommand(["mouse-share", "--for", "30s"], deps);
    expect(calls).toContainEqual(["arm", "30000"]);
    expect(await runMouseCommand(["mouse-status"], deps)).toMatchObject({ sharing: true, until: deadline });
    expect(await runMouseCommand(["mouse-keep"], deps)).toMatchObject({ sharing: true, until: null });
  });
});

test("transient unit names, deadlines and literal Bun argv", () => {
  expect(POINTER_UNITS).toEqual({ timer: "lattices-pointer-trial.timer", home: "lattices-pointer-trial.service", watch: "lattices-pointer-watch.service" });
  const executable = '/tmp/bun space/%$"\\';
  const script = "/tmp/checkout $HOME/%h/main.ts";
  const units = pointerTrialUnits(60_000, { executable, script, environment: { HYPRLAND_INSTANCE_SIGNATURE: "hypr", PATH: "/usr/bin", SECRET: "never forwarded" } });
  const value = (props: typeof units.timer, key: string) => props.find(([name]) => name === key)![1];
  expect(value(units.timer, "TimersMonotonic").signature).toBe("a(st)");
  expect(value(units.timer, "TimersMonotonic").value).toEqual([["OnActiveSec", 60_000_000n]]);
  expect(value(units.timer, "AccuracyUSec").value).toBe(100_000n);
  expect(value(units.home, "ExecStartEx").signature).toBe("a(sasas)");
  expect(value(units.home, "ExecStartEx").value).toEqual([[executable, [executable, script, "mouse-home", "--expired"], ["no-env-expand"]]]);
  expect(value(units.watch, "ExecStartEx").value).toEqual([[executable, [executable, script, "mouse-check"], ["no-env-expand"]]]);
  expect(value(units.watch, "Environment").value).toEqual(["PATH=/usr/bin", "HYPRLAND_INSTANCE_SIGNATURE=hypr", "LATTICES_POINTER_ROLE=watchdog"]);
  expect(value(units.watch, "Restart").value).toBe("on-failure");
  for (const props of Object.values(units)) expect(value(props, "CollectMode").value).toBe("inactive-or-failed");
});

test("deadline uses systemd timestamps across fresh Bun processes", () => {
  const real = BigInt(Date.parse("2026-10-09T21:00:00.000Z")) * 1000n;
  expect(pointerTrialDeadline(188_860_000_000n, real, 188_800_000_000n)).toBe("2026-10-09T21:01:00.000Z");
  expect(pointerTrialDeadline(0n, real, 1000n)).toBeNull();
  expect(pointerTrialDeadline(18_446_744_073_709_551_615n, real, 1000n)).toBeNull();
});

describe("pointer trial lifecycle with faked systemd and lan-mouse", () => {
  test("starts a stopped service, arms before activating every client, and reads persistent status", async () => {
    const { deps, calls, logs } = fake();
    const state = await startPointerTrial(undefined, deps);
    expect(state).toMatchObject({ sharing: true, until: deadline });
    expect(calls).not.toContainEqual(["start"]);
    expect(calls.indexOf(calls.find(([cmd]) => cmd === "arm")!)).toBeLessThan(calls.indexOf(calls.find(([, , verb]) => verb === "activate")!));
    expect(calls).toContainEqual(["lan-mouse", "cli", "activate", "0"]);
    expect(calls).toContainEqual(["lan-mouse", "cli", "activate", "2"]);
    expect(logs).toEqual([`start until=${deadline}`]);
    expect(await pointerState(deps)).toMatchObject({ sharing: true, until: deadline });
    await keepPointerSharing(deps);
    expect(await pointerState(deps)).toMatchObject({ sharing: true, until: null });
    expect(logs.at(-1)).toBe("keep");
    const f = fake(); f.setRunning(false);
    await startPointerTrial("1m", f.deps);
    expect(f.calls).toContainEqual(["start"]);
    expect(f.calls).toContainEqual(["arm", "60000"]);
  });
  test("startup socket retries are bounded and invalid durations have no effects", async () => {
    const f = fake(); f.setRunning(false);
    const base = f.deps.run;
    let attempts = 0;
    f.deps.run = (cmd, args, options) => cmd === "lan-mouse" && args[1] === "list" && attempts++ < 2 ? Promise.reject(new Error("starting")) : base(cmd, args, options);
    await startPointerTrial("90", f.deps);
    expect(f.sleeps).toEqual([100]);
    const bad = fake();
    await expect(startPointerTrial("bad", bad.deps)).rejects.toThrow();
    expect(bad.calls).toEqual([]);
  });
  test("keep is idempotent and never activates clients", async () => {
    const f = fake();
    expect(await keepPointerSharing(f.deps)).toMatchObject({ sharing: false, until: null });
    expect(await keepPointerSharing(f.deps)).toMatchObject({ sharing: false, until: null });
    expect(f.calls.some(([, , verb]) => verb === "activate")).toBe(false);
  });
  test("an unmanaged responsive daemon is used without starting another service", async () => {
    const f = fake(); f.deps.serviceState = async () => "inactive";
    await startPointerTrial("1m", f.deps);
    expect(f.calls).not.toContainEqual(["start"]);
  });
  test("home, Share off and expiry cancel the trial and release before warping", async () => {
    for (const mode of ["home", "off", "expiry"] as const) {
      const f = fake(); await startPointerTrial("1m", f.deps); f.calls.length = 0;
      if (mode === "off") await sharePointer(false, f.deps);
      else await bringCursorHome(f.deps, mode === "expiry" ? "expiry" : undefined);
      expect(f.calls[0]).toEqual(["cancel"]);
      expect(await pointerState(f.deps)).toMatchObject({ sharing: false, until: null });
      expect(f.calls).toContainEqual(["hyprctl", "dispatch", "movecursor", "3640", "720"]);
      if (mode === "expiry") expect(f.logs).toEqual([`start until=${deadline}`, "expiry revert"]);
    }
  });
  test("arming, listing and partial activation errors revert sharing", async () => {
    for (const mode of ["arm", "list", "activate", "empty"] as const) {
      const f = fake(); const base = f.deps.run;
      if (mode === "arm") f.deps.trial.arm = async () => { throw new Error("arming failed"); };
      f.deps.run = (cmd, args, options) => {
        if (cmd === "lan-mouse" && args[1] === mode) return Promise.reject(new Error(`${mode} failed`));
        if (mode === "empty" && cmd === "lan-mouse" && args[1] === "list") return Promise.resolve("");
        return base(cmd, args, options);
      };
      await expect(startPointerTrial("1m", f.deps)).rejects.toThrow();
      expect(f.calls).toContainEqual(["hyprctl", "dispatch", "movecursor", "3640", "720"]);
      expect(await f.deps.trial.until()).toBeNull();
      expect(f.logs).toEqual([]);
    }
  });
  test("rollback waits for a late activation before releasing clients", async () => {
    const f = fake(); const base = f.deps.run;
    let finishActivation: () => void = () => {};
    const late = new Promise<void>((resolve) => { finishActivation = resolve; });
    f.deps.run = async (cmd, args, options) => {
      if (cmd === "lan-mouse" && args[1] === "activate") {
        if (args[2] === "0") throw new Error("first activation failed");
        await late;
      }
      return base(cmd, args, options);
    };
    const share = startPointerTrial("1m", f.deps);
    await Bun.sleep(1);
    expect(f.calls.some(([, , verb]) => verb === "deactivate")).toBe(false);
    finishActivation();
    await expect(share).rejects.toThrow("first activation failed");
    expect(await pointerState(f.deps)).toMatchObject({ sharing: false, until: null });
  });
  test("cancellation errors do not prevent recovery", async () => {
    const f = fake();
    f.deps.trial.cancel = async () => { throw new Error("systemd unavailable"); };
    const receipt = await bringCursorHome(f.deps);
    expect(receipt.ok).toBe(true);
    expect(receipt.release.errors).toEqual(["Error: systemd unavailable"]);
  });
  test("watchdog is passive outside trials, resets on success, and reverts on two failures", async () => {
    const f = fake();
    await watchPointerTrial(f.deps);
    expect(f.calls).toEqual([]); expect(f.sleeps).toEqual([]);
    f.setUntil(deadline);
    const base = f.deps.run;
    let checks = 0;
    f.deps.run = (cmd, args, options) => {
      if (cmd === "lan-mouse" && args[1] === "list") {
        checks++;
        if ([1, 3, 4, 5].includes(checks)) return Promise.reject(new Error("unreachable"));
      }
      return base(cmd, args, options);
    };
    await watchPointerTrial(f.deps);
    expect(f.sleeps).toEqual([15_000, 15_000, 15_000, 15_000]);
    expect(f.calls).toContainEqual(["restart"]); // Recovery also saw the unreachable CLI.
    expect(f.logs).toEqual(["watchdog revert"]);
    expect(await f.deps.trial.until()).toBeNull();
    expect(f.calls.at(-1)).toEqual(["hyprctl", "dispatch", "movecursor", "3640", "720"]);
  });
  test("keep during a watchdog sleep prevents another CLI check", async () => {
    const f = fake(); f.setUntil(deadline);
    f.deps.sleep = async () => { await f.deps.trial.cancel(); };
    await watchPointerTrial(f.deps);
    expect(f.calls).toEqual([["cancel"]]);
  });
  test("matching endpoints are discoverable and share/keep/status dispatch with fakes", async () => {
    const f = fake(); const router = new Router(() => new Set(["spaces.read"]));
    registerEndpoints(router, { bindHost: "127.0.0.1", startedAt: 0, clientCount: () => 0 }, f.deps);
    expect(router.available().filter((e) => e.method.startsWith("mouse.")).map((e) => [e.method, e.access])).toEqual([
      ["mouse.share", "mutate"], ["mouse.keep", "mutate"], ["mouse.status", "read"], ["mouse.home", "mutate"],
    ]);
    expect(await router.dispatch("mouse.share", { for: "1m" })).toEqual({ sharing: true, until: deadline });
    expect(await router.dispatch("mouse.status", {})).toEqual({ sharing: true, clients: [
      { id: "0", host: "mini", position: "left", active: true },
      { id: "2", host: "other", position: "right", active: true },
    ], until: deadline });
    expect(await router.dispatch("mouse.keep", {})).toEqual({ sharing: true, until: null });
    await expect(router.dispatch("mouse.share", { for: 90 })).rejects.toThrow("duration string");
    await expect(router.dispatch("mouse.share", { for: "" })).rejects.toThrow("Duration");
  });
});

test("Keep Sharing has a fixed label immediately below Share Pointer only during a trial", () => {
  const state = { available: true, sharing: true, until: deadline };
  expect(pointerMenu(state, false).map((item) => [item.id, item.label])).toEqual([[1, "Bring Cursor Home"], [2, "Share Pointer"], [8, "Keep Sharing"]]);
  expect(pointerMenu({ ...state, until: null }, false)).toHaveLength(2);
  expect(pointerMenu({ ...state, sharing: false }, false)[2].label).toBe("Keep Sharing");
  expect(pointerMenu(state, true).every((item) => !item.enabled)).toBe(true);
  expect(pointerMenu({ available: true, sharing: false, until: null }, false)[1].enabled).toBe(true);
});
