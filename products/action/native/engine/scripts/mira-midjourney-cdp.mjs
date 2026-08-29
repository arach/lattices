#!/usr/bin/env bun

const command = process.argv[2] || "status";
const args = parseArgs(process.argv.slice(3));
const background = Boolean(args.background || process.env.ACTION_MJ_BACKGROUND === "1");
const debugPort = args.debugPort || process.env.ACTION_MIRA_DEBUG_PORT || "9333";
const targetURL = args.url || process.env.ACTION_MIDJOURNEY_URL || "https://www.midjourney.com/imagine";
const prompt = args.prompt || process.env.ACTION_MIDJOURNEY_PROMPT || "";
const timeoutMs = Number(args.timeoutMs || process.env.ACTION_MIDJOURNEY_TIMEOUT_MS || 240000);
const minImageCount = Number(args.minImageCount || process.env.ACTION_MIDJOURNEY_MIN_IMAGE_COUNT || 0);

switch (command) {
  case "status":
    await withPage(async (page) => {
      console.log(JSON.stringify(await page.status(), null, 2));
    });
    break;
  case "submit":
    if (!prompt) {
      throw new Error("Missing --prompt");
    }
    try {
      await withPage(async (page) => {
        const before = await page.status();
        if (!before.promptReady) {
          console.log(JSON.stringify({ ok: false, error: "Midjourney prompt box is not ready. Sign in to Midjourney in the mira profile first.", before }, null, 2));
          process.exitCode = 1;
          return;
        }
        const personalize = await page.ensurePersonalizationOff();
        if (!personalize.ok) {
          console.log(JSON.stringify({ ok: false, error: personalize.reason || "Unable to clear Midjourney profile chip on Imagine", personalize }, null, 2));
          process.exitCode = 1;
          return;
        }
        const preflight = await page.preflightComposer(prompt);
        if (!preflight.ok) {
          console.log(JSON.stringify({ ok: false, error: preflight.reason || "Midjourney composer is not ready for a clean submit", preflight }, null, 2));
          process.exitCode = 1;
          return;
        }
        await page.waitForSubmitIdle();
        const emptied = await page.ensureEmptyComposer();
        if (!emptied.ok) {
          console.log(JSON.stringify({
            ok: false,
            error: `Composer could not be cleared before submit: ${emptied.remaining || "(unknown)"}`,
          }, null, 2));
          process.exitCode = 1;
          return;
        }
        await page.ensureImageMode();
        await page.closeComposerSettings();
        let reference = null;
        let finalPrompt = sanitizePrompt(prompt);
        if (args.referenceUrl) {
          const crefUrl = args.referenceUrl.split("?")[0];
          reference = { ok: true, crefUrl, source: "url" };
          if (!finalPrompt.includes("--cref")) {
            finalPrompt = `${finalPrompt} --cref ${crefUrl} --cw 100`;
          }
        } else if (args.referenceFile) {
          reference = await page.attachReferenceImage(args.referenceFile);
          if (reference?.ok === false || !reference?.crefUrl) {
            console.log(JSON.stringify({
              ok: false,
              error: reference?.reason || "Reference upload did not produce a fresh --cref url",
              reference,
            }, null, 2));
            process.exitCode = 1;
            return;
          }
          if (!finalPrompt.includes("--cref")) {
            finalPrompt = `${finalPrompt} --cref ${reference.crefUrl} --cw 100`;
          }
        }
        const baselineHarvest = await page.harvest();
        const baselineJobIds = new Set((baselineHarvest.jobCards || []).map((card) => card.id));
        await page.setPromptText(finalPrompt);
        const verification = await page.verifyPromptText(finalPrompt);
        if (!verification.ok) {
          console.log(JSON.stringify({
            ok: false,
            error: verification.reason || "Prompt verification failed before submit",
            verification,
            reference,
            prompt: finalPrompt,
          }, null, 2));
          process.exitCode = 1;
          return;
        }
        await page.closeComposerSettings();
        await page.ensureNormalComposerMode();
        await page.focusPrompt();
        const submitted = await page.submitPrompt({ baselineJobIds }).catch(() => ({ ok: false }));
        if (!submitted?.ok) {
          console.log(JSON.stringify({
            ok: false,
            error: submitted?.reason || "Unable to click Midjourney submit button",
            submitted,
            verification,
            reference,
            prompt: finalPrompt,
          }, null, 2));
          process.exitCode = 1;
          return;
        }
        const skipJobCheck = Boolean(args.skipJobCheck);
        const needle = skipJobCheck ? "" : (args.expectedPromptSubstring || promptNeedleFrom(finalPrompt));
        const jobCheck = needle
          ? await page.waitForSubmittedJob(needle, 45000, baselineJobIds)
          : { ok: true, skipped: true };
        const after = await page.status();
        if (needle && jobCheck?.ok === false) {
          console.log(JSON.stringify({
            ok: false,
            error: jobCheck.reason || "Submitted job does not match intended prompt",
            before,
            after,
            prompt: finalPrompt,
            verification,
            reference,
            jobCheck,
          }, null, 2));
          process.exitCode = 1;
          return;
        }
        console.log(JSON.stringify({ ok: true, before, after, prompt: finalPrompt, verification, reference, submitted, jobCheck }, null, 2));
      });
    } catch (error) {
      console.log(JSON.stringify({ ok: false, error: error.message || String(error) }, null, 2));
      process.exitCode = 1;
    }
    break;
  case "wait-result":
    await withPage(async (page) => {
      const startedAt = Date.now();
      let last;
      while (Date.now() - startedAt < timeoutMs) {
        last = await page.status();
        if (last.imageCount > minImageCount || (minImageCount === 0 && last.resultLikelyReady)) {
          console.log(JSON.stringify(last, null, 2));
          return;
        }
        await sleep(5000);
      }
      console.log(JSON.stringify(last ?? await page.status(), null, 2));
      process.exitCode = 2;
    });
    break;
  case "harvest":
    await withPage(async (page) => {
      console.log(JSON.stringify(await page.harvest(), null, 2));
    });
    break;
  case "harvest-find":
    await withPage(async (page) => {
      const needle = args.expectedPromptSubstring;
      if (!needle) {
        throw new Error("harvest-find requires --expected-prompt-substring");
      }
      const maxScrolls = Number(args.maxScrolls || 60);
      const minFresh = Number(args.minFresh || 4);
      const found = await page.findJobByNeedle(needle, { maxScrolls, minFresh });
      console.log(JSON.stringify(found, null, 2));
      if (!found.ok) {
        process.exitCode = 1;
      }
    });
    break;
  case "debug-composer":
    await withPage(async (page) => {
      console.log(JSON.stringify(await page.debugComposer(), null, 2));
    });
    break;
  case "probe-cref":
    if (!args.referenceFile) {
      throw new Error("Missing --reference-file");
    }
    await withPage(async (page) => {
      await page.ensurePersonalizationOff();
      await page.waitForSubmitIdle(60000).catch(() => undefined);
      await page.focusPrompt();
      await page.clearPrompt();
      await page.clearComposerAttachments();
      const reference = await page.attachReferenceImage(args.referenceFile);
      console.log(JSON.stringify(reference, null, 2));
      if (!reference?.crefUrl) {
        process.exitCode = 1;
      }
    });
    break;
  case "prepare":
    await withPage(async (page) => {
      const before = await page.status();
      const personalize = await page.ensurePersonalizationOff();
      const cancelled = await page.cancelQueuedJobs();
      const trashed = await page.trashFailedJobs();
      await page.waitForSubmitIdle(60000).catch(() => undefined);
      await page.focusPrompt().catch(() => undefined);
      await page.clearPrompt().catch(() => undefined);
      await page.clearComposerAttachments();
      await page.forceClearPrompt().catch(() => undefined);
      const imageMode = await page.ensureImageMode();
      let reset = await page.resetComposerSettings();
      await sleep(1000);
      let resetPass2 = await page.resetComposerSettings();
      await sleep(500);
      const resetPass3 = await page.resetComposerSettings();
      resetPass2 = { ...resetPass2, pass3: resetPass3.actions };
      const settingsClosed = await page.closeComposerSettings();
      const composerMode = await page.ensureNormalComposerMode();
      const after = await page.status();
      const harvest = await page.harvest();
      console.log(JSON.stringify({
        before: {
          promptText: before.promptText?.slice(0, 200),
          textSample: before.textSample?.slice(0, 300),
          buttons: before.buttons?.filter((label) => /--profile|--hd|--ar|personalize|square|standard/i.test(label)).slice(0, 12),
        },
        personalize,
        imageMode,
        cancelled,
        trashed,
        reset,
        resetPass2,
        settingsClosed,
        composerMode,
        after: {
          promptText: after.promptText?.slice(0, 200),
          textSample: after.textSample?.slice(0, 300),
          buttons: after.buttons?.filter((label) => /--profile|--hd|--ar|personalize|square|standard/i.test(label)).slice(0, 12),
        },
        failedJobs: harvest.failedJobs?.length ?? 0,
        ready: personalize.ok && !(await page.composerToolbarState()).profileActive,
      }, null, 2));
    });
    break;
  case "animate":
    if (!args.jobId) {
      throw new Error("Missing --job-id");
    }
    await withPage(async (page) => {
      const motionPrompt = args.motionPrompt || "subtle idle motion loop, gentle breathing, pixel art character";
      const result = await page.animateJob(args.jobId, Number(args.jobIndex || 0), motionPrompt, timeoutMs);
      console.log(JSON.stringify(result, null, 2));
      if (!result.ok) {
        process.exitCode = 2;
      }
    });
    break;
  case "poll-new":
    await withPage(async (page) => {
      const scan = await scanForFreshJob(page, args);
      console.log(JSON.stringify({ ok: true, ...scan }, null, 2));
      if (scan.failed) process.exitCode = 3;
    });
    break;
  case "wait-new":
    await withPage(async (page) => {
      const startedAt = Date.now();
      const minWaitMs = Number(args.minWaitMs || 45000);
      let last;
      while (Date.now() - startedAt < timeoutMs) {
        const scan = await scanForFreshJob(page, { ...args, startedAtMs: startedAt, minWaitMs });
        last = scan.harvest;
        if (scan.failed) {
          console.log(JSON.stringify({ ...last, failed: scan.failed }, null, 2));
          process.exitCode = 3;
          return;
        }
        if (scan.complete) {
          console.log(JSON.stringify({
            ...last,
            fresh: scan.fresh,
            matchedJobId: scan.matchedJobId,
            matchedPrompt: scan.matchedPrompt,
          }, null, 2));
          return;
        }
        await sleep(2000);
      }
      const fallback = await scanForFreshJob(page, {
        ...args,
        startedAtMs: startedAt,
        minWaitMs: 0,
        minFresh: args.minFresh,
      });
      if (fallback.complete) {
        console.log(JSON.stringify({
          ...fallback.harvest,
          fresh: fallback.fresh,
          matchedJobId: fallback.matchedJobId,
          matchedPrompt: fallback.matchedPrompt,
          timedOut: true,
        }, null, 2));
        return;
      }
      console.log(JSON.stringify(fallback.harvest ?? last, null, 2));
      process.exitCode = 2;
    });
    break;
  default:
    console.error(`Unknown command: ${command}`);
    console.error("Usage: mira-midjourney-cdp.mjs status|prepare|submit|animate|wait-result|wait-new|poll-new|harvest|harvest-find [--debug-port PORT] [--prompt TEXT]");
    process.exit(1);
}

