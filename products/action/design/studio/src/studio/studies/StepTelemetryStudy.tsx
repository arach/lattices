"use client";

import { ActionFrame, Caption, Chip, LiveDot, PageHeading, Rule } from "@/studio/action/Surface";
import { Note, Prose, StudyShell } from "@/studio/studies/StudyShell";
import type { ActionPage } from "@/studio/studioRegistry";

/**
 * The one missing fact, and what it would unlock.
 *
 * This study is marked CONCEPT and draws data the app does not record yet. It
 * is separated from the Scenarios study on purpose: a shipped study must only
 * draw what exists, or the studio stops being a description of the app and
 * becomes a wish.
 */

type Row = {
  index: number;
  verb: string;
  step: string;
  target: string;
  state: "done" | "live" | "pending";
  took?: string;
};

const ROWS: Row[] = [
  { index: 1, verb: "type", step: "Enter 12", target: "keyboard", state: "done", took: "0.6s" },
  { index: 2, verb: "click", step: "Click plus", target: "calculator.operator.plus", state: "live", took: "1.2s" },
  { index: 3, verb: "type", step: "Enter 30", target: "keyboard", state: "pending" },
  { index: 4, verb: "press-key", step: "Press equals", target: "calculator.operator.equals", state: "pending" },
];

const COLS =
  "var(--act-col-index) var(--act-col-verb) minmax(140px, 1fr) var(--act-col-target) 78px";

const head: React.CSSProperties = {
  fontFamily: "var(--act-mono)",
  fontSize: 9,
  fontWeight: 600,
  letterSpacing: "var(--act-track-label)",
  textTransform: "uppercase",
  color: "var(--act-ink-muted)",
};

export function StepTelemetryStudy({ page }: { page: ActionPage }) {
  return (
    <StudyShell page={page}>
      <Prose>
        Every richer version of running and review needs the same missing fact:{" "}
        <strong>which step is executing, and what each one cost.</strong> The runtime knows — it
        dispatches the actions — but nothing on the scenario records it, so the plan cannot be
        annotated with its own run.
      </Prose>

      <section>
        <h2>What it would look like</h2>
        <Prose>
          No new layout. The grid is the one already shipped; the run appends a fifth column and
          tints one row. Coral marks the live step and stays the only colour on the page.
        </Prose>
        <ActionFrame>
          <PageHeading eyebrow="Running · step 2 of 4" title="Calculator demo" switcher />
          <div style={{ marginTop: 26 }}>
            <div style={{ display: "grid", gridTemplateColumns: COLS, paddingBottom: 7 }}>
              <div style={head}>#</div>
              <div style={head}>Verb</div>
              <div style={head}>Step</div>
              <div style={{ ...head, textAlign: "right" }}>Target</div>
              <div style={{ ...head, textAlign: "right" }}>Took</div>
            </div>
            <Rule />
            {ROWS.map((r) => (
              <div
                key={r.index}
                style={{
                  display: "grid",
                  gridTemplateColumns: COLS,
                  alignItems: "baseline",
                  padding: "10px 12px",
                  margin: "0 -12px",
                  borderRadius: 4,
                  background: r.state === "live" ? "var(--act-coral-soft)" : "transparent",
                }}
              >
                <span style={{ fontFamily: "var(--act-mono)", fontSize: 11, color: "var(--act-ink-muted)" }}>
                  {String(r.index).padStart(2, "0")}
                </span>
                <span style={{ fontFamily: "var(--act-mono)", fontSize: 11, color: "var(--act-ink-2)" }}>
                  {r.verb}
                </span>
                <span
                  style={{
                    fontSize: 13,
                    color: r.state === "pending" ? "var(--act-ink-2)" : "var(--act-ink)",
                    fontWeight: r.state === "live" ? 600 : 400,
                  }}
                >
                  {r.step}
                </span>
                <span
                  style={{
                    fontFamily: "var(--act-mono)",
                    fontSize: 11,
                    color: "var(--act-ink-muted)",
                    textAlign: "right",
                  }}
                >
                  {r.target}
                </span>
                <span
                  style={{
                    fontFamily: "var(--act-mono)",
                    fontSize: 11,
                    textAlign: "right",
                    color:
                      r.state === "live"
                        ? "var(--act-coral)"
                        : r.state === "done"
                          ? "#3E7A4E"
                          : "var(--act-ink-muted)",
                  }}
                >
                  {r.state === "done" ? `✓ ${r.took}` : r.state === "live" ? `▶ ${r.took}` : "—"}
                </span>
              </div>
            ))}
            <Rule soft />
          </div>
          <div style={{ display: "flex", gap: 12, alignItems: "center", marginTop: 22 }}>
            <LiveDot />
            <span style={{ fontFamily: "var(--act-mono)", fontSize: 11, color: "var(--act-ink-2)" }}>
              00:07 · step 2 of 4
            </span>
            <Chip>Stop</Chip>
          </div>
        </ActionFrame>
        <Caption>Concept — this data does not exist yet</Caption>
      </section>

      <Note title="What it costs">
        Write a <code>runStatus</code> and a <code>durationMs</code> per step during a drive and
        three things follow at once: the executing row lights while it runs; the review table gains
        a truthful <code>TOOK</code> column; and clicking a review row can scrub the video to that
        step, because the row already knows its own timestamp. Today{" "}
        <code>ActionScenarioStep.status</code> holds authoring state only —{" "}
        <code>pending / approved / flagged / skipped</code> — and is written by the note and skip
        controls, never by a run.
      </Note>
    </StudyShell>
  );
}
