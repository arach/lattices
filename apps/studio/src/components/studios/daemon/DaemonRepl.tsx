import { useEffect, useState } from "react";
import { daemonCall } from "../../../lib/daemon";

const SUGGESTIONS = [
  "tile Chrome right",
  "tile iTerm left",
  "distribute Chrome",
  "search W",
  "focus Notes",
];

interface SimulateResult {
  parsed: boolean;
  text: string;
  intent: string | null;
  slots?: Record<string, unknown>;
  confidence?: number;
  executed?: boolean;
  result?: unknown;
  error?: string;
  message?: string;
}

interface WindowRow {
  wid: number;
  app: string;
  title?: string;
  frame?: { x: number; y: number; w: number; h: number };
  isOnScreen?: boolean;
}

interface TerminalRow {
  app?: string;
  tabTitle?: string;
  cwd?: string;
  hasClaude?: boolean;
}

interface SpaceRow {
  id: number;
  index: number;
  name?: string;
  isCurrent: boolean;
}

interface DisplayRow {
  displayIndex: number;
  displayId: string;
  currentSpaceId: number;
  spaces: SpaceRow[];
}

interface IntentDef {
  name: string;
  description?: string;
  examples?: string[];
}

interface Turn {
  prompt: string;
  startedAt: number;
  reasoningMs?: number;
  windowsMs?: number;
  terminalsMs?: number;
  spacesMs?: number;
  windows?: WindowRow[];
  terminals?: TerminalRow[];
  displays?: DisplayRow[];
  reasoning?: SimulateResult;
  error?: string;
}

interface Execution {
  prompt: string;
  startedAt: number;
  durationMs: number;
  result?: SimulateResult;
  error?: string;
}

async function timed<T>(promise: Promise<T>): Promise<{ value: T; ms: number }> {
  const t0 = performance.now();
  const value = await promise;
  return { value, ms: Math.round(performance.now() - t0) };
}

