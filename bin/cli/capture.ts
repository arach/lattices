import {
  hasFlag,
  nonFlagArgs,
  parseFlagValue,
  parseOptionalNumber,
} from "./helpers.ts";
import { withDaemon } from "./daemon.ts";

export async function captureCommand(subcommand?: string, ...rawArgs: string[]): Promise<void> {
  const sub = subcommand || "window";
  const dashIndex = rawArgs.indexOf("--");
  const commandArgs = dashIndex >= 0 ? rawArgs.slice(0, dashIndex) : rawArgs;
  const childArgs = dashIndex >= 0 ? rawArgs.slice(dashIndex + 1) : [];
  const jsonFlag = hasFlag(commandArgs, "json");
  const positional = nonFlagArgs(commandArgs);

  if (["stop", "stop-recording", "stopRecording"].includes(sub)) {
    const params: Record<string, unknown> = {};
    const runId = positional[0] || parseFlagValue(commandArgs, "run-id") || parseFlagValue(commandArgs, "runId") || parseFlagValue(commandArgs, "id");
    const stopFile = parseFlagValue(commandArgs, "stop-file") || parseFlagValue(commandArgs, "stopFile");
    const finishedFile = parseFlagValue(commandArgs, "finished-file") || parseFlagValue(commandArgs, "finishedFile");
    const timeoutMs = Number(parseFlagValue(commandArgs, "timeout-ms") || parseFlagValue(commandArgs, "timeoutMs") || 30000);
    if (runId) params.runId = runId;
    if (stopFile) params.stopFile = stopFile;
    if (finishedFile) params.finishedFile = finishedFile;
    if (Number.isFinite(timeoutMs)) params.timeoutMs = timeoutMs;
    params.wait = !hasFlag(commandArgs, "no-wait");

    await withDaemon(async ({ daemonCall }) => {
      const result = await daemonCall("capture.stopRecording", params, timeoutMs + 5000) as any;
      if (jsonFlag) {
        console.log(JSON.stringify(result, null, 2));
        return;
      }
      console.log(result.finished ? "Recording finished." : "Recording stop requested.");
      if (result.run?.id) console.log(`  run: ${result.run.id}`);
      if (result.marker) console.log(`  marker: ${result.marker}`);
    });
    return;
  }

  const isRecordCommand = [
    "record-command",
    "recordCommand",
    "record-run",
    "recordRun",
    "record-exec",
    "recordExec",
  ].includes(sub);

  if (isRecordCommand) {
    if (!childArgs.length) {
      console.log(`lattices capture record-command — record while running a command

Usage:
  lattices capture record-command --app Scout --filename demo.mov -- <command> [...args]
`);
      return;
    }

    const params: Record<string, unknown> = { source: "cli" };
    const explicitWid = positional[0] ? Number(positional[0]) : NaN;
    if (Number.isFinite(explicitWid)) params.wid = explicitWid;

    const session = parseFlagValue(commandArgs, "session");
    const app = parseFlagValue(commandArgs, "app");
    const title = parseFlagValue(commandArgs, "title");
    const filename = parseFlagValue(commandArgs, "filename");
    const runId = parseFlagValue(commandArgs, "run-id") || parseFlagValue(commandArgs, "runId");
    const mode = parseFlagValue(commandArgs, "mode");
    const fps = parseOptionalNumber(commandArgs, "fps");
    const scale = parseOptionalNumber(commandArgs, "scale");
    const timeoutMs = Number(parseFlagValue(commandArgs, "timeout-ms") || parseFlagValue(commandArgs, "timeoutMs") || 30000);
    if (session) params.session = session;
    if (app) params.app = app;
    if (title) params.title = title;
    if (filename) params.filename = filename;
    if (runId) params.runId = runId;
    if (mode) params.mode = mode;
    if (fps !== undefined) params.fps = fps;
    if (scale !== undefined) params.scale = scale;

    for (const [flag, key] of [["x", "x"], ["y", "y"], ["width", "width"], ["height", "height"], ["w", "w"], ["h", "h"]] as const) {
      const value = parseOptionalNumber(commandArgs, flag);
      if (value !== undefined) params[key] = value;
    }

    const recordsRegion = hasFlag(commandArgs, "region") ||
      (params.x !== undefined && params.y !== undefined &&
        (params.width !== undefined || params.w !== undefined) &&
        (params.height !== undefined || params.h !== undefined));
    const method = recordsRegion ? "capture.recordRegion" : "capture.recordWindow";

    await withDaemon(async ({ daemonCall }) => {
      const start = await daemonCall(method, params, 20000) as any;
      let childExitCode = 0;
      let childError: string | undefined;

      try {
        const proc = Bun.spawn(childArgs, {
          cwd: process.cwd(),
          env: process.env,
          stdin: "inherit",
          stdout: "inherit",
          stderr: "inherit",
        });
        childExitCode = await proc.exited;
      } catch (error) {
        childExitCode = 127;
        childError = (error as Error).message;
      }

      const stop = await daemonCall(
        "capture.stopRecording",
        { runId: start.run?.id, wait: true, timeoutMs },
        timeoutMs + 5000
      ) as any;

      if (jsonFlag) {
        console.log(JSON.stringify({
          ok: childExitCode === 0 && stop.ok !== false,
          child: {
            command: childArgs,
            exitCode: childExitCode,
            error: childError,
          },
          recording: start,
          stopResult: stop,
        }, null, 2));
      } else {
        const artifact = start.artifact || {};
        const run = stop.run || start.run || {};
        console.log(`Recording finished.`);
        console.log(`  run: ${run.id || start.run?.id || "?"}`);
        console.log(`  artifact: ${artifact.path || "?"}`);
        console.log(`  child exit: ${childExitCode}`);
        if (childError) console.log(`  child error: ${childError}`);
      }

      if (childExitCode !== 0 && !hasFlag(commandArgs, "ignore-child-failure")) {
        process.exitCode = childExitCode;
      }
    });
    return;
  }

  const isRecord = ["record", "record-window", "recording", "video"].includes(sub);
  const isRecordRegion = ["record-region", "recordRegion", "region-recording"].includes(sub) ||
    (sub === "record" && ["region", "rect"].includes(positional[0] || ""));

  if (isRecord || isRecordRegion) {
    const params: Record<string, unknown> = { source: "cli" };
    const targetKind = sub === "record" ? positional[0] : undefined;
    const positionalOffset = targetKind === "window" || targetKind === "region" || targetKind === "rect" ? 1 : 0;
    const explicitWid = positional[positionalOffset] ? Number(positional[positionalOffset]) : NaN;
    if (Number.isFinite(explicitWid)) params.wid = explicitWid;

    const session = parseFlagValue(commandArgs, "session");
    const app = parseFlagValue(commandArgs, "app");
    const title = parseFlagValue(commandArgs, "title");
    const filename = parseFlagValue(commandArgs, "filename");
    const runId = parseFlagValue(commandArgs, "run-id") || parseFlagValue(commandArgs, "runId");
    const mode = parseFlagValue(commandArgs, "mode");
    const fps = parseOptionalNumber(commandArgs, "fps");
    const scale = parseOptionalNumber(commandArgs, "scale");
    const durationMs = parseOptionalNumber(commandArgs, "duration-ms", "durationMs", "duration");
    if (session) params.session = session;
    if (app) params.app = app;
    if (title) params.title = title;
    if (filename) params.filename = filename;
    if (runId) params.runId = runId;
    if (mode) params.mode = mode;
    if (fps !== undefined) params.fps = fps;
    if (scale !== undefined) params.scale = scale;

    for (const [flag, key] of [["x", "x"], ["y", "y"], ["width", "width"], ["height", "height"], ["w", "w"], ["h", "h"]] as const) {
      const value = parseOptionalNumber(commandArgs, flag);
      if (value !== undefined) params[key] = value;
    }

    await withDaemon(async ({ daemonCall }) => {
      const method = isRecordRegion ? "capture.recordRegion" : "capture.recordWindow";
      const result = await daemonCall(method, params, 20000) as any;

      if (durationMs !== undefined && durationMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, durationMs));
        const stop = await daemonCall(
          "capture.stopRecording",
          { runId: result.run?.id, wait: true, timeoutMs: 30000 },
          35000
        ) as any;
        result.stopResult = stop;
      }

      if (jsonFlag) {
        console.log(JSON.stringify(result, null, 2));
        return;
      }
      const artifact = result.artifact || {};
      const run = result.stopResult?.run || result.run || {};
      console.log(`Recording ${result.stopResult ? "finished" : "started"}.`);
      console.log(`  run: ${run.id || result.run?.id || "?"}`);
      console.log(`  artifact: ${artifact.path || "?"}`);
      if (!result.stopResult) {
        console.log(`  stop: lattices capture stop ${result.run?.id || ""}`);
      }
    });
    return;
  }

  if (!["window", "screenshot", "shot"].includes(sub)) {
    console.log(`lattices capture — capture run artifacts

Usage:
  lattices capture window [wid] [--json]
  lattices capture screenshot [wid] [--session name] [--app name]
  lattices capture record window [wid] [--app name] [--duration-ms 5000] [--json]
  lattices capture record region --x N --y N --width N --height N [--duration-ms 5000]
  lattices capture record-command --app Scout --filename demo.mov -- <command> [...args]
  lattices capture stop <run-id>
`);
    return;
  }

  const params: Record<string, unknown> = { source: "cli" };
  const explicitWid = positional[0] ? Number(positional[0]) : NaN;
  if (Number.isFinite(explicitWid)) params.wid = explicitWid;
  const session = parseFlagValue(commandArgs, "session");
  const app = parseFlagValue(commandArgs, "app");
  const title = parseFlagValue(commandArgs, "title");
  const filename = parseFlagValue(commandArgs, "filename");
  const runId = parseFlagValue(commandArgs, "run-id") || parseFlagValue(commandArgs, "runId");
  if (session) params.session = session;
  if (app) params.app = app;
  if (title) params.title = title;
  if (filename) params.filename = filename;
  if (runId) params.runId = runId;

  await withDaemon(async ({ daemonCall }) => {
    const result = await daemonCall("capture.screenshotWindow", params, 20000) as any;
    if (jsonFlag) {
      console.log(JSON.stringify(result, null, 2));
      return;
    }
    const artifact = result.artifact || {};
    const run = result.run || {};
    const target = result.target || {};
    console.log(`Captured ${target.app || "window"} ${target.wid ? `wid:${target.wid}` : ""}`);
    console.log(`  run: ${run.id || "?"}`);
    console.log(`  artifact: ${artifact.path || "?"}`);
  });
}
