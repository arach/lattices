"use client";

import { DesktopScene } from "./DesktopScene";

/**
 * Study: the spatial grid overlay — Hyper+B makes the 3×3 deploy grid visible.
 *
 * v1 had grid deploys as invisible muscle memory. Showing slot occupancy and
 * the QWERTY chord keys turns a power-user chord into something you can see
 * and learn. Free placement stays the default; the grid is opt-in per action.
 */

const SLOTS = [
  { n: 1, key: "Q", occupied: "Meeting notes" },
  { n: 2, key: "W" },
  { n: 3, key: "E" },
  { n: 4, key: "A" },
  { n: 5, key: "S", targeted: true },
  { n: 6, key: "D" },
  { n: 7, key: "Z" },
  { n: 8, key: "X" },
  { n: 9, key: "C", occupied: "Roadmap Q3" },
] as const;

export function GridOverlayStudy() {
  return (
    <DesktopScene height={580}>
      <div className="pointer-events-none absolute inset-0 z-10 bg-black/40" />

      <div className="absolute inset-0 z-20 flex flex-col items-center justify-center gap-5 px-10 py-12">
        <div className="grid h-full w-full max-w-[860px] grid-cols-3 grid-rows-3 gap-4">
          {SLOTS.map((slot) => (
            <div
              key={slot.n}
              className={
                "relative rounded-lg border backdrop-blur-[2px] transition-colors " +
                ("targeted" in slot && slot.targeted
                  ? "border-white/70 bg-white/[0.12] shadow-[0_0_40px_rgba(255,255,255,0.15)]"
                  : "border-dashed border-white/[0.22] bg-white/[0.03]")
              }
            >
              <div className="absolute left-2.5 top-2 flex items-center gap-2">
                <span className="font-mono text-[11px] text-white/45">{slot.n}</span>
                <span className="rounded border border-white/[0.2] bg-white/[0.08] px-1.5 py-0.5 font-mono text-[11px] font-semibold text-white/80">
                  {slot.key}
                </span>
              </div>

              {"occupied" in slot && slot.occupied && (
                <div className="absolute inset-x-3 bottom-3 top-9 rounded-md border border-white/[0.14] bg-white/[0.08] px-3 py-2 backdrop-blur-xl">
                  <span className="text-[11px] text-white/70">
                    ● {slot.occupied}
                  </span>
                </div>
              )}

              {"targeted" in slot && slot.targeted && (
                <span className="absolute inset-x-0 bottom-3 text-center font-mono text-[10px] uppercase tracking-[0.2em] text-white/70">
                  deploy here
                </span>
              )}
            </div>
          ))}
        </div>

        <div className="rounded-md bg-black/45 px-4 py-2 font-mono text-[11px] text-white/65 backdrop-blur-sm">
          Hyper+B → key to deploy · Esc to cancel
        </div>
      </div>
    </DesktopScene>
  );
}
