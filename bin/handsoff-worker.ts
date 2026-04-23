#!/usr/bin/env bun
/**
 * Hands-off worker — long-running process that handles both inference and TTS.
 *
 * Reads newline-delimited JSON commands from stdin, writes JSON responses to stdout.
 * Keeps SpeakEasy and inference warm — no cold starts.
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
import { infer } from "../lib/infer.ts";

const INFER_TIMEOUT_MS = 15_000;

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

// ── Streaming TTS via OpenAI API → ffplay ──────────────────────────

const OPENAI_TTS_URL = "https://api.openai.com/v1/audio/speech";
const ttsConfig = loadTTSConfig();

function loadTTSConfig() {
  // Load API key from speakeasy config or env
  let apiKey = process.env.OPENAI_API_KEY || "";
  let voice = "nova";

  try {
    const cfg = JSON.parse(
      readFileSync(join(process.env.HOME || "", ".config/speakeasy/settings.json"), "utf-8")
    );
    if (!apiKey && cfg.providers?.openai?.apiKey) apiKey = cfg.providers.openai.apiKey;
    if (cfg.providers?.openai?.voice) voice = cfg.providers.openai.voice;
  } catch {}

  return { apiKey, voice };
}

/** Stream TTS: fetch audio from OpenAI and pipe directly to ffplay. Playback starts immediately. */
async function streamSpeak(text: string): Promise<number> {
  const start = performance.now();

  const res = await fetch(OPENAI_TTS_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${ttsConfig.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "tts-1",
      voice: ttsConfig.voice,
      input: text,
      response_format: "pcm",
      speed: 1.1,
    }),
  });

  if (!res.ok) {
    throw new Error(`OpenAI TTS error: ${res.status} ${res.statusText}`);
  }

  const ttfb = Math.round(performance.now() - start);
  log(`TTS first byte in ${ttfb}ms`);

  // Pipe response body directly to ffplay — playback starts as chunks arrive
  return new Promise((resolve, reject) => {
    const player = spawn("ffplay", [
      "-nodisp",      // no video window
      "-autoexit",    // quit when done
      "-loglevel", "quiet",
      "-f", "s16le",   // PCM signed 16-bit little-endian
      "-ar", "24000",  // OpenAI TTS outputs 24kHz
      "-ch_layout", "mono",
      "-",            // read from stdin
    ], { stdio: ["pipe", "ignore", "ignore"] });

    const reader = res.body?.getReader();
    if (!reader) {
      reject(new Error("No response body"));
      return;
    }

    // Pump chunks from fetch → ffplay stdin
    (async () => {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        player.stdin.write(value);
      }
      player.stdin.end();
    })().catch(reject);

    player.on("close", () => {
      const ms = Math.round(performance.now() - start);
      resolve(ms);
    });

    player.on("error", reject);
  });
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
    const filePath = join(ackCacheDir, `voice_${safeName}.pcm`);

    if (existsSync(filePath)) {
      ackCache.set(phrase, filePath);
      cached++;
      continue;
    }

    // Generate and cache
    try {
      const res = await fetch(OPENAI_TTS_URL, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${ttsConfig.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "tts-1",
          voice: ttsConfig.voice,
          input: phrase,
          response_format: "pcm",
          speed: 1.1,
        }),
      });

      if (res.ok) {
        const buf = Buffer.from(await res.arrayBuffer());
        writeFileSync(filePath, buf);
        ackCache.set(phrase, filePath);
        generated++;
        log(`cached: "${phrase}"`);
      }
    } catch (e: any) {
      log(`cache failed for "${phrase}": ${e.message}`);
    }
  }
  log(`voice cache: ${cached} hit, ${generated} generated, ${allPhrases.length} total`);
}

