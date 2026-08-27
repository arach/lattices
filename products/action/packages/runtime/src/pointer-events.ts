import { readFile, rm, writeFile, mkdir } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { spawn } from "node:child_process";

import type {
  ClickFeedbackConfig,
  PointerEventLogHeader,
  PointerEventRecord,
} from "@action/protocol";

/**
 * Environment variable that publishes the active pointer event log to every native host
 * subprocess. The native click path reads it, so a recording captures clicks made anywhere in the
 * runtime without threading a path through each call site.
 */
export const POINTER_EVENT_LOG_ENV = "ACTION_POINTER_EVENT_LOG";

/**
 * Marker naming the recording that is currently running.
 *
 * The environment variable alone is not enough: the native host is normally started through
 * `open -n`, which launches a fresh app through LaunchServices and does not reliably carry the
 * caller's environment across. A click process reads this file whatever launched it.
 */
export function activePointerEventLogMarkerPath(): string {
  return join(
    homedir(),
    "Library/Application Support/Action/runtime/pointer-events/active.json",
  );
}

export const DEFAULT_CLICK_FEEDBACK: Required<Omit<ClickFeedbackConfig, "enabled">> = {
  style: "pulse",
  durationMs: 320,
  radius: 34,
};

export interface PointerEventLogHandle {
  path: string;
  stopFile: string;
  recordingId: string;
  sessionId?: string;
  feedbackEnabled: boolean;
}

/** Artifact path for a recording's pointer events, alongside its .mov. */
export function pointerEventLogPath(outputPath: string): string {
  return `${outputPath}.pointer-events.jsonl`;
}

/**
 * Creates the log and, when feedback is opted in, starts the pulse overlay.
 *
 * The header is written by the native host rather than here: it carries a macOS system-uptime
 * reading that the click processes later subtract against, and Node has no comparable clock.
 */
export async function startPointerEventLog(input: {
  runHost: (command: string, ...args: string[]) => Promise<unknown>;
  nativeHostPath: string;
  outputPath: string;
  recordingId: string;
  sessionId?: string;
  clickFeedback?: ClickFeedbackConfig;
}): Promise<PointerEventLogHandle> {
  const path = pointerEventLogPath(input.outputPath);
  const stopFile = `${path}.stop`;
  const feedback = input.clickFeedback;
  const enabled = feedback?.enabled === true;

  await mkdir(dirname(path), { recursive: true });
  await rm(path, { force: true });
  await rm(stopFile, { force: true });

  await input.runHost(
    "pointer-event-log-init",
    "--path",
    path,
    "--recording-id",
    input.recordingId,
    ...(input.sessionId ? ["--session-id", input.sessionId] : []),
    "--click-feedback",
    String(enabled),
    "--click-feedback-style",
    feedback?.style ?? DEFAULT_CLICK_FEEDBACK.style,
    "--click-feedback-duration-ms",
    String(feedback?.durationMs ?? DEFAULT_CLICK_FEEDBACK.durationMs),
    "--click-feedback-radius",
    String(feedback?.radius ?? DEFAULT_CLICK_FEEDBACK.radius),
  );

  if (enabled) {
    await spawnDetached(input.nativeHostPath, [
      "click-feedback-overlay",
      "--event-log",
      path,
      "--stop-file",
      stopFile,
    ]);
  }

  return {
    path,
    stopFile,
    recordingId: input.recordingId,
    sessionId: input.sessionId,
    feedbackEnabled: enabled,
  };
}

/** Stops the pulse overlay. The log itself stays as the recording's artifact. */
export async function stopPointerEventLog(handle: PointerEventLogHandle): Promise<void> {
  if (!handle.feedbackEnabled) {
    return;
  }
  try {
    await mkdir(dirname(handle.stopFile), { recursive: true });
    await writeFile(handle.stopFile, "stop\n");
  } catch {
    // The overlay is presentation; a failed stop must not fail the recording.
  }
}

/** Publishes the log so native host subprocesses record into it, however they are launched. */
export async function publishPointerEventLog(path: string | undefined): Promise<void> {
  const marker = activePointerEventLogMarkerPath();
  if (path) {
    process.env[POINTER_EVENT_LOG_ENV] = path;
  } else {
    delete process.env[POINTER_EVENT_LOG_ENV];
  }

  try {
    if (path) {
      await mkdir(dirname(marker), { recursive: true });
      await writeFile(marker, `${JSON.stringify({ path })}\n`);
    } else {
      await rm(marker, { force: true });
    }
  } catch {
    // The environment variable still covers directly executed hosts; a missing marker only means
    // clicks go unrecorded, never that an action fails.
  }
}

export interface ParsedPointerEventLog {
  header?: PointerEventLogHeader;
  events: PointerEventRecord[];
}

/** Parses a pointer event log, tolerating a partial trailing line from a live writer. */
export function parsePointerEventLog(contents: string): ParsedPointerEventLog {
  let header: PointerEventLogHeader | undefined;
  const events: PointerEventRecord[] = [];

  for (const line of contents.split("\n")) {
    if (line.trim().length === 0) {
      continue;
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    const record = parsed as { kind?: string };
    if (record.kind === "header" && !header) {
      header = parsed as PointerEventLogHeader;
    } else if (record.kind === "pointer") {
      events.push(parsed as PointerEventRecord);
    }
  }

  return { header, events };
}

export async function readPointerEventLog(path: string): Promise<ParsedPointerEventLog> {
  try {
    return parsePointerEventLog(await readFile(path, "utf8"));
  } catch {
    return { events: [] };
  }
}

function spawnDetached(command: string, args: string[]): Promise<void> {
  return new Promise<void>((resolvePromise, reject) => {
    const child = spawn(command, args, { stdio: "ignore", detached: true });
    child.once("error", reject);
    child.once("spawn", () => {
      child.unref();
      resolvePromise();
    });
  });
}
