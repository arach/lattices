/**
 * Hudson / Vox on-device TTS client for Lattices workers.
 *
 * Speaks through the embedded Lattices voice runtime (Kokoro via mlx-audio by default).
 */

import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { spawn } from "child_process";

export const KOKORO_MODEL_ID = "mlx-community/Kokoro-82M-bf16";
export const KOKORO_VOICE_ID = "af_heart";
export const AVSPEECH_MODEL_ID = "avspeech:system";

const DEFAULT_CAPABILITY_PATH = join(
  homedir(),
  "Library/Application Support/Lattices/Voice/hudson-voice-runtime.json"
);

type Capability = {
  webSocketUrl?: string;
  host?: string;
  port?: number;
  authToken?: string;
};

type VoxRuntime = {
  capability: Capability;
  wsUrl: string;
  authToken: string;
};

let cachedRuntime: VoxRuntime | null | undefined;
let requestCounter = 0;

function resolveCapabilityPath(): string {
  return process.env.LATTICES_VOICE_CAPABILITY?.trim() || DEFAULT_CAPABILITY_PATH;
}

function loadCapability(): Capability | null {
  const path = resolveCapabilityPath();
  if (!existsSync(path)) return null;
  try {
    return JSON.parse(readFileSync(path, "utf8")) as Capability;
  } catch {
    return null;
  }
}

export function resolveVoxRuntime(): VoxRuntime | null {
  if (cachedRuntime !== undefined) return cachedRuntime;

  const capability = loadCapability();
  if (!capability) {
    cachedRuntime = null;
    return null;
  }

  const wsUrl =
    capability.webSocketUrl?.trim() ||
    (capability.host && capability.port
      ? `ws://${capability.host}:${capability.port}`
      : process.env.LATTICES_VOICE_WS_URL?.trim() || "ws://127.0.0.1:9398");

  const authToken = capability.authToken?.trim() || process.env.VOX_AUTH_TOKEN?.trim() || "";
  if (!authToken) {
    cachedRuntime = null;
    return null;
  }

  cachedRuntime = { capability, wsUrl, authToken };
  return cachedRuntime;
}

export function resetVoxRuntimeCache() {
  cachedRuntime = undefined;
}

function playWavFile(filePath: string): Promise<number> {
  const start = performance.now();
  return new Promise((resolve, reject) => {
    const player = spawn("/usr/bin/afplay", [filePath], {
      stdio: ["ignore", "ignore", "pipe"],
    });
    let stderr = "";
    player.stderr?.on("data", (chunk: Buffer) => {
      stderr += chunk.toString();
    });
    player.on("close", (code) => {
      const ms = Math.round(performance.now() - start);
      if (code === 0) resolve(ms);
      else reject(new Error(`afplay failed (${code ?? "unknown"}): ${stderr.slice(0, 160)}`));
    });
    player.on("error", reject);
  });
}

async function voxRpc(
  runtime: VoxRuntime,
  method: string,
  params: Record<string, unknown>,
  timeoutMs = 120_000
): Promise<Record<string, unknown>> {
  const id = `handsoff-${++requestCounter}`;
  const ws = new WebSocket(runtime.wsUrl);

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      try {
        ws.close();
      } catch {}
      reject(new Error(`Vox ${method} timed out after ${timeoutMs}ms`));
    }, timeoutMs);

    const cleanup = () => clearTimeout(timer);

    ws.addEventListener("open", () => {
      ws.send(
        JSON.stringify({
          id,
          method,
          authToken: runtime.authToken,
          params: {
            clientId: "handsoff-worker",
            ...params,
          },
        })
      );
    });

    ws.addEventListener("message", (event) => {
      let payload: any;
      try {
        payload = JSON.parse(String(event.data));
      } catch {
        return;
      }
      if (payload.id !== id) return;

      cleanup();
      try {
        ws.close();
      } catch {}

      if (payload.error) {
        reject(new Error(String(payload.error)));
        return;
      }
      resolve((payload.result ?? {}) as Record<string, unknown>);
    });

    ws.addEventListener("error", () => {
      cleanup();
      reject(new Error(`Could not connect to Hudson voice runtime at ${runtime.wsUrl}`));
    });
  });
}

export async function synthesizeWithVox(
  text: string,
  options: {
    modelId?: string;
    voiceId?: string;
    format?: string;
  } = {}
): Promise<{ wav: Buffer; elapsedMs: number; modelId: string; voiceId: string }> {
  const runtime = resolveVoxRuntime();
  if (!runtime) {
    throw new Error("Hudson voice runtime capability is unavailable");
  }

  const result = await voxRpc(runtime, "synthesize.generate", {
    text,
    modelId: options.modelId,
    voiceId: options.voiceId,
    format: options.format ?? "wav",
  });

  const audioBase64 = String(result.audioBase64 ?? "");
  if (!audioBase64) {
    throw new Error("Vox synthesize.generate returned no audio");
  }

  const wav = Buffer.from(audioBase64, "base64");
  return {
    wav,
    elapsedMs: Number(result.elapsedMs ?? 0),
    modelId: String(result.modelId ?? options.modelId ?? KOKORO_MODEL_ID),
    voiceId: String(result.voiceId ?? options.voiceId ?? KOKORO_VOICE_ID),
  };
}

export async function speakWithVox(
  text: string,
  options: {
    modelId?: string;
    voiceId?: string;
    cachePath?: string;
  } = {}
): Promise<number> {
  const { wav, elapsedMs } = await synthesizeWithVox(text, {
    modelId: options.modelId,
    voiceId: options.voiceId,
  });

  if (options.cachePath) {
    const { writeFileSync } = await import("fs");
    writeFileSync(options.cachePath, wav);
    return elapsedMs;
  }

  const { mkdtempSync, writeFileSync, rmSync } = await import("fs");
  const { tmpdir } = await import("os");
  const dir = mkdtempSync(join(tmpdir(), "lattices-vox-tts-"));
  const filePath = join(dir, "speech.wav");
  writeFileSync(filePath, wav);
  try {
    const playbackMs = await playWavFile(filePath);
    return Math.max(playbackMs, elapsedMs);
  } finally {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {}
  }
}

export async function playCachedWav(filePath: string): Promise<number> {
  return playWavFile(filePath);
}

export function describeVoxRuntime(): string {
  const runtime = resolveVoxRuntime();
  if (!runtime) return "unavailable";
  return runtime.wsUrl;
}
