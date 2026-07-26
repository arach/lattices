"use client";

import { ArrowRight, Command } from "lucide-react";
import type { StudioHudsonRenderContext } from "studio/app-shell";
import { useStudioRouter } from "studio/router";
import { DeckBuilderStudy } from "@/studio/studies/DeckBuilder";
import { CrossAppTabsStudy } from "@/studio/studies/CrossAppTabs";
import {
  HOME_HREF,
  pages,
  type Bucket,
  type LatticesPage,
  type Status,
  type Surface,
} from "@/studio/studioRegistry";

type RenderContext = StudioHudsonRenderContext<Bucket, Surface, Status>;

export function renderStudioPage({ pathname, page }: RenderContext) {
  if (pathname === HOME_HREF) return <HomePage />;
  if (page?.href === "/studio/studies/nexus") return <NexusStudy page={page} />;
  if (page?.href === "/studio/studies/deck-builder") return <DeckBuilderStudy page={page} />;
  if (page?.href === "/studio/studies/cross-app-tabs") return <CrossAppTabsStudy page={page} />;
  if (page) return <PlaceholderPage page={page} />;
  return <NotFoundPage />;
}

function HomePage() {
  const { Link } = useStudioRouter();
  const studies = pages.filter((p) => p.bucket === "studies");

  return (
    <main className="mx-auto max-w-5xl px-6 py-10 lg:px-8">
      <header className="border-b border-studio-rule pb-8">
        <div className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
          lattices / design studio
        </div>
        <h1 className="mt-4 max-w-[760px] text-[40px] font-medium leading-tight text-studio-ink-strong">
          Design the surfaces before SwiftUI gets touched.
        </h1>
        <p className="mt-5 max-w-[64ch] text-[15px] leading-[1.7] text-studio-ink">
          A studio for the Lattices macOS workspace manager. Each study explores
          one surface — overlays, HUD, command flows — as a self-contained mock
          so the look and interaction land before any Swift is written.
        </p>
      </header>

      <section className="py-8">
        <div className="flex items-center gap-2 font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
          <Command size={14} />
          Studies
        </div>
        <ul className="mt-4 divide-y divide-studio-rule border-y border-studio-rule">
          {studies.map((entry) => (
            <li key={entry.href}>
              <Link
                href={entry.href}
                className="group grid gap-3 py-4 transition-colors hover:bg-studio-chip-bg md:grid-cols-[140px_1fr_20px]"
              >
                <span className="font-mono text-[11px] uppercase tracking-[0.18em] text-studio-ink-faint">
                  {entry.surface}
                </span>
                <span>
                  <span className="block text-[15px] font-medium text-studio-ink-strong">
                    {entry.label}
                  </span>
                  <span className="mt-1 block text-[12.5px] leading-relaxed text-studio-ink-faint">
                    {entry.blurb}
                  </span>
                </span>
                <ArrowRight
                  size={15}
                  className="self-center text-studio-ink-faint transition-transform group-hover:translate-x-1"
                />
              </Link>
            </li>
          ))}
        </ul>
      </section>
    </main>
  );
}

function NexusStudy({ page }: { page: LatticesPage }) {
  return (
    <main className="w-full px-6 py-10 lg:px-7">
      <PageHeader page={page} />
      <section className="py-8">
        <div className="overflow-hidden border border-studio-rule">
          <iframe
            src="/nexus/board.html"
            title="Nexus — command bar states"
            style={{
              width: "100%",
              height: 1680,
              border: 0,
              display: "block",
              background: "#0b0e12",
            }}
          />
        </div>
        <p className="mt-4 font-mono text-[11px] leading-relaxed text-studio-ink-faint">
          Static mock — Langley theme (Geist Mono, electric-cyan signal). Source
          of truth for the look while the SwiftUI <code>NexusView</code> is built.
        </p>
      </section>
    </main>
  );
}

function PlaceholderPage({ page }: { page: LatticesPage }) {
  return (
    <main className="w-full px-6 py-10 lg:px-7">
      <PageHeader page={page} />
      <section className="py-8 font-mono text-[13px] text-studio-ink-faint">
        {page.blurb ?? "Nothing here yet."}
      </section>
    </main>
  );
}

function PageHeader({ page }: { page: LatticesPage }) {
  return (
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
  );
}

function NotFoundPage() {
  const { Link } = useStudioRouter();
  return (
    <main className="mx-auto max-w-3xl px-6 py-16 lg:px-8">
      <h1 className="text-[34px] font-medium text-studio-ink-strong">
        Page not found.
      </h1>
      <Link
        href={HOME_HREF}
        className="mt-6 inline-flex items-center gap-2 font-mono text-[10px] uppercase tracking-[0.18em] text-studio-ink-faint hover:text-studio-ink"
      >
        Back to Studio
        <ArrowRight size={13} />
      </Link>
    </main>
  );
}
