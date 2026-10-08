// Screenshots through grim. Files land in ~/.lattices/captures like the Mac's
// run artifacts; `inline: true` also returns the bytes as base64, which is what
// a remote client needs.

import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { runBuffer } from "./exec.ts";
import type { Rect } from "./placement.ts";

export const CAPTURE_DIR = join(homedir(), ".lattices", "captures");

export interface CaptureOptions {
  region?: Rect;
  output?: string;
  format?: "png" | "jpeg";
  quality?: number;
  scale?: number;
  cursor?: boolean;
}

export function grimArgs(options: CaptureOptions): string[] {
  const args: string[] = ["-t", options.format ?? "png"];
  if (options.format === "jpeg") args.push("-q", String(Math.round(options.quality ?? 80)));
  if (options.scale && options.scale !== 1) args.push("-s", String(options.scale));
  if (options.cursor) args.push("-c");
  if (options.region) {
    const r = options.region;
    args.push("-g", `${Math.round(r.x)},${Math.round(r.y)} ${Math.round(r.w)}x${Math.round(r.h)}`);
  } else if (options.output) {
    args.push("-o", options.output);
  }
  args.push("-");
  return args;
}

export async function grab(options: CaptureOptions): Promise<Buffer> {
  return runBuffer("grim", grimArgs(options));
}

/** Image dimensions from a PNG or JPEG header. */
export function imageSize(bytes: Buffer): { width: number; height: number } | null {
  if (bytes.length > 24 && bytes.readUInt32BE(0) === 0x89504e47) {
    return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
  }
  if (bytes[0] === 0xff && bytes[1] === 0xd8) {
    let i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] !== 0xff) return null;
      const marker = bytes[i + 1];
      const length = bytes.readUInt16BE(i + 2);
      if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
        return { height: bytes.readUInt16BE(i + 5), width: bytes.readUInt16BE(i + 7) };
      }
      i += 2 + length;
    }
  }
  return null;
}

export function save(bytes: Buffer, format: "png" | "jpeg", filename?: string): string {
  mkdirSync(CAPTURE_DIR, { recursive: true });
  const safe = filename?.replace(/[^\w.-]/g, "-");
  const name = safe || `capture-${new Date().toISOString().replace(/[:.]/g, "-")}.${format === "jpeg" ? "jpg" : "png"}`;
  const path = join(CAPTURE_DIR, name);
  writeFileSync(path, bytes);
  return path;
}
