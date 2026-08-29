"use client";

import { useEffect, useMemo, useState } from "react";

/**
 * Study: every note style in one place.
 *
 * The five sheet templates rendered side by side, all reacting to one shared
 * set of theme controls (accent, tint, radius, type, font, mode) — plus a
 * motion lab (eight entrances, duration/stagger/loop) so you can watch notes
 * fall into place and dial the feel, and a live config.json that mirrors what
 * the app reads. The "see all the permutations, tweak them" surface.
 */

type Sheet = "glass" | "card" | "dotted" | "bracket" | "marginalia";
type Mode = "read" | "edit";
type Entrance =
  | "none"
  | "shimmer"
  | "drop"
  | "rise"
  | "pop"
  | "slide"
  | "draw"
  | "blur";

const SHEETS: { key: Sheet; note: string }[] = [
  { key: "glass", note: "HUD blur — the default" },
  { key: "card", note: "Opaque paper, no blur" },
  { key: "dotted", note: "Dotted notebook margin" },
  { key: "bracket", note: "Corner brackets only" },
  { key: "marginalia", note: "Ruled annotation margin" },
];

const ACCENTS: { label: string; value: string }[] = [
  { label: "Ice", value: "rgba(158,203,255,0.95)" },
  { label: "Warm", value: "rgba(255,200,150,0.95)" },
  { label: "Mint", value: "rgba(150,230,190,0.95)" },
  { label: "Rose", value: "rgba(255,170,190,0.95)" },
  { label: "Violet", value: "rgba(200,170,255,0.95)" },
];

const FONTS: { label: string; value: string }[] = [
  { label: "System sans", value: '-apple-system, "SF Pro Text", system-ui, sans-serif' },
  { label: "Serif", value: '"Iowan Old Style", Charter, Georgia, serif' },
  { label: "Mono", value: 'ui-monospace, "SF Mono", Menlo, monospace' },
  { label: "Rounded", value: 'ui-rounded, "SF Pro Rounded", "Nunito", sans-serif' },
  { label: "Grotesk", value: 'Inter, "Helvetica Neue", Arial, sans-serif' },
];

const ENTRANCES: Entrance[] = [
  "none",
  "shimmer",
  "drop",
  "rise",
  "pop",
  "slide",
  "draw",
  "blur",
];

const deskBg =
  "radial-gradient(120% 90% at 15% 10%, #2b3a67 0%, transparent 55%)," +
  "radial-gradient(100% 80% at 85% 20%, #4c2f63 0%, transparent 50%)," +
  "radial-gradient(90% 90% at 70% 95%, #173f4e 0%, transparent 55%),#101322";

// Fractal-noise grain, as an inline SVG — the faint tooth that keeps glass and
// paper from reading as flat fills.
const grain =
  "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='140' height='140'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E\")";

