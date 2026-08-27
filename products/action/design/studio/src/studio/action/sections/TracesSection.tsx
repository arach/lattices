"use client";

import { useState } from "react";
import {
  Camera,
  Clock8,
  Eye,
  LayoutGrid,
  List,
  MousePointer2,
  Search,
} from "lucide-react";
import {
  DESTINATION_LABEL,
  OUTCOME_COLOR,
  OUTCOME_LABEL,
  SESSIONS,
  type RunKind,
  type Session,
} from "@/studio/action/fixtures";
import { WindowPageHeader } from "@/studio/action/Window";

/**
 * Traces: one object, two views, one filter strip.
 *
 * Runs and Library were never two sections. `LibrarySection` was
 * `SESSIONS.filter(s => s.destination === "take" || s.destination === "finder")` —
 * the same rows the ledger draws, minus the ones that left nothing, shown in a
 * second visual language under a second nav slot. Two prior rounds spent their
 * budget making the two languages agree, which is the expensive way of not
 * asking why there were two. A session has a kind, an outcome, an agent, a
 * time, and sometimes an artifact. "Sometimes an artifact" is a property of a
 * run, not a reason to found a section.
 *
 * So: one section, one filtered set, and a toggle that changes how that set is
 * drawn. The filter strip is the whole payoff. Library never had filters and
 * Runs never had posters; after the merge, `Drive · Failed` narrows the posters
 * exactly as it narrows the ledger, and the gallery inherits the day grouping
 * it never had. Neither half could do either thing.
 *
 * Four calls this file makes, with reasons:
 *
 * 1. ONE MEASURE, AND IT IS THE LEDGER'S 900. The gallery used to run to a
 *    1242 stop. But the strip, the day headers and the pagination line are now
 *    shared furniture standing above both views, and furniture that changes
 *    width when you press a toggle is two pages wearing one name — the day
 *    rule would visibly grow 340pt on a keystroke. `--act-ledger-width` wins
 *    because it is the one of the two that is an argument rather than a stop:
 *    it exists so a row's outcome badge stays attached to its title. At 900 the
 *    grid resolves to 3 × 291, which is inside the Swift's
 *    `adaptive(minimum: 220, maximum: 300)` — the gallery keeps its native
 *    shape. The real cost is honest and worth stating: Library was the only
 *    page in the window that gained a column on a wide desk, and it no longer
 *    does. On a 32in half-screen the gallery gains margin, like Scenarios does.
 *    A measured gallery is the thinner answer, and thinner is the house rule.
 *
 * 2. OPENS STAYS IN THE LEDGER; THE GALLERY NEVER PRINTS IT. Both answer "did
 *    this leave anything I can look at", and the honest resolution is that they
 *    answer it in the only way each can afford: the gallery *draws* the
 *    artifact at 132pt, the ledger *names* it in a column you can read straight
 *    down. Deleting either would make one view strictly worse than the section
 *    it replaced — the redundancy is not waste, it is the reason there are two
 *    views at all. What the merge does change is the caption: it drops the
 *    `day` line, which the new day header now owns, and spends the recovered
 *    room on outcome and agent. Library showed a failed drive and a completed
 *    one identically. That was the gallery's real defect, and it was never
 *    about posters.
 *
 * 3. PAGINATION IS THE DATA'S LINE, NOT THE VIEW'S. "Show 80 more · 212 older"
 *    is a statement about what the store is holding back, and it holds back the
 *    same 212 whichever way you are looking. It stays, unchanged, at the same
 *    measure below the last group in both views — literally the same element in
 *    the same place, which is also what proves the toggle changed the drawing
 *    and not the query.
 *
 * 4. THE SUBTITLE STAYS EMPTY, AND SO DOES THE COUNTER. The only count worth
 *    putting there is the number of runs, and the strip says `All 9` forty
 *    points below it — two answers to one question in a single eyeful. A
 *    subtitle also costs 22pt of header, which would push the strip and the
 *    first day line down; the header now has to hold still across a view
 *    toggle, so it holds still. Two lines, always.
 *
 * The header lives inside this file rather than in the shell because the
 * control in its `right` slot is bound to this page's view state. Threading
 * that state up into the window would make the shell own a fact only this page
 * has.
 */

