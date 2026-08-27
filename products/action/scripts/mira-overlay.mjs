#!/usr/bin/env bun

import { randomBytes } from "node:crypto";
import { copyFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { createConnection } from "node:net";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";

const DAEMON_HOST = "127.0.0.1";
const DAEMON_PORT = 9399;
const ACTOR_ID = "action-mira";
const PET_ID = "mira";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "..");
const sourceMetadataPath = join(repoRoot, "assets/pets/mira/pet.json");
const sourceSpritesheetPath = join(
  repoRoot,
  "assets/pets/explorer-cat/sprites/explorer-cat.sheet.webp"
);
const installedPetRoot = join(homedir(), ".codex/pets/mira");

const [command = "show", ...rest] = process.argv.slice(2);

try {
  switch (command) {
    case "install":
      await installMiraPet();
      console.log(JSON.stringify({ ok: true, petRoot: installedPetRoot }, null, 2));
      break;
    case "show":
      await installMiraPet();
      await assertLatticesDaemon();
      console.log(JSON.stringify(await showMira(rest.join(" ").trim()), null, 2));
      break;
    case "hide":
      await assertLatticesDaemon();
      console.log(JSON.stringify(await hideMira(), null, 2));
      break;
    case "move":
      await assertLatticesDaemon();
      console.log(JSON.stringify(await moveMira(rest), null, 2));
      break;
    case "status":
      console.log(JSON.stringify(await daemonCall("daemon.status"), null, 2));
      break;
    default:
      printUsageAndExit();
  }
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
}

async function installMiraPet() {
  if (!existsSync(sourceMetadataPath)) {
    throw new Error(`Missing Mira metadata: ${sourceMetadataPath}`);
  }
  if (!existsSync(sourceSpritesheetPath)) {
    throw new Error(`Missing Mira spritesheet source: ${sourceSpritesheetPath}`);
  }

  await mkdir(installedPetRoot, { recursive: true });
  await copyFile(sourceMetadataPath, join(installedPetRoot, "pet.json"));
  await copyFile(sourceSpritesheetPath, join(installedPetRoot, "spritesheet.webp"));
}

async function showMira(message) {
  const result = await daemonCall("overlay.actor.publish", {
    id: ACTOR_ID,
    renderer: "sprite",
    asset: PET_ID,
    state: "idle",
    name: "Mira",
    message: message || "Ready on the lattice.",
    placement: "bottom",
    style: "playful",
    ttlMs: 0,
    opacity: 1,
    zIndex: 540,
    dismissible: false,
  });
  return { ok: true, petRoot: installedPetRoot, result };
}

async function hideMira() {
  const result = await daemonCall("overlay.clear", { id: ACTOR_ID });
  return { ok: true, result };
}

async function moveMira(args) {
  const x = Number(args[0]);
  const y = Number(args[1]);
  const durationMs = Number(args[2] ?? 900);
  if (!Number.isFinite(x) || !Number.isFinite(y)) {
    throw new Error("Usage: bun run mira:move -- <x> <y> [durationMs]");
  }

  const result = await daemonCall("overlay.actor.moveTo", {
    id: ACTOR_ID,
    x,
    y,
    durationMs: Number.isFinite(durationMs) ? durationMs : 900,
    easing: "spring",
  });
  return { ok: true, result };
}

async function assertLatticesDaemon() {
  try {
    await daemonCall("daemon.status", null, 1200);
  } catch {
    throw new Error(
      "Lattices daemon is not reachable at ws://127.0.0.1:9399. Start it with `lattices app`, then rerun this command."
    );
  }
}

async function daemonCall(method, params = null, timeoutMs = 5000) {
  const id = randomBytes(4).toString("hex");
  const request = JSON.stringify({ id, method, params });

  return new Promise((resolvePromise, rejectPromise) => {
    const socket = createConnection({ host: DAEMON_HOST, port: DAEMON_PORT });
    let settled = false;
    let upgraded = false;
    let buffer = Buffer.alloc(0);

    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        socket.destroy();
        rejectPromise(new Error("Lattices daemon request timed out"));
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
        rejectPromise(error);
      }
    });

    socket.on("connect", () => {
      const key = randomBytes(16).toString("base64");
      socket.write([
        "GET / HTTP/1.1",
        `Host: ${DAEMON_HOST}:${DAEMON_PORT}`,
        "Upgrade: websocket",
        "Connection: Upgrade",
        `Sec-WebSocket-Key: ${key}`,
        "Sec-WebSocket-Version: 13",
        "",
        "",
      ].join("\r\n"));
    });

    socket.on("data", (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);

      if (!upgraded) {
        const headerEnd = buffer.indexOf("\r\n\r\n");
        if (headerEnd === -1) {
          return;
        }
        const header = buffer.subarray(0, headerEnd).toString();
        if (!header.includes("101")) {
          settled = true;
          cleanup();
          rejectPromise(new Error("WebSocket upgrade failed"));
          return;
        }
        upgraded = true;
        buffer = buffer.subarray(headerEnd + 4);
        sendFrame(socket, request);
      }

      while (true) {
        const result = parseFrame(buffer);
        if (!result) {
          break;
        }
        buffer = result.rest;

        try {
          const parsed = JSON.parse(result.payload);
          if (parsed.event || parsed.id !== id) {
            continue;
          }

          if (!settled) {
            settled = true;
            cleanup();
            if (parsed.error) {
              rejectPromise(new Error(parsed.error));
            } else {
              resolvePromise(parsed.result);
            }
          }
          return;
        } catch {
          if (!settled) {
            settled = true;
            cleanup();
            rejectPromise(new Error("Invalid JSON response from Lattices daemon"));
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
  for (let index = 0; index < payload.length; index += 1) {
    masked[index] = payload[index] ^ mask[index % 4];
  }

  socket.write(Buffer.concat([header, mask, masked]));
}

function parseFrame(buffer) {
  if (buffer.length < 2) {
    return null;
  }

  const isMasked = (buffer[1] & 0x80) !== 0;
  let payloadLength = buffer[1] & 0x7f;
  let offset = 2;

  if (payloadLength === 126) {
    if (buffer.length < 4) {
      return null;
    }
    payloadLength = buffer.readUInt16BE(2);
    offset = 4;
  } else if (payloadLength === 127) {
    if (buffer.length < 10) {
      return null;
    }
    payloadLength = Number(buffer.readBigUInt64BE(2));
    offset = 10;
  }

  if (isMasked) {
    offset += 4;
  }
  if (buffer.length < offset + payloadLength) {
    return null;
  }

  let payload = buffer.subarray(offset, offset + payloadLength);
  if (isMasked) {
    const mask = buffer.subarray(offset - 4, offset);
    payload = Buffer.alloc(payloadLength);
    for (let index = 0; index < payloadLength; index += 1) {
      payload[index] = buffer[offset + index] ^ mask[index % 4];
    }
  }

  return {
    payload: payload.toString("utf8"),
    rest: buffer.subarray(offset + payloadLength),
  };
}

function printUsageAndExit() {
  console.log(usageText());
  process.exit(1);
}

function usageText() {
  return [
    "Usage: bun scripts/mira-overlay.mjs <command>",
    "",
    "Commands:",
    "  install                 Install Mira into ~/.codex/pets/mira",
    "  show [message]          Show Mira through Lattices overlay.actor.publish",
    "  move <x> <y> [ms]       Move the persistent Mira actor",
    "  hide                    Clear the persistent Mira actor",
    "  status                  Print Lattices daemon status",
  ].join("\n");
}
