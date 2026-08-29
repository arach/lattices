"use client";

import { useState } from "react";
import {
  ActionFrame,
  Caption,
  Chip,
  Field,
  LiveDot,
  Meta,
  PageHeading,
  PlanTable,
  QuietButton,
  type Step,
} from "@/studio/action/Surface";
import { StudyShell, Note, Prose } from "@/studio/studies/StudyShell";
import type { ActionPage } from "@/studio/studioRegistry";

/**
 * Scenarios — one table, three states.
 *
 * The argument: a scenario is a list of instructions and it stays a list of
 * instructions the whole way through. The grid is fixed and never rearranges;
 * a state appends a column rather than redrawing the table.
 */

const PRESET: Step[] = [
  { index: 1, verb: "type", step: "Enter 12", target: "keyboard" },
  { index: 2, verb: "click", step: "Click plus", target: "calculator.operator.plus" },
  { index: 3, verb: "type", step: "Enter 30", target: "keyboard" },
  { index: 4, verb: "press-key", step: "Press equals", target: "calculator.operator.equals" },
];

const ANNOTATED: Step[] = PRESET.map((s) =>
  // Deliberately not the same string as the field's placeholder: a saved note
  // and an empty field showing an example are two different things, and
  // printing one sentence twice made them look like one duplicated row.
  s.index === 2 ? { ...s, note: "Calculator can be slow to open cold" } : s,
);

export function ScenariosStudy({ page }: { page: ActionPage }) {
  const [openIndex, setOpenIndex] = useState<number | null>(2);

  return (
    <StudyShell page={page}>
      <Prose>
        The start page found the right object — a plan, ruled, on paper. Press Start and the app
        used to forget it: the same four steps came back as cards inside cards. Four cards, three
        of them holding more cards, to show four steps.
      </Prose>

      <section>
        <h2>Plan</h2>
        <Prose>
          Click a step to open it. The note hangs under the column it belongs to, and the tint holds
          the row and what it opened as one band — the same click-to-open-context pattern the Home
          ledger uses.
        </Prose>
        <ActionFrame>
          <PageHeading eyebrow="Plan" title="Calculator demo" switcher />
          <div style={{ marginTop: 26 }}>
            <PlanTable
              steps={ANNOTATED}
              openIndex={openIndex}
              onToggle={(i) => setOpenIndex(openIndex === i ? null : i)}
            />
          </div>
          <div style={{ marginTop: 24 }}>
            <Field label="Goal" value="Calculator, keyboard and click" />
          </div>
          <div style={{ display: "flex", gap: 12, alignItems: "center", marginTop: 22 }}>
            <QuietButton shortcut="⏎">Run</QuietButton>
            <Meta>Calculator · 4 steps</Meta>
          </div>
        </ActionFrame>
        <Caption>Live — the step rows respond</Caption>
      </section>

      <section>
        <h2>Running</h2>
        <Prose>
          Nothing moves. The goal field and Run are gone for the duration, Stop takes the one slot
          that stays, and rows stop responding so the table cannot be annotated out from under the
          run that is executing it.
        </Prose>
        <ActionFrame>
          <PageHeading eyebrow="Running" title="Calculator demo" switcher />
          <div style={{ marginTop: 26 }}>
            <PlanTable steps={ANNOTATED} interactive={false} />
          </div>
          <div style={{ display: "flex", gap: 12, alignItems: "center", marginTop: 22 }}>
            <LiveDot />
            <span style={{ fontFamily: "var(--act-mono)", fontSize: 11, color: "var(--act-ink-2)" }}>
              Driving Calculator
            </span>
            <Chip>Stop</Chip>
          </div>
        </ActionFrame>
        <Caption>One coral dot, and no colour anywhere else</Caption>
      </section>

      <section>
        <h2>Review</h2>
        <Prose>
          The take is the one graphite object on the page, which is honest — it is a recording of a
          screen, not a document. The plan below it reads exactly as it did before the run.
        </Prose>
        <ActionFrame>
          <PageHeading eyebrow="Take · 2 mins ago" title="Calculator demo" switcher />
          <div
            style={{
              marginTop: 22,
              background: "var(--act-deep)",
              borderRadius: 8,
              height: 190,
              display: "flex",
              alignItems: "flex-end",
              justifyContent: "space-between",
              padding: "14px 16px",
              color: "var(--act-on-deep-meta)",
              fontFamily: "var(--act-mono)",
              fontSize: 10.5,
              letterSpacing: "0.06em",
            }}
          >
            <span>10 × 7 · = 70</span>
            <span>00:05 · 1440 × 900</span>
          </div>
          <div style={{ marginTop: 20 }}>
            <PlanTable steps={ANNOTATED} interactive={false} />
          </div>
          <div style={{ display: "flex", gap: 12, alignItems: "center", marginTop: 22 }}>
            <QuietButton>Run again</QuietButton>
            <Chip>Plan</Chip>
            <Chip>Replay</Chip>
            <Chip>Finder</Chip>
          </div>
        </ActionFrame>
        <Caption>The eyebrow carries the age of the take, so the state is stated</Caption>
      </section>

      <Note title="Where the list lives">
        The scenario name <em>is</em> the switcher. A chip beside the page name printed the same
        words twice — and with one scenario saved, printed them twice to offer a choice of one. The
        34pt name carries a small chevron and owns the menu: every scenario, New, Delete, Open in
        Library. The counter appears only when there is more than one.
      </Note>

      <Note title="What is not drawn here">
        The first version of this study appended a <code>TOOK</code> column with per-step durations
        and lit the executing row in coral. Action records neither.{" "}
        <code>ActionScenarioStep.status</code> is authoring state —{" "}
        <code>pending / approved / flagged / skipped</code> — not run progress. Drawing that column
        would have been a mock of telemetry that does not exist. See the{" "}
        <strong>Step telemetry</strong> study for what writing it would unlock.
      </Note>
    </StudyShell>
  );
}
