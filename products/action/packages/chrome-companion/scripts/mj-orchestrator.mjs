#!/usr/bin/env bun

import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function parseCdpJson(stdout) {
  const jsonStart = stdout.indexOf("{");
  const jsonEnd = stdout.lastIndexOf("}");
  if (jsonStart === -1 || jsonEnd === -1) return null;
  return JSON.parse(stdout.slice(jsonStart, jsonEnd + 1));
}

export function createMjClient({ cdpScript, debugPort, background }) {
  const cdpExtraArgs = background ? ["--background"] : [];
  const cdpEnv = {
    ...process.env,
    ACTION_MIRA_DEBUG_PORT: debugPort,
    ...(background ? { ACTION_MJ_BACKGROUND: "1" } : {}),
  };

  function runCdp(command, extraArgs = [], options = {}) {
    const startedAt = Date.now();
    const result = spawnSync("bun", [cdpScript, command, "--debug-port", debugPort, ...cdpExtraArgs, ...extraArgs], {
      encoding: "utf8",
      env: cdpEnv,
    });
    const parsed = parseCdpJson(result.stdout || "");
    const elapsedMs = Date.now() - startedAt;
    if (result.status !== 0 || parsed?.ok === false) {
      const message = parsed?.error
        || result.stderr?.trim()
        || result.stdout?.trim()
        || `CDP ${command} failed`;
      if (options.soft) {
        return { ok: false, error: message, data: parsed, status: result.status ?? 1, elapsedMs };
      }
      throw new Error(message);
    }
    if (!parsed) {
      throw new Error(`CDP ${command} returned no JSON:\n${result.stdout}`);
    }
    return { ok: true, data: parsed, elapsedMs };
  }

  return { runCdp, cdpEnv, cdpExtraArgs };
}

export function logMj(step, detail = "") {
  const stamp = new Date().toISOString().slice(11, 19);
  console.log(detail ? `[mj ${stamp}] ${step} — ${detail}` : `[mj ${stamp}] ${step}`);
}

export const OUTCOMES = {
  SUCCESS: "success",
  PARTIAL: "partial",
  SUBMITTED: "submitted",
  SKIPPED: "skipped",
  TIMEOUT: "timeout",
  MJ_FAILED: "mj_failed",
  SUBMIT_FAILED: "submit_failed",
  DOWNLOAD_FAILED: "download_failed",
  ERROR: "error",
};

const STATUS_ORDER = [
  "pending",
  "skipped",
  "preparing",
  "submitting",
  "submitted",
  "developing",
  "waiting_mj",
  "downloading",
  "ok",
  "partial",
  "failed",
];

export function resolveWaitMode(args, env = process.env) {
  if (args.includes("--submit-only") || args.includes("--no-wait")) return false;
  if (args.includes("--wait")) return true;
  if (env.ACTION_MJ_WAIT === "0" || env.ACTION_MJ_NO_WAIT === "1") return false;
  return true;
}

export function isCollectMode(args) {
  return args.includes("--collect") || args.includes("--wait-only");
}

export function classifyFailure(reason) {
  if (!reason) {
    return { outcome: OUTCOMES.ERROR, errorKind: "unknown" };
  }
  const text = String(reason).toLowerCase();
  if (text.includes("timed out") || text.includes("timeout")) {
    return { outcome: OUTCOMES.TIMEOUT, errorKind: "timeout" };
  }
  if (text.includes("creation failed") || text.includes("midjourney job failed") || text.includes("failed job")) {
    return { outcome: OUTCOMES.MJ_FAILED, errorKind: "mj_failed" };
  }
  if (text.includes("submit") || text.includes("verification failed")) {
    return { outcome: OUTCOMES.SUBMIT_FAILED, errorKind: "submit_failed" };
  }
  if (text.includes("download")) {
    return { outcome: OUTCOMES.DOWNLOAD_FAILED, errorKind: "download_failed" };
  }
  return { outcome: OUTCOMES.ERROR, errorKind: "error" };
}

export function outcomeForStatus(status, savedCount = 0, pickCount = 4) {
  if (status === "ok") return OUTCOMES.SUCCESS;
  if (status === "partial") return OUTCOMES.PARTIAL;
  if (status === "skipped") return OUTCOMES.SKIPPED;
  if (status === "submitted") return OUTCOMES.SUBMITTED;
  if (status === "failed") {
    return savedCount > 0 ? OUTCOMES.PARTIAL : OUTCOMES.ERROR;
  }
  if (savedCount >= pickCount) return OUTCOMES.SUCCESS;
  if (savedCount > 0) return OUTCOMES.PARTIAL;
  return null;
}

export function needsCollection(item) {
  return ["submitted", "developing", "waiting_mj"].includes(item.status);
}

