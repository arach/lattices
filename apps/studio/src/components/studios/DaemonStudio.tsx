import type { StudioEntry } from "../../lib/studios";
import { DaemonConnection } from "../DaemonConnection";
import { DaemonRepl } from "./daemon/DaemonRepl";

interface DaemonStudioProps {
  entry: StudioEntry;
  exhibit?: string;
}

export function DaemonStudio({ entry }: DaemonStudioProps) {
  return (
    <main className="max-w-6xl px-6 py-8">
      <header>
        <p className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
          studio · daemon
        </p>
        <h1 className="mt-2 font-sans text-4xl font-medium tracking-tight text-studio-ink sm:text-5xl">
          {entry.title}
        </h1>
        <p className="mt-4 max-w-2xl text-[15px] leading-relaxed text-studio-ink-faint">
          A live REPL against the local Lattices daemon. Speak a turn, see the
          full stack — snapshot, reasoning, actions, daemon call — and
          optionally fire it for real.
        </p>
      </header>

      <section className="mt-10">
        <DaemonConnection />
      </section>

      <DaemonRepl />

      <footer className="mt-20 border-t border-studio-edge pt-5">
        <p className="font-mono text-[10px] uppercase tracking-[0.22em] text-studio-ink-faint">
          source · LatticesApi.swift · DaemonServer.swift · PhraseMatcher.swift
        </p>
      </footer>
    </main>
  );
}