export function StylePermutationsStudy() {
  // Defaults are the look the owner settled on — baked in.
  const [accent, setAccent] = useState(ACCENTS[1].value); // warm
  const [tintRead, setTintRead] = useState(0.36);
  const [tintEdit, setTintEdit] = useState(0.28);
  const [radius, setRadius] = useState(7);
  const [fontSize, setFontSize] = useState(11);
  const [lineHeight, setLineHeight] = useState(1.4);
  const [font, setFont] = useState(FONTS[2].value); // mono
  const [mode, setMode] = useState<Mode>("read");

  const [entrance, setEntrance] = useState<Entrance>("slide");
  const [duration, setDuration] = useState(200);
  const [stagger, setStagger] = useState(50);
  const [loop, setLoop] = useState(false);

  const [playKey, setPlayKey] = useState(0);
  const [copied, setCopied] = useState(false);

  const theme = { accent, radius, fontSize, lineHeight, font };
  const tint = mode === "edit" ? tintEdit : tintRead;

  // Loop: re-drop the whole matrix on an interval so you can just watch.
  useEffect(() => {
    if (!loop) return;
    const period = duration + SHEETS.length * stagger + 900;
    const id = setInterval(() => setPlayKey((k) => k + 1), period);
    return () => clearInterval(id);
  }, [loop, duration, stagger]);

  const configJson = useMemo(
    () =>
      JSON.stringify(
        {
          panel: {
            cornerRadius: radius,
            tintRead: round(tintRead),
            tintEdit: round(tintEdit),
          },
          editor: {
            fontFamily: font,
            accentColor: accent,
            fontSize,
            lineHeight: round(lineHeight),
          },
          motion: { entrance, durationMs: duration, staggerMs: stagger },
        },
        null,
        2,
      ),
    [radius, tintRead, tintEdit, font, accent, fontSize, lineHeight, entrance, duration, stagger],
  );

  const replay = () => setPlayKey((k) => k + 1);

  const copyConfig = async () => {
    try {
      await navigator.clipboard.writeText(configJson);
      setCopied(true);
      setTimeout(() => setCopied(false), 1400);
    } catch {
      /* clipboard blocked — no-op */
    }
  };

  return (
    <div className="w-full">
      <style>{ENTRANCE_CSS}</style>

      <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
        {/* Gallery */}
        <div
          className="relative overflow-hidden rounded-xl border border-studio-edge p-5 shadow-[0_30px_80px_rgba(0,0,0,0.35)]"
          style={{ background: deskBg }}
        >
          {/* overhead light */}
          <div
            className="pointer-events-none absolute inset-0"
            style={{
              background:
                "radial-gradient(80% 55% at 50% -10%, rgba(255,255,255,0.10), transparent 60%)",
            }}
          />
          {/* grain over the desk */}
          <div
            className="pointer-events-none absolute inset-0"
            style={{ backgroundImage: grain, backgroundSize: "140px 140px", opacity: 0.05, mixBlendMode: "overlay" }}
          />
          <div className="relative grid grid-cols-1 gap-5 md:grid-cols-2">
            {SHEETS.map((s, i) => (
              <SheetTile
                key={`${s.key}-${entrance}-${playKey}`}
                sheet={s.key}
                caption={s.note}
                theme={theme}
                tint={tint}
                mode={mode}
                entrance={entrance}
                duration={duration}
                stagger={stagger}
                index={i}
              />
            ))}
            <div className="hidden flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-white/10 md:flex">
              <span className="font-mono text-[11px] uppercase tracking-[0.16em] text-white/45">
                {mode} · {entrance}
              </span>
              <button
                onClick={replay}
                className="mt-1 rounded-md border border-white/15 px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.14em] text-white/60 hover:bg-white/10"
              >
                ▶ fall into place
              </button>
            </div>
          </div>
        </div>

        {/* Controls */}
        <aside className="space-y-5">
          <Control label="Mode">
            <Segmented options={["read", "edit"]} value={mode} onChange={(v) => setMode(v as Mode)} />
          </Control>

          <Control label="Accent">
            <div className="flex gap-2">
              {ACCENTS.map((a) => (
                <button
                  key={a.value}
                  onClick={() => setAccent(a.value)}
                  title={a.label}
                  className={
                    "h-6 w-6 rounded-full border transition-transform hover:scale-110 " +
                    (accent === a.value
                      ? "border-studio-ink-strong ring-2 ring-studio-ink-strong/30"
                      : "border-studio-rule")
                  }
                  style={{ background: a.value }}
                />
              ))}
            </div>
          </Control>

          <Control label="Font">
            <select
              value={font}
              onChange={(e) => setFont(e.target.value)}
              className="w-full rounded-md border border-studio-rule bg-studio-canvas px-2 py-1.5 text-[12px] text-studio-ink-strong"
              style={{ fontFamily: font }}
            >
              {FONTS.map((f) => (
                <option key={f.value} value={f.value} style={{ fontFamily: f.value }}>
                  {f.label}
                </option>
              ))}
            </select>
          </Control>

          <Slider
            label={`Tint · ${mode}`}
            value={mode === "edit" ? tintEdit : tintRead}
            min={0}
            max={0.6}
            step={0.02}
            onChange={(v) => (mode === "edit" ? setTintEdit(v) : setTintRead(v))}
            display={round(mode === "edit" ? tintEdit : tintRead).toString()}
          />
          <Slider label="Corner radius" value={radius} min={0} max={22} step={1} onChange={setRadius} display={`${radius}px`} />
          <Slider label="Font size" value={fontSize} min={10} max={17} step={0.5} onChange={setFontSize} display={`${fontSize}px`} />
          <Slider label="Line height" value={lineHeight} min={1.3} max={2.1} step={0.05} onChange={setLineHeight} display={round(lineHeight).toString()} />

          {/* Motion lab */}
          <div className="rounded-lg border border-studio-rule p-3">
            <div className="mb-2 font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
              Motion
            </div>
            <Chips
              options={ENTRANCES}
              value={entrance}
              onChange={(v) => {
                setEntrance(v as Entrance);
                setPlayKey((k) => k + 1);
              }}
            />
            <div className="mt-3 space-y-3">
              <Slider label="Duration" value={duration} min={120} max={900} step={20} onChange={setDuration} display={`${duration}ms`} />
              <Slider label="Stagger" value={stagger} min={0} max={180} step={10} onChange={setStagger} display={`${stagger}ms`} />
            </div>
            <div className="mt-3 flex gap-2">
              <button
                onClick={replay}
                className="flex-1 rounded-md bg-studio-ink-strong py-2 font-mono text-[10px] uppercase tracking-[0.16em] text-studio-canvas hover:opacity-90"
              >
                ▶ fall into place
              </button>
              <button
                onClick={() => setLoop((l) => !l)}
                className={
                  "rounded-md border px-3 py-2 font-mono text-[10px] uppercase tracking-[0.14em] transition-colors " +
                  (loop
                    ? "border-studio-ink-strong bg-studio-chip-bg text-studio-ink-strong"
                    : "border-studio-rule text-studio-ink-faint hover:bg-studio-chip-bg")
                }
              >
                {loop ? "loop ⏸" : "loop ↻"}
              </button>
            </div>
          </div>

          {/* config.json export */}
          <div>
            <div className="mb-2 flex items-center justify-between">
              <span className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
                config.json
              </span>
              <button
                onClick={copyConfig}
                className="rounded border border-studio-rule px-2 py-0.5 font-mono text-[10px] uppercase tracking-[0.12em] text-studio-ink-faint hover:bg-studio-chip-bg"
              >
                {copied ? "copied ✓" : "copy"}
              </button>
            </div>
            <pre className="overflow-x-auto rounded-lg border border-white/10 bg-[#0c0e14] p-3 text-[11px] leading-[1.7] text-white/70">
              {configJson}
            </pre>
          </div>
        </aside>
      </div>
    </div>
  );
}

