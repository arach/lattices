import { randomBytes } from "node:crypto";
import { createConnection } from "node:net";

const DEFAULT_DAEMON_HOST = "127.0.0.1";
const DEFAULT_DAEMON_PORT = 9399;
const DEFAULT_TIMEOUT_MS = 3000;

export function daemonConfig(overrides = {}) {
  const host = overrides.host ?? process.env.LATTICES_DAEMON_HOST ?? DEFAULT_DAEMON_HOST;
  const rawPort = overrides.port ?? process.env.LATTICES_DAEMON_PORT ?? DEFAULT_DAEMON_PORT;
  const rawTimeout = overrides.timeoutMs ?? process.env.LATTICES_DAEMON_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS;
  const port = Number(rawPort);
  const timeoutMs = Number(rawTimeout);

  return {
    host,
    port: Number.isFinite(port) && port > 0 ? port : DEFAULT_DAEMON_PORT,
    timeoutMs: Number.isFinite(timeoutMs) && timeoutMs > 0 ? timeoutMs : DEFAULT_TIMEOUT_MS,
  };
}

export async function daemonCall(method, params = null, options = {}) {
  const { host, port, timeoutMs } = daemonConfig(options);
  const id = randomBytes(4).toString("hex");
  const request = JSON.stringify({ id, method, params: params ?? null });

  return new Promise((resolve, reject) => {
    const socket = createConnection({ host, port });
    let settled = false;
    let upgraded = false;
    let buffer = Buffer.alloc(0);

    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        socket.destroy();
        const error = new Error(`Daemon request timed out after ${timeoutMs}ms`);
        error.code = "LATTICES_DAEMON_TIMEOUT";
        reject(error);
      }
    }, timeoutMs);

    const cleanup = () => {
      clearTimeout(timer);
      socket.destroy();
    };

    socket.on("error", (error) => {
      if (!settled) {
        settled = true;
        cleanup();
        reject(error);
      }
    });

    socket.on("connect", () => {
      const key = randomBytes(16).toString("base64");
      const upgrade = [
        "GET / HTTP/1.1",
        `Host: ${host}:${port}`,
        "Upgrade: websocket",
        "Connection: Upgrade",
        `Sec-WebSocket-Key: ${key}`,
        "Sec-WebSocket-Version: 13",
        "",
        "",
      ].join("\r\n");
      socket.write(upgrade);
    });

    socket.on("data", (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);

      if (!upgraded) {
        const headerEnd = buffer.indexOf("\r\n\r\n");
        if (headerEnd === -1) return;

        const header = buffer.subarray(0, headerEnd).toString();
        if (!header.includes("101")) {
          settled = true;
          cleanup();
          const error = new Error("WebSocket upgrade failed");
          error.code = "LATTICES_DAEMON_UPGRADE";
          reject(error);
          return;
        }

        upgraded = true;
        buffer = buffer.subarray(headerEnd + 4);
        sendFrame(socket, request);
      }

      while (true) {
        const parsedFrame = parseFrame(buffer);
        if (!parsedFrame) break;
        buffer = parsedFrame.rest;

        try {
          const parsed = JSON.parse(parsedFrame.payload);
          if (parsed.event || parsed.id !== id) continue;

          if (!settled) {
            settled = true;
            cleanup();
            if (parsed.error) {
              const error = new Error(parsed.error);
              error.code = "LATTICES_DAEMON_ERROR";
              reject(error);
            } else {
              resolve(parsed.result);
            }
          }
          return;
        } catch {
          if (!settled) {
            settled = true;
            cleanup();
            const error = new Error("Invalid JSON response from Lattices daemon");
            error.code = "LATTICES_DAEMON_INVALID_JSON";
            reject(error);
          }
          return;
        }
      }
    });
  });
}

export function isDaemonUnavailable(error) {
  const code = error?.code;
  return code === "ECONNREFUSED"
    || code === "ECONNRESET"
    || code === "EHOSTUNREACH"
    || code === "ENETUNREACH"
    || code === "ETIMEDOUT"
    || code === "LATTICES_DAEMON_TIMEOUT"
    || code === "LATTICES_DAEMON_UPGRADE";
}

function sendFrame(socket, text) {
  const payload = Buffer.from(text, "utf8");
  const mask = randomBytes(4);
  const len = payload.length;

  let header;
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
  for (let i = 0; i < payload.length; i += 1) {
    masked[i] = payload[i] ^ mask[i % 4];
  }

  socket.write(Buffer.concat([header, mask, masked]));
}

function parseFrame(buf) {
  if (buf.length < 2) return null;

  const isMasked = (buf[1] & 0x80) !== 0;
  let payloadLen = buf[1] & 0x7f;
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
    for (let i = 0; i < payloadLen; i += 1) {
      payload[i] = buf[offset + i] ^ maskKey[i % 4];
    }
  }

  return {
    payload: payload.toString("utf8"),
    rest: buf.subarray(offset + payloadLen),
  };
}
