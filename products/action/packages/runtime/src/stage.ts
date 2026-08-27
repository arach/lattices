import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { dirname, resolve } from "node:path";
import { access, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { promisify } from "node:util";

import type {
  Bounds,
  StageDrapeLevel,
  StageMode,
  StageOwner,
  StageSceneIntruderReason,
  StageSceneReport,
  StageSubject,
  StageWindowInfo,
  StageWorld,
  StageWorldStatus,
} from "@action/protocol";

const execFileAsync = promisify(execFile);

const DEFAULT_COLOR = "0e0d0a";
const DEFAULT_MODE: StageMode = "drape";
const DEFAULT_LEVEL: StageDrapeLevel = "normal";
const DEFAULT_OWNER: StageOwner = "caller";
const ACTION_BUNDLE_ID = "dev.action.Action";
const MIN_SCENE_WINDOW = 32;
const SCENE_RETRY_LIMIT = 3;
const SCENE_RETRY_WAIT_MS = 120;

export type StageHostRunner = (args: string[]) => Promise<{ stdout: string }>;

export class StageSceneError extends Error {
  readonly stage: StageWorldStatus;

  constructor(message: string, stage: StageWorldStatus) {
    super(message);
    this.name = "StageSceneError";
    this.stage = stage;
  }
}

export function stageStateDir(): string {
  return resolve(homedir(), "Library/Application Support/Action/stage");
}

export function normalizeHexColor(input: string | undefined): string {
  const raw = (input ?? DEFAULT_COLOR).trim().replace(/^#/, "");
  if (!/^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(raw)) {
    throw new Error(`Invalid stage color "${input ?? ""}". Use RRGGBB.`);
  }
  return raw.toLowerCase();
}

export function parseStageWorld(input: {
  mode?: unknown;
  color?: unknown;
  level?: unknown;
  bounds?: unknown;
  subjects?: unknown;
  seconds?: unknown;
}): StageWorld {
  const mode = input.mode === "space" ? "space" : DEFAULT_MODE;
  // A Space-scoped sheet is a take sheet, so it stays at a level AXRaise can beat.
  // Normalizing here rather than at launch keeps the reported world equal to the
  // world that is actually up.
  const level: StageDrapeLevel = mode === "space" ? "normal" : input.level === "desktop" ? "desktop" : DEFAULT_LEVEL;
  const color = normalizeHexColor(typeof input.color === "string" ? input.color : undefined);
  const subjects = parseSubjects(input.subjects);
  const bounds = parseBounds(input.bounds);
  const seconds = parseSeconds(input.seconds);
  return {
    mode,
    color,
    level,
    subjects,
    ...(bounds ? { bounds } : {}),
    ...(seconds === undefined ? {} : { seconds }),
  };
}

function parseSeconds(value: unknown): number | undefined {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }
  const seconds = Number(value);
  if (!Number.isFinite(seconds) || seconds <= 0) {
    throw new Error("seconds must be a positive number");
  }
  return seconds;
}

function parseSubjects(value: unknown): StageSubject[] {
  if (value === undefined) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw new Error("subjects must be an array of { bundleId, title? }");
  }
  return value.map((entry, index) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new Error(`subjects[${index}] must be an object`);
    }
    const record = entry as Record<string, unknown>;
    const bundleId = typeof record.bundleId === "string" ? record.bundleId.trim() : "";
    if (!bundleId) {
      throw new Error(`subjects[${index}].bundleId is required`);
    }
    const title = typeof record.title === "string" && record.title.length > 0 ? record.title : undefined;
    return title ? { bundleId, title } : { bundleId };
  });
}

function parseBounds(value: unknown): Bounds | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new Error("bounds must be { x, y, width, height }");
  }
  const record = value as Record<string, unknown>;
  const x = Number(record.x);
  const y = Number(record.y);
  const width = Number(record.width);
  const height = Number(record.height);
  if (![x, y, width, height].every(Number.isFinite) || width <= 0 || height <= 0) {
    throw new Error("bounds must be finite x,y,width,height with positive size");
  }
  return { x, y, width, height };
}