export function initQueue(prompts, existingById = new Map(), queueById = new Map()) {
  const items = prompts.map((entry) => {
    const prior = existingById.get(entry.id);
    const queued = queueById.get(entry.id);
    if (prior?.status === "ok" || prior?.outcome === OUTCOMES.SUCCESS) {
      return {
        id: entry.id,
        title: entry.title,
        status: "skipped",
        outcome: OUTCOMES.SKIPPED,
        phase: "resume",
        message: `already ok (${prior.saved?.length ?? 0} saved)`,
        saved: prior.saved ?? [],
      };
    }
    if (queued && needsCollection(queued)) {
      return {
        id: entry.id,
        title: entry.title,
        status: queued.status,
        outcome: queued.outcome ?? OUTCOMES.SUBMITTED,
        phase: queued.phase ?? "collect",
        message: queued.message ?? "awaiting MJ development",
        attempts: queued.attempts ?? 0,
        pollCount: queued.pollCount ?? 0,
        saved: queued.saved ?? [],
        submittedAt: queued.submittedAt ?? null,
        needle: queued.needle ?? null,
        baselineHrefs: queued.baselineHrefs ?? [],
      };
    }
    return {
      id: entry.id,
      title: entry.title,
      status: "pending",
      outcome: null,
      phase: null,
      message: null,
      attempts: 0,
      pollCount: 0,
      saved: [],
    };
  });
  return {
    updatedAt: new Date().toISOString(),
    current: null,
    summary: summarize(items),
    items,
  };
}

export function summarize(items) {
  const summary = Object.fromEntries(STATUS_ORDER.map((status) => [status, 0]));
  for (const item of items) {
    summary[item.status] = (summary[item.status] ?? 0) + 1;
  }
  return summary;
}

export function findQueueItem(queue, id) {
  return queue.items.find((item) => item.id === id);
}

export async function saveQueue(outputDir, queue) {
  queue.updatedAt = new Date().toISOString();
  queue.summary = summarize(queue.items);
  const queuePath = join(outputDir, "queue.json");
  await writeFile(queuePath, `${JSON.stringify(queue, null, 2)}\n`);
  return queuePath;
}

export async function patchQueue(outputDir, queue, id, patch) {
  const item = findQueueItem(queue, id);
  if (!item) return queue;
  Object.assign(item, patch);
  if (patch.status && patch.status !== "pending") {
    queue.current = ["waiting_mj", "submitting", "preparing", "downloading", "developing"].includes(patch.status)
      ? id
      : null;
  }
  return saveQueue(outputDir, queue);
}

export async function pollForFreshJob({
  runCdp,
  baselineFile,
  baselineHrefs,
  needle,
  timeoutMs,
  minWaitMs,
  pollIntervalMs,
  startedAt,
  onPoll,
}) {
  const deadline = startedAt + timeoutMs;
  let pollCount = 0;

  while (Date.now() < deadline) {
    pollCount += 1;
    const elapsedMs = Date.now() - startedAt;
    const pollArgs = [
      "--min-fresh", "4",
      "--min-wait-ms", String(minWaitMs),
      "--started-at-ms", String(startedAt),
    ];
    if (baselineFile) {
      pollArgs.push("--baseline-file", baselineFile);
    } else if (baselineHrefs?.length) {
      pollArgs.push("--baseline-hrefs", baselineHrefs.join(","));
    }
    if (needle) pollArgs.push("--expected-prompt-substring", needle);

    const outcome = runCdp("poll-new", pollArgs, { soft: true });
    const payload = outcome.data ?? {};
    const tick = {
      pollCount,
      elapsedMs,
      complete: Boolean(payload.complete),
      freshCount: payload.fresh?.length ?? 0,
      failure: payload.failed ?? null,
      statusTexts: payload.statusTexts ?? [],
      newestPrompt: payload.newestPrompt ?? null,
      error: outcome.ok ? null : outcome.error,
    };

    if (onPoll) await onPoll(tick);

    if (payload.failed) {
      return { ok: false, reason: payload.failed.reason || "Midjourney job failed", pollCount, elapsedMs, payload };
    }
    if (payload.complete && payload.fresh?.length) {
      return { ok: true, fresh: payload.fresh, matchedJobId: payload.matchedJobId, pollCount, elapsedMs, payload };
    }

    await sleep(pollIntervalMs);
  }

  return {
    ok: false,
    reason: `Timed out after ${pollCount} poll(s) over ${Math.round((Date.now() - startedAt) / 1000)}s`,
    pollCount,
    elapsedMs: Date.now() - startedAt,
  };
}

export function printQueueStatus(queue) {
  const { summary, current } = queue;
  const parts = STATUS_ORDER
    .filter((status) => summary[status] > 0)
    .map((status) => `${status}=${summary[status]}`);
  console.log(`queue: ${parts.join(", ")}${current ? ` | current=${current}` : ""}`);
}