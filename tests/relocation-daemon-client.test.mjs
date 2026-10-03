import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:net";
import { once } from "node:events";
import { daemonCall, daemonTimeoutMs } from "../bin/daemon-client.ts";
import { runWindowMovement } from "../bin/cli/window.ts";

// Test-only ephemeral endpoint. No traffic reaches the everyday daemon.
async function fixture(t, handle) {
  const sockets = new Set();
  let requests = 0;
  const server = createServer(socket => {
    sockets.add(socket);
    socket.on("close", () => sockets.delete(socket));
    socket.on("error", () => {});
    let upgraded = false;
    let buffer = Buffer.alloc(0);
    socket.on("data", chunk => {
      buffer = Buffer.concat([buffer, chunk]);
      if (!upgraded) {
        const end = buffer.indexOf("\r\n\r\n");
        if (end < 0) return;
        buffer = buffer.subarray(end + 4);
        upgraded = true;
        socket.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n");
      }
      if (buffer.length < 6) return;
      let length = buffer[1] & 127, offset = 2;
      if (length === 126) { if (buffer.length < 8) return; length = buffer.readUInt16BE(2); offset = 4; }
      if (buffer.length < offset + 4 + length) return;
      const mask = buffer.subarray(offset, offset + 4);
      const data = Buffer.from(buffer.subarray(offset + 4, offset + 4 + length));
      for (let i = 0; i < data.length; i++) data[i] ^= mask[i % 4];
      buffer = buffer.subarray(offset + 4 + length);
      requests++;
      handle(JSON.parse(data.toString()), socket, value => {
        const data = Buffer.from(JSON.stringify(value));
        const header = data.length < 126 ? Buffer.from([0x81, data.length]) : Buffer.from([0x81, 126, data.length >> 8, data.length & 255]);
        if (!socket.destroyed) socket.write(Buffer.concat([header, data]));
      });
    });
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(async () => {
    for (const socket of sockets) socket.destroy();
    await new Promise(resolve => server.close(resolve));
  });
  return { endpoint: { host: "127.0.0.1", port: server.address().port }, count: () => requests };
}

test("relocation defaults allow staging and recovery; ordinary RPCs stay short", () => {
  for (const method of ["window.move", "window.place", "actions.undo", "actions.execute"])
    assert.equal(daemonTimeoutMs(method), 60_000);
  assert.equal(daemonTimeoutMs("daemon.status"), 3000);
});

test("delayed move response retains verified result after intervening event", async t => {
  const f = await fixture(t, (request, _socket, send) => {
    send({ event: "desktop.changed" });
    setTimeout(() => send({ id: request.id, result: { status: "ok", verified: true } }), 60);
  });
  assert.deepEqual(await daemonCall("window.move", { wid: 123 }, 1000, f.endpoint),
    { status: "ok", verified: true });
  assert.equal(f.count(), 1);
});

test("timeout reports uncertain outcome and never retries a mutation", async t => {
  const f = await fixture(t, () => {});
  await assert.rejects(daemonCall("window.move", { wid: 123 }, 100, f.endpoint),
    /timed out; the operation may still finish/);
  assert.equal(f.count(), 1);
});

test("daemon relocation errors are surfaced unchanged", async t => {
  const f = await fixture(t, (request, _socket, send) =>
    send({ id: request.id, error: "Source staging failed; original position unchanged" }));
  await assert.rejects(daemonCall("window.move", { wid: 123 }, 1000, f.endpoint), /Source staging failed/);
});

test("connection loss is not treated as successful move", async t => {
  const f = await fixture(t, (_request, socket) => socket.destroy());
  await assert.rejects(daemonCall("window.move", { wid: 123 }, 1000, f.endpoint), /closed before a response/);
});

test("movement CLI passes the long timeout and propagates errors", async () => {
  let seen;
  await assert.rejects(runWindowMovement("move", { wid: 123, display: 2, json: false, dryRun: false },
    async (...args) => { seen = args; throw new Error("fixture timeout"); }), /fixture timeout/);
  assert.deepEqual(seen, ["window.move", { wid: 123, display: 2 }, 60_000]);
});
