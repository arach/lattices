import { appendFile, mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

export type PlayLogStatus = "start" | "ok" | "fail";

export interface PlayLogEvent {
  at: string;
  play: string;
  event: "play-start" | "play-ok" | "play-fail" | "step-start" | "step-ok" | "step-fail";
  index?: number;
  of?: number;
  do?: string;
  detail?: string;
  ms?: number;
  error?: string;
  leaseId?: string;
}

export type PlayLogEventName = PlayLogEvent["event"];

export interface PlayHudFilter {
  /** When false, Action's HUD ignores play log lines. The files still record everything. */
  show: boolean;
  /** Event names to show. Empty or omitted with show true means the default set. */
  events?: PlayLogEventName[];
}

export const defaultPlayHudEvents: PlayLogEventName[] = [
  "play-start",
  "step-start",
  "step-fail",
  "play-fail",
  "play-ok",
];

export function playLogDirectory(): string {
  return join(homedir(), "Library/Application Support/Action/runtime/plays");
}

export function playHudFilterPath(): string {
  return join(playLogDirectory(), "hud-filter.json");
}

export async function ensurePlayHudFilter(): Promise<PlayHudFilter> {
  await mkdir(playLogDirectory(), { recursive: true });
  const path = playHudFilterPath();
  try {
    const parsed = JSON.parse(await readFile(path, "utf8")) as PlayHudFilter;
    return normalizePlayHudFilter(parsed);
  } catch {
    const filter: PlayHudFilter = { show: true, events: [...defaultPlayHudEvents] };
    await writeFile(path, `${JSON.stringify(filter, null, 2)}\n`);
    return filter;
  }
}

export function normalizePlayHudFilter(raw: PlayHudFilter | undefined): PlayHudFilter {
  const show = raw?.show !== false;
  const events = raw?.events?.length ? raw.events : [...defaultPlayHudEvents];
  return { show, events };
}

export function isPlayHudEventVisible(
  event: PlayLogEventName,
  filter: PlayHudFilter,
): boolean {
  if (!filter.show) {
    return false;
  }
  return (filter.events ?? defaultPlayHudEvents).includes(event);
}

function hudLine(event: PlayLogEvent): string {
  if (event.event === "play-start") {
    return `${event.play} · ${event.of ?? 0} steps`;
  }
  if (event.event === "play-ok") {
    return `${event.play} · done`;
  }
  if (event.event === "play-fail") {
    return `${event.play} · failed${event.error ? `: ${event.error}` : ""}`.slice(0, 120);
  }
  const n = event.index !== undefined && event.of !== undefined
    ? `${event.index + 1}/${event.of}`
    : "?";
  const verb = event.do ?? "step";
  if (event.event === "step-fail") {
    return `${n} fail ${verb}${event.error ? `: ${event.error}` : ""}`.slice(0, 120);
  }
  if (event.event === "step-ok") {
    const ms = event.ms !== undefined ? ` ${event.ms}ms` : "";
    return `${n} ${verb}${ms}`.slice(0, 120);
  }
  return `${n} ${verb}`.slice(0, 120);
}

function textLine(event: PlayLogEvent): string {
  const extra = event.detail ?? event.error ?? "";
  return `${event.at}  ${hudLine(event)}${extra && extra !== hudLine(event) ? `  ${extra}` : ""}`;
}

export class PlayLogger {
  readonly play: string;
  readonly leaseId?: string;
  private readonly dir: string;

  constructor(play: string, leaseId?: string) {
    this.play = play;
    this.leaseId = leaseId;
    this.dir = playLogDirectory();
  }

  async playStart(of: number): Promise<void> {
    await mkdir(this.dir, { recursive: true });
    await ensurePlayHudFilter();
    await writeFile(join(this.dir, "current.jsonl"), "");
    await writeFile(join(this.dir, "current.log"), "");
    await this.write({
      at: new Date().toISOString(),
      play: this.play,
      event: "play-start",
      of,
      leaseId: this.leaseId,
    });
  }

  async stepStart(index: number, of: number, verb: string, detail?: string): Promise<void> {
    await this.write({
      at: new Date().toISOString(),
      play: this.play,
      event: "step-start",
      index,
      of,
      do: verb,
      detail,
      leaseId: this.leaseId,
    });
  }

  async stepOk(index: number, of: number, verb: string, ms: number, detail?: string): Promise<void> {
    await this.write({
      at: new Date().toISOString(),
      play: this.play,
      event: "step-ok",
      index,
      of,
      do: verb,
      ms,
      detail,
      leaseId: this.leaseId,
    });
  }

  async stepFail(index: number, of: number, verb: string, error: string): Promise<void> {
    await this.write({
      at: new Date().toISOString(),
      play: this.play,
      event: "step-fail",
      index,
      of,
      do: verb,
      error,
      leaseId: this.leaseId,
    });
  }

  async playOk(): Promise<void> {
    await this.write({
      at: new Date().toISOString(),
      play: this.play,
      event: "play-ok",
      leaseId: this.leaseId,
    });
  }

  async playFail(error: string, index?: number): Promise<void> {
    await this.write({
      at: new Date().toISOString(),
      play: this.play,
      event: "play-fail",
      index,
      error,
      leaseId: this.leaseId,
    });
  }

  private async write(event: PlayLogEvent): Promise<void> {
    await mkdir(this.dir, { recursive: true });
    const json = `${JSON.stringify(event)}\n`;
    const line = `${textLine(event)}\n`;
    await appendFile(join(this.dir, "log.jsonl"), json);
    await appendFile(join(this.dir, "current.jsonl"), json);
    await appendFile(join(this.dir, "current.log"), line);
    const filter = await ensurePlayHudFilter();
    if (isPlayHudEventVisible(event.event, filter)) {
      await this.publishHud(hudLine(event), event.at);
    }
  }

  private async publishHud(line: string, at: string): Promise<void> {
    const supervision = join(homedir(), "Library/Application Support/Action/runtime/supervision");
    await mkdir(supervision, { recursive: true });
    await appendFile(
      join(supervision, "notes.jsonl"),
      `${JSON.stringify({ at, leaseId: this.leaseId, line })}\n`,
    );
    const registrations = join(supervision, "registrations");
    try {
      const files = await readdir(registrations);
      for (const file of files) {
        if (!file.endsWith(".json")) {
          continue;
        }
        const path = join(registrations, file);
        try {
          const registration = JSON.parse(await readFile(path, "utf8")) as Record<string, unknown>;
          registration.detail = line;
          registration.updatedAt = at;
          await writeFile(path, `${JSON.stringify(registration, null, 2)}\n`);
        } catch {
          // torn registration
        }
      }
    } catch {
      // overlay may be down
    }
  }
}