/** Play a pre-cached audio file. Near-instant — no API call. */
async function playCached(phrase: string): Promise<number> {
  const start = performance.now();
  const filePath = ackCache.get(phrase);

  if (!filePath) {
    log(`playCached: cache miss for "${phrase}", falling back to TTS`);
    return streamSpeak(phrase);
  }

  log(`playing cached: "${phrase}"`);
  return new Promise((resolve, reject) => {
    const player = spawn("ffplay", [
      "-nodisp", "-autoexit", "-loglevel", "quiet",
      "-f", "s16le", "-ar", "24000", "-ch_layout", "mono",
      filePath,
    ], { stdio: ["ignore", "ignore", "pipe"] });

    let stderr = "";
    player.stderr?.on("data", (d: Buffer) => { stderr += d.toString(); });

    player.on("close", (code: number) => {
      const ms = Math.round(performance.now() - start);
      if (code !== 0) log(`ffplay error (code ${code}): ${stderr.slice(0, 100)}`);
      else log(`played "${phrase}" in ${ms}ms`);
      resolve(ms);
    });

    player.on("error", (err: Error) => {
      log(`ffplay spawn error: ${err.message}`);
      reject(err);
    });
  });
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

log("worker started, streaming TTS ready");

// ── Load system prompt once ────────────────────────────────────────

const systemPrompt = buildAssistantSystemPrompt();
log("system prompt loaded");

// ── Auto-restart on file changes ───────────────────────────────────

const watchFiles = [
  assistantPromptPath,
  join(import.meta.dir, "assistant-intelligence.ts"),
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
        const ms = await streamSpeak(cmd.text);
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
      streamSpeak(cmd.text).catch((e) => log(`ack TTS error: ${e.message}`));
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
          provider: "xai",
          model: "grok-4.20-beta-0309-non-reasoning",
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
      // Full orchestrated turn — parallel where possible.
      //
      // Timeline:
      //   t=0  ──┬── ack TTS (fire & forget)
      //          └── Groq inference
      //   t=~600ms ─┬── narrate TTS (what we're doing)
      //             └── execute actions (in parallel with narrate)
      //   t=done ── respond with results
      //
      const turnStart = performance.now();
      const transcript = cmd.transcript;
      const snap = cmd.snapshot ?? {};
      const history = cmd.history ?? [];

      log(`⏱ turn start: "${transcript.slice(0, 50)}"`);

      // Fire cached ack sound + inference in PARALLEL
      const ackPromise = playAck().catch((e) => log(`ack error: ${e.message}`));

      const messages = history.map((h: any) => ({
        role: h.role as "user" | "assistant",
        content: typeof h.content === "string" ? h.content : JSON.stringify(h.content),
      })).filter((m: any) => m.content && m.content.length > 0);

      let inferResult: any = null;
      const localPlan = tryLocalAssistantPlan(transcript, snap);
      if (localPlan) {
        inferResult = localPlan;
        log("local planner matched");
      } else {
        const userMessage = buildAssistantContextMessage(transcript, snap);
        try {
          const { data, raw } = await inferSmart(userMessage, {
            provider: "xai",
            model: "grok-4.20-beta-0309-non-reasoning",
            system: systemPrompt,
            messages,
            temperature: 0.2,
            maxTokens: 512,
            tag: "hands-off",
          });
          const plan = normalizeAssistantPlan(data, transcript);
          inferResult = { ...plan, _meta: { ...plan._meta, provider: raw.provider, model: raw.model, durationMs: raw.durationMs, tokens: raw.usage?.totalTokens } };
          log(`⏱ inference done in ${raw.durationMs}ms`);
        } catch (err: any) {
          log(`⏱ inference error: ${err.message}`);
          inferResult = { actions: [], spoken: "Sorry, I had trouble with that.", _meta: { error: err.message } };
        }
      }

      // Wait for ack to finish before narrating (don't overlap speech)
      await ackPromise;

      // Step 2: Narrate + execute in PARALLEL
      const hasActions = Array.isArray(inferResult.actions) && inferResult.actions.length > 0;
      const spokenText = inferResult.spoken;

      if (hasActions && spokenText) {
        // SPEAK FIRST — user must hear what's about to happen before windows move
        log(`⏱ narrating: "${spokenText.slice(0, 50)}"`);
        await streamSpeak(spokenText).catch((e) => log(`narrate error: ${e.message}`));

        // NOW respond with actions — Swift executes after user heard the plan
        const turnMs = Math.round(performance.now() - turnStart);
        log(`⏱ turn response at ${turnMs}ms — actions sent after narration`);
        respond({ ok: true, data: inferResult, turnMs });

        // Confirm
        await playCached("Done.").catch(() => {});
      } else if (spokenText) {
        // Conversation only — speak and respond
        await streamSpeak(spokenText).catch((e) => log(`speak error: ${e.message}`));
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

function log(msg: string) {
  const ts = new Date().toISOString().slice(11, 23);
  console.error(`[${ts}] handsoff-worker: ${msg}`);
}