function isImageResult(result) {
  return result.imageUrl &&
    !result.imageUrl.startsWith("blob:") &&
    !/\/video\//i.test(result.imageUrl) &&
    /cdn\.midjourney|cdn\.discordapp/i.test(result.imageUrl);
}

async function loadBaselineJobs(args) {
  let baselineList = (args.baselineHrefs || "").split(",").filter(Boolean);
  if (args.baselineFile) {
    baselineList = JSON.parse(await Bun.file(args.baselineFile).text());
  }
  return new Set(baselineList.map((href) => href.match(/jobs\/([^?]+)/)?.[1]).filter(Boolean));
}

async function scanForFreshJob(page, args) {
  const baselineJobs = await loadBaselineJobs(args);
  const startedAt = Number(args.startedAtMs || Date.now());
  const minWaitMs = Number(args.minWaitMs ?? 45000);
  const harvest = await page.harvest();
  const failure = pickFreshFailure(harvest.failedJobs, baselineJobs, args.expectedPromptSubstring);
  if (failure) {
    return {
      complete: false,
      failed: failure,
      harvest,
      elapsedMs: Date.now() - startedAt,
      statusTexts: harvest.statusTexts ?? [],
      newestPrompt: newestHarvestPrompt(harvest),
    };
  }
  const grouped = groupFreshImageJobs(harvest, baselineJobs);
  const complete = pickCompleteJob(grouped, harvest, {
    minFresh: Number(args.minFresh || 4),
    needle: args.expectedPromptSubstring,
    minElapsedMs: minWaitMs,
    startedAt,
  });
  return {
    complete: Boolean(complete),
    fresh: complete?.items ?? [],
    matchedJobId: complete?.jobId ?? null,
    matchedPrompt: complete?.prompt ?? null,
    freshJobCandidates: grouped.size,
    harvest,
    elapsedMs: Date.now() - startedAt,
    statusTexts: harvest.statusTexts ?? [],
    newestPrompt: newestHarvestPrompt(harvest),
  };
}

function groupFreshImageJobs(harvest, baselineJobs) {
  const grouped = new Map();
  for (const result of harvest.results || []) {
    if (!isImageResult(result)) continue;
    const jobId = result.href.match(/jobs\/([^?]+)/)?.[1] || result.href;
    if (baselineJobs.has(jobId)) continue;
    const bucket = grouped.get(jobId) || [];
    bucket.push(result);
    grouped.set(jobId, bucket);
  }
  return grouped;
}

function newestHarvestPrompt(harvest) {
  const cards = [...(harvest.jobCards || [])].sort((left, right) => (right.rect?.y ?? 0) - (left.rect?.y ?? 0));
  return cards[0]?.prompt?.slice(0, 160) ?? null;
}

async function withPage(callback) {
  const target = await findOrOpenTarget();
  const client = await CDPClient.connect(target.webSocketDebuggerUrl);
  try {
    await client.send("Page.enable");
    await client.send("Runtime.enable");
    if (!background) {
      await client.send("Page.bringToFront");
    }
    if (!/midjourney\.com\/imagine/.test(target.url || "")) {
      await client.send("Page.navigate", { url: targetURL });
      await sleep(3000);
    }
    await sleep(250);
    await callback(new MidjourneyPage(client, { background }));
  } finally {
    client.close();
  }
}

async function findOrOpenTarget() {
  let targets = await listTargets();
  let target = chooseTarget(targets);
  if (target) {
    return target;
  }

  await fetch(`http://127.0.0.1:${debugPort}/json/new?${encodeURIComponent(targetURL)}`, {
    method: "PUT",
  }).catch(() => undefined);
  await sleep(1500);
  targets = await listTargets();
  target = chooseTarget(targets);
  if (!target) {
    throw new Error(`Unable to find or open Midjourney target on Chrome debug port ${debugPort}`);
  }
  return target;
}

async function listTargets() {
  const response = await fetch(`http://127.0.0.1:${debugPort}/json/list`);
  if (!response.ok) {
    throw new Error(`Chrome debug port ${debugPort} is not reachable`);
  }
  return await response.json();
}

function chooseTarget(targets) {
  return targets.find((target) => target.type === "page" && /midjourney\.com\/imagine/.test(target.url || ""))
    ?? targets.find((target) => target.type === "page" && /midjourney\.com/.test(target.url || ""))
    ?? targets.find((target) => target.type === "page" && /discord\.com\/oauth2/.test(target.url || ""));
}

class MidjourneyPage {
  constructor(client, options = {}) {
    this.client = client;
    this.background = Boolean(options.background);
  }

  async status() {
    const status = await this.evaluate(pageStatusExpression());
    const harvest = await this.harvest();
    return { ...status, recentResults: harvest.results };
  }

  async harvest() {
    return await this.evaluate(harvestExpression());
  }

  async focusPrompt() {
    const result = await this.evaluate(`
      (() => {
        const element = window.__actionFindPromptBox?.() ?? (${findPromptBoxSource()})();
        if (!element) return { ok: false, reason: "prompt box missing" };
        if (!${this.background ? "true" : "false"}) {
          element.scrollIntoView({ block: "center", inline: "center" });
          element.click();
        }
        element.focus();
        return { ok: true };
      })()
    `);
    if (!result.ok) {
      throw new Error(result.reason || "Unable to focus prompt box");
    }
  }

