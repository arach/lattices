// Screen recording without a recorder binary: grim frames at a fixed rate,
// encoded with ffmpeg when the recording stops. Coarser than a real encoder,
// but it needs only tools this host already uses, and pause/resume are just
// gaps in the frame loop.

import { mkdirSync, readdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { CAPTURE_DIR, grab } from "./capture.ts";
import { run } from "./exec.ts";
import type { Rect } from "./placement.ts";
import { writeFileSync } from "node:fs";

interface Recording {
  id: string;
  dir: string;
  fps: number;
  region?: Rect;
  output?: string;
  format: "mp4" | "mov";
  frames: number;
  paused: boolean;
  startedAt: number;
  timer: ReturnType<typeof setInterval>;
  busy: boolean;
  errors: number;
}

let active: Recording | null = null;

export function status() {
  if (!active) return { recording: false };
  const { id, fps, frames, paused, startedAt, region, format } = active;
  return { recording: true, id, fps, frames, paused, region: region ?? null, format, seconds: (Date.now() - startedAt) / 1000 };
}

export function start(options: { region?: Rect; output?: string; fps?: number; format?: "mp4" | "mov" }) {
  if (active) throw new Error(`already recording (${active.id}); stop it first`);
  const fps = Math.max(1, Math.min(15, Math.round(options.fps ?? 5)));
  const id = `rec-${new Date().toISOString().replace(/[:.]/g, "-")}`;
  const dir = join(CAPTURE_DIR, id);
  mkdirSync(dir, { recursive: true });
  const rec: Recording = {
    id,
    dir,
    fps,
    region: options.region,
    output: options.output,
    format: options.format ?? "mp4",
    frames: 0,
    paused: false,
    startedAt: Date.now(),
    busy: false,
    errors: 0,
    timer: setInterval(async () => {
      if (rec.paused || rec.busy) return;
      rec.busy = true;
      try {
        const frame = await grab({ region: rec.region, output: rec.output, format: "jpeg", quality: 85 });
        rec.frames += 1;
        writeFileSync(join(dir, `${String(rec.frames).padStart(6, "0")}.jpg`), frame);
      } catch {
        rec.errors += 1;
      } finally {
        rec.busy = false;
      }
    }, 1000 / fps),
  };
  active = rec;
  return status();
}

export function setPaused(paused: boolean) {
  if (!active) throw new Error("not recording");
  active.paused = paused;
  return status();
}

export async function stop(): Promise<{ ok: true; path: string; frames: number; fps: number; seconds: number; format: string }> {
  const rec = active;
  if (!rec) throw new Error("not recording");
  clearInterval(rec.timer);
  active = null;
  while (rec.busy) await new Promise((r) => setTimeout(r, 20));
  if (rec.frames === 0) throw new Error("recording captured no frames");
  const path = join(CAPTURE_DIR, `${rec.id}.${rec.format}`);
  await run(
    "ffmpeg",
    [
      "-y", "-loglevel", "error",
      "-framerate", String(rec.fps),
      "-i", join(rec.dir, "%06d.jpg"),
      // Even dimensions for yuv420p.
      "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
      "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
      path,
    ],
    { timeoutMs: 300_000 }
  );
  const frames = readdirSync(rec.dir).length;
  rmSync(rec.dir, { recursive: true, force: true });
  return { ok: true, path, frames, fps: rec.fps, seconds: frames / rec.fps, format: rec.format };
}
