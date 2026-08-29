"use client";

import { useState } from "react";
import { PLAN, SESSIONS } from "@/studio/action/fixtures";
import { Chip, PlanTable, QuietButton } from "@/studio/action/Surface";

/**
 * One table, three states.
 *
 * A scenario is a list of instructions and it stays a list of instructions the
 * whole way through. Two columns: the left is the scenario itself — goal, the
 * table, the one control the state offers — and the right is a fixed
 * `--act-aside-width` aside of facts about the document, ruled like the table
 * it stands beside. Everything a state adds goes in the aside,
 * which is what finally makes the old claim true: the table's top edge is at
 * the same y in Plan, Running and Review. It used to move 210pt down in Review
 * because the take poster was inserted above it.
 *
 * The aside is also the answer to the width problem. Scenarios is capped at a
 * reading measure and left-aligned, so a wide window used to leave 500pt of
 * nothing at the right edge. Letting the table grow into it would strand
 * "keyboard" a foot away from "Enter 12"; centring it would unpin the table
 * from the header and rail it shares a left edge with. A second right-anchored
 * column turns the empty band into a gutter between two things.
 */

export type ScenarioState = "plan" | "running" | "review";

const mono = "var(--act-mono)";

export function ScenariosSection({ state }: { state: ScenarioState }) {
  const [open, setOpen] = useState<number | null>(2);
  const interactive = state === "plan";

  return (
    <div
      style={{
        display: "grid",
        gridTemplateColumns: "minmax(420px, 1fr) var(--act-aside-width)",
        columnGap: 36,
        // Load-bearing: without it the aside stretches to the table's height and
        // the poster grows out of its 16:10.
        alignItems: "start",
        // Composed from its parts rather than written as 1040: the reading
        // measure, the gutter, and the aside. Stated that way the number cannot
        // drift out of agreement with the columns it is the sum of.
        maxWidth: "calc(var(--act-page-width) + 36px + var(--act-aside-width))",
      }}
    >
      <div>
        <Goal />

        <div style={{ marginTop: 20 }}>
          <PlanTable
            steps={PLAN}
            openIndex={open}
            onToggle={(i) => setOpen(open === i ? null : i)}
            interactive={interactive}
          />
        </div>

        {/* One primary per state. */}
        <div style={{ display: "flex", gap: 12, alignItems: "center", marginTop: 22 }}>
          {state === "plan" && (
            <>
              <QuietButton shortcut="⏎">Run</QuietButton>
              <Chip>Last take</Chip>
            </>
          )}
          {/* Stop is the only way to halt an agent driving the operator's Mac,
              so it gets the primary. The coral dot and "Driving Calculator"
              moved to the masthead: the state of the run belongs where the page
              names itself, not next to the button that ends it. */}
          {state === "running" && <QuietButton>Stop</QuietButton>}
          {state === "review" && (
            <>
              <QuietButton>Run again</QuietButton>
              <Chip>Plan</Chip>
              <Chip>Replay</Chip>
              <Chip>Finder</Chip>
            </>
          )}
        </div>
      </div>

      {/* gap: 0 because the facts are ruled now, and a gap on top of a rule
          doubles the separator. Each fact carries its own top edge, so the
          column has one and reads as a table of the document's fields rather
          than as loose pairs floating on bare paper. Every other tabular thing
          in this window is ruled; this is the same object as its neighbour. */}
      <aside style={{ display: "grid", gap: 0 }}>
        {state === "review" && (
          <>
            {/* The poster takes no rule: it is an object, not a fact, so the
                column of facts starts under it at RESULT. */}
            <TakeStage />
            <AsideFact label="RESULT">{SESSIONS[0].result}</AsideFact>
          </>
        )}
        <AsideFact label="TARGET">Calculator · com.apple.calculator</AsideFact>
        {/* STEPS is gone. The table two inches to the left is numbered 01 02 03
            04, so the aside was spending a slot restating what the reader can
            count. Three facts against a 500pt table is short, and true; the
            alternative is inventing a fourth. */}
        <AsideFact label="TAKES">3</AsideFact>
        <AsideFact label="UPDATED">14:22</AsideFact>
      </aside>
    </div>
  );
}

/**
 * The goal, stated as a line rather than a field. `Field` draws a rule under
 * its value, which on a page with no other inputs reads as a text box the
 * operator is meant to type in — and the goal is not edited here.
 */
function Goal() {
  return (
    <div>
      <div
        style={{
          fontFamily: mono,
          fontSize: 9,
          fontWeight: 600,
          letterSpacing: "var(--act-track-label)",
          color: "var(--act-ink-muted)",
        }}
      >
        GOAL
      </div>
      <div style={{ fontSize: "var(--act-row)", color: "var(--act-ink)", marginTop: 4 }}>
        Calculator, keyboard and click
      </div>
    </div>
  );
}

/** One fact from the scenario document. Nothing here is invented; each line is
 *  a field the runtime writes — RESULT reads `Session.result` off the fixture
 *  rather than being typed out beside it.
 *
 *  The rule is on top rather than underneath so the last fact does not close
 *  the column with an edge that promises another line. 9 above and 11 below
 *  because the label sits high in its own box and the value sits low in it. */
function AsideFact({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div
      style={{
        borderTop: "1px solid var(--act-rule-soft)",
        paddingTop: 9,
        paddingBottom: 11,
      }}
    >
      <div
        style={{
          fontFamily: mono,
          fontSize: 9,
          fontWeight: 600,
          letterSpacing: "var(--act-track-label)",
          color: "var(--act-ink-muted)",
        }}
      >
        {label}
      </div>
      <div style={{ fontSize: "var(--act-row)", color: "var(--act-ink)", marginTop: 3 }}>
        {children}
      </div>
    </div>
  );
}

/**
 * The take is the one graphite object on the page, which is honest — it is a
 * recording of a screen, not a document.
 *
 * 240 × 150 is 16:10, the shape of the thing recorded, and the same poster
 * convention Library already uses at 220–300 × 132. It was a 760 × 190 band of
 * empty near-black labelling itself 1440 × 900 — a 1.6:1 recording drawn in a
 * 4:1 frame.
 */
function TakeStage() {
  return (
    <div
      style={{
        width: "var(--act-aside-width)",
        height: 150,
        // The air the aside's gap used to supply, kept only here: the poster
        // must not sit flush on RESULT's rule.
        marginBottom: 14,
        background: "var(--act-deep)",
        borderRadius: 8,
        display: "flex",
        alignItems: "flex-end",
        justifyContent: "space-between",
        padding: "10px 12px",
        color: "var(--act-on-deep-meta)",
        fontFamily: mono,
        fontSize: "var(--act-micro)",
        letterSpacing: "var(--act-track-label)",
      }}
    >
      <span>00:05</span>
      <span>1440 × 900</span>
    </div>
  );
}