  async clearPrompt() {
    if (this.background) {
      await this.forceClearPrompt();
      return;
    }
    await this.focusPrompt().catch(() => undefined);
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyDown",
      key: "Meta",
      code: "MetaLeft",
      modifiers: 4,
    });
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyDown",
      key: "a",
      code: "KeyA",
      text: "a",
      unmodifiedText: "a",
      modifiers: 4,
    });
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyUp",
      key: "a",
      code: "KeyA",
      modifiers: 4,
    });
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyUp",
      key: "Meta",
      code: "MetaLeft",
    });
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyDown",
      key: "Backspace",
      code: "Backspace",
    });
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyUp",
      key: "Backspace",
      code: "Backspace",
    });
    await this.forceClearPrompt();
  }

  async forceClearPrompt() {
    return await this.evaluate(`
      (() => {
        ${findPromptBoxSource({ assign: true })}
        const promptBox = window.__actionFindPromptBox?.();
        if (!promptBox) return { ok: false, reason: "prompt box missing" };
        if ("value" in promptBox) promptBox.value = "";
        else promptBox.textContent = "";
        promptBox.dispatchEvent(new InputEvent("input", { bubbles: true }));
        return { ok: true };
      })()
    `);
  }

  async typeText(text) {
    for (const character of text) {
      await this.client.send("Input.dispatchKeyEvent", {
        type: "char",
        text: character,
        unmodifiedText: character,
      });
      await sleep(8);
    }
  }

  async readPromptText() {
    const status = await this.status();
    return (status.promptText || "").trim();
  }

  async ensureEmptyComposer() {
    for (let pass = 0; pass < 3; pass += 1) {
      await this.clearPrompt();
      await this.clearComposerAttachments();
      await this.forceClearPrompt();
      const current = await this.readPromptText();
      if (!current) return { ok: true, pass };
      await sleep(200);
    }
    const remaining = await this.readPromptText();
    return { ok: !remaining, remaining: remaining.slice(0, 240) };
  }

  async setPromptText(text) {
    const empty = await this.ensureEmptyComposer();
    if (!empty.ok) {
      throw new Error(`Composer is not empty before setPromptText: ${empty.remaining || "(unknown)"}`);
    }
    await this.focusPrompt();
    const assignPrompt = async () => this.evaluate(`
      (() => {
        ${findPromptBoxSource({ assign: true })}
        const element = window.__actionFindPromptBox?.();
        if (!element) return { ok: false, reason: "prompt box missing" };
        const text = ${JSON.stringify(text)};
        if ("value" in element) {
          const setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, "value")?.set
            || Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value")?.set;
          if (setter) setter.call(element, text);
          else element.value = text;
        } else {
          element.textContent = text;
        }
        element.dispatchEvent(new InputEvent("input", { bubbles: true }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
        const read = ("value" in element) ? element.value : (element.innerText || element.textContent || "");
        return { ok: Boolean(read.trim()), length: read.length, sample: read.slice(0, 240), method: "dom" };
      })()
    `);
    let result = await assignPrompt();
    if (!result.ok || result.length < text.length * 0.9 || result.length > text.length * 1.08) {
      await this.ensureEmptyComposer();
      await this.focusPrompt();
      result = await assignPrompt();
    }
    if (!result.ok || result.length < text.length * 0.9) {
      await this.ensureEmptyComposer();
      await this.focusPrompt();
      await this.typeText(text);
      const typed = await this.readPromptText();
      result = {
        ok: Boolean(typed.trim()),
        length: typed.length,
        sample: typed.slice(0, 240),
        method: "type",
      };
    }
    if (!result.ok) {
      throw new Error(result.reason || "Unable to set prompt text");
    }
    const corruption = promptCorruptionReason(await this.readPromptText(), text);
    if (corruption) {
      throw new Error(`Composer prompt looks corrupted after setPromptText: ${corruption}`);
    }
  }

  async waitForSubmitIdle(timeoutMs = 120000) {
    const startedAt = Date.now();
    while (Date.now() - startedAt < timeoutMs) {
      const status = await this.status();
      if (!/submitting\.\.\./i.test(status.textSample || "")) {
        return status;
      }
      await sleep(2000);
    }
    throw new Error("Timed out waiting for Midjourney composer to become idle");
  }

  async clearComposerAttachments() {
    return await this.evaluate(`
      (() => {
        ${findPromptBoxSource({ assign: true })}
        const promptBox = window.__actionFindPromptBox?.();
        const promptRect = promptBox?.getBoundingClientRect?.();
        const clickables = [...document.querySelectorAll("button,[role='button'],a,label")]
          .filter((element) => {
            const rect = element.getBoundingClientRect();
            return rect.width > 8 && rect.height > 8;
          });
        let removed = 0;
        for (const element of clickables) {
          const text = [
            element.getAttribute("aria-label"),
            element.innerText,
            element.textContent,
          ].filter(Boolean).join(" ").trim().toLowerCase();
          if (!/remove|delete|clear|close|trash|detach/i.test(text)) continue;
          const rect = element.getBoundingClientRect();
          if (promptRect && Math.abs(rect.y - promptRect.y) > 220) continue;
          element.click();
          removed += 1;
        }
        if (promptBox) {
          const read = ("value" in promptBox) ? promptBox.value : (promptBox.innerText || promptBox.textContent || "");
          const stripped = read
            .replace(/https?:\\/\\/cdn\\.midjourney\\.com\\/[^\\s]+/gi, "")
            .replace(/\\s--cref\\s+\\S+/gi, "")
            .replace(/\\s--cw\\s+\\d+/gi, "")
            .replace(/\\s{2,}/g, " ")
            .trim();
          if ("value" in promptBox) promptBox.value = stripped;
          else promptBox.textContent = stripped;
          promptBox.dispatchEvent(new InputEvent("input", { bubbles: true }));
        }
        return { ok: true, removed };
      })()
    `);
  }

  async verifyPromptText(expected) {
    const actual = await this.readPromptText();
    const expectedCore = expected.replace(/\s--[a-z]+(?:\s+[^\s]+)?/gi, "").trim().toLowerCase();
    const actualCore = actual.replace(/\s--[a-z]+(?:\s+[^\s]+)?/gi, "").trim().toLowerCase();
    if (!actualCore) {
      return { ok: false, reason: "Composer prompt is empty after setPromptText", actual };
    }
    const corruption = promptCorruptionReason(actual, expected);
    if (corruption) {
      return { ok: false, reason: `Composer prompt looks corrupted: ${corruption}`, actual: actual.slice(0, 240) };
    }
    if (/striped cat/i.test(actual) && !/striped cat/i.test(expected)) {
      return { ok: false, reason: "Composer still contains stale cat prompt text", actual: actual.slice(0, 240) };
    }
    const prefix = expectedCore.slice(0, Math.min(72, expectedCore.length));
    if (!actualCore.startsWith(prefix.slice(0, Math.min(32, prefix.length)))) {
      return { ok: false, reason: "Composer prompt does not match intended submission", actual: actual.slice(0, 240), expected: expected.slice(0, 240) };
    }
    if (actualCore.length > expectedCore.length * 1.12 + 24) {
      return { ok: false, reason: "Composer prompt is longer than expected and may contain merged stale text", actual: actual.slice(0, 240), expected: expected.slice(0, 240) };
    }
    return { ok: true, actual: actual.slice(0, 240) };
  }

  async preflightComposer(expectedPrompt) {
    const harvest = await this.harvest();
    const toolbar = await this.composerToolbarState();
    const text = `${toolbar.chips.join("\n")}`;
    const starting = ((await this.status()).textSample || "").match(/starting\.\.\./gi)?.length ?? 0;
    const failed = harvest.failedJobs?.length ?? 0;
    if (starting >= 2) {
      return { ok: false, reason: `Midjourney queue is busy (${starting} jobs still starting). Wait or trash stuck jobs before submitting again.` };
    }
    if (failed >= 1 && !/striped cat/i.test(expectedPrompt)) {
      return { ok: false, reason: `Midjourney has ${failed} failed job(s). Run prepare or trash failed jobs before submitting a new species.` };
    }
    if (toolbar.profileActive) {
      return { ok: false, reason: "Personalization profile chip is still on the Imagine toolbar (ph39jen). The P toggle must be off before cast runs." };
    }
    if (/--hd\b/i.test(text) && /--ar\s+4:3/i.test(text)) {
      return { ok: false, reason: "Composer toolbar still has HD + 4:3 from old cat runs. Run prepare to reset Square + Standard." };
    }
    return { ok: true, starting, failed, toolbar };
  }

  async composerToolbarState() {
    return await this.evaluate(`
      (() => {
        ${findPromptBoxSource({ assign: true })}
        function normalize(value) {
          return value.replace(/\\s+/g, " ").trim();
        }
        const promptBox = window.__actionFindPromptBox?.();
        const promptRect = promptBox?.getBoundingClientRect?.() ?? null;
        const chips = [...document.querySelectorAll("button,[role='button']")]
          .filter((element) => {
            const rect = element.getBoundingClientRect();
            const text = normalize(element.innerText || element.textContent || "");
            if (!text || text.length > 72) return false;
            if (!promptRect) return rect.bottom > window.innerHeight * 0.72;
            return Math.abs(rect.y - promptRect.y) < 120
              && rect.x >= promptRect.x - 120
              && rect.x <= promptRect.right + 520;
          })
          .map((element) => normalize(element.innerText || element.textContent || ""))
          .filter((text) => /--profile\\b|--ar\\b|--hd\\b|^p$/i.test(text) || /profile ph39jen|global v7\\/v8 profile/i.test(text));
        return {
          promptText: promptBox ? (("value" in promptBox) ? promptBox.value : (promptBox.innerText || promptBox.textContent || "")) : "",
          chips: [...new Set(chips)],
          profileActive: chips.some((text) => /--profile\\b|profile ph39jen|global v7\\/v8 profile/i.test(text)),
        };
      })()
    `);
  }

  async ensureImaginePage() {
    const currentUrl = (await this.evaluate(`location.href`)) || "";
    if (/midjourney\.com\/imagine/.test(currentUrl)) {
      return { navigated: false };
    }
    await this.client.send("Page.navigate", { url: targetURL });
    await sleep(1500);
    return { navigated: true };
  }

  async ensurePersonalizationOff() {
    await this.ensureImaginePage();
    const toolbarBefore = await this.composerToolbarState();
    if (!toolbarBefore.profileActive) {
      return { ok: true, skipped: true, toolbar: toolbarBefore };
    }

    const imagineBar = await this.toggleImagineProfileOff();
    let toolbar = await this.composerToolbarState();
    if (toolbar.profileActive) {
      const settingsReset = await this.resetComposerSettings();
      imagineBar.settingsReset = settingsReset;
      await sleep(800);
      toolbar = await this.composerToolbarState();
    }
    return {
      ok: !toolbar.profileActive,
      skipped: false,
      imagineBar,
      toolbar,
      reason: toolbar.profileActive
        ? "Profile chip still on Imagine toolbar — toggle P off in Mira Chrome once (we never open /personalize)."
        : undefined,
    };
  }

  async toggleImagineProfileOff() {
    const imagineBar = { actions: [] };
    for (let pass = 0; pass < 6; pass += 1) {
      const passResult = await this.evaluate(`
        (() => {
          ${findPromptBoxSource({ assign: true })}
          function normalize(value) {
            return value.replace(/\\s+/g, " ").trim();
          }
          function nearPrompt(rect, promptRect) {
            if (!promptRect) return rect.bottom > window.innerHeight * 0.72;
            return Math.abs(rect.y - promptRect.y) < 160
              && rect.x >= promptRect.x - 200
              && rect.x <= promptRect.right + 720;
          }
          function clickElement(element, label) {
            if (!element) return null;
            element.scrollIntoView({ block: "nearest", inline: "nearest" });
            element.click();
            const rect = element.getBoundingClientRect();
            element.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, clientX: rect.left + rect.width / 2, clientY: rect.top + rect.height / 2 }));
            return label;
          }
          const promptBox = window.__actionFindPromptBox?.();
          const promptRect = promptBox?.getBoundingClientRect?.() ?? null;
          const actions = [];
          const clickables = [...document.querySelectorAll("button,[role='button'],a,div,span")];
          const pButton = clickables.find((element) => {
            const rect = element.getBoundingClientRect();
            const text = normalize(element.innerText || element.getAttribute("aria-label") || element.getAttribute("title") || "");
            return nearPrompt(rect, promptRect)
              && (/^p$/i.test(text) || /^personalize$/i.test(text))
              && rect.width <= 120
              && rect.height <= 80;
          });
          const profileChip = clickables.find((element) => {
            const rect = element.getBoundingClientRect();
            const text = normalize(element.innerText || element.textContent || "");
            return nearPrompt(rect, promptRect)
              && (/--profile\\b|profile ph39jen|global v7\\/v8 profile/i.test(text))
              && text.length <= 140;
          });
          const preferP = ${pass % 2 === 0 ? "true" : "false"};
          if (preferP && pButton) {
            const label = clickElement(pButton, "p-toggle");
            if (label) actions.push(label);
          } else if (profileChip) {
            const label = clickElement(profileChip, "profile-chip");
            if (label) actions.push(label);
          } else if (pButton) {
            const label = clickElement(pButton, "p-toggle");
            if (label) actions.push(label);
          }
          return { actions, profileVisible: Boolean(profileChip), pVisible: Boolean(pButton) };
        })()
      `);
      imagineBar.actions.push(...(passResult.actions || []));
      await sleep(700);
      const toolbar = await this.composerToolbarState();
      if (!toolbar.profileActive) break;
    }
    return imagineBar;
  }

  async animateJob(jobId, index, motionPrompt) {
    const jobUrl = `https://www.midjourney.com/jobs/${jobId}?index=${index}`;
    await this.client.send("Page.navigate", { url: jobUrl });
    await sleep(2500);
    const clicked = await this.evaluate(`
      (() => {
        function isVisible(element) {
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          return rect.width > 8 && rect.height > 8
            && style.visibility !== "hidden"
            && style.display !== "none";
        }
        function normalize(value) {
          return value.replace(/\\s+/g, " ").trim();
        }
        const actions = [];
        const animateButton = [...document.querySelectorAll("button,[role='button'],a")]
          .filter(isVisible)
          .find((element) => /^animate$/i.test(normalize(element.innerText || element.textContent || element.getAttribute("aria-label") || "")));
        if (!animateButton) {
          return { ok: false, reason: "Animate button not found on job page" };
        }
        animateButton.click();
        actions.push("animate");
        return { ok: true, actions };
      })()
    `);
    if (!clicked?.ok) {
      return clicked;
    }
    await sleep(1500);
    await this.setPromptText(motionPrompt).catch(() => undefined);
    await this.pressEnter();
    await sleep(800);
    const submitted = await this.submitPrompt().catch(() => ({ ok: false }));
    return { ok: true, jobId, index, motionPrompt, clicked, submitted };
  }

  async waitForVideo(parentJobId, timeoutMs = 240000) {
    const startedAt = Date.now();
    let last;
    while (Date.now() - startedAt < timeoutMs) {
      last = await this.harvest();
      const videos = (last.results || []).filter((result) =>
        /\/video\//i.test(result.imageUrl || "")
        || /\.mp4/i.test(result.imageUrl || result.href || ""),
      );
      const match = videos.find((result) => {
        const text = `${result.href} ${result.imageUrl} ${result.text}`;
        return text.includes(parentJobId.slice(0, 8)) || /animate|motion|video/i.test(result.text || "");
      }) || videos[0];
      if (match?.imageUrl) {
        return { ok: true, video: match, elapsedMs: Date.now() - startedAt };
      }
      await sleep(5000);
    }
    return { ok: false, reason: "Timed out waiting for animate video", last };
  }

  async cancelQueuedJobs(max = 24) {
    let total = 0;
    for (let pass = 0; pass < max; pass += 1) {
      const result = await this.evaluate(`
        (() => {
          function isVisible(element) {
            const rect = element.getBoundingClientRect();
            const style = getComputedStyle(element);
            return rect.width > 8 && rect.height > 8
              && style.visibility !== "hidden"
              && style.display !== "none";
          }
          const cancelButtons = [...document.querySelectorAll("button,[role='button'],a")]
            .filter(isVisible)
            .filter((element) => /^cancel$/i.test((element.innerText || element.textContent || "").trim()));
          let clicked = 0;
          const reasons = [];
          for (const button of cancelButtons) {
            let node = button;
            for (let depth = 0; depth < 12; depth += 1) {
              node = node.parentElement;
              if (!node) break;
              const text = (node.innerText || node.textContent || "").trim();
              if (/queued|starting|submitting|\d+%\s*complete/i.test(text)) {
                button.click();
                clicked += 1;
                reasons.push(text.replace(/\\s+/g, " ").slice(0, 100));
                break;
              }
            }
          }
          return { clicked, reasons };
        })()
      `);
      if (!result?.clicked) break;
      total += result.clicked;
      await sleep(1400);
    }
    return { cancelled: total };
  }

  async trashFailedJobs(max = 12) {
    let total = 0;
    for (let pass = 0; pass < max; pass += 1) {
      const result = await this.evaluate(`
        (() => {
          function isVisible(element) {
            const rect = element.getBoundingClientRect();
            const style = getComputedStyle(element);
            return rect.width > 8 && rect.height > 8
              && style.visibility !== "hidden"
              && style.display !== "none";
          }
          const trashButtons = [...document.querySelectorAll("button,[role='button'],a")]
            .filter(isVisible)
            .filter((element) => /^trash$/i.test((element.innerText || element.textContent || "").trim()));
          for (const button of trashButtons) {
            let node = button;
            for (let depth = 0; depth < 12; depth += 1) {
              node = node.parentElement;
              if (!node) break;
              const text = (node.innerText || node.textContent || "").trim();
              if (/creation failed|not completed/i.test(text)) {
                button.click();
                const jobId = text.match(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i)?.[1] || null;
                return { clicked: true, jobId };
              }
            }
          }
          return { clicked: false };
        })()
      `);
      if (!result?.clicked) break;
      total += 1;
      await sleep(1200);
    }
    return { trashed: total };
  }

  async ensureImageMode() {
    const result = await this.evaluate(`
      (() => {
        ${findPromptBoxSource({ assign: true })}
        function isVisible(element) {
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          return rect.width >= 20 && rect.height >= 20
            && style.visibility !== "hidden"
            && style.display !== "none";
        }
        const promptRect = window.__actionFindPromptBox?.()?.getBoundingClientRect?.() ?? null;
        const toolbar = [...document.querySelectorAll("button,[role='button']")]
          .filter(isVisible)
          .filter((element) => {
            const rect = element.getBoundingClientRect();
            if (promptRect) {
              return Math.abs(rect.y - promptRect.y) < 80 && rect.x >= promptRect.x - 40;
            }
            return rect.y < 90 && rect.x > 900;
          });
        const iconButtons = toolbar
          .filter((element) => {
            const rect = element.getBoundingClientRect();
            const label = [
              element.getAttribute("aria-label"),
              element.getAttribute("title"),
              element.innerText,
              element.textContent,
            ].filter(Boolean).join(" ").trim();
            if (/^p$/i.test(label)) return false;
            if (label.length > 24) return false;
            if (!promptRect) return rect.y < 90 && rect.x > 2200 && rect.width <= 72 && rect.height <= 72;
            return Math.abs(rect.y - promptRect.y) < 100
              && rect.x >= promptRect.right - 20
              && rect.x <= promptRect.right + 360
              && rect.width <= 72
              && rect.height <= 72;
          })
          .sort((left, right) => left.getBoundingClientRect().x - right.getBoundingClientRect().x);
        const labeledImage = iconButtons.find((element) => {
          const label = [
            element.getAttribute("aria-label"),
            element.getAttribute("title"),
            element.innerText,
            element.textContent,
          ].filter(Boolean).join(" ").toLowerCase();
          return /\\bimage\\b/.test(label);
        });
        const labeledVideo = iconButtons.find((element) => {
          const label = [
            element.getAttribute("aria-label"),
            element.getAttribute("title"),
            element.innerText,
            element.textContent,
          ].filter(Boolean).join(" ").toLowerCase();
          return /\\bvideo\\b/.test(label);
        });
        const positionalImage = iconButtons.find((element) => promptRect
          ? element.getBoundingClientRect().x > promptRect.right + 30
          : element.getBoundingClientRect().x > 2350);
        const imageButton = labeledImage || positionalImage;
        if (!imageButton) {
          return {
            ok: false,
            reason: "image mode button not found in composer toolbar",
            iconCount: iconButtons.length,
            hasVideo: Boolean(labeledVideo),
          };
        }
        if (labeledVideo && labeledVideo !== imageButton) {
          labeledVideo.click();
        }
        imageButton.click();
        return {
          ok: true,
          action: labeledVideo && labeledVideo !== imageButton ? "video-then-image" : "image-mode",
          x: Math.round(imageButton.getBoundingClientRect().x),
          iconCount: iconButtons.length,
        };
      })()
    `);
    await sleep(400);
    return result;
  }

  async conversationalComposerActive() {
    return await this.evaluate(`
      (() => {
        function normalize(value) {
          return (value || "").replace(/\\s+/g, " ").trim();
        }
        ${findPromptBoxSource({ assign: true })}
        const promptBox = window.__actionFindPromptBox?.();
        const promptRect = promptBox?.getBoundingClientRect?.() ?? null;
        const topComposer = promptRect && promptRect.top < 140;
        const refine = [...document.querySelectorAll("body *")]
          .map((element) => normalize(element.innerText || element.textContent || ""))
          .some((text) => /^refine your prompt using text or voice$/i.test(text));
        return {
          active: Boolean(topComposer && refine),
          promptY: promptRect ? Math.round(promptRect.top) : null,
          refine,
        };
      })()
    `);
  }

  async ensureNormalComposerMode() {
    const actions = [];
    for (let pass = 0; pass < 5; pass += 1) {
      const state = await this.conversationalComposerActive();
      if (!state?.active) {
        return { ok: true, conversational: false, actions, promptY: state?.promptY ?? null };
      }

      const result = await this.evaluate(`
        (() => {
          function isVisible(element) {
            const rect = element.getBoundingClientRect();
            const style = getComputedStyle(element);
            return rect.width > 8 && rect.height > 8
              && style.visibility !== "hidden"
              && style.display !== "none";
          }
          function normalize(value) {
            return (value || "").replace(/\\s+/g, " ").trim();
          }
          const actions = [];
          const clickables = [...document.querySelectorAll("button,[role='button'],a,label,div,span")]
            .filter(isVisible);
          const convChip = clickables
            .filter((element) => {
              const text = normalize(element.innerText || element.textContent || "");
              const rect = element.getBoundingClientRect();
              return rect.top < 120 && /^conversational mode$/i.test(text);
            })
            .sort((left, right) => left.getBoundingClientRect().height - right.getBoundingClientRect().height)[0];
          if (convChip) {
            convChip.click();
            actions.push("conversational-chip");
          }
          const pButton = clickables.find((element) => {
            const rect = element.getBoundingClientRect();
            const text = normalize(element.innerText || element.getAttribute("aria-label") || "");
            return rect.top < 120 && rect.width <= 80 && /^p$/i.test(text);
          });
          if (pButton) {
            pButton.click();
            actions.push("top-p-toggle");
          }
          const create = clickables.find((element) => {
            const rect = element.getBoundingClientRect();
            const text = normalize(element.innerText || element.textContent || "");
            return rect.x < 180 && /^create$/i.test(text);
          });
          if (create) {
            create.click();
            actions.push("create-nav");
          }
          return { actions };
        })()
      `);
      actions.push(...(result.actions || []));
      await sleep(700);

      if (pass === 2) {
        await this.client.send("Page.reload", { ignoreCache: true });
        await sleep(2500);
      }
      if (pass === 3) {
        await this.ensureImaginePage();
        await sleep(1500);
      }
    }

    const finalState = await this.conversationalComposerActive();
    return {
      ok: !finalState?.active,
      conversational: Boolean(finalState?.active),
      actions,
      promptY: finalState?.promptY ?? null,
    };
  }

  async composerSettingsOpen() {
    return await this.evaluate(`
      (() => {
        const text = (document.body?.innerText || "").replace(/\\s+/g, " ");
        const settingsOpen = /add images.*aspect ratio|stylization|weirdness|variety/i.test(text)
          && /personalize.*on.*off|video batch size/i.test(text);
        return { settingsOpen };
      })()
    `);
  }

  async closeComposerSettings() {
    const dismissPanel = async () => this.evaluate(`
      (() => {
        ${findPromptBoxSource({ assign: true })}
        function isVisible(element) {
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          return rect.width > 8 && rect.height > 8
            && style.visibility !== "hidden"
            && style.display !== "none";
        }
        function normalize(value) {
          return (value || "").replace(/\\s+/g, " ").trim();
        }
        const actions = [];
        const promptBox = window.__actionFindPromptBox?.();
        if (promptBox) {
          promptBox.focus?.();
          promptBox.click?.();
          actions.push("focus-prompt");
        }
        const clickables = [...document.querySelectorAll("button,[role='button'],a,label,div,span")].filter(isVisible);
        const settingsToggle = clickables.find((element) => {
          const text = normalize(element.innerText || element.textContent || element.getAttribute("aria-label") || "");
          return /^settings$/i.test(text) || /^--ar\\b/i.test(text) || /^ar\\b/i.test(text);
        });
        if (settingsToggle) {
          settingsToggle.click();
          actions.push("toggle-settings");
        }
        const gridHit = document.elementFromPoint(
          Math.round(window.innerWidth * 0.45),
          Math.round(Math.max(220, window.innerHeight * 0.35)),
        );
        if (gridHit && !gridHit.closest("button,[role='button'],textarea,[contenteditable='true'],[role='textbox']")) {
          gridHit.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
          gridHit.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
          gridHit.dispatchEvent(new MouseEvent("click", { bubbles: true }));
          actions.push("click-grid");
        }
        return { actions };
      })()
    `);

    for (let pass = 0; pass < 4; pass += 1) {
      await dismissPanel();
      await this.client.send("Input.dispatchKeyEvent", {
        type: "keyDown",
        key: "Escape",
        code: "Escape",
        windowsVirtualKeyCode: 27,
        nativeVirtualKeyCode: 27,
      });
      await this.client.send("Input.dispatchKeyEvent", {
        type: "keyUp",
        key: "Escape",
        code: "Escape",
        windowsVirtualKeyCode: 27,
        nativeVirtualKeyCode: 27,
      });
      await sleep(350);
      const state = await this.composerSettingsOpen();
      if (!state?.settingsOpen) {
        return { ok: true, settingsOpen: false, passes: pass + 1 };
      }
    }
    return { ok: false, settingsOpen: true };
  }

  async openComposerSettings() {
    return await this.evaluate(`
      (() => {
        ${findPromptBoxSource({ assign: true })}
        function isVisible(element) {
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          return rect.width > 8 && rect.height > 8
            && style.visibility !== "hidden"
            && style.display !== "none";
        }
        function normalize(value) {
          return value.replace(/\\s+/g, " ").trim();
        }
        const promptRect = window.__actionFindPromptBox?.()?.getBoundingClientRect?.() ?? null;
        const composerScope = [...document.querySelectorAll("button,[role='button'],a,label,div,span")]
          .filter(isVisible)
          .filter((element) => {
            const rect = element.getBoundingClientRect();
            if (!promptRect) return rect.bottom > window.innerHeight * 0.72;
            return rect.top >= promptRect.top - 180 && rect.bottom <= window.innerHeight + 40;
          });
        const opener = composerScope.find((element) => {
          const text = normalize(element.innerText || element.textContent || "");
          return /^--ar\\b/i.test(text) || /^ar\\b/i.test(text) || /^settings$/i.test(text);
        });
        if (opener) opener.click();
        return { ok: Boolean(opener), label: opener ? normalize(opener.innerText || opener.textContent || "").slice(0, 60) : null };
      })()
    `);
  }

  async resetComposerSettings() {
    await this.openComposerSettings();
    await sleep(600);
    const firstPass = await this.evaluate(`
      (() => {
        function isVisible(element) {
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          return rect.width > 8 && rect.height > 8
            && style.visibility !== "hidden"
            && style.display !== "none";
        }
        function normalize(value) {
          return value.replace(/\\s+/g, " ").trim();
        }
        function clickExact(labels) {
          const clickables = [...document.querySelectorAll("button,[role='button'],a,label,div,span")].filter(isVisible);
          for (const label of labels) {
            const match = clickables.find((element) => normalize(element.innerText || element.textContent || "") === label);
            if (match) {
              match.click();
              return label;
            }
          }
          return null;
        }
        const actions = [];
        const square = clickExact(["Square", "1:1"]);
        if (square) actions.push("square");
        const standard = clickExact(["Standard"]);
        if (standard) actions.push("standard");
        const off = clickExact(["Off"]);
        if (off) actions.push("personalize-off");
        return { ok: true, actions };
      })()
    `);
    await this.closeComposerSettings();
    return firstPass;
  }

  async debugComposer() {
    const settings = await this.composerSettingsOpen();
    const promptCandidates = await this.evaluate(`
      (() => {
        function isVisible(element) {
          const rect = element.getBoundingClientRect();
          const style = getComputedStyle(element);
          return rect.width > 40 && rect.height > 12
            && style.visibility !== "hidden"
            && style.display !== "none";
        }
        return [...document.querySelectorAll("textarea,[contenteditable='true'],[role='textbox'],input[type='text'],input:not([type])")]
          .filter(isVisible)
          .map((element) => {
            const rect = element.getBoundingClientRect();
            return {
              tag: element.tagName,
              y: Math.round(rect.y),
              h: Math.round(rect.height),
              w: Math.round(rect.width),
              ph: (element.getAttribute("placeholder") || element.getAttribute("aria-label") || "").slice(0, 60),
              text: ((element.value ?? element.innerText ?? element.textContent) || "").slice(0, 80),
            };
          })
          .slice(0, 12);
      })()
    `);
    const submitProbe = await this.evaluate(`
      (() => {
        ${findPromptBoxSource({ assign: true })}
        function normalize(value) {
          return (value || "").replace(/\\s+/g, " ").trim();
        }
        function isVisible(button) {
          const rect = button.getBoundingClientRect();
          const style = getComputedStyle(button);
          return rect.width >= 16 && rect.height >= 16
            && style.visibility !== "hidden"
            && style.display !== "none"
            && style.pointerEvents !== "none";
        }
        const element = window.__actionFindPromptBox?.();
        if (!element) return { ok: false, reason: "prompt box missing" };
        const promptRect = element.getBoundingClientRect();
        const topComposer = promptRect.top < 140;
        const buttons = [...document.querySelectorAll("button,[role='button'],[type='submit']")]
          .filter(isVisible)
          .map((button) => {
            const rect = button.getBoundingClientRect();
            return {
              label: normalize([
                button.getAttribute("aria-label"),
                button.getAttribute("title"),
                button.innerText,
                button.textContent,
              ].filter(Boolean).join(" ")).slice(0, 48),
              x: Math.round(rect.x + rect.width / 2),
              y: Math.round(rect.y + rect.height / 2),
              w: Math.round(rect.width),
              h: Math.round(rect.height),
            };
          })
          .filter((button) => topComposer ? button.y < 140 : button.y > window.innerHeight * 0.65)
          .slice(0, 24);
        return {
          ok: true,
          topComposer,
          promptRect: {
            x: Math.round(promptRect.x),
            y: Math.round(promptRect.y),
            w: Math.round(promptRect.width),
            h: Math.round(promptRect.height),
          },
          buttons,
        };
      })()
    `);
    return { settings, promptCandidates, submitProbe };
  }

  async scanQueuedPrompts() {
    return await this.evaluate(`
      (() => {
        const prompts = [];
        const seen = new Set();
        for (const element of document.querySelectorAll("body *")) {
          const text = (element.innerText || element.textContent || "").replace(/\\s+/g, " ").trim();
          if (!/^(queued|starting|submitting)/i.test(text)) continue;
          if (text.length < 60 || text.length > 1200 || seen.has(text)) continue;
          seen.add(text);
          const prompt = text
            .replace(/^(queued|starting|submitting)\\.\\.\\.?\\s*/i, "")
            .replace(/\\+ use text.*/i, "")
            .trim();
          if (prompt.length > 40) prompts.push(prompt.slice(0, 320));
        }
        return prompts;
      })()
    `);
  }

  async scrollFeed(stepPx = 720) {
    await this.evaluate(`
      (() => {
        const step = ${Number.isFinite(stepPx) ? stepPx : 720};
        const candidates = [...document.querySelectorAll("main, body, html, [class*='scroll']")]
          .filter((element) => element.scrollHeight > element.clientHeight + 40)
          .sort((left, right) =>
            (right.scrollHeight - right.clientHeight) - (left.scrollHeight - left.clientHeight),
          );
        const target = candidates[0] || document.documentElement;
        target.scrollTop += step;
        window.scrollBy(0, step);
        return {
          tag: target.tagName,
          scrollTop: target.scrollTop,
          scrollHeight: target.scrollHeight,
          step,
        };
      })()
    `);
    await sleep(700);
  }

  async findJobByNeedle(needle, options = {}) {
    const maxScrolls = options.maxScrolls ?? 60;
    const minFresh = options.minFresh ?? 4;
    const sources = [
      { label: "imagine", url: targetURL },
      { label: "organize", url: "https://www.midjourney.com/organize" },
      { label: "archive", url: "https://www.midjourney.com/archive" },
    ];
    let lastHarvest = null;

    for (const source of sources) {
      const currentUrl = (await this.evaluate(`location.href`)) || "";
      if (!currentUrl.includes(source.url.replace("https://www.midjourney.com", ""))) {
        await this.client.send("Page.navigate", { url: source.url });
        await sleep(2200);
      }
      await this.evaluate(`(() => { window.scrollTo(0, 0); document.documentElement.scrollTop = 0; document.body.scrollTop = 0; })()`);
      await sleep(400);

      for (let scroll = 0; scroll <= maxScrolls; scroll += 1) {
        const harvest = await this.harvest();
        lastHarvest = harvest;
        const grouped = groupFreshImageJobs(harvest, new Set());
        const complete = pickCompleteJob(grouped, harvest, {
          minFresh,
          needle,
          minElapsedMs: 0,
          startedAt: 0,
        });
        if (complete) {
          return {
            ok: true,
            source: source.label,
            jobId: complete.jobId,
            prompt: complete.prompt,
            fresh: complete.items,
            scrolls: scroll,
            harvest,
          };
        }
        if (scroll < maxScrolls) {
          await this.scrollFeed();
        }
      }
    }

    return {
      ok: false,
      reason: `No completed job matching "${needle}" on imagine or archive after ${maxScrolls} scroll(s) each`,
      scrolls: maxScrolls,
      harvest: lastHarvest,
    };
  }

  async waitForSubmittedJob(needle, timeoutMs = 45000, baselineJobIds = new Set()) {
    if (!needle) return { ok: true, skipped: true };
    const wants = needle.toLowerCase();
    const startedAt = Date.now();
    while (Date.now() - startedAt < timeoutMs) {
      const harvest = await this.harvest();
      const prompts = [
        ...(await this.scanQueuedPrompts()),
        ...(harvest.jobCards || [])
          .filter((card) => card.id && !baselineJobIds.has(card.id))
          .map((card) => card.prompt)
          .filter(Boolean),
      ];
      for (const rawPrompt of prompts) {
        const prompt = rawPrompt.toLowerCase();
        if (/striped cat|steampunk aviator/.test(prompt) && !/\bcat\b/.test(wants)) {
          return {
            ok: false,
            reason: `Midjourney queued a cat/profile job instead of "${needle}". Clear Personalize profile before retrying.`,
            prompt: rawPrompt.slice(0, 240),
          };
        }
        if (prompt.includes(wants)) {
          return { ok: true, prompt: rawPrompt.slice(0, 240) };
        }
      }
      await sleep(1000);
    }
    return {
      ok: false,
      uncertain: true,
      reason: `No matching fresh job card detected for "${needle}" within ${timeoutMs}ms`,
    };
  }

  async submitPrompt(options = {}) {
    const baselineJobIds = options.baselineJobIds ?? new Set();
    await this.closeComposerSettings();
    let clickAttempt = await this.evaluate(`
      (() => {
        ${findPromptBoxSource({ assign: true })}
        const element = window.__actionFindPromptBox?.();
        if (!element) return { ok: false, reason: "prompt box missing" };
        function normalize(value) {
          return (value || "").replace(/\\s+/g, " ").trim();
        }
        function isVisible(button) {
          const rect = button.getBoundingClientRect();
          const style = getComputedStyle(button);
          return rect.width >= 20 && rect.height >= 20
            && style.visibility !== "hidden"
            && style.display !== "none"
            && style.pointerEvents !== "none";
        }
        const promptRect = element.getBoundingClientRect();
        const topComposer = promptRect.top < 140;
        const nearComposer = (rect) => {
          if (topComposer) {
            return rect.y < 140
              && rect.x >= promptRect.right + 40
              && rect.x <= promptRect.right + 720;
          }
          const verticalNear = Math.abs(rect.y - promptRect.y) < 140
            || (rect.bottom >= promptRect.top - 24 && rect.top <= promptRect.bottom + 96);
          const horizontalNear = rect.x >= promptRect.x - 96
            && rect.x <= promptRect.right + 360;
          const inBottomBand = rect.bottom >= window.innerHeight * 0.78
            && rect.x >= promptRect.x - 48;
          return (verticalNear && horizontalNear) || inBottomBand;
        };
        const buttons = [...document.querySelectorAll("button,[role='button'],[type='submit']")]
          .filter(isVisible)
          .filter((button) => nearComposer(button.getBoundingClientRect()));
        const ranked = buttons.sort((left, right) => {
          const lr = left.getBoundingClientRect();
          const rr = right.getBoundingClientRect();
          const leftScore = lr.x - promptRect.right + (lr.width <= 72 ? 24 : 0);
          const rightScore = rr.x - promptRect.right + (rr.width <= 72 ? 24 : 0);
          return rightScore - leftScore;
        });
        const badLabel = /^(p|add image|explore|create|edit|organize|personalize|moodboards|help|updates|light mode|midjourney|tasks|arach)$/i;
        const buttonText = (button) => normalize([
          button.getAttribute("aria-label"),
          button.getAttribute("title"),
          button.innerText,
          button.textContent,
        ].filter(Boolean).join(" "));
        const isExcluded = (button) => {
          const text = buttonText(button).toLowerCase();
          return badLabel.test(text)
            || /^--/.test(text)
            || /conversational|refine your prompt|voice|add images|settings|aspect ratio|rerun|trash|more|use|extend|search|folder|loading|new folder/i.test(text);
        };
        const eligible = ranked.filter((button) => !isExcluded(button));
        const submit = eligible.find((button) => {
          const text = buttonText(button).toLowerCase();
          return /^(submit|send|imagine|run|go)$/.test(text) || /^submit|^send/.test(text);
        }) || [...eligible]
          .filter((button) => {
            const rect = button.getBoundingClientRect();
            return rect.width <= 80 && rect.height <= 80 && rect.x >= promptRect.right + 120;
          })
          .sort((left, right) => right.getBoundingClientRect().x - left.getBoundingClientRect().x)[0];
        if (!submit) {
          return {
            ok: false,
            reason: "prompt-adjacent submit button missing",
            debug: ranked.slice(0, 10).map((button) => {
              const rect = button.getBoundingClientRect();
              return {
                label: normalize(button.innerText || button.getAttribute("aria-label") || ""),
                x: Math.round(rect.x),
                y: Math.round(rect.y),
                w: Math.round(rect.width),
                h: Math.round(rect.height),
              };
            }),
          };
        }
        const rect = submit.getBoundingClientRect();
        return {
          ok: true,
          label: submit.innerText || submit.getAttribute("aria-label") || "send",
          method: "click",
          x: Math.round(rect.left + rect.width / 2),
          y: Math.round(rect.top + rect.height / 2),
        };
      })()
    `);

    await this.closeComposerSettings();
    if (this.background) {
      await this.client.send("Page.bringToFront");
      await sleep(250);
    }

    if (clickAttempt?.ok) {
      const domClick = await this.evaluate(`
        (() => {
          ${findPromptBoxSource({ assign: true })}
          function normalize(value) {
            return (value || "").replace(/\\s+/g, " ").trim();
          }
          function isVisible(button) {
            const rect = button.getBoundingClientRect();
            const style = getComputedStyle(button);
            return rect.width >= 20 && rect.height >= 20
              && style.visibility !== "hidden"
              && style.display !== "none"
              && style.pointerEvents !== "none";
          }
          const element = window.__actionFindPromptBox?.();
          if (!element) return { ok: false, reason: "prompt box missing" };
          const promptRect = element.getBoundingClientRect();
          const topComposer = promptRect.top < 140;
          const nearComposer = (rect) => {
            if (topComposer) {
              return rect.y < 120 && rect.x >= promptRect.right + 80 && rect.x <= promptRect.right + 520;
            }
            const verticalNear = Math.abs(rect.y - promptRect.y) < 140
              || (rect.bottom >= promptRect.top - 24 && rect.top <= promptRect.bottom + 96);
            const horizontalNear = rect.x >= promptRect.x - 96 && rect.x <= promptRect.right + 360;
            const inBottomBand = rect.bottom >= window.innerHeight * 0.78 && rect.x >= promptRect.x - 48;
            return (verticalNear && horizontalNear) || inBottomBand;
          };
          const buttons = [...document.querySelectorAll("button,[role='button'],[type='submit']")]
            .filter(isVisible)
            .filter((button) => nearComposer(button.getBoundingClientRect()));
          const badLabel = /^(p|add image|explore|create|edit|organize|personalize|moodboards|help|updates|light mode|midjourney|tasks|arach)$/i;
          const buttonText = (button) => normalize([
            button.getAttribute("aria-label"),
            button.getAttribute("title"),
            button.innerText,
            button.textContent,
          ].filter(Boolean).join(" "));
          const isExcluded = (button) => {
            const text = buttonText(button).toLowerCase();
            return badLabel.test(text)
              || /^--/.test(text)
              || /conversational|refine your prompt|voice|add images|settings|aspect ratio|rerun|trash|more|use|extend|search|folder|loading|new folder/i.test(text);
          };
          const submit = buttons.find((button) => /^(submit|send|imagine|run|go)$/i.test(buttonText(button).toLowerCase()))
            || buttons.find((button) => {
              const rect = button.getBoundingClientRect();
              return !isExcluded(button) && rect.x >= promptRect.right + 120 && rect.width <= 72 && rect.height <= 72;
            });
          if (!submit) return { ok: false, reason: "prompt-adjacent submit button missing on dom click" };
          submit.scrollIntoView({ block: "nearest", inline: "nearest" });
          submit.click();
          const rect = submit.getBoundingClientRect();
          return {
            ok: true,
            label: buttonText(submit) || "send",
            x: Math.round(rect.left + rect.width / 2),
            y: Math.round(rect.top + rect.height / 2),
          };
        })()
      `);
      if (domClick?.ok) {
        clickAttempt = { ...clickAttempt, ...domClick, method: "dom-click" };
      } else if (clickAttempt.x && clickAttempt.y) {
        await this.clickAt(clickAttempt.x, clickAttempt.y);
      }
    }

    async function verifyQueued(method, label, extra = {}) {
      await sleep(1400);
      const queued = await this.scanQueuedPrompts();
      const harvest = await this.harvest();
      const freshCards = (harvest.jobCards || []).filter((card) => card.id && !baselineJobIds.has(card.id));
      const activity = (harvest.statusTexts || []).some((text) => {
        const trimmed = text.trim();
        return /^(queued|starting|submitting)\b/i.test(trimmed)
          || /\d+%\s*complete/i.test(trimmed);
      });
      if ((queued?.length ?? 0) > 0 || freshCards.length > 0 || activity) {
        if (freshCards.length > 0 && !queued?.length && !activity) {
          return {
            ok: false,
            reason: "submit click did not produce queued activity (stale cards only)",
            method,
            queued,
            freshCards,
            statusTexts: harvest.statusTexts,
            ...extra,
          };
        }
        return {
          ok: true,
          label,
          method,
          queued,
          activity,
          freshCards: freshCards.map((card) => ({ id: card.id, prompt: card.prompt?.slice(0, 120) })),
          ...extra,
        };
      }
      return {
        ok: false,
        reason: "submit did not queue a visible Midjourney job",
        method,
        queued,
        freshCards,
        statusTexts: harvest.statusTexts,
        ...extra,
      };
    }

    if (clickAttempt?.ok && !/search|folder|loading/i.test(clickAttempt.label || "")) {
      const verified = await verifyQueued.call(this, clickAttempt.method, clickAttempt.label, { click: clickAttempt });
      if (verified.ok) return verified;
      clickAttempt = verified;
    } else if (clickAttempt?.ok) {
      clickAttempt = { ok: false, reason: `refusing non-submit control: ${clickAttempt.label}`, debug: clickAttempt };
    }

    await this.focusPrompt().catch(() => undefined);
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyDown",
      key: "Enter",
      code: "Enter",
      windowsVirtualKeyCode: 13,
      nativeVirtualKeyCode: 36,
      modifiers: 4,
    });
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyUp",
      key: "Enter",
      code: "Enter",
      windowsVirtualKeyCode: 13,
      nativeVirtualKeyCode: 36,
      modifiers: 4,
    });
    let entered = await verifyQueued.call(this, "keyboard", "cmd-enter", {
      clickFailed: clickAttempt?.reason,
      debug: clickAttempt?.debug,
    });
    if (entered.ok) return entered;
    await this.pressEnter();
    entered = await verifyQueued.call(this, "keyboard", "enter", {
      clickFailed: clickAttempt?.reason,
      debug: clickAttempt?.debug,
    });
    if (entered.ok) return entered;
    return {
      ok: false,
      reason: clickAttempt?.reason || entered.reason || "submit did not queue a visible Midjourney job",
      method: "keyboard",
      debug: clickAttempt?.debug,
      queued: entered.queued,
      statusTexts: entered.statusTexts,
    };
  }

  async clickAt(x, y) {
    await this.client.send("Input.dispatchMouseEvent", {
      type: "mouseMoved",
      x,
      y,
    });
    await this.client.send("Input.dispatchMouseEvent", {
      type: "mousePressed",
      x,
      y,
      button: "left",
      clickCount: 1,
    });
    await this.client.send("Input.dispatchMouseEvent", {
      type: "mouseReleased",
      x,
      y,
      button: "left",
      clickCount: 1,
    });
  }

  async pressEnter() {
    await this.focusPrompt().catch(() => undefined);
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyDown",
      key: "Enter",
      code: "Enter",
      windowsVirtualKeyCode: 13,
      nativeVirtualKeyCode: 36,
    });
    await this.client.send("Input.dispatchKeyEvent", {
      type: "keyUp",
      key: "Enter",
      code: "Enter",
      windowsVirtualKeyCode: 13,
      nativeVirtualKeyCode: 36,
    });
  }

  async attachReferenceImage(filePath) {
    const absolutePath = filePath.startsWith("/") ? filePath : `${process.cwd()}/${filePath}`;
    await this.ensureImaginePage();
    await this.client.send("Page.enable");
    await this.client.send("DOM.enable");
    await this.clearComposerAttachments();
    const baselineUrls = await this.composerCrefUrls();

    const domUpload = await this.uploadViaFileInputs(absolutePath);
    const domCrefUrl = await this.waitForFreshCrefUrl(baselineUrls, 8000);
    if (domCrefUrl) {
      return { ok: true, path: absolutePath, crefUrl: domCrefUrl, ...domUpload, source: "dom-input", baselineUrls };
    }

    const chooserPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("file chooser timeout")), 15000);
      const handler = (event) => {
        const message = JSON.parse(String(event.data));
        if (message.method !== "Page.fileChooserOpened") return;
        clearTimeout(timeout);
        this.client.socket.removeEventListener("message", handler);
        resolve(message.params);
      };
      this.client.socket.addEventListener("message", handler);
    });

    await this.client.send("Page.setInterceptFileChooserDialog", { enabled: true });
    const revealed = await this.revealImageUploadControl();

    try {
      await chooserPromise;
      await this.client.send("Page.handleFileChooser", {
        action: "accept",
        files: [absolutePath],
      });
      await this.client.send("Page.setInterceptFileChooserDialog", { enabled: false });
      const crefUrl = await this.waitForFreshCrefUrl(baselineUrls, 10000);
      if (crefUrl) {
        return { ok: true, path: absolutePath, revealed, crefUrl, source: "file-chooser", baselineUrls };
      }
      return { ok: false, reason: "file chooser accepted but no fresh --cref url appeared", revealed, baselineUrls };
    } catch (error) {
      const fallback = await this.uploadViaFileInputs(absolutePath);
      await this.client.send("Page.setInterceptFileChooserDialog", { enabled: false });
      const fallbackCrefUrl = await this.waitForFreshCrefUrl(baselineUrls, 8000);
      if (fallbackCrefUrl) {
        return { ok: true, path: absolutePath, revealed, crefUrl: fallbackCrefUrl, ...fallback, fallback: "dom-input", baselineUrls };
      }
      return { ok: false, reason: error.message || "file chooser failed", revealed, ...fallback, baselineUrls };
    }
  }

  async composerCrefUrls() {
    return await this.evaluate(`
      (() => {
        ${findPromptBoxSource({ assign: true })}
        const promptBox = window.__actionFindPromptBox?.();
        const promptRect = promptBox?.getBoundingClientRect?.() ?? null;
        const urls = new Set();
        const add = (value) => {
          if (!value || !/cdn\\.midjourney\\.com/i.test(value) || /\\/video\\//i.test(value)) return;
          for (const match of String(value).matchAll(/https?:\\/\\/cdn\\.midjourney\\.com\\/[^\\s"'<>]+/gi)) {
            const normalized = match[0].split("?")[0];
            if (!/\\/video\\//i.test(normalized)) urls.add(normalized);
          }
        };
        if (promptBox) {
          add(("value" in promptBox) ? promptBox.value : (promptBox.innerText || promptBox.textContent || ""));
        }
        for (const element of document.querySelectorAll("img,source,video,a,button,[role='button'],[data-url],[data-src]")) {
          const rect = element.getBoundingClientRect();
          if (promptRect && Math.abs(rect.y - promptRect.y) > 260) continue;
          add(element.currentSrc || element.src || element.href || element.getAttribute("data-url") || element.getAttribute("data-src"));
          add(element.getAttribute("style"));
        }
        return [...urls];
      })()
    `);
  }

  async waitForFreshCrefUrl(baselineUrls, timeoutMs = 8000) {
    const baseline = new Set((baselineUrls || []).map((url) => url.split("?")[0]));
    const startedAt = Date.now();
    while (Date.now() - startedAt < timeoutMs) {
      const urls = await this.composerCrefUrls();
      const fresh = urls
        .map((url) => normalizeCrefUrl(url))
        .filter(Boolean)
        .find((url) => !baseline.has(url));
      if (fresh) return fresh;
      await sleep(500);
    }
    return null;
  }

  async revealImageUploadControl() {
    return await this.evaluate(`
      (() => {
        ${findPromptBoxSource({ assign: true })}
        function normalize(value) {
          return value.replace(/\\s+/g, " ").trim();
        }
        const promptBox = window.__actionFindPromptBox?.();
        const promptRect = promptBox?.getBoundingClientRect?.() ?? null;
        const clickables = [...document.querySelectorAll("button,[role='button'],label,a")]
          .filter((element) => {
            const rect = element.getBoundingClientRect();
            return rect.width > 12 && rect.height > 12 && rect.width < 240 && rect.height < 80;
          });
        const nearPrompt = clickables.filter((element) => {
          const rect = element.getBoundingClientRect();
          if (!promptRect) return rect.bottom > window.innerHeight * 0.72;
          return Math.abs(rect.y - promptRect.y) < 120
            && rect.x >= promptRect.x - 200
            && rect.x <= promptRect.right + 420;
        });
        const imageButton = nearPrompt.find((element) => {
          const text = [
            element.getAttribute("aria-label"),
            element.innerText,
            element.textContent,
          ].filter(Boolean).join(" ").trim().toLowerCase();
          return /^add images?$/i.test(text) || /^upload$/i.test(text) || /^image$/i.test(text) || text === "+";
        }) || clickables.find((element) => /^add images?$/i.test(normalize(element.getAttribute("aria-label") || element.innerText || "")));
        if (imageButton) imageButton.click();
        return {
          clicked: Boolean(imageButton),
          label: imageButton?.innerText || imageButton?.getAttribute("aria-label") || null,
        };
      })()
    `);
  }

  async uploadViaFileInputs(absolutePath) {
    await this.revealImageUploadControl();
    await sleep(400);
    const node = await this.client.send("DOM.getDocument", { depth: -1, pierce: true });
    const query = await this.client.send("DOM.querySelectorAll", {
      nodeId: node.root.nodeId,
      selector: "input[type='file']",
    });
    const nodeIds = query.nodeIds ?? [];
    for (const nodeId of nodeIds) {
      await this.client.send("DOM.setFileInputFiles", { files: [absolutePath], nodeId });
    }
    if (nodeIds.length) {
      await sleep(2500);
      return { inputs: nodeIds.length };
    }
    return { inputs: 0 };
  }

  async evaluate(expression) {
    const response = await this.client.send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
    });
    if (response.exceptionDetails) {
      const details = response.exceptionDetails;
      throw new Error(
        details.exception?.description || details.text || JSON.stringify(details),
      );
    }
    return response.result?.value;
  }
}

