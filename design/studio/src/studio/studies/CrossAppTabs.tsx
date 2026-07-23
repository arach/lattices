"use client";

import { useState } from "react";
import {
  ChevronDown,
  ExternalLink,
  Globe2,
  Grid2X2,
  Layers3,
  Plus,
  Search,
  Terminal,
  X,
} from "lucide-react";
import type { LatticesPage } from "@/studio/studioRegistry";

type TabID = "chrome" | "terminal";

const tabs = [
  {
    id: "chrome" as const,
    app: "Google Chrome",
    label: "Chrome",
    title: "lattices — GitHub",
    icon: Globe2,
  },
  {
    id: "terminal" as const,
    app: "iTerm2",
    label: "iTerm",
    title: "lattices — zsh",
    icon: Terminal,
  },
];

export function CrossAppTabsStudy({ page }: { page: LatticesPage }) {
  const [activeTab, setActiveTab] = useState<TabID>("chrome");
  const [isGrid, setIsGrid] = useState(false);

  return (
    <main className="w-full px-6 py-10 lg:px-7">
      <header className="max-w-[980px] border-b border-studio-rule pb-7">
        <div className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
          {page.bucket} / {page.surface}
        </div>
        <h1 className="mt-4 text-[36px] font-medium leading-tight text-studio-ink-strong">
          {page.label}
        </h1>
        <p className="mt-4 max-w-[70ch] text-[15px] leading-[1.7] text-studio-ink">
          {page.blurb}
        </p>
      </header>

      <section className="py-8">
        <div className="mb-4 flex flex-wrap items-end justify-between gap-4">
          <div>
            <div className="font-mono text-[10px] uppercase tracking-[0.2em] text-studio-ink-faint">
              Live specimen / Hyper-3
            </div>
            <p className="mt-2 max-w-[66ch] text-[13px] leading-relaxed text-studio-ink-faint">
              Two real macOS windows occupy one frame. Lattices contributes only the shared
              chrome: identity, switching, and the stack-to-grid transition.
            </p>
          </div>
          <div className="flex items-center gap-2 rounded-full border border-studio-chip-border bg-studio-chip-bg px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.16em] text-studio-ink-faint">
            <span className="h-1.5 w-1.5 rounded-full bg-[#68e7d1] shadow-[0_0_8px_rgba(104,231,209,.7)]" />
            Interactive
          </div>
        </div>

        <div className="overflow-hidden rounded-[18px] border border-white/[0.09] bg-[#080a0c] shadow-[0_28px_90px_rgba(0,0,0,.34)]">
          <DesktopBar />

          <div
            className="relative min-h-[650px] overflow-hidden p-8 lg:p-12"
            style={{
              background:
                "radial-gradient(circle at 48% 16%, rgba(78,91,96,.14), transparent 42%), linear-gradient(145deg,#101316 0%,#0a0d0f 58%,#07090b 100%)",
            }}
          >
            <div className="absolute inset-0 opacity-[0.035] [background-image:linear-gradient(rgba(255,255,255,.5)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,.5)_1px,transparent_1px)] [background-size:32px_32px]" />

            <div className="relative mx-auto max-w-[1120px]">
              <div className="mb-5 flex items-center justify-between font-mono text-[9px] uppercase tracking-[0.18em] text-white/35">
                <span>Topic · Cross-app tab system</span>
                <span>{isGrid ? "Grid overview" : "Stacked · top left"}</span>
              </div>

              <div className="rounded-[11px] border border-white/[0.14] bg-[#15191d]/96 p-[3px] shadow-[0_24px_70px_rgba(0,0,0,.52),0_1px_0_rgba(255,255,255,.04)_inset]">
                <TabRail
                  activeTab={activeTab}
                  isGrid={isGrid}
                  onSelect={(id) => {
                    setActiveTab(id);
                    setIsGrid(false);
                  }}
                  onToggleGrid={() => setIsGrid((value) => !value)}
                />

                <div className="overflow-hidden rounded-b-[7px] border border-white/[0.08] border-t-0 bg-[#0d1115]">
                  {isGrid ? (
                    <div className="grid min-h-[492px] gap-px bg-white/[0.06] p-px md:grid-cols-2">
                      <button
                        type="button"
                        onClick={() => {
                          setActiveTab("chrome");
                          setIsGrid(false);
                        }}
                        className="group relative min-h-[360px] overflow-hidden bg-[#11161a] text-left"
                      >
                        <WindowLabel app="Google Chrome" title="lattices — GitHub" icon={Globe2} />
                        <ChromeSurface compact />
                        <OpenHint />
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setActiveTab("terminal");
                          setIsGrid(false);
                        }}
                        className="group relative min-h-[360px] overflow-hidden bg-[#090d10] text-left"
                      >
                        <WindowLabel app="iTerm2" title="lattices — zsh" icon={Terminal} />
                        <TerminalSurface compact />
                        <OpenHint />
                      </button>
                    </div>
                  ) : activeTab === "chrome" ? (
                    <ChromeSurface />
                  ) : (
                    <TerminalSurface />
                  )}
                </div>
              </div>

              <div className="mt-4 flex flex-wrap items-center justify-between gap-3 px-1 font-mono text-[9px] uppercase tracking-[0.16em] text-white/34">
                <span>⌃⌥⇧⌘3 reveals group chrome</span>
                <span>Click a tab to raise its real window · Grid never creates a clone</span>
              </div>
            </div>
          </div>
        </div>

        <div className="mt-8 grid border-y border-studio-rule md:grid-cols-3 md:divide-x md:divide-studio-rule">
          <Principle number="01" title="One frame">
            The group owns a single spatial footprint. Selecting a tab raises another native
            window into that exact frame.
          </Principle>
          <Principle number="02" title="Thin ownership">
            Lattices adds 38 pixels of chrome and a quiet signal border. The apps remain visually
            and behaviorally themselves.
          </Principle>
          <Principle number="03" title="Grid is a mode">
            Grid temporarily fans the same windows out for comparison; choosing one collapses the
            group back into a stack.
          </Principle>
        </div>
      </section>
    </main>
  );
}