export function DaemonRepl() {
  const [prompt, setPrompt] = useState("");
  const [running, setRunning] = useState(false);
  const [turn, setTurn] = useState<Turn | null>(null);
  const [executing, setExecuting] = useState(false);
  const [execution, setExecution] = useState<Execution | null>(null);
  const [intents, setIntents] = useState<IntentDef[] | null>(null);

  // Load the intent catalog once for the "what could match?" affordance.
  // Errors are silent — this is decorative.
  useEffect(() => {
    let cancelled = false;
    daemonCall<IntentDef[]>("intents.list")
      .then((list) => {
        if (!cancelled) setIntents(list);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  async function runTurn(text: string) {
    const trimmed = text.trim();
    if (!trimmed || running) return;
    const startedAt = Date.now();
    setRunning(true);
    setExecution(null);
    setTurn({ prompt: trimmed, startedAt });

    const winP = timed(daemonCall<WindowRow[]>("windows.list")).catch(
      (err: Error) => ({ error: err.message, ms: 0 }),
    );
    const termP = timed(daemonCall<TerminalRow[]>("terminals.list")).catch(
      (err: Error) => ({ error: err.message, ms: 0 }),
    );
    const spacesP = timed(daemonCall<DisplayRow[]>("spaces.list")).catch(
      (err: Error) => ({ error: err.message, ms: 0 }),
    );
    const reasoningP = timed(
      daemonCall<SimulateResult>("voice.simulate", {
        text: trimmed,
        execute: false,
      }),
    ).catch((err: Error) => ({ error: err.message, ms: 0 }));

    const [winR, termR, spacesR, reasoningR] = await Promise.all([
      winP,
      termP,
      spacesP,
      reasoningP,
    ]);

    const next: Turn = {
      prompt: trimmed,
      startedAt,
    };
    if ("error" in winR) next.error = `windows.list: ${winR.error}`;
    else {
      next.windows = winR.value;
      next.windowsMs = winR.ms;
    }
    if ("error" in termR) {
      // soft-fail on terminals; not fatal
    } else {
      next.terminals = termR.value;
      next.terminalsMs = termR.ms;
    }
    if ("error" in spacesR) {
      // soft-fail on displays; not fatal
    } else {
      next.displays = spacesR.value;
      next.spacesMs = spacesR.ms;
    }
    if ("error" in reasoningR) next.error = (next.error ? next.error + " · " : "") + `voice.simulate: ${reasoningR.error}`;
    else {
      next.reasoning = reasoningR.value;
      next.reasoningMs = reasoningR.ms;
    }

    setTurn(next);
    setRunning(false);
  }

  async function fireTurn() {
    if (!turn || executing) return;
    const startedAt = Date.now();
    setExecuting(true);
    try {
      const t0 = performance.now();
      const result = await daemonCall<SimulateResult>("voice.simulate", {
        text: turn.prompt,
        execute: true,
      });
      setExecution({
        prompt: turn.prompt,
        startedAt,
        durationMs: Math.round(performance.now() - t0),
        result,
      });
    } catch (err) {
      setExecution({
        prompt: turn.prompt,
        startedAt,
        durationMs: Date.now() - startedAt,
        error: err instanceof Error ? err.message : String(err),
      });
    } finally {
      setExecuting(false);
    }
  }

  function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    runTurn(prompt);
  }

  const canRun = prompt.trim().length > 0 && !running;
  const hasIntent = !!turn?.reasoning?.parsed && !!turn.reasoning.intent;
  const canFire = hasIntent && !executing;

  return (
    <div className="mt-10 flex flex-col gap-10">
      <PromptPane
        prompt={prompt}
        onPrompt={setPrompt}
        onSubmit={onSubmit}
        onSuggestion={(s) => {
          setPrompt(s);
          runTurn(s);
        }}
        running={running}
        canRun={canRun}
      />

      {turn ? (
        <>
          <SnapshotPane turn={turn} />
          <ReasoningPane turn={turn} intents={intents} />
          <ActionsPane turn={turn} />
          <ExecutePane
            turn={turn}
            execution={execution}
            executing={executing}
            canFire={canFire}
            onFire={fireTurn}
          />
        </>
      ) : (
        <p className="font-mono text-[11px] text-studio-ink-faint">
          Type something to start a turn.
        </p>
      )}
    </div>
  );
}

function PaneHeading({
  step,
  title,
  meta,
}: {
  step: string;
  title: string;
  meta?: string;
}) {
  return (
    <div className="flex items-baseline justify-between border-b border-studio-edge pb-2">
      <div className="flex items-baseline gap-3">
        <span className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
          {step}
        </span>
        <h3 className="font-mono text-[13px] text-studio-ink">{title}</h3>
      </div>
      {meta ? (
        <span className="font-mono text-[10px] text-studio-ink-faint tabular-nums">
          {meta}
        </span>
      ) : null}
    </div>
  );
}

function PromptPane({
  prompt,
  onPrompt,
  onSubmit,
  onSuggestion,
  running,
  canRun,
}: {
  prompt: string;
  onPrompt: (v: string) => void;
  onSubmit: (e: React.FormEvent) => void;
  onSuggestion: (s: string) => void;
  running: boolean;
  canRun: boolean;
}) {
  return (
    <section>
      <PaneHeading step="01 · prompt" title="Turn input" />
      <form onSubmit={onSubmit} className="mt-4 flex flex-col gap-3">
        <div className="flex items-stretch gap-2">
          <input
            value={prompt}
            onChange={(e) => onPrompt(e.target.value)}
            placeholder="say something the agent would hear…"
            disabled={running}
            spellCheck={false}
            autoFocus
            className="flex-1 rounded-sm border border-studio-edge bg-transparent px-3 py-2.5 font-mono text-[13px] text-studio-ink outline-none focus:border-[color:var(--scout-accent)] disabled:opacity-50"
          />
          <button
            type="submit"
            disabled={!canRun}
            className={[
              "shrink-0 rounded-sm border px-4 py-2 font-mono text-[11px] uppercase tracking-[0.18em] transition-colors",
              canRun
                ? "border-[color:var(--scout-accent)] text-[color:var(--scout-accent)] hover:bg-[color:var(--studio-edge)]"
                : "border-studio-edge text-studio-ink-faint",
            ].join(" ")}
          >
            {running ? "running…" : "run turn"}
          </button>
        </div>
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="mr-1 font-mono text-[9.5px] uppercase tracking-[0.22em] text-studio-ink-faint">
            try
          </span>
          {SUGGESTIONS.map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => onSuggestion(s)}
              disabled={running}
              className="rounded-full border border-studio-edge px-2.5 py-1 font-mono text-[10.5px] text-studio-ink-faint transition-colors hover:border-studio-ink-faint hover:text-studio-ink disabled:opacity-50"
            >
              {s}
            </button>
          ))}
        </div>
      </form>
    </section>
  );
}