class CDPClient {
  static async connect(url) {
    const socket = new WebSocket(url);
    const client = new CDPClient(socket);
    await new Promise((resolve, reject) => {
      socket.addEventListener("open", resolve, { once: true });
      socket.addEventListener("error", reject, { once: true });
    });
    return client;
  }

  constructor(socket) {
    this.socket = socket;
    this.nextId = 1;
    this.pending = new Map();
    socket.addEventListener("message", (event) => {
      const message = JSON.parse(String(event.data));
      const pending = this.pending.get(message.id);
      if (!pending) {
        return;
      }
      this.pending.delete(message.id);
      if (message.error) {
        pending.reject(new Error(message.error.message));
      } else {
        pending.resolve(message.result || {});
      }
    });
  }

  send(method, params = {}) {
    const id = this.nextId++;
    this.socket.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
  }

  close() {
    this.socket.close();
  }
}

function harvestExpression() {
  return `
    (() => {
      function isVisible(element) {
        const rect = element.getBoundingClientRect();
        const style = getComputedStyle(element);
        return rect.width > 24 && rect.height > 24
          && style.visibility !== "hidden"
          && style.display !== "none";
      }
      const results = [...document.querySelectorAll("a[href*='/jobs/']")]
        .filter(isVisible)
        .map((link) => {
          const rect = link.getBoundingClientRect();
          const image = link.querySelector("img");
          return {
            href: link.href,
            imageUrl: image?.currentSrc || image?.src || null,
            text: (link.innerText || link.textContent || "").trim().slice(0, 240),
            rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
          };
        })
        .filter((result) => result.imageUrl && result.rect.width > 48 && result.rect.height > 48);
      const failedJobs = [];
      const seenFailures = new Set();
      function recordFailure(jobId, reason, rect) {
        if (!jobId || seenFailures.has(jobId)) return;
        seenFailures.add(jobId);
        failedJobs.push({
          jobId,
          reason: reason.replace(/\\s+/g, " ").slice(0, 240),
          rect: rect || { x: 0, y: 0, width: 0, height: 0 },
        });
      }
      for (const element of document.querySelectorAll("body *")) {
        if (!isVisible(element)) continue;
        const text = (element.innerText || element.textContent || "").trim();
        if (!/creation failed|not completed|generation failed|job failed/i.test(text)) continue;
        const jobId = text.match(/job\\s+([0-9a-f-]{36})/i)?.[1]
          || text.match(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i)?.[1];
        if (!jobId) continue;
        const rect = element.getBoundingClientRect();
        recordFailure(jobId, text, { x: rect.x, y: rect.y, width: rect.width, height: rect.height });
      }
      const bodyText = document.body?.innerText || "";
      for (const match of bodyText.matchAll(/creation failed[\\s\\S]{0,120}?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/gi)) {
        recordFailure(match[1], match[0]);
      }
      for (const match of bodyText.matchAll(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\\s+not completed/gi)) {
        recordFailure(match[1], "Job " + match[1] + " not completed");
      }
      const jobCards = [];
      const tilesByJob = new Map();
      for (const result of results) {
        const id = result.href.match(/jobs\\/([^?]+)/)?.[1];
        if (!id) continue;
        if (!tilesByJob.has(id)) tilesByJob.set(id, []);
        tilesByJob.get(id).push(result);
      }
      for (const [id, tiles] of tilesByJob) {
        const link = [...document.querySelectorAll("a[href*='/jobs/" + id + "']")].find(isVisible);
        let prompt = "";
        let node = link;
        for (let depth = 0; depth < 10 && node; depth += 1) {
          node = node.parentElement;
          if (!node) break;
          const candidates = [...node.querySelectorAll("p, span, div, button")]
            .map((element) => (element.innerText || element.textContent || "").trim())
            .filter((text) =>
              text.length > 50
              && text.length < 900
              && !/^(Rerun|Trash|Use |More|Style|profile|raw|hd|Creation failed|--|\\+ use|Midjourney|Explore|Create)/i.test(text)
              && (/pixel|four|panel|arranged|explorer|logo|bust|silhouette|app icon|flat vector|minimal flat|dovetail|anvil|midjourney/i.test(text)),
            );
          if (candidates.length) {
            prompt = candidates.sort((a, b) => b.length - a.length)[0];
            break;
          }
        }
        jobCards.push({
          id,
          prompt,
          tileCount: tiles.length,
          rect: tiles[0]?.rect ?? { x: 0, y: 0, width: 0, height: 0 },
        });
      }
      return {
        url: location.href,
        title: document.title,
        results,
        jobCards,
        failedJobs,
        statusTexts: [...new Set(
          [...document.querySelectorAll("body *")]
            .filter(isVisible)
            .map((element) => (element.innerText || element.textContent || "").trim())
            .filter((text) => /starting|submitting|waiting|\d+%\s*complete|relax|fast|draft|creation failed|not completed/i.test(text))
        )].slice(0, 12),
      };
    })()
  `;
}

