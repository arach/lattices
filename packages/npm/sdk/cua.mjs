import { randomBytes } from "node:crypto";
import { createConnection } from "node:net";

import { z } from "zod";

const DAEMON_HOST = "127.0.0.1";
const DAEMON_PORT = 9399;

export const computerTreatmentSchema = z.enum([
  "observe",
  "stage",
  "present",
  "execute",
]);

export const computerClickTransportSchema = z.enum([
  "auto",
  "ax",
  "accessibility",
  "pointer",
  "mouse",
  "hardware",
]);

export const cursorStyleSchema = z.enum(["spotlight", "pulse", "marker"]);
export const cursorShapeSchema = z.enum([
  "arrow",
  "chevron",
  "facet",
  "shard",
  "wedge",
  "prism",
  "notch",
  "needle",
  "petal",
  "kite",
]);
export const cursorSizeSchema = z.enum(["tiny", "small", "regular", "large"]);
export const cursorTrailSchema = z.enum(["none", "thread", "ribbon", "spark", "comet", "route"]);
export const cursorMotionSchema = z.enum([
  "glide",
  "snap",
  "float",
  "rush",
  "crawl",
  "accelerate",
  "teleport",
  "spring",
  "magnet",
  "slingshot",
]);
export const cursorTrajectorySchema = z.enum(["straight", "soft", "arc", "swoop", "overshoot"]);
export const cursorGlowSchema = z.enum(["none", "soft", "halo", "comet"]);
export const cursorIdleSchema = z.enum([
  "still",
  "breathe",
  "wiggle",
  "orbit",
  "hover",
  "nod",
  "drift",
  "shimmer",
  "blink",
  "tremble",
]);
export const cursorEdgeSchema = z.enum([
  "none",
  "pulse",
  "ripple",
  "tick",
  "reticle",
  "blink",
  "spark",
  "underline",
  "echo",
  "scan",
  "pin",
]);
export const cursorSoundSchema = z.enum(["none", "tick", "click", "engage", "chime"]);
export const captionPlacementSchema = z.enum([
  "top-left",
  "top-right",
  "bottom-left",
  "bottom-right",
  "top-center",
  "top",
  "center",
  "middle",
  "near-cursor",
  "cursor",
]);

const ratioSchema = z.number().min(0).max(1);
const pointSchema = z.number().finite();

const windowTargetSchema = z.object({
  wid: z.number().int().positive().optional(),
  app: z.string().min(1).optional(),
  title: z.string().optional(),
});

const actionBaseSchema = z.object({
  treatment: computerTreatmentSchema.optional(),
  dryRun: z.boolean().optional(),
  capture: z.boolean().optional(),
  source: z.string().optional(),
});

const pointTargetSchema = z.object({
  x: pointSchema.optional(),
  y: pointSchema.optional(),
  xRatio: ratioSchema.optional(),
  yRatio: ratioSchema.optional(),
});