const mono = "var(--act-mono)";

/** Every band — strip, day lines, rows, grid, pagination — stops at the same
 *  edge, left-aligned inside the page's 28px gutter. See call 1 above. */
const measure = { maxWidth: "var(--act-ledger-width)" } as const;

type View = "list" | "gallery";

const KIND_ICON = { drive: MousePointer2, inspection: Eye, capture: Camera };
/* The well's placeholder prints the label a person reads everywhere else in the
   app — `kind.title`, not the Swift's lowercase `kind.rawValue`. */
const KIND_LABEL: Record<RunKind, string> = {
  drive: "Drive",
  inspection: "Inspect",
  capture: "Capture",
};

const FILTERS: { key: RunKind | "all"; label: string }[] = [
  { key: "all", label: "All" },
  { key: "drive", label: "Drive" },
  { key: "inspection", label: "Inspect" },
  { key: "capture", label: "Capture" },
];

/* The ledger's three right-hand columns, stated once so the labels on the day
   line sit over the exact edge their values do. `opens` narrows in compact
   because its words are short and it is the last column in. */
const COL_OUTCOME = 74;
const COL_TIME = 56;
const colOpens = (compact: boolean) => (compact ? 54 : 66);

export function TracesSection({ compact }: { compact: boolean }) {
  const [view, setView] = useState<View>("list");
  const [filter, setFilter] = useState<RunKind | "all">("all");
  // One selection, both views. Picking a run in the ledger and pressing the
  // gallery toggle has to land on the same run still lit, or the toggle is
  // navigating rather than re-drawing.
  const [selected, setSelected] = useState<string | null>(SESSIONS[0].id);

  const rows = SESSIONS.filter((s) => filter === "all" || s.kind === filter);
  const days = ["Today", "Yesterday"]
    .map((d) => ({ day: d, runs: rows.filter((r) => r.day === d) }))
    .filter((g) => g.runs.length > 0);

  return (
    <div style={{ display: "flex", flexDirection: "column", minHeight: 0, flex: 1 }}>
      {/* The window's standard header inset. Nothing in here changes between
          views, so the strip below it never moves when the toggle is pressed.
          The header takes the measure too, which the other pages' headers do
          not: on Library the toggle sat at the pane edge, 110pt right of every
          band beneath it, and read as having come loose. Held to 900 it lands
          on the same right edge as OPENS and as the day line's rule, so the
          page is one column from the eyebrow down. */}
      <div style={{ padding: "20px 28px 16px" }}>
        <div style={measure}>
          <WindowPageHeader
            eyebrow="WHAT AGENTS DID"
            title="Traces"
            right={<ViewToggle view={view} onView={setView} />}
          />
        </div>
      </div>

      <ControlStrip filter={filter} onFilter={setFilter} counts={SESSIONS} compact={compact} />

      {/* No top inset: in list view the day line carries the column names and
          has to start against the strip's rule, the way Settings' and
          Scenarios' column heads run straight into their rows. Gallery keeps
          the same start so the first day line does not move on toggle. */}
      <div style={{ flex: 1, minHeight: 0, overflow: "auto", padding: "0 28px 24px" }}>
        {days.map((g) => (
          <div key={g.day} style={{ ...measure, paddingBottom: view === "list" ? 20 : 26 }}>
            <DayHeader day={g.day} count={g.runs.length} columns={view === "list"} compact={compact} />

            {view === "list" ? (
              g.runs.map((s, i) => (
                <div key={s.id}>
                  {i > 0 && <div style={{ height: 1, background: "var(--act-rule-soft)" }} />}
                  <RunRow
                    session={s}
                    selected={selected === s.id}
                    onSelect={() => setSelected(s.id)}
                    compact={compact}
                  />
                </div>
              ))
            ) : (
              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))",
                  gap: 14,
                  alignItems: "start",
                  paddingTop: 6,
                }}
              >
                {g.runs.map((s) => (
                  <PosterCell
                    key={s.id}
                    session={s}
                    selected={selected === s.id}
                    onSelect={() => setSelected(s.id)}
                  />
                ))}
              </div>
            )}
          </div>
        ))}

        <ShowMore />
      </div>
    </div>
  );
}

