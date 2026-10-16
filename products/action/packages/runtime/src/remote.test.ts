import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import type { Duplex } from "node:stream";
import { after, before, describe, test } from "node:test";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { RemoteEngine, remoteEngineFromEnv } from "./remote.js";

// A fake lattices host: records every call and answers like lattices-host.
const calls: { method: string; params: Record<string, unknown> }[] = [];
const PNG = Buffer.from("fake-png");
const VIDEO = Buffer.alloc(40_000, 7);

function answer(method: string, params: Record<string, any>): unknown {
  switch (method) {
    case "host.describe":
      return { platform: "linux", hostname: "acrhie", tailnetName: "archie", capabilities: ["capture.still", "input.keys", "input.pointer", "ocr"] };
    case "windows.list":
      return [
        { wid: 7, app: "foot", title: "notes", frame: { x: 10, y: 20, w: 300, h: 200 }, isFocused: true, displayIndex: 0 },
        { wid: 9, app: "firefox", title: "docs", frame: { x: 400, y: 20, w: 800, h: 600 }, isFocused: false, displayIndex: 0 },
      ];
    case "spaces.list":
      return [{ displayIndex: 0, frame: { x: 0, y: 0, w: 2000, h: 1000 }, visibleFrame: { x: 0, y: 0, w: 2000, h: 1000 } }];
    case "windows.place":
      return { after: { x: 500, y: 200, w: 1000, h: 600 } };
    case "ocr.find":
      return params.text === "Save"
        ? { matches: [{ text: "Save", confidence: 0.9, bounds: { x: 100, y: 50, w: 40, h: 20 }, point: { x: 120, y: 60 } }, { text: "Save as", confidence: 0.8, bounds: { x: 0, y: 0, w: 1, h: 1 }, point: { x: 0, y: 0 } }] }
        : { matches: [] };
    case "capture.screenshotRegion":
    case "capture.screenshotWindow":
    case "capture.screenshotDisplay":
      return { data: PNG.toString("base64"), width: 2, height: 2, path: "/remote/shot.png" };
    case "capture.record":
      return params.action === "stop" ? { path: "/remote/rec.mov", frames: 12, fps: 6, seconds: 2 } : { recording: true };
    case "files.read": {
      const offset = params.offset ?? 0;
      const chunk = VIDEO.subarray(offset, offset + 16_000);
      return { data: chunk.toString("base64"), length: chunk.length, eof: offset + chunk.length >= VIDEO.length };
    }
    case "apps.open":
      return { window: { wid: 11, app: "foot", title: "new", frame: { x: 0, y: 0, w: 10, h: 10 }, isFocused: false, displayIndex: 0 } };
    case "computer.pressKey":
    case "computer.click":
    case "computer.typeText":
    case "computer.drag":
    case "computer.scroll":
    case "windows.focus":
      return { ok: true };
    default:
      throw new Error(`Unknown method: ${method}`);
  }
}

// Minimal WebSocket server: text frames only, enough for the daemon protocol.
function wsFrame(text: string): Buffer {
  const payload = Buffer.from(text);
  const len = payload.length;
  const header = len < 126 ? Buffer.from([0x81, len]) : len < 65536 ? Buffer.from([0x81, 126, len >> 8, len & 255]) : (() => {
    const h = Buffer.alloc(10);
    h[0] = 0x81;
    h[1] = 127;
    h.writeBigUInt64BE(BigInt(len), 2);
    return h;
  })();
  return Buffer.concat([header, payload]);
}

function onFrames(socket: Duplex, handle: (text: string) => void) {
  let buf = Buffer.alloc(0);
  socket.on("data", (chunk: Buffer) => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      if (buf.length < 2) return;
      let len = buf[1] & 127;
      let off = 2;
      if (len === 126) {
        if (buf.length < 4) return;
        len = buf.readUInt16BE(2);
        off = 4;
      } else if (len === 127) {
        if (buf.length < 10) return;
        len = Number(buf.readBigUInt64BE(2));
        off = 10;
      }
      if (buf.length < off + 4 + len) return;
      const mask = buf.subarray(off, off + 4);
      const data = Buffer.from(buf.subarray(off + 4, off + 4 + len).map((b, i) => b ^ mask[i % 4]));
      const opcode = buf[0] & 15;
      buf = buf.subarray(off + 4 + len);
      if (opcode === 1) handle(data.toString());
      if (opcode === 8) socket.end();
    }
  });
}

let server: Server;
let engine: RemoteEngine;
let dir: string;