function SnapshotPane({ turn }: { turn: Turn }) {
  const winCount = turn.windows?.length;
  const termCount = turn.terminals?.length;
  const onScreen = turn.windows?.filter((w) => w.isOnScreen !== false).length;
  const meta = [
    turn.windowsMs !== undefined ? `${turn.windowsMs}ms · windows.list` : null,
    turn.terminalsMs !== undefined ? `${turn.terminalsMs}ms · terminals.list` : null,
    turn.spacesMs !== undefined ? `${turn.spacesMs}ms · spaces.list` : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <section>
      <PaneHeading step="02 · snapshot" title="What the agent sees" meta={meta} />
      {turn.displays && turn.displays.length ? (
        <DisplaysStrip displays={turn.displays} />
      ) : null}
      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        <Block label={`windows · ${winCount ?? "—"}${onScreen != null ? ` · ${onScreen} on screen` : ""}`}>
          {turn.windows ? (
            <ScrollList>
              {turn.windows.slice(0, 12).map((w) => (
                <li
                  key={w.wid}
                  className="flex items-baseline justify-between gap-2 border-b border-studio-edge py-1 last:border-b-0"
                >
                  <span className="truncate font-sans text-[12.5px] text-studio-ink">
                    <span className="text-studio-ink-faint">{w.app}</span>
                    {w.title ? ` · ${w.title}` : ""}
                  </span>
                  <span className="shrink-0 font-mono text-[10px] text-studio-ink-faint tabular-nums">
                    #{w.wid}
                  </span>
                </li>
              ))}
              {turn.windows.length > 12 ? (
                <li className="pt-1 font-mono text-[10px] text-studio-ink-faint">
                  + {turn.windows.length - 12} more
                </li>
              ) : null}
            </ScrollList>
          ) : (
            <p className="font-mono text-[10.5px] text-studio-ink-faint">no data</p>
          )}
        </Block>
        <Block label={`terminals · ${termCount ?? "—"}`}>
          {turn.terminals && turn.terminals.length ? (
            <ScrollList>
              {turn.terminals.slice(0, 10).map((t, i) => (
                <li
                  key={i}
                  className="flex items-baseline justify-between gap-2 border-b border-studio-edge py-1 last:border-b-0"
                >
                  <span className="truncate font-sans text-[12.5px] text-studio-ink">
                    <span className="text-studio-ink-faint">{t.app ?? "term"}</span>
                    {t.tabTitle ? ` · ${t.tabTitle}` : ""}
                  </span>
                  {t.hasClaude ? (
                    <span
                      className="shrink-0 font-mono text-[9px] uppercase tracking-[0.18em]"
                      style={{ color: "var(--scout-accent)" }}
                    >
                      claude
                    </span>
                  ) : null}
                </li>
              ))}
              {turn.terminals.length > 10 ? (
                <li className="pt-1 font-mono text-[10px] text-studio-ink-faint">
                  + {turn.terminals.length - 10} more
                </li>
              ) : null}
            </ScrollList>
          ) : (
            <p className="font-mono text-[10.5px] text-studio-ink-faint">no data</p>
          )}
        </Block>
      </div>
    </section>
  );
}

