// Virtual displays: headless Hyprland outputs the host creates for remote
// viewers. The host only removes outputs it created (or was told to adopt);
// ownership lives in ~/.lattices/host-displays.json so it survives restarts.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { run } from "./exec.ts";
import * as hypr from "./hyprland.ts";
import { RouterError } from "./router.ts";

export const REGISTRY_PATH = join(homedir(), ".lattices", "host-displays.json");

export interface Owned {
  name: string;
  createdAt: number;
  adopted?: boolean;
}

export function readOwned(path = REGISTRY_PATH): Owned[] {
  try {
    const parsed = JSON.parse(readFileSync(path, "utf8")) as { outputs?: Owned[] };
    return Array.isArray(parsed.outputs) ? parsed.outputs.filter((o) => typeof o?.name === "string") : [];
  } catch {
    return [];
  }
}

function writeOwned(outputs: Owned[], path = REGISTRY_PATH) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify({ outputs }, null, 2) + "\n");
}

/** Output names Hyprland accepts and Lua quoting can't break. */
export function validName(name: string): boolean {
  return /^[A-Za-z0-9_-]{1,32}$/.test(name);
}

/** The first LATS-n not taken by a live output. */
export function nextName(taken: string[]): string {
  for (let n = 1; ; n++) if (!taken.includes(`LATS-${n}`)) return `LATS-${n}`;
}

export interface Spec {
  width: number;
  height: number;
  scale: number;
  refresh: number;
}

/** The monitor rule, as Lua (0.55+, which refuses `keyword`) or a legacy keyword. */
export function monitorRule(name: string, spec: Spec, lua: boolean): string[] {
  const mode = `${Math.round(spec.width)}x${Math.round(spec.height)}@${Math.round(spec.refresh)}`;
  return lua
    ? ["eval", `hl.monitor({ output = ${JSON.stringify(name)}, mode = ${JSON.stringify(mode)}, position = "auto", scale = ${spec.scale} })`]
    : ["keyword", "monitor", `${name},${mode},auto,${spec.scale}`];
}

async function hyprctl(args: string[]) {
  const out = (await run("hyprctl", args)).trim();
  if (out !== "ok") throw new Error(`hyprctl ${args[0]}: ${out}`);
}

async function waitForOutput(name: string, present: boolean) {
  for (let i = 0; i < 20; i++) {
    const live = (await hypr.monitors()).some((m) => m.name === name);
    if (live === present) return;
    await Bun.sleep(50);
  }
  throw new Error(`output ${name} did not ${present ? "appear" : "go away"}`);
}

export async function create(opts: { name?: string; spec: Spec; adopt?: boolean }) {
  const monitors = await hypr.monitors();
  const name = opts.name ?? nextName(monitors.map((m) => m.name));
  if (!validName(name)) throw new RouterError(`Invalid display name: ${name}`);
  const existing = monitors.find((m) => m.name === name);
  const owned = readOwned();
  const trace: string[] = [];

  if (existing) {
    if (!owned.some((o) => o.name === name) && !opts.adopt) {
      throw new RouterError(`Display ${name} already exists and was not created by this host; pass adopt: true to manage it`);
    }
  } else {
    await hyprctl(["output", "create", "headless", name]);
    trace.push(`output create headless ${name}`);
    await waitForOutput(name, true);
  }
  const rule = monitorRule(name, opts.spec, await hypr.usesLua());
  await hyprctl(rule);
  trace.push(rule.join(" "));
  if (!owned.some((o) => o.name === name)) {
    writeOwned([...owned, { name, createdAt: Date.now(), ...(existing ? { adopted: true } : {}) }]);
  }
  return { name, created: !existing, adopted: Boolean(existing), trace };
}

export async function remove(name: string) {
  const owned = readOwned();
  if (!owned.some((o) => o.name === name)) {
    throw new RouterError(`Display ${name} was not created by this host; refusing to remove it`);
  }
  const live = (await hypr.monitors()).some((m) => m.name === name);
  if (live) {
    await hyprctl(["output", "remove", name]);
    await waitForOutput(name, false);
  }
  writeOwned(owned.filter((o) => o.name !== name));
  return { name, removed: live };
}
