import { afterAll, expect, test } from "bun:test";

import {
  clearCredentialCache,
  infer,
  type ProviderName,
} from "../bin/infer.ts";
import {
  browserQueryDomParamsSchema,
  computerClickParamsSchema,
  computerHotkeyParamsSchema,
} from "../packages/npm/sdk/cua.mjs";

const originalFetch = globalThis.fetch;

afterAll(() => {
  globalThis.fetch = originalFetch;
});

test("CUA schemas validate without Zod", () => {
  expect(computerClickParamsSchema.parse({
    xRatio: 0.5,
    button: "left",
    count: 2,
    ignored: true,
  })).toEqual({ xRatio: 0.5, button: "left", count: 2 });
  expect(computerClickParamsSchema.safeParse({ xRatio: 2 }).success).toBe(false);
  expect(computerHotkeyParamsSchema.safeParse({}).success).toBe(false);
  expect(browserQueryDomParamsSchema.safeParse({
    selector: "main",
    allowAutomation: true,
  }).success).toBe(true);
});

test("inference providers use their dependency-free HTTP contracts", async () => {
  process.env.GROQ_API_KEY = "test-groq";
  process.env.OPENAI_API_KEY = "test-openai";
  process.env.ANTHROPIC_API_KEY = "test-anthropic";
  process.env.GOOGLE_GENERATIVE_AI_API_KEY = "test-google";
  process.env.XAI_API_KEY = "test-xai";
  process.env.MINIMAX_API_KEY = "test-minimax";
  clearCredentialCache();

  const requests: Array<{ url: string; init: RequestInit; body: any }> = [];
  globalThis.fetch = (async (input: string | URL | Request, init: RequestInit = {}) => {
    const url = String(input);
    const body = JSON.parse(String(init.body));
    requests.push({ url, init, body });

    if (url.includes("anthropic.com")) {
      return Response.json({
        content: [{ type: "text", text: "anthropic ok" }],
        usage: { input_tokens: 2, output_tokens: 1 },
      });
    }
    if (url.includes("googleapis.com")) {
      return Response.json({
        candidates: [{ content: { parts: [{ text: "google ok" }] } }],
        usageMetadata: {
          promptTokenCount: 2,
          candidatesTokenCount: 1,
          totalTokenCount: 3,
        },
      });
    }
    return Response.json({
      choices: [{ message: { content: "openai compatible ok" } }],
      usage: { prompt_tokens: 2, completion_tokens: 1, total_tokens: 3 },
    });
  }) as typeof fetch;

  const expectedHosts: Record<ProviderName, string> = {
    groq: "api.groq.com",
    openai: "api.openai.com",
    anthropic: "api.anthropic.com",
    google: "generativelanguage.googleapis.com",
    xai: "api.x.ai",
    minimax: "api.minimax.io",
  };

  for (const provider of Object.keys(expectedHosts) as ProviderName[]) {
    const result = await infer("hello", {
      provider,
      model: `${provider}-test`,
      system: "Be concise",
      maxTokens: 64,
    });
    const request = requests.at(-1)!;
    expect(request.url).toContain(expectedHosts[provider]);
    expect(result.usage?.totalTokens).toBe(3);
    if (provider === "google") {
      expect(request.url).toContain("google-test:generateContent");
    } else {
      expect(request.body.model).toBe(`${provider}-test`);
    }
  }

  const anthropic = requests.find((request) => request.url.includes("anthropic.com"))!;
  expect(anthropic.body.system).toBe("Be concise");
  expect(anthropic.body.max_tokens).toBe(64);

  const google = requests.find((request) => request.url.includes("googleapis.com"))!;
  expect(google.body.systemInstruction.parts[0].text).toBe("Be concise");
  expect(google.body.generationConfig.maxOutputTokens).toBe(64);
});
