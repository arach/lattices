#!/usr/bin/env bun

const port = Number(process.env.ACTION_CHROME_COMPANION_PORT || 4321);
const pending = new Map();
let extensionSocket = null;

const server = Bun.serve({
  port,
  async fetch(request, server) {
    const url = new URL(request.url);

    if (url.pathname === "/chrome-companion" && server.upgrade(request)) {
      return undefined;
    }

    if (url.pathname === "/health") {
      return json({
        ok: true,
        connected: extensionSocket?.readyState === WebSocket.OPEN,
        pending: pending.size,
      });
    }

    if (url.pathname === "/rpc" && request.method === "POST") {
      if (extensionSocket?.readyState !== WebSocket.OPEN) {
        return json({ ok: false, error: "Action Chrome Companion extension is not connected." }, 503);
      }

      const message = await request.json();
      const id = crypto.randomUUID();
      const response = await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          pending.delete(id);
          reject(new Error(`Timed out waiting for extension response to ${message.method}`));
        }, Number(process.env.ACTION_CHROME_COMPANION_TIMEOUT_MS || 30000));

        pending.set(id, {
          resolve(response) {
            clearTimeout(timeout);
            resolve(response);
          },
        });
        extensionSocket.send(JSON.stringify({ id, message }));
      }).catch((error) => ({ ok: false, error: error.message }));

      return json(response, response.ok === false ? 500 : 200);
    }

    return json({
      ok: true,
      service: "Action Chrome Companion Bridge",
      endpoints: ["GET /health", "POST /rpc", "WS /chrome-companion"],
    });
  },
  websocket: {
    open(socket) {
      extensionSocket = socket;
      console.log(`[bridge] extension connected on ws://127.0.0.1:${port}/chrome-companion`);
    },
    message(_socket, data) {
      let payload;
      try {
        payload = JSON.parse(String(data));
      } catch {
        return;
      }

      if (payload.type === "hello") {
        console.log(`[bridge] ${payload.name || "extension"} ready`);
        return;
      }

      const waiter = pending.get(payload.id);
      if (!waiter) {
        return;
      }

      pending.delete(payload.id);
      waiter.resolve(payload.response);
    },
    close(socket) {
      if (extensionSocket === socket) {
        extensionSocket = null;
        console.log("[bridge] extension disconnected");
      }
    },
  },
});

console.log(`[bridge] listening on http://127.0.0.1:${server.port}`);

function json(value, status = 200) {
  return new Response(`${JSON.stringify(value, null, 2)}\n`, {
    status,
    headers: { "content-type": "application/json" },
  });
}
