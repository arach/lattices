"use client";

import { DesktopScene, SavePip, TrafficLights, glass } from "./DesktopScene";

/**
 * Study: edit ↔ read mode — two faces of one surface.
 *
 * The same note rendered twice, side by side:
 *  - edit mode: the markdown source with dimmed markers and a caret
 *  - read mode: the same content rendered as typography on glass
 *
 * The flip happens in place — ⌘⇧P both ways, double-click read→edit — so it
 * feels like turning a card, not opening a different app.
 */
export function EditorModesStudy() {
  return (
    <DesktopScene height={520}>
      {/* Edit mode — the markdown source */}
      <div
        className={
          "absolute left-[6%] top-[12%] flex w-[400px] flex-col rounded-xl " +
          glass
        }
        style={{ height: 330 }}
      >
        <PanelTitleBar title="Panels spec" saved />
        <div className="flex-1 overflow-hidden px-5 py-4 font-mono text-[12.5px] leading-[1.8] text-white/85">
          <p>
            <span className="text-white/30"># </span>
            <span className="font-semibold text-white/95">Floating panels</span>
          </p>
          <p className="mt-2">
            The note is the window —{" "}
            <span className="text-white/30">**</span>glass and text
            <span className="text-white/30">**</span>, nothing more.
          </p>
          <p className="mt-2">
            <span className="text-white/30">- </span>chrome earned on hover
          </p>
          <p>
            <span className="text-white/30">- </span>shade to a 28px bar
            <span className="animate-pulse text-white">▏</span>
          </p>
          <p className="mt-2">
            <span className="text-white/30">&gt; </span>free placement stays the
            default
          </p>
          <p className="mt-2">
            run <span className="text-white/30">`</span>Hyper+B
            <span className="text-white/30">`</span> to deploy
          </p>
        </div>
        <div className="flex h-8 items-center rounded-b-xl border-t border-white/[0.08] px-4 text-[11px] text-white/55">
          <span>✎ editing · ⌘⇧P to read</span>
        </div>
      </div>

      {/* Read mode — the same content rendered as typography */}
      <div
        className={
          "absolute right-[6%] top-[12%] flex w-[400px] flex-col rounded-xl " +
          glass
        }
        style={{ height: 330 }}
      >
        <PanelTitleBar title="Panels spec" saved dim />
        <div className="flex-1 overflow-hidden px-6 py-5">
          <h1 className="text-[20px] font-bold leading-tight text-white/96">
            Floating panels
          </h1>
          <p className="mt-3 text-[13.5px] leading-[1.7] text-white/80">
            The note is the window —{" "}
            <span className="font-semibold text-white/95">glass and text</span>,
            nothing more.
          </p>
          <ul className="mt-3 space-y-1 text-[13.5px] leading-[1.7] text-white/80">
            <li className="flex gap-2">
              <span className="text-white/30">•</span>chrome earned on hover
            </li>
            <li className="flex gap-2">
              <span className="text-white/30">•</span>shade to a 28px bar
            </li>
          </ul>
          <blockquote className="mt-3 border-l-2 border-white/20 pl-3 text-[13px] italic leading-[1.7] text-white/55">
            free placement stays the default
          </blockquote>
          <p className="mt-3 text-[13.5px] leading-[1.7] text-white/80">
            run{" "}
            <code className="rounded-[3px] bg-white/[0.07] px-1.5 py-0.5 font-mono text-[12px] text-white/85">
              Hyper+B
            </code>{" "}
            to deploy
          </p>
        </div>
        <div className="flex h-8 items-center rounded-b-xl px-6 text-[11px] text-white/45">
          <span>◧ reading · double-click to edit</span>
        </div>
      </div>

      {/* Caption chip */}
      <div className="absolute bottom-4 left-4 rounded-md bg-black/40 px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.18em] text-white/60 backdrop-blur-sm">
        two faces of one surface — flips in place, scroll preserved
      </div>
    </DesktopScene>
  );
}

function PanelTitleBar({
  title,
  saved,
  dim = false,
}: {
  title: string;
  saved: boolean;
  dim?: boolean;
}) {
  return (
    <div className="flex h-7 shrink-0 items-center justify-between border-b border-white/[0.08] px-3">
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
