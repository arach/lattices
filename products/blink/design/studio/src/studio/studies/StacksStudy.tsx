"use client";

import { useState } from "react";
import { TrafficLights, glass } from "./DesktopScene";

/**
 * Study: stacks in the see-all view — where idle notes go to be left alone.
 *
 * The triad has no Library, but older notes need a home that isn't a hidden
 * archive list. The stack is the desk-corner pile made digital: parked notes
 * stay visible, countable, and leaf-through-able. Four metaphors for what
 * that pile could be, each rendered in the same see-all context:
 *
 *  01 card pile       — rotated offset pile + count badge; hover fans it out
 *  02 stacked sheets  — inbox-tray edges, titles peeking; hover expands
 *  03 shelf           — spined bundles on a ledge, grouped by age
 *  04 messy desk      — loose cluster, front note readable, the rest peeking
 */

type FakeNote = { title: string; snippet: string; age: string };

const ACTIVE_NOTES: FakeNote[] = [
  { title: "Meeting notes", snippet: "standup — panel drag shipped, dictation next", age: "2m" },
  { title: "Roadmap Q3", snippet: "PanelKit → HudsonKit · dictation polish · themes", age: "1h" },
  { title: "Grocery", snippet: "miso, scallions, tofu, sesame oil…", age: "3h" },
  { title: "Blink release checklist", snippet: "notarize → DMG → update feed → tag", age: "1d" },
  { title: "Ideas parking lot", snippet: "shade-to-bar on idle? gather-all command…", age: "2d" },
  { title: "Reading — spatial interfaces", snippet: "cards on the table; piles as metadata…", age: "4d" },
];

/** The parked tail — oldest first, most recently parked last. */
const STACK_NOTES: FakeNote[] = [
  { title: "2019 tax scans", snippet: "W-2, 1099, receipts — keep until 2027", age: "6y" },
  { title: "Moving checklist", snippet: "deposit returned ✓ · keys handed over ✓", age: "2y" },
  { title: "Conference talk draft", snippet: "notes as windows — the 20-min version", age: "14mo" },
  { title: "Recipe — miso ramen", snippet: "broth 20 min, tare first, egg 6:30", age: "9mo" },
  { title: "App icon sketches", snippet: "eye + lid variants; v3 exported", age: "7mo" },
  { title: "Gift ideas — mum", snippet: "ceramic class? the blue scarf?", age: "5mo" },
  { title: "Old standup notes", snippet: "weeks 34–41, kept for the retro", age: "3mo" },
];

export function StacksStudy() {
  return (
    <div className="space-y-14">
      <Variant
        index="01"
        name="Card pile"
        interaction="Hover fans the pile into a row you can leaf through; a card lifts on hover."
        tradeoff="Best feel and count-at-a-glance — but the fan-out needs width and order is implied, not shown."
        hint="hover the pile →"
        interactive
      >
        <CardPile />
      </Variant>

      <Variant
        index="02"
        name="Stacked sheets"
        interaction="Inbox-tray edges with titles peeking out; hover expands the tray accordion-style."
        tradeoff="Every title is one hover away and the rest state is tiny — but expanded it reads as a list, not a pile."
        hint="hover the tray →"
        interactive
      >
        <SheetTray />
      </Variant>

      <Variant
        index="03"
        name="Shelf"
        interaction="Stacks stand on a ledge at the bottom of the view, grouped by age; each is a spined bundle with a count."
        tradeoff="Tidiest and most scalable — but spines are abstract: no titles peek, you trust the grouping."
        hint="grouped by age"
      >
        <Shelf />
      </Variant>

      <Variant
        index="04"
        name="Messy desk"
        interaction="A loose cluster, as you left it — front note fully readable, the rest peeking at angles."
        tradeoff="Most personality, closest to the real desk-corner pile — but the organic layout costs scannability."
        hint="as you left it"
      >
        <MessyDesk />
      </Variant>
    </div>
  );
}

/* ——— variant frame ———————————————————————————————————————— */

function Variant({
  index,
  name,
  interaction,
  tradeoff,
  hint,
  interactive = false,
  children,
}: {
  index: string;
  name: string;
  interaction: string;
  tradeoff: string;
  hint: string;
  interactive?: boolean;
  children: React.ReactNode;
}) {
  return (
    <section>
      <header className="mb-3 flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
          {index}
        </span>
        <h3 className="text-[17px] font-medium text-studio-ink-strong">{name}</h3>
        {interactive && (
          <span className="rounded border border-studio-rule px-1.5 py-px font-mono text-[9px] uppercase tracking-[0.16em] text-studio-ink-faint">
            hover me
          </span>
        )}
        <span className="max-w-[62ch] text-[12.5px] leading-relaxed text-studio-ink-faint">
          {interaction}
        </span>
      </header>

      <SeeAllWindow hint={hint}>{children}</SeeAllWindow>

      <p className="mt-2.5 text-[12px] leading-relaxed text-studio-ink-faint">
        tradeoff — {tradeoff}
      </p>
    </section>
  );
}