function SheetTile({
  sheet,
  caption,
  theme,
  tint,
  mode,
  entrance,
  duration,
  stagger,
  index,
}: {
  sheet: Sheet;
  caption: string;
  theme: { accent: string; radius: number; fontSize: number; lineHeight: number; font: string };
  tint: number;
  mode: Mode;
  entrance: Entrance;
  duration: number;
  stagger: number;
  index: number;
}) {
  const surface: Record<Sheet, string> = {
    glass: "bg-white/[0.08] border border-white/[0.14] backdrop-blur-2xl",
    card: "bg-[#15171c] border border-white/10",
    dotted: "bg-white/[0.03] border border-white/10",
    bracket: "bg-white/[0.02] border border-transparent",
    marginalia: "bg-white/[0.04] border border-white/10",
  };

  const pad = sheet === "dotted" || sheet === "marginalia" ? "pl-8 pr-4 py-3.5" : "px-4 py-3.5";
  // Brackets are a square frame — they read wrong under a corner radius.
  const tileRadius = sheet === "bracket" ? 0 : theme.radius;

  return (
    <div className="flex flex-col gap-2">
      <div
        className={`sp-anim sp-anim-${entrance} relative h-[200px] overflow-hidden shadow-[0_16px_44px_rgba(0,0,0,0.45)] ${surface[sheet]}`}
        style={{
          borderRadius: tileRadius,
          animationDuration: `${duration}ms`,
          animationDelay: `${index * stagger}ms`,
        }}
      >
        {/* sheet-specific decoration */}
        {sheet === "dotted" && (
          <div className="pointer-events-none absolute left-0 top-0 bottom-0 w-7 border-r border-dashed border-white/15" />
        )}
        {sheet === "marginalia" && (
          <div className="pointer-events-none absolute left-7 top-0 bottom-0 w-px bg-rose-300/30" />
        )}
        {sheet === "bracket" && <Brackets />}

        {/* tint overlay (contrast floor) */}
        <div className="pointer-events-none absolute inset-0 bg-black" style={{ opacity: tint }} />
        {/* lighting — a soft top sheen and a hairline highlight along the top edge */}
        <div
          className="pointer-events-none absolute inset-x-0 top-0 h-1/2"
          style={{ background: "linear-gradient(to bottom, rgba(255,255,255,0.08), transparent)" }}
        />
        <div
          className="pointer-events-none absolute inset-x-0 top-0 h-px"
          style={{ background: "linear-gradient(to right, transparent, rgba(255,255,255,0.30), transparent)" }}
        />
        {/* grain texture on the sheet itself */}
        <div
          className="pointer-events-none absolute inset-0"
          style={{ backgroundImage: grain, backgroundSize: "120px 120px", opacity: 0.05, mixBlendMode: "overlay" }}
        />
        {/* shimmer sweep */}
        {entrance === "shimmer" && <div className="sp-sweep pointer-events-none absolute inset-0" />}

        {/* content */}
        <div
          className={`relative ${pad}`}
          style={{ fontSize: theme.fontSize, lineHeight: theme.lineHeight, fontFamily: theme.font }}
        >
          <div className="font-semibold text-white/95" style={{ fontSize: theme.fontSize + 4 }}>
            Weekly review
          </div>
          <div className="mt-1 text-white/55">## Friday</div>
          <div className="text-white/75">- ship the studio gallery</div>
          <div className="text-white/75">
            - see <span style={{ color: theme.accent }}>[[roadmap]]</span>
            {mode === "edit" && <span className="sp-caret" style={{ background: theme.accent }} />}
          </div>
          <div className="text-white/75">
            -{" "}
            <code
              className="rounded px-1 py-0.5"
              style={{ background: "rgba(255,255,255,0.08)", fontFamily: "ui-monospace, Menlo, monospace" }}
            >
              blink append
            </code>{" "}
            typed live
          </div>
          <div className="mt-2 border-l-2 border-white/15 pl-2 text-white/45">
            notes land where you leave them
          </div>
        </div>
      </div>
      <div className="flex items-baseline justify-between px-0.5">
        <span className="font-mono text-[12px] text-studio-ink-strong">{sheet}</span>
        <span className="text-[11px] text-studio-ink-faint">{caption}</span>
      </div>
    </div>
  );
}

