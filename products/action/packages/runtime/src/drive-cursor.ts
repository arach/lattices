import { access, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";

import type {
  AxActionTier,
  DriveLease,
  Point,
  ResolvedTarget,
  RuntimeAction,
} from "@action/protocol";

export const AGENT_CURSOR_IDLE_EXPIRY_MS = 90_000;

export interface AgentCursorHighlight {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface AgentCursorState {
  x?: number;
  y?: number;
  agent?: string;
  label?: string;
  phase?: "idle" | "click" | "type" | "key" | "countdown" | string;
  typingText?: string;
  keyLabel?: string;
  countdown?: number;
  cueId?: string;
  highlight?: AgentCursorHighlight;
  expiresAt?: string;
  updatedAt?: string;
}

function cursorDirectory(): string {
  return join(homedir(), "Library/Application Support/Action/runtime/drive/cursors");
}

function sanitizeID(raw: string): string {
  return raw.replace(/[^A-Za-z0-9._-]+/g, "_");
}

export function agentCursorStatePath(leaseId: string): string {
  return join(cursorDirectory(), `${sanitizeID(leaseId)}.json`);
}

export function agentCursorStopPath(leaseId: string): string {
  return `${agentCursorStatePath(leaseId)}.stop`;
}

export function agentCursorExpiration(updatedAt: string): string {
  const parsed = Date.parse(updatedAt);
  const base = Number.isFinite(parsed) ? parsed : Date.now();
  return new Date(base + AGENT_CURSOR_IDLE_EXPIRY_MS).toISOString();
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

export async function startAgentCursor(input: {
  nativeHostPath: string;
  lease: DriveLease;
  point?: Point;
  label?: string;
}): Promise<void> {
  const statePath = agentCursorStatePath(input.lease.leaseId);
  const stopPath = agentCursorStopPath(input.lease.leaseId);
  await mkdir(cursorDirectory(), { recursive: true });

  if (await pathExists(statePath)) {
    await writeFile(stopPath, "stop\n");
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 200));
  }
  await rm(stopPath, { force: true });

  const updatedAt = new Date().toISOString();
  const state: AgentCursorState = {
    x: input.point?.x,
    y: input.point?.y,
    agent: input.lease.agent,
    label: input.label ?? input.lease.task,
    phase: "idle",
    expiresAt: agentCursorExpiration(updatedAt),
    updatedAt,
  };
  await writeFile(statePath, `${JSON.stringify(state, null, 2)}\n`);

  await spawnHostDetached(input.nativeHostPath, [
    "agent-cursor-overlay",
    "--state-file",
    statePath,
    "--stop-file",
    stopPath,
    "--lease-stop-file",
    input.lease.stopFile,
  ]);
}

export async function readAgentCursorState(leaseId: string): Promise<AgentCursorState | undefined> {
  try {
    return JSON.parse(await readFile(agentCursorStatePath(leaseId), "utf8")) as AgentCursorState;
  } catch {
    return undefined;
  }
}

/** Milliseconds to wait after aiming so the overlay warp finishes before the act. */
export function cursorTravelMs(from: Point | undefined, to: Point): number {
  if (!from || !Number.isFinite(from.x) || !Number.isFinite(from.y)) {
    return 220;
  }
  const distance = Math.hypot(to.x - from.x, to.y - from.y);
  if (distance < 2) {
    return 80;
  }
  // Match the native overlay warp, then a short settle so the strike reads after arrival.
  return Math.min(380, Math.max(110, distance / 2.4)) + 90;
}

export async function updateAgentCursor(input: {
  leaseId: string;
  agent?: string;
  point?: Point;
  label?: string;
  phase?: "idle" | "click" | "type" | "key" | "countdown";
  typingText?: string;
  keyLabel?: string;
  countdown?: number;
  cueId?: string;
  highlight?: AgentCursorHighlight | null;
}): Promise<void> {
  const statePath = agentCursorStatePath(input.leaseId);
  let previous: AgentCursorState = {};
  try {
    previous = JSON.parse(await readFile(statePath, "utf8")) as AgentCursorState;
  } catch {
    return;
  }

  const updatedAt = new Date().toISOString();
  const next: AgentCursorState = {
    ...previous,
    x: input.point?.x ?? previous.x,
    y: input.point?.y ?? previous.y,
    agent: input.agent ?? previous.agent,
    label: input.label ?? previous.label,
    phase: input.phase ?? "idle",
    typingText: input.typingText,
    keyLabel: input.keyLabel,
    countdown: input.countdown,
    cueId: input.cueId ?? previous.cueId,
    expiresAt: agentCursorExpiration(updatedAt),
    updatedAt,
  };
  if (input.highlight === null) {
    delete next.highlight;
  } else if (input.highlight) {
    next.highlight = input.highlight;
  }
  if (next.phase === "idle") {
    next.typingText = undefined;
    next.keyLabel = undefined;
    next.countdown = undefined;
  }
  await writeFile(statePath, `${JSON.stringify(next, null, 2)}\n`);
}

export const POINTER_FOCUS_COUNTDOWN_SECONDS = 3;
export const POINTER_FOCUS_COUNTDOWN_STEP_MS = 800;

/** Return true only for acts likely to move the real pointer or steal foreground focus. */
export function requiresPointerFocusWarning(input: {
  action: RuntimeAction;
  target?: ResolvedTarget;
  axTier: AxActionTier;
  channel: string;
}): boolean {
  if (input.axTier === "attention" || input.axTier === "target-focus") {
    return true;
  }
  if (input.channel === "hid" || input.target?.mode === "coordinate") {
    return true;
  }

  const kind = input.action.kind;
  if (kind === "focus-window" || kind === "open-app") {
    return true;
  }
  return (
    (kind === "click" || kind === "drag" || kind === "scroll")
    && Boolean(input.action.target?.point || input.action.input?.point)
  );
}

/** Show a 3-2-1 cursor warning before an attention-taking act. */
export async function runPointerFocusCountdown(input: {
  leaseId: string;
  agent?: string;
  point?: Point;
  label?: string;
  seconds?: number;
  stepMs?: number;
}): Promise<boolean> {
  const seconds = input.seconds ?? POINTER_FOCUS_COUNTDOWN_SECONDS;
  const stepMs = input.stepMs ?? POINTER_FOCUS_COUNTDOWN_STEP_MS;
  if (!Number.isInteger(seconds) || seconds < 1) {
    throw new Error("countdown seconds must be a positive integer");
  }
  if (!Number.isFinite(stepMs) || stepMs < 0) {
    throw new Error("countdown stepMs must be a non-negative number");
  }
  if (!(await pathExists(agentCursorStatePath(input.leaseId)))) {
    return false;
  }

  const cueBase = `countdown_${Date.now()}`;
  for (let remaining = seconds; remaining >= 1; remaining -= 1) {
    await updateAgentCursor({
      leaseId: input.leaseId,
      agent: input.agent,
      point: input.point,
      label: input.label ?? "taking pointer",
      phase: "countdown",
      countdown: remaining,
      cueId: `${cueBase}_${remaining}`,
    });
    await new Promise((resolvePromise) => setTimeout(resolvePromise, stepMs));
  }
  return true;
}

/** Re-check native lease authority after the warning window and before acting. */
export async function revalidatePointerFocusLease(input: {
  warningShown: boolean;
  isLeaseActive: () => Promise<boolean>;
  onLeaseEnded?: () => Promise<void>;
  onCheckFailed?: () => Promise<void>;
}): Promise<void> {
  if (!input.warningShown) {
    return;
  }

  let isActive = false;
  try {
    isActive = await input.isLeaseActive();
  } catch (error) {
    try {
      await input.onCheckFailed?.();
    } catch {}
    throw error;
  }
  if (isActive) {
    return;
  }

  try {
    await input.onLeaseEnded?.();
  } catch {}
  throw new Error("Drive lease ended during pointer focus countdown");
}

export async function stopAgentCursor(leaseId: string): Promise<void> {
  await mkdir(cursorDirectory(), { recursive: true });
  await writeFile(agentCursorStopPath(leaseId), "stop\n");
}

export function pointFromBounds(bounds: {
  x: number;
  y: number;
  width: number;
  height: number;
}): Point {
  return {
    x: bounds.x + bounds.width / 2,
    y: bounds.y + bounds.height / 2,
  };
}

function spawnHostDetached(nativeHostPath: string, args: string[]): Promise<void> {
  return new Promise<void>((resolvePromise, reject) => {
    const child = spawn(nativeHostPath, args, {
      stdio: "ignore",
      detached: true,
    });
    child.once("error", reject);
    child.once("spawn", () => {
      child.unref();
      resolvePromise();
    });
  });
}