function boundsIntersect(a: Bounds, b: Bounds): boolean {
  return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
}

function unionBounds(frames: Bounds[]): Bounds | undefined {
  if (frames.length === 0) {
    return undefined;
  }
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const frame of frames) {
    minX = Math.min(minX, frame.x);
    minY = Math.min(minY, frame.y);
    maxX = Math.max(maxX, frame.x + frame.width);
    maxY = Math.max(maxY, frame.y + frame.height);
  }
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

export function titleMatches(needle: string, title: string): boolean {
  const want = needle.toLowerCase();
  const have = title.toLowerCase();
  return have === want || have.includes(want);
}

export function isDrapeWindow(
  window: StageWindowInfo,
  drapePid?: number,
  actionBundleId = ACTION_BUNDLE_ID,
): boolean {
  if (drapePid !== undefined && window.pid === drapePid) {
    return true;
  }
  return window.bundleId === actionBundleId && window.title === "Action Drape";
}

export function isSubjectWindow(window: StageWindowInfo, subjects: StageSubject[]): boolean {
  return subjects.some((subject) => {
    if (subject.bundleId !== window.bundleId) {
      return false;
    }
    return subject.title ? titleMatches(subject.title, window.title) : true;
  });
}

export function evaluateStageScene(input: {
  windows: StageWindowInfo[];
  subjects: StageSubject[];
  drapePid?: number;
  bounds?: Bounds;
  actionBundleId?: string;
}): StageSceneReport {
  const actionBundleId = input.actionBundleId ?? ACTION_BUNDLE_ID;
  const takeLayer = input.windows.filter(
    (window) =>
      window.layer === 0
      && window.bounds.width >= MIN_SCENE_WINDOW
      && window.bounds.height >= MIN_SCENE_WINDOW,
  );
  const drapes = takeLayer.filter((window) => isDrapeWindow(window, input.drapePid, actionBundleId));
  const sceneBounds = input.bounds ?? unionBounds(drapes.map((window) => window.bounds));
  const inScene = takeLayer.filter((window) => !sceneBounds || boundsIntersect(window.bounds, sceneBounds));

  const tops: StageWindowInfo[] = [];
  for (const window of inScene) {
    if (isDrapeWindow(window, input.drapePid, actionBundleId)) {
      continue;
    }
    const overlappingDrapes = drapes.filter((drape) => boundsIntersect(window.bounds, drape.bounds));
    const aboveSheet = overlappingDrapes.length === 0
      || overlappingDrapes.some((drape) => inScene.indexOf(window) < inScene.indexOf(drape));
    if (aboveSheet) {
      tops.push(window);
    }
  }

  const subjectWindows = tops.filter((window) => isSubjectWindow(window, input.subjects));
  const intruders: StageSceneReport["intruders"] = [];
  for (const window of tops) {
    if (isSubjectWindow(window, input.subjects)) {
      continue;
    }
    const overSubject = subjectWindows.some((subject) => boundsIntersect(window.bounds, subject.bounds));
    const reason: StageSceneIntruderReason = overSubject ? "above-subject" : "in-rect";
    intruders.push({ ...window, reason });
  }

  for (const subject of input.subjects) {
    const found = subjectWindows.some((window) => isSubjectWindow(window, [subject]));
    if (!found) {
      intruders.push({
        bundleId: subject.bundleId,
        title: subject.title ?? "",
        owner: subject.bundleId,
        pid: 0,
        layer: 0,
        bounds: sceneBounds ?? { x: 0, y: 0, width: 0, height: 0 },
        reason: "subject-buried",
      });
    }
  }

  return {
    ok: drapes.length > 0 && intruders.length === 0,
    ...(sceneBounds ? { bounds: sceneBounds } : {}),
    tops,
    subjects: subjectWindows,
    drapes,
    intruders,
  };
}

