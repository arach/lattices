/**
 * Lattices inference wrapper — dependency-free HTTP clients for text models.
 *
 * Features:
 *  - Multi-provider: groq, openai, anthropic, google, xai, minimax
 *  - Credential loading: env vars → .env.local/.env → ~/.lattices/inference.json → macOS Keychain
 *  - Instrumented: every call logged with timing, model, token usage
 *  - Simple API: `await infer("do something", { provider: "groq" })`
 */

import { readFileSync, existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { getKeychainSecret } from "./keychain";

// ── Types ──────────────────────────────────────────────────────────

export type ProviderName = "groq" | "openai" | "anthropic" | "google" | "xai" | "minimax";

export interface InferenceMessage {
  role: "system" | "user" | "assistant";
  content: string | Array<{ type?: string; text?: string }>;
}

export interface InferOptions {
  provider?: ProviderName;
  model?: string;
  system?: string;
  messages?: InferenceMessage[];
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

const PROVIDER_NAMES: ProviderName[] = ["groq", "openai", "anthropic", "google", "xai", "minimax"];
const VOICE_PROVIDER_PRIORITY: ProviderName[] = ["xai", "groq", "openai", "google", "anthropic", "minimax"];

const DEFAULT_MODELS: Record<ProviderName, string> = {
  groq: "llama-3.3-70b-versatile",
  openai: "gpt-4o-mini",
  anthropic: "claude-sonnet-4-6",
  google: "gemini-2.0-flash",
  xai: "grok-4.20-reasoning",
  minimax: "MiniMax-M2.5-highspeed",
};

// Voice paths use the same models as default — earlier we forced groq to
// llama-3.1-8b-instant for latency, but its 6k TPM cap couldn't fit a real
// desktop snapshot (saw 7174-token requests rejected). 70B versatile fits
// 128k context and Groq still serves it fast.
const VOICE_DEFAULT_MODELS: Record<ProviderName, string> = {
  ...DEFAULT_MODELS,
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
let _cachedLocalEnv: Record<string, string> | null = null;

function parseDotEnv(content: string): Record<string, string> {
  const env: Record<string, string> = {};

  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;

    const match = line.match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!match) continue;

    const [, key, rawValue] = match;
    let value = rawValue.trim();
    const quote = value[0];
    if ((quote === `"` || quote === `'`) && value.endsWith(quote)) {
      value = value.slice(1, -1);
    } else {
      value = value.replace(/\s+#.*$/, "").trim();
    }

    env[key] = value;
  }

  return env;
}

function loadLocalEnv(): Record<string, string> {
  if (_cachedLocalEnv) return _cachedLocalEnv;

  const repoRoot = join(import.meta.dir, "..");
  const candidates = [
    join(repoRoot, ".env"),
    join(repoRoot, ".env.local"),
    join(process.cwd(), ".env"),
    join(process.cwd(), ".env.local"),
  ];

  const env: Record<string, string> = {};
  for (const file of Array.from(new Set(candidates))) {
    if (!existsSync(file)) continue;
    try {
      Object.assign(env, parseDotEnv(readFileSync(file, "utf-8")));
    } catch {}
  }

  _cachedLocalEnv = env;
  return env;
}

export function getInferenceEnv(name: string): string | undefined {
  return process.env[name] || loadLocalEnv()[name];
}

function firstInferenceEnv(names: string[]): string | undefined {
  for (const name of names) {
    const value = getInferenceEnv(name);
    if (value) return value;
  }
}

function normalizeProvider(value: string | undefined): ProviderName | undefined {
  const provider = value?.trim().toLowerCase();
  return PROVIDER_NAMES.includes(provider as ProviderName) ? (provider as ProviderName) : undefined;
}

function assignGrokAlias(creds: CredentialStore) {
  const key = getInferenceEnv("GROK_API_KEY");
  if (!key) return;

  // People often say/type "Grok" when they mean Groq. Use the key shape to
  // route the alias without making xAI and Groq credentials interchangeable.
  if (!creds.groq && key.startsWith("gsk_")) creds.groq = key;
  if (!creds.xai && key.startsWith("xai-")) creds.xai = key;
}

function loadCredentials(): CredentialStore {
  if (_cachedCreds) return _cachedCreds;

  const creds: CredentialStore = {};

  // Layer 1: env vars (highest priority)
  const groqKey = getInferenceEnv("GROQ_API_KEY");
  const openaiKey = getInferenceEnv("OPENAI_API_KEY");
  const anthropicKey = getInferenceEnv("ANTHROPIC_API_KEY");
  const googleKey = getInferenceEnv("GOOGLE_GENERATIVE_AI_API_KEY");
  // SUPERGROK_API_KEY (SuperGrok Heavy tier) takes precedence over the
  // standard XAI_API_KEY when both are present.
  const xaiKey =
    getInferenceEnv("SUPERGROK_API_KEY") || getInferenceEnv("XAI_API_KEY");
  const minimaxKey = getInferenceEnv("MINIMAX_API_KEY");
  if (groqKey) creds.groq = groqKey;
  if (openaiKey) creds.openai = openaiKey;
  if (anthropicKey) creds.anthropic = anthropicKey;
  if (googleKey) creds.google = googleKey;
  if (xaiKey) creds.xai = xaiKey;
  if (minimaxKey) creds.minimax = minimaxKey;
  assignGrokAlias(creds);

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

  // Layer 3 — macOS keychain via built-in `/usr/bin/security` under the
  // `lattices.inference` service. One read per missing provider, cached
  // in `_cachedCreds` for the process lifetime. Keys never touch disk.
  // Portable across machines (no external CLI dep).
  if (!creds.xai) creds.xai = getKeychainSecret("xai");
  if (!creds.groq) creds.groq = getKeychainSecret("groq");
  if (!creds.openai) creds.openai = getKeychainSecret("openai");
  if (!creds.anthropic) creds.anthropic = getKeychainSecret("anthropic");
  if (!creds.google) creds.google = getKeychainSecret("google");
  if (!creds.minimax) creds.minimax = getKeychainSecret("minimax");

  _cachedCreds = creds;
  return creds;
}

/** Clear cached credentials (call if config changes at runtime) */
export function clearCredentialCache() {
  _cachedCreds = null;
  _cachedLocalEnv = null;
}

/** List which providers have credentials available */
export function availableProviders(): ProviderName[] {
  const creds = loadCredentials();
  return (Object.keys(creds) as ProviderName[]).filter((k) => !!creds[k]);
}

/** Voice/hands-off defaults favor the lowest-latency configured provider. */
export function resolveVoiceInferenceOptions(): { provider: ProviderName; model: string } {
  const configuredProvider = normalizeProvider(firstInferenceEnv([
    "LATTICES_VOICE_PROVIDER",
    "LATTICES_HANDSOFF_PROVIDER",
    "LATTICES_INFER_PROVIDER",
  ]));

  const creds = loadCredentials();
  const provider = configuredProvider
    ?? VOICE_PROVIDER_PRIORITY.find((name) => !!creds[name])
    ?? "groq";

  const model = firstInferenceEnv([
    "LATTICES_VOICE_MODEL",
    "LATTICES_HANDSOFF_MODEL",
    "LATTICES_INFER_MODEL",
  ]) ?? VOICE_DEFAULT_MODELS[provider];

  return { provider, model };
}

// ── Provider HTTP clients ─────────────────────────────────────────

interface ProviderResponse {
  text: string;
  usage?: InferResult["usage"];
}

interface NormalizedMessage {
  role: InferenceMessage["role"];
  content: string;
}

function contentText(content: InferenceMessage["content"]): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return String(content ?? "");
  return content
    .map((part) => typeof part?.text === "string" ? part.text : "")
    .filter(Boolean)
    .join("\n");
}

function normalizeMessages(
  prompt: string,
  messages: InferenceMessage[] = []
): NormalizedMessage[] {
  return [
    ...messages.map((message) => ({
      role: message.role,
      content: contentText(message.content),
    })),
    { role: "user" as const, content: prompt },
  ];
}

async function postJSON(
  url: string,
  headers: Record<string, string>,
  body: Record<string, unknown>,
  abortSignal?: AbortSignal
): Promise<any> {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
    signal: abortSignal,
  });
  const raw = await response.text();
  let data: any;
  try {
    data = raw ? JSON.parse(raw) : {};
  } catch {
    data = { message: raw };
  }

  if (!response.ok) {
    const detail = data?.error?.message ?? data?.error ?? data?.message ?? raw;
    throw new Error(`HTTP ${response.status}: ${String(detail || response.statusText)}`);
  }
  return data;
}