function promptCorruptionReason(actual, expected) {
  const actualCore = actual.replace(/\s--[a-z]+(?:\s+[^\s]+)?/gi, "").trim();
  const expectedCore = expected.replace(/\s--[a-z]+(?:\s+[^\s]+)?/gi, "").trim();
  if (!actualCore || !expectedCore) return null;

  if (actualCore.length > expectedCore.length * 1.12 + 24) {
    return "prompt length exceeds expected range";
  }

  const tripleLetters = actualCore.match(/\b[a-z]*([a-z])\1\1[a-z]*\b/gi) ?? [];
  const suspiciousRepeats = tripleLetters.filter((word) => word.length >= 6);
  if (suspiciousRepeats.length >= 2) {
    return `repeated-letter gibberish (${suspiciousRepeats.slice(0, 2).join(", ")})`;
  }

  const expectedWords = [...expectedCore.toLowerCase().matchAll(/\b[a-z]{4,}\b/g)].map((match) => match[0]);
  const actualLower = actualCore.toLowerCase();
  let hits = 0;
  let lastIndex = -1;
  for (const word of expectedWords) {
    const index = actualLower.indexOf(word, lastIndex + 1);
    if (index === -1) continue;
    hits += 1;
    lastIndex = index;
  }
  const requiredHits = Math.max(4, Math.ceil(expectedWords.length * 0.45));
  if (hits < requiredHits) {
    return `too few expected words preserved (${hits}/${requiredHits})`;
  }

  if (/reference image[a-z]/i.test(actualCore)) return "merged reference-image fragment";
  if (/exact same charact[^ ]{0,8}[^a-z]/i.test(actualCore)) return "merged character fragment";
  if (/pixel art[^ ]{0,8}depict/i.test(actualCore)) return "merged pixel-art fragment";
  if (/midjourney/i.test(actualCore) && !/midjourney/i.test(expectedCore)) return "midjourney UI text leaked into prompt";
  if (/poinsettia|papriest|popoiness|hoorinivontall|meafferrencee|onimagee|charaacteristix/i.test(actualCore)) {
    return "nonsense tokens";
  }

  return null;
}

