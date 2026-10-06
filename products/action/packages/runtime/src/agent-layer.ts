import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { resolve } from "node:path";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { promisify } from "node:util";

import type {
  AgentLayerOwner,
  AgentLayerState,
  AgentLayerStatus,
  AgentLayerSubject,
} from "@action/protocol";

import type { AgentLayerRouting } from "./interaction/index.js";

const execFileAsync = promisify(execFile);

const DEFAULT_OWNER: AgentLayerOwner = "caller";
const STATE_POLL_MS = 40;
const DEFAULT_STATE_WAIT_MS = 3000;
const DEFAULT_CLOSE_WAIT_MS = 3000;
const SIGTERM_WAIT_MS = 1500;
const CONTROL_WAIT_MS = 1500;
const RECORD_WAIT_MS = 5000;

export type AgentLayerHostRunner = (args: string[]) => Promise<{ stdout: string }>;

export interface AgentLayerOpenInput {
  bundleId?: string;
  pid?: number;
  width?: number;
  height?: number;
  pip?: boolean;
  /** Move only this window (CGWindowID / kCGWindowNumber) instead of all the app's windows. */
  windowId?: number;
  /** Move only windows whose title contains this, case-insensitively. */
  windowTitle?: string;
  /**
   * Open this in the subject app without activating it, once its windows are on the
   * layer. A bare host reads as https. Needs bundleId or pid.
   */
  url?: string;
  /**
   * Don't ask the app for a window when it has none: the caller makes one itself, right
   * on the layer (a browser through DevTools). Windows that appear are still adopted.
   */
  windowless?: boolean;
  owner?: AgentLayerOwner;
}

export interface AgentLayerMark {
  kind: "aim" | "click" | "drag" | "scroll" | "field";
  point?: { x: number; y: number };
  from?: { x: number; y: number };
  frame?: { x: number; y: number; width: number; height: number };
  dy?: number;
}

export interface AgentLayerSnapshotInput {
  /** Crop to this window (kCGWindowNumber). Must be on the layer. */
  windowId?: number;
  /** The whole layer instead of the subject's windows. */
  full?: boolean;
  /** PNG path. Defaults to the layer's snapshots folder. */
  out?: string;
}

export interface AgentLayerSnapshot {
  ok: boolean;
  path?: string;
  width?: number;
  height?: number;
  /** Display-local points on the layer. */
  crop?: { x: number; y: number; width: number; height: number };
  windowId?: number | null;
  /** Time since the layer last changed: the frame is current, this is how long it's been still. */
  unchangedMs?: number;
  detail?: string;
}

/** Sidecar the director writes next to the native state file: who asked, and for what. */
interface AgentLayerRequest {
  owner: AgentLayerOwner;
  ownerPid?: number;
  subject?: AgentLayerSubject;
  pid?: number;
}

export interface AgentLayerDirectorOptions {
  root?: string;
  runHost?: AgentLayerHostRunner;
  /** Liveness probe. Defaults to `process.kill(pid, 0)`. */
  isAlive?: (pid: number) => boolean;
  /** Sends SIGTERM. Defaults to `process.kill(pid, "SIGTERM")`. */
  terminate?: (pid: number) => void;
  stateWaitMs?: number;
  closeWaitMs?: number;
}

export function agentLayerStateDir(): string {
  return resolve(homedir(), "Library/Application Support/Action/agent-layer");
}

