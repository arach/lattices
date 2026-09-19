"use client";

/**
 * Space Bezel — boxy tray of logo-cells, one cell per Space.
 *
 * The 3×3 mark's rounded-square cell becomes the atom: N cells for N spaces.
 * The container is a box, not a capsule. Three color treatments on the same
 * anatomy:
 *
 * A  Mono     — all cells same gray; active = bright (the logo's own
 *               bright/dim mechanic). Only EDGE borrows color.
 * B  Signal   — cells gray; active = cyan glow, EDGE = amber. Color only
 *               ever means "state", never "identity".
 * C  Spectrum — each space tinted from the Lats palette. The color-coded
 *               extreme, for comparison.
 *
 * The stage is a mock desktop — drive it with ←/→. The space content swaps
 * with a slight directional drift (no parallax, nothing animated beyond
 * ~200ms). Bezel column docks at the travel edge; press at a boundary to
 * see the amber EDGE states.
 */

import { useCallback, useEffect, useState } from "react";
import { ArrowLeft, ArrowRight } from "lucide-react";
import type { LatticesPage } from "@/studio/studioRegistry";

// ── Lats tokens (HUDChrome.swift / Theme.swift / DeckBuilder TINTS) ──────
const CYAN = "#57C7F5";      // HUDChrome.cyan
const AMBER = "#F5A624";     // Palette.detach — edge signal
const BASE_TOP = "#0E0F12";  // HUDChrome.baseTop
const BASE_BOT = "#060709";  // HUDChrome.baseBottom
const FG = "#E2E2DF";
const FG3 = "#71716C";
const DIM_CELL = "rgba(242,242,242,0.18)"; // logo.svg dim cell
const LIT_CELL = "#F2F2F2";                // logo.svg bright cell

const TINTS = ["#6ECFCF", "#7EAFE2", "#81DD86", "#E8BC6B", "#BD97FC"]; // teal blue green amber violet
const SPACES = 5;
type Dir = "left" | "right";

// ── bezel atoms ──────────────────────────────────────────────────────────

function LogoCell({
  color,
  opacity = 1,
  glow = false,
  size = 15,
}: {
  color: string;
  opacity?: number;
  glow?: boolean;
  size?: number;
}) {
  return (
    <div
      style={{
        width: size,
        height: size,
        borderRadius: size * 0.24, // logo rx≈10 on 107 → ~9.3%
        background: color,
        opacity,
        boxShadow: glow ? `0 0 8px ${color}66, inset 0 0 0 0.5px ${color}` : "none",
        transition: "background .18s ease, opacity .18s ease, box-shadow .18s ease",
      }}
    />
  );
}

/** Boxy tray — rounded-rect, not a capsule. Slides in from travel edge. */
function Tray({
  dir,
  seq,
  edge,
  children,
}: {
  dir: Dir;
  seq: number;
  edge: boolean;
  children: React.ReactNode;
}) {
  const accent = edge ? AMBER : CYAN;
  return (
    <div
      key={seq}
      style={{
        borderRadius: 10,
        display: "flex",
        alignItems: "center",
        gap: 9,
        padding: "9px 11px",
        width: "max-content",
        background: `linear-gradient(180deg, ${BASE_TOP} 0%, ${BASE_BOT} 100%)`,
        border: `1px solid ${edge ? "rgba(245,166,36,0.38)" : "rgba(255,255,255,0.10)"}`,
        boxShadow: [
          "0 10px 28px rgba(0,0,0,0.60)",
          `inset 0 0 0 0.5px ${accent}22`,
          `0 0 22px ${accent}14`,
        ].join(", "),
        animation: edge
          ? "trayBump .32s cubic-bezier(.3,1.4,.4,1)"
          : "trayIn .22s cubic-bezier(.22,1.3,.36,1)",
        ["--drift" as string]: dir === "left" ? "-14px" : "14px",
      }}
    >
      {children}
    </div>
  );
}

