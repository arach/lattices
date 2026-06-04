#!/usr/bin/env bun
// Generic stdio dispatcher for the metaharness.
//
// Reads one JSON op per line on stdin; writes JSON lines on stdout. Native
// hosts (e.g. the Lattices Swift app) drive this instead of spawning a harness
// themselves — every per-harness detail is handled by @openscout/agent-sessions.
//
// Ops:
//   {"op":"ping"}
//   {"op":"catalog"}
//   {"op":"start","sessionId":"s1","harness":"pi","cwd":"…","provider":"…","model":"…","systemPrompt":"…","options":{…}}
//   {"op":"prompt","sessionId":"s1","text":"…"}
//   {"op":"interrupt","sessionId":"s1"}
//   {"op":"shutdown"}
//
// Replies: {"type":"response","id":…,"op":…,"ok":true|false,…}
// Streamed adapter events: {"type":"event","event":{…}}  (PairingEvent w/ sessionId)
//
// Requires the Bun runtime (adapters use Bun.spawn).

import { createMetaharness, describeCatalog, METAHARNESS_VERSION } from "../src/index.mjs";

const meta = createMetaharness();

// Stream every adapter event straight to stdout.
meta.onEvent((sequenced) => {
  write({ type: "event", event: sequenced.event ?? sequenced });
});

function write(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

function reply(request, fields) {
  write({ type: "response", id: request?.id ?? null, op: request?.op ?? null, ...fields });
}

async function handleLine(line) {
  const trimmed = line.trim();
  if (!trimmed) return;

  let request;
  try {
    request = JSON.parse(trimmed);
  } catch {
    write({ type: "response", ok: false, error: `Invalid JSON: ${trimmed.slice(0, 120)}` });
    return;
  }

  try {
    switch (request.op) {
      case "ping":
        reply(request, { ok: true, version: METAHARNESS_VERSION });
        break;

      case "catalog":
        reply(request, { ok: true, harnesses: describeCatalog() });
        break;

      case "start": {
        const session = await meta.start(request.harness, {
          sessionId: request.sessionId,
          name: request.name,
          cwd: request.cwd,
          provider: request.provider,
          model: request.model,
          systemPrompt: request.systemPrompt,
          options: request.options,
        });
        reply(request, { ok: true, sessionId: session.id, session });
        break;
      }

      case "prompt":
        meta.prompt({ sessionId: request.sessionId, text: request.text, images: request.images });
        reply(request, { ok: true, sessionId: request.sessionId });
        break;

      case "interrupt":
        meta.interrupt(request.sessionId);
        reply(request, { ok: true, sessionId: request.sessionId });
        break;

      case "shutdown":
        await meta.shutdown();
        reply(request, { ok: true });
        process.exit(0);
        break;

      default:
        reply(request, { ok: false, error: `Unsupported op: ${request.op}` });
    }
  } catch (error) {
    reply(request, { ok: false, error: error?.message ?? String(error) });
  }
}

// Line-buffered stdin.
let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let nl;
  while ((nl = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, nl);
    buffer = buffer.slice(nl + 1);
    void handleLine(line);
  }
});
process.stdin.on("end", () => {
  void meta.shutdown().finally(() => process.exit(0));
});
process.stdin.on("error", () => {
  void meta.shutdown().finally(() => process.exit(1));
});