export function parseAgentLayerOpen(input: {
  bundleId?: unknown;
  pid?: unknown;
  width?: unknown;
  height?: unknown;
  pip?: unknown;
  windowId?: unknown;
  windowTitle?: unknown;
  url?: unknown;
  owner?: unknown;
  windowless?: unknown;
}): AgentLayerOpenInput {
  const bundleId = typeof input.bundleId === "string" && input.bundleId.trim() ? input.bundleId.trim() : undefined;
  const pid = optionalPositiveInt(input.pid, "pid");
  if (bundleId && pid !== undefined) {
    throw new Error("Pass bundleId or pid, not both");
  }
  const width = optionalPositiveInt(input.width, "width");
  const height = optionalPositiveInt(input.height, "height");
  if ((width === undefined) !== (height === undefined)) {
    throw new Error("width and height go together");
  }
  const pip = input.pip === undefined || input.pip === null ? undefined : input.pip !== false && input.pip !== "off" && input.pip !== "false";
  const windowId = optionalPositiveInt(input.windowId, "windowId");
  const windowTitle = typeof input.windowTitle === "string" && input.windowTitle.trim() ? input.windowTitle.trim() : undefined;
  const url = typeof input.url === "string" && input.url.trim() ? input.url.trim() : undefined;
  if (url && !bundleId && pid === undefined) {
    throw new Error('url needs the app to open it in: pass bundleId too, e.g. "com.apple.Safari"');
  }
  if (url && (windowId !== undefined || windowTitle)) {
    // The app picks the window a URL lands in, which may be one the operator still has.
    throw new Error("url opens in the app's front window, so it can't be combined with windowId or windowTitle");
  }
  const owner: AgentLayerOwner = input.owner === "detached" ? "detached" : DEFAULT_OWNER;
  return {
    ...(bundleId ? { bundleId } : {}),
    ...(pid !== undefined ? { pid } : {}),
    ...(width !== undefined ? { width, height } : {}),
    ...(pip !== undefined ? { pip } : {}),
    ...(windowId !== undefined ? { windowId } : {}),
    ...(windowTitle ? { windowTitle } : {}),
    ...(url ? { url } : {}),
    ...(input.windowless === true ? { windowless: true } : {}),
    owner,
  };
}

function optionalPositiveInt(value: unknown, name: string): number | undefined {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return number;
}

/** The layer's app: the requested subject, else the first window that moved onto it. */
export function agentLayerSubject(status: AgentLayerStatus): AgentLayerSubject | undefined {
  if (status.subject?.bundleId || status.subject?.pid) {
    return status.subject;
  }
  const first = status.layer?.windows[0];
  if (!first) {
    return undefined;
  }
  return first.bundleId ? { bundleId: first.bundleId } : { pid: first.pid };
}

/** What the interaction router needs from a status, or undefined when no layer is up. */
export function agentLayerRouting(status: AgentLayerStatus): AgentLayerRouting | undefined {
  if (!status.active || !status.layer) {
    return undefined;
  }
  const subject = agentLayerSubject(status);
  return {
    ...(subject?.bundleId ? { bundleId: subject.bundleId } : {}),
    ...(subject?.pid ? { pid: subject.pid } : {}),
    bounds: status.layer.bounds,
  };
}

function defaultIsAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function defaultTerminate(pid: number): void {
  try {
    process.kill(pid, "SIGTERM");
  } catch {
    // Already gone.
  }
}

export class AgentLayerDirector {
  private readonly root: string;
  private readonly runHost: AgentLayerHostRunner;
  private readonly isAlive: (pid: number) => boolean;
  private readonly terminate: (pid: number) => void;
  private readonly stateWaitMs: number;
  private readonly closeWaitMs: number;

  constructor(
    private readonly nativeHostPath: string,
    options: AgentLayerDirectorOptions = {},
  ) {
    this.root = options.root ?? agentLayerStateDir();
    this.runHost = options.runHost ?? ((args) => execFileAsync(this.nativeHostPath, args));
    this.isAlive = options.isAlive ?? defaultIsAlive;
    this.terminate = options.terminate ?? defaultTerminate;
    this.stateWaitMs = options.stateWaitMs ?? DEFAULT_STATE_WAIT_MS;
    this.closeWaitMs = options.closeWaitMs ?? DEFAULT_CLOSE_WAIT_MS;
  }

  paths() {
    return {
      stop: resolve(this.root, "layer.stop"),
      state: resolve(this.root, "state.json"),
      request: resolve(this.root, "request.json"),
      log: resolve(this.root, "layer.log"),
      controlRequest: resolve(this.root, "control.request.json"),
      controlReply: resolve(this.root, "control.reply.json"),
      handoff: resolve(this.root, "handoff.json"),
    };
  }

