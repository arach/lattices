// Lightweight WebSocket client for lattices daemon (ws://127.0.0.1:9399)
// Uses Node `net` module with manual HTTP upgrade + minimal WS framing.
// Zero npm dependencies.

import { createConnection, type Socket } from "node:net";
import { randomBytes } from "node:crypto";

const DAEMON_HOST = "127.0.0.1";
const DAEMON_PORT = 9399;

interface ParsedFrame {
  payload: string;
  rest: Buffer<ArrayBuffer>;
}

/**
 * Send a JSON-RPC-style request to the daemon and return the response.
 */
export async function daemonCall(
  method: string,
  params?: Record<string, unknown> | null,
  timeoutMs = 3000
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
        reject(new Error("Daemon request timed out"));
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
      // Send HTTP upgrade request
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
      buffer = Buffer.concat([buffer, chunk]) as Buffer<ArrayBuffer>;

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
        buffer = buffer.subarray(headerEnd + 4);

        // Send the request as a masked WebSocket text frame
        sendFrame(socket, request);
      }

      // The daemon can push broadcast events before the RPC response.
      // Keep consuming frames until we see our matching response id.
      while (true) {
        const result = parseFrame(buffer);
        if (!result) break;
        buffer = result.rest;

        try {
          const parsed = JSON.parse(result.payload);
          if (parsed.event) {
            continue;
          }
          if (parsed.id !== id) {
            continue;
          }
          if (!settled) {
            settled = true;
            cleanup();
            if (parsed.error) {
              reject(new Error(parsed.error));
            } else {
              resolve(parsed.result);
            }
          }
          return;
        } catch {
          if (!settled) {
            settled = true;
            cleanup();
            reject(new Error("Invalid JSON response from daemon"));
          }
          return;
        }
      }
    });
  });
}

/**
 * Check if the daemon is reachable.
 */
export async function isDaemonRunning(): Promise<boolean> {
  try {
    await daemonCall("daemon.status", null, 1000);
    return true;
  } catch {
    return false;
  }
}

// MARK: - WebSocket framing helpers

function sendFrame(socket: Socket, text: string): void {
  const payload = Buffer.from(text, "utf8");
  const mask = randomBytes(4);
  const len = payload.length;

  let header: Buffer;
  if (len < 126) {
    header = Buffer.alloc(2);
    header[0] = 0x81; // FIN + text opcode
    header[1] = 0x80 | len; // masked + length
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

  // Mask payload
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
    rest: buf.subarray(offset + payloadLen) as Buffer<ArrayBuffer>,
  };
}
