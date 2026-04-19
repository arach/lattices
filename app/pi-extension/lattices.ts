import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { createConnection, type Socket } from "node:net";
import { randomBytes } from "node:crypto";

const DAEMON_HOST = "127.0.0.1";
const DAEMON_PORT = 9399;

// ── Daemon client ──────────────────────────────────────────────

interface ParsedFrame {
  payload: string;
  rest: Buffer;
}

function sendFrame(socket: Socket, text: string): void {
  const payload = Buffer.from(text, "utf8");
  const mask = randomBytes(4);
  const len = payload.length;

  let header: Buffer;
  if (len < 126) {
    header = Buffer.alloc(2);
    header[0] = 0x81;
    header[1] = 0x80 | len;
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 0x80 | 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 0x80 | 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }

  const masked = Buffer.alloc(payload.length);
  for (let i = 0; i < payload.length; i++) {
    masked[i] = payload[i]! ^ mask[i % 4]!;
  }
  socket.write(Buffer.concat([header, mask, masked]));
}

function parseFrame(buf: Buffer): ParsedFrame | null {
  if (buf.length < 2) return null;
  const isMasked = (buf[1]! & 0x80) !== 0;
  let payloadLen = buf[1]! & 0x7f;
  let offset = 2;

  if (payloadLen === 126) {
    if (buf.length < 4) return null;
    payloadLen = buf.readUInt16BE(2);
    offset = 4;
  } else if (payloadLen === 127) {
    if (buf.length < 10) return null;
    payloadLen = Number(buf.readBigUInt64BE(2));
    offset = 10;
  }

  if (isMasked) offset += 4;
  if (buf.length < offset + payloadLen) return null;

  let payload = buf.subarray(offset, offset + payloadLen);
  if (isMasked) {
    const maskKey = buf.subarray(offset - 4, offset);
    payload = Buffer.alloc(payloadLen);
    for (let i = 0; i < payloadLen; i++) {
      payload[i] = buf[offset + i]! ^ maskKey[i % 4]!;
    }
  }

  return {
    payload: payload.toString("utf8"),
    rest: buf.subarray(offset + payloadLen) as Buffer,
  };
}

async function daemonCall(
  method: string,
  params?: Record<string, unknown> | null,
  timeoutMs = 5000
): Promise<unknown> {
  const id = randomBytes(4).toString("hex");
  const request = JSON.stringify({ id, method, params: params ?? null });

  return new Promise((resolve, reject) => {
    const socket = createConnection({ host: DAEMON_HOST, port: DAEMON_PORT });
    let settled = false;
    let buffer = Buffer.alloc(0);
    let upgraded = false;

    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        socket.destroy();
        reject(new Error(`Daemon request timed out (${method})`));
      }
    }, timeoutMs);

    const cleanup = () => {
      clearTimeout(timer);
      socket.destroy();
    };

    socket.on("error", (err) => {
      if (!settled) {
        settled = true;
        cleanup();
        reject(err);
      }
    });

    socket.on("connect", () => {
      const key = randomBytes(16).toString("base64");
      const upgrade = [
        `GET / HTTP/1.1`,
        `Host: ${DAEMON_HOST}:${DAEMON_PORT}`,
        `Upgrade: websocket`,
        `Connection: Upgrade`,
        `Sec-WebSocket-Key: ${key}`,
        `Sec-WebSocket-Version: 13`,
        ``,
        ``,
      ].join("\r\n");
      socket.write(upgrade);
    });

    socket.on("data", (chunk: Buffer) => {
      buffer = Buffer.concat([buffer, chunk]) as Buffer;

      if (!upgraded) {
        const headerEnd = buffer.indexOf("\r\n\r\n");
        if (headerEnd === -1) return;
        const header = buffer.subarray(0, headerEnd).toString();
        if (!header.includes("101")) {
          settled = true;
          cleanup();
          reject(new Error("WebSocket upgrade failed"));
          return;
        }
        upgraded = true;
        buffer = buffer.subarray(headerEnd + 4) as Buffer;
        sendFrame(socket, request);
      }

      while (true) {
        const result = parseFrame(buffer);
        if (!result) break;
        buffer = result.rest;

        try {
          const parsed = JSON.parse(result.payload);
          if (parsed.event) continue;
          if (parsed.id !== id) continue;
          if (!settled) {
            settled = true;
            cleanup();
            if (parsed.error) reject(new Error(parsed.error));
            else resolve(parsed.result);
          }
          return;
        } catch {
          if (!settled) {
            settled = true;
            cleanup();
            reject(new Error("Invalid JSON from daemon"));
          }
          return;
        }
      }
    });
  });
}

async function isDaemonRunning(): Promise<boolean> {
  try {
    await daemonCall("daemon.status", null, 1500);
    return true;
  } catch {
    return false;
  }
}