function Brackets() {
  const c = "pointer-events-none absolute h-4 w-4 border-white/35";
  return (
    <>
      <span className={`${c} left-0 top-0 border-l-2 border-t-2`} />
      <span className={`${c} right-0 top-0 border-r-2 border-t-2`} />
      <span className={`${c} left-0 bottom-0 border-l-2 border-b-2`} />
      <span className={`${c} right-0 bottom-0 border-r-2 border-b-2`} />
    </>
  );
}

function Control({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="mb-2 font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
        {label}
      </div>
      {children}
    </div>
  );
}

function Slider({
  label,
  value,
  min,
  max,
  step,
  onChange,
  display,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (v: number) => void;
  display: string;
}) {
  return (
    <div>
      <div className="mb-1.5 flex items-center justify-between font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
        <span>{label}</span>
        <span className="text-studio-ink-strong">{display}</span>
      </div>
      <input
        type="range"
        value={value}
        min={min}
        max={max}
        step={step}
        onChange={(e) => onChange(Number(e.target.value))}
        className="h-1 w-full cursor-pointer appearance-none rounded-full bg-studio-rule accent-studio-ink-strong"
      />
    </div>
  );
}

function Segmented({
  options,
  value,
  onChange,
}: {
  options: string[];
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="flex rounded-md border border-studio-rule p-0.5">
      {options.map((o) => (
        <button
          key={o}
          onClick={() => onChange(o)}
          className={
            "flex-1 rounded px-2 py-1 font-mono text-[10px] uppercase tracking-[0.1em] transition-colors " +
            (value === o
              ? "bg-studio-ink-strong text-studio-canvas"
              : "text-studio-ink-faint hover:bg-studio-chip-bg")
          }
        >
          {o}
        </button>
      ))}
    </div>
  );
}