function Hairline() {
  return <div style={{ width: 1, height: 20, background: "rgba(255,255,255,0.12)" }} />;
}

function StateLabel({ n, edge }: { n: number; edge: boolean }) {
  return (
    <span
      style={{
        fontSize: 10,
        letterSpacing: "0.14em",
        fontWeight: 600,
        color: edge ? AMBER : FG,
        fontFamily: "ui-monospace, monospace",
      }}
    >
      {edge ? "EDGE" : `DESKTOP ${n}`}
    </span>
  );
}

function Wordmark() {
  return (
    <span
      style={{
        fontSize: 7,
        letterSpacing: "0.22em",
        fontWeight: 600,
        color: FG3,
        fontFamily: "ui-monospace, monospace",
      }}
    >
      LATTICES
    </span>
  );
}

/** Direction tick — a small chevron riding the tray's leading side. */
function DirTick({ dir, edge }: { dir: Dir; edge: boolean }) {
  return (
    <span
      style={{
        fontSize: 13,
        fontWeight: 700,
        lineHeight: 1,
        color: edge ? AMBER : CYAN,
        fontFamily: "ui-monospace, monospace",
      }}
    >
      {edge ? "↔" : dir === "left" ? "‹" : "›"}
    </span>
  );
}

// ── the three treatments ─────────────────────────────────────────────────

interface VProps {
  dir: Dir;
  idx: number;
  edge: boolean;
  seq: number;
}

function Cells({
  idx,
  edge,
  seq,
  color,
}: VProps & { color: (i: number, active: boolean) => { c: string; o: number; g: boolean } }) {
  return (
    <>
      {Array.from({ length: SPACES }, (_, i) => {
        const { c, o, g } = color(i, i === idx);
        return <LogoCell key={`${seq}-${i}`} color={c} opacity={o} glow={g} />;
      })}
    </>
  );
}

/** A · Mono — the logo's own bright/dim language, no hue. */
function BezelMono(p: VProps) {
  return (
    <Tray dir={p.dir} seq={p.seq} edge={p.edge}>
      <DirTick dir={p.dir} edge={p.edge} />
      <Cells
        {...p}
        color={(_i, active) =>
          active
            ? { c: p.edge ? AMBER : LIT_CELL, o: 1, g: true }
            : { c: DIM_CELL, o: 1, g: false }
        }
      />
      <Hairline />
      <StateLabel n={p.idx + 1} edge={p.edge} />
      <Wordmark />
    </Tray>
  );
}

/** B · Signal — color only means state: cyan active, amber edge. */
function BezelSignal(p: VProps) {
  return (
    <Tray dir={p.dir} seq={p.seq} edge={p.edge}>
      <DirTick dir={p.dir} edge={p.edge} />
      <Cells
        {...p}
        color={(_i, active) =>
          active
            ? { c: p.edge ? AMBER : CYAN, o: 1, g: true }
            : { c: DIM_CELL, o: 1, g: false }
        }
      />
      <Hairline />
      <StateLabel n={p.idx + 1} edge={p.edge} />
      <Wordmark />
    </Tray>
  );
}

/** C · Spectrum — each space carries a Lats tint. */
function BezelSpectrum(p: VProps) {
  return (
    <Tray dir={p.dir} seq={p.seq} edge={p.edge}>
      <DirTick dir={p.dir} edge={p.edge} />
      <Cells
        {...p}
        color={(i, active) =>
          active
            ? { c: p.edge ? AMBER : TINTS[i], o: 1, g: true }
            : { c: TINTS[i], o: 0.28, g: false }
        }
      />
      <Hairline />
      <StateLabel n={p.idx + 1} edge={p.edge} />
      <Wordmark />
    </Tray>
  );
}

// ── mock desktop ─────────────────────────────────────────────────────────