function ReasoningPane({
  turn,
  intents,
}: {
  turn: Turn;
  intents: IntentDef[] | null;
}) {
  const r = turn.reasoning;
  const meta = turn.reasoningMs !== undefined ? `${turn.reasoningMs}ms · voice.simulate` : undefined;
  const noMatch = r !== undefined && !r.parsed;

  return (
    <section>
      <PaneHeading step="03 · reasoning" title="Phrase match · fast path" meta={meta} />
      <p className="mt-2 max-w-2xl text-[12px] leading-relaxed text-studio-ink-faint">
        Deterministic rule-based matcher. Handles the command vocabulary
        below. Open-ended questions go to the LLM-backed handsoff loop —{" "}
        <em>coming next</em>.
      </p>

      <MethodInspector turn={turn} />

      {turn.error && !r ? (
        <p className="mt-4 font-mono text-[11.5px] text-[color:var(--status-error-fg)]">
          {turn.error}
        </p>
      ) : r ? (
        <div className="mt-4 grid gap-4 sm:grid-cols-[1fr_220px]">
          <Block label="response">
            <pre className="overflow-x-auto font-mono text-[11.5px] leading-[1.55] text-studio-ink">
              {JSON.stringify(r, null, 2)}
            </pre>
          </Block>
          <Block label="summary">
            <Row label="parsed">
              <Pill
                tone={r.parsed ? "ok" : "warn"}
                label={r.parsed ? "matched" : "no match"}
              />
            </Row>
            {r.intent ? <Row label="intent">{r.intent}</Row> : null}
            {r.confidence !== undefined ? (
              <Row label="confidence">{Math.round(r.confidence * 100)}%</Row>
            ) : null}
            {r.message ? (
              <Row label="message">
                <span className="text-studio-ink-faint">{r.message}</span>
              </Row>
            ) : null}
          </Block>
        </div>
      ) : (
        <p className="mt-4 font-mono text-[11px] text-studio-ink-faint">
          probing…
        </p>
      )}

      {noMatch && intents ? <IntentVocab intents={intents} /> : null}
    </section>
  );
}

function MethodInspector({ turn }: { turn: Turn }) {
  const [expanded, setExpanded] = useState(false);
  const requestPayload = {
    method: "voice.simulate",
    params: { text: turn.prompt, execute: false },
  };

  return (
    <div className="mt-4 rounded-sm border border-studio-edge bg-[color:var(--studio-canvas)]">
      <button
        type="button"
        onClick={() => setExpanded((v) => !v)}
        className="flex w-full items-center justify-between gap-3 px-4 py-2.5 text-left transition-colors hover:bg-[color:var(--studio-edge)]"
        aria-expanded={expanded}
      >
        <div className="flex items-baseline gap-3">
          <span className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
            method
          </span>
          <span className="font-mono text-[12px] text-studio-ink">
            voice.simulate
          </span>
          <ImplBadge tone="neutral" label="deterministic" />
          <span className="font-mono text-[10px] text-studio-ink-faint">
            no LLM
          </span>
        </div>
        <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-studio-ink-faint">
          {expanded ? "− collapse" : "+ unpack"}
        </span>
      </button>

      {expanded ? (
        <div className="border-t border-studio-edge p-4">
          <div className="grid gap-4 sm:grid-cols-[1fr_1fr]">
            <div className="flex flex-col gap-1.5">
              <Row label="endpoint">
                <span className="font-mono text-[12px] text-studio-ink">
                  voice.simulate
                </span>
              </Row>
              <Row label="impl">
                <span className="font-mono text-[12px] text-studio-ink">
                  PhraseMatcher.shared
                </span>
              </Row>
              <Row label="type">
                <span className="font-mono text-[12px] text-studio-ink">
                  rule-based · pattern bind
                </span>
              </Row>
              <Row label="model">
                <span className="font-mono text-[12px] text-studio-ink-faint">
                  — no model involved
                </span>
              </Row>
              <Row label="prompt">
                <span className="font-mono text-[12px] text-studio-ink-faint">
                  — no system prompt
                </span>
              </Row>
              <Row label="tokens">
                <span className="font-mono text-[12px] text-studio-ink-faint">
                  — n/a
                </span>
              </Row>
            </div>

            <div className="flex flex-col gap-3">
              <div>
                <p className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
                  request · sent to daemon
                </p>
                <pre className="mt-2 overflow-x-auto rounded-sm border border-studio-edge bg-[color:var(--code-bg)] p-3 font-mono text-[11px] leading-[1.55] text-studio-ink">
                  {JSON.stringify(requestPayload, null, 2)}
                </pre>
              </div>
              <div>
                <p className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
                  not sent
                </p>
                <ul className="mt-2 space-y-0.5 font-mono text-[10.5px] text-studio-ink-faint">
                  <li>· snapshot (windows / terminals / displays)</li>
                  <li>· system prompt</li>
                  <li>· conversation history</li>
                  <li>· user identity / preferences</li>
                </ul>
              </div>
            </div>
          </div>

          <p className="mt-4 max-w-2xl text-[11.5px] leading-relaxed text-studio-ink-faint">
            The phrase matcher binds the raw input against a hardcoded set of
            patterns and returns the matched intent + slots. No LLM is
            consulted; the snapshot you see above is purely decorative for
            this path. When the LLM-backed handsoff endpoint lands, this
            inspector will surface model, system prompt, the actual snapshot
            slice sent, and token usage.
          </p>
        </div>
      ) : null}
    </div>
  );
}

