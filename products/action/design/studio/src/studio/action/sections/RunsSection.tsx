"use client";

import { useState } from "react";
import { Camera, Clock8, Eye, MousePointer2, Search } from "lucide-react";
import {
  DESTINATION_LABEL,
  OUTCOME_COLOR,
  OUTCOME_LABEL,
  SESSIONS,
  type RunKind,
  type Session,
} from "@/studio/action/fixtures";

/**
 * A ledger, not a card of stripes.
 *
 * Zebra banding inside a bordered box paints two tones of furniture behind
 * every row and still needs the box to say where the day ends. Hairlines
 * between rows do the same work with one mark, and match the way a plan is set
 * on Scenarios — the same table language for the steps you are about to run
 * and the runs you already made.
 *
 * There is no box left on this page at all: the strip's controls, the day
 * groups and the pagination line are three bands of one ledger, and they all
 * stop at `--act-ledger-width`. A row that stretches to any window width lets
 * the outcome badge drift until it stops belonging to its title. The single
 * exception is the rule under the strip, which runs the full pane on purpose —
 * see `ControlStrip`.
 */

const mono = "var(--act-mono)";

/** Every band of the ledger measures to the same edge, left-aligned inside the
 *  page's 28px gutter. Centring would make the left edge move with the window,
 *  and the eye reads titles down that edge. */
const ledger = { maxWidth: "var(--act-ledger-width)" } as const;

const KIND_ICON = { drive: MousePointer2, inspection: Eye, capture: Camera };
const FILTERS: { key: RunKind | "all"; label: string }[] = [
  { key: "all", label: "All" },
  { key: "drive", label: "Drive" },
  { key: "inspection", label: "Inspect" },
  { key: "capture", label: "Capture" },
];

/* The three right-hand columns, stated once, so the labels on the day line sit
   over the exact edge their values do. `opens` narrows in compact because it is
   the column that can afford to: its words are short and it is the last one
   in. */
const COL_OUTCOME = 74;
const COL_TIME = 56;
const colOpens = (compact: boolean) => (compact ? 54 : 66);

export function RunsSection({ compact }: { compact: boolean }) {
  const [filter, setFilter] = useState<RunKind | "all">("all");
  const [selected, setSelected] = useState<string | null>(SESSIONS[0].id);

  const rows = SESSIONS.filter((s) => filter === "all" || s.kind === filter);
  const days = ["Today", "Yesterday"].map((d) => ({
    day: d,
    runs: rows.filter((r) => r.day === d),
  })).filter((g) => g.runs.length > 0);

  return (
    <div style={{ display: "flex", flexDirection: "column", minHeight: 0, flex: 1 }}>
      <ControlStrip filter={filter} onFilter={setFilter} counts={SESSIONS} compact={compact} />

      {/* No top inset: the day line carries the column names now, and it has to
          start against the strip's rule the way Settings' and Scenarios' column
          heads run straight into their rows. */}
      <div style={{ flex: 1, minHeight: 0, overflow: "auto", padding: "0 28px 24px" }}>
        {days.map((g) => (
          <div key={g.day} style={{ ...ledger, paddingBottom: 20 }}>
            <DayHeader day={g.day} count={g.runs.length} compact={compact} />
            {g.runs.map((s, i) => (
              <div key={s.id}>
                {i > 0 && <div style={{ height: 1, background: "var(--act-rule-soft)" }} />}
                <RunRow
                  session={s}
                  selected={selected === s.id}
                  onSelect={() => setSelected(s.id)}
                  compact={compact}
                />
              </div>
            ))}
          </div>
        ))}

        <ShowMore />
      </div>
    </div>
  );
}

/* -------------------------------------------------------- control strip -- */