  /**
   * Put one layer up. One layer at a time: an existing layer is closed first, so its
   * windows go back to their original frames before the new subject moves over.
   */
  async open(input: Parameters<typeof parseAgentLayerOpen>[0] = {}): Promise<AgentLayerStatus> {
    const request = parseAgentLayerOpen(input);
    const owner = request.owner ?? DEFAULT_OWNER;
    const closed = await this.close();
    if (closed.active) {
      throw new Error(`Previous agent layer (pid ${closed.pid}) did not exit; refusing to open another`);
    }

    const paths = this.paths();
    await mkdir(this.root, { recursive: true });
    await rm(paths.stop, { force: true });
    await rm(paths.state, { force: true });
    await rm(paths.log, { force: true });

    const args = ["agent-layer", "--stop-file", paths.stop, "--state-file", paths.state, "--debug-log", paths.log];
    // Same rule as the stage drape: a caller-owned layer watches this process and
    // restores the windows if it dies. A one-shot CLI exits right after open, so it
    // asks for `detached` and relies on `layer close`.
    if (owner === "caller") {
      args.push("--parent-pid", String(process.pid));
    }
    // Where the viewer's "go to owner" goes. A detached CLI is gone by then, so the
    // chain is taken now.
    const owners = await processAncestry(process.pid);
    if (owners.length > 0) {
      args.push("--owner-pids", owners.join(","));
    }
    if (request.bundleId) {
      args.push("--bundle-id", request.bundleId);
    } else if (request.pid !== undefined) {
      args.push("--pid", String(request.pid));
    }
    if (request.width !== undefined && request.height !== undefined) {
      args.push("--width", String(request.width), "--height", String(request.height));
    }
    if (request.pip !== undefined) {
      args.push("--pip", request.pip ? "on" : "off");
    }
    if (request.windowId !== undefined) {
      args.push("--window-id", String(request.windowId));
    }
    if (request.windowTitle) {
      args.push("--window-title", request.windowTitle);
    }
    if (request.url) {
      args.push("--url", request.url);
    }
    if (request.windowless) {
      args.push("--windowless", "1");
    }

    const { stdout } = await this.runHost(args);
    const response = JSON.parse(stdout.trim() || "{}") as { status?: string; detail?: string };
    if (response.status !== "agent-layer-running") {
      throw new Error(`agent-layer did not start: ${response.detail ?? response.status ?? "no reply"}`);
    }
    const parsedPid = response.detail ? Number(response.detail) : Number.NaN;
    const replyPid = Number.isFinite(parsedPid) && parsedPid > 0 ? parsedPid : undefined;

    const subject: AgentLayerSubject | undefined = request.bundleId
      ? { bundleId: request.bundleId }
      : request.pid !== undefined
        ? { pid: request.pid }
        : undefined;
    // Record the pid before waiting on the state file, so a layer whose state never
    // lands can still be closed.
    const sidecar: AgentLayerRequest = {
      owner,
      ...(owner === "caller" ? { ownerPid: process.pid } : {}),
      ...(subject ? { subject } : {}),
      ...(replyPid ? { pid: replyPid } : {}),
    };
    await writeFile(paths.request, `${JSON.stringify(sidecar, null, 2)}\n`);

    const state = await this.waitForState(this.stateWaitMs);
    if (!state) {
      await this.close();
      throw new Error("agent-layer replied but never wrote its state file");
    }
    if (!sidecar.pid) {
      sidecar.pid = state.pid;
      await writeFile(paths.request, `${JSON.stringify(sidecar, null, 2)}\n`);
    }
    return this.describe(sidecar, state, true);
  }

  /** Touch the stop file, wait for the layer to restore windows and exit, SIGTERM if not. */
  async close(): Promise<AgentLayerStatus> {
    const paths = this.paths();
    // Closing (or opening, which closes first) acknowledges an operator takeover.
    await rm(paths.handoff, { force: true });
    const request = await this.readRequest();
    const state = await this.readState();
    const pid = state?.pid ?? request?.pid;
    const owner = request?.owner ?? DEFAULT_OWNER;

    if (!pid && !state && !request) {
      return { active: false, owner };
    }

    await mkdir(this.root, { recursive: true });
    await writeFile(paths.stop, "stop\n");

    let gone = pid ? await this.waitForExit(pid, this.closeWaitMs) : true;
    if (!gone && pid) {
      this.terminate(pid);
      gone = await this.waitForExit(pid, SIGTERM_WAIT_MS);
    }

    if (gone) {
      await rm(paths.state, { force: true });
      await rm(paths.request, { force: true });
      await rm(paths.stop, { force: true });
    }
    return {
      // A layer still up after the stop file and SIGTERM holds the user's windows.
      // Report it rather than calling it closed.
      active: !gone,
      owner,
      ...(request?.subject ? { subject: request.subject } : {}),
      ...(gone ? {} : { pid }),
    };
  }