function Chips({
  options,
  value,
  onChange,
}: {
  options: string[];
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="grid grid-cols-4 gap-1">
      {options.map((o) => (
        <button
          key={o}
          onClick={() => onChange(o)}
          className={
            "rounded px-1.5 py-1 font-mono text-[10px] uppercase tracking-[0.08em] transition-colors " +
            (value === o
              ? "bg-studio-ink-strong text-studio-canvas"
              : "border border-studio-rule text-studio-ink-faint hover:bg-studio-chip-bg")
          }
        >
          {o}
        </button>
      ))}
    </div>
  );
}

function round(n: number) {
  return Math.round(n * 100) / 100;
}

const ENTRANCE_CSS = `
.sp-anim { animation-fill-mode: both; animation-timing-function: cubic-bezier(0.22,1,0.36,1); }
.sp-anim-none { animation-name: none; }
.sp-anim-shimmer { animation-name: sp-fade; }
.sp-anim-drop { animation-name: sp-drop; }
.sp-anim-rise { animation-name: sp-rise; }
.sp-anim-pop { animation-name: sp-pop; }
.sp-anim-slide { animation-name: sp-slide; }
.sp-anim-draw { animation-name: sp-draw; }
.sp-anim-blur { animation-name: sp-blur; }
@keyframes sp-fade { 0% { opacity: 0; } 100% { opacity: 1; } }
@keyframes sp-drop { 0% { opacity: 0; transform: translateY(-14px); } 72% { transform: translateY(3px); } 100% { opacity: 1; transform: translateY(0); } }
@keyframes sp-rise { 0% { opacity: 0; transform: translateY(16px); } 100% { opacity: 1; transform: translateY(0); } }
@keyframes sp-pop { 0% { opacity: 0; transform: scale(0.9); } 70% { transform: scale(1.02); } 100% { opacity: 1; transform: scale(1); } }
@keyframes sp-slide { 0% { opacity: 0; transform: translateX(-22px); } 100% { opacity: 1; transform: translateX(0); } }
@keyframes sp-draw { 0% { opacity: 0; clip-path: inset(0 100% 0 0); } 100% { opacity: 1; clip-path: inset(0 0 0 0); } }
@keyframes sp-blur { 0% { opacity: 0; filter: blur(10px); } 100% { opacity: 1; filter: blur(0); } }
.sp-sweep { background: linear-gradient(105deg, transparent 30%, rgba(255,255,255,0.18) 50%, transparent 70%); transform: translateX(-120%); animation: sp-sweep 900ms ease-out both; }
@keyframes sp-sweep { 0% { transform: translateX(-120%); } 100% { transform: translateX(160%); } }
.sp-caret { display: inline-block; width: 2px; height: 1em; margin-left: 2px; vertical-align: text-bottom; animation: sp-blink 1.05s steps(1) infinite; }
@keyframes sp-blink { 0%,49% { opacity: 1; } 50%,100% { opacity: 0; } }
`;
