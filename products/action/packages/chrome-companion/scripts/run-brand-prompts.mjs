#!/usr/bin/env bun

import { mkdir, writeFile } from "node:fs/promises";
import { mkdtempSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { port, activateMiraProcess, miraChromePid } from "./mira-chrome.mjs";
import {
  classifyFailure,
  createMjClient,
  findQueueItem,
  initQueue,
  isCollectMode,
  logMj,
  needsCollection,
  OUTCOMES,
  outcomeForStatus,
  patchQueue,
  pollForFreshJob,
  printQueueStatus,
  resolveWaitMode,
  saveQueue,
  sleep,
} from "./mj-orchestrator.mjs";

const rootPath = fileURLToPath(new URL("..", import.meta.url));
const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
const cdpScript = join(repoRoot, "native/engine/scripts/mira-midjourney-cdp.mjs");
const args = process.argv.slice(2);
const promptsFile = argValue("--prompts-file") ||
  join(repoRoot, "assets/brand/explorations/midjourney-prompts.txt");
const outputDir = argValue("--output-dir") ||
  join(repoRoot, "assets/brand/explorations/midjourney");
const debugPort = String(port);
const timeoutMs = Number(process.env.ACTION_BRAND_PROMPT_TIMEOUT_MS || 600000);
const pollIntervalMs = Number(process.env.ACTION_MJ_POLL_INTERVAL_MS || 15000);
const minFresh = argValue("--min-fresh") || "4";
const pickCount = Number(argValue("--pick") || "4");
const maxRetries = Number(argValue("--retries") || process.env.ACTION_BRAND_PROMPT_RETRIES || "0");
const minWaitMs = Number(argValue("--min-wait-ms") || process.env.ACTION_BRAND_PROMPT_MIN_WAIT_MS || 45000);
const skipPrepare = args.includes("--skip-prepare");
const continueOnFailure = !args.includes("--fail-fast");
const resumeComplete = !args.includes("--no-resume");
const background = (args.includes("--background") || process.env.ACTION_MJ_BACKGROUND === "1") && !args.includes("--foreground");
const waitForDevelopment = resolveWaitMode(args);
const collectOnly = isCollectMode(args);

const only = args.includes("--only")
  ? args[args.indexOf("--only") + 1]?.split(",").map((entry) => entry.trim()).filter(Boolean)
  : undefined;
const dryRun = args.includes("--dry-run");
const referenceFile = argValue("--reference-file");
const referenceUrl = argValue("--reference-url");
const skipReference = args.includes("--no-reference");

const { runCdp } = createMjClient({ cdpScript, debugPort, background });

function argValue(flag) {
  let value;
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === flag) value = args[index + 1];
  }
  return value;
}

const speciesNeedlePattern = /\b(polar bear|brown bear|sea otter|red panda|magical girl|sword student|mecha pilot|hamster|giraffe|crocodile|alligator|elephant|rabbit|terrier|owl|fox|panda|otter|lion|tiger|wolf|deer|moose|badger|penguin|raccoon|hedgehog|capybara|eagle|frog|turtle|zebra|koala|flamingo|goat|schoolgirl|rogue|elf|robot|scout|cartographer|researcher|deckhand|guide)\b/i;

function promptNeedleFor(prompt) {
  if (/four pixel art sprite/i.test(prompt)) return "four pixel art sprite";
  const appIcon = prompt.match(/app icon of (?:an |a |the )?([^,.]{8,64})/i);
  if (appIcon) return appIcon[1].trim().toLowerCase().split(/\s+/).slice(0, 4).join(" ");
  if (/flat vector app icon/i.test(prompt)) return "flat vector app icon";
  const species = prompt.match(speciesNeedlePattern);
  if (species) return species[1].toLowerCase();
  const panel = prompt.match(/panel 1 ([^,]+?)(?=\s+panel 2)/i)
    || prompt.match(/panel 2 ([^,]+?)(?=\s+panel 3)/i)
    || prompt.match(/panel 3 ([^,]+?)(?=\s+panel 4)/i);
  if (panel) return panel[1].trim().toLowerCase();
  const featuring = prompt.match(/featuring (?:a |an )?([^,.]{8,48})/i);
  return featuring?.[1]?.trim().toLowerCase() ?? "";
}