const cursorAppearanceSchema = z.object({
  style: cursorStyleSchema.optional(),
  appearance: cursorStyleSchema.optional(),
  shape: cursorShapeSchema.optional(),
  angleDeg: z.number().finite().optional(),
  size: cursorSizeSchema.optional(),
  color: z.string().min(1).optional(),
  durationMs: z.number().int().positive().optional(),
  label: z.string().optional(),
  caption: z.string().optional(),
  captionTitle: z.string().optional(),
  captionBody: z.string().optional(),
  captionDetail: z.string().optional(),
  captionTags: z.string().optional(),
  captionMode: z.enum(["auto", "selection"]).optional(),
  captionEyebrow: z.string().optional(),
  captionLeadMs: z.number().finite().nonnegative().optional(),
  captionSound: cursorSoundSchema.optional(),
  captionPlacement: captionPlacementSchema.optional(),
  captionMargin: z.number().finite().nonnegative().optional(),
  captionX: z.number().finite().optional(),
  captionY: z.number().finite().optional(),
  captionXRatio: ratioSchema.optional(),
  captionYRatio: ratioSchema.optional(),
  captionLeftRatio: ratioSchema.optional(),
  captionTopRatio: ratioSchema.optional(),
  sound: cursorSoundSchema.optional(),
  sfx: cursorSoundSchema.optional(),
  showCaption: z.boolean().optional(),
  captionSelections: z.boolean().optional(),
  treatmentLabel: z.string().optional(),
  variant: z.string().optional(),
  trail: cursorTrailSchema.optional(),
  pathStyle: cursorTrailSchema.optional(),
  motion: cursorMotionSchema.optional(),
  trajectory: cursorTrajectorySchema.optional(),
  glow: cursorGlowSchema.optional(),
  bloom: cursorGlowSchema.optional(),
  idle: cursorIdleSchema.optional(),
  settle: cursorIdleSchema.optional(),
  presence: cursorIdleSchema.optional(),
  edge: cursorEdgeSchema.optional(),
  edgeEffect: cursorEdgeSchema.optional(),
  arrival: cursorEdgeSchema.optional(),
  typewriter: z.boolean().optional(),
  typing: z.boolean().optional(),
  typeIntervalMs: z.number().finite().positive().optional(),
  typingIntervalMs: z.number().finite().positive().optional(),
});

export const computerClickParamsSchema = windowTargetSchema
  .merge(pointTargetSchema)
  .merge(actionBaseSchema)
  .merge(cursorAppearanceSchema.pick({ label: true }))
  .extend({
    button: z.enum(["left", "right", "secondary", "context"]).optional(),
    transport: computerClickTransportSchema.optional(),
    axLabel: z.string().min(1).optional(),
    targetText: z.string().min(1).optional(),
    noFocus: z.boolean().optional(),
  });

export const computerMagicCursorParamsSchema = windowTargetSchema
  .merge(pointTargetSchema)
  .merge(actionBaseSchema)
  .merge(cursorAppearanceSchema)
  .extend({
    text: z.string().optional(),
    append: z.boolean().optional(),
    fromX: pointSchema.optional(),
    fromY: pointSchema.optional(),
    fromXRatio: ratioSchema.optional(),
    fromYRatio: ratioSchema.optional(),
  });

export function createCuaClient(options = {}) {
  const defaultTimeoutMs = options.defaultTimeoutMs ?? 30_000;

  async function call(method, params, timeoutMs = defaultTimeoutMs) {
    return daemonCall(method, params, timeoutMs);
  }

  return {
    click(params) {
      return call("computer.click", computerClickParamsSchema.parse(params));
    },
    magicCursor(params) {
      return call("computer.magicCursor", computerMagicCursorParamsSchema.parse(params));
    },
  };
}

export const cua = createCuaClient();

export function click(params) {
  return cua.click(params);
}

export function magicCursor(params) {
  return cua.magicCursor(params);
}

async function daemonCall(method, params = null, timeoutMs = 3000) {
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
      const key = randomBytes(16).toString("base64");
      const upgrade = [
        "GET / HTTP/1.1",
        `Host: ${DAEMON_HOST}:${DAEMON_PORT}`,
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
          reject(new Error("WebSocket upgrade failed"));
          return;
        }
        upgraded = true;
        buffer = buffer.subarray(headerEnd + 4);
        sendFrame(socket, request);
      }

      while (true) {
        const result = parseFrame(buffer);
        if (!result) break;
        buffer = result.rest;

        try {
          const parsed = JSON.parse(result.payload);
          if (parsed.event || parsed.id !== id) continue;
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
  for (let i = 0; i < payload.length; i++) {
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
    for (let i = 0; i < payloadLen; i++) {
      payload[i] = buf[offset + i] ^ maskKey[i % 4];
    }
  }

  return {
    payload: payload.toString("utf8"),
    rest: buf.subarray(offset + payloadLen),
  };
}
