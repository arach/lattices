#!/usr/bin/env bun
/**
 * Hands-off worker — long-running process that handles both inference and TTS.
 *
 * Reads newline-delimited JSON commands from stdin, writes JSON responses to stdout.
 * Keeps TTS and inference warm — no cold starts.
 *
 * Commands:
 *   {"cmd":"infer","transcript":"...","snapshot":{...},"history":[...]}
 *   {"cmd":"speak","text":"..."}
 *   {"cmd":"ack","text":"..."}   (speak + don't wait for completion)
 *   {"cmd":"ping"}
 *
 * Responses:
 *   {"ok":true,"data":{...}}
 *   {"ok":false,"error":"..."}
 */

import {
  assistantPromptPath,
  buildAssistantContextMessage,
  buildAssistantSystemPrompt,
  normalizeAssistantPlan,
  tryLocalAssistantPlan,
} from "./assistant-intelligence.ts";
import { infer, resolveVoiceInferenceOptions } from "./infer.ts";

const INFER_TIMEOUT_MS = 15_000;
const voiceInference = resolveVoiceInferenceOptions();

/** Call infer and parse JSON if possible, otherwise treat as spoken-only response */
async function inferSmart(prompt: string, options: any): Promise<{ data: any; raw: any }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), INFER_TIMEOUT_MS);
  let raw: any;
  try {
    raw = await infer(prompt, { ...options, abortSignal: controller.signal });
  } finally {
    clearTimeout(timer);
  }

  // Try to parse as JSON
  let cleaned = raw.text
    .replace(/```json\s*/g, "")
    .replace(/```\s*/g, "")
    .trim();

  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");

  if (start !== -1 && end !== -1) {
    try {
      const data = JSON.parse(cleaned.slice(start, end + 1));
      return { data, raw };
    } catch {}
  }

  // Not JSON — treat as conversational response (spoken-only, no actions)
  log(`response was plain text, wrapping as spoken: "${raw.text.slice(0, 80)}"`);
  return {
    data: { actions: [], spoken: raw.text },
    raw,
  };
}
import { readFileSync } from "fs";
import { join } from "path";
import { spawn } from "child_process";
import {
  AVSPEECH_MODEL_ID,
  describeVoxRuntime,
  KOKORO_MODEL_ID,
  KOKORO_VOICE_ID,
  playCachedWav,
  resolveVoxRuntime,
  speakWithVox,
  synthesizeWithVox,
} from "./vox-tts.ts";

// ── TTS via Hudson/Vox (Kokoro) → avspeech → say ───────────────────

let voxTTSDisabledReason: string | null = resolveVoxRuntime() ? null : "Hudson voice runtime unavailable";

function disableVoxTTS(reason: string) {
  if (voxTTSDisabledReason) return;
  voxTTSDisabledReason = reason;
  log(`Hudson TTS disabled for this worker: ${reason}`);
}

/** Last-resort macOS speech when Hudson voice runtime is unavailable. */
async function localSpeak(text: string): Promise<number> {
  const start = performance.now();
  return new Promise((resolve, reject) => {
    const speaker = spawn("/usr/bin/say", ["-r", "210", text], {
      stdio: ["ignore", "ignore", "pipe"],
    });
    let stderr = "";
    speaker.stderr?.on("data", (data: Buffer) => { stderr += data.toString(); });
    speaker.on("close", (code: number | null) => {
      const ms = Math.round(performance.now() - start);
      if (code === 0) resolve(ms);
      else reject(new Error(`macOS speech failed (${code ?? "unknown"}): ${stderr.slice(0, 160)}`));
    });
    speaker.on("error", reject);
  });
}

async function speak(text: string): Promise<number> {
  if (!voxTTSDisabledReason) {
    try {
      const ms = await speakWithVox(text, {
        modelId: KOKORO_MODEL_ID,
        voiceId: KOKORO_VOICE_ID,
      });
      log(`Kokoro spoke "${text.slice(0, 40)}" in ${ms}ms`);
      return ms;
    } catch (error: any) {
      log(`Kokoro TTS unavailable: ${error.message}`);
      disableVoxTTS(error.message);
    }
  }

  if (resolveVoxRuntime()) {
    try {
      const ms = await speakWithVox(text, { modelId: AVSPEECH_MODEL_ID });
      log(`avspeech spoke "${text.slice(0, 40)}" in ${ms}ms`);
      return ms;
    } catch (error: any) {
      log(`avspeech fallback failed: ${error.message}`);
    }
  }

  return localSpeak(text);
}