/** Five fake window arrangements, % of the stage. */
const SPACE_LAYOUTS: { x: number; y: number; w: number; h: number }[][] = [
  [{ x: 5, y: 12, w: 58, h: 78 }, { x: 66, y: 12, w: 29, h: 40 }, { x: 66, y: 56, w: 29, h: 34 }],
  [{ x: 5, y: 12, w: 42, h: 78 }, { x: 50, y: 12, w: 45, h: 78 }],
  [{ x: 8, y: 16, w: 84, h: 70 }],
  [{ x: 5, y: 12, w: 30, h: 78 }, { x: 38, y: 12, w: 30, h: 78 }, { x: 71, y: 12, w: 24, h: 78 }],
  [{ x: 5, y: 12, w: 58, h: 38 }, { x: 5, y: 54, w: 58, h: 36 }, { x: 66, y: 12, w: 29, h: 78 }],
];

const SPACE_TINT = ["#57C7F5", "#81DD86", "#E8BC6B", "#BD97FC", "#6ECFCF"];

function Desktop({
  idx,
  dir,
  seq,
  children,
}: {
  idx: number;
  dir: Dir;
  seq: number;
  children: React.ReactNode;
}) {
  const tint = SPACE_TINT[idx];
  return (
    <div
      style={{
        position: "relative",
        height: 400,
        borderRadius: 12,
        border: "1px solid #1e2024",
        background: "#050607",
        overflow: "hidden",
      }}
    >
      {/* menu bar */}
      <div
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          right: 0,
          height: 22,
          background: "rgba(255,255,255,0.035)",
          borderBottom: "1px solid rgba(255,255,255,0.05)",
          display: "flex",
          alignItems: "center",
          padding: "0 12px",
          gap: 8,
        }}
      >
        <div style={{ width: 8, height: 8, borderRadius: 2, background: "rgba(255,255,255,0.14)" }} />
        <div style={{ width: 40, height: 5, borderRadius: 2.5, background: "rgba(255,255,255,0.08)" }} />
        <div style={{ marginLeft: "auto", width: 60, height: 5, borderRadius: 2.5, background: "rgba(255,255,255,0.06)" }} />
      </div>

      {/* the space's windows — slight drift+fade on swap */}
      <div
        key={seq}
        style={{
          position: "absolute",
          inset: 0,
          animation: "spaceSlide .24s cubic-bezier(.25,.9,.3,1)",
          ["--slide" as string]: dir === "left" ? "-22px" : "22px",
        }}
      >
        {SPACE_LAYOUTS[idx].map((w, i) => (
          <div
            key={i}
            style={{
              position: "absolute",
              left: `${w.x}%`,
              top: `${w.y}%`,
              width: `${w.w}%`,
              height: `${w.h}%`,
              borderRadius: 7,
              border: `1px solid ${i === 0 ? `${tint}30` : "rgba(255,255,255,0.07)"}`,
              background:
                i === 0
                  ? `linear-gradient(180deg, ${tint}0d, rgba(255,255,255,0.02))`
                  : "rgba(255,255,255,0.025)",
              boxShadow: i === 0 ? `0 0 30px ${tint}0a` : "none",
            }}
          >
            <div
              style={{
                height: 14,
                margin: "6px 8px",
                borderRadius: 4,
                background: "rgba(255,255,255,0.05)",
              }}
            />
          </div>
        ))}
      </div>

      {/* bezel column docked at the travel edge */}
      <div
        style={{
          position: "absolute",
          [dir]: 18,
          top: "50%",
          transform: "translateY(-50%)",
          display: "flex",
          flexDirection: "column",
          gap: 10,
          alignItems: dir === "left" ? "flex-start" : "flex-end",
        }}
      >
        {children}
      </div>
    </div>
  );
}

// ── study page ───────────────────────────────────────────────────────────

const VARIANTS = [
  { key: "A", name: "Mono", note: "The logo's own bright/dim — no hue at all. Only EDGE borrows amber." },
  { key: "B", name: "Signal", note: "Color = state only. Cyan lands you, amber blocks you." },
  { key: "C", name: "Spectrum", note: "Each space tinted. The color-coded extreme — richest, loudest." },
] as const;