/**
 * Chips, outcome picker and search in one band. The strip used to sit in its
 * own radius-13 enclosure, which put a second box inside a page whose ledger
 * had already dropped its own — nested furniture. What groups the controls now
 * is the hairline they sit on.
 *
 * That hairline runs the full pane while the controls stop at the ledger's
 * measure, which is the same mark Settings makes: a rule that spans the pane
 * over a column that does not is what says the page is narrow by choice rather
 * than by accident. Stopping the rule at 900 too left the boundary between the
 * pane-wide heading and the 900 ledger unexplained.
 *
 * The chips are Settings' pane tabs, because they are Settings' control — pick
 * one of N views of this page. A fill and a radius on the selected one made
 * "All 9" the only filled furniture on a page otherwise reduced to hairlines.
 * The outcome picker and the search field keep their 24pt rows.
 */
function ControlStrip({
  filter,
  onFilter,
  counts,
  compact,
}: {
  filter: RunKind | "all";
  onFilter: (f: RunKind | "all") => void;
  counts: Session[];
  compact: boolean;
}) {
  const n = (k: RunKind | "all") =>
    k === "all" ? counts.length : counts.filter((s) => s.kind === k).length;

  return (
    <>
      <div style={{ padding: "0 28px" }}>
        <div
          style={{
            ...ledger,
            display: "flex",
            alignItems: "center",
            gap: 8,
            // No horizontal inset. The 7pt was the gap between the controls and
            // the enclosure that used to hold them; with the enclosure gone it
            // left the first chip sitting 7pt inside a hairline that the day
            // headers and the rows below start flush against — a ragged left
            // edge at the top of the ledger. No bottom inset either: the chip
            // underline has to land on the strip's rule the way Settings' tabs
            // land on theirs, and 7pt of air between them would read as a
            // double rule. Only the top padding is real breathing room.
            padding: "7px 0 0",
          }}
        >
          <div style={{ display: "flex", gap: 3, flex: "0 0 auto" }}>
            {FILTERS.map((f) => {
              const Icon = f.key === "all" ? Clock8 : KIND_ICON[f.key as RunKind];
              const on = filter === f.key;
              return (
                <button
                  key={f.key}
                  type="button"
                  onClick={() => onFilter(f.key)}
                  style={{
                    display: "inline-flex",
                    alignItems: "center",
                    gap: 6,
                    // Settings' tab exactly: 30 tall, and the 2pt is reserved
                    // in every chip and painted only on the selected one, so
                    // moving the selection never re-lays the row.
                    height: 30,
                    padding: "0 9px",
                    border: 0,
                    borderBottom: `2px solid ${on ? "var(--act-ink)" : "transparent"}`,
                    cursor: "pointer",
                    background: "transparent",
                    color: on ? "var(--act-ink)" : "var(--act-ink-2)",
                    fontSize: "var(--act-caption)",
                    fontWeight: on ? 600 : 500,
                  }}
                >
                  <Icon size={11} />
                  {f.label}
                  <span
                    style={{
                      fontFamily: mono,
                      fontSize: "var(--act-micro)",
                      color: "var(--act-ink-muted)",
                      fontVariantNumeric: "tabular-nums",
                    }}
                  >
                    {n(f.key)}
                  </span>
                </button>
              );
            })}
          </div>

          <span style={{ width: 1, height: 18, background: "var(--act-rule)", margin: "0 3px" }} />

          <span
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 6,
              height: 24,
              padding: "0 9px",
              borderRadius: 6,
              fontSize: "var(--act-caption)",
              color: "var(--act-ink-2)",
            }}
          >
            Any outcome <span style={{ color: "var(--act-ink-muted)" }}>▾</span>
          </span>

          <span style={{ flex: 1, minWidth: 12 }} />

          {/* Flexible rather than pinned: the window resizes, and a fixed field
              is the first thing to push the strip off its own edge. */}
          <span
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 6,
              height: 24,
              padding: "0 9px",
              borderRadius: 6,
              background: "var(--act-panel-raised)",
              border: "1px solid var(--act-rule)",
              width: compact ? 150 : 240,
              transition: "width 160ms ease",
              color: "var(--act-ink-muted)",
              fontSize: "var(--act-caption)",
            }}
          >
            <Search size={11} />
            Search runs
          </span>
        </div>
      </div>

      {/* The one mark that used to be a four-sided box, now run to the pane's
          own edges so the ledger's 900 reads as a chosen measure. */}
      <div style={{ height: 1, background: "var(--act-rule)" }} />
    </>
  );
}

