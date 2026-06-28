import { createHash } from "node:crypto";
import { basename, resolve } from "node:path";
import { runQuiet } from "./helpers.ts";

export function pathHash(dir: string): string {
  return createHash("sha256").update(resolve(dir)).digest("hex").slice(0, 6);
}

export function toSessionName(dir: string): string {
  const base = basename(dir).replace(/[^a-zA-Z0-9_-]/g, "-");
  return `${base}-${pathHash(dir)}`;
}

export function esc(str: string): string {
  return str.replace(/'/g, "'\\''");
}

export function slugify(str: string): string {
  return str
    .toLowerCase()
    .replace(/\.app$/i, "")
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "") || "app";
}

export function sessionExists(name: string): boolean {
  return runQuiet(`tmux has-session -t "${name}" 2>&1`) !== null;
}

export function toGroupSessionName(groupId: string): string {
  return `lattices-group-${groupId}`;
}