function responseText(content: unknown): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((part) => typeof part === "string" ? part : part?.text ?? "")
      .filter(Boolean)
      .join("\n");
  }
  return "";
}

async function inferOpenAICompatible(
  provider: "groq" | "openai" | "xai" | "minimax",
  apiKey: string,
  model: string,
  messages: NormalizedMessage[],
  options: InferOptions
): Promise<ProviderResponse> {
  const baseURLs = {
    groq: "https://api.groq.com/openai/v1",
    openai: "https://api.openai.com/v1",
    xai: "https://api.x.ai/v1",
    minimax: "https://api.minimax.io/v1",
  } as const;
  const maxTokens = options.maxTokens ?? 1024;
  const data = await postJSON(
    `${baseURLs[provider]}/chat/completions`,
    { authorization: `Bearer ${apiKey}` },
    {
      model,
      messages: [
        ...(options.system ? [{ role: "system", content: options.system }] : []),
        ...messages,
      ],
      temperature: options.temperature ?? 0.3,
      ...(provider === "xai"
        ? { max_tokens: maxTokens }
        : { max_completion_tokens: maxTokens }),
    },
    options.abortSignal
  );
  const usage = data?.usage;
  const text = responseText(data?.choices?.[0]?.message?.content);
  if (!text) throw new Error(`${provider} returned no text`);
  return {
    text,
    usage: usage ? {
      promptTokens: usage.prompt_tokens,
      completionTokens: usage.completion_tokens,
      totalTokens: usage.total_tokens,
    } : undefined,
  };
}