function extractCrefUrls(text) {
  return [...text.matchAll(/https?:\/\/cdn\.midjourney\.com\/[^\s)]+/gi)]
    .map((match) => match[0])
    .filter((url) => !/\/video\//i.test(url));
}

function normalizeCrefUrl(url) {
  if (!url || !/cdn\.midjourney\.com/i.test(url) || /\/video\//i.test(url)) return null;
  return url.split("?")[0];
}

function promptNeedleFrom(prompt) {
  const species = prompt.match(/\b(polar bear|brown bear|sea otter|red panda|magical girl|sword student|mecha pilot|hamster|giraffe|crocodile|alligator|elephant|rabbit|terrier|owl|fox|panda|otter|lion|tiger|wolf|deer|moose|badger|penguin|raccoon|hedgehog|capybara|eagle|frog|turtle|zebra|koala|flamingo|goat|schoolgirl|rogue|elf|robot|scout|cartographer|researcher|deckhand|guide)\b/i);
  if (species) return species[1].toLowerCase();
  const featuring = prompt.match(/featuring (?:a |an )?([^,.]{8,48})/i);
  return featuring?.[1]?.trim().toLowerCase() ?? "";
}

function sanitizePrompt(prompt) {
  const noTerms = new Set();
  for (const match of prompt.matchAll(/\s--no\s+([^]+?)(?=\s--|$)/gi)) {
    for (const term of match[1].split(",")) {
      const normalized = term.trim();
      if (normalized && normalized !== "profile") noTerms.add(normalized);
    }
  }
  const arMatch = prompt.match(/\s--ar\s+([\d:]+)/i);
  let cleaned = prompt
    .replace(/\s--no\s+[^]+?(?=\s--|$)/gi, "")
    .replace(/\s--profile\s+\S+(?:\s+\S+)*/gi, "")
    .replace(/\s--cref\s+\S+/gi, "")
    .replace(/\s--cw\s+\d+/gi, "")
    .replace(/\s--ar\s+[\d:]+/gi, "")
    .replace(/\s--raw\b/gi, "")
    .replace(/\s--hd\b/gi, "")
    .replace(/\s--stylize\s+\d+/gi, "")
    .replace(/\s{2,}/g, " ")
    .trim();
  if (noTerms.size === 0) {
    noTerms.add("cat");
    noTerms.add("logo");
    noTerms.add("text");
    noTerms.add("watermark");
  }
  const arClause = arMatch ? ` --ar ${arMatch[1]}` : "";
  const noClause = `--no ${[...noTerms].join(", ")}`;
  return `${cleaned}${arClause} ${noClause}`.replace(/\s{2,}/g, " ").trim();
}

function jobCardFor(harvest, jobId) {
  return harvest.jobCards?.find((card) => card.id === jobId || jobId.startsWith(card.id) || card.id?.startsWith(jobId));
}

function jobMatchesNeedle(harvest, jobId, needle) {
  if (!needle) return true;
  const card = jobCardFor(harvest, jobId);
  const prompt = (card?.prompt || "").toLowerCase();
  if (!prompt) return false;
  const normalizedNeedle = needle.toLowerCase();
  const matched = prompt.includes(normalizedNeedle)
    || normalizedNeedle.split(/\s+/).filter((token) => token.length > 3 && !/^\d+$/.test(token))
      .every((token) => prompt.includes(token));
  if (!matched) return false;
  if (/striped cat|steampunk aviator/.test(prompt) && !/\bcat\b/.test(needle)) return false;
  return true;
}

function pickCompleteJob(grouped, harvest, options) {
  const { minFresh, needle, minElapsedMs, startedAt } = options;
  if (Date.now() - startedAt < minElapsedMs) return null;
  const ranked = [...grouped.entries()]
    .filter(([, items]) => items.length >= minFresh)
    .sort((left, right) => right[1][0].rect.y - left[1][0].rect.y);
  for (const [jobId, items] of ranked) {
    if (!jobMatchesNeedle(harvest, jobId, needle)) continue;
    const card = jobCardFor(harvest, jobId);
    return { jobId, items, prompt: card?.prompt ?? "" };
  }
  return null;
}

function pickFreshFailure(failedJobs, baselineJobs, expectedPromptSubstring) {
  if (!Array.isArray(failedJobs) || failedJobs.length === 0) {
    return null;
  }
  const needle = expectedPromptSubstring?.toLowerCase();
  const sorted = [...failedJobs].sort((left, right) => right.rect.y - left.rect.y);
  return sorted.find((entry) => {
    if (!entry.jobId || baselineJobs.has(entry.jobId)) return false;
    if (!needle) return true;
    return (entry.reason || "").toLowerCase().includes(needle);
  }) ?? null;
}

function pageStatusExpression() {
  return `
    (() => {
      ${findPromptBoxSource({ assign: true })}
      const text = document.body?.innerText || "";
      const promptBox = window.__actionFindPromptBox();
      const images = [...document.images]
        .map((image) => image.currentSrc || image.src || "")
        .filter((src) => /midjourney|cdn\\.discordapp|cdn\\.midjourney/i.test(src));
      const buttons = [...document.querySelectorAll("button,[role='button'],a")]
        .map((element) => (element.innerText || element.getAttribute("aria-label") || "").trim())
        .filter(Boolean)
        .slice(0, 30);
      return {
        url: location.href,
        title: document.title,
        promptReady: Boolean(promptBox),
        promptText: promptBox ? readText(promptBox) : "",
        imageCount: images.length,
        resultLikelyReady: images.length > 0 || /upscale|vary|rerun|download/i.test(text),
        needsLogin: /auth\\/signin|discord\\.com\\/oauth2|log in|sign up|authorize/i.test(location.href + "\\n" + text),
        buttons,
        textSample: text.replace(/\\s+/g, " ").slice(0, 500),
      };

      function readText(element) {
        if ("value" in element) return element.value || "";
        return element.innerText || element.textContent || "";
      }
    })()
  `;
}

function findPromptBoxSource(options = {}) {
  const body = `
    function isVisible(element) {
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return rect.width > 80
        && rect.height > 18
        && style.visibility !== "hidden"
        && style.display !== "none";
    }
    function score(element) {
      const rect = element.getBoundingClientRect();
      const text = [
        element.getAttribute("aria-label"),
        element.getAttribute("placeholder"),
        element.getAttribute("data-placeholder"),
        element.innerText,
      ].filter(Boolean).join(" ").toLowerCase();
      let value = 0;
      if (/imagine|prompt|describe|what/.test(text)) value += 10;
      if (element.matches("textarea,[contenteditable='true'],[role='textbox']")) value += 6;
      if (element.matches("input")) value += 2;
      if (rect.top < 140) value += 12;
      if (rect.bottom > window.innerHeight * 0.45) value += 2;
      return value;
    }
    const candidates = [...document.querySelectorAll("textarea,[contenteditable='true'],[role='textbox'],input[type='text'],input:not([type])")]
      .filter(isVisible)
      .sort((a, b) => score(b) - score(a));
    return candidates[0] || null;
  `;

  if (options.assign) {
    return `
      window.__actionFindPromptBox = function __actionFindPromptBox() {
        ${body}
      };
    `;
  }

  return `function () { ${body} }`;
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--debug-port") {
      parsed.debugPort = values[++index];
    } else if (value === "--url") {
      parsed.url = values[++index];
    } else if (value === "--prompt") {
      parsed.prompt = values[++index];
    } else if (value === "--timeout-ms") {
      parsed.timeoutMs = values[++index];
    } else if (value === "--min-image-count") {
      parsed.minImageCount = values[++index];
    } else if (value === "--baseline-hrefs") {
      parsed.baselineHrefs = values[++index];
    } else if (value === "--baseline-file") {
      parsed.baselineFile = values[++index];
    } else if (value === "--min-fresh") {
      parsed.minFresh = values[++index];
    } else if (value === "--reference-file") {
      parsed.referenceFile = values[++index];
    } else if (value === "--reference-url") {
      parsed.referenceUrl = values[++index];
    } else if (value === "--expected-prompt-substring") {
      parsed.expectedPromptSubstring = values[++index];
    } else if (value === "--min-wait-ms") {
      parsed.minWaitMs = values[++index];
    } else if (value === "--started-at-ms") {
      parsed.startedAtMs = values[++index];
    } else if (value === "--job-id") {
      parsed.jobId = values[++index];
    } else if (value === "--job-index") {
      parsed.jobIndex = values[++index];
    } else if (value === "--motion-prompt") {
      parsed.motionPrompt = values[++index];
    } else if (value === "--background") {
      parsed.background = true;
    } else if (value === "--skip-job-check") {
      parsed.skipJobCheck = true;
    } else if (value === "--max-scrolls") {
      parsed.maxScrolls = values[++index];
    }
  }
  return parsed;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
