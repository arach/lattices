#!/usr/bin/env bun

import { execFile } from "node:child_process";
import { appendFile, access, mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { DriverIdentityContext } from "./driver-identity.js";
import { DriveCursorPresenter, parseDriveCursorStyle } from "./drive-cursor-presenter.js";
import { recordToolCall, verbForTool } from "./tool-ledger.js";

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import type { CallToolResult, Tool } from "@modelcontextprotocol/sdk/types.js";
import type {
  AxActionTier,
  Bounds,
  DriveLease,
  DriveMode,
  DriveOutcome,
  ClickFeedbackConfig,
  ResolvedTarget,
  RuntimeAction,
  SessionMode,
  TargetQuery,
  TraceEvent,
} from "@action/protocol";
import {
  analyzeScreenshotVision,
  CompanionClient,
  DriveAgentClient,
  inferAxTier,
  inspectCurrentSurface,
  MacOSCommandEngine,
  ocrScreenshot,
  StageDirector,
  StageSceneError,
  pointFromBounds,
  publishPointerEventLog,
  readPointerEventLog,
  revalidatePointerFocusLease,
  requiresPointerFocusWarning,
  runPointerFocusCountdown,
  searchOCRText,
  startAgentCursor,
  startPointerEventLog,
  readAgentCursorState,
  cursorTravelMs,
  PlayLogger,
  stopAgentCursor,
  stopPointerEventLog,
  updateAgentCursor,
  type PointerEventLogHandle,
} from "@action/runtime";

export const toolFamilies = [
  "driver",
  "session",
  "drive",
  "observe",
  "resolve",
  "act",
  "stage",
  "record",
  "artifacts",
  "compose",
  "export",
] as const;

type JsonObject = Record<string, unknown>;
type ToolHandler = (args: JsonObject) => Promise<JsonObject>;

interface JsonSchemaObject {
  [key: string]: unknown;
  type: "object";
  properties?: Record<string, object>;
  required?: string[];
  additionalProperties?: boolean;
}

interface RecordingEntry {
  recordingId: string;
  sessionId?: string;
  scope: "current-surface" | "app-window" | "region";
  outputPath: string;
  stopFile: string;
  finishedFile: string;
  debugLog?: string;
  startedAt: string;
  nativeStatus?: string;
  nativeDetail?: string;
  bundleId?: string;
  bounds?: Bounds;
  /** Path to this recording's pointer event artifact, written by the native click path. */
  pointerEventLog?: string;
  /** Whether the operator opted in to a visible pulse for each Action-driven click. */
  clickFeedback?: boolean;
}

const execFileAsync = promisify(execFile);
const sourceDir = dirname(fileURLToPath(import.meta.url));
const defaultActionRoot = resolve(sourceDir, "../../..");
const actionRoot = resolve(process.env.ACTION_ROOT ?? defaultActionRoot);
const nativeHostPath = resolve(
  process.env.ACTION_NATIVE_HOST ?? resolve(actionRoot, "native/engine/scripts/run-app-host.sh"),
);
const driveClient = new DriveAgentClient({ launcherPath: nativeHostPath });
const stageDirector = new StageDirector(nativeHostPath);
const driverIdentity = new DriverIdentityContext();
const cursorPresenter = new DriveCursorPresenter({
  start: async ({ lease, label }) => startAgentCursor({ nativeHostPath, lease, label }),
  update: updateAgentCursor,
  stop: stopAgentCursor,
});
const activeRecordings = new Map<string, RecordingEntry>();
const activePointerEventLogs = new Map<string, PointerEventLogHandle>();

function now(): string {
  return new Date().toISOString();
}

function timestampId(): string {
  return now().replace(/[-:.]/g, "").replace("T", "_").replace("Z", "");
}

function objectSchema(
  properties: Record<string, object> = {},
  required: string[] = [],
): JsonSchemaObject {
  return {
    type: "object",
    properties,
    required,
    additionalProperties: true,
  };
}

function tool(
  name: string,
  title: string,
  description: string,
  inputSchema: JsonSchemaObject = objectSchema(),
  annotations: Tool["annotations"] = {},
): Tool {
  return {
    name,
    title,
    description,
    inputSchema,
    annotations,
  };
}

function textProperty(description: string): object {
  return { type: "string", description };
}

function booleanProperty(description: string): object {
  return { type: "boolean", description };
}

function numberProperty(description: string): object {
  return { type: "number", description };
}

function objectProperty(description: string): object {
  return { type: "object", description, additionalProperties: true };
}


function parseVisionProvider(value: unknown): "minimax" | "moondream" | undefined {
  return value === "moondream" || value === "minimax" ? value : undefined;
}

function enumProperty(values: string[], description: string): object {
  return { type: "string", enum: values, description };
}

function asObject(value: unknown, label: string): JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }

  return value as JsonObject;
}

function optionalObject(value: unknown, label: string): JsonObject | undefined {
  if (value === undefined) {
    return undefined;
  }

  return asObject(value, label);
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function optionalBoolean(value: unknown): boolean | undefined {
  return typeof value === "boolean" ? value : undefined;
}

function optionalNumber(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }

  return undefined;
}

function parseSessionMode(value: unknown): SessionMode {
  if (value === "inspection" || value === "hybrid" || value === "capture") {
    return value;
  }

  return "inspection";
}

function parseDriveMode(value: unknown): DriveMode {
  return value === "attention" ? "attention" : "background";
}

function parseDriveOutcome(value: unknown): DriveOutcome {
  if (value === "done" || value === "failed" || value === "cancelled") {
    return value;
  }
  return "cancelled";
}

function parseBounds(value: unknown, label = "bounds"): Bounds {
  const object = asObject(value, label);
  const x = optionalNumber(object.x);
  const y = optionalNumber(object.y);
  const width = optionalNumber(object.width);
  const height = optionalNumber(object.height);

  if (x === undefined || y === undefined || width === undefined || height === undefined) {
    throw new Error(`${label} requires numeric x, y, width, and height`);
  }

  return { x, y, width, height };
}

function parseTargetQuery(value: unknown): TargetQuery {
  return asObject(value, "query") as TargetQuery;
}

function parseResolvedTarget(value: unknown): ResolvedTarget {
  return asObject(value, "target") as unknown as ResolvedTarget;
}

function parseRuntimeAction(value: unknown): RuntimeAction {
  const action = asObject(value, "action") as Partial<RuntimeAction>;
  const kind = optionalString(action.kind);

  if (!kind) {
    throw new Error("action.kind is required");
  }

  return {
    id: optionalString(action.id) ?? `action_${timestampId()}`,
    kind: kind as RuntimeAction["kind"],
    description: optionalString(action.description) ?? kind,
    target: action.target,
    input: action.input,
  };
}

function sessionOutputDir(sessionId: string): string {
  return resolve(actionRoot, "artifacts", "sessions", sessionId);
}

function defaultSessionId(mode: SessionMode): string {
  return `${mode}_${timestampId()}`;
}

function defaultRecordingId(): string {
  return `recording_${timestampId()}`;
}

function mcpResult(data: JsonObject): CallToolResult {
  return {
    content: [
      {
        type: "text",
        text: JSON.stringify(data, null, 2),
      },
    ],
    structuredContent: data,
  };
}