/* --------------------------------------------------------- view toggle -- */

/**
 * The one control that is about looking rather than about the data, which is
 * why it is the only thing in the header's right slot and why the search field
 * is not up here: search belongs beside the filters it works with, and the
 * strip already had one. Two search boxes was the clearest single symptom that
 * these were one section drawn twice.
 *
 * List leads because Traces opens as a ledger — "what happened" is the
 * section's question and the gallery answers the narrower "what can I watch".
 * Geometry is the segmented control Library already used: 2pt of padding
 * inside a radius-8 hairline, so the 6pt inner radius stays concentric with
 * it, and 30 × 24 segments that reserve their ground whether lit or not.
 */
function ViewToggle({ view, onView }: { view: View; onView: (v: View) => void }) {
  const seg = (v: View, Icon: typeof List) => {
    const on = view === v;
    return (
      <button
        type="button"
        onClick={() => onView(v)}
        title={v === "list" ? "List" : "Gallery"}
        style={{
          display: "grid",
          placeItems: "center",
          width: 30,
          height: 24,
          padding: 0,
          border: 0,
          borderRadius: 6,
          cursor: "pointer",
          background: on ? "var(--act-panel-raised)" : "transparent",
          color: on ? "var(--act-ink)" : "var(--act-ink-muted)",
        }}
      >
        <Icon size={12} />
      </button>
    );
  };

  return (
    <span
      style={{
        display: "inline-flex",
        padding: 2,
        borderRadius: 8,
        border: "1px solid var(--act-rule)",
        background: "var(--act-card)",
      }}
    >
      {seg("list", List)}
      {seg("gallery", LayoutGrid)}
    </span>
  );
}

/* -------------------------------------------------------- control strip -- */

/**
 * Chips, outcome picker and search in one band, above whichever view is
 * showing. This is the merge's actual argument: the filters were built for the
 * ledger, the gallery never had any, and there was never a reason for that
 * beyond the two pages having been drawn by different hands.
 *
 * The hairline runs the full pane while the controls stop at the measure —
 * the same mark Settings makes: a rule that spans the pane over a column that
 * does not is what says the page is narrow by choice rather than by accident.
 *
 * The chips are Settings' pane tabs, because they are Settings' control: pick
 * one of N views of this page. A fill and a radius on the selected one would
 * make "All 9" the only filled furniture on a page otherwise reduced to
 * hairlines.
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
            ...measure,
            display: "flex",
            alignItems: "center",
            gap: 8,
            // No horizontal inset: the first chip starts on the same hard left
            // edge the day headers and the rows below start on. No bottom
            // inset either, because the chip underline has to land on the
            // strip's rule the way Settings' tabs land on theirs, and air
            // between them would read as a double rule.
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
                    // Settings' tab exactly: 30 tall, and the 2pt underline is
                    // reserved in every chip and painted only on the selected
                    // one, so moving the selection never re-lays the row.
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

          {/* The section's only search box, and it says "traces" rather than
              "runs" or "takes" because it now reaches both. Flexible rather
              than pinned: the window resizes, and a fixed field is the first
              thing to push the strip off its own edge. */}
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
            Search traces
          </span>
        </div>
      </div>

      <div style={{ height: 1, background: "var(--act-rule)" }} />
    </>
  );
}

/* ---------------------------------------------------------- day header -- */

/**
 * `TODAY 5 ——— OUTCOME TIME OPENS` in list view; `TODAY 5 ———` in gallery.
 * The column names are folded into the day line so they sit permanently over
 * their own columns and stay there while the ledger scrolls; the cost is that
 * they repeat once per group, which is cheaper than a header that labels the
 * wrong thing. In gallery there are no columns, so there are no names, and the
 * rule simply runs to the measure.
 *
 * Giving the gallery this line at all is the second thing the merge buys.
 * Library had no time structure whatsoever — a take from four minutes ago and
 * one from yesterday sat in the same undifferentiated shelf — while the ledger
 * beside it grouped by day. The day line is also what keeps the two views the
 * same shape: press the toggle and the headings stay put while only the bodies
 * between them change.
 *
 * The z-index is not needed in list view, where the rows are transparent, but
 * a graphite poster scrolling over a sticky line with a canvas ground would
 * win without it.
 */
