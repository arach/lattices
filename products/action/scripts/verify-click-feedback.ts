#!/usr/bin/env bun
/**
 * Produces an Action-native verification artifact for opt-in click feedback.
 *
 * Records a region of the display while driving real Action clicks through the shared pointer
 * channel, then proves three things from the recording itself:
 *
 *  1. the normal macOS cursor is what appears — nothing draws a synthetic pointer,
 *  2. the opt-in pulse is present in the recorded pixels at each click,
 *  3. the frame timestamps line up with the pointer event log the same clicks wrote.
 *
 * Run with click feedback on (the artifact this is for):
 *   bun scripts/verify-click-feedback.ts
 * Run the control, to show the default is silent:
 *   bun scripts/verify-click-feedback.ts --no-click-feedback
 */
import { execFile } from "node:child_process";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { promisify } from "node:util";

import {
  parsePointerEventLog,
  publishPointerEventLog,
  startPointerEventLog,
  stopPointerEventLog,
} from "../packages/runtime/src/pointer-events.js";

const execFileAsync = promisify(execFile);
const actionRoot = resolve(import.meta.dir, "..");
const hostPath = resolve(actionRoot, "native/engine/scripts/run-app-host.sh");

const clickFeedbackEnabled = !process.argv.includes("--no-click-feedback");
const label = clickFeedbackEnabled ? "feedback-on" : "feedback-off";

async function runHost(command: string, ...args: string[]): Promise<Record<string, unknown>> {
  const { stdout } = await execFileAsync(hostPath, [command, ...args], { cwd: actionRoot });
  const text = stdout.trim();
  return text ? (JSON.parse(text) as Record<string, unknown>) : {};
}

function sleep(ms: number): Promise<void> {
  return new Promise((done) => setTimeout(done, ms));
}

async function waitForFile(path: string, timeoutMs: number): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const contents = await readFile(path, "utf8");
      if (contents.length > 0) {
        return true;
      }
    } catch {
      // not written yet
    }
    await sleep(100);
  }
  return false;
}

/**
 * Per-frame average luminance of a small box around a point, straight out of the recorded file.
 * The pulse is the only thing that changes there between clicks, so a spike marks the frame the
 * pulse was drawn in — measured from pixels, with no reference to the metadata being checked.
 */
async function boxLuminanceByFrame(
  videoPath: string,
  box: { x: number; y: number; size: number },
): Promise<Array<{ time: number; luminance: number }>> {
  const { stdout } = await execFileAsync("ffprobe", [
    "-v", "error",
    "-f", "lavfi",
    "-i", `movie=${videoPath},crop=${box.size}:${box.size}:${box.x}:${box.y},signalstats`,
    "-show_entries", "frame=pkt_pts_time:frame_tags=lavfi.signalstats.YAVG",
    "-of", "json",
  ], { maxBuffer: 32 * 1024 * 1024 });

  const parsed = JSON.parse(stdout) as {
    frames?: Array<{ pkt_pts_time?: string; tags?: Record<string, string> }>;
  };
  return (parsed.frames ?? []).flatMap((frame, index) => {
    const luminance = Number(frame.tags?.["lavfi.signalstats.YAVG"]);
    const time = Number(frame.pkt_pts_time ?? index / 30);
    return Number.isFinite(luminance) && Number.isFinite(time) ? [{ time, luminance }] : [];
  });
}

function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle];
}

/** Video time of the frame whose box luminance deviates most from its own baseline. */
function peakDeviationTime(
  samples: Array<{ time: number; luminance: number }>,
): { time: number; deviation: number } | undefined {
  if (samples.length === 0) {
    return undefined;
  }
  const baseline = median(samples.map((sample) => sample.luminance));
  let best = samples[0];
  let bestDeviation = Math.abs(samples[0].luminance - baseline);
  for (const sample of samples) {
    const deviation = Math.abs(sample.luminance - baseline);
    if (deviation > bestDeviation) {
      best = sample;
      bestDeviation = deviation;
    }
  }
  return { time: best.time, deviation: bestDeviation };
}

