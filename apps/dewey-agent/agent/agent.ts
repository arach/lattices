import { anthropic } from "@ai-sdk/anthropic";
import { createOpenAICompatible } from "@ai-sdk/openai-compatible";
import { defineAgent } from "eve";

function resolveModel() {
  const provider = process.env.DEWEY_AGENT_PROVIDER ?? "local";

  if (provider === "anthropic") {
    return anthropic(process.env.DEWEY_AGENT_MODEL ?? "claude-opus-4.8");
  }

  const local = createOpenAICompatible({
    name: process.env.DEWEY_AGENT_PROVIDER_NAME ?? "local",
    baseURL: process.env.DEWEY_AGENT_BASE_URL ?? "http://127.0.0.1:11434/v1",
    apiKey: process.env.DEWEY_AGENT_API_KEY ?? "local",
  });

  return local.chatModel(process.env.DEWEY_AGENT_MODEL ?? "llama3.1:8b");
}

function contextWindowTokens() {
  const raw = process.env.DEWEY_AGENT_CONTEXT_WINDOW_TOKENS;
  const parsed = raw ? Number.parseInt(raw, 10) : 131_072;

  return Number.isFinite(parsed) && parsed > 0 ? parsed : 131_072;
}

export default defineAgent({
  model: resolveModel(),
  modelContextWindowTokens: contextWindowTokens(),
  compaction: {
    modelContextWindowTokens: contextWindowTokens(),
    thresholdPercent: 0.85,
  },
});