function DayHeader({
  day,
  count,
  columns,
  compact,
}: {
  day: string;
  count: number;
  columns: boolean;
  compact: boolean;
}) {
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
        zIndex: 1,
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
      <span style={{ fontFamily: mono, fontSize: "var(--act-micro)", color: "var(--act-ink-muted)" }}>
        {count}
      </span>
      <span style={{ flex: 1, height: 1, background: "var(--act-rule)" }} />

      {columns && (
        /* The 20 gap and the 10 right inset are the row's: the day line spans
           the full measure while a row's cells sit inside a 3pt rail, so
           matching the right edge is what makes the columns line up. */
        <div style={{ display: "flex", alignItems: "center", gap: 20, paddingRight: 10 }}>
          <span style={{ ...cell, width: COL_OUTCOME }}>OUTCOME</span>
          <span style={{ ...cell, width: COL_TIME, textAlign: "right" }}>TIME</span>
          <span style={{ ...cell, width: colOpens(compact), textAlign: "right" }}>OPENS</span>
        </div>
      )}
    </div>
  );
}

/* ---------------------------------------------------------- pagination -- */

/**
 * Says what is still off-screen rather than just "more": a list that stops
 * without saying how much it is holding back reads as the end. Drawn as the
 * last line of the measure rather than as a bordered slab, because opening a
 * run is the primary action on this page and pagination framed in the darkest
 * edge on the page would outrank every row above it.
 *
 * Unchanged between views on purpose — see call 3 in the file header.
 */
function ShowMore() {
  const [hover, setHover] = useState(false);

  return (
    <div style={measure}>
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
        <span style={{ fontFamily: mono, fontSize: "var(--act-caption)", color: "var(--act-ink-muted)" }}>
          212 older
        </span>
      </button>
    </div>
  );
}

/* ------------------------------------------------------------- list row -- */

/**
 * Three clusters, deliberately unequal gaps: what it is and who ran it
 * (tight), how it ended (medium), when and where it opens (tight, pinned
 * right). The widest joint is the elastic one after the agent, so the eye
 * reads titles down the page and only then crosses to the rail.
 *
 * A selected row says so twice — the blue rail and the semibold title — and
 * the wash says nothing, because `--act-row-open` and `--act-row-hover` are
 * the same 3.5% ink and a selected row painted with it is indistinguishable
 * from any row the pointer happens to be over. The wash has one meaning: the
 * pointer is here.
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
          <OutcomeDot session={session} />
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
            column is the thing the gallery cannot do, which is why it survives
            the merge even though the poster answers the same question. */}
        <span
          style={{
            width: colOpens(compact),
            textAlign: "right",
            flex: "0 0 auto",
            fontFamily: mono,
            fontSize: "var(--act-caption)",
            color: session.destination === "none" ? "var(--act-ink-muted)" : "var(--act-ink-2)",
          }}
        >
          {DESTINATION_LABEL[session.destination]}
        </span>
      </div>
    </div>
  );
}

/**
 * Status colour is spent only when the status is news. A completed run is the
 * expected case, so it gets the reserved 6pt and no paint — which leaves the
 * failure you came here to find as one of the only coloured marks on the page.
 * The column going ragged is the signal, not a defect. Shared by both views so
 * the rule cannot drift apart again.
 */
function OutcomeDot({ session }: { session: Session }) {
  if (session.outcome === "ok") return <span style={{ width: 6, flex: "0 0 auto" }} />;
  return (
    <span
      style={{
        width: 6,
        height: 6,
        flex: "0 0 auto",
        borderRadius: "50%",
        background: OUTCOME_COLOR[session.outcome],
      }}
    />
  );
}

/* --------------------------------------------------------- poster cell -- */