/**
 * The day line and the column names are one band: `TODAY 5 ——— OUTCOME TIME
 * OPENS`. Standing the labels off on their own put an entire day header and a
 * rule between a column name and its first value, and left them sitting nearer
 * the filter strip than anything they named — so they read as a caption on the
 * strip. Folded in here they are permanently over their own columns and, being
 * part of the sticky line, stay there while the ledger scrolls. The cost is
 * that the names repeat once per day group; that is cheaper than a header that
 * labels the wrong thing.
 *
 * The label widths and the 20 gap are the row's, and the 10 right inset is the
 * row's too — the day line spans the full ledger while a row's cells sit inside
 * a 3pt rail, so matching the right edge is what makes the columns line up.
 */
function DayHeader({ day, count, compact }: { day: string; count: number; compact: boolean }) {
  const cell = {
    flex: "0 0 auto",
    fontFamily: mono,
    fontSize: "var(--act-label)",
    fontWeight: 600,
    letterSpacing: "var(--act-track-label)",
    color: "var(--act-ink-muted)",
  } as const;

  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 8,
        padding: "6px 0 7px",
        position: "sticky",
        top: 0,
        background: "var(--act-canvas)",
      }}
    >
      <span
        style={{
          fontSize: "var(--act-micro)",
          fontWeight: 600,
          letterSpacing: "0.7px",
          color: "var(--act-ink-2)",
        }}
      >
        {day.toUpperCase()}
      </span>
      <span
        style={{
          fontFamily: mono,
          fontSize: "var(--act-micro)",
          color: "var(--act-ink-muted)",
        }}
      >
        {count}
      </span>
      <span style={{ flex: 1, height: 1, background: "var(--act-rule)" }} />

      <div style={{ display: "flex", alignItems: "center", gap: 20, paddingRight: 10 }}>
        <span style={{ ...cell, width: COL_OUTCOME }}>OUTCOME</span>
        <span style={{ ...cell, width: COL_TIME, textAlign: "right" }}>TIME</span>
        <span style={{ ...cell, width: colOpens(compact), textAlign: "right" }}>OPENS</span>
      </div>
    </div>
  );
}

/**
 * Says what is still off-screen rather than just "more". A ledger that stops
 * without saying how much it is holding back reads as the end.
 *
 * Drawn as the ledger's last line, not as a bordered slab: opening a run is the
 * primary action on this page, and pagination framed in the darkest edge on the
 * page outranked every row above it.
 */
function ShowMore() {
  const [hover, setHover] = useState(false);

  return (
    <div style={ledger}>
      <div style={{ height: 1, background: "var(--act-rule-soft)" }} />
      <button
        type="button"
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
        style={{
          display: "flex",
          alignItems: "center",
          gap: 10,
          width: "100%",
          height: 30,
          // 3 for the rail a row spends, then a row's own 9: the label starts
          // on the same edge as a run's kind icon.
          padding: "0 10px 0 12px",
          border: 0,
          background: hover ? "var(--act-row-hover)" : "transparent",
          cursor: "pointer",
          textAlign: "left",
        }}
      >
        <span style={{ fontSize: "var(--act-caption)", fontWeight: 600, color: "var(--act-ink-2)" }}>
          Show 80 more
        </span>
        <span
          style={{
            fontFamily: mono,
            fontSize: "var(--act-caption)",
            color: "var(--act-ink-muted)",
          }}
        >
          212 older
        </span>
      </button>
    </div>
  );
}

