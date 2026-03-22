import { spawn, type ChildProcess } from "node:child_process";
import { mkdir, readFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";

export type ProjectTwinThinkingLevel = "off" | "minimal" | "low" | "medium" | "high" | "xhigh";

export interface ProjectTwinOptions {
  cwd: string;
  name?: string;
  piCommand?: string[];
  provider?: string;
  model?: string;
  thinking?: ProjectTwinThinkingLevel;
  tools?: string[];
  extensions?: string[];
  skills?: string[];
  promptTemplates?: string[];
  disableExtensions?: boolean;
  disableSkills?: boolean;
  disablePromptTemplates?: boolean;
  systemPrompt?: string;
  appendSystemPrompt?: string;
  storageDir?: string;
  sessionDir?: string;
  env?: Record<string, string>;
  defaultTimeoutMs?: number;
  autoLoadOpenScoutRelay?: boolean;
}

export interface ProjectTwinInvokeRequest {
  task: string;
  caller?: string;
  context?: string | string[];
  memory?: string | string[];
  protocol?: string;
  protocolContext?: unknown;
  timeoutMs?: number;
}

export interface ProjectTwinState {
  sessionId: string;
  sessionFile?: string;
  sessionName?: string;
  isStreaming: boolean;
  messageCount: number;
  pendingMessageCount: number;
  autoCompactionEnabled: boolean;
}

export interface ProjectTwinResult {
  text: string;
  state: ProjectTwinState;
  events: ProjectTwinEvent[];
}

export interface OpenScoutRelayContext {
  relayDir: string;
  linkPath?: string;
  configPath?: string;
  channelLogPath?: string;
  hub?: string;
  linkedAt?: string;
  agentCount?: number;
  config?: Record<string, unknown>;
  recentChannelLines: string[];
}

export interface ProjectTwinEvent {
  type: string;
  [key: string]: unknown;
}

interface PiRpcResponse {
  id?: string;
  type: "response";
  command: string;
  success: boolean;
  data?: unknown;
  error?: string;
}

interface PiRpcStateResponse {
  sessionId: string;
  sessionFile?: string;
  sessionName?: string;
  isStreaming: boolean;
  messageCount: number;
  pendingMessageCount?: number;
  autoCompactionEnabled?: boolean;
}

const DEFAULT_TOOLS = ["read", "bash", "edit", "write"];

const DEFAULT_TWIN_APPEND_SYSTEM_PROMPT = [
  "You are the persistent project twin for the current working directory.",
  "A project twin is the project-native runtime that mediates between a primary agent and project-specific protocols, tools, and memory.",
  "Treat caller messages as invocations from another agent, not as end-user chat.",
  "Prefer concise operational handoffs that the caller can act on immediately.",
  "Keep project-specific protocol semantics behind this boundary instead of teaching them back to the caller unless explicitly asked.",
  "If context is missing, inspect the project and say what is missing instead of inventing it.",
].join(" ");

function slugify(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || "project-twin";
}

function normalizeTextBlock(value: string | string[] | undefined): string | undefined {
  if (value === undefined) return undefined;
  return Array.isArray(value) ? value.filter(Boolean).join("\n\n") : value.trim();
}

function renderUnknown(value: unknown): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value === "string") return value.trim();
  return JSON.stringify(value, null, 2);
}

function pushSection(parts: string[], tag: string, value: string | undefined): void {
  if (!value) return;
  parts.push(`<${tag}>\n${value}\n</${tag}>`);
}

function encodeJsonLine(value: unknown): string {
  return `${JSON.stringify(value)}\n`;
}

function defaultTwinName(cwd: string, name?: string): string {
  return name?.trim() || `${basename(cwd)}-twin`;
}

function defaultStorageDir(cwd: string, name?: string): string {
  return join(cwd, ".openscout", "twins", slugify(defaultTwinName(cwd, name)));
}

function buildTwinAppendSystemPrompt(options: ProjectTwinOptions): string {
  const parts = [DEFAULT_TWIN_APPEND_SYSTEM_PROMPT];
  if (options.appendSystemPrompt?.trim()) {
    parts.push(options.appendSystemPrompt.trim());
  }
  return parts.join("\n\n");
}

function buildInvocationPrompt(
  twinName: string,
  cwd: string,
  request: ProjectTwinInvokeRequest,
  relayContext?: OpenScoutRelayContext,
): string {
  const parts: string[] = [
    `This is a mediated invocation into the project twin "${twinName}" for ${cwd}.`,
    "Resume with the right project context, do whatever local inspection or protocol work is needed, and return a concise handoff to the calling agent.",
  ];

  pushSection(parts, "caller", request.caller?.trim());
  pushSection(parts, "context", normalizeTextBlock(request.context));
  pushSection(parts, "memory", normalizeTextBlock(request.memory));

  if (request.protocol?.trim()) {
    parts.push(`<protocol>\n${request.protocol.trim()}\n</protocol>`);
  }

  pushSection(parts, "protocol-context", renderUnknown(request.protocolContext));

  if (relayContext) {
    pushSection(parts, "openscout-relay", renderUnknown(relayContext));
  }

  pushSection(parts, "task", request.task.trim());

  parts.push(
    [
      "Respond in Markdown with these sections:",
      "## Outcome",
      "## Actions",
      "## Notes",
      "## Next",
    ].join("\n"),
  );

  return parts.join("\n\n");
}

