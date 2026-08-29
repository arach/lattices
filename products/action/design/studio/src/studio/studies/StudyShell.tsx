"use client";

import type { ReactNode } from "react";
import type { ActionPage } from "@/studio/studioRegistry";

/**
 * The page furniture every study shares: title, blurb, the files it argues
 * about, and the two prose primitives. Studies differ in what they draw, not
 * in how they are framed.
 */

export function StudyShell({
  page,
  children,
  /** The window study draws a 1600px app; 5xl would scale it to a thumbnail. */
  wide = false,
}: {
  page: ActionPage;
  children: ReactNode;
  wide?: boolean;
}) {
  return (
    <main
      className={
        (wide ? "max-w-[1500px]" : "max-w-5xl") +
        " mx-auto px-6 py-10 lg:px-8 [&_section]:mt-14 [&_h2]:text-[19px] [&_h2]:font-medium [&_h2]:text-studio-ink-strong [&_h2]:mb-3"
      }
    >
      <header className="border-b border-studio-rule pb-8">
        <div className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
          action / {page.bucket}
        </div>
        <h1 className="mt-4 max-w-[760px] text-[34px] font-medium leading-tight text-studio-ink-strong">
          {page.label}
        </h1>
        {page.blurb && (
          <p className="mt-5 max-w-[68ch] text-[15px] leading-[1.7] text-studio-ink">
            {page.blurb}
          </p>
        )}
        {page.source && page.source.length > 0 && (
          <ul className="mt-6 flex flex-wrap gap-2">
            {page.source.map((file) => (
              <li
                key={file}
                className="rounded border border-studio-chip-border bg-studio-chip-bg px-2 py-1 font-mono text-[10px] text-studio-ink-faint"
              >
                {file}
              </li>
            ))}
          </ul>
        )}
      </header>
      {children}
    </main>
  );
}

export function Prose({ children }: { children: ReactNode }) {
  return (
    <p className="mb-5 max-w-[68ch] text-[14px] leading-[1.75] text-studio-ink">{children}</p>
  );
}

export function Note({ title, children }: { title: string; children: ReactNode }) {
  return (
    <aside className="mt-14 border-t border-studio-rule pt-6">
      <div className="font-mono text-[10px] uppercase tracking-eyebrow text-studio-ink-faint">
        {title}
      </div>
      <p className="mt-3 max-w-[68ch] text-[14px] leading-[1.75] text-studio-ink [&_code]:font-mono [&_code]:text-[12.5px] [&_code]:text-studio-ink-strong">
        {children}
      </p>
    </aside>
  );
}