export function describeStageScene(scene: StageSceneReport): string {
  if (scene.ok) {
    const names = scene.tops.map((window) => window.title || window.owner || window.bundleId || "window");
    return names.length === 0 ? "scene is only the drape" : `scene tops: ${names.join(", ")}`;
  }
  if (scene.drapes.length === 0) {
    return "stage sheet is not on screen";
  }
  const parts = scene.intruders.map((window) => {
    const name = window.title || window.owner || window.bundleId || "window";
    if (window.reason === "subject-buried") {
      return `${name} is still under the sheet`;
    }
    if (window.reason === "above-subject") {
      return `${name} sits above a subject`;
    }
    return `${name} occupies the scene`;
  });
  return `stage scene is buried: ${parts.join("; ")}`;
}

export class StageDirector {
  private readonly runHost: StageHostRunner;

  constructor(
    private readonly nativeHostPath: string,
    private readonly root = stageStateDir(),
    runHost?: StageHostRunner,
  ) {
    this.runHost = runHost ?? ((args) => execFileAsync(this.nativeHostPath, args));
  }

  private paths() {
    return {
      stop: resolve(this.root, "drape.stop"),
      log: resolve(this.root, "drape.log"),
      world: resolve(this.root, "world.json"),
    };
  }

  async set(
    input: Parameters<typeof parseStageWorld>[0] & { owner?: StageOwner },
  ): Promise<StageWorldStatus> {
    const world = parseStageWorld(input);
    const owner: StageOwner = input.owner === "detached" ? "detached" : DEFAULT_OWNER;
    await this.clear({ forget: false });

    const paths = this.paths();
    await mkdir(this.root, { recursive: true });
    await rm(paths.stop, { force: true });
    await rm(paths.log, { force: true });

    const args = [
      "drape",
      "--color",
      world.color,
      "--level",
      world.level,
      "--space",
      world.mode,
      "--stop-file",
      paths.stop,
      "--debug-log",
      paths.log,
    ];
    // A `caller`-owned drape dismisses itself when this process goes away, which is the
    // teardown that survives a crash. A one-shot CLI process exits as soon as the drape
    // is up, so handing it this pid would tear the sheet down within one poll interval —
    // those callers ask for `detached` and lean on `seconds` instead.
    if (owner === "caller") {
      args.push("--parent-pid", String(process.pid));
    }
    if (world.seconds !== undefined) {
      args.push("--seconds", String(world.seconds));
    }
    if (world.bounds) {
      args.push(
        "--bounds",
        `${world.bounds.x},${world.bounds.y},${world.bounds.width},${world.bounds.height}`,
      );
    }

    const { stdout } = await this.runHost(args);
    const response = JSON.parse(stdout.trim() || "{}") as { status?: string; detail?: string };
    const parsedPid = response.detail ? Number(response.detail) : Number.NaN;
    const pid = Number.isFinite(parsedPid) ? parsedPid : undefined;

    const base: StageWorldStatus = {
      ...world,
      active: true,
      pid,
      owner,
      ...(owner === "caller" ? { ownerPid: process.pid } : {}),
      stopFile: paths.stop,
      raised: [],
    };
    // Record the drape before raising anything. A subject that fails to raise throws out
    // of this method, and without the pid on disk that leaves a sheet up that `clear`
    // cannot kill and `status` reports as absent.
    await writeFile(paths.world, `${JSON.stringify(base, null, 2)}\n`);

    const raised: Array<StageSubject & { title: string }> = [];
    const raiseSubjects = async () => {
      raised.length = 0;
      for (const subject of world.subjects) {
        const raiseArgs = ["raise-window", "--bundle-id", subject.bundleId];
        if (subject.title) {
          raiseArgs.push("--title", subject.title);
        }
        const raisedResult = await this.runHost(raiseArgs);
        const payload = JSON.parse(raisedResult.stdout.trim() || "{}") as { detail?: string };
        const title = payload.detail?.split(": ").slice(1).join(": ") || subject.title || subject.bundleId;
        raised.push({ bundleId: subject.bundleId, title });
      }
    };

    await raiseSubjects();

    let scene = await this.inspectScene(world, pid);
    for (let attempt = 1; !scene.ok && attempt < SCENE_RETRY_LIMIT; attempt += 1) {
      await new Promise((resolveWait) => setTimeout(resolveWait, SCENE_RETRY_WAIT_MS));
      await raiseSubjects();
      scene = await this.inspectScene(world, pid);
    }

    const status: StageWorldStatus = { ...base, raised, scene };
    await writeFile(paths.world, `${JSON.stringify(status, null, 2)}\n`);
    if (!scene.ok) {
      throw new StageSceneError(describeStageScene(scene), status);
    }
    return status;
  }