async function inferAnthropic(
  apiKey: string,
  model: string,
  messages: NormalizedMessage[],
  options: InferOptions
): Promise<ProviderResponse> {
  const systemMessages = messages.filter((message) => message.role === "system");
  const system = [options.system, ...systemMessages.map((message) => message.content)]
    .filter(Boolean)
    .join("\n\n");
  const data = await postJSON(
    "https://api.anthropic.com/v1/messages",
    {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    {
      model,
      max_tokens: options.maxTokens ?? 1024,
      temperature: options.temperature ?? 0.3,
      ...(system ? { system } : {}),
      messages: messages.filter((message) => message.role !== "system"),
    },
    options.abortSignal
  );
  const text = responseText(data?.content);
  if (!text) throw new Error("anthropic returned no text");
  const promptTokens = data?.usage?.input_tokens;
  const completionTokens = data?.usage?.output_tokens;
  return {
    text,
    usage: data?.usage ? {
      promptTokens,
      completionTokens,
      totalTokens: typeof promptTokens === "number" && typeof completionTokens === "number"
        ? promptTokens + completionTokens
        : undefined,
    } : undefined,
  };
}

async function inferGoogle(
  apiKey: string,
  model: string,
  messages: NormalizedMessage[],
  options: InferOptions
): Promise<ProviderResponse> {
  const modelId = model.replace(/^models\//, "");
  const systemMessages = messages.filter((message) => message.role === "system");
  const system = [options.system, ...systemMessages.map((message) => message.content)]
    .filter(Boolean)
    .join("\n\n");
  const data = await postJSON(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(modelId)}:generateContent`,
    { "x-goog-api-key": apiKey },
    {
      ...(system ? { systemInstruction: { parts: [{ text: system }] } } : {}),
      contents: messages
        .filter((message) => message.role !== "system")
        .map((message) => ({
          role: message.role === "assistant" ? "model" : "user",
          parts: [{ text: message.content }],
        })),
      generationConfig: {
        temperature: options.temperature ?? 0.3,
        maxOutputTokens: options.maxTokens ?? 1024,
      },
    },
    options.abortSignal
  );
  const text = responseText(data?.candidates?.[0]?.content?.parts);
  if (!text) throw new Error("google returned no text");
  const usage = data?.usageMetadata;
  return {
    text,
    usage: usage ? {
      promptTokens: usage.promptTokenCount,
      completionTokens: usage.candidatesTokenCount,
      totalTokens: usage.totalTokenCount,
    } : undefined,
  };
}

async function callProvider(
  provider: ProviderName,
  apiKey: string,
  model: string,
  messages: NormalizedMessage[],
  options: InferOptions
): Promise<ProviderResponse> {
  if (provider === "anthropic") {
    return inferAnthropic(apiKey, model, messages, options);
  }
  if (provider === "google") {
    return inferGoogle(apiKey, model, messages, options);
  }
  return inferOpenAICompatible(provider, apiKey, model, messages, options);
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
      `No API key for provider "${provider}". Set it in env, .env.local, ~/.lattices/inference.json, or the macOS Keychain`
    );
  }

  const apiKey = creds[provider];
  const messages = normalizeMessages(prompt, options.messages);

  log(tag, `→ ${provider}/${modelId} (${prompt.length} chars)`);
  const start = performance.now();

  try {
    const result = await callProvider(provider, apiKey, modelId, messages, options);

    const durationMs = Math.round(performance.now() - start);

    const usage = result.usage;

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
