import type { JsonObject, JsonRpcRequest, ToolDefinition, Toolset } from "./types.ts";

const PROTOCOL_VERSION = "2025-06-18";

/**
 * The lattices MCP server: JSON-RPC framing over stdio, plus a table mapping
 * tool names to the toolset that owns them.
 *
 * Tool names are flat and unprefixed on purpose. `browser_open` is named in
 * standing agent instructions across several harnesses; the client-side prefix
 * (`mcp__lattices__`) is derived from the server name and is not something any
 * instruction refers to. Renaming tools to namespace them would silently
 * invalidate all of it.
 */
export class McpRouter {
  private readonly owners = new Map<string, Toolset>();
  private readonly toolList: ToolDefinition[] = [];
  private started = false;

  constructor(
    private readonly toolsets: readonly Toolset[],
    private readonly serverVersion: string,
  ) {
    for (const toolset of toolsets) {
      for (const tool of toolset.tools) {
        const existing = this.owners.get(tool.name);
        if (existing) {
          throw new Error(
            `Toolsets "${existing.name}" and "${toolset.name}" both define the tool "${tool.name}".`,
          );
        }
        this.owners.set(tool.name, toolset);
        this.toolList.push(tool);
      }
    }
  }

  get tools(): readonly ToolDefinition[] {
    return this.toolList;
  }

  private get instructions(): string {
    return this.toolsets.flatMap((toolset) => toolset.instructions ?? []).join("\n");
  }

  async start(): Promise<void> {
    if (this.started) return;
    this.started = true;
    for (const toolset of this.toolsets) {
      await toolset.init?.();
    }
  }

  /**
   * Release every toolset's resources, then hand back. Each toolset enforces its
   * own budget; one that hangs must not keep the others from releasing, so they
   * run concurrently rather than in sequence.
   */
  async shutdown(reason: string): Promise<void> {
    await Promise.all(this.toolsets.map((toolset) => toolset.shutdown?.(reason)));
  }

  shutdownSync(): void {
    for (const toolset of this.toolsets) {
      try {
        toolset.shutdownSync?.();
      } catch {
        // A failed release must not stop the next toolset from trying.
      }
    }
  }

  async callTool(name: string, args: JsonObject): Promise<JsonObject> {
    const toolset = this.owners.get(name);
    if (!toolset) throw new Error(`Unknown tool: ${name}`);
    toolset.onToolCall?.(name);
    return await toolset.callTool(name, args) as unknown as JsonObject;
  }

  async handleRequest(request: JsonRpcRequest): Promise<JsonObject | undefined> {
    const id = request.id;
    if (request.method.startsWith("notifications/") || id === undefined) {
      return undefined;
    }

    try {
      switch (request.method) {
        case "initialize":
          return {
            jsonrpc: "2.0",
            id,
            result: {
              protocolVersion: String(request.params?.protocolVersion ?? PROTOCOL_VERSION),
              capabilities: { tools: { listChanged: false } },
              serverInfo: { name: "lattices", version: this.serverVersion },
              instructions: this.instructions,
            },
          };
        case "ping":
          return { jsonrpc: "2.0", id, result: {} };
        case "tools/list":
          return { jsonrpc: "2.0", id, result: { tools: this.toolList } };
        case "tools/call": {
          const params = request.params ?? {};
          const name = params.name;
          if (typeof name !== "string" || !name) {
            throw new Error("tools/call requires a tool name.");
          }
          const args = params.arguments && typeof params.arguments === "object"
            ? params.arguments as JsonObject
            : {};
          return { jsonrpc: "2.0", id, result: await this.callTool(name, args) };
        }
        default:
          return {
            jsonrpc: "2.0",
            id,
            error: { code: -32601, message: `Method not found: ${request.method}` },
          };
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      // A failed tool call is a result the agent can read and recover from, not a
      // protocol error that leaves it guessing.
      if (request.method === "tools/call") {
        return {
          jsonrpc: "2.0",
          id,
          result: {
            isError: true,
            content: [{ type: "text", text: JSON.stringify({ ok: false, error: message }, null, 2) }],
            structuredContent: { ok: false, error: message },
          },
        };
      }
      return { jsonrpc: "2.0", id, error: { code: -32603, message } };
    }
  }

  /** Read newline-delimited JSON-RPC off a stream until it ends. */
  async serve(stream: ReadableStream<Uint8Array>, write: (line: string) => void): Promise<void> {
    let buffer = "";
    const decoder = new TextDecoder();
    for await (const chunk of stream) {
      buffer += decoder.decode(chunk, { stream: true });
      while (buffer.includes("\n")) {
        const newline = buffer.indexOf("\n");
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        if (!line) continue;
        const request = JSON.parse(line) as JsonRpcRequest;
        const response = await this.handleRequest(request);
        if (response) write(`${JSON.stringify(response)}\n`);
      }
    }
  }
}