function DesktopBar() {
  return (
      <div className="flex h-10 items-center border-b border-white/[0.07] bg-[#111315] px-4">
      <div className="flex gap-2">
        <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
        <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
        <span className="h-2.5 w-2.5 rounded-full bg-white/15" />
      </div>
      <div className="mx-auto flex items-center gap-2 text-[10px] text-white/38">
        <Layers3 size={12} /> Research workspace
      </div>
      <div className="w-[52px] text-right font-mono text-[9px] text-white/25">12:43</div>
    </div>
  );
}

function TabRail({
  activeTab,
  isGrid,
  onSelect,
  onToggleGrid,
}: {
  activeTab: TabID;
  isGrid: boolean;
  onSelect: (id: TabID) => void;
  onToggleGrid: () => void;
}) {
  return (
    <div className="flex h-[38px] items-end gap-1 rounded-t-[7px] border border-white/[0.07] bg-[#202428]/95 px-1.5 pt-1 shadow-[0_1px_0_rgba(255,255,255,.035)_inset] backdrop-blur-xl">
      <button
        type="button"
        className="mb-1 mr-0.5 flex h-7 min-w-[116px] items-center gap-1.5 rounded px-2 text-left text-white/70 hover:bg-white/[0.045] hover:text-white/90"
        aria-label="Research tab group"
      >
        <span className="grid h-4 w-4 place-items-center rounded-[4px] border border-white/[0.08] bg-black/20 text-white/52">
          <Layers3 size={9} strokeWidth={1.8} />
        </span>
        <span className="truncate text-[9.5px] font-medium">Research</span>
        <ChevronDown size={9} className="ml-auto text-white/25" />
      </button>

      <span className="mb-2 h-4 w-px bg-white/[0.08]" />

      <div className="flex min-w-0 flex-1 items-end gap-1 overflow-x-auto px-0.5">
        {tabs.map((tab) => {
          const Icon = tab.icon;
          const active = activeTab === tab.id && !isGrid;
          return (
            <button
              key={tab.id}
              type="button"
              onClick={() => onSelect(tab.id)}
              aria-label={`${tab.app} ${tab.title}`}
              title={`${tab.app} · ${tab.title}`}
              className={`relative flex h-[30px] min-w-[108px] max-w-[142px] items-center gap-2 rounded-t-[6px] border border-b-0 px-2.5 text-left transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-inset focus-visible:ring-[#6ed8c8]/65 ${
                active
                  ? "border-white/[0.11] bg-[#2d3236] text-white/92 shadow-[0_-1px_0_rgba(255,255,255,.025)_inset]"
                  : "border-transparent bg-transparent text-white/38 hover:bg-white/[0.04] hover:text-white/70"
              }`}
            >
              {active ? <span className="absolute inset-x-2 bottom-0 h-[2px] rounded-t-full bg-[#6ed8c8]/75" /> : null}
              <Icon size={11} className={active ? "text-[#6ed8c8]" : "text-white/30"} />
              <span className="truncate text-[9.5px] font-medium">{tab.label}</span>
            </button>
          );
        })}

        <button
          type="button"
          className="mb-1 grid h-7 w-7 shrink-0 place-items-center rounded text-white/20 hover:bg-white/[0.04] hover:text-white/60"
          aria-label="Add tab"
        >
          <Plus size={11} />
        </button>
      </div>

      <span className="mb-2 h-4 w-px bg-white/[0.08]" />

      <button
        type="button"
        onClick={onToggleGrid}
        aria-label={isGrid ? "Return to stack" : "Grid"}
        title={isGrid ? "Return to stack" : "Show group as grid"}
        className={`mb-1 grid h-7 w-8 place-items-center rounded border transition-colors ${
          isGrid
            ? "border-white/[0.16] bg-[#d9dfdf] text-[#161a1d]"
            : "border-transparent bg-transparent text-white/32 hover:bg-white/[0.04] hover:text-white/72"
        }`}
      >
        <Grid2X2 size={11} />
      </button>
    </div>
  );
}