  async clear(options: { forget?: boolean } = {}): Promise<StageWorldStatus> {
    const paths = this.paths();
    const previous = await this.readWorld();
    // Written unconditionally: a drape whose world.json was lost still polls this path,
    // so it stays dismissable even when there is no recorded pid to signal.
    await mkdir(dirname(paths.stop), { recursive: true });
    await writeFile(paths.stop, "stop\n");
    if (previous?.pid) {
      try {
        await execFileAsync("kill", ["-TERM", String(previous.pid)]);
      } catch {
        // Already gone.
      }
    }

    const gone = previous?.pid ? await waitForExit(previous.pid, 2000) : true;
    if (options.forget !== false) {
      await rm(paths.world, { force: true });
    }
    return {
      mode: previous?.mode ?? DEFAULT_MODE,
      color: previous?.color ?? DEFAULT_COLOR,
      level: previous?.level ?? DEFAULT_LEVEL,
      subjects: previous?.subjects ?? [],
      bounds: previous?.bounds,
      seconds: previous?.seconds,
      owner: previous?.owner ?? DEFAULT_OWNER,
      // Reporting the drape as down while its process is still up is how a leaked sheet
      // stays invisible to the operator. Say so instead.
      active: !gone,
      ...(gone ? {} : { pid: previous?.pid }),
      raised: [],
    };
  }

  async status(): Promise<StageWorldStatus> {
    const world = await this.readWorld();
    if (!world) {
      return {
        mode: DEFAULT_MODE,
        color: DEFAULT_COLOR,
        level: DEFAULT_LEVEL,
        subjects: [],
        owner: DEFAULT_OWNER,
        active: false,
        raised: [],
      };
    }
    const owner = world.owner ?? DEFAULT_OWNER;
    if (world.pid) {
      try {
        process.kill(world.pid, 0);
      } catch {
        return { ...world, owner, active: false, pid: undefined };
      }
      const scene = await this.inspectScene(world, world.pid);
      const current = { ...world, owner, active: true, scene };
      await writeFile(this.paths().world, `${JSON.stringify(current, null, 2)}\n`);
      return current;
    }
    return { ...world, owner, active: false };
  }

  private async inspectScene(
    world: Pick<StageWorld, "subjects" | "bounds">,
    drapePid?: number,
  ): Promise<StageSceneReport> {
    const args = ["window-order"];
    if (world.bounds) {
      args.push(
        "--bounds",
        `${world.bounds.x},${world.bounds.y},${world.bounds.width},${world.bounds.height}`,
      );
    }
    const { stdout } = await this.runHost(args);
    const payload = JSON.parse(stdout.trim() || "{}") as { windows?: StageWindowInfo[] };
    return evaluateStageScene({
      windows: payload.windows ?? [],
      subjects: world.subjects,
      drapePid,
      bounds: world.bounds,
    });
  }

  private async readWorld(): Promise<StageWorldStatus | undefined> {
    const path = this.paths().world;
    try {
      await access(path);
      return JSON.parse(await readFile(path, "utf8")) as StageWorldStatus;
    } catch {
      return undefined;
    }
  }
}

/** Poll until `pid` is gone. Returns false if it outlived the budget. */
async function waitForExit(pid: number, budgetMs: number): Promise<boolean> {
  const deadline = Date.now() + budgetMs;
  for (;;) {
    try {
      process.kill(pid, 0);
    } catch {
      return true;
    }
    if (Date.now() >= deadline) {
      return false;
    }
    await new Promise((resolveWait) => setTimeout(resolveWait, 40));
  }
}