async function readIfExists(path: string): Promise<string | undefined> {
  try {
    return await readFile(path, "utf8");
  } catch {
    return undefined;
  }
}

async function readJsonIfExists(path: string): Promise<Record<string, unknown> | undefined> {
  const text = await readIfExists(path);
  if (!text) return undefined;

  try {
    const parsed = JSON.parse(text) as unknown;
    return parsed && typeof parsed === "object" ? (parsed as Record<string, unknown>) : undefined;
  } catch {
    return undefined;
  }
}

async function readTailLines(path: string, count: number): Promise<string[]> {
  const text = await readIfExists(path);
  if (!text) return [];
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .slice(-count);
}

export async function readOpenScoutRelayContext(cwd: string): Promise<OpenScoutRelayContext | undefined> {
  const openScoutDir = join(cwd, ".openscout");
  const linkPath = join(openScoutDir, "relay.json");
  const relayDir = join(openScoutDir, "relay");
  const configPath = join(relayDir, "config.json");
  const channelLogPath = join(relayDir, "channel.log");

  const [linkMeta, config, recentChannelLines] = await Promise.all([
    readJsonIfExists(linkPath),
    readJsonIfExists(configPath),
    readTailLines(channelLogPath, 10),
  ]);

  if (!linkMeta && !config && recentChannelLines.length === 0) {
    return undefined;
  }

  const agents = Array.isArray(config?.agents) ? config.agents : undefined;

  return {
    relayDir,
    linkPath: linkMeta ? linkPath : undefined,
    configPath: config ? configPath : undefined,
    channelLogPath: recentChannelLines.length > 0 ? channelLogPath : undefined,
    hub: typeof linkMeta?.hub === "string" ? linkMeta.hub : undefined,
    linkedAt: typeof linkMeta?.linkedAt === "string" ? linkMeta.linkedAt : undefined,
    agentCount: agents?.length,
    config,
    recentChannelLines,
  };
}

class PiRpcClient {
  private process: ChildProcess | null = null;
  private stdoutBuffer = "";
  private stderrBuffer = "";
  private listeners = new Set<(event: ProjectTwinEvent) => void>();
  private pendingRequests = new Map<
    string,
    { resolve: (response: PiRpcResponse) => void; reject: (error: Error) => void; timeout: Timer }
  >();
  private requestCounter = 0;

  constructor(
    private readonly command: string[],
    private readonly cwd: string,
    private readonly env: NodeJS.ProcessEnv,
    private readonly defaultTimeoutMs: number,
  ) {}

  async start(): Promise<void> {
    if (this.process) return;
    if (this.command.length === 0) {
      throw new Error("Pi command cannot be empty");
    }

    const [bin, ...args] = this.command;
    const child = spawn(bin, args, {
      cwd: this.cwd,
      env: this.env,
      stdio: ["pipe", "pipe", "pipe"],
    });

    await new Promise<void>((resolvePromise, rejectPromise) => {
      const onError = (error: Error) => {
        child.off("spawn", onSpawn);
        rejectPromise(
          new Error(
            `Failed to start Pi RPC process (${bin}). Install pi, set PI_BIN, or pass piCommand explicitly. ${error.message}`,
          ),
        );
      };
      const onSpawn = () => {
        child.off("error", onError);
        resolvePromise();
      };

      child.once("error", onError);
      child.once("spawn", onSpawn);
    });

    child.stdout?.on("data", (chunk: Buffer | string) => {
      this.handleStdoutChunk(typeof chunk === "string" ? chunk : chunk.toString("utf8"));
    });

    child.stderr?.on("data", (chunk: Buffer | string) => {
      this.stderrBuffer += typeof chunk === "string" ? chunk : chunk.toString("utf8");
    });

    child.on("exit", () => {
      this.process = null;
      for (const pending of this.pendingRequests.values()) {
        clearTimeout(pending.timeout);
        pending.reject(new Error(`Pi RPC process exited. Stderr: ${this.stderrBuffer.trim()}`));
      }
      this.pendingRequests.clear();
    });

    this.process = child;
  }

