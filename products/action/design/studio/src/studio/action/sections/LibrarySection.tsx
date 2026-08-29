"use client";

import { Camera, Eye, MousePointer2 } from "lucide-react";
import { SESSIONS, type RunKind } from "@/studio/action/fixtures";

/**
 * Takes, as a gallery. The grid is `adaptive(minimum: 220, maximum: 300)` in
 * the Swift, which is why this is the one page whose column count actually
 * changes with the window — everything else reflows within fixed columns. The
 * tracks stretch toward the maximum before a column is added, so `1fr` with a
 * 220 minimum is the honest transcription; `minmax(220, 300)` pinned every
 * track at the minimum and left a third of a wide window as dead gutter.
 *
 * There is no card, and there is no drawn poster inside the well either. The
 * runtime writes no still, so a light rectangle in the well is a picture of
 * nothing — at full size it reads as a recording that came out blank, which is
 * a worse lie than an empty well. A take is the bare graphite well plus its
 * mono duration and notes, which is the same object `ScenariosSection`'s
 * `TakeStage` already draws. One take, one drawing.
 *
 * The caption sits on the ground under the well: Finder and Photos do the same,
 * and a filled bordered card around an already-framed object would just be a
 * second rectangle.
 */

const mono = "var(--act-mono)";

const KIND_ICON = { drive: MousePointer2, inspection: Eye, capture: Camera };
/* What the placeholder says when there is no still. The Swift prints
   `kind.rawValue` here, which is the lowercase case name; the label a person
   reads everywhere else in the app is `kind.title`, so the study draws that. */
const KIND_LABEL: Record<RunKind, string> = {
  drive: "Drive",
  inspection: "Inspect",
  capture: "Capture",
};

/* The gallery's measure, and the reason it is a stop rather than a track count:
   `auto-fill` adds a column the moment one more 220 fits, so what this actually
   produces is 3 × 271 at Minimum, 4 × 300 at Default and 5 × 237 at Wide —
   exactly the shape `adaptive(minimum: 220, maximum: 300)` gives in the Swift.
   Without a stop, a gallery that ran to the edge of any window would keep the
   caption for the last take a screen-width away from the first. */
const GRID_MAX = 1242;

export function LibrarySection() {
  const takes = SESSIONS.filter((s) => s.destination === "take" || s.destination === "finder");

  return (
    <div
      style={{
        display: "grid",
        gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))",
        gap: 14,
        maxWidth: GRID_MAX,
        alignItems: "start",
      }}
    >
      {takes.map((s) => {
        const Icon = KIND_ICON[s.kind];
        const hasPoster = s.destination === "take";

        return (
          <div key={s.id}>
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
                  /* Only captures draw a glyph. With the take's inner plate
                     gone this label is the one thing that tells an empty take
                     well from a capture well, which is now its whole job. */
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
                      {KIND_LABEL[s.kind]}
                    </span>
                  </div>
                )}
              </div>

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
                <span>{s.duration}</span>
                {s.notes ? <span>{s.notes} ▮</span> : null}
              </div>
            </div>

            {/* Flush with the thumbnail's left edge: with the card gone there is
                no box to inset the caption from. */}
            <div style={{ padding: "10px 0 0" }}>
              <div
                style={{
                  fontSize: "var(--act-row)",
                  fontWeight: 600,
                  whiteSpace: "nowrap",
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                }}
              >
                {s.title}
              </div>
              <div
                style={{
                  marginTop: 4,
                  display: "flex",
                  gap: 6,
                  fontSize: "var(--act-caption)",
                  color: "var(--act-ink-2)",
                }}
              >
                {/* Only a real result earns a token here. Printing "Capture"
                    as the fallback repeated the word the well already says 10px
                    above, and put a proportional face where every other row in
                    the column runs mono — the typeface changed by row for no
                    reason a reader could see. The separator goes with it. */}
                {s.result ? (
                  <>
                    <span style={{ fontFamily: mono }}>{s.result}</span>
                    <span style={{ color: "var(--act-ink-muted)" }}>·</span>
                  </>
                ) : null}
                <span style={{ color: "var(--act-ink-muted)" }}>{s.day.toLowerCase()}</span>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
