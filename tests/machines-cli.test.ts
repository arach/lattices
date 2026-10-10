import { expect, test } from "bun:test";
import { resolve } from "node:path";

test("Machines CLI routes mutations to an isolated mock daemon", async () => {
  const requests: { method: string; params: unknown }[] = [];
  const server = Bun.serve({
    hostname: "127.0.0.1", port: 0,
    fetch(request, server) {
      if (server.upgrade(request)) return;
      return new Response("WebSocket required", { status: 400 });
    },
    websocket: {
      message(ws, data) {
        const request = JSON.parse(String(data));
        requests.push(request);
        ws.send(JSON.stringify({ id: request.id, result: { ok: true, kept: true, sharing: true } }));
      },
    },
  });
  try {
    for (const [args, method, params] of [
      [["visit", "side", "fixture", "left"], "visit.side", { host: "fixture", side: "left" }],
      [["visit", "forget", "fixture"], "visit.forget", { host: "fixture" }],
      [["mouse", "stop"], "mouse.stop", null],
      [["mouse", "share"], "mouse.share", {}],
      [["mouse", "keep"], "mouse.keep", null],
    ] as const) {
      requests.length = 0;
      const proc = Bun.spawn([process.execPath, resolve("bin/lattices.ts"), ...args], {
        env: { ...process.env, LATTICES_DAEMON_HOST: "127.0.0.1", LATTICES_DAEMON_PORT: String(server.port) },
        stdout: "pipe", stderr: "pipe",
      });
      expect(await proc.exited).toBe(0);
      expect(requests.map(r => r.method)).toEqual(["daemon.status", method]);
      expect(requests[1].params).toEqual(params);
    }
    requests.length = 0;
    const invalid = Bun.spawn([process.execPath, resolve("bin/lattices.ts"), "visit", "side", "fixture", "diagonal"], {
      env: { ...process.env, LATTICES_DAEMON_HOST: "127.0.0.1", LATTICES_DAEMON_PORT: String(server.port) },
      stdout: "pipe", stderr: "pipe",
    });
    await invalid.exited;
    expect(requests.map(r => r.method)).toEqual(["daemon.status"]);
    expect(await new Response(invalid.stdout).text()).toContain("Usage:");
  } finally { server.stop(true); }
}, 20000);