  async stop(): Promise<void> {
    if (!this.process) return;

    const child = this.process;
    this.process = null;

    await new Promise<void>((resolvePromise) => {
      const timer = setTimeout(() => {
        child.kill("SIGKILL");
        resolvePromise();
      }, 1000);

      child.once("exit", () => {
        clearTimeout(timer);
        resolvePromise();
      });

      child.kill("SIGTERM");
    });
  }

  onEvent(listener: (event: ProjectTwinEvent) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  async promptAndWait(message: string, timeoutMs = this.defaultTimeoutMs): Promise<ProjectTwinEvent[]> {
    const collector = this.collectEventsUntilIdle(timeoutMs);
    try {
      await this.send({ type: "prompt", message }, timeoutMs);
      return await collector.promise;
    } catch (error) {
      collector.dispose();
      throw error;
    }
  }

  async newSession(parentSession?: string): Promise<{ cancelled: boolean }> {
    const response = await this.send({ type: "new_session", parentSession }, this.defaultTimeoutMs);
    return this.unwrapData<{ cancelled: boolean }>(response);
  }

  async getState(): Promise<ProjectTwinState> {
    const response = await this.send({ type: "get_state" }, this.defaultTimeoutMs);
    const data = this.unwrapData<PiRpcStateResponse>(response);

    return {
      sessionId: data.sessionId,
      sessionFile: data.sessionFile,
      sessionName: data.sessionName,
      isStreaming: data.isStreaming,
      messageCount: data.messageCount,
      pendingMessageCount: data.pendingMessageCount ?? 0,
      autoCompactionEnabled: data.autoCompactionEnabled ?? true,
    };
  }

  async getLastAssistantText(): Promise<string | null> {
    const response = await this.send({ type: "get_last_assistant_text" }, this.defaultTimeoutMs);
    const data = this.unwrapData<{ text: string | null }>(response);
    return data.text;
  }

  async setSessionName(name: string): Promise<void> {
    await this.send({ type: "set_session_name", name }, this.defaultTimeoutMs);
  }

  private collectEventsUntilIdle(timeoutMs: number): {
    promise: Promise<ProjectTwinEvent[]>;
    dispose: () => void;
  } {
    let cleanup = () => {};

    const promise = new Promise<ProjectTwinEvent[]>((resolvePromise, rejectPromise) => {
      const events: ProjectTwinEvent[] = [];
      const timer = setTimeout(() => {
        unsubscribe();
        rejectPromise(new Error(`Timed out waiting for Pi to become idle. Stderr: ${this.stderrBuffer.trim()}`));
      }, timeoutMs);

      const unsubscribe = this.onEvent((event) => {
        events.push(event);
        if (event.type === "agent_end") {
          clearTimeout(timer);
          unsubscribe();
          resolvePromise(events);
        }
      });

      cleanup = () => {
        clearTimeout(timer);
        unsubscribe();
      };
    });

    return {
      promise,
      dispose: cleanup,
    };
  }

  private async send(command: Record<string, unknown>, timeoutMs: number): Promise<PiRpcResponse> {
    if (!this.process?.stdin) {
      throw new Error("Pi RPC client is not started");
    }

    const id = `req_${++this.requestCounter}`;
    const payload = { ...command, id };

    return new Promise<PiRpcResponse>((resolvePromise, rejectPromise) => {
      const timeout = setTimeout(() => {
        this.pendingRequests.delete(id);
        rejectPromise(
          new Error(
            `Timed out waiting for Pi RPC response to ${String(command.type)}. Stderr: ${this.stderrBuffer.trim()}`,
          ),
        );
      }, timeoutMs);

      this.pendingRequests.set(id, {
        resolve: resolvePromise,
        reject: rejectPromise,
        timeout,
      });

      this.process?.stdin?.write(encodeJsonLine(payload));
    });
  }

  private unwrapData<T>(response: PiRpcResponse): T {
    if (!response.success) {
      throw new Error(response.error || `Pi RPC command ${response.command} failed`);
    }
    return response.data as T;
  }

  private handleStdoutChunk(chunk: string): void {
    this.stdoutBuffer += chunk;

    while (true) {
      const newlineIndex = this.stdoutBuffer.indexOf("\n");
      if (newlineIndex === -1) return;

      const rawLine = this.stdoutBuffer.slice(0, newlineIndex);
      this.stdoutBuffer = this.stdoutBuffer.slice(newlineIndex + 1);

      const line = rawLine.endsWith("\r") ? rawLine.slice(0, -1) : rawLine;
      if (!line.trim()) continue;

      this.handleStdoutLine(line);
    }
  }

  private handleStdoutLine(line: string): void {
    let payload: unknown;
    try {
      payload = JSON.parse(line);
    } catch {
      return;
    }

    if (!payload || typeof payload !== "object") return;

    const response = payload as PiRpcResponse;
    if (response.type === "response" && response.id && this.pendingRequests.has(response.id)) {
      const pending = this.pendingRequests.get(response.id)!;
      clearTimeout(pending.timeout);
      this.pendingRequests.delete(response.id);
      pending.resolve(response);
      return;
    }

    const event = payload as ProjectTwinEvent;
    for (const listener of this.listeners) {
      listener(event);
    }
  }
}

export class ProjectTwin {
  readonly cwd: string;
  readonly name: string;
  readonly storageDir: string;
  readonly sessionDir: string;