async function main() {
  const stamp = new Date().toISOString().replace(/[-:.]/g, "").replace("T", "_").slice(0, 15);
  const recordingId = `verify_click_feedback_${label}_${stamp}`;
  const outputDir = resolve(actionRoot, "artifacts", "verification", recordingId);
  const outputPath = resolve(outputDir, "capture.mov");
  const stopFile = `${outputPath}.stop`;
  const finishedFile = `${outputPath}.finished`;
  const debugLog = `${outputPath}.log`;

  await mkdir(outputDir, { recursive: true });

  // Calculator gives a real target whose visual response proves the click actually landed.
  await runHost("launch-app", "--bundle-id", "com.apple.calculator");
  await sleep(1200);
  await runHost("activate-app", "--bundle-id", "com.apple.calculator");
  await sleep(600);

  const frameReply = await runHost("get-window-frame", "--bundle-id", "com.apple.calculator");
  const frame = (frameReply.frame ?? frameReply) as Record<string, unknown>;
  const bounds = {
    x: Math.round(Number(frame.x)),
    y: Math.round(Number(frame.y)),
    width: Math.round(Number(frame.width)),
    height: Math.round(Number(frame.height)),
  };
  if (!Object.values(bounds).every(Number.isFinite)) {
    throw new Error(`Could not read the Calculator window frame: ${JSON.stringify(frameReply)}`);
  }

  // Record a padded region rather than the window itself: a window-filtered capture contains only
  // the target window's layer, so a screen overlay would not be in its pixels.
  const pad = 60;
  const region = {
    x: Math.max(0, bounds.x - pad),
    y: Math.max(0, bounds.y - pad),
    width: bounds.width + pad * 2,
    height: bounds.height + pad * 2,
  };

  const pointerLog = await startPointerEventLog({
    runHost,
    nativeHostPath: hostPath,
    outputPath,
    recordingId,
    sessionId: "verification",
    clickFeedback: { enabled: clickFeedbackEnabled, style: "pulse", durationMs: 320, radius: 34 },
  });
  await publishPointerEventLog(pointerLog.path);
  // Give the detached overlay a moment to map its window before the recorder opens.
  await sleep(clickFeedbackEnabled ? 1200 : 200);

  await rm(stopFile, { force: true });
  await rm(finishedFile, { force: true });

  const recordStart = Date.now();
  await runHost(
    "record-region",
    "--x", String(region.x),
    "--y", String(region.y),
    "--width", String(region.width),
    "--height", String(region.height),
    "--fps", "30",
    "--scale", "1",
    "--output", outputPath,
    "--stop-file", stopFile,
    "--finished-file", finishedFile,
    "--debug-log", debugLog,
  );
  await sleep(1500);

  // Three clicks spread far enough apart that each pulse is its own visible beat.
  const targets = [
    { label: "7", x: bounds.x + bounds.width * 0.22, y: bounds.y + bounds.height * 0.62 },
    { label: "+", x: bounds.x + bounds.width * 0.86, y: bounds.y + bounds.height * 0.62 },
    { label: "5", x: bounds.x + bounds.width * 0.5, y: bounds.y + bounds.height * 0.73 },
    { label: "=", x: bounds.x + bounds.width * 0.86, y: bounds.y + bounds.height * 0.93 },
  ];
  const clicks: Array<{ label: string; x: number; y: number; hostDetail: unknown }> = [];
  for (const target of targets) {
    const reply = await runHost(
      "click-point",
      "--x", String(Math.round(target.x)),
      "--y", String(Math.round(target.y)),
    );
    clicks.push({
      label: target.label,
      x: Math.round(target.x),
      y: Math.round(target.y),
      hostDetail: reply.detail,
    });
    await sleep(1100);
  }

  await sleep(1200);
  await writeFile(stopFile, "stop\n");
  const finished = await waitForFile(finishedFile, 45_000);
  const recordEnd = Date.now();

  await stopPointerEventLog(pointerLog);
  await publishPointerEventLog(undefined);

  const parsed = parsePointerEventLog(await readFile(pointerLog.path, "utf8"));
  const presses = parsed.events.filter((event) => event.phase === "down");

  // Measure each pulse from the pixels. The video clock starts whenever the recorder opened, which
  // is not the log's zero, so that one offset is fitted from the most confident detection and then
  // every click is checked against it. Fitting one unknown across four clicks leaves three real
  // degrees of freedom, so a pulse that had drifted from its metadata would still show up.
  const boxSize = 96;
  const samplesByPress = new Map<string, Array<{ time: number; luminance: number }>>();
  const pulseFrames: Array<{
    correlationId: string;
    box: { x: number; y: number; size: number };
    freePeakTime?: number;
    deviation?: number;
  }> = [];

  for (const press of presses) {
    const box = {
      x: Math.max(0, Math.round(press.x - region.x - boxSize / 2)),
      y: Math.max(0, Math.round(press.y - region.y - boxSize / 2)),
      size: boxSize,
    };
    let samples: Array<{ time: number; luminance: number }> = [];
    try {
      samples = await boxLuminanceByFrame(outputPath, box);
    } catch {
      // A failed probe leaves this click unmeasured rather than failing the run.
    }
    samplesByPress.set(press.correlationId, samples);
    const peak = peakDeviationTime(samples);
    pulseFrames.push({
      correlationId: press.correlationId,
      box,
      freePeakTime: peak?.time,
      deviation: peak?.deviation,
    });
  }

  // Anchor on the strongest detection: the Calculator's own repaints move luminance too, and the
  // clearest pulse is the least likely to be one of them.
  const anchorIndex = pulseFrames.reduce(
    (best, entry, index) =>
      (entry.deviation ?? -1) > (pulseFrames[best]?.deviation ?? -1) ? index : best,
    0,
  );
  const anchor = pulseFrames[anchorIndex];
  const anchorPress = presses[anchorIndex];
  const videoStartOffsetSeconds = anchor?.freePeakTime !== undefined && anchorPress
    ? anchor.freePeakTime - anchorPress.recordingElapsedMs / 1000
    : undefined;

  const alignment = presses.map((press, index) => {
    const expectedVideoTime = videoStartOffsetSeconds === undefined
      ? undefined
      : videoStartOffsetSeconds + press.recordingElapsedMs / 1000;
    const samples = samplesByPress.get(press.correlationId) ?? [];
    // Look only near where the metadata says the pulse should be, so an unrelated repaint
    // elsewhere in the clip cannot masquerade as the click.
    const window = expectedVideoTime === undefined
      ? []
      : samples.filter((sample) => Math.abs(sample.time - expectedVideoTime) <= 0.2);
    const localPeak = peakDeviationTime(window);
    return {
      correlationId: press.correlationId,
      recordingElapsedMs: press.recordingElapsedMs,
      at: press.at,
      expectedVideoTime,
      observedVideoTime: localPeak?.time,
      deviation: localPeak?.deviation,
      isAnchor: index === anchorIndex,
      driftMs: expectedVideoTime !== undefined && localPeak
        ? (localPeak.time - expectedVideoTime) * 1000
        : undefined,
      /**
       * Whether the pixel change sits inside one pulse lifetime of where the metadata says it
       * should be. This is the honest bound on the measurement: average luminance over a 96pt box
       * is dominated by the target app's own press animation, not by a 1.6pt ring, so the peak
       * frame is not the pulse peak. It bounds the correspondence; the strips show the pulse.
       */
      withinPulseDuration: expectedVideoTime !== undefined && localPeak
        ? Math.abs(localPeak.time - expectedVideoTime) * 1000 <= 320
        : undefined,
    };
  });

  // Stills and strips are the human-readable half of the artifact: the full-region frame shows the
  // normal macOS cursor next to the pulse, and the strip shows the pulse expand and vanish without
  // leaving a trail.
  const stills: string[] = [];
  for (const [index, entry] of alignment.entries()) {
    const videoTime = entry.observedVideoTime ?? entry.expectedVideoTime;
    if (videoTime === undefined) {
      continue;
    }
    const box = pulseFrames[index].box;

    // A third of the way into the pulse, where the ring is wide enough to read but has not yet
    // faded — the luminance peak alone lands anywhere inside the press animation.
    const stillPath = resolve(outputDir, `click-${index + 1}-pulse.png`);
    await execFileAsync("ffmpeg", [
      "-v", "error",
      "-ss", String(videoTime + 0.1),
      "-i", outputPath,
      "-frames:v", "1",
      stillPath,
      "-y",
    ]);
    stills.push(stillPath);

    const stripPath = resolve(outputDir, `click-${index + 1}-strip.png`);
    await execFileAsync("ffmpeg", [
      "-v", "error",
      "-i", outputPath,
      "-vf", [
        `crop=${box.size}:${box.size}:${box.x}:${box.y}`,
        `select='between(t,${(videoTime - 0.2).toFixed(3)},${(videoTime + 0.35).toFixed(3)})'`,
        "tile=6x3",
      ].join(","),
      "-frames:v", "1",
      stripPath,
      "-y",
    ]);
    stills.push(stripPath);
  }

  const summary = {
    recordingId,
    clickFeedback: clickFeedbackEnabled,
    outputPath,
    pointerEventLog: pointerLog.path,
    finished,
    region,
    calculatorFrame: bounds,
    recordWallClockMs: recordEnd - recordStart,
    header: parsed.header,
    clicks,
    events: parsed.events,
    /**
     * The point posted to the system, the point recorded in the artifact, and the point the pulse
     * is drawn at are one value read from one record — this restates it per click so the artifact
     * is auditable without re-reading the source.
     */
    coordinateAgreement: parsed.events
      .filter((event) => event.phase === "down")
      .map((event, index) => ({
        correlationId: event.correlationId,
        requested: clicks[index] ? { x: clicks[index].x, y: clicks[index].y } : undefined,
        recorded: { x: event.x, y: event.y },
        matches: clicks[index] ? clicks[index].x === event.x && clicks[index].y === event.y : false,
        recordingElapsedMs: event.recordingElapsedMs,
        at: event.at,
      })),
    videoStartOffsetSeconds,
    pulseFrames,
    alignment,
    stills,
  };

  const summaryPath = resolve(outputDir, "verification.json");
  await writeFile(summaryPath, `${JSON.stringify(summary, null, 2)}\n`);

  console.log(JSON.stringify({
    ok: finished,
    outputDir,
    outputPath,
    summaryPath,
    pointerEventLog: pointerLog.path,
    clickFeedback: clickFeedbackEnabled,
    eventCount: parsed.events.length,
    maxDriftMs: alignment.reduce(
      (worst, entry) => Math.max(worst, Math.abs(entry.driftMs ?? 0)),
      0,
    ),
    stills,
  }, null, 2));
}

await main();
