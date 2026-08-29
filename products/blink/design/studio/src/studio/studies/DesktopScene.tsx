"use client";

import type { ReactNode } from "react";

/**
 * A simulated macOS desktop that every Blink study renders into. Self-contained
 * dark wallpaper so glass materials read the same in both studio themes.
 */
export function DesktopScene({
  children,
  menubar = false,
  dimmed = false,
  height = 560,
}: {
  children: ReactNode;
  menubar?: boolean;
  dimmed?: boolean;
  height?: number;
}) {
  return (
    <div
      className="relative w-full select-none overflow-hidden rounded-xl border border-studio-edge shadow-[0_30px_80px_rgba(0,0,0,0.35)]"
      style={{
        height,
        background:
          "radial-gradient(120% 90% at 15% 10%, #2b3a67 0%, transparent 55%)," +
          "radial-gradient(100% 80% at 85% 20%, #4c2f63 0%, transparent 50%)," +
          "radial-gradient(90% 90% at 70% 95%, #173f4e 0%, transparent 55%)," +
          "radial-gradient(70% 70% at 30% 80%, #3d2b4f 0%, transparent 60%)," +
          "#101322",
      }}
    >
      {menubar && (
        <div className="absolute inset-x-0 top-0 z-10 flex h-7 items-center justify-between border-b border-white/[0.06] bg-black/25 px-3 backdrop-blur-md">
          <div className="flex items-center gap-4 text-[12px] text-white/80">
            <span className="text-[13px]"></span>
            <span className="font-semibold">Finder</span>
            <span className="text-white/50">File</span>
            <span className="text-white/50">Edit</span>
            <span className="text-white/50">View</span>
          </div>
          <div className="flex items-center gap-3 text-[11px] text-white/70">
            <BlinkStatusIcon active />
            <span>􀙇</span>
            <span>􀋦</span>
            <span className="tabular-nums">Tue 9:41 AM</span>
          </div>
        </div>
      )}

      {children}

      {dimmed && (
        <div className="pointer-events-none absolute inset-0 z-20 bg-black/35" />
      )}
    </div>
  );
}

/** The Blink status item — an eye glyph in the menubar. */
export function BlinkStatusIcon({ active = false }: { active?: boolean }) {
  return (
    <span
      className={
        "flex h-5 items-center rounded px-1.5 " +
        (active ? "bg-white/20" : "")
      }
      title="Blink"
    >
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" className="text-white/90">
        <path
          d="M2 12s3.5-6.5 10-6.5S22 12 22 12s-3.5 6.5-10 6.5S2 12 2 12Z"
          stroke="currentColor"
          strokeWidth="1.6"
        />
        <circle cx="12" cy="12" r="2.6" fill="currentColor" />
      </svg>
    </span>
  );
}

/** Standard glass material for mock Blink surfaces. */
export const glass =
  "border border-white/[0.14] bg-white/[0.08] shadow-[0_20px_60px_rgba(0,0,0,0.45)] backdrop-blur-2xl";

/** Heavier glass for popover / palette surfaces that sit over content. */
export const glassHeavy =
  "border border-white/[0.12] bg-[#1a1d2e]/80 shadow-[0_24px_70px_rgba(0,0,0,0.55)] backdrop-blur-2xl";

export function TrafficLights({ dim = false }: { dim?: boolean }) {
  const base = "h-[10px] w-[10px] rounded-full";
  return (
    <div className={"flex items-center gap-[7px] " + (dim ? "opacity-40" : "")}>
      <span className={base + " bg-[#ff5f57]"} />
      <span className={base + " bg-[#febc2e]"} />
      <span className={base + " bg-[#28c840]"} />
    </div>
  );
}

export function SavePip({ saved = true }: { saved?: boolean }) {
  return (
    <span
      className={
        "h-[7px] w-[7px] rounded-full " +
        (saved ? "bg-emerald-400/90" : "bg-amber-400/90")
      }
      title={saved ? "saved" : "unsaved changes"}
    />
  );
}