  private readonly options: ProjectTwinOptions;
  private rpc: PiRpcClient | null = null;
  private startPromise: Promise<void> | null = null;
  private invokeQueue: Promise<unknown> = Promise.resolve();

  constructor(options: ProjectTwinOptions) {
    this.options = {
      defaultTimeoutMs: 60000,
      autoLoadOpenScoutRelay: true,
      disableExtensions: true,
      disableSkills: true,
      disablePromptTemplates: true,
      tools: DEFAULT_TOOLS,
      ...options,
    };

    this.cwd = resolve(this.options.cwd);
    this.name = defaultTwinName(this.cwd, this.options.name);
    this.storageDir = this.options.storageDir
      ? resolve(this.options.storageDir)
      : defaultStorageDir(this.cwd, this.name);
    this.sessionDir = this.options.sessionDir
      ? resolve(this.options.sessionDir)
      : join(this.storageDir, "sessions");
  }

  async start(): Promise<void> {
    if (this.rpc) return;
    if (this.startPromise) return this.startPromise;

    this.startPromise = this.startInternal().finally(() => {
      this.startPromise = null;
    });
    return this.startPromise;
  }

  async stop(): Promise<void> {
    await this.rpc?.stop();
    this.rpc = null;
  }

  async reset(parentSession?: string): Promise<{ cancelled: boolean }> {
    await this.start();
    return this.rpc!.newSession(parentSession);
  }

  async getState(): Promise<ProjectTwinState> {
    await this.start();
    return this.rpc!.getState();
  }

  invoke(request: ProjectTwinInvokeRequest): Promise<ProjectTwinResult> {
    const run = this.invokeQueue.then(() => this.invokeInternal(request));
    this.invokeQueue = run.catch(() => {});
    return run;
  }

  private async startInternal(): Promise<void> {
    await mkdir(this.sessionDir, { recursive: true });

    const piCommand = this.options.piCommand ?? (process.env.PI_BIN ? [process.env.PI_BIN] : ["pi"]);
    const command = [...piCommand, ...this.buildPiArgs()];

    this.rpc = new PiRpcClient(
      command,
      this.cwd,
      { ...process.env, ...this.options.env },
      this.options.defaultTimeoutMs!,
    );

    await this.rpc.start();
    await this.rpc.setSessionName(this.name);
  }

  private buildPiArgs(): string[] {
    const args = ["--mode", "rpc", "--session-dir", this.sessionDir];

    if (this.options.provider) {
      args.push("--provider", this.options.provider);
    }
    if (this.options.model) {
      args.push("--model", this.options.model);
    }
    if (this.options.thinking) {
      args.push("--thinking", this.options.thinking);
    }
    if (this.options.systemPrompt?.trim()) {
      args.push("--system-prompt", this.options.systemPrompt.trim());
    }

    args.push("--append-system-prompt", buildTwinAppendSystemPrompt(this.options));

    const tools = this.options.tools?.filter(Boolean);
    if (tools && tools.length > 0) {
      args.push("--tools", tools.join(","));
    }

    if (this.options.disableExtensions) {
      args.push("--no-extensions");
    }
    for (const extension of this.options.extensions ?? []) {
      args.push("--extension", extension);
    }

    if (this.options.disableSkills) {
      args.push("--no-skills");
    }
    for (const skill of this.options.skills ?? []) {
      args.push("--skill", skill);
    }

    if (this.options.disablePromptTemplates) {
      args.push("--no-prompt-templates");
    }
    for (const promptTemplate of this.options.promptTemplates ?? []) {
      args.push("--prompt-template", promptTemplate);
    }

    return args;
  }

  private async invokeInternal(request: ProjectTwinInvokeRequest): Promise<ProjectTwinResult> {
    await this.start();

    const relayContext =
      this.options.autoLoadOpenScoutRelay === false ? undefined : await readOpenScoutRelayContext(this.cwd);
    const prompt = buildInvocationPrompt(this.name, this.cwd, request, relayContext);
    const events = await this.rpc!.promptAndWait(prompt, request.timeoutMs ?? this.options.defaultTimeoutMs);
    const [text, state] = await Promise.all([this.rpc!.getLastAssistantText(), this.rpc!.getState()]);

    return {
      text: text ?? "",
      state,
      events,
    };
  }
}

export function createProjectTwin(options: ProjectTwinOptions): ProjectTwin {
  return new ProjectTwin(options);
}
