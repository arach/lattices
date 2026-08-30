"use client";

import { DesktopScene, SavePip, TrafficLights, glass } from "./DesktopScene";

/**
 * Study: the floating note panel — Blink v2's atomic unit.
 *
 * Three states on one desktop:
 *  - focused panel (hover it: the footer chrome appears — chrome is earned)
 *  - resting panel (no chrome at all, just glass + text)
 *  - shaded panel (the 28px title bar is all that remains)
 */
export function NotePanelStudy() {
  return (
    <DesktopScene height={580}>
      {/* Focused panel — hover to reveal footer chrome */}
      <div
        className={
          "group absolute left-[6%] top-[10%] flex w-[420px] flex-col rounded-xl " +
          glass
        }
        style={{ height: 340 }}
      >
        <PanelTitleBar title="Meeting notes" saved />
        <div className="flex-1 overflow-hidden px-5 py-4 text-[13px] leading-[1.75] text-white/85">
          <p className="font-semibold text-white/95">## Standup</p>
          <p className="mt-2">- shipped panel drag</p>
          <p>- PanelKit geometry persistence is in</p>
          <p>
            - dictation next<span className="animate-pulse text-white">▏</span>
          </p>
          <p className="mt-3 text-white/60">
            &gt; decision: bridge stays four messages wide until M2
          </p>
        </div>
        <div className="flex h-8 items-center justify-between rounded-b-xl border-t border-white/[0.08] px-4 text-[11px] text-white/60 opacity-0 transition-opacity duration-150 group-hover:opacity-100">
          <span>142 words · saved</span>
          <span className="flex items-center gap-3">
            <span className="cursor-default hover:text-white/90">✎ edit</span>
            <span className="cursor-default hover:text-white/90">🎙</span>
          </span>
        </div>
      </div>

      {/* Resting panel — chrome fully at rest */}
      <div
        className={
          "absolute right-[7%] top-[8%] flex w-[300px] flex-col rounded-xl opacity-[0.93] " +
          glass
        }
        style={{ height: 210 }}
      >
        <PanelTitleBar title="Roadmap Q3" saved dim />
        <div className="flex-1 px-5 py-3 text-[12.5px] leading-[1.7] text-white/75">
          <p>1. PanelKit → upstream to HudsonKit</p>
          <p>2. dictation polish</p>
          <p>3. themes: keep it to five</p>
        </div>
      </div>

      {/* Shaded panel — middle-click the title bar and this is all that remains */}
      <div
        className={"absolute bottom-[12%] right-[10%] w-[260px] rounded-lg " + glass}
      >
        <PanelTitleBar title="Grocery" saved dim shaded />
      </div>

      {/* Caption chip */}
      <div className="absolute bottom-4 left-4 rounded-md bg-black/40 px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.18em] text-white/60 backdrop-blur-sm">
        hover the focused panel — chrome is earned, not given
      </div>
    </DesktopScene>
  );
}

function PanelTitleBar({
  title,
  saved,
  dim = false,
  shaded = false,
}: {
  title: string;
  saved: boolean;
  dim?: boolean;
  shaded?: boolean;
}) {
  return (
    <div
      className={
        "flex h-7 shrink-0 items-center justify-between px-3 " +
        (shaded ? "" : "border-b border-white/[0.08]")
      }
    >
      <TrafficLights dim={dim} />
      <span
        className={
          "pointer-events-none absolute left-1/2 -translate-x-1/2 text-[11px] font-medium " +
          (dim ? "text-white/40" : "text-white/55")
        }
      >
        {title}
      </span>
      <SavePip saved={saved} />
    </div>
  );
}
