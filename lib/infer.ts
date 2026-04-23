/**
 * Lattices inference wrapper — thin layer over Vercel AI SDK.
 *
 * Features:
 *  - Multi-provider: groq, openai, anthropic, google, xai
 *  - Credential loading: env vars → ~/.lattices/inference.json → ~/.config/speakeasy/settings.json
 *  - Instrumented: every call logged with timing, model, token usage
 *  - Simple API: `await infer("do something", { provider: "groq" })`
 */

import { generateText, type ModelMessage } from "ai";
import { createOpenAI } from "@ai-sdk/openai";
import { createAnthropic } from "@ai-sdk/anthropic";
import { createGoogleGenerativeAI } from "@ai-sdk/google";
import { createXai } from "@ai-sdk/xai";
import { readFileSync, existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";

// ── Types ──────────────────────────────────────────────────────────

export type ProviderName = "groq" | "openai" | "anthropic" | "google" | "xai" | "minimax";

export interface InferOptions {
  provider?: ProviderName;
  model?: string;
  system?: string;
  messages?: ModelMessage[];
  temperature?: number;
  maxTokens?: number;
  /** Tag for logging — e.g. "hands-off", "voice-fallback" */
  tag?: string;
  /** Abort signal for cancellation/timeout */
  abortSignal?: AbortSignal;
}

export interface InferResult {
  text: string;
  provider: ProviderName;
  model: string;
  durationMs: number;
  usage?: {
    promptTokens?: number;
    completionTokens?: number;
    totalTokens?: number;
  };
}

// ── Default models per provider ────────────────────────────────────

const DEFAULT_MODELS: Record<ProviderName, string> = {
  groq: "llama-3.3-70b-versatile",
  openai: "gpt-4o-mini",
  anthropic: "claude-sonnet-4-6",
  google: "gemini-2.0-flash",
  xai: "grok-4-1-fast",
  minimax: "MiniMax-M2.5-highspeed",
};

// ── Credential loading ─────────────────────────────────────────────

interface CredentialStore {
  groq?: string;
  openai?: string;
  anthropic?: string;
  google?: string;
  xai?: string;
  minimax?: string;
}

let _cachedCreds: CredentialStore | null = null;

function loadCredentials(): CredentialStore {
  if (_cachedCreds) return _cachedCreds;

  const creds: CredentialStore = {};

  // Layer 1: env vars (highest priority)
  if (process.env.GROQ_API_KEY) creds.groq = process.env.GROQ_API_KEY;
  if (process.env.OPENAI_API_KEY) creds.openai = process.env.OPENAI_API_KEY;
  if (process.env.ANTHROPIC_API_KEY) creds.anthropic = process.env.ANTHROPIC_API_KEY;
  if (process.env.GOOGLE_GENERATIVE_AI_API_KEY) creds.google = process.env.GOOGLE_GENERATIVE_AI_API_KEY;
  if (process.env.XAI_API_KEY) creds.xai = process.env.XAI_API_KEY;
  if (process.env.MINIMAX_API_KEY) creds.minimax = process.env.MINIMAX_API_KEY;

  // Layer 2: ~/.lattices/inference.json
  const latticesConfig = join(homedir(), ".lattices", "inference.json");
  if (existsSync(latticesConfig)) {
    try {
      const cfg = JSON.parse(readFileSync(latticesConfig, "utf-8"));
      if (cfg.keys) {
        if (!creds.groq && cfg.keys.groq) creds.groq = cfg.keys.groq;
        if (!creds.openai && cfg.keys.openai) creds.openai = cfg.keys.openai;
        if (!creds.anthropic && cfg.keys.anthropic) creds.anthropic = cfg.keys.anthropic;
        if (!creds.google && cfg.keys.google) creds.google = cfg.keys.google;
        if (!creds.xai && cfg.keys.xai) creds.xai = cfg.keys.xai;
        if (!creds.minimax && cfg.keys.minimax) creds.minimax = cfg.keys.minimax;
      }
    } catch {}
  }

  // Layer 3: ~/.config/speakeasy/settings.json (fallback)
  const speakeasyConfig = join(homedir(), ".config", "speakeasy", "settings.json");
  if (existsSync(speakeasyConfig)) {
    try {
      const cfg = JSON.parse(readFileSync(speakeasyConfig, "utf-8"));
      const p = cfg.providers || {};
      if (!creds.groq && p.groq?.apiKey) creds.groq = p.groq.apiKey;
      if (!creds.openai && p.openai?.apiKey) creds.openai = p.openai.apiKey;
      if (!creds.anthropic && p.anthropic?.apiKey) creds.anthropic = p.anthropic.apiKey;
      if (!creds.google && p.gemini?.apiKey) creds.google = p.gemini.apiKey;
    } catch {}
  }

  _cachedCreds = creds;
  return creds;
}

/** Clear cached credentials (call if config changes at runtime) */
export function clearCredentialCache() {
  _cachedCreds = null;
}

/** List which providers have credentials available */
export function availableProviders(): ProviderName[] {
  const creds = loadCredentials();
  return (Object.keys(creds) as ProviderName[]).filter((k) => !!creds[k]);
}

// ── Provider factory ───────────────────────────────────────────────

function getModel(provider: ProviderName, modelId: string) {
  const creds = loadCredentials();

  switch (provider) {
    case "groq": {
      const groq = createOpenAI({
        baseURL: "https://api.groq.com/openai/v1",
        apiKey: creds.groq,
      });
      return groq(modelId);
    }
    case "openai": {
      const openai = createOpenAI({ apiKey: creds.openai });
      return openai(modelId);
    }
    case "anthropic": {
      const anthropic = createAnthropic({ apiKey: creds.anthropic });
      return anthropic(modelId);
    }
    case "google": {
      const google = createGoogleGenerativeAI({ apiKey: creds.google });
      return google(modelId);
    }
    case "xai": {
      const xai = createXai({ apiKey: creds.xai });
      return xai(modelId);
    }
    case "minimax": {
      // MiniMax uses OpenAI-compatible chat completions API
      const minimax = createOpenAI({
        baseURL: "https://api.minimax.io/v1",
        apiKey: creds.minimax,
      });
      return minimax.chat(modelId);
    }
  }
}

// ── Logging ────────────────────────────────────────────────────────

function log(tag: string, msg: string) {
  const ts = new Date().toISOString().slice(11, 23);
  console.error(`[${ts}] infer${tag ? `/${tag}` : ""}: ${msg}`);
}

// ── Main inference function ────────────────────────────────────────

/**
 * Run inference against any supported provider.
 *
 * @example
 * // Simple
 * const { text } = await infer("What windows do I have?", { provider: "groq" })
 *
 * // With system prompt and messages
 * const { text } = await infer("tile chrome left", {
 *   provider: "groq",
 *   system: "You are a workspace assistant...",
 *   tag: "hands-off",
 * })
 *
 * // With conversation history
 * const { text } = await infer("now the other one right", {
 *   provider: "groq",
 *   messages: [
 *     { role: "user", content: "tile chrome left" },
 *     { role: "assistant", content: '{"actions":[...]}' },
 *   ],
 * })
 */
export async function infer(
  prompt: string,
  options: InferOptions = {}
): Promise<InferResult> {
  const provider = options.provider ?? "groq";
  const modelId = options.model ?? DEFAULT_MODELS[provider];
  const tag = options.tag ?? "";

  // Check credentials
  const creds = loadCredentials();
  if (!creds[provider]) {
    throw new Error(
      `No API key for provider "${provider}". Set it in env, ~/.lattices/inference.json, or ~/.config/speakeasy/settings.json`
    );
  }

  const model = getModel(provider, modelId);

  // Build messages
  const messages: ModelMessage[] = [
    ...(options.messages ?? []),
    { role: "user", content: prompt },
  ];

  log(tag, `→ ${provider}/${modelId} (${prompt.length} chars)`);
  const start = performance.now();

  try {
    const result = await generateText({
      model,
      system: options.system,
      messages,
      temperature: options.temperature ?? 0.3,
      maxOutputTokens: options.maxTokens ?? 1024,
      abortSignal: options.abortSignal,
    });

    const durationMs = Math.round(performance.now() - start);

    const usage = result.usage
      ? {
          promptTokens: result.usage.inputTokens,
          completionTokens: result.usage.outputTokens,
          totalTokens: result.usage.totalTokens,
        }
      : undefined;

    log(
      tag,
      `← ${durationMs}ms | ${usage?.totalTokens ?? "?"} tokens | ${result.text.length} chars`
    );

    return {
      text: result.text,
      provider,
      model: modelId,
      durationMs,
      usage,
    };
  } catch (err: any) {
    const durationMs = Math.round(performance.now() - start);
    log(tag, `✗ ${durationMs}ms | ${err.message ?? err}`);
    throw err;
  }
}

// ── Convenience: infer with automatic JSON parsing ─────────────────

export async function inferJSON<T = any>(
  prompt: string,
  options: InferOptions = {}
): Promise<{ data: T; raw: InferResult }> {
  const result = await infer(prompt, options);

  // Extract JSON from response (handle markdown fences)
  let cleaned = result.text
    .replace(/```json\s*/g, "")
    .replace(/```\s*/g, "")
    .trim();

  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  if (start === -1 || end === -1) {
    throw new Error(`No JSON found in response: ${result.text.slice(0, 200)}`);
  }
  cleaned = cleaned.slice(start, end + 1);

  const data = JSON.parse(cleaned) as T;
  return { data, raw: result };
}