function mcpError(message: string, metadata: JsonObject = {}): CallToolResult {
  return {
    isError: true,
    content: [
      {
        type: "text",
        text: JSON.stringify({ ok: false, error: message, ...metadata }, null, 2),
      },
    ],
    structuredContent: {
      ok: false,
      error: message,
      ...metadata,
    },
  };
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function fileSize(path: string): Promise<number | undefined> {
  try {
    return (await stat(path)).size;
  } catch {
    return undefined;
  }
}

async function readTextIfExists(path: string): Promise<string | undefined> {
  try {
    return await readFile(path, "utf8");
  } catch {
    return undefined;
  }
}

async function writeJson(path: string, value: unknown): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`);
}

async function persistDriveSession(lease: DriveLease, events: TraceEvent[]): Promise<void> {
  const outputDir = sessionOutputDir(lease.sessionId);
  await writeJson(resolve(outputDir, "drive-lease.json"), lease);

  if (events.length > 0) {
    const tracePath = resolve(outputDir, "drive-trace.json");
    const rawTrace = await readTextIfExists(tracePath);
    let trace: TraceEvent[] = [];
    try {
      const parsed = rawTrace ? JSON.parse(rawTrace) : [];
      trace = Array.isArray(parsed) ? parsed as TraceEvent[] : [];
    } catch {
      trace = [];
    }
    await writeJson(tracePath, [...trace, ...events]);
  }

  const sessionPath = resolve(outputDir, "session.json");
  const rawSession = await readTextIfExists(sessionPath);
  let session: JsonObject = {};
  try {
    session = rawSession ? JSON.parse(rawSession) as JsonObject : {};
  } catch {
    session = {};
  }
  await writeJson(sessionPath, {
    ...session,
    id: session.id ?? lease.sessionId,
    mode: session.mode ?? "hybrid",
    state: lease.status === "driving" ? "running" : "completed",
    phase: lease.status === "driving" ? "acting" : "completed",
    createdAt: session.createdAt ?? lease.startedAt,
    outputDir: session.outputDir ?? outputDir,
    updatedAt: lease.releasedAt ?? lease.lastActAt,
    driveLeaseId: lease.leaseId,
    drive: lease,
  });
}

async function heartbeatDrive(input: {
  leaseId?: string;
  axTier: AxActionTier;
  actionKind?: string;
}): Promise<DriveLease | undefined> {
  if (!input.leaseId && !driveClient.isConnected) {
    return undefined;
  }
  const lease = await driveClient.touch({
    leaseId: input.leaseId,
    axTier: input.axTier,
  });
  if (!lease) {
    return undefined;
  }
  await persistDriveSession(lease, [{
    type: "drive.act_tier",
    at: lease.lastActAt,
    leaseId: lease.leaseId,
    axTier: input.axTier,
    actionKind: input.actionKind,
  }]);
  await cursorPresenter.renew(lease);
  return lease;
}

async function ensureDriveLeaseForAct(input: {
  leaseId?: string;
  axTier: AxActionTier;
  actionKind: string;
  description: string;
}): Promise<DriveLease> {
  let lease = await driveClient.touch({
    leaseId: input.leaseId,
    axTier: input.axTier,
  });

  if (!lease) {
    const identity = driverIdentity.get();
    const begun = await driveClient.begin({
      agent: identity.agent,
      task: identity.task ?? input.description ?? input.actionKind,
      mode: "background",
      implicit: true,
    });
    if (begun.status !== "granted") {
      throw new Error(begun.reason ?? "Unable to begin an implicit drive lease");
    }
    lease = await driveClient.touch({
      leaseId: begun.lease.leaseId,
      axTier: input.axTier,
    }) ?? begun.lease;
    await persistDriveSession(lease, [{
      type: "drive.lease_began",
      at: lease.startedAt,
      leaseId: lease.leaseId,
      agent: lease.agent,
      task: lease.task,
      mode: lease.mode,
      sessionId: lease.sessionId,
      implicit: true,
    }]);
  }

  await persistDriveSession(lease, [{
    type: "drive.act_tier",
    at: lease.lastActAt,
    leaseId: lease.leaseId,
    axTier: input.axTier,
    actionKind: input.actionKind,
  }]);
  await cursorPresenter.ensure(lease);
  return lease;
}

function actPoint(action: RuntimeAction, target: ResolvedTarget | undefined): { x: number; y: number } | undefined {
  const bounds = target?.bounds;
  const point = bounds
    ? pointFromBounds(bounds)
    : action.target?.point
      ? {
          x: Number((action.target.point as { x?: number }).x),
          y: Number((action.target.point as { y?: number }).y),
        }
      : undefined;
  if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y)) {
    return undefined;
  }
  return point;
}

function actHighlight(target: ResolvedTarget | undefined): {
  x: number;
  y: number;
  width: number;
  height: number;
} | undefined {
  const bounds = target?.bounds;
  if (!bounds) {
    return undefined;
  }
  const x = Number(bounds.x);
  const y = Number(bounds.y);
  const width = Number(bounds.width);
  const height = Number(bounds.height);
  if (![x, y, width, height].every(Number.isFinite) || width < 4 || height < 4) {
    return undefined;
  }
  return { x, y, width, height };
}

async function sleep(ms: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function publishDriveNote(line: string, leaseId?: string): Promise<JsonObject> {
  const note = {
    at: now(),
    leaseId,
    line: line.slice(0, 120),
  };
  const supervisionDir = resolve(
    homedir(),
    "Library/Application Support/Action/runtime/supervision",
  );
  const notesPath = resolve(supervisionDir, "notes.jsonl");
  await mkdir(supervisionDir, { recursive: true });
  await appendFile(notesPath, `${JSON.stringify(note)}\n`);

  const registrationsDir = resolve(supervisionDir, "registrations");
  if (await pathExists(registrationsDir)) {
    const files = await readdir(registrationsDir);
    for (const file of files) {
      if (!file.endsWith(".json")) {
        continue;
      }
      const path = resolve(registrationsDir, file);
      try {
        const registration = JSON.parse(await readFile(path, "utf8")) as JsonObject;
        registration.detail = note.line;
        registration.updatedAt = note.at;
        await writeFile(path, `${JSON.stringify(registration, null, 2)}\n`);
      } catch {
        // A torn registration is not worth failing the note.
      }
    }
  }

  return { note, notesPath };
}

async function stageCursor(input: {
  lease: DriveLease;
  point?: { x: number; y: number };
  highlight?: { x: number; y: number; width: number; height: number } | null;
  label?: string;
  wait?: boolean;
}): Promise<void> {
  if (!cursorPresenter.isPresenting(input.lease.leaseId)) {
    return;
  }
  const previous = await readAgentCursorState(input.lease.leaseId);
  const from = previous && Number.isFinite(previous.x) && Number.isFinite(previous.y)
    ? { x: previous.x as number, y: previous.y as number }
    : undefined;
  await cursorPresenter.update({
    leaseId: input.lease.leaseId,
    agent: input.lease.agent,
    point: input.point,
    label: input.label ?? "looking",
    phase: "idle",
    highlight: input.highlight,
  });
  if (input.wait === false || !input.point) {
    return;
  }
  await sleep(cursorTravelMs(from, input.point));
}

async function presentActCue(input: {
  lease: DriveLease;
  action: RuntimeAction;
  target: ResolvedTarget | undefined;
}): Promise<void> {
  try {
    const kind = input.action.kind;
    const cueId = `${input.action.id}_${Date.now()}`;
    const safePoint = actPoint(input.action, input.target);
    const highlight = actHighlight(input.target);
    const description = (input.action.description || kind).slice(0, 40);

    if (kind === "type") {
      const text = String(input.action.input?.text ?? description);
      await cursorPresenter.update({
        leaseId: input.lease.leaseId,
        agent: input.lease.agent,
        point: safePoint,
        label: "type",
        phase: "type",
        typingText: text.slice(0, 80),
        cueId,
        highlight,
      });
      const holdMs = Math.min(3200, 420 + text.length * 55);
      setTimeout(() => {
        void cursorPresenter.update({
          leaseId: input.lease.leaseId,
          agent: input.lease.agent,
          phase: "idle",
          label: "driving",
          highlight: null,
        });
      }, holdMs);
      return;
    }

    if (kind === "press-key") {
      const keys = Array.isArray(input.action.input?.keys)
        ? (input.action.input.keys as unknown[]).filter((key): key is string => typeof key === "string")
        : [];
      const key = String(input.action.input?.key ?? keys.at(-1) ?? "key");
      const chord = (keys.length > 1 ? keys : [key]).join(" + ");
      await cursorPresenter.update({
        leaseId: input.lease.leaseId,
        agent: input.lease.agent,
        point: safePoint,
        label: chord,
        phase: "key",
        keyLabel: chord,
        cueId,
        highlight,
      });
      setTimeout(() => {
        void cursorPresenter.update({
          leaseId: input.lease.leaseId,
          agent: input.lease.agent,
          phase: "idle",
          label: "driving",
          highlight: null,
        });
      }, 700);
      return;
    }

    await cursorPresenter.update({
      leaseId: input.lease.leaseId,
      agent: input.lease.agent,
      point: safePoint,
      label: description,
      phase: safePoint ? "click" : "idle",
      cueId,
      highlight,
    });
    if (safePoint) {
      setTimeout(() => {
        void cursorPresenter.update({
          leaseId: input.lease.leaseId,
          agent: input.lease.agent,
          phase: "idle",
          label: "driving",
          highlight: null,
        });
      }, 480);
    }
  } catch {
    // The action result remains authoritative when cursor presentation fails.
  }
}

async function runHost(command: string, ...args: string[]): Promise<JsonObject> {
  const { stdout } = await execFileAsync(nativeHostPath, [command, ...args], {
    cwd: actionRoot,
  });
  const text = stdout.trim();
  if (!text) {
    return {};
  }

  return JSON.parse(text) as JsonObject;
}

function newEngine(): MacOSCommandEngine {
  return new MacOSCommandEngine(nativeHostPath);
}

function recordingMetadataPath(entry: RecordingEntry): string | undefined {
  if (!entry.sessionId) {
    return undefined;
  }

  return resolve(sessionOutputDir(entry.sessionId), `${entry.recordingId}.recording.json`);
}

async function persistRecording(entry: RecordingEntry): Promise<void> {
  const metadataPath = recordingMetadataPath(entry);
  if (metadataPath) {
    await writeJson(metadataPath, entry);
  }
}

async function loadRecordingFromDisk(args: JsonObject): Promise<RecordingEntry | undefined> {
  const recordingId = optionalString(args.recordingId);
  const sessionId = optionalString(args.sessionId);
  if (!recordingId || !sessionId) {
    return undefined;
  }

  const metadataPath = resolve(sessionOutputDir(sessionId), `${recordingId}.recording.json`);
  const raw = await readTextIfExists(metadataPath);
  if (!raw) {
    return undefined;
  }

  return JSON.parse(raw) as RecordingEntry;
}

async function resolveRecording(args: JsonObject): Promise<RecordingEntry> {
  const recordingId = optionalString(args.recordingId);
  if (recordingId && activeRecordings.has(recordingId)) {
    return activeRecordings.get(recordingId)!;
  }

  const diskEntry = await loadRecordingFromDisk(args);
  if (diskEntry) {
    activeRecordings.set(diskEntry.recordingId, diskEntry);
    return diskEntry;
  }

  const outputPath = optionalString(args.outputPath);
  if (outputPath) {
    const resolvedOutputPath = resolve(actionRoot, outputPath);
    return {
      recordingId: recordingId ?? "recording_from_output_path",
      sessionId: optionalString(args.sessionId),
      scope: "region",
      outputPath: resolvedOutputPath,
      stopFile: optionalString(args.stopFile) ?? `${resolvedOutputPath}.stop`,
      finishedFile: optionalString(args.finishedFile) ?? `${resolvedOutputPath}.finished`,
      startedAt: now(),
    };
  }

  throw new Error("recordingId with sessionId, an active recordingId, or outputPath is required");
}

async function statusForRecording(entry: RecordingEntry): Promise<JsonObject> {
  const finishedText = await readTextIfExists(entry.finishedFile);
  const outputSize = await fileSize(entry.outputPath);
  const stopRequested = await pathExists(entry.stopFile);
  let state: "starting" | "recording" | "stopping" | "completed" | "failed" = "starting";
  let finishedStatus: string | undefined;

  if (finishedText !== undefined) {
    finishedStatus = finishedText.trim();
    state = finishedStatus.startsWith("error:") ? "failed" : "completed";
  } else if (stopRequested) {
    state = "stopping";
  } else if (outputSize !== undefined) {
    state = "recording";
  }

  return {
    ok: true,
    recordingId: entry.recordingId,
    sessionId: entry.sessionId,
    scope: entry.scope,
    state,
    outputPath: entry.outputPath,
    outputSize,
    stopFile: entry.stopFile,
    finishedFile: entry.finishedFile,
    finishedStatus,
    debugLog: entry.debugLog,
    startedAt: entry.startedAt,
    nativeStatus: entry.nativeStatus,
    nativeDetail: entry.nativeDetail,
  };
}

async function waitForRecordingFinished(
  entry: RecordingEntry,
  timeoutMs: number,
): Promise<JsonObject> {
  const startedAt = Date.now();

  while (Date.now() - startedAt < timeoutMs) {
    const status = await statusForRecording(entry);
    if (status.state === "completed" || status.state === "failed") {
      return status;
    }
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 250));
  }

  return statusForRecording(entry);
}

async function listFiles(root: string): Promise<JsonObject[]> {
  const entries: JsonObject[] = [];

  async function visit(dir: string): Promise<void> {
    const dirEntries = await readdir(dir, { withFileTypes: true });
    for (const entry of dirEntries) {
      const path = resolve(dir, entry.name);
      if (entry.isDirectory()) {
        await visit(path);
        continue;
      }

      const stats = await stat(path);
      entries.push({
        path,
        relativePath: relative(root, path),
        bytes: stats.size,
        updatedAt: stats.mtime.toISOString(),
      });
    }
  }

  if (await pathExists(root)) {
    await visit(root);
  }

  return entries;
}

const tools: Tool[] = [
  tool(
    "action.driver.identify",
    "Identify Driver",
    "Set a stable human-readable identity for implicit drive leases on this MCP connection.",
    objectSchema({
      agent: textProperty("Stable caller label shown to the operator, for example Codex · checkout audit."),
      task: textProperty("Optional default task label for implicit drive leases."),
    }, ["agent"]),
    { readOnlyHint: false, idempotentHint: true },
  ),
  tool(
    "action.health",
    "Action Health",
    "Check native Action permissions and host availability.",
    objectSchema(),
    { readOnlyHint: true, idempotentHint: true },
  ),
  tool(
    "action.session.create",
    "Create Session",
    "Create a durable Action session directory for harness-driven work.",
    objectSchema({
      mode: enumProperty(["capture", "inspection", "hybrid"], "Session mode. Defaults to inspection."),
      sessionId: textProperty("Optional stable session id."),
      outputDir: textProperty("Optional absolute or Action-root-relative output directory."),
    }),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.drive.begin",
    "Begin Drive Lease",
    "Announce that an automation client is driving the Mac and show its identity and task in the supervision HUD.",
    objectSchema({
      agent: textProperty("Automation client identity shown to the operator."),
      task: textProperty("Short description of the work shown to the operator."),
      mode: enumProperty(["background", "attention"], "Drive mode. Background is the supported default; attention approval is not available yet."),
      sessionId: textProperty("Optional Action session id for drive artifacts."),
      showSupervisionLabel: booleanProperty("Show the driver identity label to the operator. Defaults to true."),
      pointerControl: booleanProperty("Allow pointer drags and coordinate targeting on this background lease. Some work has no accessibility element to aim at \u2014 dragging a selection rectangle is coordinate-only by nature. Defaults to false; the lease records the grant so supervision can show it."),
      cursorStyle: enumProperty(["synthetic", "system"], "Cursor presentation. Defaults to synthetic; system uses the normal macOS cursor."),
    }, ["agent", "task"]),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.drive.release",
    "Release Drive Lease",
    "Give control back to the operator and record a terminal outcome.",
    objectSchema({
      leaseId: textProperty("Lease id returned by action.drive.begin."),
      outcome: enumProperty(["done", "failed", "cancelled"], "Terminal outcome. Defaults to cancelled."),
      summary: textProperty("Optional short completion summary."),
    }, ["leaseId"]),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.drive.status",
    "Drive Status",
    "Read active and recently completed drive leases from the native Action agent.",
    objectSchema({
      leaseId: textProperty("Optional lease id to focus the response."),
    }),
    { readOnlyHint: true, idempotentHint: true },
  ),
  tool(
    "action.drive.note",
    "Drive Note",
    "Write a short beat to the floating supervision HUD so the operator can see what this client is doing without watching the console.",
    objectSchema({
      line: textProperty("One short status line. Keep it under 80 characters."),
      leaseId: textProperty("Optional drive lease id this note belongs to."),
    }, ["line"]),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.drive.aim",
    "Drive Aim",
    "Move the synthetic cursor to a point and optionally highlight a region. Does not click, type, or paste. Use this to set up what the operator should look at, then act.",
    objectSchema({
      leaseId: textProperty("Drive lease id. Required when this client has more than one active lease."),
      point: objectProperty("Screen point { x, y } for the cursor tip."),
      highlight: objectProperty("Optional region { x, y, width, height } to frame."),
      label: textProperty("Optional badge label while aiming."),
    }),
    { readOnlyHint: false, idempotentHint: true },
  ),
  tool(
    "action.drive.play",
    "Drive Play",
    "Run a short named sequence of beats as one play. Each beat is note, aim, wait, or act. Use this to group steps instead of driving them one tool call at a time.",
    objectSchema({
      title: textProperty("Short name for the play, shown on the HUD."),
      beats: {
        type: "array",
        description: "Ordered beats. Each is { do: note|aim|wait|act, ... }. note needs line; aim takes point/highlight/label; wait needs ms; act needs action (same shape as act.execute).",
      },
      leaseId: textProperty("Drive lease id. Required when this client has more than one active lease."),
    }, ["beats"]),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.observe.snapshot",
    "Observe Snapshot",
    "Capture the current focused surface screenshot, AX snapshot, and Apple Vision OCR as session artifacts.",
    objectSchema({
      sessionId: textProperty("Optional session id. A new inspection session id is generated when omitted."),
      outputDir: textProperty("Optional absolute or Action-root-relative output directory."),
      includeOcr: booleanProperty("Whether to run Apple Vision OCR on the screenshot. Defaults to true."),
      includeVision: booleanProperty("Whether to run vision analysis via MiniMax MCP. Defaults to false."),
      visionPrompt: textProperty("Optional vision prompt when includeVision is true."),
      visionProvider: enumProperty(["minimax", "moondream"], "Vision provider. Defaults to minimax when MINIMAX_API_KEY is set."),
      direct: booleanProperty("Bypass action-companion and run as a one-shot MCP call."),
      mockNative: booleanProperty("Use companion mock native mode for verification when ActionAgent is unavailable."),
      leaseId: textProperty("Optional drive lease id to heartbeat while observing."),
    }),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.observe.ocr",
    "Observe OCR",
    "Run Apple Vision OCR on an existing screenshot or the current focused surface.",
    objectSchema({
      imagePath: textProperty("Optional screenshot path. Captures the current surface when omitted."),
      outputPath: textProperty("Optional JSON output path for OCR results."),
      query: textProperty("Optional text search filter applied to OCR blocks."),
    }),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.observe.vision",
    "Observe Vision",
    "Run vision analysis on an existing screenshot or the current focused surface. Defaults to MiniMax MCP understand_image.",
    objectSchema({
      imagePath: textProperty("Optional screenshot path. Captures the current surface when omitted."),
      outputPath: textProperty("Optional JSON output path for vision analysis."),
      prompt: textProperty("Optional vision prompt."),
      provider: enumProperty(["minimax", "moondream"], "Vision provider. Defaults to minimax when MINIMAX_API_KEY is set."),
      direct: booleanProperty("Bypass action-companion and run as a one-shot MCP call."),
      mockNative: booleanProperty("Use companion mock native mode for verification when ActionAgent is unavailable."),
    }),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.observe.ax",
    "Observe Accessibility",
    "Capture an accessibility snapshot for the current focused surface.",
    objectSchema({
      sessionId: textProperty("Optional session id used to choose the artifact directory."),
      outputPath: textProperty("Optional absolute or Action-root-relative JSON output path."),
    }),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.resolve.target",
    "Resolve Target",
    "Resolve a target query through Action's runtime target interface.",
    objectSchema({
      query: objectProperty("TargetQuery object with semanticId, text, role, surfaceId, anchorId, or point."),
    }, ["query"]),
    { readOnlyHint: true, idempotentHint: true },
  ),
  tool(
    "action.stage.set",
    "Set Stage",
    "Declare what the world should look like for a take. Puts up a flat color drape, raises only the listed windows, then reads on-screen z-order and fails if anything else still occupies the scene. Does not write the wallpaper, hide apps, or change Spaces unless mode is space (sheet stays on the current Space).",
    objectSchema({
      mode: enumProperty(["drape", "space"], "drape (default) buries other windows under a same-level sheet. space keeps the sheet on this Space only."),
      color: textProperty("Sheet color as RRGGBB. Defaults to 0e0d0a."),
      level: enumProperty(["normal", "desktop"], "normal (default) can be beaten by AXRaise. desktop sits under all app windows."),
      bounds: objectProperty("Optional top-left region { x, y, width, height }. Omit to cover every screen."),
      seconds: numberProperty("Optional lifetime. The drape dismisses itself when it expires. Omit to keep it up until action.stage.clear or until this server exits."),
      subjects: {
        type: "array",
        description: "Windows to raise above the sheet. Each item is { bundleId, title? }.",
        items: {
          type: "object",
          properties: {
            bundleId: { type: "string" },
            title: { type: "string" },
          },
          required: ["bundleId"],
        },
      },
    }),
    { readOnlyHint: false, idempotentHint: true },
  ),
  tool(
    "action.stage.clear",
    "Clear Stage",
    "Take the drape down. Subject windows stay where they are.",
    objectSchema(),
    { readOnlyHint: false, idempotentHint: true },
  ),
  tool(
    "action.stage.status",
    "Stage Status",
    "Read whether a drape is up, its pid, which windows were last raised, and which windows are actually on top of the sheet.",
    objectSchema(),
    { readOnlyHint: true, idempotentHint: true },
  ),
  tool(
    "action.act.execute",
    "Execute Action",
    "Execute a deterministic runtime action. Prefer resolved targets over raw coordinates.",
    objectSchema({
      action: objectProperty(
        "RuntimeAction object. kind is one of click, type, press-key, drag, scroll, focus-window, open-app. "
        + "Any other kind declared in ActionKind has no handler in the macOS runtime and is rejected rather than silently skipped. "
        + "focus-window and open-app need input.bundleId — an app name is not accepted; focus-window also takes an optional input.title to pick a window. "
        + "click accepts input.holdMs for press-and-hold (requires a point); some controls, including SwiftUI Toggle, do not actuate on a plain click and need a hold. "
        + "scroll takes a point plus input.deltaX/deltaY and an optional input.durationMs. Deltas are raw scroll wheel values, "
        + "not a screen direction: which way the content moves is up to the target app, so scroll once and observe rather than reasoning from the sign.",
      ),
      target: objectProperty("Optional ResolvedTarget. If omitted, action.target is resolved first when present."),
      leaseId: textProperty("Drive lease id for this action. Required when this client has more than one active lease."),
    }, ["action"]),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.record.start",
    "Start Recording",
    "Start an asynchronous native recording. Completion is represented by the finished file and status tool.",
    objectSchema({
      scope: enumProperty(["current-surface", "app-window", "region"], "Recording target. Defaults from bundleId or bounds, otherwise current-surface."),
      sessionId: textProperty("Optional session id used for default artifact paths."),
      recordingId: textProperty("Optional stable recording id."),
      outputPath: textProperty("Optional absolute or Action-root-relative .mov path."),
      bundleId: textProperty("Bundle id for app-window recording."),
      bounds: objectProperty("Bounds for region recording: x, y, width, height."),
      profile: enumProperty(["draft", "final"], "Region recording quality profile. Defaults to draft."),
      includeSupervisionOverlay: booleanProperty("Include the operator supervision label in recorded pixels. Defaults to true; false keeps it visible only to the operator."),
      clickFeedback: booleanProperty("Show a short pulse at each Action-driven click. Defaults to false. The normal macOS cursor is preserved either way; click metadata is recorded either way."),
      clickFeedbackDurationMs: numberProperty("Lifetime of one click pulse in milliseconds. Defaults to 320."),
      clickFeedbackRadius: numberProperty("Outer radius the click pulse expands to, in points. Defaults to 34."),
    }),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.record.status",
    "Recording Status",
    "Read recording status from an active recording entry, output path, or finished marker.",
    objectSchema({
      recordingId: textProperty("Recording id returned by action.record.start."),
      sessionId: textProperty("Session id used to reload recording metadata if needed."),
      outputPath: textProperty("Optional .mov path for marker-derived status."),
      stopFile: textProperty("Optional stop marker path when using outputPath."),
      finishedFile: textProperty("Optional finished marker path when using outputPath."),
    }),
    { readOnlyHint: true, idempotentHint: true },
  ),
  tool(
    "action.record.stop",
    "Stop Recording",
    "Request a clean recording stop by writing the stop marker and optionally waiting for completion.",
    objectSchema({
      recordingId: textProperty("Recording id returned by action.record.start."),
      sessionId: textProperty("Session id used to reload recording metadata if needed."),
      outputPath: textProperty("Optional .mov path for marker-derived stop."),
      stopFile: textProperty("Optional stop marker path when using outputPath."),
      finishedFile: textProperty("Optional finished marker path when using outputPath."),
      wait: booleanProperty("Whether to wait for the finished marker. Defaults to true."),
      timeoutMs: numberProperty("Maximum wait for the finished marker. Defaults to 30000."),
    }),
    { readOnlyHint: false, idempotentHint: false },
  ),
  tool(
    "action.artifacts.list",
    "List Artifacts",
    "List artifacts for an Action session directory.",
    objectSchema({
      sessionId: textProperty("Session id under artifacts/sessions."),
      outputDir: textProperty("Optional absolute or Action-root-relative artifact directory."),
    }),
    { readOnlyHint: true, idempotentHint: true },
  ),
];


async function runCompanionJobIfAvailable(kind: string, payload: JsonObject, direct: boolean | undefined): Promise<JsonObject | undefined> {
  if (direct || process.env.ACTION_COMPANION_DIRECT === "1") {
    return undefined;
  }
  const client = new CompanionClient({ timeoutMs: 2_000 });
  if (!(await client.isReachable())) {
    return undefined;
  }
  const job = await client.createJob({
    kind,
    payload,
    sessionId: optionalString(payload.sessionId),
    client: "action-mcp",
  });
  const completed = await client.waitJob(job.id, 120_000);
  return {
    ok: completed.state === "completed",
    companion: true,
    job: completed as unknown as JsonObject,
    result: completed.result as JsonObject | undefined,
    error: completed.error,
  };
}

const handlers: Record<string, ToolHandler> = {
  async "action.driver.identify"(args) {
    const agent = optionalString(args.agent);
    if (!agent) {
      throw new Error("agent is required");
    }
    const identity = driverIdentity.identify(agent, optionalString(args.task));
    return {
      ok: true,
      identity,
      note: "Identity will be used for implicit drive leases on this MCP connection.",
    };
  },

  async "action.health"() {
    const engine = newEngine();
    const diagnostics = await engine.diagnostics();

    return {
      ok: true,
      actionRoot,
      nativeHostPath,
      diagnostics,
      toolFamilies,
    };
  },

  async "action.session.create"(args) {
    const mode = parseSessionMode(args.mode);
    const sessionId = optionalString(args.sessionId) ?? defaultSessionId(mode);
    const outputDir = resolve(actionRoot, optionalString(args.outputDir) ?? sessionOutputDir(sessionId));
    const createdAt = now();
    const session = {
      id: sessionId,
      mode,
      state: "created",
      phase: "created",
      createdAt,
      updatedAt: createdAt,
      outputDir,
      tracePath: resolve(outputDir, "trace.json"),
      manifestPath: resolve(outputDir, "manifest.json"),
      artifactCount: 0,
      traceCount: 0,
      artifacts: [],
    };
    const manifest = {
      sessionId,
      mode,
      generatedAt: createdAt,
      outputDir,
      tracePath: session.tracePath,
      artifacts: [],
    };

    await mkdir(outputDir, { recursive: true });
    await writeJson(session.tracePath, []);
    await writeJson(session.manifestPath, manifest);
    await writeJson(resolve(outputDir, "session.json"), session);

    return {
      ok: true,
      session,
      manifest,
    };
  },

  async "action.drive.begin"(args) {
    const agent = optionalString(args.agent);
    const task = optionalString(args.task);
    if (!agent || !task) {
      throw new Error("agent and task are required");
    }
    driverIdentity.identify(agent, task);
    const result = await driveClient.begin({
      agent,
      task,
      mode: parseDriveMode(args.mode),
      sessionId: optionalString(args.sessionId),
      showSupervisionLabel: optionalBoolean(args.showSupervisionLabel) ?? true,
      pointerControl: optionalBoolean(args.pointerControl) ?? false,
    });
    if (result.status === "denied") {
      return {
        ok: false,
        status: result.status,
        leaseId: result.lease.leaseId,
        reason: result.reason,
        lease: result.lease,
      };
    }

    await persistDriveSession(result.lease, [{
      type: "drive.lease_began",
      at: result.lease.startedAt,
      leaseId: result.lease.leaseId,
      agent: result.lease.agent,
      task: result.lease.task,
      mode: result.lease.mode,
      sessionId: result.lease.sessionId,
      implicit: result.lease.implicit,
    }]);
    cursorPresenter.recordStyle(result.lease.leaseId, parseDriveCursorStyle(args.cursorStyle));
    await cursorPresenter.ensure(result.lease);
    return {
      ok: true,
      status: result.status,
      leaseId: result.lease.leaseId,
      lease: result.lease,
    };
  },

  async "action.drive.release"(args) {
    const leaseId = optionalString(args.leaseId);
    if (!leaseId) {
      throw new Error("leaseId is required");
    }
    const lease = await driveClient.release({
      leaseId,
      outcome: parseDriveOutcome(args.outcome),
      summary: optionalString(args.summary),
    });
    await cursorPresenter.release(lease.leaseId);
    await persistDriveSession(lease, [{
      type: "drive.lease_released",
      at: lease.releasedAt ?? lease.lastActAt,
      leaseId: lease.leaseId,
      outcome: lease.outcome ?? "cancelled",
      summary: lease.summary,
    }]);
    return {
      ok: true,
      leaseId: lease.leaseId,
      outcome: lease.outcome,
      lease,
    };
  },

  async "action.drive.status"(args) {
    const snapshot = await driveClient.status();
    const drivingIDs = new Set(
      snapshot.leases.filter((lease) => lease.status === "driving").map((lease) => lease.leaseId),
    );
    for (const leaseId of cursorPresenter.presentingLeaseIDs()) {
      if (!drivingIDs.has(leaseId)) {
        await cursorPresenter.release(leaseId);
      }
    }
    const leaseId = optionalString(args.leaseId);
    if (!leaseId) {
      return { ok: true, ...snapshot };
    }
    return {
      ok: true,
      state: snapshot.state,
      activeCount: snapshot.activeCount,
      lease: snapshot.leases.find((lease) => lease.leaseId === leaseId),
      leases: snapshot.leases,
    };
  },

  async "action.drive.note"(args) {
    const line = optionalString(args.line)?.replaceAll("\n", " ").trim();
    if (!line) {
      throw new Error("line is required");
    }
    return { ok: true, ...(await publishDriveNote(line, optionalString(args.leaseId))) };
  },

  async "action.drive.aim"(args) {
    const lease = await ensureDriveLeaseForAct({
      leaseId: optionalString(args.leaseId),
      axTier: "semantic",
      actionKind: "drive.aim",
      description: optionalString(args.label) ?? "aim",
    });
    await cursorPresenter.ensure(lease);
    const point = args.point && typeof args.point === "object"
      ? (() => {
          const object = args.point as JsonObject;
          const x = optionalNumber(object.x);
          const y = optionalNumber(object.y);
          return x !== undefined && y !== undefined ? { x, y } : undefined;
        })()
      : undefined;
    const highlight = args.highlight === null
      ? null
      : args.highlight && typeof args.highlight === "object"
        ? (() => {
            try {
              return parseBounds(args.highlight, "highlight");
            } catch {
              return undefined;
            }
          })()
        : undefined;
    await stageCursor({
      lease,
      point,
      highlight,
      label: optionalString(args.label) ?? "looking",
      wait: true,
    });
    return {
      ok: true,
      leaseId: lease.leaseId,
      point,
      highlight: highlight ?? undefined,
    };
  },

  async "action.drive.play"(args) {
    const title = optionalString(args.title) ?? "play";
    const beats = Array.isArray(args.beats) ? args.beats : [];
    if (beats.length === 0) {
      throw new Error("beats must be a non-empty array");
    }
    const lease = await ensureDriveLeaseForAct({
      leaseId: optionalString(args.leaseId),
      axTier: "semantic",
      actionKind: "drive.play",
      description: title,
    });
    await cursorPresenter.ensure(lease);
    const log = new PlayLogger(title, lease.leaseId);
    await log.playStart(beats.length);

    const ran: JsonObject[] = [];
    for (const [index, raw] of beats.entries()) {
      const beat = asObject(raw, `beats[${index}]`);
      const kind = optionalString(beat.do) ?? optionalString(beat.kind);
      const label = optionalString(beat.label)
        ?? optionalString(beat.line)
        ?? kind
        ?? `beat ${index + 1}`;
      const started = Date.now();
      await log.stepStart(index, beats.length, kind ?? "step", label);

      try {
        if (kind === "note") {
          const line = optionalString(beat.line);
          if (!line) {
            throw new Error("note beat requires line");
          }
          ran.push({ index, do: "note", line });
        } else if (kind === "wait") {
          const ms = Math.min(8000, Math.max(0, optionalNumber(beat.ms) ?? 400));
          await sleep(ms);
          ran.push({ index, do: "wait", ms });
        } else if (kind === "aim") {
          await handlers["action.drive.aim"]({
            leaseId: lease.leaseId,
            point: beat.point,
            highlight: beat.highlight,
            label: optionalString(beat.label) ?? label,
          });
          ran.push({ index, do: "aim", label });
        } else if (kind === "act") {
          await handlers["action.act.execute"]({
            leaseId: lease.leaseId,
            action: beat.action,
            target: beat.target,
          });
          ran.push({ index, do: "act", label });
        } else {
          throw new Error(`Unknown beat do="${kind ?? ""}". Use note, aim, wait, or act.`);
        }
        await log.stepOk(index, beats.length, kind ?? "step", Date.now() - started, label);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        await log.stepFail(index, beats.length, kind ?? "step", message);
        await log.playFail(message, index);
        return {
          ok: false,
          title,
          leaseId: lease.leaseId,
          logDir: join(homedir(), "Library/Application Support/Action/runtime/plays"),
          stoppedAt: index,
          error: message,
          ran,
        };
      }
    }

    await log.playOk();
    return {
      ok: true,
      title,
      leaseId: lease.leaseId,
      logDir: join(homedir(), "Library/Application Support/Action/runtime/plays"),
      beatCount: beats.length,
      ran,
    };
  },

  async "action.observe.snapshot"(args) {
    const sessionId = optionalString(args.sessionId) ?? defaultSessionId("inspection");
    const outputDir = resolve(actionRoot, optionalString(args.outputDir) ?? sessionOutputDir(sessionId));
    const payload = {
      sessionId,
      outputDir,
      includeOcr: args.includeOcr === false ? false : true,
      includeVision: args.includeVision === true,
      visionPrompt: optionalString(args.visionPrompt),
      visionProvider: parseVisionProvider(args.visionProvider),
      mockNative: optionalBoolean(args.mockNative),
    };
    await heartbeatDrive({
      leaseId: optionalString(args.leaseId),
      axTier: "observe",
      actionKind: "observe.snapshot",
    });
    const companion = await runCompanionJobIfAvailable("observe.snapshot", payload, optionalBoolean(args.direct));
    if (companion) {
      return companion;
    }

    const result = await inspectCurrentSurface({
      engine: newEngine(),
      sessionId,
      outputDir,
      includeOcr: payload.includeOcr,
      includeVision: payload.includeVision,
      visionPrompt: payload.visionPrompt,
      visionProvider: payload.visionProvider,
    });

    return {
      ok: true,
      currentSurface: result.currentSurface,
      session: result.session,
      manifest: result.manifest,
      ocr: result.ocr,
      vision: result.vision,
    };
  },

  async "action.observe.ocr"(args) {
    const engine = newEngine();
    const sessionId = defaultSessionId("inspection");
    const outputDir = resolve(actionRoot, sessionOutputDir(sessionId));
    const existingImagePath = optionalString(args.imagePath);
    let currentSurface;
    let screenshotPath: string;

    if (existingImagePath) {
      screenshotPath = resolve(actionRoot, existingImagePath);
    } else {
      await mkdir(outputDir, { recursive: true });
      screenshotPath = resolve(outputDir, "snapshot.png");
      const capture = await engine.captureCurrentSurfaceScreenshot(screenshotPath);
      currentSurface = capture.currentSurface;
    }

    const outputPath = resolve(
      actionRoot,
      optionalString(args.outputPath) ?? (existingImagePath ? `${screenshotPath}.ocr.json` : resolve(outputDir, "ocr-snapshot.json")),
    );
    const result = await ocrScreenshot(screenshotPath, outputPath);
    const query = optionalString(args.query);
    const matches = query ? searchOCRText(result.result, query) : undefined;

    return {
      ok: true,
      currentSurface,
      artifact: result.artifact,
      ocr: result.result,
      matches,
    };
  },

  async "action.observe.vision"(args) {
    const payload = {
      imagePath: optionalString(args.imagePath),
      outputPath: optionalString(args.outputPath),
      prompt: optionalString(args.prompt),
      provider: parseVisionProvider(args.provider),
      mockNative: optionalBoolean(args.mockNative),
    };
    const companion = await runCompanionJobIfAvailable("observe.vision", payload, optionalBoolean(args.direct));
    if (companion) {
      return companion;
    }

    const engine = newEngine();
    let imagePath = payload.imagePath;

    if (!imagePath) {
      const sessionId = defaultSessionId("inspection");
      const outputDir = resolve(actionRoot, sessionOutputDir(sessionId));
      const capture = await engine.captureCurrentSurfaceScreenshot(resolve(outputDir, "snapshot.png"));
      imagePath = capture.artifact.path;
    } else {
      imagePath = resolve(actionRoot, imagePath);
    }

    const outputPath = resolve(
      actionRoot,
      payload.outputPath ?? `${imagePath}.vision.json`,
    );
    const result = await analyzeScreenshotVision(imagePath, {
      prompt: payload.prompt,
      outputPath,
      provider: payload.provider,
    });

    return {
      ok: true,
      artifact: result.artifact,
      vision: result.result,
    };
  },

  async "action.observe.ax"(args) {
    const sessionId = optionalString(args.sessionId) ?? defaultSessionId("inspection");
    const outputPath = resolve(
      actionRoot,
      optionalString(args.outputPath)
        ?? resolve(sessionOutputDir(sessionId), `ax-snapshot-${timestampId()}.json`),
    );
    const engine = newEngine();
    const currentSurface = await engine.currentSurface();
    const result = await engine.captureSurfaceAccessibilitySnapshot(currentSurface, outputPath);

    return {
      ok: true,
      sessionId,
      currentSurface,
      artifact: result.artifact,
      nodeCount: result.nodeCount,
    };
  },

  async "action.resolve.target"(args) {
    const query = parseTargetQuery(args.query);
    const result = await newEngine().resolveTarget(query);

    return {
      ok: true,
      query,
      result,
    };
  },

  async "action.act.execute"(args) {
    const action = parseRuntimeAction(args.action);
    const engine = newEngine();
    const target = optionalObject(args.target, "target")
      ? parseResolvedTarget(args.target)
      : action.target
        ? await engine.resolveTarget(action.target)
        : undefined;

    const channel = target?.mode === "coordinate" ? "hid" : "native";
    const axTier = inferAxTier({
      actionKind: action.kind,
      channel,
      targetMode: target?.mode,
    });
    const lease = await ensureDriveLeaseForAct({
      leaseId: optionalString(args.leaseId),
      axTier,
      actionKind: action.kind,
      description: action.description,
    });

    let pointerFocusWarningShown = false;
    if (
      cursorPresenter.isPresenting(lease.leaseId)
      && requiresPointerFocusWarning({ action, target, axTier, channel })
    ) {
      const bounds = target?.bounds;
      const point = bounds
        ? pointFromBounds(bounds)
        : action.target?.point
          ? {
              x: Number((action.target.point as { x?: number }).x),
              y: Number((action.target.point as { y?: number }).y),
            }
          : undefined;
      const safePoint = point && Number.isFinite(point.x) && Number.isFinite(point.y)
        ? point
        : undefined;
      pointerFocusWarningShown = await runPointerFocusCountdown({
        leaseId: lease.leaseId,
        agent: lease.agent,
        point: safePoint,
        label: (action.description || action.kind).slice(0, 40),
      });
    }
    await revalidatePointerFocusLease({
      warningShown: pointerFocusWarningShown,
      isLeaseActive: async () => Boolean(await heartbeatDrive({
        leaseId: lease.leaseId,
        axTier,
        actionKind: action.kind,
      })),
      onLeaseEnded: async () => {
        // The native terminal transition owns the lease stop signal; only forget
        // the local presentation handle so we do not recreate an orphan marker.
        cursorPresenter.forget(lease.leaseId);
      },
      onCheckFailed: async () => cursorPresenter.release(lease.leaseId),
    });

    // performAction throws for anything it could not carry out — including an action kind the
    // runtime has no handler for — and the tool dispatcher turns a throw into an isError reply.
    // Reaching this line is therefore the success signal; the literal below is not an assumption.
    const stagedPoint = actPoint(action, target);
    const stagedHighlight = actHighlight(target);
    await stageCursor({
      lease,
      point: stagedPoint,
      highlight: stagedHighlight,
      label: (action.description || action.kind).slice(0, 40),
      wait: true,
    });

    try {
      await engine.performAction(action, target);
    } catch (error) {
      if (pointerFocusWarningShown) {
        try {
          await cursorPresenter.update({
            leaseId: lease.leaseId,
            agent: lease.agent,
            phase: "idle",
            label: "driving",
          });
        } catch {
          // The native lease expiry remains the independent cleanup path.
        }
      }
      throw error;
    }
    await presentActCue({ lease, action, target });

    return {
      ok: true,
      result: {
        id: action.id,
        at: now(),
        status: "succeeded",
        channel,
        detail: action.description,
        axTier,
      },
      action,
      target,
      drive: {
        leaseId: lease.leaseId,
        agent: lease.agent,
        task: lease.task,
        mode: lease.mode,
        implicit: lease.implicit === true,
      },
    };
  },

  async "action.record.start"(args) {
    const sessionId = optionalString(args.sessionId);
    const recordingId = optionalString(args.recordingId) ?? defaultRecordingId();
    const scope = (() => {
      const explicit = optionalString(args.scope);
      if (explicit === "current-surface" || explicit === "app-window" || explicit === "region") {
        return explicit;
      }
      if (args.bounds !== undefined) {
        return "region";
      }
      if (optionalString(args.bundleId)) {
        return "app-window";
      }
      return "current-surface";
    })();
    const outputPath = resolve(
      actionRoot,
      optionalString(args.outputPath)
        ?? resolve(sessionOutputDir(sessionId ?? "mcp"), `${recordingId}.mov`),
    );
    const stopFile = `${outputPath}.stop`;
    const finishedFile = `${outputPath}.finished`;
    const debugLog = `${outputPath}.log`;

    await mkdir(dirname(outputPath), { recursive: true });
    await rm(outputPath, { force: true });
    await rm(stopFile, { force: true });
    await rm(finishedFile, { force: true });
    await rm(debugLog, { force: true });

    const clickFeedback: ClickFeedbackConfig = {
      enabled: optionalBoolean(args.clickFeedback) ?? false,
      style: "pulse",
      durationMs: optionalNumber(args.clickFeedbackDurationMs),
      radius: optionalNumber(args.clickFeedbackRadius),
    };
    // Opened before the recorder so a click in the first frames is already covered, and published
    // to the environment so every host subprocess this server spawns records into it.
    const pointerLog = await startPointerEventLog({
      runHost: (command, ...hostArgs) => runHost(command, ...hostArgs),
      nativeHostPath,
      outputPath,
      recordingId,
      sessionId,
      clickFeedback,
    });
    activePointerEventLogs.set(recordingId, pointerLog);
    await publishPointerEventLog(pointerLog.path);

    let nativeResponse: JsonObject;
    let bundleId = optionalString(args.bundleId);
    let bounds: Bounds | undefined;

    if (scope === "current-surface") {
      const currentSurface = await newEngine().currentSurface();
      bundleId = currentSurface.bundleId;
      nativeResponse = await runHost(
        "record-app-window",
        "--bundle-id",
        currentSurface.bundleId,
        "--output",
        outputPath,
        "--stop-file",
        stopFile,
        "--finished-file",
        finishedFile,
      "--debug-log",
      debugLog,
    );
    } else if (scope === "app-window") {
      if (!bundleId) {
        throw new Error("bundleId is required for app-window recording");
      }
      nativeResponse = await runHost(
        "record-app-window",
        "--bundle-id",
        bundleId,
        "--output",
        outputPath,
        "--stop-file",
        stopFile,
        "--finished-file",
        finishedFile,
        "--debug-log",
        debugLog,
      );
    } else {
      bounds = parseBounds(args.bounds);
      const profile = optionalString(args.profile) === "final" ? "final" : "draft";
      nativeResponse = await runHost(
        "record-region",
        "--x",
        String(bounds.x),
        "--y",
        String(bounds.y),
        "--width",
        String(bounds.width),
        "--height",
        String(bounds.height),
        "--fps",
        profile === "final" ? "60" : "15",
        "--scale",
        profile === "final" ? "1" : "0.75",
        "--include-supervision-overlay",
        String(optionalBoolean(args.includeSupervisionOverlay) ?? true),
        "--output",
        outputPath,
        "--stop-file",
        stopFile,
        "--finished-file",
        finishedFile,
        "--debug-log",
        debugLog,
      );
    }

    const entry: RecordingEntry = {
      recordingId,
      sessionId,
      scope,
      outputPath,
      stopFile,
      finishedFile,
      debugLog,
      startedAt: now(),
      nativeStatus: optionalString(nativeResponse.status),
      nativeDetail: optionalString(nativeResponse.detail),
      bundleId,
      bounds,
      pointerEventLog: pointerLog.path,
      clickFeedback: pointerLog.feedbackEnabled,
    };
    activeRecordings.set(recordingId, entry);
    await persistRecording(entry);

    return {
      ok: true,
      status: "recording-started",
      recording: entry,
      nativeResponse,
      pointerEvents: {
        path: pointerLog.path,
        clickFeedback: pointerLog.feedbackEnabled,
        note: pointerLog.feedbackEnabled && scope !== "region"
          ? "Click feedback is drawn as a screen overlay. Only the region scope records the whole display, so app-window and current-surface captures will not contain the pulse."
          : "Every Action-driven click and drag press/release is appended to this JSONL artifact.",
      },
      completion: {
        note: "Recording start is an acknowledgement only. Use action.record.status or the finishedFile marker for completion.",
        finishedFile,
      },
    };
  },

  async "action.record.status"(args) {
    return statusForRecording(await resolveRecording(args));
  },

  async "action.record.stop"(args) {
    const entry = await resolveRecording(args);
    const wait = optionalBoolean(args.wait) ?? true;
    const timeoutMs = optionalNumber(args.timeoutMs) ?? 30_000;

    await mkdir(dirname(entry.stopFile), { recursive: true });
    await writeFile(entry.stopFile, "stop\n");

    // Clicks after this belong to no recording, and the pulse has nothing left to appear in.
    const pointerLog = activePointerEventLogs.get(entry.recordingId);
    if (pointerLog) {
      await stopPointerEventLog(pointerLog);
      activePointerEventLogs.delete(entry.recordingId);
    }
    await publishPointerEventLog(undefined);

    const status = wait
      ? await waitForRecordingFinished(entry, timeoutMs)
      : await statusForRecording(entry);

    const pointerEvents = entry.pointerEventLog
      ? await readPointerEventLog(entry.pointerEventLog)
      : undefined;

    return {
      ok: true,
      stopRequested: true,
      ...status,
      pointerEvents: entry.pointerEventLog
        ? {
            path: entry.pointerEventLog,
            clickFeedback: entry.clickFeedback === true,
            eventCount: pointerEvents?.events.length ?? 0,
            startedAt: pointerEvents?.header?.startedAt,
          }
        : undefined,
    };
  },

  async "action.stage.set"(args) {
    const status = await stageDirector.set({
      mode: optionalString(args.mode),
      color: optionalString(args.color),
      level: optionalString(args.level),
      bounds: args.bounds,
      subjects: args.subjects,
      seconds: optionalNumber(args.seconds),
      // This server outlives the call, so the drape can watch it and dismiss itself if
      // the server dies before action.stage.clear runs.
      owner: "caller",
    });
    return { ok: true, stage: status };
  },

  async "action.stage.clear"() {
    const status = await stageDirector.clear();
    return { ok: true, stage: status };
  },

  async "action.stage.status"() {
    const status = await stageDirector.status();
    return { ok: true, stage: status };
  },

  async "action.artifacts.list"(args) {
    const outputDir = resolve(
      actionRoot,
      optionalString(args.outputDir)
        ?? sessionOutputDir(optionalString(args.sessionId) ?? "mcp"),
    );
    const manifestPath = resolve(outputDir, "manifest.json");
    const sessionPath = resolve(outputDir, "session.json");
    const manifestRaw = await readTextIfExists(manifestPath);
    const sessionRaw = await readTextIfExists(sessionPath);

    return {
      ok: true,
      outputDir,
      manifest: manifestRaw ? JSON.parse(manifestRaw) : undefined,
      session: sessionRaw ? JSON.parse(sessionRaw) : undefined,
      files: await listFiles(outputDir),
    };
  },
};

/** Grok (and the MCP 2025 name grammar) reject dots in tool names.
 *  `action.health` stays the handler key for Hermes. Spec names
 *  (`health`, `observe_snapshot`, …) are what tools/list advertises
 *  unless ACTION_MCP_TOOL_NAMES=legacy|both. Grok drops the *entire*
 *  list if any advertised name has a dot, so "both" is never for Grok. */
const specToolAliases: Record<string, string> = {};
const legacyTools = [...tools];
const specTools: Tool[] = [];
for (const existing of legacyTools) {
  const alias = existing.name.replace(/^action\./, "").replaceAll(".", "_");
  if (alias === existing.name) {
    specTools.push(existing);
    continue;
  }
  specToolAliases[alias] = existing.name;
  specTools.push({ ...existing, name: alias });
}

function advertisedTools(): Tool[] {
  const mode = (process.env.ACTION_MCP_TOOL_NAMES ?? "spec").trim().toLowerCase();
  if (mode === "legacy") {
    return legacyTools;
  }
  if (mode === "both") {
    return [...legacyTools, ...specTools];
  }
  return specTools;
}

function createServer(): Server {
  const server = new Server(
    {
      name: "@action/mcp",
      version: "0.0.0",
    },
    {
      capabilities: {
        tools: { listChanged: true },
      },
      instructions: [
        "Call action.driver.identify once when the connection label is not already supplied by the environment.",
        "Use Action tools to observe, resolve, act, record, and inspect native macOS surfaces.",
        "Before multi-step UI work, call action.drive.begin with an agent identity and short task.",
        "Pass the returned leaseId to observe and act calls, then call action.drive.release when the work ends.",
        "Background is the supported drive mode; attention approval is not available yet.",
        "Treat action.record.start as asynchronous; completion is represented by action.record.status and the finished file.",
        "Prefer action.observe.snapshot and action.resolve.target before action.act.execute.",
        "Use action.drive.note before each beat so the supervision HUD shows what you are doing.",
        "Use action.drive.aim to move the synthetic cursor and highlight a region before acting. Move, then do the thing.",
        "Use action.drive.play to run a named list of beats (note, aim, wait, act) as one sequence.",
        "Use action.stage.set to declare the world for a take: a color drape plus the windows that sit on it. Never write the desktop picture.",
        "These tools are also how you control the user's regular Chrome: it is a native window like any other, observed through screen capture and accessibility. The action-browser plugin's DOM tools (browser_snapshot / click / fill / screenshot) reach only Action-owned Chrome identities, never the user's own browser.",
      ].join("\n"),
    },
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: advertisedTools(),
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const requested = request.params.name;
    const canonical = specToolAliases[requested] ?? requested;
    const handler = handlers[canonical];
    if (!handler) {
      return mcpError(`Unknown tool: ${requested}`);
    }

    // Every tool call settles here, so this is the one place that can count them
    // without each handler remembering to. The ledger write is fire-and-forget:
    // Home's Actions panel is worth a count, never a failed tool call.
    const startedAt = Date.now();
    let args: JsonObject = {};
    const settle = (ok: boolean) => {
      void recordToolCall({
        at: new Date(startedAt).toISOString(),
        tool: canonical,
        verb: verbForTool(canonical, args),
        ok,
        ms: Date.now() - startedAt,
      });
    };

    try {
      args = asObject(request.params.arguments ?? {}, "arguments");
      const result = mcpResult(await handler(args));
      settle(true);
      return result;
    } catch (error) {
      settle(false);
      if (error instanceof StageSceneError) {
        return mcpError(error.message, {
          tool: request.params.name,
          stage: error.stage as unknown as JsonObject,
        });
      }
      return mcpError(error instanceof Error ? error.message : String(error), {
        tool: request.params.name,
      });
    }
  });

  return server;
}

export async function main(): Promise<void> {
  const server = createServer();
  await server.connect(new StdioServerTransport());
}

if (import.meta.main) {
  void main();
}
