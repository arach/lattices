import { readFile } from "node:fs/promises";
import { extname, isAbsolute, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import type { AgentLayerStatus, Bounds, RuntimeAction } from "@action/protocol";
import {
  FOCUSED_RECT_SCRIPT,
  clickAt,
  devToolsKey,
  dragBetween,
  findElementScript,
  fromPage,
  insertText,
  pageOnLayer,
  pressKey,
  toPage,
  wheelAt,
  type AgentLayerMark,
  type AgentLayerSnapshot,
  type DevToolsPage,
  type PageGeometry,
} from "@action/runtime";
import { primitiveAction, readPoint, readSpace, toGlobal, type LayerPoint, type LayerPrimitive, type LayerView } from "./layer-primitives.js";

/**
 * One way to drive the agent layer, whichever door the agent comes in by: a single
 * tool call, a list of steps, a steps file, or a script that gets the driver as a
 * function argument.
 *
 * Each act picks its route. A Chromium browser on the layer with a DevTools port takes
 * input straight into the page: nothing of the operator's moves. Anything else runs as
 * a blink, through accessibility first and the borrowed pointer last.
 */

export const LAYER_VERBS = ["click", "type", "press", "go", "drag", "scroll", "js", "wait", "look", "note"] as const;
export type LayerVerb = (typeof LAYER_VERBS)[number];

type Args = Record<string, unknown>;

export interface LayerStep {
  verb: LayerVerb;
  args: Args;
}

export interface LayerDriverDeps {
  status(): Promise<AgentLayerStatus>;
  view(): LayerView | undefined;
  /** Throws when the operator paused or took back the layer. */
  guard(): Promise<void>;
  /** Run an act as a blink through action.act.execute. */
  blink(action: RuntimeAction): Promise<{ host?: string; leaseId?: string }>;
  /** Keep the layer's drive alive for an act that didn't go through act.execute. */
  touch(kind: string): Promise<void>;
  mark(act: AgentLayerMark): Promise<void>;
  look(): Promise<AgentLayerSnapshot>;
  note(text: string): Promise<void>;
}

/** How long the viewer's pointer gets to reach a spot before the act lands there. */
const AIM_LEAD_MS = 260;

const sleep = (ms: number) => new Promise((done) => setTimeout(done, ms));

function isVerb(key: string): key is LayerVerb {
  return (LAYER_VERBS as readonly string[]).includes(key);
}

function isRecord(value: unknown): value is Args {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

/**
 * A step as written to its verb and arguments. Each verb has a short form:
 *
 *   { click: "Search" }            label        { click: [420, 310] }   point
 *   { type: "hello\n" }            text         { press: "cmd+l" }      key
 *   { go: "news.ycombinator.com" } url          { scroll: -400 }        dy, mid-view
 *   { drag: [[x, y], [x, y]] }     from, to     { wait: 500 }           ms
 *   { wait: "settled" }            until still  { wait: "Sign in" }     until text shows
 *   { js: "document.title" }       code         { note: "Opening" }     viewer note
 *   { look: true }                 snapshot
 *
 * The long form is an object under the verb ({ click: { label, holdMs } }) or
 * { do: "click", ...args }. Keys next to the verb are extra arguments.
 */
export function parseLayerStep(raw: unknown): LayerStep {
  if (!isRecord(raw)) {
    throw new Error(`A step is an object such as { click: "Search" }, not ${JSON.stringify(raw)}`);
  }
  if (typeof raw.do === "string") {
    if (!isVerb(raw.do)) throw new Error(`Unknown step "${raw.do}". Steps: ${LAYER_VERBS.join(", ")}`);
    const { do: _do, ...args } = raw;
    return { verb: raw.do, args };
  }
  const verbs = Object.keys(raw).filter(isVerb);
  if (verbs.length !== 1) {
    throw new Error(
      verbs.length === 0
        ? `A step names one of ${LAYER_VERBS.join(", ")}: ${JSON.stringify(raw)}`
        : `A step names one verb, not ${verbs.join(" and ")}`,
    );
  }
  const verb = verbs[0]!;
  const { [verb]: value, ...extra } = raw;
  return { verb, args: { ...shorthand(verb, value), ...extra } };
}

function shorthand(verb: LayerVerb, value: unknown): Args {
  if (isRecord(value) && !(verb === "click" && readPoint(value))) {
    return value;
  }
  switch (verb) {
    case "click":
      if (typeof value === "string") return { label: value };
      if (readPoint(value)) return { at: value };
      break;
    case "type":
      if (typeof value === "string") return { text: value };
      break;
    case "press":
      if (typeof value === "string") return { key: value };
      break;
    case "go":
      if (typeof value === "string") return { url: value };
      break;
    case "drag":
      if (Array.isArray(value) && value.length === 2) return { from: value[0], to: value[1] };
      break;
    case "scroll":
      if (typeof value === "number") return { dy: value };
      break;
    case "wait":
      if (typeof value === "number") return { ms: value };
      if (value === "settled") return { until: "settled" };
      if (typeof value === "string") return { text: value };
      break;
    case "js":
      if (typeof value === "string") return { code: value };
      break;
    case "note":
      if (typeof value === "string") return { text: value };
      break;
    case "look":
      return {};
  }
  throw new Error(`${verb} doesn't take ${JSON.stringify(value)}`);
}

/** Steps from a run call: inline, or a JSON file of steps (an array, or { steps }). */
export function parseLayerSteps(raw: unknown): LayerStep[] {
  const list = isRecord(raw) && Array.isArray(raw.steps) ? raw.steps : raw;
  if (!Array.isArray(list) || list.length === 0) {
    throw new Error("steps is a non-empty list, e.g. [{ go: \"example.com\" }, { click: \"More information\" }]");
  }
  return list.map((step, index) => {
    try {
      return parseLayerStep(step);
    } catch (error) {
      throw new Error(`step ${index + 1}: ${(error as Error).message}`);
    }
  });
}

export function normalizeUrl(value: string): string {
  const url = value.trim();
  if (/^[a-z][a-z0-9+.-]*:/i.test(url)) return url;
  if (url.startsWith("/") || url.startsWith("~")) return `file://${url}`;
  return `https://${url}`;
}

/** What a script file gets: one method per verb, taking the same short forms. */
export type LayerScriptApi = {
  [verb in LayerVerb]: (value?: unknown, extra?: Args) => Promise<Record<string, unknown>>;
} & {
  step(step: unknown): Promise<Record<string, unknown>>;
  status(): Promise<AgentLayerStatus>;
};

interface BrowserPage {
  page: DevToolsPage;
  geometry: PageGeometry;
}

export class LayerDriver {
  constructor(private readonly deps: LayerDriverDeps) {}

  async step(step: LayerStep): Promise<Record<string, unknown>> {
    if (step.verb === "note") {
      const text = typeof step.args.text === "string" ? step.args.text : "";
      await this.deps.note(text);
      return { note: text };
    }
    if (step.verb === "look") {
      return { snapshot: await this.deps.look() };
    }
    if (step.verb === "wait") {
      return this.wait(step.args);
    }
    await this.deps.guard();
    const status = await this.deps.status();
    if (!status.active || !status.layer) {
      throw new Error("No agent layer is up. Open one with action.layer.open { bundleId } or { browser: true }.");
    }
    const near = this.pointOf(step, status.layer.bounds);
    const browser = await this.browser(status, near);
    try {
      if (browser) {
        const result = await this.viaDevTools(step, browser, status.layer.bounds);
        if (result) {
          await this.deps.touch(step.verb);
          return { route: "devtools", ...result };
        }
      }
      return await this.viaBlink(step, status);
    } finally {
      browser?.page.close();
    }
  }

  /** The script-file face of the driver. */
  api(): LayerScriptApi {
    const api: Record<string, unknown> = {
      step: (step: unknown) => this.step(parseLayerStep(step)),
      status: () => this.deps.status(),
    };
    for (const verb of LAYER_VERBS) {
      api[verb] = (value?: unknown, extra: Args = {}) =>
        this.step({ verb, args: { ...shorthand(verb, verb === "look" ? true : value), ...extra } });
    }
    return api as LayerScriptApi;
  }

  /**
   * Run steps in order. Stops at the first that fails and says which, with a look at
   * the layer, so the caller sees where it got to.
   */
  async run(steps: LayerStep[]): Promise<{ ok: boolean; steps: Record<string, unknown>[]; failed?: { step: number; verb: LayerVerb; error: string } }> {
    const results: Record<string, unknown>[] = [];
    for (const [index, step] of steps.entries()) {
      try {
        const started = Date.now();
        const result = summarize(await this.step(step));
        results.push({ [step.verb]: result, ms: Date.now() - started });
      } catch (error) {
        return { ok: false, steps: results, failed: { step: index + 1, verb: step.verb, error: (error as Error).message } };
      }
    }
    return { ok: true, steps: results };
  }

  /** A .json file of steps, or a .ts/.js module whose default export is `async (layer) => …`. */
  async runFile(path: string): Promise<Record<string, unknown>> {
    const file = isAbsolute(path) ? path : resolve(process.cwd(), path);
    const ext = extname(file).toLowerCase();
    if (ext === ".json") {
      return this.run(parseLayerSteps(JSON.parse(await readFile(file, "utf8"))));
    }
    if ([".ts", ".js", ".mjs", ".mts"].includes(ext)) {
      // Cache-busted so an edited script runs as edited.
      const module = await import(`${pathToFileURL(file).href}?at=${Date.now()}`) as { default?: unknown };
      if (typeof module.default !== "function") {
        throw new Error(`${path} needs a default export: export default async (layer) => { await layer.click("Search") }`);
      }
      try {
        const value = await (module.default as (layer: LayerScriptApi) => unknown)(this.api());
        return { ok: true, ...(value !== undefined ? { value } : {}) };
      } catch (error) {
        return { ok: false, error: (error as Error).message };
      }
    }
    throw new Error(`Run a .json steps file or a .ts/.js script, not ${ext || "a file without an extension"}`);
  }

  private pointOf(step: LayerStep, bounds: Bounds): LayerPoint | undefined {
    const raw = step.verb === "drag" ? readPoint(step.args.from) : readAt(step.args);
    return raw ? toGlobal(raw, readSpace(step.args.space), bounds, this.deps.view()) : undefined;
  }

  private async browser(status: AgentLayerStatus, near?: LayerPoint): Promise<BrowserPage | undefined> {
    const pids = new Set<number>();
    for (const window of status.layer?.windows ?? []) pids.add(window.pid);
    if (status.subject?.pid) pids.add(status.subject.pid);
    for (const pid of pids) {
      const found = await pageOnLayer(pid, status.layer!.bounds, near).catch(() => undefined);
      if (found) {
        // A background window's page still takes focus and caret as if it were in front.
        await found.page.call("Emulation.setFocusEmulationEnabled", { enabled: true }).catch(() => undefined);
        return found;
      }
    }
    return undefined;
  }

  /** The act through DevTools, or undefined to leave it to the blink route. */
  private async viaDevTools(step: LayerStep, { page, geometry }: BrowserPage, bounds: Bounds): Promise<Record<string, unknown> | undefined> {
    const args = step.args;
    const global = (point: LayerPoint) => toGlobal(point, readSpace(args.space), bounds, this.deps.view());
    switch (step.verb) {
      case "click": {
        let at: LayerPoint;
        let found: Record<string, unknown> | undefined;
        if (typeof args.label === "string" || typeof args.selector === "string") {
          const rect = await page.evaluate<{ x: number; y: number; width: number; height: number; tag: string; text: string } | null>(
            findElementScript({
              ...(typeof args.label === "string" ? { label: args.label } : {}),
              ...(typeof args.selector === "string" ? { selector: args.selector } : {}),
            }),
          );
          if (!rect) {
            if (typeof args.selector === "string") throw new Error(`Nothing visible matches ${args.selector}`);
            // Not in the page: the browser's own chrome, perhaps. Accessibility knows it.
            return undefined;
          }
          const frame = fromPage(geometry, rect);
          at = { x: frame.x + frame.width / 2, y: frame.y + frame.height / 2 };
          found = { tag: rect.tag, text: rect.text };
        } else {
          const point = readAt(args);
          if (!point) throw new Error("click needs a label, a selector, or a point: { click: \"Search\" } or { click: [x, y] }");
          at = global(point);
        }
        const inPage = toPage(geometry, at);
        if (!within(geometry, inPage)) return undefined;
        await this.aim(at);
        await clickAt(page, inPage, finite(args.holdMs) ?? 0);
        await this.deps.mark({ kind: "click", point: at });
        return { at: round(at), ...(found ? { element: found } : {}) };
      }
      case "type": {
        if (typeof args.text !== "string" || args.text === "") throw new Error('type needs text. End it with "\\n" to submit.');
        await this.markFocused(page, geometry);
        await insertText(page, args.text);
        return { text: args.text };
      }
      case "press": {
        if (typeof args.key !== "string") throw new Error('press needs key: "return", "cmd+l", "⌘⇧T"…');
        const key = devToolsKey(args.key);
        if (!key) return undefined;
        await this.markFocused(page, geometry);
        await pressKey(page, key);
        return { key: args.key };
      }
      case "go": {
        if (typeof args.url !== "string" || !args.url.trim()) throw new Error("go needs url");
        const url = normalizeUrl(args.url);
        const reply = await page.call<{ errorText?: string }>("Page.navigate", { url });
        if (reply.errorText) throw new Error(`${url}: ${reply.errorText}`);
        await waitFor(page, "document.readyState !== 'loading'", 10_000);
        return { url, title: await page.evaluate<string>("document.title") };
      }
      case "drag": {
        const from = readPoint(args.from);
        const to = readPoint(args.to);
        if (!from || !to) throw new Error("drag needs from and to: { drag: [[x, y], [x, y]] }");
        const a = global(from);
        const b = global(to);
        if (!within(geometry, toPage(geometry, a))) return undefined;
        await this.aim(a);
        await dragBetween(page, toPage(geometry, a), toPage(geometry, b), finite(args.durationMs) ?? 200);
        await this.deps.mark({ kind: "drag", point: b, from: a });
        return { from: round(a), to: round(b) };
      }
      case "scroll": {
        const dy = finite(args.dy) ?? 0;
        const dx = finite(args.dx) ?? 0;
        if (dx === 0 && dy === 0) throw new Error("scroll needs dy or dx (wheel pixels; positive dy scrolls up)");
        const point = readAt(args);
        const at = point
          ? global(point)
          : { x: geometry.origin.x + (geometry.width * geometry.zoom) / 2, y: geometry.origin.y + (geometry.height * geometry.zoom) / 2 };
        const inPage = toPage(geometry, at);
        if (!within(geometry, inPage)) return undefined;
        await this.aim(at);
        await wheelAt(page, inPage, dx, dy);
        await this.deps.mark({ kind: "scroll", point: at, dy });
        return { at: round(at), dy, ...(dx ? { dx } : {}) };
      }
      case "js": {
        if (typeof args.code !== "string" || !args.code.trim()) throw new Error("js needs code");
        return { value: await page.evaluate(args.code) };
      }
      default:
        return undefined;
    }
  }

  private async viaBlink(step: LayerStep, status: AgentLayerStatus): Promise<Record<string, unknown>> {
    const subjectBundleId = status.subject?.bundleId ?? status.layer?.windows[0]?.bundleId ?? undefined;
    let action: RuntimeAction;
    switch (step.verb) {
      case "js":
        throw new Error("js runs in a browser page: open the layer with { browser: true } (Chrome with a DevTools port).");
      case "go": {
        if (typeof step.args.url !== "string" || !step.args.url.trim()) throw new Error("go needs url");
        if (!subjectBundleId) throw new Error("go needs the layer opened on an app (bundleId).");
        const url = normalizeUrl(step.args.url);
        action = {
          id: `layer_go_${Date.now().toString(36)}`,
          kind: "open-app",
          description: `open ${url}`,
          input: { bundleId: subjectBundleId, url, background: true },
        };
        break;
      }
      default:
        action = primitiveAction(step.verb as LayerPrimitive, step.args, {
          bounds: status.layer!.bounds,
          view: this.deps.view(),
          ...(subjectBundleId ? { subjectBundleId } : {}),
        });
    }
    const executed = await this.deps.blink(action);
    return { route: "blink", ...(action.input ?? {}), ...(executed.host ? { host: executed.host } : {}) };
  }

  private async wait(args: Args): Promise<Record<string, unknown>> {
    const ms = finite(args.ms);
    if (ms !== undefined) {
      await sleep(Math.min(ms, 30_000));
      return { ms };
    }
    const budget = Math.min(finite(args.timeoutMs) ?? 8_000, 30_000);
    const started = Date.now();
    if (typeof args.text === "string") {
      const status = await this.deps.status();
      const browser = status.layer ? await this.browser(status) : undefined;
      if (!browser) throw new Error("wait for text reads a browser page: open the layer with { browser: true }, or wait for ms.");
      try {
        await waitFor(browser.page, `document.body && document.body.innerText.includes(${JSON.stringify(args.text)})`, budget);
      } finally {
        browser.page.close();
      }
      return { text: args.text, ms: Date.now() - started };
    }
    // Settled: the page done loading, if there is one, and the layer still for a beat.
    // A page's still beat is shorter and capped, since a blinking caret never stops.
    const status = await this.deps.status();
    const browser = status.layer ? await this.browser(status) : undefined;
    if (browser) {
      try {
        await waitFor(browser.page, "document.readyState === 'complete'", budget).catch(() => undefined);
      } finally {
        browser.page.close();
      }
    }
    const still = browser ? 250 : 400;
    const deadline = browser ? Math.min(started + budget, Date.now() + 1_500) : started + budget;
    for (;;) {
      const snapshot = await this.deps.look();
      if ((snapshot.unchangedMs ?? 0) >= still || Date.now() >= deadline) {
        return { until: "settled", ms: Date.now() - started, unchangedMs: snapshot.unchangedMs };
      }
      await sleep(120);
    }
  }

  private async aim(point: LayerPoint): Promise<void> {
    await this.deps.mark({ kind: "aim", point });
    await sleep(AIM_LEAD_MS);
  }

  private async markFocused(page: DevToolsPage, geometry: PageGeometry): Promise<void> {
    const rect = await page.evaluate<{ x: number; y: number; width: number; height: number } | null>(FOCUSED_RECT_SCRIPT).catch(() => null);
    if (rect) await this.deps.mark({ kind: "field", frame: fromPage(geometry, rect) });
  }
}

function finite(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function readAt(args: Args): LayerPoint | undefined {
  const x = finite(args.x);
  const y = finite(args.y);
  return x !== undefined && y !== undefined ? { x, y } : readPoint(args.at);
}

function within(geometry: PageGeometry, point: LayerPoint): boolean {
  return point.x >= 0 && point.y >= 0 && point.x < geometry.width && point.y < geometry.height;
}

function round(point: LayerPoint): LayerPoint {
  return { x: Math.round(point.x), y: Math.round(point.y) };
}

async function waitFor(page: DevToolsPage, condition: string, budgetMs: number): Promise<void> {
  const deadline = Date.now() + budgetMs;
  for (;;) {
    if (await page.evaluate<boolean>(`Boolean(${condition})`).catch(() => false)) return;
    if (Date.now() >= deadline) throw new Error(`timed out after ${budgetMs}ms waiting for ${condition}`);
    await sleep(100);
  }
}

/** A step's result for a run's log: the snapshot path, not the whole snapshot. */
function summarize(result: Record<string, unknown>): Record<string, unknown> {
  const snapshot = result.snapshot as AgentLayerSnapshot | undefined;
  return snapshot ? { ...result, snapshot: { path: snapshot.path, width: snapshot.width, height: snapshot.height } } : result;
}