export function SpaceBezelStudy({ page }: { page: LatticesPage }) {
  const [idx, setIdx] = useState(2);
  const [dir, setDir] = useState<Dir>("right");
  const [edge, setEdge] = useState(false);
  const [seq, setSeq] = useState(1);

  const press = useCallback((d: Dir) => {
    setDir(d);
    setIdx((cur) => {
      const next = cur + (d === "right" ? 1 : -1);
      if (next < 0 || next >= SPACES) {
        setEdge(true);
        return cur;
      }
      setEdge(false);
      return next;
    });
    setSeq((s) => s + 1);
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "ArrowLeft") press("left");
      if (e.key === "ArrowRight") press("right");
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [press]);

  const v = { dir, idx, edge, seq };

  return (
    <main className="w-full px-6 py-10 lg:px-7">
      <style>{`
        @keyframes trayIn {
          from { opacity: 0; transform: translateX(var(--drift)); }
          to   { opacity: 1; transform: none; }
        }
        @keyframes trayBump {
          0%   { transform: none; }
          35%  { transform: translateX(calc(var(--drift) * -0.3)); }
          100% { transform: none; }
        }
        @keyframes spaceSlide {
          from { opacity: 0; transform: translateX(var(--slide)); }
          to   { opacity: 1; transform: none; }
        }
      `}</style>

      <header className="max-w-[980px] border-b border-studio-rule pb-7">
        <div className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
          {page.bucket} / {page.surface}
        </div>
        <h1 className="mt-4 text-[36px] font-medium leading-tight text-studio-ink-strong">
          {page.label}
        </h1>
        {page.blurb ? (
          <p className="mt-4 max-w-[66ch] text-[15px] leading-[1.7] text-studio-ink">
            {page.blurb}
          </p>
        ) : null}
      </header>

      {/* controls */}
      <section className="mt-6 flex items-center gap-4">
        <button
          onClick={() => press("left")}
          className="flex items-center gap-2 rounded-md border border-studio-rule px-3 py-1.5 font-mono text-[11px] text-studio-ink hover:bg-studio-chip-bg"
        >
          <ArrowLeft size={13} /> ctrl
        </button>
        <button
          onClick={() => press("right")}
          className="flex items-center gap-2 rounded-md border border-studio-rule px-3 py-1.5 font-mono text-[11px] text-studio-ink hover:bg-studio-chip-bg"
        >
          ctrl <ArrowRight size={13} />
        </button>
        <span className="font-mono text-[11px] text-studio-ink-faint">
          or use ←/→ — space {idx + 1} of {SPACES}
          {edge ? " · at the wall" : ""}
        </span>
      </section>

      {/* mock desktop with all three trays docked at the travel edge */}
      <section className="mt-6">
        <Desktop idx={idx} dir={dir} seq={seq}>
          <BezelMono {...v} />
          <BezelSignal {...v} />
          <BezelSpectrum {...v} />
        </Desktop>
      </section>

      {/* legend */}
      <section className="mt-6 grid gap-3 md:grid-cols-3">
        {VARIANTS.map((t) => (
          <div key={t.key} className="rounded-lg border border-studio-rule p-4">
            <div className="flex items-baseline gap-3">
              <span className="font-mono text-[10px] uppercase tracking-eyebrow" style={{ color: CYAN }}>
                {t.key}
              </span>
              <span className="text-[14px] font-medium text-studio-ink-strong">{t.name}</span>
            </div>
            <p className="mt-2 text-[12.5px] leading-relaxed text-studio-ink-faint">{t.note}</p>
          </div>
        ))}
      </section>

      <p className="mt-8 max-w-[68ch] font-mono text-[11px] leading-relaxed text-studio-ink-faint">
        Cell count follows the space count (5 shown; &gt;9 could wrap into a
        second row or shrink). Tray chrome: baseTop→baseBottom gradient,
        10px radius, inset signal ring — boxy sibling of the shipping pill.
      </p>
    </main>
  );
}
