import { Client } from "@modelcontextprotocol/sdk/client";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

export interface MinimaxMcpOptions {
  command?: string;
  args?: string[];
  model?: string;
  timeoutMs?: number;
  env?: NodeJS.ProcessEnv;
}

export interface MinimaxUnderstandImageRequest {
  prompt: string;
  imageSource: string;
  options?: MinimaxMcpOptions;
}

export interface MinimaxUnderstandImageResult {
  provider: string;
  model: string;
  text: string;
  parsed?: Record<string, unknown>;
}

function asObject(input: unknown): Record<string, unknown> {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("MiniMax MCP response must be a JSON object");
  }

  return input as Record<string, unknown>;
}

export function parseMinimaxArgsJSON(input: string | undefined): string[] {
  if (!input) {
    return [];
  }

  const parsed = JSON.parse(input) as unknown;
  if (!Array.isArray(parsed) || parsed.some((value) => typeof value !== "string")) {
    throw new Error("ACTION_PIE_ARGS_JSON must be a JSON string array");
  }

  return parsed as string[];
}

export function envRecord(env: NodeJS.ProcessEnv): Record<string, string> {
  const record: Record<string, string> = {};
  for (const [key, value] of Object.entries(env)) {
    if (typeof value === "string") {
      record[key] = value;
    }
  }
  return record;
}

function stripCodeFence(input: string): string {
  const fencedMatch = input.trim().match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  if (fencedMatch) {
    return fencedMatch[1].trim();
  }

  return input.trim();
}

function extractJSONObject(input: string): string {
  const trimmed = stripCodeFence(input);
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start === -1 || end === -1 || end < start) {
    return trimmed;
  }

  return trimmed.slice(start, end + 1);
}

export function parseMinimaxJSONText(input: string): Record<string, unknown> | undefined {
  const candidate = extractJSONObject(input);
  if (!candidate.includes("{")) {
    return undefined;
  }

  try {
    const parsed = JSON.parse(candidate) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return undefined;
    }
    return parsed as Record<string, unknown>;
  } catch {
    return undefined;
  }
}

export function extractMinimaxTextResult(result: unknown): string {
  const object = asObject(result);
  let content = object.content;

  if (!Array.isArray(content) && object.toolResult !== undefined) {
    const toolResult = asObject(object.toolResult);
    content = toolResult.content;
  }

  if (!Array.isArray(content)) {
    throw new Error("MiniMax MCP returned no content payload");
  }

  const text = content
    .filter((item): item is { type: string; text?: string } => {
      return !!item && typeof item === "object" && !Array.isArray(item);
    })
    .filter((item) => item.type === "text" && typeof item.text === "string")
    .map((item) => item.text ?? "")
    .join("\n")
    .trim();

  if (text.length === 0) {
    throw new Error("MiniMax MCP returned no text content");
  }

  return text;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

async function withTimeout<T>(promise: Promise<T>, timeoutMs: number, label: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timer = setTimeout(() => {
          reject(new Error(`${label} timed out after ${timeoutMs}ms`));
        }, timeoutMs);
      }),
    ]);
  } finally {
    if (timer) {
      clearTimeout(timer);
    }
  }
}

export function resolveMinimaxMcpConfig(options: MinimaxMcpOptions = {}) {
  const env = options.env ?? process.env;
  const model = options.model ?? env.ACTION_PIE_MODEL ?? "minimax-m2.7";
  const command = options.command ?? env.ACTION_PIE_COMMAND ?? "uvx";
  const args = options.args ?? parseMinimaxArgsJSON(env.ACTION_PIE_ARGS_JSON);
  const resolvedArgs = args.length > 0 ? args : ["minimax-coding-plan-mcp", "-y"];
  const timeoutMs = options.timeoutMs ?? Number(env.ACTION_PIE_TIMEOUT_MS ?? 20000);

  return {
    env,
    model,
    command,
    args: resolvedArgs,
    timeoutMs,
    providerId: `minimax:${model}`,
  };
}

export async function callMinimaxUnderstandImage(
  request: MinimaxUnderstandImageRequest,
): Promise<MinimaxUnderstandImageResult> {
  const config = resolveMinimaxMcpConfig(request.options);
  const apiKey = config.env.MINIMAX_API_KEY;
  if (!apiKey) {
    throw new Error(
      "MINIMAX_API_KEY is required for MiniMax vision analysis. Run with: secret run MINIMAX_API_KEY -- <command>",
    );
  }

  const stderrLines: string[] = [];
  const transport = new StdioClientTransport({
    command: config.command,
    args: config.args,
    env: {
      ...envRecord(config.env),
      MINIMAX_API_KEY: apiKey,
      MINIMAX_API_HOST: config.env.MINIMAX_API_HOST ?? "https://api.minimax.io",
    },
    stderr: "pipe",
  });
  const stderr = transport.stderr;
  if (stderr) {
    stderr.on("data", (chunk: Buffer | string) => {
      const line = Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
      stderrLines.push(line);
    });
  }

  const client = new Client(
    { name: "action-runtime", version: "0.0.0" },
    { capabilities: {} },
  );

  try {
    await withTimeout(client.connect(transport), config.timeoutMs, "MiniMax MCP connect");

    const toolResult = await withTimeout(
      client.callTool({
        name: "understand_image",
        arguments: {
          prompt: request.prompt,
          image_source: request.imageSource,
        },
      }),
      config.timeoutMs,
      "MiniMax understand_image",
    );
    const text = extractMinimaxTextResult(toolResult);
    return {
      provider: config.providerId,
      model: config.model,
      text,
      parsed: parseMinimaxJSONText(text),
    };
  } catch (error) {
    const stderrText = stderrLines.join("").trim();
    const suffix = stderrText.length > 0 ? `\n${stderrText}` : "";
    throw new Error(`MiniMax understand_image failed: ${errorMessage(error)}${suffix}`);
  } finally {
    await transport.close().catch(() => {});
  }
}