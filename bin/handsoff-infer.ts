#!/usr/bin/env bun
/**
 * Hands-off inference script — called by HandsOffSession.swift.
 *
 * Usage: echo '{"transcript":"tile chrome left","snapshot":{...}}' | bun run bin/handsoff-infer.ts
 *
 * Reads JSON from stdin, calls the configured voice inference provider, prints JSON result to stdout.
 * All logging goes to stderr so it doesn't pollute the JSON output.
 */

import {
  buildAssistantContextMessage,
  buildAssistantSystemPrompt,
  normalizeAssistantPlan,
  tryLocalAssistantPlan,
} from "./assistant-intelligence.ts";
import { inferJSON, resolveVoiceInferenceOptions } from "./infer.ts";

const INFER_TIMEOUT_MS = 15_000;

// ── Read input from stdin ──────────────────────────────────────────

const input = await Bun.stdin.text();
const req = JSON.parse(input) as {
  transcript: string;
  snapshot: {
    stageManager?: boolean;
    smGrouping?: string;
    activeStage?: Array<{ wid: number; app: string; title: string; frame: string }>;
    stripApps?: string[];
    hiddenApps?: string[];
    currentLayer?: string;
    screen?: string;
  };
  history?: Array<{ role: "user" | "assistant"; content: string }>;
};

const transcript = req.transcript ?? "";
const systemPrompt = buildAssistantSystemPrompt();
const userMessage = buildAssistantContextMessage(transcript, req.snapshot ?? {});
const voiceInference = resolveVoiceInferenceOptions();

const localPlan = tryLocalAssistantPlan(transcript, req.snapshot ?? {});
if (localPlan) {
  console.log(JSON.stringify(localPlan));
  process.exit(0);
}

// ── Call inference ──────────────────────────────────────────────────

const messages = (req.history ?? []).map((h) => ({
  role: h.role as "user" | "assistant",
  content: h.content,
}));

const controller = new AbortController();
const timer = setTimeout(() => controller.abort(), INFER_TIMEOUT_MS);

try {
  const { data, raw } = await inferJSON(userMessage, {
    provider: voiceInference.provider,
    model: voiceInference.model,
    system: systemPrompt,
    messages,
    temperature: 0.2,
    maxTokens: 512,
    abortSignal: controller.signal,
    tag: "hands-off",
  });

  // Output result as JSON to stdout
  const plan = normalizeAssistantPlan(data, transcript);
  const output = {
    ...plan,
    _meta: {
      ...plan._meta,
      provider: raw.provider,
      model: raw.model,
      durationMs: raw.durationMs,
      tokens: raw.usage?.totalTokens,
    },
  };

  console.log(JSON.stringify(output));
} catch (err: any) {
  console.log(
    JSON.stringify({
      actions: [],
      spoken: "Sorry, I had trouble processing that.",
      _meta: { error: err.message },
    })
  );
  process.exitCode = 1;
} finally {
  clearTimeout(timer);
}
