import type { LatticesPage } from "@/studio/studioRegistry";

export function ProductFamilyStudy({ page }: { page: LatticesPage }) {
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
        <div className="overflow-hidden border border-studio-rule">
          <iframe
            src="/product-family/board.html"
            title="Product family homepage insertion study"
            style={{
              width: "100%",
              height: 10800,
              border: 0,
              display: "block",
              background: "#111113",
            }}
          />
        </div>
        <p className="mt-4 font-mono text-[11px] leading-relaxed text-studio-ink-faint">
          Static homepage study — a progressive capability narrative, with the
          earlier product-family surfaces retained for comparison. No site code touched.
        </p>
      </section>
    </main>
  );
}