function savedFilesForEntry(entryId) {
  try {
    return readdirSync(outputDir).filter((name) => name.startsWith(`${entryId}-`) && name.endsWith(".webp"));
  } catch {
    return [];
  }
}

function parsePrompts(text) {
  const blocks = [];
  let current;
  for (const line of text.split("\n")) {
    const heading = line.match(/^(\d{2}(?:-[\w-]+)?)\s+(.+)$/);
    if (heading) {
      if (current?.prompt) blocks.push(current);
      current = { id: heading[1], title: heading[2], prompt: "" };
      continue;
    }
    if (!current) continue;
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || /^Action (brand|character)/i.test(trimmed)) continue;
    current.prompt = current.prompt ? `${current.prompt} ${trimmed}` : trimmed;
  }
  if (current?.prompt) blocks.push(current);
  return blocks;
}

async function recoverComposer(reason) {
  logMj("recover", reason);
  const outcome = runCdp("prepare", [], { soft: true });
  if (!outcome.ok) {
    console.warn(`prepare during recovery failed: ${outcome.error}`);
  }
}

async function downloadResult(url, destPath) {
  if (!url || !/^https?:\/\//.test(url)) {
    throw new Error(`Invalid image URL: ${url || "(empty)"}`);
  }
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Download failed ${response.status} for ${url}`);
  }
  const bytes = await response.arrayBuffer();
  await writeFile(destPath, Buffer.from(bytes));
}

function manifestRecord({ entry, status, outcome, errorKind, attempts, lastError, saved }) {
  return {
    id: entry.id,
    title: entry.title,
    prompt: entry.prompt,
    status,
    outcome: outcome ?? outcomeForStatus(status, saved.length, pickCount),
    errorKind: errorKind ?? undefined,
    attempts,
    error: lastError || undefined,
    message: lastError || undefined,
    saved,
    waited: waitForDevelopment,
  };
}

async function loadExistingQueue(outputDir) {
  try {
    const queue = JSON.parse(await Bun.file(join(outputDir, "queue.json")).text());
    return new Map((queue.items ?? []).map((item) => [item.id, item]));
  } catch {
    return new Map();
  }
}

async function collectAndDownload({
  entry,
  queue,
  queueItem,
  attempts,
  minWaitForPoll = 0,
}) {
  const promptNeedle = queueItem.needle || promptNeedleFor(entry.prompt);
  const submittedAt = queueItem.submittedAt
    ? Date.parse(queueItem.submittedAt)
    : Date.now() - minWaitMs;
  const baselineHrefs = queueItem.baselineHrefs ?? [];

  await patchQueue(outputDir, queue, entry.id, {
    status: "waiting_mj",
    phase: "collect",
    outcome: OUTCOMES.SUBMITTED,
    attempts,
    message: "collecting MJ result",
  });
  logMj("collect", `${entry.id}${promptNeedle ? ` (needle: ${promptNeedle})` : ""}`);

  const wait = await pollForFreshJob({
    runCdp,
    baselineHrefs,
    needle: promptNeedle,
    timeoutMs,
    minWaitMs: minWaitForPoll,
    pollIntervalMs,
    startedAt: submittedAt,
    onPoll: async (tick) => {
      const msg = tick.complete
        ? `matched ${tick.freshCount} image(s) after ${Math.round(tick.elapsedMs / 1000)}s`
        : `poll ${tick.pollCount}: no match (${Math.round(tick.elapsedMs / 1000)}s)${tick.failure ? ` | ${tick.failure.reason || "mj failed"}` : ""}`;
      logMj("poll", `${entry.id} — ${msg}`);
      await patchQueue(outputDir, queue, entry.id, {
        status: tick.failure ? "developing" : "waiting_mj",
        phase: tick.failure ? "mj-failed" : "poll",
        pollCount: tick.pollCount,
        lastPollAt: new Date().toISOString(),
        message: msg,
      });
    },
  });

  if (!wait.ok) {
    const failure = classifyFailure(wait.reason);
    return {
      saved: [],
      status: "failed",
      outcome: failure.outcome,
      errorKind: failure.errorKind,
      lastError: wait.reason,
    };
  }

  await patchQueue(outputDir, queue, entry.id, {
    status: "downloading",
    phase: "download",
    message: `saving ${wait.fresh.length} image(s)`,
    matchedJobId: wait.matchedJobId,
  });
  logMj("harvest", `${entry.id} job ${wait.matchedJobId?.slice(0, 8) ?? "?"}`);

  const saved = [];
  const picks = (wait.fresh || [])
    .filter((result) => result.imageUrl && !/\/video\//i.test(result.imageUrl))
    .slice(0, pickCount);
  let downloadFailures = 0;
  for (const [index, result] of picks.entries()) {
    if (!result.imageUrl || /\/video\//i.test(result.imageUrl)) continue;
    const slug = entry.title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
    const filename = `${entry.id}-${slug}-${index + 1}.webp`;
    const destPath = join(outputDir, filename);
    const imageUrl = result.imageUrl.replace("_640_", "_1024_");
    try {
      await downloadResult(imageUrl, destPath);
      saved.push({ filename, href: result.href, imageUrl: result.imageUrl });
      logMj("saved", filename);
    } catch (error) {
      downloadFailures += 1;
      console.warn(`download failed ${filename}: ${error.message || error}`);
    }
  }

  if (saved.length === 0 && downloadFailures > 0) {
    const failure = classifyFailure(`all ${downloadFailures} download(s) failed for ${entry.id}`);
    return {
      saved,
      status: "failed",
      outcome: failure.outcome,
      errorKind: failure.errorKind,
      lastError: failure.outcome === OUTCOMES.DOWNLOAD_FAILED
        ? `all ${downloadFailures} download(s) failed for ${entry.id}`
        : wait.reason,
    };
  }

  if (saved.length === 0) {
    const failure = classifyFailure(wait.reason || `no images saved for ${entry.id}`);
    return {
      saved,
      status: "failed",
      outcome: failure.outcome,
      errorKind: failure.errorKind,
      lastError: wait.reason || `no images saved for ${entry.id}`,
    };
  }

  if (saved.length < pickCount) {
    return {
      saved,
      status: "partial",
      outcome: OUTCOMES.PARTIAL,
      errorKind: "partial",
      lastError: `saved ${saved.length}/${pickCount}`,
    };
  }

  return {
    saved,
    status: "ok",
    outcome: OUTCOMES.SUCCESS,
    errorKind: undefined,
    lastError: null,
  };
}

async function writeManifest(manifest) {
  const manifestPath = join(outputDir, "manifest.json");
  let merged = manifest;
  try {
    const existing = JSON.parse(await Bun.file(manifestPath).text());
    if (Array.isArray(existing)) {
      const byId = new Map(existing.map((entry) => [entry.id, entry]));
      for (const entry of manifest) byId.set(entry.id, entry);
      merged = [...byId.values()].sort((left, right) =>
        String(left.id).localeCompare(String(right.id), undefined, { numeric: true }));
    }
  } catch {
    /* first write */
  }
  await writeFile(manifestPath, `${JSON.stringify(merged, null, 2)}\n`);
}

async function main() {
  const promptText = await Bun.file(promptsFile).text();
  let prompts = parsePrompts(promptText);
  if (only?.length) {
    prompts = prompts.filter((entry) =>
      only.some((needle) => entry.id === needle || entry.id.startsWith(`${needle}-`)),
    );
  }

  if (prompts.length === 0) {
    throw new Error("No prompts matched.");
  }

  await mkdir(outputDir, { recursive: true });

  if (background) {
    console.log("background mode: will not activate Mira Chrome or steal focus");
  } else {
    try {
      activateMiraProcess(miraChromePid());
    } catch {
      // Mira may already be frontmost.
    }
  }

  console.log(
    collectOnly
      ? "collect mode: waiting for MJ jobs already in queue.json"
      : waitForDevelopment
        ? "wait mode: submit then poll until success, error, or timeout"
        : "submit-only mode: queue prompts to MJ without waiting for development",
  );

  const manifest = [];
  const failures = [];
  const existingById = new Map();
  if (resumeComplete) {
    try {
      const existing = JSON.parse(await Bun.file(join(outputDir, "manifest.json")).text());
      if (Array.isArray(existing)) {
        for (const entry of existing) existingById.set(entry.id, entry);
      }
    } catch {
      /* first run */
    }
  }

  const queueById = await loadExistingQueue(outputDir);
  const queue = initQueue(prompts, existingById, queueById);
  for (const entry of prompts) {
    const onDisk = savedFilesForEntry(entry.id);
    if (resumeComplete && onDisk.length >= pickCount) {
      const item = queue.items.find((row) => row.id === entry.id);
      if (item) {
        item.status = "skipped";
        item.outcome = OUTCOMES.SKIPPED;
        item.phase = "disk";
        item.message = `${onDisk.length} file(s) on disk`;
      }
    }
  }
  await saveQueue(outputDir, queue);
  printQueueStatus(queue);

  if (!dryRun && !skipPrepare && !collectOnly) {
    logMj("prepare", "composer reset");
    const prepared = runCdp("prepare", [], { soft: true });
    if (!prepared.ok) {
      console.warn(`prepare failed: ${prepared.error}`);
      if (!continueOnFailure) {
        throw new Error(prepared.error || "prepare failed");
      }
    } else if (!prepared.data?.ready) {
      const composerMode = prepared.data?.composerMode;
      const personalize = prepared.data?.personalize;
      const reason = composerMode?.conversational
        ? "Midjourney is stuck in Conversational Mode — click Create or exit conversational mode in Mira Chrome once"
        : personalize?.reason
          || "composer not ready (profile chip, settings, or queue may need manual cleanup)";
      console.error(`prepare not ready: ${reason}`);
      if (!continueOnFailure) {
        throw new Error(reason);
      }
    }
  }

  const workPrompts = collectOnly
    ? prompts.filter((entry) => {
      const item = findQueueItem(queue, entry.id);
      return item && needsCollection(item);
    })
    : prompts;

  if (collectOnly && workPrompts.length === 0) {
    console.log("collect: no submitted/developing items matched --only filter");
    printQueueStatus(queue);
    return;
  }

  for (const entry of workPrompts) {
    console.log(`\n=== ${entry.id} ${entry.title} ===`);
    if (dryRun) {
      console.log(entry.prompt);
      continue;
    }

    const prior = existingById.get(entry.id);
    if (prior?.status === "ok" && (prior.saved?.length ?? 0) >= pickCount) {
      console.log(`skip ${entry.id}: already saved ${prior.saved.length} image(s)`);
      manifest.push(prior);
      await patchQueue(outputDir, queue, entry.id, {
        status: "skipped",
        outcome: OUTCOMES.SKIPPED,
        phase: "manifest",
        message: "manifest ok",
      });
      continue;
    }

    const onDisk = savedFilesForEntry(entry.id);
    if (resumeComplete && onDisk.length >= pickCount) {
      console.log(`skip ${entry.id}: ${onDisk.length} file(s) already on disk`);
      const record = manifestRecord({
        entry,
        status: "ok",
        outcome: OUTCOMES.SUCCESS,
        attempts: 0,
        lastError: null,
        saved: onDisk.sort().map((filename) => ({ filename })),
      });
      manifest.push(record);
      await patchQueue(outputDir, queue, entry.id, {
        status: "skipped",
        outcome: OUTCOMES.SKIPPED,
        phase: "disk",
        message: `${onDisk.length} on disk`,
        saved: record.saved,
      });
      continue;
    }

    let saved = [];
    let status = "ok";
    let outcome = OUTCOMES.SUCCESS;
    let errorKind;
    let lastError = null;
    let attempts = 0;
    const queueItem = findQueueItem(queue, entry.id);

    if (collectOnly) {
      attempts = queueItem?.attempts ?? 1;
      const result = await collectAndDownload({ entry, queue, queueItem, attempts });
      saved = result.saved;
      status = result.status;
      outcome = result.outcome;
      errorKind = result.errorKind;
      lastError = result.lastError;
    } else {
      while (attempts <= maxRetries && saved.length === 0 && status !== "submitted") {
        attempts += 1;
        try {
          if (attempts > 1) {
            logMj("retry", `${entry.id} attempt ${attempts}/${maxRetries + 1}`);
            await recoverComposer(`retry ${entry.id}`);
            await sleep(3000);
          }

          await patchQueue(outputDir, queue, entry.id, {
            status: "preparing",
            phase: "baseline",
            attempts,
            message: "harvesting baseline",
          });

          const before = runCdp("harvest");
          const baselineHrefs = before.data.results.map((result) => result.href);
          const baselineDir = mkdtempSync(join(tmpdir(), "action-brand-baseline-"));
          const baselineFile = join(baselineDir, "baseline.json");
          await writeFile(baselineFile, JSON.stringify(baselineHrefs));

          const submitArgs = ["--prompt", entry.prompt];
          const promptNeedle = promptNeedleFor(entry.prompt);
          if (promptNeedle && waitForDevelopment) {
            submitArgs.push("--expected-prompt-substring", promptNeedle);
          } else if (!waitForDevelopment) {
            submitArgs.push("--skip-job-check");
          }
          if (referenceUrl && !skipReference) {
            submitArgs.unshift("--reference-url", referenceUrl);
          } else if (referenceFile && !skipReference) {
            submitArgs.unshift("--reference-file", referenceFile);
          }

          await patchQueue(outputDir, queue, entry.id, {
            status: "submitting",
            phase: "submit",
            needle: promptNeedle || null,
            message: "calling CDP submit",
          });
          logMj("submit", `${entry.id}${promptNeedle ? ` (needle: ${promptNeedle})` : ""}`);

          const submitOutcome = runCdp("submit", submitArgs, { soft: true });
          if (!submitOutcome.ok) {
            const failure = classifyFailure(submitOutcome.error);
            lastError = submitOutcome.error;
            outcome = failure.outcome;
            errorKind = failure.errorKind;
            console.warn(`submit failed: ${lastError}`);
            await patchQueue(outputDir, queue, entry.id, {
              status: "failed",
              phase: "submit-error",
              outcome,
              errorKind,
              message: lastError,
            });
            await recoverComposer(lastError);
            continue;
          }

          const submit = submitOutcome.data;
          if (submit.submitted && !submit.submitted.ok) {
            const failure = classifyFailure(submit.submitted.reason || "Submit did not queue a job");
            lastError = submit.submitted.reason || "Submit did not queue a job";
            outcome = failure.outcome;
            errorKind = failure.errorKind;
            console.warn(`submit not queued: ${lastError}`);
            await patchQueue(outputDir, queue, entry.id, {
              status: "failed",
              phase: "submit-error",
              outcome,
              errorKind,
              message: lastError,
            });
            await recoverComposer(lastError);
            continue;
          }
          if (submit.jobCheck && submit.jobCheck.ok === false) {
            const failure = classifyFailure(submit.jobCheck.reason || "Submitted job did not match needle");
            lastError = submit.jobCheck.reason || "Submitted job did not match needle";
            outcome = failure.outcome;
            errorKind = failure.errorKind;
            console.warn(`submit job check failed: ${lastError}`);
            await patchQueue(outputDir, queue, entry.id, {
              status: "failed",
              phase: "job-check",
              outcome,
              errorKind,
              message: lastError,
            });
            await recoverComposer(lastError);
            continue;
          }
          if (submit.verification && !submit.verification.ok) {
            const failure = classifyFailure(submit.verification.reason || "Prompt verification failed before submit");
            lastError = submit.verification.reason || "Prompt verification failed before submit";
            outcome = failure.outcome;
            errorKind = failure.errorKind;
            console.warn(lastError);
            await patchQueue(outputDir, queue, entry.id, {
              status: "failed",
              phase: "verify-error",
              outcome,
              errorKind,
              message: lastError,
            });
            await recoverComposer(lastError);
            continue;
          }

          const submittedAt = Date.now();
          const submitMeta = {
            submittedAt: new Date(submittedAt).toISOString(),
            pollCount: 0,
            needle: promptNeedle || null,
            baselineHrefs,
            attempts,
          };

          if (!waitForDevelopment) {
            status = "submitted";
            outcome = OUTCOMES.SUBMITTED;
            const queuedJobId = submit?.submitted?.freshCards?.[0]?.id
              || submit?.submitted?.queued?.[0]?.jobId
              || null;
            await patchQueue(outputDir, queue, entry.id, {
              ...submitMeta,
              status: "submitted",
              phase: "queued",
              outcome,
              matchedJobId: queuedJobId,
              message: queuedJobId
                ? `submitted to MJ (job ${queuedJobId.slice(0, 8)})`
                : "submitted to MJ — not waiting for development",
            });
            logMj("submitted", `${entry.id} queued in ${submitOutcome.elapsedMs}ms (no-wait)${queuedJobId ? ` job=${queuedJobId.slice(0, 8)}` : ""}`);
            break;
          }

          await patchQueue(outputDir, queue, entry.id, {
            ...submitMeta,
            status: "waiting_mj",
            phase: "poll",
            message: "submitted — polling MJ",
          });
          logMj("submitted", `${entry.id} in ${submitOutcome.elapsedMs}ms`);

          const result = await collectAndDownload({
            entry,
            queue,
            queueItem: {
              ...submitMeta,
              needle: promptNeedle || null,
            },
            attempts,
            minWaitForPoll: minWaitMs,
          });
          saved = result.saved;
          status = result.status;
          outcome = result.outcome;
          errorKind = result.errorKind;
          lastError = result.lastError;
          if (saved.length === 0) {
            await recoverComposer(lastError || "collect failed");
          }
        } catch (error) {
          const failure = classifyFailure(error.message || String(error));
          lastError = error.message || String(error);
          outcome = failure.outcome;
          errorKind = failure.errorKind;
          console.warn(`attempt error for ${entry.id}: ${lastError}`);
          await patchQueue(outputDir, queue, entry.id, {
            status: "failed",
            phase: "error",
            outcome,
            errorKind,
            message: lastError,
          });
          await recoverComposer(lastError);
        }
      }
    }

    if (status === "submitted") {
      console.log(`queued ${entry.id}: submitted to MJ (use --collect to wait and download later)`);
      await patchQueue(outputDir, queue, entry.id, {
        status: "submitted",
        outcome: OUTCOMES.SUBMITTED,
        message: "submitted to MJ — awaiting collection",
        attempts,
      });
    } else if (saved.length === 0) {
      status = "failed";
      const failure = classifyFailure(lastError);
      outcome = outcome || failure.outcome;
      errorKind = errorKind || failure.errorKind;
      failures.push({ id: entry.id, title: entry.title, error: lastError, outcome, errorKind, attempts });
      console.error(`failed ${entry.id} after ${attempts} attempt(s) — ${outcome}${lastError ? `: ${lastError}` : ""}`);
      await patchQueue(outputDir, queue, entry.id, {
        status: "failed",
        outcome,
        errorKind,
        message: lastError,
        attempts,
      });
      if (!continueOnFailure) {
        throw new Error(lastError || `Prompt ${entry.id} failed`);
      }
    } else if (saved.length < pickCount) {
      status = "partial";
      outcome = OUTCOMES.PARTIAL;
      errorKind = "partial";
      failures.push({ id: entry.id, title: entry.title, error: `saved ${saved.length}/${pickCount}`, outcome, errorKind, attempts });
      console.warn(`partial ${entry.id}: saved ${saved.length}/${pickCount} — moving on`);
      await patchQueue(outputDir, queue, entry.id, {
        status: "partial",
        outcome,
        errorKind,
        message: `saved ${saved.length}/${pickCount}`,
        saved,
        attempts,
      });
    } else {
      status = "ok";
      outcome = OUTCOMES.SUCCESS;
      await patchQueue(outputDir, queue, entry.id, {
        status: "ok",
        phase: "done",
        outcome,
        message: `saved ${saved.length}`,
        saved,
        attempts,
      });
    }

    manifest.push(manifestRecord({
      entry,
      status,
      outcome,
      errorKind,
      attempts,
      lastError,
      saved,
    }));
    await writeManifest(manifest);
    printQueueStatus(queue);
  }

  if (!dryRun) {
    queue.current = null;
    await saveQueue(outputDir, queue);
    const okCount = manifest.filter((entry) => entry.outcome === OUTCOMES.SUCCESS).length;
    const submittedCount = manifest.filter((entry) => entry.outcome === OUTCOMES.SUBMITTED).length;
    const failCount = failures.length;
    const outcomeSummary = Object.entries(
      manifest.reduce((counts, entry) => {
        const key = entry.outcome || entry.status || "unknown";
        counts[key] = (counts[key] ?? 0) + 1;
        return counts;
      }, {}),
    ).map(([key, count]) => `${key}=${count}`).join(", ");
    console.log(`\nDone. success=${okCount}, submitted=${submittedCount}, failures=${failCount}`);
    console.log(`outcomes: ${outcomeSummary}`);
    console.log(`artifacts → ${outputDir}`);
    console.log(`queue state → ${join(outputDir, "queue.json")}`);
    if (failCount > 0) {
      process.exitCode = 1;
    }
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});