function ImplBadge({
  tone,
  label,
}: {
  tone: "neutral" | "accent";
  label: string;
}) {
  const color =
    tone === "accent" ? "var(--scout-accent)" : "var(--status-neutral-fg)";
  return (
    <span
      className="rounded-[3px] border px-1.5 py-0.5 font-mono text-[9px] font-semibold uppercase tracking-[0.18em]"
      style={{ color, borderColor: color }}
    >
      {label}
    </span>
  );
}

function IntentVocab({ intents }: { intents: IntentDef[] }) {
  return (
    <div className="mt-4 rounded-sm border border-studio-edge bg-[color:var(--studio-canvas)] p-4">
      <p className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
        what could match · {intents.length} intents
      </p>
      <ul className="mt-3 flex flex-wrap gap-1.5">
        {intents.map((intent) => (
          <li
            key={intent.name}
            title={intent.description ?? intent.name}
            className="rounded-full border border-studio-edge px-2.5 py-1 font-mono text-[10.5px] text-studio-ink-faint"
          >
            {intent.name}
          </li>
        ))}
      </ul>
    </div>
  );
}

function DisplaysStrip({ displays }: { displays: DisplayRow[] }) {
  return (
    <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      {displays.map((d) => {
        const current = d.spaces.find((s) => s.isCurrent);
        return (
          <div
            key={d.displayId}
            className="rounded-sm border border-studio-edge bg-[color:var(--studio-canvas)] p-4"
          >
            <div className="flex items-baseline justify-between">
              <p className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
                display · {d.displayIndex}
              </p>
              <span className="font-mono text-[9.5px] text-studio-ink-faint truncate ml-2">
                {d.displayId.slice(0, 10)}
              </span>
            </div>
            <p className="mt-2 font-mono text-[12px] text-studio-ink">
              {d.spaces.length} space{d.spaces.length === 1 ? "" : "s"}
              {current ? (
                <>
                  <span className="text-studio-ink-faint"> · current </span>
                  <span style={{ color: "var(--scout-accent)" }}>
                    {current.name ?? `#${current.index}`}
                  </span>
                </>
              ) : null}
            </p>
          </div>
        );
      })}
    </div>
  );
}