// ── Extension ──────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  // Inject Lattices context into every prompt
  pi.on("before_agent_start", async (event) => {
    let context = "";

    try {
      const [windows, tmux, projects, status] = await Promise.all([
        daemonCall("windows.list").catch(() => []),
        daemonCall("tmux.sessions").catch(() => []),
        daemonCall("projects.list").catch(() => []),
        daemonCall("daemon.status").catch(() => null),
      ]);

      const winList = windows as any[];
      const tmuxList = tmux as any[];
      const projList = projects as any[];

      if (winList?.length) {
        const summary = winList
          .slice(0, 30)
          .map((w: any) => {
            let line = `  ${w.app}: ${w.title}`;
            if (w.latticesSession) line += ` [session: ${w.latticesSession}]`;
            return line;
          })
          .join("\n");
        context += `\nCurrent windows (${winList.length} total):\n${summary}`;
      }

      if (tmuxList?.length) {
        const summary = tmuxList
          .map((s: any) => {
            let line = `  ${s.name} (${s.windowCount} windows${s.attached ? ", attached" : ""})`;
            if (s.panes?.length) {
              const paneInfo = s.panes
                .slice(0, 6)
                .map((p: any) => {
                  let desc = p.currentCommand || "shell";
                  if (p.children?.length) {
                    desc += " → " + p.children.map((c: any) => c.command).join(", ");
                  }
                  return desc;
                })
                .join("; ");
              line += ` [${paneInfo}]`;
            }
            return line;
          })
          .join("\n");
        context += `\n\nTmux sessions (${tmuxList.length}):\n${summary}`;
      }

      if (projList?.length) {
        const summary = projList
          .map((p: any) => {
            let line = `  ${p.name} (${p.path})`;
            if (p.isRunning) line += " [running]";
            return line;
          })
          .join("\n");
        context += `\n\nKnown projects (${projList.length}):\n${summary}`;
      }

      if (status) {
        const s = status as any;
        context += `\n\nDaemon: up ${Math.round(s.uptime)}s, ${s.windowCount} windows, ${s.tmuxSessionCount} tmux sessions`;
      }
    } catch {
      context += "\n\n[Daemon unavailable — live state not loaded]";
    }

    const systemPrompt =
      event.systemPrompt +
      `\n\n# Lattices workspace context\n` +
      `You are also the assistant for Lattices, a macOS developer workspace manager. ` +
      `You have tools to query the Lattices daemon for live desktop state — windows, tmux sessions, projects, and search. ` +
      `Use the lattices_* tools to answer questions about the user's workspace. ` +
      `Be specific and grounded: reference actual window titles, app names, and session names from the data.\n` +
      context;

    return { systemPrompt };
  });

  // ── Tools ────────────────────────────────────────────────────

  pi.registerTool({
    name: "lattices_search",
    label: "Lattices Search",
    description:
      "Search across all windows, terminal tabs, tmux sessions, and OCR content. " +
      "Returns windows matching the query with match sources and scores.",
    promptSnippet: "Search windows, terminals, and OCR by keyword",
    parameters: Type.Object({
      query: Type.String({ description: "Search text" }),
      sources: Type.Optional(
        Type.Array(Type.String(), {
          description:
            "Data sources: titles, apps, sessions, cwd, tabs, tmux, ocr, processes. Omit for smart default.",
        })
      ),
    }),
    async execute(_toolCallId, params) {
      const result = await daemonCall("lattices.search", {
        query: params.query,
        sources: params.sources,
      });
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        details: {},
      };
    },
  });

  pi.registerTool({
    name: "lattices_windows",
    label: "Lattices Windows",
    description:
      "List all windows currently known to Lattices, or get a specific window by ID.",
    promptSnippet: "List or get desktop windows",
    parameters: Type.Object({
      wid: Type.Optional(
        Type.Number({ description: "Window ID to get a specific window" })
      ),
    }),
    async execute(_toolCallId, params) {
      if (params.wid) {
        const result = await daemonCall("windows.get", { wid: params.wid });
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
          details: {},
        };
      }
      const result = await daemonCall("windows.list");
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        details: {},
      };
    },
  });

  pi.registerTool({
    name: "lattices_tmux",
    label: "Lattices Tmux",
    description:
      "List tmux sessions with pane details, running commands, and child processes.",
    promptSnippet: "List tmux sessions and pane activity",
    parameters: Type.Object({}),
    async execute() {
      const result = await daemonCall("tmux.sessions");
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        details: {},
      };
    },
  });

  pi.registerTool({
    name: "lattices_projects",
    label: "Lattices Projects",
    description:
      "List all discovered development projects with their paths, session names, and status.",
    promptSnippet: "List known development projects",
    parameters: Type.Object({}),
    async execute() {
      const result = await daemonCall("projects.list");
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        details: {},
      };
    },
  });

  pi.registerTool({
    name: "lattices_processes",
    label: "Lattices Processes",
    description:
      "List interesting developer processes (node, claude, python, etc.) with tmux/window linkage.",
    promptSnippet: "List developer processes with terminal linkage",
    parameters: Type.Object({
      command: Type.Optional(
        Type.String({
          description: "Filter by command name (e.g. 'claude', 'node')",
        })
      ),
    }),
    async execute(_toolCallId, params) {
      const callParams: Record<string, unknown> = {};
      if (params.command) callParams.command = params.command;
      const result = await daemonCall("processes.list", callParams);
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        details: {},
      };
    },
  });

  pi.registerTool({
    name: "lattices_status",
    label: "Lattices Status",
    description:
      "Get daemon status: uptime, connected clients, window count, tmux session count.",
    promptSnippet: "Check Lattices daemon health and stats",
    parameters: Type.Object({}),
    async execute() {
      const result = await daemonCall("daemon.status");
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        details: {},
      };
    },
  });

  pi.registerTool({
    name: "lattices_spaces",
    label: "Lattices Spaces",
    description: "List all displays and their macOS spaces/desktops.",
    promptSnippet: "List displays and spaces",
    parameters: Type.Object({}),
    async execute() {
      const result = await daemonCall("spaces.list");
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        details: {},
      };
    },
  });

  pi.registerTool({
    name: "lattices_layers",
    label: "Lattices Layers",
    description: "List workspace layers and the active layer index.",
    promptSnippet: "List workspace layers",
    parameters: Type.Object({}),
    async execute() {
      const result = await daemonCall("layers.list");
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        details: {},
      };
    },
  });
}