/** The see-all context every variant lives in: active grid + a stacks zone. */
function SeeAllWindow({
  hint,
  children,
}: {
  hint: string;
  children: React.ReactNode;
}) {
  return (
    <div
      className="flex h-[470px] w-full select-none flex-col overflow-hidden rounded-xl border border-white/[0.1] shadow-[0_30px_80px_rgba(0,0,0,0.35)]"
      style={{ background: "linear-gradient(180deg, #151827 0%, #101321 100%)" }}
    >
      {/* title bar */}
      <div className="flex h-9 shrink-0 items-center gap-3 border-b border-white/[0.08] px-3.5">
        <TrafficLights dim />
        <span className="text-[11.5px] font-medium text-white/55">
          Library — 31 notes
        </span>
        <span className="ml-auto w-[180px] rounded-md bg-white/[0.06] px-2.5 py-1 text-[11px] text-white/40">
          ⌕ Search notes…
        </span>
      </div>

      {/* active notes grid */}
      <div className="shrink-0 px-5 pt-3.5">
        <div className="font-mono text-[9px] uppercase tracking-[0.2em] text-white/35">
          Active — 6
        </div>
        <div className="mt-2 grid grid-cols-3 gap-2.5">
          {ACTIVE_NOTES.map((note) => (
            <div
              key={note.title}
              className="h-[64px] cursor-default overflow-hidden rounded-lg border border-white/[0.09] bg-white/[0.05] p-2.5 hover:bg-white/[0.09]"
            >
              <div className="truncate text-[11.5px] font-medium text-white/85">
                {note.title}
              </div>
              <div className="mt-1 line-clamp-2 text-[10px] leading-snug text-white/40">
                {note.snippet}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* stacks zone */}
      <div className="flex shrink-0 items-baseline justify-between px-5 pt-3.5">
        <div className="font-mono text-[9px] uppercase tracking-[0.2em] text-white/35">
          Stacks — parked notes
        </div>
        <div className="font-mono text-[9px] uppercase tracking-[0.16em] text-white/25">
          {hint}
        </div>
      </div>
      <div className="relative mx-5 mb-4 flex-1">{children}</div>
    </div>
  );
}

/* ——— 01 · card pile (interactive) ————————————————————————— */

const PILE_ROT = [-7, 4, -3, 6, -5, 2, 8];

function CardPile() {
  const [fanned, setFanned] = useState(false);
  const [hovered, setHovered] = useState<number | null>(null);
  const n = STACK_NOTES.length;
  const mid = (n - 1) / 2;

  return (
    <div
      className="absolute bottom-0 left-1/2 h-[160px] w-[920px] -translate-x-1/2"
      onMouseEnter={() => setFanned(true)}
      onMouseLeave={() => {
        setFanned(false);
        setHovered(null);
      }}
    >
      {STACK_NOTES.map((note, i) => {
        const isTop = i === n - 1;
        const isHovered = fanned && hovered === i;
        const transform = fanned
          ? `translateX(${(i - mid) * 112}px) translateY(${isHovered ? -12 : 0}px) rotate(0deg) scale(${isHovered ? 1.06 : 1})`
          : `translateX(${(i - mid) * 4}px) translateY(${-i * 2}px) rotate(${PILE_ROT[i]}deg)`;
        return (
          <div
            key={note.title}
            onMouseEnter={() => setHovered(i)}
            className={
              "absolute bottom-0 left-1/2 ml-[-75px] h-[96px] w-[150px] cursor-default rounded-lg p-3 " +
              glass +
              (fanned ? " bg-[#171a29]/95" : "")
            }
            style={{
              transform,
              zIndex: isHovered ? 40 : fanned ? 20 + i : i,
              transition: "transform 340ms cubic-bezier(0.22, 1, 0.36, 1)",
            }}
          >
            <div className="truncate text-[11.5px] font-medium text-white/90">
              {note.title}
            </div>
            <div className="mt-1 line-clamp-2 text-[10px] leading-snug text-white/45">
              {note.snippet}
            </div>
            <div className="absolute bottom-2 left-3 text-[9.5px] tabular-nums text-white/35">
              {note.age}
            </div>
            {isTop && (
              <span
                className={
                  "absolute -right-2 -top-2 flex h-5 min-w-5 items-center justify-center rounded-full bg-white px-1 text-[10px] font-semibold text-black shadow transition-opacity duration-200 " +
                  (fanned ? "opacity-0" : "opacity-100")
                }
              >
                {n}
              </span>
            )}
          </div>
        );
      })}
    </div>
  );
}

/* ——— 02 · stacked sheets (interactive) ———————————————————— */

function SheetTray() {
  const sheets = STACK_NOTES.slice(1); // drop the oldest; most recently parked on top
  return (
    <div className="group absolute bottom-0 left-4 w-[460px]">
      {[...sheets].reverse().map((note, i) => {
        const open = i === 0; // most recently parked sits on top, readable
        return (
          <div
            key={note.title}
            className={
              "flex cursor-default items-center gap-3 overflow-hidden border border-b-0 border-white/[0.1] bg-white/[0.06] px-3 backdrop-blur-xl transition-all duration-300 first:rounded-t-lg last:rounded-b-lg last:border-b hover:bg-white/[0.12] " +
              (open ? "h-[54px]" : "h-[15px] group-hover:h-[34px]")
            }
          >
            <span className="h-2 w-[3px] shrink-0 rounded-full bg-white/20" />
            {open ? (
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[11.5px] font-medium text-white/90">
                  {note.title}
                </span>
                <span className="mt-0.5 block truncate text-[10px] text-white/45">
                  {note.snippet}
                </span>
              </span>
            ) : (
              <>
                <span className="min-w-0 flex-1 truncate text-[10.5px] text-white/75">
                  {note.title}
                </span>
                <span className="hidden max-w-[45%] truncate text-[9.5px] text-white/40 group-hover:block">
                  {note.snippet}
                </span>
              </>
            )}
            <span className="shrink-0 text-[9.5px] tabular-nums text-white/35">
              {note.age}
            </span>
          </div>
        );
      })}
      <span className="absolute -right-2 -top-2 flex h-5 min-w-5 items-center justify-center rounded-full bg-white px-1 text-[10px] font-semibold text-black shadow">
        {sheets.length}
      </span>
    </div>
  );
}

/* ——— 03 · shelf ——————————————————————————————————————————— */

const SHELF_GROUPS = [
  { label: "last month", count: 3, h: 58 },
  { label: "this year", count: 8, h: 76 },
  { label: "older", count: 14, h: 92 },
];

function Shelf() {
  return (
    <div className="absolute inset-0">
      {/* the ledge */}
      <div className="absolute inset-x-2 bottom-[20px] h-[3px] rounded-full bg-white/[0.12] shadow-[0_4px_14px_rgba(0,0,0,0.5)]" />
      <div className="absolute inset-x-0 bottom-[23px] flex items-end justify-center gap-16">
        {SHELF_GROUPS.map((g) => (
          <div key={g.label} className="flex flex-col items-center gap-1.5">
            <div
              className="relative w-[52px] cursor-default rounded-t-[5px] border border-white/[0.12] hover:border-white/[0.25]"
              style={{
                height: g.h,
                background:
                  "repeating-linear-gradient(to top, rgba(255,255,255,0.10) 0 1px, transparent 1px 5px)," +
                  "rgba(255,255,255,0.05)",
              }}
              title={`${g.count} notes · ${g.label}`}
            >
              <span className="absolute inset-x-0 bottom-1 text-center text-[10px] font-medium tabular-nums text-white/60">
                {g.count}
              </span>
            </div>
            <span className="h-[14px] font-mono text-[9px] uppercase tracking-[0.18em] text-white/40">
              {g.label}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ——— 04 · messy desk —————————————————————————————————————— */

const SCATTER: Array<{ note: number; x: string; y: string; r: number; o: number; z: number; w: number }> = [
  { note: 0, x: "5%", y: "10%", r: -9, o: 0.55, z: 1, w: 148 },
  { note: 1, x: "19%", y: "50%", r: 6, o: 0.65, z: 2, w: 150 },
  { note: 2, x: "73%", y: "6%", r: 10, o: 0.55, z: 1, w: 146 },
  { note: 3, x: "61%", y: "46%", r: -5, o: 0.7, z: 3, w: 152 },
  { note: 4, x: "37%", y: "4%", r: 3, o: 0.8, z: 4, w: 156 },
];

function MessyDesk() {
  const front = STACK_NOTES[6];
  return (
    <div className="absolute inset-0">
      {SCATTER.map(({ note, x, y, r, o, z, w }) => {
        const n = STACK_NOTES[note];
        return (
          <div
            key={n.title}
            className={"absolute h-[88px] cursor-default rounded-lg p-2.5 " + glass}
            style={{
              left: x,
              top: y,
              width: w,
              opacity: o,
              zIndex: z,
              transform: `rotate(${r}deg)`,
            }}
          >
            <div className="truncate text-[10.5px] font-medium text-white/80">
              {n.title}
            </div>
            <div className="mt-1 text-[9.5px] tabular-nums text-white/35">{n.age}</div>
          </div>
        );
      })}

      {/* front card — fully readable */}
      <div
        className={"absolute h-[104px] w-[210px] cursor-default rounded-lg p-3 " + glass + " bg-[#171a29]/90"}
        style={{ left: "38%", top: "32%", zIndex: 10, transform: "rotate(-2deg)" }}
      >
        <div className="truncate text-[12px] font-semibold text-white/95">
          {front.title}
        </div>
        <div className="mt-1 line-clamp-2 text-[10.5px] leading-snug text-white/50">
          {front.snippet}
        </div>
        <div className="absolute bottom-2 left-3 text-[9.5px] tabular-nums text-white/35">
          parked {front.age} ago
        </div>
        <span className="absolute -right-2 -top-2 flex h-5 min-w-5 items-center justify-center rounded-full bg-white px-1 text-[10px] font-semibold text-black shadow">
          {STACK_NOTES.length}
        </span>
      </div>
    </div>
  );
}