// ── Pre-cached ack sounds (no API call needed) ────────────────────

// Ack phrases — played immediately when user stops talking
const ACK_PHRASES = [
  "Got it.",
  "Heard you.",
  "On it.",
  "Yep.",
  "Cool.",
  "Sure.",
  "Okay.",
  "One sec.",
];

// Confirmation phrases — played after executing known actions
const CONFIRM_PHRASES = [
  "Tiled.",
  "Focused.",
  "Done.",
  "Maximized.",
  "Split.",
  "Switched.",
  "Distributed.",
  "Restored.",
  "Searching.",
];

const ackCacheDir = join(process.env.HOME || "", ".lattices", "tts-cache");
const ackCache = new Map<string, string>(); // phrase → file path

async function ensureVoiceCache() {
  const { mkdirSync, existsSync, writeFileSync } = await import("fs");
  mkdirSync(ackCacheDir, { recursive: true });

  const allPhrases = [...ACK_PHRASES, ...CONFIRM_PHRASES];
  let cached = 0;
  let generated = 0;

  for (const phrase of allPhrases) {
    const safeName = phrase.replace(/[^a-z]/gi, "_").toLowerCase();
    const filePath = join(ackCacheDir, `kokoro_${safeName}.wav`);
    const legacyPath = join(ackCacheDir, `voice_${safeName}.pcm`);

    if (existsSync(filePath)) {
      ackCache.set(phrase, filePath);
      cached++;
      continue;
    }

    if (existsSync(legacyPath)) {
      try {
        const { unlinkSync } = await import("fs");
        unlinkSync(legacyPath);
      } catch {}
    }

    try {
      const { wav } = await synthesizeWithVox(phrase, {
        modelId: KOKORO_MODEL_ID,
        voiceId: KOKORO_VOICE_ID,
      });
      writeFileSync(filePath, wav);
      ackCache.set(phrase, filePath);
      generated++;
      log(`cached: "${phrase}"`);
    } catch (e: any) {
      log(`cache failed for "${phrase}": ${e.message}`);
      if (voxTTSDisabledReason) break;
    }
  }
  log(`voice cache: ${cached} hit, ${generated} generated, ${allPhrases.length} total`);
}

/** Play a pre-cached audio file. Near-instant — no API call. */
async function playCached(phrase: string): Promise<number> {
  const start = performance.now();
  const filePath = ackCache.get(phrase);

  if (!filePath) {
    log(`playCached: cache miss for "${phrase}", using live speech`);
    return speak(phrase);
  }

  log(`playing cached: "${phrase}"`);
  try {
    const ms = await playCachedWav(filePath);
    log(`played "${phrase}" in ${ms}ms`);
    return ms;
  } catch (err: any) {
    log(`cached playback failed: ${err.message}`);
    return speak(phrase);
  }
}

/** Play a random ack phrase from cache. */
function playAck(): Promise<number> {
  const phrase = ACK_PHRASES[Math.floor(Math.random() * ACK_PHRASES.length)];
  return playCached(phrase);
}

/** Play the right confirmation for an action. */
function playConfirm(intent: string): Promise<number> {
  const map: Record<string, string> = {
    tile_window: "Tiled.",
    focus: "Focused.",
    distribute: "Distributed.",
    search: "Searching.",
    switch_layer: "Switched.",
    create_layer: "Done.",
  };
  return playCached(map[intent] ?? "Done.");
}

// Warm up cache on startup
ensureVoiceCache().then(() => log("voice cache ready"));

log(`worker started, TTS=${voxTTSDisabledReason ? "macOS say fallback" : `Hudson Kokoro (${KOKORO_VOICE_ID})`} @ ${describeVoxRuntime()}`);

// ── Load system prompt once ────────────────────────────────────────

