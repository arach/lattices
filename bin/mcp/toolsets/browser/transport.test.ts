import { describe, expect, test } from "bun:test";
import { CDPSession, boundedWait, deadlineFetchJson, deadlineSleep, withDeadline } from "./transport.ts";

describe("browser operation deadlines", () => {
  test("zero budget does not start work", async () => {
    let started = false;
    await expect(withDeadline(0, "browser_open", async () => { started = true; })).rejects.toThrow("timed out");
    expect(started).toBe(false);
  });

  test("one budget covers successive steps and prevents late continuation", async () => {
    let late = false;
    const started = performance.now();
    await expect(withDeadline(60, "browser_open", async () => {
      await deadlineSleep(35);
      await deadlineSleep(35);
      late = true;
    })).rejects.toThrow("browser_open timed out");
    expect(performance.now() - started).toBeLessThan(200);
    await Bun.sleep(60);
    expect(late).toBe(false);
  });

  test("standalone I/O has its own bound and cancels on timeout", async () => {
    let cancelled = false;
    await expect(boundedWait(new Promise(() => {}), "I/O", () => { cancelled = true; }, 20)).rejects.toThrow("I/O timed out");
    expect(cancelled).toBe(true);
  });

  test("HTTP budget includes a response body that never finishes", async () => {
    const server = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch() {
      return new Response(new ReadableStream({ start(controller) { controller.enqueue(new TextEncoder().encode("{")); } }));
    } });
    try {
      await expect(withDeadline(50, "browser_open", () => deadlineFetchJson(server.url.href))).rejects.toThrow("timed out");
    } finally { server.stop(true); }
  });

  test("unanswered CDP command closes socket; a new session still works", async () => {
    let closed = 0;
    const server = Bun.serve({ port: 0, hostname: "127.0.0.1",
      fetch(request, server) { if (server.upgrade(request)) return; return new Response("bad", { status: 400 }); },
      websocket: {
        message(ws, raw) { const request = JSON.parse(String(raw)); if (request.method === "ping") ws.send(JSON.stringify({ id: request.id, result: { ok: true } })); },
        close() { closed++; },
      },
    });
    const url = server.url.href.replace("http:", "ws:");
    try {
      await expect(withDeadline(50, "browser_open", async () => {
        const session = await CDPSession.connect(url);
        await session.call("Page.navigate");
      })).rejects.toThrow("timed out");
      await Bun.sleep(30);
      expect(closed).toBe(1);
      const session = await CDPSession.connect(url);
      try { expect(await session.call("ping")).toEqual({ ok: true }); } finally { session.close(); }
    } finally { server.stop(true); }
  });
});
