import { findStudioBySlug } from "../lib/studios";
import { CursorStudio } from "./studios/CursorStudio";
import { HandsoffStudio } from "./studios/HandsoffStudio";
import { IntentExplorer } from "./studios/IntentExplorer";
import { TilingStudio } from "./studios/TilingStudio";

interface StudioPageProps {
  slug: string;
  exhibit?: string;
}

export function StudioPage({ slug, exhibit }: StudioPageProps) {
  const entry = findStudioBySlug(slug);

  if (!entry) {
    return (
      <main className="px-8 py-12">
        <p className="font-mono text-[11px] uppercase tracking-[0.22em] text-studio-ink-faint">
          Studio not found
        </p>
        <p className="mt-3 text-sm">
          <a className="underline" href="/">
            Back home
          </a>
        </p>
      </main>
    );
  }

  if (slug === "tiling") return <TilingStudio entry={entry} exhibit={exhibit} />;
  if (slug === "intents") return <IntentExplorer entry={entry} />;
  if (slug === "handsoff") return <HandsoffStudio entry={entry} />;
  if (slug === "cursor") return <CursorStudio entry={entry} />;

  return (
    <main className="px-8 py-12">
      <p className="font-mono text-[11px] uppercase tracking-[0.22em] text-studio-ink-faint">
        {entry.title}
      </p>
      <p className="mt-3 text-sm text-studio-ink-faint">
        This studio is still being built.
      </p>
    </main>
  );
}