const systemPrompt = buildAssistantSystemPrompt();
log("system prompt loaded");
log(`voice inference: ${voiceInference.provider}/${voiceInference.model}`);

// ── Auto-restart on file changes ───────────────────────────────────

const watchFiles = [
  assistantPromptPath,
  join(import.meta.dir, "assistant-intelligence.ts"),
  join(import.meta.dir, "..", ".env"),
  join(import.meta.dir, "..", ".env.local"),
  import.meta.path, // this script itself
];

for (const f of watchFiles) {
  try {
    const { watch } = await import("fs");
    let debounce: ReturnType<typeof setTimeout> | null = null;
    watch(f, () => {
      if (debounce) return;
      debounce = setTimeout(() => {
        log(`file changed: ${f.split("/").pop()} — exiting for restart`);
        process.exit(0); // Swift auto-restarts in 2s
      }, 500);
    });
    log(`watching: ${f.split("/").pop()}`);
  } catch {}
}

// ── Command loop ───────────────────────────────────────────────────

const decoder = new TextDecoder();
const reader = Bun.stdin.stream().getReader();
let buffer = "";

async function processLine(line: string) {
  const trimmed = line.trim();
  if (!trimmed) return;

  let cmd: any;
  try {
    cmd = JSON.parse(trimmed);
  } catch {
    respond({ ok: false, error: "invalid JSON" });
    return;
  }

  switch (cmd.cmd) {
    case "ping":
      respond({ ok: true, data: { pong: true } });
      break;

    case "speak":
      try {
        const ms = await speak(cmd.text);
        log(`spoke "${cmd.text.slice(0, 40)}" in ${ms}ms`);
        respond({ ok: true, data: { durationMs: ms } });
      } catch (err: any) {
        log(`TTS error: ${err.message}`);
        respond({ ok: false, error: err.message });
      }
      break;

    case "ack":
      // Fire and forget — respond immediately, speak in background
      respond({ ok: true, data: { queued: true } });
      speak(cmd.text).catch((e) => log(`ack TTS error: ${e.message}`));
      break;

    case "play_cached":
      respond({ ok: true, data: { queued: true, cached: true } });
      playCached(cmd.text).catch((e) => log(`play_cached error: ${e.message}`));
      break;

    case "infer":
      try {
        const localPlan = tryLocalAssistantPlan(cmd.transcript, cmd.snapshot ?? {});
        if (localPlan) {
          respond({ ok: true, data: localPlan });
          break;
        }

        const userMessage = buildAssistantContextMessage(cmd.transcript, cmd.snapshot ?? {});

        const messages = (cmd.history ?? []).map((h: any) => ({
          role: h.role as "user" | "assistant",
          content: h.content,
        }));

        const { data, raw } = await inferSmart(userMessage, {
          provider: voiceInference.provider,
          model: voiceInference.model,
          system: systemPrompt,
          messages,
          temperature: 0.2,
          maxTokens: 512,
          tag: "hands-off",
        });

        const plan = normalizeAssistantPlan(data, cmd.transcript);
        respond({
          ok: true,
          data: {
            ...plan,
            _meta: {
              ...plan._meta,
              provider: raw.provider,
              model: raw.model,
              durationMs: raw.durationMs,
              tokens: raw.usage?.totalTokens,
            },
          },
        });
      } catch (err: any) {
        respond({
          ok: false,
          error: err.message,
          data: {
            actions: [],
            spoken: "Sorry, I had trouble processing that.",
          },
        });
      }
      break;

    case "turn": {
      const turnStart = performance.now();
      const transcript = cmd.transcript;
      const snap = cmd.snapshot ?? {};
      const history = cmd.history ?? [];

      log(`⏱ turn start: "${transcript.slice(0, 50)}"`);
      progress("acknowledging", turnStart);

      const ackPromise = playAck().catch((e) => log(`ack error: ${e.message}`));

      const messages = history.map((h: any) => ({
        role: h.role as "user" | "assistant",
        content: typeof h.content === "string" ? h.content : JSON.stringify(h.content),
      })).filter((m: any) => m.content && m.content.length > 0);

      let inferResult: any = null;
      const localPlan = tryLocalAssistantPlan(transcript, snap);
      if (localPlan) {
        inferResult = { ...localPlan, _meta: turnMeta("quick", "quick", true) };
        log("local planner matched — quick path");
      } else {
        progress("planning", turnStart, "standard");
        const userMessage = buildAssistantContextMessage(transcript, snap);
        try {
          const { data, raw } = await inferSmart(userMessage, {
            provider: voiceInference.provider,
            model: voiceInference.model,
            system: systemPrompt,
            messages,
            temperature: 0.2,
            maxTokens: 512,
            tag: "hands-off",
          });
          const plan = normalizeAssistantPlan(data, transcript);
          const hasActions = Array.isArray(plan.actions) && plan.actions.length > 0;
          const turnKind = hasActions ? "standard" : "conversation";
          inferResult = {
            ...plan,
            _meta: {
              ...plan._meta,
              ...turnMeta("standard", turnKind, false),
              provider: raw.provider,
              model: raw.model,
              durationMs: raw.durationMs,
              tokens: raw.usage?.totalTokens,
            },
          };
          log(`⏱ inference done in ${raw.durationMs}ms`);
        } catch (err: any) {
          log(`⏱ inference error: ${err.message}`);
          inferResult = {
            actions: [],
            spoken: "Sorry, I had trouble with that.",
            _meta: { ...turnMeta("standard", "conversation", false), error: err.message },
          };
        }
      }

      const hasActions = Array.isArray(inferResult.actions) && inferResult.actions.length > 0;
      const spokenText = inferResult.spoken;
      const isQuick = inferResult._meta?.path === "quick" && hasActions;

      if (isQuick) {
        await ackPromise;
        progress("executing", turnStart, "quick");
        const turnMs = Math.round(performance.now() - turnStart);
        log(`⏱ quick turn response at ${turnMs}ms`);
        respond({ ok: true, data: inferResult, turnMs });
        progress("confirming", turnStart, "quick");
        const intent = inferResult.actions?.[0]?.intent as string | undefined;
        playConfirm(intent ?? "done").catch(() => {});
        break;
      }

      await ackPromise;

      if (hasActions && spokenText) {
        progress("narrating", turnStart, "standard");
        log(`⏱ narrating: "${spokenText.slice(0, 50)}"`);
        await speak(spokenText).catch((e) => log(`narrate error: ${e.message}`));
        progress("executing", turnStart, "standard");
        const turnMs = Math.round(performance.now() - turnStart);
        log(`⏱ turn response at ${turnMs}ms — actions sent after narration`);
        respond({ ok: true, data: inferResult, turnMs });
        progress("confirming", turnStart, "standard");
        await playCached("Done.").catch(() => {});
      } else if (spokenText) {
        progress("narrating", turnStart, "conversation");
        await speak(spokenText).catch((e) => log(`speak error: ${e.message}`));
        const turnMs = Math.round(performance.now() - turnStart);
        respond({ ok: true, data: inferResult, turnMs });
      } else {
        const turnMs = Math.round(performance.now() - turnStart);
        respond({ ok: true, data: inferResult, turnMs });
      }

      const totalMs = Math.round(performance.now() - turnStart);
      log(`⏱ turn complete: ${totalMs}ms total`);
      break;
    }

    default:
      respond({ ok: false, error: `unknown command: ${cmd.cmd}` });
  }
}

// Read stdin line by line
(async () => {
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";

    for (const line of lines) {
      await processLine(line);
    }
  }
})();

function respond(obj: any) {
  console.log(JSON.stringify(obj));
}

function progress(stage: string, turnStart: number, turnKind?: "quick" | "standard" | "conversation") {
  respond({
    ok: true,
    progress: stage,
    turnKind,
    turnMs: Math.round(performance.now() - turnStart),
  });
}

function turnMeta(path: "quick" | "standard", turnKind: "quick" | "standard" | "conversation", localMatch = false) {
  return { path, turnKind, localMatch };
}


function log(msg: string) {
  const ts = new Date().toISOString().slice(11, 23);
  console.error(`[${ts}] handsoff-worker: ${msg}`);
}
