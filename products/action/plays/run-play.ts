#!/usr/bin/env bun
// Non-thinking play runner. Reads a play JSON and executes beats. No model.

import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { resolve } from "node:path";

import { PlayLogger } from "../packages/runtime/src/play-log.ts";

const actionRoot = resolve(import.meta.dir, "..");
const host = resolve(actionRoot, "native/engine/scripts/run-app-host.sh");
const uidrag = resolve(homedir(), "dev/talkie/scripts/demo/uidrag.swift");
const playPath = process.argv[2] ?? resolve(import.meta.dir, "ghostty-window-demo.json");

type Point = { x: number; y: number };
type GhosttyWin = { x: number; y: number; width: number; height: number };

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function run(cmd: string, args: string[]): void {
  const result = spawnSync(cmd, args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`${cmd} ${args.join(" ")} failed: ${result.stderr || result.stdout}`);
  }
}

function listGhostty(): GhosttyWin[] {
  const script = `
import Cocoa
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in info {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  guard owner == "Ghostty" else { continue }
  let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
  let wdt = b["Width"] ?? 0
  let hgt = b["Height"] ?? 0
  if wdt < 200 || hgt < 120 { continue }
  print("\\(Int(b["X"] ?? 0)),\\(Int(b["Y"] ?? 0)),\\(Int(wdt)),\\(Int(hgt))")
}
`;
  const written = `/tmp/ghostty-wins-${process.pid}.swift`;
  require("node:fs").writeFileSync(written, script);
  const result = spawnSync("swift", [written], { encoding: "utf8" });
  return (result.stdout || "")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line: string) => {
      const [x, y, width, height] = line.split(",").map(Number);
      return { x, y, width, height };
    });
}

function trailingTitlebar(win: GhosttyWin): Point {
  return { x: win.x + win.width - 70, y: win.y + 12 };
}

function bodyPoint(win: GhosttyWin): Point {
  return { x: win.x + win.width / 2, y: win.y + Math.min(win.height * 0.45, 220) };
}

function beatVerb(beat: Record<string, unknown>): string {
  const kind = String(beat.do);
  if (kind === "act") {
    return String(beat.kind ?? "act");
  }
  return kind;
}

function beatDetail(beat: Record<string, unknown>): string | undefined {
  if (typeof beat.line === "string") {
    return beat.line;
  }
  if (typeof beat.text === "string") {
    return beat.text;
  }
  if (typeof beat.label === "string") {
    return beat.label;
  }
  return undefined;
}

async function main(): Promise<void> {
  const play = JSON.parse(await readFile(playPath, "utf8")) as {
    title: string;
    beats: Array<Record<string, unknown>>;
  };
  const log = new PlayLogger(play.title);
  await log.playStart(play.beats.length);
  let subject: GhosttyWin | undefined;
  const before = listGhostty();

  for (const [index, beat] of play.beats.entries()) {
    const kind = String(beat.do);
    const verb = beatVerb(beat);
    const started = Date.now();
    await log.stepStart(index, play.beats.length, verb, beatDetail(beat));
    try {
      if (kind === "note") {
        // Author line is already on the HUD via step-start detail.
      } else if (kind === "wait") {
        await sleep(Number(beat.ms ?? 300));
      } else if (kind === "act") {
        const act = String(beat.kind);
        if (act === "focus-ghostty") {
          spawnSync("open", ["-b", "com.mitchellh.ghostty"]);
          await sleep(250);
        } else if (act === "press-key") {
          const key = String(beat.key);
          const modifiers = Array.isArray(beat.modifiers) ? (beat.modifiers as string[]) : [];
          const hostArgs = ["press-key", "--key", key];
          if (modifiers.length) {
            hostArgs.push("--modifiers", modifiers.join(","));
          }
          run(host, hostArgs);
        } else if (act === "pick-new-ghostty") {
          const after = listGhostty();
          subject = after.find((w) =>
            w.width < 1200 && !before.some((b) => b.x === w.x && b.y === w.y && b.width === w.width)
          ) ?? after.find((w) => w.width < 1200 && w.width > 400);
          if (!subject) {
            throw new Error("No new Ghostty window found");
          }
        } else if (act === "click-window-body") {
          if (!subject) {
            throw new Error("no subject");
          }
          const wins = listGhostty();
          subject = wins.find((w) => Math.abs(w.width - subject!.width) < 40 && w.width < 1200) ?? subject;
          const p = bodyPoint(subject);
          run("swift", [uidrag, "click", String(p.x), String(p.y)]);
        } else if (act === "type") {
          run(host, ["type-text", "--text", String(beat.text ?? ""), "--delay-ms", "28"]);
        } else {
          throw new Error(`unknown act ${act}`);
        }
      } else if (kind === "drag-titlebar-trailing") {
        if (!subject) {
          throw new Error("no subject");
        }
        const wins = listGhostty();
        subject = wins.find((w) => w.width < 1200 && w.width > 400) ?? subject;
        const from = trailingTitlebar(subject);
        const to = beat.to as Point;
        run("swift", [
          uidrag,
          "drag",
          String(from.x),
          String(from.y),
          String(to.x),
          String(to.y),
          "--duration",
          String(beat.durationMs ?? 800),
          "--settle",
          "120",
        ]);
        await sleep(200);
        const moved = listGhostty().find((w) => w.width < 1200 && w.width > 400);
        if (moved) {
          subject = moved;
        }
      } else {
        throw new Error(`unknown beat ${kind} at ${index}`);
      }
      await log.stepOk(index, play.beats.length, verb, Date.now() - started, beatDetail(beat));
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await log.stepFail(index, play.beats.length, verb, message);
      await log.playFail(message, index);
      throw error;
    }
  }
  await log.playOk();
}

await main();