function ActionsPane({ turn }: { turn: Turn }) {
  const r = turn.reasoning;
  return (
    <section>
      <PaneHeading step="04 · actions" title="Intent + slots" />
      {r?.parsed && r.intent ? (
        <div className="mt-4 rounded-sm border border-studio-edge bg-[color:var(--studio-canvas)] p-4">
          <div className="flex items-baseline justify-between gap-3 border-b border-studio-edge pb-2">
            <p
              className="font-mono text-[13px]"
              style={{ color: "var(--scout-accent)" }}
            >
              {r.intent}
            </p>
            {r.confidence !== undefined ? (
              <p className="font-mono text-[10px] text-studio-ink-faint">
                {Math.round(r.confidence * 100)}% confidence
              </p>
            ) : null}
          </div>
          <div className="mt-3 flex flex-col gap-2">
            {r.slots && Object.keys(r.slots).length ? (
              Object.entries(r.slots).map(([key, value]) => (
                <Row key={key} label={key}>
                  <span className="font-mono text-[12px] text-studio-ink">
                    {typeof value === "string" ? value : JSON.stringify(value)}
                  </span>
                </Row>
              ))
            ) : (
              <p className="font-mono text-[10.5px] text-studio-ink-faint">no slots</p>
            )}
          </div>
        </div>
      ) : (
        <p className="mt-4 font-mono text-[11px] text-studio-ink-faint">
          {r?.message ?? "no intent — the phrase matcher didn't bind"}
        </p>
      )}
    </section>
  );
}

function ExecutePane({
  turn,
  execution,
  executing,
  canFire,
  onFire,
}: {
  turn: Turn;
  execution: Execution | null;
  executing: boolean;
  canFire: boolean;
  onFire: () => void;
}) {
  const callJson = JSON.stringify(
    {
      method: "voice.simulate",
      params: { text: turn.prompt, execute: true },
    },
    null,
    2,
  );
  return (
    <section>
      <PaneHeading
        step="05 · execute"
        title="Fire for real"
        meta={execution ? `${execution.durationMs}ms` : undefined}
      />
      <div className="mt-4 grid gap-4 sm:grid-cols-[1fr_220px]">
        <Block label="daemon call">
          <pre className="overflow-x-auto font-mono text-[11.5px] leading-[1.55] text-studio-ink">
            {callJson}
          </pre>
        </Block>
        <div className="flex flex-col gap-3">
          <button
            type="button"
            disabled={!canFire}
            onClick={onFire}
            className={[
              "rounded-sm border px-3 py-3 font-mono text-[11px] uppercase tracking-[0.18em] transition-colors",
              canFire
                ? "border-[color:var(--scout-accent)] bg-[color:var(--studio-canvas)] text-[color:var(--scout-accent)] hover:bg-[color:var(--studio-edge)]"
                : "border-studio-edge text-studio-ink-faint",
            ].join(" ")}
          >
            {executing ? "firing…" : "↗ fire it"}
          </button>
          {!canFire && !executing ? (
            <p className="font-mono text-[10px] text-studio-ink-faint">
              need a parsed intent first
            </p>
          ) : null}
        </div>
      </div>

      {execution ? (
        <div className="mt-4">
          {execution.error ? (
            <Block label="error">
              <p className="font-mono text-[11.5px] text-[color:var(--status-error-fg)]">
                {execution.error}
              </p>
            </Block>
          ) : (
            <Block
              label={
                execution.result?.executed
                  ? "result · executed"
                  : "result · not executed"
              }
            >
              <pre className="overflow-x-auto font-mono text-[11.5px] leading-[1.55] text-studio-ink">
                {JSON.stringify(execution.result, null, 2)}
              </pre>
            </Block>
          )}
        </div>
      ) : null}
    </section>
  );
}

function Block({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-sm border border-studio-edge bg-[color:var(--studio-canvas)] p-4">
      <p className="mb-2 font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
        {label}
      </p>
      {children}
    </div>
  );
}

function ScrollList({ children }: { children: React.ReactNode }) {
  return (
    <ul className="max-h-[280px] overflow-y-auto pr-1">{children}</ul>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-studio-edge py-1.5 last:border-b-0">
      <span className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
        {label}
      </span>
      <span className="min-w-0 text-right">{children}</span>
    </div>
  );
}

function Pill({ tone, label }: { tone: "ok" | "warn"; label: string }) {
  return (
    <span
      className="inline-block rounded-[3px] px-1.5 py-0.5 font-mono text-[9px] font-semibold uppercase tracking-[0.18em]"
      style={{
        color: `var(--status-${tone}-fg)`,
        background: `var(--status-${tone}-bg)`,
      }}
    >
      {label}
    </span>
  );
}