  /** Brings the PiP viewer back after the user dismissed it. The layer itself never stopped. */
  async showViewer(): Promise<AgentLayerStatus> {
    const status = await this.status();
    if (!status.active || !status.layer) {
      throw new Error("No agent layer is up");
    }
    if (!status.layer.pip) {
      process.kill(status.layer.pid, "SIGUSR1");
      const deadline = Date.now() + 1000;
      while (Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 50));
        const next = await this.status();
        if (next.layer?.pip) {
          return next;
        }
      }
    }
    return this.status();
  }

  /**
   * A PNG of one window on the layer (or the subject's windows, or the whole layer),
   * cut from the layer's running feed. Nothing is captured on request: the layer
   * already holds the current frame, so this answers in milliseconds.
   */
  async snapshot(input: AgentLayerSnapshotInput = {}): Promise<AgentLayerSnapshot> {
    const out = resolve(input.out ?? resolve(this.root, "snapshots", `layer-${Date.now()}.png`));
    return this.control<AgentLayerSnapshot>("snapshot", {
      out,
      ...(input.windowId !== undefined ? { windowId: input.windowId } : {}),
      full: input.full === true,
    });
  }

  /**
   * Record the layer to a movie off the same running feed the viewer shows, so the
   * take starts on the next frame. One take at a time; `stopRecording` finishes it.
   */
  async startRecording(input: { out?: string } = {}): Promise<{ ok: boolean; path?: string }> {
    const out = resolve(input.out ?? resolve(this.root, "recordings", `layer-${Date.now()}.mov`));
    return this.control("record-start", { out }, RECORD_WAIT_MS);
  }

  async stopRecording(): Promise<{ ok: boolean; path?: string }> {
    return this.control("record-stop", {}, RECORD_WAIT_MS);
  }

  /**
   * Show an act on the viewer, for acts the layer's host did not run (DevTools input
   * into a browser on the layer): the pointer gliding to it, a press, a trail, a field
   * lighting up. Global top-left points.
   */
  async mark(act: AgentLayerMark): Promise<void> {
    await this.control("mark", {
      kind: act.kind,
      ...(act.point ? { x: act.point.x, y: act.point.y } : {}),
      ...(act.from ? { fromX: act.from.x, fromY: act.from.y } : {}),
      ...(act.frame ? { fx: act.frame.x, fy: act.frame.y, fw: act.frame.width, fh: act.frame.height } : {}),
      ...(act.dy !== undefined ? { dy: act.dy } : {}),
    });
  }

  /** Leaves a request next to the state file, signals the layer, and waits for its reply. */
  private async control<T extends { ok: boolean; detail?: string }>(
    op: string,
    payload: Record<string, unknown>,
    budgetMs = CONTROL_WAIT_MS,
  ): Promise<T> {
    const status = await this.status();
    if (!status.active || !status.layer) {
      throw new Error("No agent layer is up");
    }
    const paths = this.paths();
    const id = randomUUID();
    await rm(paths.controlReply, { force: true });
    await writeFile(paths.controlRequest, `${JSON.stringify({ id, op, ...payload })}\n`);
    process.kill(status.layer.pid, "SIGUSR2");
    const deadline = Date.now() + budgetMs;
    for (;;) {
      const reply = await readJson<T & { id?: string }>(paths.controlReply);
      if (reply?.id === id) {
        const { id: _id, ...result } = reply;
        if (!result.ok) {
          throw new Error(`agent-layer ${op} failed: ${result.detail ?? "no detail"}`);
        }
        return result as unknown as T;
      }
      if (Date.now() >= deadline) {
        throw new Error(`agent-layer did not answer ${op}`);
      }
      await delay(10);
    }
  }

  /** The live layer, or an inactive status. Stale files from a dead layer are removed. */
  async status(): Promise<AgentLayerStatus> {
    const request = await this.readRequest();
    const state = await this.readState();
    const owner = request?.owner ?? DEFAULT_OWNER;
    const pid = state?.pid ?? request?.pid;
    if (!pid) {
      if (state || request) {
        await this.clearFiles();
      }
      return { active: false, owner };
    }
    if (!this.isAlive(pid)) {
      await this.clearFiles();
      return { active: false, owner };
    }
    if (!state) {
      // Alive but no state yet (still starting, or state lost). Closable, not routable.
      return {
        active: true,
        owner,
        pid,
        ...(request?.subject ? { subject: request.subject } : {}),
        stopFile: this.paths().stop,
      };
    }
    return this.describe(request ?? { owner }, state, true);
  }

  /**
   * Why an agent act must not run right now, or undefined when it may: the operator
   * paused the layer from its viewer, or took the windows back.
   */
  async actRefusal(): Promise<string | undefined> {
    const status = await this.status();
    if (status.active && status.layer?.paused) {
      return "The operator paused the agent layer from its viewer. Wait for them to resume it.";
    }
    if (!status.active) {
      const handoff = await readJson<{ at?: string }>(this.paths().handoff);
      if (handoff) {
        return `The operator took over the agent layer${handoff.at ? ` at ${handoff.at}` : ""} and the windows are back on their desktop. Open a new layer (or close it to acknowledge) before acting again.`;
      }
    }
    return undefined;
  }

  /** Routing input for the interaction layer, or undefined when no layer is up. */
  async routing(): Promise<AgentLayerRouting | undefined> {
    return agentLayerRouting(await this.status());
  }

  private describe(request: AgentLayerRequest, state: AgentLayerState, active: boolean): AgentLayerStatus {
    const paths = this.paths();
    return {
      active,
      owner: request.owner,
      ...(request.ownerPid ? { ownerPid: request.ownerPid } : {}),
      ...(request.subject ? { subject: request.subject } : {}),
      stopFile: paths.stop,
      stateFile: paths.state,
      layer: state,
    };
  }

  private async clearFiles(): Promise<void> {
    const paths = this.paths();
    await rm(paths.state, { force: true });
    await rm(paths.request, { force: true });
    await rm(paths.stop, { force: true });
  }

  private async waitForState(budgetMs: number): Promise<AgentLayerState | undefined> {
    const deadline = Date.now() + budgetMs;
    for (;;) {
      const state = await this.readState();
      if (state) {
        return state;
      }
      if (Date.now() >= deadline) {
        return undefined;
      }
      await delay(STATE_POLL_MS);
    }
  }

  private async waitForExit(pid: number, budgetMs: number): Promise<boolean> {
    const deadline = Date.now() + budgetMs;
    for (;;) {
      if (!this.isAlive(pid)) {
        return true;
      }
      if (Date.now() >= deadline) {
        return false;
      }
      await delay(STATE_POLL_MS);
    }
  }

  private async readState(): Promise<AgentLayerState | undefined> {
    const parsed = await readJson<AgentLayerState>(this.paths().state);
    return parsed && typeof parsed.pid === "number" && parsed.bounds ? parsed : undefined;
  }

  private async readRequest(): Promise<AgentLayerRequest | undefined> {
    return readJson<AgentLayerRequest>(this.paths().request);
  }
}

/** `pid` and its parents, nearest first, stopping before launchd. */
async function processAncestry(pid: number): Promise<number[]> {
  let table: string;
  try {
    ({ stdout: table } = await execFileAsync("/bin/ps", ["-A", "-o", "pid=,ppid="]));
  } catch {
    return [pid];
  }
  const parents = new Map<number, number>();
  for (const line of table.split("\n")) {
    const [child, parent] = line.trim().split(/\s+/).map(Number);
    if (child && parent !== undefined) {
      parents.set(child, parent);
    }
  }
  const chain: number[] = [];
  for (let current = pid; current > 1 && chain.length < 16; current = parents.get(current) ?? 0) {
    chain.push(current);
  }
  return chain;
}

async function readJson<T>(path: string): Promise<T | undefined> {
  try {
    return JSON.parse(await readFile(path, "utf8")) as T;
  } catch {
    return undefined;
  }
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolveWait) => setTimeout(resolveWait, milliseconds));
}
