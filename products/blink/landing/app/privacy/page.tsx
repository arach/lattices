import type { Metadata } from "next"
import { BlinkMark } from "@/components/homepage/BlinkMark"

export const metadata: Metadata = {
  title: "Privacy — Blink",
  description: "How Blink handles notes, device data, local-network access, and website analytics.",
  alternates: { canonical: "/privacy/" },
}

const appFacts = [
  "No Blink account is required.",
  "The app contains no advertising or tracking SDKs.",
  "Blink does not send your notes or workspace metadata to Arach or another cloud service.",
  "The mobile companion is read-only in this release.",
]

export default function PrivacyPage() {
  return (
    <div className="min-h-screen">
      <header className="border-b border-linex bg-[rgba(var(--bg-rgb),0.88)] backdrop-blur-md">
        <div className="mx-auto flex h-12 max-w-3xl items-center justify-between px-4 md:px-6">
          <a
            href="/"
            className="font-display flex items-center gap-2 text-[17px] font-semibold leading-none tracking-[-0.015em] text-[var(--text)] transition-colors hover:text-acc"
          >
            <BlinkMark className="h-4 w-4 text-acc" />
            <span>blink</span>
          </a>
          <a
            href="https://github.com/arach/blink"
            className="rounded-[4px] py-1 text-[11px] text-dimx transition-colors hover:text-acc"
          >
            source ↗
          </a>
        </div>
      </header>

      <main className="mx-auto max-w-3xl px-4 pb-24 pt-14 md:px-6 md:pt-20">
        <div className="max-w-2xl">
          <p className="label-x">Privacy policy</p>
          <h1 className="font-display mt-4 text-balance text-5xl font-semibold leading-[0.95] tracking-[-0.025em] text-[var(--text)] md:text-6xl">
            Your notes stay yours.
          </h1>
          <p className="mt-6 max-w-[66ch] text-[15px] leading-7 text-dimx">
            Blink is local-first software. The Mac app keeps notes as Markdown files you control,
            and the iPhone and iPad companion receives a replaceable, read-only copy directly
            from your Mac.
          </p>
          <p className="mt-4 text-[11px] text-faintx">Effective August 4, 2026</p>
        </div>

        <div className="mt-14 divide-y divide-[var(--line)] border-y border-linex">
          <section className="grid gap-5 py-9 md:grid-cols-[10rem_1fr] md:gap-8">
            <h2 className="text-[12px] font-bold text-[var(--text)]">The app</h2>
            <ul className="space-y-3 text-[14px] leading-6 text-dimx">
              {appFacts.map((fact) => (
                <li key={fact} className="flex gap-3">
                  <span className="mt-[0.65rem] h-1.5 w-1.5 shrink-0 bg-[var(--acc)]" aria-hidden />
                  <span>{fact}</span>
                </li>
              ))}
            </ul>
          </section>

          <section className="grid gap-5 py-9 md:grid-cols-[10rem_1fr] md:gap-8">
            <h2 className="text-[12px] font-bold text-[var(--text)]">Local sync</h2>
            <div className="space-y-4 text-[14px] leading-6 text-dimx">
              <p>
                Blink asks for local-network access so the mobile companion can discover and pair
                with Blink on your Mac. Note snapshots travel over the local network inside an
                end-to-end encrypted peer session.
              </p>
              <p>
                The mobile copy is stored in the app&apos;s private container and is excluded from
                device backups. The device&apos;s pairing identity is kept in non-synchronizing
                Keychain storage.
              </p>
            </div>
          </section>

          <section className="grid gap-5 py-9 md:grid-cols-[10rem_1fr] md:gap-8">
            <h2 className="text-[12px] font-bold text-[var(--text)]">Your controls</h2>
            <div className="space-y-4 text-[14px] leading-6 text-dimx">
              <p>
                Use <strong className="font-semibold text-[var(--text)]">Remove Offline Notes</strong>{" "}
                in the mobile app&apos;s Settings to delete the cached note copy. Removing the app
                deletes its remaining on-device data. Your original Markdown files remain on your
                Mac until you change or delete them there.
              </p>
            </div>
          </section>

          <section className="grid gap-5 py-9 md:grid-cols-[10rem_1fr] md:gap-8">
            <h2 className="text-[12px] font-bold text-[var(--text)]">This website</h2>
            <div className="space-y-4 text-[14px] leading-6 text-dimx">
              <p>
                blink.arach.dev uses Google Analytics to understand aggregate site visits. Google
                may receive browser and device details, referring pages, page interactions, and an
                approximate location derived from your IP address. This website analytics is
                separate from the Blink apps; the apps do not contain Google Analytics.
              </p>
              <p>
                Learn more in Google&apos;s{" "}
                <a
                  href="https://policies.google.com/privacy"
                  className="text-acc underline decoration-[var(--line-2)] underline-offset-4 hover:decoration-[var(--acc)]"
                >
                  privacy policy
                </a>
                .
              </p>
            </div>
          </section>

          <section className="grid gap-5 py-9 md:grid-cols-[10rem_1fr] md:gap-8">
            <h2 className="text-[12px] font-bold text-[var(--text)]">Contact</h2>
            <p className="text-[14px] leading-6 text-dimx">
              Questions about Blink privacy can be sent to{" "}
              <a
                href="mailto:arach@tchoupani.com"
                className="text-acc underline decoration-[var(--line-2)] underline-offset-4 hover:decoration-[var(--acc)]"
              >
                arach@tchoupani.com
              </a>
              .
            </p>
          </section>
        </div>
      </main>

      <footer className="border-t border-linex py-8">
        <div className="mx-auto flex max-w-3xl flex-wrap items-center justify-between gap-3 px-4 text-[10px] text-[var(--ghost)] md:px-6">
          <span>Blink · local-first spatial notes</span>
          <a href="/" className="transition-colors hover:text-acc">
            blink.arach.dev
          </a>
        </div>
      </footer>
    </div>
  )
}
