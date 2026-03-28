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

import { infer, inferJSON } from "../lib/infer.ts";

/** Call infer and parse JSON if possible, otherwise treat as spoken-only response */
async function inferSmart(prompt: string, options: any): Promise<{ data: any; raw: any }> {
  const raw = await infer(prompt, options);

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
import { join, dirname } from "path";
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

// ── Fast path: local intent matching (no LLM needed) ──────────────

interface FastMatch {
  actions: Array<{ intent: string; slots: Record<string, string> }>;
  confirm: string; // which confirmation to play
}

function tryFastMatch(transcript: string, snapshot: any): FastMatch | null {
  const t = transcript.toLowerCase().trim();
  const activeApps = (snapshot.activeStage ?? []).map((w: any) => ({
    app: w.app as string,
    wid: w.wid as number,
  }));

  // Tile patterns
  const tileMatch = t.match(
    /(?:tile|snap|put|move)\s+(\w+)\s+(?:to\s+)?(?:the\s+)?(left|right|top|bottom|maximize|center|top.?left|top.?right|bottom.?left|bottom.?right|left.?third|center.?third|right.?third)/
  );
  if (tileMatch) {
    const app = tileMatch[1];
    const pos = tileMatch[2].replace(/\s+/g, "-");
    return {
      actions: [{ intent: "tile_window", slots: { app, position: pos } }],
      confirm: "tile_window",
    };
  }

  // Split screen: "split X and Y" or "X left Y right"
  const splitMatch = t.match(/split\s+(\w+)\s+(?:and|&)\s+(\w+)/);
  if (splitMatch) {
    return {
      actions: [
        { intent: "tile_window", slots: { app: splitMatch[1], position: "left" } },
        { intent: "tile_window", slots: { app: splitMatch[2], position: "right" } },
      ],
      confirm: "tile_window",
    };
  }

  // Focus: "focus X" / "focus on X" / "switch to X" / "go to X"
  const focusMatch = t.match(/(?:focus(?:\s+on)?|switch\s+to|go\s+to|show)\s+(?:the\s+)?(?:on\s+)?(\w+)/);
  if (focusMatch && !t.includes("tile") && !t.includes("split")) {
    const app = focusMatch[1];
    if (app && app !== "on" && app !== "the") {
      return {
        actions: [{ intent: "focus", slots: { app } }],
        confirm: "focus",
      };
    }
  }

  // Maximize: "maximize" / "full screen" / "make it big"
  if (/maximize|full\s*screen|make\s+it\s+big/.test(t)) {
    return {
      actions: [{ intent: "tile_window", slots: { position: "maximize" } }],
      confirm: "tile_window",
    };
  }

  // Distribute: "grid" / "mosaic" / "distribute" / "even"
  if (/grid|mosaic|distribute|even\s+(?:out|grid)|arrange/.test(t)) {
    return {
      actions: [{ intent: "distribute", slots: {} }],
      confirm: "distribute",
    };
  }

  // Corners: "quadrants" / "four corners"
  if (/quadrants?|four\s+corners?|corners/.test(t) && activeApps.length >= 4) {
    const positions = ["top-left", "top-right", "bottom-left", "bottom-right"];
    return {
      actions: activeApps.slice(0, 4).map((a: any, i: number) => ({
        intent: "tile_window",
        slots: { app: a.app, position: positions[i] },
      })),
      confirm: "tile_window",
    };
  }

  // Thirds: "thirds"
  if (/thirds/.test(t) && activeApps.length >= 3) {
    const positions = ["left-third", "center-third", "right-third"];
    return {
      actions: activeApps.slice(0, 3).map((a: any, i: number) => ({
        intent: "tile_window",
        slots: { app: a.app, position: positions[i] },
      })),
      confirm: "tile_window",
    };
  }

  return null; // No fast match — fall through to LLM
}

// Warm up cache on startup
ensureVoiceCache().then(() => log("voice cache ready"));

log("worker started, streaming TTS ready");

// ── Load system prompt once ────────────────────────────────────────

const promptDir = join(dirname(import.meta.dir), "docs", "prompts");
let systemPrompt: string;
try {
  systemPrompt = readFileSync(join(promptDir, "hands-off-system.md"), "utf-8")
    .split("\n")
    .filter((l) => !l.startsWith("# "))
    .join("\n")
    .trim();
} catch {
  systemPrompt = "You are a workspace assistant. Respond with JSON: {actions, spoken}.";
}

const intentCatalog = `
tile_window: Tile a window to a screen position
  Slots:
    position (required): Named position or grid:CxR:C,R syntax.
      Halves: left, right, top, bottom
      Quarters (2x2): top-left, top-right, bottom-left, bottom-right
      Thirds (3x1): left-third, center-third, right-third
      Sixths (3x2): top-left-third, top-center-third, top-right-third, bottom-left-third, bottom-center-third, bottom-right-third
      Fourths (4x1): first-fourth, second-fourth, third-fourth, last-fourth
      Eighths (4x2): top-first-fourth, top-second-fourth, top-third-fourth, top-last-fourth, bottom-first-fourth, bottom-second-fourth, bottom-third-fourth, bottom-last-fourth
      Special: maximize (full screen), center (centered floating)
      Grid syntax: grid:CxR:C,R (e.g. grid:5x3:2,1 = center cell of 5x3 grid)
    app (optional): Target app name — match loosely (e.g. "chrome" matches "Google Chrome")
    wid (optional): Target window ID (from snapshot)
    session (optional): Tmux session name
  If no app/wid/session given, tiles the frontmost window.
  "quarter" = 2x2 cell (top-left etc.), NOT a 4x1 fourth.
  "top quarter" = top-left or top-right (2x2). "top third" = top-left-third (3x2).

focus: Focus a window, app, or session
  Slots: app, session, or wid (at least one)

distribute: Arrange all visible windows in an even grid. No slots.

search: Search windows by text
  Slots: query (required)

list_windows: List all visible windows. No slots.

switch_layer: Switch to a workspace layer
  Slots: layer (required) — name or index

create_layer: Save current arrangement as a named layer
  Slots: name (required)

TILING PRESETS (use multiple tile_window actions):
  "split screen" → left + right
  "thirds" → left-third, center-third, right-third
  "mosaic"/"grid" → use distribute
  "corners"/"quadrants" → top-left, top-right, bottom-left, bottom-right
  "stack" → top + bottom
  "six-up"/"3 by 2" → 3x2 grid using the sixth positions
  "eight-up"/"4 by 2" → 4x2 grid using the eighth positions
`;

systemPrompt = systemPrompt.replace("{{intent_catalog}}", intentCatalog);
log("system prompt loaded");

// ── Auto-restart on file changes ───────────────────────────────────

const watchFiles = [
  join(promptDir, "hands-off-system.md"),
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

// ── Build context message from snapshot ─────────────────────────────

function buildContextMessage(transcript: string, snap: any): string {
  let msg = `USER: "${transcript}"\n\n`;
  msg += "--- DESKTOP SNAPSHOT ---\n";

  // Screens
  const screens = snap.screens ?? [];
  if (screens.length > 1) {
    msg += `Displays: ${screens.map((s: any) => `${s.width}x${s.height}${s.isMain ? " (main)" : ""}`).join(", ")}\n`;
  } else if (screens.length === 1) {
    msg += `Screen: ${screens[0].width}x${screens[0].height}\n`;
  }

  // Stage Manager
  if (snap.stageManager) {
    msg += `Stage Manager: ON (grouping: ${snap.smGrouping ?? "all-at-once"})\n`;
  }

  // All windows — full inventory, ordered front-to-back (zIndex 0 = frontmost)
  const windows = snap.windows ?? snap.activeStage ?? [];
  const onScreen = windows.filter((w: any) => w.onScreen !== false);
  const offScreen = windows.filter((w: any) => w.onScreen === false);

  msg += `\nVisible windows (${onScreen.length}, front-to-back order):\n`;
  for (const w of onScreen) {
    const flags: string[] = [];
    if (w.zIndex === 0) flags.push("FRONTMOST");
    if (w.session) flags.push(`session:${w.session}`);
    const flagStr = flags.length ? ` [${flags.join(", ")}]` : "";
    msg += `  wid:${w.wid} ${w.app}: "${w.title}" — ${w.frame}${flagStr}\n`;
  }

  if (offScreen.length > 0) {
    // Summarize hidden windows by app instead of listing all
    const hiddenByApp: Record<string, number> = {};
    for (const w of offScreen) {
      const app = w.app;
      hiddenByApp[app] = (hiddenByApp[app] || 0) + 1;
    }
    const summary = Object.entries(hiddenByApp)
      .filter(([app]) => !["WindowManager", "Spotlight", "CursorUIViewService", "AutoFill", "coreautha", "loginwindow", "Open and Save Panel Service"].includes(app))
      .map(([app, count]) => `${app}(${count})`)
      .join(", ");
    if (summary) {
      msg += `\nHidden windows: ${summary}\n`;
    }
  }

  // Terminals — cwd, running commands, claude, tmux
  const terminals = snap.terminals ?? [];
  if (terminals.length > 0) {
    msg += `\nTerminal tabs (${terminals.length}):\n`;
    for (const t of terminals) {
      const flags: string[] = [];
      if (t.hasClaude) flags.push("Claude Code");
      if (t.tmuxSession) flags.push(`tmux:${t.tmuxSession}`);
      if (!t.isActiveTab) flags.push("background tab");
      const flagStr = flags.length ? ` [${flags.join(", ")}]` : "";
      const cwd = t.cwd ? ` cwd:${t.cwd.replace(/^\/Users\/\w+\//, "~/")}` : "";
      const cmds = (t.runningCommands ?? []).map((c: any) => c.command).join(", ");
      const cmdStr = cmds ? ` running:${cmds}` : "";
      msg += `  ${t.displayName}${cwd}${cmdStr}${flagStr}`;
      if (t.windowId) msg += ` (wid:${t.windowId})`;
      msg += "\n";
    }
  }

  // Tmux sessions
  const tmux = snap.tmuxSessions ?? [];
  if (tmux.length > 0) {
    msg += `\nTmux sessions: ${tmux.map((s: any) => `${s.name} (${s.windows} windows${s.attached ? ", attached" : ""})`).join(", ")}\n`;
  }

  // Layer
  if (snap.currentLayer) {
    msg += `\nCurrent layer: ${snap.currentLayer.name} (index: ${snap.currentLayer.index})\n`;
  }

  msg += "--- END SNAPSHOT ---\n";
  return msg;
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
        const userMessage = buildContextMessage(cmd.transcript, cmd.snapshot ?? {});

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

        respond({
          ok: true,
          data: {
            ...data,
            _meta: {
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

      // Build full context message from snapshot
      const userMessage = buildContextMessage(transcript, snap);

      const messages = history.map((h: any) => ({
        role: h.role as "user" | "assistant",
        content: typeof h.content === "string" ? h.content : JSON.stringify(h.content),
      })).filter((m: any) => m.content && m.content.length > 0);

      let inferResult: any = null;
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
        inferResult = { ...data, _meta: { provider: raw.provider, model: raw.model, durationMs: raw.durationMs, tokens: raw.usage?.totalTokens } };
        log(`⏱ inference done in ${raw.durationMs}ms`);
      } catch (err: any) {
        log(`⏱ inference error: ${err.message}`);
        inferResult = { actions: [], spoken: "Sorry, I had trouble with that.", _meta: { error: err.message } };
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
