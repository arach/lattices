"use client";

import { ArrowRight, Command } from "lucide-react";
import type { StudioHudsonRenderContext } from "studio/app-shell";
import { useStudioRouter } from "studio/router";
import { AppStudy } from "@/studio/studies/AppStudy";
import { ScenariosStudy } from "@/studio/studies/ScenariosStudy";
import { StepTelemetryStudy } from "@/studio/studies/StepTelemetryStudy";
import { TokensStudy } from "@/studio/studies/TokensStudy";
import {
  HOME_HREF,
  pages,
  type ActionPage,
  type Bucket,
  type Status,
  type Surface,
} from "@/studio/studioRegistry";

type RenderContext = StudioHudsonRenderContext<Bucket, Surface, Status>;

export function renderStudioPage({ pathname, page }: RenderContext) {
  if (pathname === HOME_HREF) return <HomePage />;
  if (page?.href === "/studio/foundations/tokens") return <TokensStudy page={page} />;
  if (page?.href === "/studio/studies/window") return <AppStudy page={page} />;
  if (page?.href === "/studio/studies/scenarios") return <ScenariosStudy page={page} />;
  if (page?.href === "/studio/studies/step-telemetry") return <StepTelemetryStudy page={page} />;
  if (page) return <PlaceholderPage page={page} />;
  return <NotFoundPage />;
}

function HomePage() {
  const { Link } = useStudioRouter();
  const entries = pages.filter((p) => p.href !== HOME_HREF);

  return (
    <main className="mx-auto max-w-5xl px-6 py-10 lg:px-8">
      <header className="border-b border-studio-rule pb-8">
        <div className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
          action / design studio
        </div>
        <h1 className="mt-4 max-w-[760px] text-[40px] font-medium leading-tight text-studio-ink-strong">
          Design the surfaces before SwiftUI gets touched.
        </h1>
        <p className="mt-5 max-w-[66ch] text-[15px] leading-[1.7] text-studio-ink">
          Action is a computer-use module for macOS: an agent drives the Mac, and the app is the
          supervision surface around that. Each study takes one surface, draws it in Action&apos;s
          real palette at the real content width, and names the files it argues about.
        </p>
        <p className="mt-4 max-w-[66ch] text-[14px] leading-[1.7] text-studio-ink-faint">
          A study marked <span className="font-mono text-[12.5px]">SHIPPED</span> draws only what
          the app actually records. Anything that needs data the runtime does not write yet is a
          separate study marked <span className="font-mono text-[12.5px]">CONCEPT</span> — otherwise
          the studio stops describing the app and starts wishing at it.
        </p>
      </header>

      <section className="py-8">
        <div className="flex items-center gap-2 font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
          <Command size={14} />
          Studies
        </div>
        <ul className="mt-4 divide-y divide-studio-rule border-y border-studio-rule">
          {entries.map((entry) => (
            <li key={entry.href}>
              <Link
                href={entry.href}
                className="group grid gap-3 py-5 transition-colors hover:bg-studio-chip-bg md:grid-cols-[150px_1fr_20px]"
              >
                <span className="font-mono text-[11px] uppercase tracking-[0.18em] text-studio-ink-faint">
                  {entry.status}
                </span>
                <span>
                  <span className="block text-[15px] font-medium text-studio-ink-strong">
                    {entry.label}
                  </span>
                  <span className="mt-1 block max-w-[62ch] text-[13.5px] leading-[1.65] text-studio-ink">
                    {entry.blurb}
                  </span>
                </span>
                <ArrowRight
                  size={16}
                  className="mt-1 text-studio-ink-faint transition-transform group-hover:translate-x-1"
                />
              </Link>
            </li>
          ))}
        </ul>
      </section>

      <section className="pb-10">
        <div className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
          Elsewhere
        </div>
        <p className="mt-3 max-w-[66ch] text-[14px] leading-[1.7] text-studio-ink">
          The component previews live in the{" "}
          <span className="font-mono text-[12.5px] text-studio-ink-strong">
            Action — Design System
          </span>{" "}
          project in Claude Design, built from{" "}
          <span className="font-mono text-[12.5px] text-studio-ink-strong">design/kit/build.ts</span>{" "}
          and the same tokens this studio reads. Rebuild them with{" "}
          <span className="font-mono text-[12.5px] text-studio-ink-strong">bun design/kit/build.ts</span>.
        </p>
      </section>
    </main>
  );
}

function PlaceholderPage({ page }: { page: ActionPage }) {
  return (
    <main className="mx-auto max-w-3xl px-6 py-16 lg:px-8">
      <div className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
        action / {page.bucket}
      </div>
      <h1 className="mt-4 text-[32px] font-medium text-studio-ink-strong">{page.label}</h1>
      <p className="mt-5 max-w-[62ch] text-[15px] leading-[1.7] text-studio-ink">{page.blurb}</p>
      <p className="mt-8 font-mono text-[12px] text-studio-ink-faint">Not drawn yet.</p>
    </main>
  );
}

function NotFoundPage() {
  return (
    <main className="mx-auto max-w-3xl px-6 py-16 lg:px-8">
      <h1 className="text-[32px] font-medium text-studio-ink-strong">No such study</h1>
      <p className="mt-4 text-[15px] text-studio-ink">
        Check the registry in <span className="font-mono text-[13px]">src/studio/studioRegistry.ts</span>.
      </p>
    </main>
  );
}
