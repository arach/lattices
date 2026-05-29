import type { ReactNode } from "react";
import { ENG_DOC_GROUPS } from "../lib/eng-docs";
import { STUDIO_ENTRIES } from "../lib/studios";
import { StatusPill } from "./StatusPill";

interface StudioChromeProps {
  pathname: string;
  children: ReactNode;
}

export function StudioChrome({ pathname, children }: StudioChromeProps) {
  return (
    <div className="flex min-h-screen bg-studio-canvas text-studio-ink">
      <aside className="hidden w-64 shrink-0 border-r border-studio-edge px-5 py-8 md:block">
        <a
          href="/"
          className="block font-mono text-[11px] uppercase tracking-[0.22em] text-studio-ink-faint hover:text-studio-ink"
        >
          lattices · studio
        </a>
        <nav className="mt-8 space-y-7">
          <section>
            <h2 className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
              Studios
            </h2>
            <ul className="mt-3 space-y-1">
              {STUDIO_ENTRIES.map((entry) => {
                const href = `/studio/${entry.slug}`;
                const active = pathname === href;
                return (
                  <li key={entry.slug}>
                    <a
                      href={href}
                      className={[
                        "flex items-center justify-between gap-2 rounded-sm px-2 py-1 text-sm transition-colors",
                        active
                          ? "bg-[color:var(--studio-edge)] text-studio-ink"
                          : "text-studio-ink-faint hover:text-studio-ink",
                      ].join(" ")}
                    >
                      <span className="truncate">{entry.title}</span>
                      <span
                        className="font-mono text-[9px] uppercase tracking-[0.18em]"
                        style={{ color: "var(--scout-accent)" }}
                      >
                        {entry.status === "live" ? "LIVE" : "DRAFT"}
                      </span>
                    </a>
                  </li>
                );
              })}
            </ul>
          </section>
          {ENG_DOC_GROUPS.filter((g) => g.key === "proposals").map((group) => (
            <section key={group.key}>
              <h2 className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
                {group.label}
              </h2>
              <ul className="mt-3 space-y-1">
                {group.entries.map((entry) => {
                  const href = `/eng/${entry.slug}`;
                  const active = pathname === href;
                  return (
                    <li key={entry.slug}>
                      <a
                        href={href}
                        className={[
                          "flex items-center justify-between gap-2 rounded-sm px-2 py-1 text-sm transition-colors",
                          active
                            ? "bg-[color:var(--studio-edge)] text-studio-ink"
                            : "text-studio-ink-faint hover:text-studio-ink",
                        ].join(" ")}
                      >
                        <span className="truncate">
                          {entry.proposalId ? (
                            <span className="mr-1.5 font-mono text-[10px] text-studio-ink-faint">
                              {entry.proposalId}
                            </span>
                          ) : null}
                          {entry.title}
                        </span>
                        {entry.status ? (
                          <StatusPill status={entry.status} variant="text" />
                        ) : null}
                      </a>
                    </li>
                  );
                })}
              </ul>
            </section>
          ))}
        </nav>
      </aside>
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  );
}