function ChromeSurface({ compact = false }: { compact?: boolean }) {
  const files = [
    ["apps", "macOS app and website"],
    ["bin", "CLI and app build tools"],
    ["design/studio", "product studies"],
    ["docs", "concepts, API, and layers"],
    ["README.md", "Lattices workspace manager"],
  ];

  return (
    <div className={`${compact ? "h-full min-h-[425px]" : "min-h-[492px]"} bg-[#f6f8fa] text-[#1f2328]`}>
      <div className="border-b border-black/15 bg-[#dee1e5]">
        <div className="flex h-9 items-end gap-2 px-3">
          <div className="mb-3 flex gap-1.5">
            <span className="h-2.5 w-2.5 rounded-full bg-[#ff5f57]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#febc2e]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#28c840]" />
          </div>
          <div className="flex h-7 min-w-0 max-w-[245px] flex-1 items-center gap-2 rounded-t-lg bg-[#f3f4f5] px-3 text-[9px] text-black/70 shadow-sm">
            <span className="grid h-3.5 w-3.5 place-items-center rounded-full bg-[#24292f] text-[6px] font-bold text-white">GH</span>
            <span className="truncate">arach/lattices · GitHub</span>
            <X size={9} className="ml-auto text-black/35" />
          </div>
          <Plus size={11} className="mb-2 text-black/45" />
        </div>
        <div className="flex h-9 items-center gap-2 bg-[#f3f4f5] px-3">
          <span className="text-[13px] text-black/35">‹</span>
          <span className="text-[13px] text-black/35">›</span>
          <span className="text-[12px] text-black/38">↻</span>
          <div className="flex h-6 flex-1 items-center rounded-full border border-black/[0.08] bg-white/80 px-3 text-[8px] text-black/45">
            <Search size={9} className="mr-2" /> github.com/arach/lattices
          </div>
          <span className="grid h-5 w-5 place-items-center rounded-full bg-[#59636d] text-[7px] font-semibold text-white">A</span>
        </div>
      </div>

      <div className={`${compact ? "px-5 py-5 pt-14" : "px-8 py-7 lg:px-12"}`}>
        <div className="mx-auto max-w-[820px]">
          <div className="flex items-center gap-2 text-[10px] text-[#59636d]">
            <span className="grid h-6 w-6 place-items-center rounded-md bg-[#24292f] text-[8px] font-bold text-white">L</span>
            <span className="text-[#0969da]">arach</span>
            <span>/</span>
            <strong className="text-[13px] text-[#1f2328]">lattices</strong>
            <span className="rounded-full border border-black/15 px-1.5 py-0.5 text-[7px]">Public</span>
          </div>

          <div className="mt-5 flex items-center gap-4 border-b border-black/10 pb-2 text-[9px] text-[#59636d]">
            <strong className="border-b-2 border-[#fd8c73] pb-2 text-[#1f2328]">Code</strong>
            <span>Issues&nbsp; 12</span>
            <span>Pull requests&nbsp; 3</span>
            <span>Actions</span>
          </div>

          <div className="mt-4 overflow-hidden rounded-md border border-[#d0d7de] bg-white">
            <div className="flex h-9 items-center border-b border-[#d0d7de] bg-[#f6f8fa] px-3 text-[8px] text-[#59636d]">
              <strong className="text-[#1f2328]">main</strong>
              <span className="ml-auto">02b9c61 · Add cross-app tab groups</span>
            </div>
            {files.map(([name, detail]) => (
              <div key={name} className="grid grid-cols-[1fr_1.7fr_auto] items-center border-b border-[#d8dee4] px-3 py-2.5 text-[9px] last:border-0">
                <span className="font-medium text-[#0969da]">{name}</span>
                <span className="truncate text-[#59636d]">{detail}</span>
                <span className="text-[#8c959f]">today</span>
              </div>
            ))}
          </div>

          {!compact ? (
            <div className="mt-4 rounded-md border border-[#d0d7de] bg-white p-4">
              <div className="text-[12px] font-semibold">Lattices</div>
              <p className="mt-2 text-[10px] leading-relaxed text-[#59636d]">
                A macOS workspace manager for grouping, arranging, and navigating real application windows.
              </p>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function TerminalSurface({ compact = false }: { compact?: boolean }) {
  const lines = [
    ["➜", "lattices git:(codex/cross-app-tabs) bun run check"],
    ["", "✓ TypeScript typecheck"],
    ["", "✓ Swift app build"],
    ["➜", "lattices git:(codex/cross-app-tabs) lattices tabs list"],
    ["", "Research   tabs   2 windows   top-left"],
    ["", "Chrome     65433   lattices — GitHub"],
    ["", "iTerm2     65745   lattices — zsh"],
  ];

  return (
    <div className={`${compact ? "h-full min-h-[425px] p-5 pt-14" : "min-h-[492px] p-7 lg:p-9"} bg-[#17191c] font-mono`}>
      <div className="mx-auto max-w-[860px] overflow-hidden rounded-lg border border-black/50 bg-[#0b0d0f] shadow-[0_18px_45px_rgba(0,0,0,.38)]">
        <div className="flex h-9 items-center border-b border-black/60 bg-[#25282c] px-3">
          <div className="flex gap-1.5">
            <span className="h-2.5 w-2.5 rounded-full bg-[#ff5f57]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#febc2e]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#28c840]" />
          </div>
          <span className="mx-auto text-[9px] text-white/52">lattices — zsh — 132×34</span>
          <span className="w-[38px]" />
        </div>
        <div className="min-h-[365px] space-y-2.5 p-5 text-[10px] leading-relaxed lg:p-7 lg:text-[11px]">
          {lines.map(([sigil, text], index) => (
            <div key={`${text}-${index}`} className={text.startsWith("✓") ? "text-[#72c19e]" : "text-[#c6cbd0]"}>
              <span className={sigil === "➜" ? "text-[#63d4c3]" : "text-white/22"}>{sigil}</span>{" "}
              {text}
            </div>
          ))}
          <div className="flex items-center gap-1 text-white/70">
            <span className="text-[#63d4c3]">➜</span>
            <span className="text-[#b178d3]">lattices</span>
            <span className="text-[#e1b55c]">git:(codex/cross-app-tabs)</span>
            <span className="h-4 w-1.5 animate-pulse bg-white/75" />
          </div>
        </div>
      </div>
    </div>
  );
}

function WindowLabel({ app, title, icon: Icon }: { app: string; title: string; icon: typeof Globe2 }) {
  return (
    <div className="absolute inset-x-0 top-0 z-10 flex h-11 items-center border-b border-white/[0.07] bg-[#0b1014]/95 px-4 backdrop-blur">
      <Icon size={12} className="text-[#68e7d1]" />
      <span className="ml-2 font-mono text-[8px] uppercase tracking-[0.16em] text-white/42">{app}</span>
      <span className="mx-2 text-white/15">/</span>
      <span className="truncate text-[10px] text-white/72">{title}</span>
    </div>
  );
}

function OpenHint() {
  return (
    <span className="absolute bottom-4 right-4 flex items-center gap-1 rounded-full border border-white/[0.08] bg-black/45 px-2.5 py-1.5 font-mono text-[8px] uppercase tracking-[0.14em] text-white/0 backdrop-blur transition-colors group-hover:text-white/60">
      Open tab <ExternalLink size={9} />
    </span>
  );
}

function Principle({ number, title, children }: { number: string; title: string; children: React.ReactNode }) {
  return (
    <div className="px-5 py-6 first:pl-0 last:pr-0 md:px-7">
      <div className="font-mono text-[9px] uppercase tracking-[0.2em] text-studio-ink-faint">{number}</div>
      <h2 className="mt-3 text-[14px] font-medium text-studio-ink-strong">{title}</h2>
      <p className="mt-2 text-[12px] leading-[1.65] text-studio-ink-faint">{children}</p>
    </div>
  );
}