before(async () => {
  server = createServer();
  server.on("upgrade", (req, socket) => {
    const accept = createHash("sha1").update(`${req.headers["sec-websocket-key"]}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`).digest("base64");
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    onFrames(socket, (text) => {
      const req = JSON.parse(text);
      calls.push({ method: req.method, params: req.params });
      try {
        socket.write(wsFrame(JSON.stringify({ id: req.id, result: answer(req.method, req.params), error: null })));
      } catch (err) {
        socket.write(wsFrame(JSON.stringify({ id: req.id, result: null, error: (err as Error).message })));
      }
    });
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", () => r()));
  engine = new RemoteEngine({ host: "127.0.0.1", port: (server.address() as AddressInfo).port });
  dir = await mkdtemp(join(tmpdir(), "remote-engine-"));
});

after(() => {
  engine.close();
  server.closeAllConnections();
  server.close();
});

const last = (method: string) => [...calls].reverse().find((c) => c.method === method)?.params;

describe("RemoteEngine", () => {
  test("diagnostics map host capabilities onto the permission fields", async () => {
    const d = await engine.diagnostics();
    assert.partialDeepStrictEqual(d, { accessibility: "granted", screenRecording: "granted", platform: "linux", host: "archie" });
  });

  test("current surface is the focused remote window", async () => {
    const cs = await engine.currentSurface();
    assert.deepEqual(cs.surface, { id: "remote:wid:7", kind: "window", label: "foot — notes", bounds: { x: 10, y: 20, width: 300, height: 200 } });
  });

  test("text targets resolve through OCR on the target surface", async () => {
    const t = await engine.resolveTarget({ text: "Save", surfaceId: "remote:wid:9" });
    assert.partialDeepStrictEqual(t, { mode: "textual", point: { x: 120, y: 60 }, confidence: 0.9, ambiguousWith: ["Save as"] });
    assert.deepEqual(last("ocr.find"), { text: "Save", wid: 9 });
    assert.equal((await engine.resolveTarget({ text: "Nope" })).confidence, 0);
    assert.equal((await engine.resolveTarget({ point: { x: 1, y: 2 } })).mode, "coordinate");
  });

  test("actions become executed computer.* calls", async () => {
    await engine.performAction({ id: "1", kind: "click", description: "", target: { text: "Save" } });
    assert.deepEqual(last("computer.click"), { x: 120, y: 60, count: 1, button: "left", treatment: "execute" });

    await engine.performAction({ id: "2", kind: "press-key", description: "", input: { key: "cmd+shift+p" } });
    assert.partialDeepStrictEqual(last("computer.pressKey"), { key: "p", treatment: "execute" });
    assert.deepEqual((last("computer.pressKey")!.modifiers as string[]).sort(), ["command", "shift"]);

    await engine.performAction({ id: "3", kind: "drag", description: "", input: { from: { x: 1, y: 2 }, to: { x: 3, y: 4 } } });
    assert.deepEqual(last("computer.drag"), { fromX: 1, fromY: 2, toX: 3, toY: 4, treatment: "execute" });

    await engine.performAction({ id: "4", kind: "type", description: "", input: { text: "hi" } });
    assert.deepEqual(last("computer.typeText"), { text: "hi", treatment: "execute" });
  });

  test("a centered viewport places the surface by fractions and keeps the real frame", async () => {
    await engine.focusSurface("remote:wid:9");
    const vp = await engine.configureViewport({ id: "v", bounds: { x: 0, y: 0, width: 1000, height: 600 }, dimming: "none", placement: "centered-safe" });
    assert.deepEqual(last("windows.place"), { wid: 9, display: 0, placement: { kind: "fractions", x: 0.25, y: 0.2, w: 0.5, h: 0.6 } });
    assert.deepEqual(vp.bounds, { x: 500, y: 200, width: 1000, height: 600 });
  });

  test("screenshots and recordings land at the local paths the session asked for", async () => {
    const shot = await engine.captureScreenshot(join(dir, "a.png"));
    assert.deepEqual(await readFile(shot.path), PNG);
    assert.partialDeepStrictEqual(last("capture.screenshotRegion"), { x: 500, y: 200, width: 1000, height: 600, inline: true });

    await engine.startCapture({ sessionId: "s", outputPath: join(dir, "run.mov") });
    assert.partialDeepStrictEqual(last("capture.record"), { action: "start", format: "mov" });
    const video = await engine.stopCapture();
    assert.equal(video.kind, "raw-capture");
    assert.equal((await readFile(video.path)).equals(VIDEO), true);
    assert.equal(calls.filter((c) => c.method === "files.read").length, 3);
  });

  test("open-app launches a command, not a bundle id", async () => {
    await engine.performAction({ id: "5", kind: "open-app", description: "", input: { app: "Foot" } });
    assert.partialDeepStrictEqual(last("apps.open"), { command: "foot" });
  });

  test("macOS-only surfaces are absent, not faked", () => {
    assert.equal(engine.platform, "remote");
    assert.equal("captureSurfaceAccessibilitySnapshot" in engine, false);
  });
});

describe("remoteEngineFromEnv", () => {
  test("reads host and port, and is off by default", () => {
    assert.equal(remoteEngineFromEnv({}), undefined);
    const e = remoteEngineFromEnv({ ACTION_REMOTE_HOST: "archie:9400" })!;
    assert.equal(e.client.url, "ws://archie:9400");
  });
});
