import { expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const latticesVersion = (JSON.parse(
  readFileSync(join(import.meta.dir, "../../package.json"), "utf8"),
) as { version: string }).version;

// Fake CDP transport only: these tests never launch or connect to real Chrome.
for (const stalledPhase of ["health", "navigate", "readiness", "none"] as const) {
  test(`lattices mcp browser_open bounds ${stalledPhase}`, async () => {
    const directory = await mkdtemp(join(tmpdir(), "action-browser-test-"));
    const server = Bun.serve({ port: 0, hostname: "127.0.0.1",
      async fetch(request, server) {
        const path = new URL(request.url).pathname;
        if (path === "/devtools/page/test") { if (server.upgrade(request)) return; }
        if (stalledPhase === "health") return new Promise<Response>(() => {});
        if (path === "/json/version") return Response.json({ Browser: "Fake CDP" });
        const target = { id: "test", type: "page", title: "Test", url: "https://example.com/", webSocketDebuggerUrl: `ws://127.0.0.1:${server.port}/devtools/page/test` };
        if (path === "/json/new") return Response.json(target);
        if (path === "/json/list") return Response.json([target]);
        return Response.json({});
      },
      websocket: { message(ws, raw) {
        const request = JSON.parse(String(raw));
        if (stalledPhase === "navigate" && request.method === "Page.navigate") return;
        if (stalledPhase === "readiness" && request.method === "Runtime.evaluate") return;
        const result = request.method === "Page.getFrameTree" ? { frameTree: { frame: {} } }
          : request.method === "Runtime.evaluate" ? { result: { value: { readyState: "complete", documentUrl: "https://example.com/", title: "Test" } } } : {};
        ws.send(JSON.stringify({ id: request.id, result }));
      } },
    });
    const child = Bun.spawn([process.execPath, join(import.meta.dir, "server.ts"), "--toolsets", "browser"], {
      stdin: "pipe", stdout: "pipe", stderr: "pipe",
      env: { ...process.env, ACTION_BROWSER_DEBUG_PORT: String(server.port), ACTION_BROWSER_PROFILE_ROOT: directory,
        ACTION_BROWSER_SESSION_DIR: join(directory, "sessions"), ACTION_BROWSER_IDLE_TIMEOUT_MS: "0" },
    });
    const reader = child.stdout.getReader();
    let buffer = "";
    const next = async () => {
      while (!buffer.includes("\n")) { const chunk = await reader.read(); if (chunk.done) throw new Error("MCP exited"); buffer += new TextDecoder().decode(chunk.value); }
      const end = buffer.indexOf("\n"); const line = buffer.slice(0, end); buffer = buffer.slice(end + 1); return JSON.parse(line);
    };
    const send = (id: number, method: string, params = {}) => child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    try {
      send(1, "initialize");
      // The server identifies as lattices, at the lattices version. Nothing here
      // is pinned to a plugin version any more -- that pinning is what broke.
      const initialize = (await next()).result;
      expect(initialize.serverInfo.name).toBe("lattices");
      expect(initialize.serverInfo.version).toBe(latticesVersion);
      expect(initialize.instructions).toContain("Action Browser");
      send(2, "tools/list");
      expect((await next()).result.tools.find((tool: { name: string }) => tool.name === "browser_open").inputSchema.properties.mode).toBeDefined();
      const started = performance.now();
      send(3, "tools/call", { name: "browser_open", arguments: { url: "https://example.com/", waitMs: 200 } });
      const reply = await next();
      expect(performance.now() - started).toBeLessThan(700);
      if (stalledPhase === "none") expect(reply.result.structuredContent.ok).toBe(true);
      else {
        expect(reply.result.isError).toBe(true);
        expect(reply.result.structuredContent.error).toContain("timed out");
      }
      send(4, "ping");
      expect((await next()).id).toBe(4);
    } finally {
      // Only stop our isolated test process; no shared browser/services involved.
      child.kill();
      server.stop(true);
      await child.exited;
      await rm(directory, { recursive: true, force: true });
    }
  }, 5000);
}