/**
 * Three clusters, deliberately unequal gaps: what it is and who ran it
 * (tight), how it ended (medium), when and where it opens (tight, pinned
 * right). The widest joint is the elastic one after the agent, so the eye
 * reads titles down the page and only then crosses to the rail.
 *
 * A selected row says so twice — the blue rail and the semibold title — and the
 * wash says nothing, because it is not the selection's. `--act-row-open` and
 * `--act-row-hover` are the same 3.5% ink, so a selected row painted with it
 * was indistinguishable from any row the pointer happened to be over. The wash
 * now has one meaning: the pointer is here. The kind icon never takes the
 * accent either — blue on this page means selection, and the rail owns it.
 */
function RunRow({
  session,
  selected,
  onSelect,
  compact,
}: {
  session: Session;
  selected: boolean;
  onSelect: () => void;
  compact: boolean;
}) {
  const Icon = KIND_ICON[session.kind];
  const [hover, setHover] = useState(false);

  return (
    <div
      onClick={onSelect}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        display: "flex",
        alignItems: "center",
        height: 30,
        cursor: "pointer",
        background: hover ? "var(--act-row-hover)" : "transparent",
      }}
    >
      <span
        style={{
          width: 3,
          alignSelf: "stretch",
          background: selected ? "var(--act-review-accent)" : "transparent",
        }}
      />
      <div
        style={{
          flex: 1,
          minWidth: 0,
          display: "flex",
          alignItems: "center",
          gap: 20,
          padding: "0 10px 0 9px",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 8, flex: 1, minWidth: 0 }}>
          <Icon size={12} style={{ color: "var(--act-ink-muted)", flex: "0 0 auto" }} />
          <span
            style={{
              fontSize: "var(--act-row)",
              fontWeight: selected ? 600 : 500,
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {session.title}
          </span>
          {/* Who drove it, next to what it did. Apart, the two read as
              unrelated columns; together they say whether a run has real
              provenance or is an unidentified stray. */}
          <span
            style={{
              fontSize: "var(--act-caption)",
              color: "var(--act-ink-muted)",
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
              maxWidth: 190,
            }}
          >
            {session.agent}
          </span>
        </div>

        <span
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: 6,
            width: COL_OUTCOME,
            flex: "0 0 auto",
            fontSize: "var(--act-caption)",
            color: "var(--act-ink-2)",
          }}
        >
          {/* Status colour is spent only when the status is news. A completed
              run is the expected case, so it gets the reserved 6pt and no
              paint — which leaves exactly one coloured mark on the page, and it
              is the failure you came here to find. The column going ragged is
              the signal, not a defect. */}
          {session.outcome === "ok" ? (
            <span style={{ width: 6, flex: "0 0 auto" }} />
          ) : (
            <span
              style={{
                width: 6,
                height: 6,
                flex: "0 0 auto",
                borderRadius: "50%",
                background: OUTCOME_COLOR[session.outcome],
              }}
            />
          )}
          {OUTCOME_LABEL[session.outcome]}
        </span>

        <span
          style={{
            width: COL_TIME,
            textAlign: "right",
            flex: "0 0 auto",
            fontFamily: mono,
            fontSize: "var(--act-caption)",
            color: "var(--act-ink-muted)",
            fontVariantNumeric: "tabular-nums",
          }}
        >
          {session.clock}
        </span>

        {/* Where this row's click lands, stated at rest. Reading down this
            column is how you find the drives that left something to look at. */}
        <span
          style={{
            width: colOpens(compact),
            textAlign: "right",
            flex: "0 0 auto",
            fontFamily: mono,
            fontSize: "var(--act-caption)",
            color:
              session.destination === "none" ? "var(--act-ink-muted)" : "var(--act-ink-2)",
          }}
        >
          {DESTINATION_LABEL[session.destination]}
        </span>
      </div>
    </div>
  );
}