/**
 * A run as a poster. Every run gets one, including the drive that left
 * nothing: filtering the gallery down to rows with artifacts is what made
 * Library a second section in the first place, and a drive that ended empty
 * still happened. The artifact-less rows get the kind glyph the capture wells
 * already used, which now has a real job — it is the mark that says this run
 * left no still.
 *
 * There is no drawn image inside a take's well either. The runtime writes no
 * poster frame, so a light rectangle there is a picture of nothing; at full
 * size it reads as a recording that came out blank, which is a worse lie than
 * an empty well.
 *
 * The caption is where the merge shows: `day` is gone, because the day header
 * above the grid now says it, and outcome and agent take its place. Library
 * drew a failed drive and a completed one identically — the gallery's real
 * defect was never that it lacked posters, it was that it lacked the run.
 * TIME and OPENS stay behind in the ledger: the grid is day-grouped and
 * ordered, and the exact minute and the destination word are what you switch
 * views to get.
 */
function PosterCell({
  session,
  selected,
  onSelect,
}: {
  session: Session;
  selected: boolean;
  onSelect: () => void;
}) {
  const Icon = KIND_ICON[session.kind];
  const hasPoster = session.destination === "take";
  const [hover, setHover] = useState(false);

  return (
    <div
      onClick={onSelect}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{ cursor: "pointer" }}
    >
      <div
        style={{
          height: 132,
          borderRadius: 8,
          background: "var(--act-deep)",
          display: "flex",
          flexDirection: "column",
          padding: "10px 12px",
          gap: 6,
        }}
      >
        <div
          style={{
            flex: 1,
            minHeight: 0,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          {hasPoster ? null : (
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: 6,
                color: "var(--act-on-deep-meta)",
              }}
            >
              <Icon size={16} />
              <span style={{ fontSize: "var(--act-micro)", fontWeight: 600 }}>
                {KIND_LABEL[session.kind]}
              </span>
            </div>
          )}
        </div>

        {/* Facts that belong to the artifact rather than to the run stay inside
            the well: how long it is, and how many notes are pinned to it. */}
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            fontFamily: mono,
            fontSize: "var(--act-micro)",
            letterSpacing: "0.05em",
            color: "var(--act-on-deep-meta)",
          }}
        >
          <span>{session.duration}</span>
          {session.notes ? <span>{session.notes} ▮</span> : null}
        </div>
      </div>

      {/* The list row's 3pt selection rail, turned ninety degrees. The height
          is reserved in every cell and painted only on the selected one, so
          selecting never re-lays the grid — the same reservation the filter
          chips make for their underline. Hover is the ink wash the rows use,
          spent here as a hairline under the well rather than a tint behind the
          caption, because a wash on paper beside a graphite well disappears. */}
      <div
        style={{
          height: 2,
          marginTop: 6,
          background: selected
            ? "var(--act-review-accent)"
            : hover
              ? "var(--act-rule)"
              : "transparent",
        }}
      />

      {/* Flush with the well's left edge: with the card gone there is no box to
          inset the caption from. */}
      <div style={{ padding: "6px 0 0" }}>
        <div
          style={{
            fontSize: "var(--act-row)",
            fontWeight: 600,
            whiteSpace: "nowrap",
            overflow: "hidden",
            textOverflow: "ellipsis",
          }}
        >
          {session.title}
        </div>
        <div
          style={{
            marginTop: 4,
            display: "flex",
            alignItems: "center",
            gap: 6,
            fontSize: "var(--act-caption)",
            color: "var(--act-ink-2)",
            whiteSpace: "nowrap",
            overflow: "hidden",
          }}
        >
          <OutcomeDot session={session} />
          <span style={{ flex: "0 0 auto" }}>{OUTCOME_LABEL[session.outcome]}</span>
          {/* Only a real result earns a token. Printing a fallback here would
              repeat the word the well already says 10px above, in a
              proportional face where the column runs mono. */}
          {session.result && (
            <>
              <span style={{ color: "var(--act-ink-muted)" }}>·</span>
              <span style={{ fontFamily: mono, flex: "0 0 auto" }}>{session.result}</span>
            </>
          )}
          <span style={{ color: "var(--act-ink-muted)" }}>·</span>
          <span
            style={{
              color: "var(--act-ink-muted)",
              minWidth: 0,
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {session.agent}
          </span>
        </div>
      </div>
    </div>
  );
}
