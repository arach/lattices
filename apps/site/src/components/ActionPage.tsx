import { useEffect, useState } from "react";
import { LatticesLogo } from "./LandingPage";
import { ThemeToggle } from "./ThemeToggle";

const downloadUrl = "/action/download";
const sourceUrl = "https://github.com/arach/lattices/tree/main/products/action";

const runSteps = [
  {
    label: "Observe",
    detail: "Calculator · AX + screenshot",
    status: "surface ready",
  },
  {
    label: "Act",
    detail: "Press equals · semantic target",
    status: "executed",
  },
  {
    label: "Record",
    detail: "Video + trace · local artifacts",
    status: "finished",
  },
  {
    label: "Verify",
    detail: "Display value · 42",
    status: "confirmed",
  },
];

export default function ActionPage() {
  const [theme, setTheme] = useState<"light" | "dark">(() => {
    if (typeof document === "undefined") return "dark";
    return (document.documentElement.getAttribute("data-theme") as "light" | "dark") || "dark";
  });

  useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem("theme", theme);
  }, [theme]);

  return (
    <div className="action-page">
      <nav className="nav action-nav" aria-label="Action navigation">
        <div className="nav-inner">
          <a href="/" className="nav-brand action-family-lockup" aria-label="Lattices home">
            <LatticesLogo size={20} />
            <span className="nav-name">lattices</span>
            <span className="action-lockup-divider" aria-hidden="true">/</span>
            <span className="action-lockup-product">action</span>
          </a>
          <div className="nav-links">
            <a href="/" className="nav-link action-nav-optional">Lattices</a>
            <a href="/action/agents/" data-router="reload" className="nav-link action-nav-optional">For agents</a>
            <a href={sourceUrl} className="nav-link">Source</a>
            <ThemeToggle
              theme={theme}
              onToggle={() => setTheme(theme === "dark" ? "light" : "dark")}
            />
            <a href={downloadUrl} data-router="reload" className="action-nav-download">Download</a>
          </div>
        </div>
      </nav>

      <main className="action-shell">
        <section className="action-hero" aria-labelledby="action-title">
          <div className="action-hero-copy">
            <div className="action-product-id">
              <img src="/action/action-mark.svg" alt="" />
              <span>
                <strong>Action</strong>
                <small>A Lattices product</small>
              </span>
            </div>
            <h1 id="action-title">Computer use you can inspect.</h1>
            <p className="action-hero-lead">
              Action is the focused computer-use product from Lattices. It gives agents a native
              macOS path to observe apps, act on explicit targets, record the run, and verify what changed.
            </p>
            <div className="action-hero-actions">
              <a href={downloadUrl} data-router="reload" className="hero-primary-cta action-primary-cta">
                Download Action
                <span aria-hidden="true">↓</span>
              </a>
              <a href="/action/agents/" data-router="reload" className="hero-secondary-cta">
                Read the agent guide
              </a>
            </div>
            <p className="action-platform-note">macOS 14+ · Apple silicon · local first</p>
          </div>

          <div className="action-receipt" aria-label="Example Action run receipt">
            <div className="action-receipt-head">
              <span>action.run</span>
              <span className="action-live-state"><i aria-hidden="true" /> completed</span>
            </div>
            <ol className="action-run-list">
              {runSteps.map((step, index) => (
                <li key={step.label}>
                  <span className="action-run-index">{String(index + 1).padStart(2, "0")}</span>
                  <span className="action-run-copy">
                    <strong>{step.label}</strong>
                    <small>{step.detail}</small>
                  </span>
                  <span className="action-run-status">{step.status}</span>
                </li>
              ))}
            </ol>
            <div className="action-receipt-foot">
              <span>run_8f24</span>
              <span>4 artifacts · 1 receipt</span>
            </div>
          </div>
        </section>

        <section className="action-purpose" aria-labelledby="action-purpose-title">
          <div className="action-section-heading">
            <p className="action-kicker">One family, two focused products</p>
            <h2 id="action-purpose-title">The workspace and the run belong together.</h2>
          </div>
          <div className="action-product-boundary">
            <article>
              <span className="action-boundary-label">Lattices</span>
              <h3>The workspace</h3>
              <p>Windows, sessions, layouts, and a local API for keeping the whole Mac organized and programmable.</p>
              <a href="/">Explore Lattices &rarr;</a>
            </article>
            <div className="action-boundary-bridge" aria-label="Shared product model">
              <span>observe</span>
              <i aria-hidden="true" />
              <span>act</span>
              <i aria-hidden="true" />
              <span>verify</span>
            </div>
            <article>
              <span className="action-boundary-label action-boundary-label-product">Action</span>
              <h3>The computer-use run</h3>
              <p>Target resolution, on-device actions, capture, trace, and review for one inspectable piece of work.</p>
              <a href={downloadUrl} data-router="reload">Download Action &rarr;</a>
            </article>
          </div>
          <p className="action-boundary-note">
            Use Action on its own, or pair it with Lattices when the whole workspace needs to stay organized and programmable.
          </p>
        </section>

        <section className="action-proof" aria-labelledby="action-proof-title">
          <div className="action-section-heading">
            <p className="action-kicker">Native by design</p>
            <h2 id="action-proof-title">Every action leaves evidence.</h2>
            <p>
              Action keeps computer use close to the system surfaces it controls and makes completion visible in artifacts, not just an optimistic API reply.
            </p>
          </div>
          <div className="action-proof-lines">
            <article>
              <span>01</span>
              <h3>Resolve before acting</h3>
              <p>Prefer Accessibility, DOM, and semantic evidence before coordinate fallback.</p>
            </article>
            <article>
              <span>02</span>
              <h3>Run on the Mac</h3>
              <p>AppKit lifecycle, ScreenCaptureKit, and explicit macOS permission boundaries.</p>
            </article>
            <article>
              <span>03</span>
              <h3>Keep the receipt</h3>
              <p>Video, screenshots, traces, and finished markers stay attached to the run.</p>
            </article>
          </div>
        </section>

        <section className="action-final-cta" aria-labelledby="action-final-title">
          <div>
            <p className="action-kicker">Action for macOS</p>
            <h2 id="action-final-title">Give the agent a computer-use path you can review.</h2>
          </div>
          <div className="action-final-links">
            <a href={downloadUrl} data-router="reload" className="hero-primary-cta action-primary-cta">Download Action</a>
            <a href={sourceUrl} className="hero-secondary-cta">View source</a>
          </div>
        </section>
      </main>

      <footer className="action-footer">
        <div className="action-footer-inner">
          <span>Action is a focused computer-use product from Lattices.</span>
          <div>
            <a href="/">Lattices</a>
            <a href="/action/llms.txt" data-router="reload">Action docs</a>
            <a href={sourceUrl}>GitHub</a>
          </div>
        </div>
      </footer>
    </div>
  );
}
