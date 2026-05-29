import { ENG_DOC_GROUPS } from "../lib/eng-docs";
import { STUDIO_ENTRIES } from "../lib/studios";
import { StatusPill } from "./StatusPill";

const PLANS = ENG_DOC_GROUPS.find((g) => g.key === "proposals");

export function HomePage() {
  return (
    <main className="max-w-5xl px-6 pt-10 pb-16">
      <header className="max-w-2xl">
        <p className="font-mono text-[11px] uppercase tracking-[0.22em] text-studio-ink-faint">
          lattices · studio
        </p>
        <h1 className="mt-4 font-sans text-4xl font-medium leading-tight tracking-tight text-studio-ink sm:text-5xl">
          A working surface for{" "}
          <span style={{ color: "var(--scout-accent)" }}>lattices</span>.
        </h1>
        <p className="mt-5 max-w-xl text-[15px] leading-relaxed text-studio-ink-faint">
          Lattices is a macOS workspace manager — tmux sessions, tiled windows,
          voice intents. This is where the moving parts get pulled out,
          rearranged on a bench, and shown working.
        </p>
      </header>

      <section className="mt-12">
        <div className="flex items-baseline justify-between border-b border-studio-edge pb-3">
          <h2 className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
            Studios
          </h2>
          <span className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
            interactive
          </span>
        </div>
        <div className="mt-5 grid gap-4 sm:grid-cols-2">
          {STUDIO_ENTRIES.map((entry) => (
            <a
              key={entry.slug}
              href={`/studio/${entry.slug}`}
              className="group relative flex flex-col justify-between border border-studio-edge bg-[color:var(--studio-canvas)] p-6 transition-colors hover:border-studio-ink-faint sm:p-7"
            >
              <div className="flex items-start justify-between gap-4">
                <p className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
                  {entry.slug.replace(/-/g, " ")}
                </p>
                <span
                  className="font-mono text-[9px] uppercase tracking-[0.18em]"
                  style={{ color: "var(--scout-accent)" }}
                >
                  {entry.status === "live" ? "LIVE" : "DRAFT"}
                </span>
              </div>
              <div className="mt-10">
                <h3 className="font-sans text-2xl font-medium text-studio-ink">
                  {entry.title}
                </h3>
                <p className="mt-2 text-sm text-studio-ink-faint">
                  {entry.caption}
                </p>
                <p className="mt-5 font-mono text-[11px] uppercase tracking-[0.18em] text-studio-ink-faint transition-colors group-hover:text-studio-ink">
                  open studio →
                </p>
              </div>
            </a>
          ))}
        </div>
      </section>

      {PLANS ? (
        <section className="mt-14">
          <div className="flex items-baseline justify-between border-b border-studio-edge pb-3">
            <h2 className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
              Plans
            </h2>
            <span className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
              {String(PLANS.entries.length).padStart(2, "0")}
            </span>
          </div>
          <ul className="mt-5 grid gap-px border border-studio-edge bg-[color:var(--studio-edge)] sm:grid-cols-2">
            {PLANS.entries.map((entry) => (
              <li key={entry.slug} className="bg-studio-canvas">
                <a
                  href={`/eng/${entry.slug}`}
                  className="flex h-full flex-col justify-between gap-3 p-4 transition-colors hover:bg-[color:var(--studio-edge)]"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      {entry.proposalId ? (
                        <p className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
                          {entry.proposalId}
                        </p>
                      ) : null}
                      <p className="mt-1 font-sans text-[15px] leading-snug text-studio-ink">
                        {entry.title}
                      </p>
                    </div>
                    {entry.status ? (
                      <StatusPill status={entry.status} variant="text" />
                    ) : null}
                  </div>
                </a>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </main>
  );
}
