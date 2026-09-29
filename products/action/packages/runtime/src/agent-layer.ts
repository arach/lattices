import { execFile } from "node:child_process";
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

export type AgentLayerHostRunner = (args: string[]) => Promise<{ stdout: string }>;

export interface AgentLayerOpenInput {
  bundleId?: string;
  pid?: number;
  width?: number;
  height?: number;
  pip?: boolean;
  owner?: AgentLayerOwner;
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
  owner?: unknown;
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
  const owner: AgentLayerOwner = input.owner === "detached" ? "detached" : DEFAULT_OWNER;
  return {
    ...(bundleId ? { bundleId } : {}),
    ...(pid !== undefined ? { pid } : {}),
    ...(width !== undefined ? { width, height } : {}),
    ...(pip !== undefined ? { pip } : {}),
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
