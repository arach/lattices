import { useEffect, useState } from "react";
import { LatticesLogo } from "./LandingPage";
import { ThemeToggle } from "./ThemeToggle";

const downloadUrl = "/blink/download";
const sourceUrl = "https://github.com/arach/lattices/tree/main/products/blink";

const deskSteps = [
  {
    label: "Capture",
    detail: "Hyper+N · glass panel",
    status: "open",
  },
  {
    label: "Place",
    detail: "Slot 6 · focus style",
    status: "parked",
  },
  {
    label: "Write",
    detail: "standup.md · local file",
    status: "saved",
  },
  {
    label: "Recall",
    detail: "Same frame · same note",
    status: "restored",
  },
];

export default function BlinkPage() {
  const [theme, setTheme] = useState<"light" | "dark">(() => {
    if (typeof document === "undefined") return "dark";
    return (document.documentElement.getAttribute("data-theme") as "light" | "dark") || "dark";
  });

  useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem("theme", theme);
  }, [theme]);

  return (
    <div className="action-page blink-page">
      <nav className="nav action-nav" aria-label="Blink navigation">
        <div className="nav-inner">
          <a href="/" className="nav-brand action-family-lockup" aria-label="Lattices home">
            <LatticesLogo size={20} />
            <span className="nav-name">lattices</span>
            <span className="action-lockup-divider" aria-hidden="true">/</span>
            <span className="action-lockup-product">blink</span>
          </a>
          <div className="nav-links">
            <a href="/" className="nav-link action-nav-optional">Lattices</a>
            <a href="/blink/agents.md" data-router="reload" className="nav-link action-nav-optional">For agents</a>
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
        <section className="action-hero" aria-labelledby="blink-title">
          <div className="action-hero-copy">
            <div className="action-product-id">
              <img src="/blink/blink-mark.svg" alt="" />
              <span>
                <strong>Blink</strong>
                <small>A Lattices product</small>
              </span>
            </div>
            <h1 id="blink-title">The note is the window.</h1>
            <p className="action-hero-lead">
              Blink is spatial notes from Lattices. Summon a glass panel with a
              keystroke, place it on the desktop, and it stays there — plain
              Markdown you own, open to your agents.
            </p>
            <div className="action-hero-actions">
              <a href={downloadUrl} data-router="reload" className="hero-primary-cta action-primary-cta">
                Download Blink
                <span aria-hidden="true">↓</span>
              </a>
              <a href="/blink/agents.md" data-router="reload" className="hero-secondary-cta">
                Read the agent guide
              </a>
            </div>
            <p className="action-platform-note">macOS 14+ · Apple silicon · local first</p>
          </div>

          <div className="action-receipt" aria-label="Example Blink desk">
            <div className="action-receipt-head">
              <span>blink.desk</span>
              <span className="action-live-state"><i aria-hidden="true" /> placed</span>
            </div>
            <ol className="action-run-list">
              {deskSteps.map((step, index) => (
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
              <span>~/Library/Application Support/Blink/Notes</span>
              <span>one file · one panel</span>
            </div>
          </div>
        </section>

        <section className="action-purpose" aria-labelledby="blink-purpose-title">
          <div className="action-section-heading">
            <p className="action-kicker">One family, focused products</p>
            <h2 id="blink-purpose-title">The workspace and the note belong together.</h2>
          </div>
          <div className="action-product-boundary">
            <article>
              <span className="action-boundary-label">Lattices</span>
              <h3>The workspace</h3>
              <p>Windows, sessions, layouts, and a local API for keeping the whole Mac organized and programmable.</p>
              <a href="/">Explore Lattices &rarr;</a>
            </article>
            <div className="action-boundary-bridge" aria-label="Shared product model">
              <span>capture</span>
              <i aria-hidden="true" />
              <span>place</span>
              <i aria-hidden="true" />
              <span>recall</span>
            </div>
            <article>
              <span className="action-boundary-label action-boundary-label-product">Blink</span>
              <h3>The spatial note</h3>
              <p>Floating panels, local Markdown, and a CLI that writes the same files the desk renders.</p>
              <a href={downloadUrl} data-router="reload">Download Blink &rarr;</a>
            </article>
          </div>
          <p className="action-boundary-note">
            Use Blink on its own, or pair it with Lattices when the whole workspace needs to stay organized. Action covers inspectable computer use.
          </p>
        </section>

        <section className="action-proof" aria-labelledby="blink-proof-title">
          <div className="action-section-heading">
            <p className="action-kicker">Files are truth</p>
            <h2 id="blink-proof-title">Agents write the same notes you see.</h2>
            <p>
              One note is one Markdown file with YAML frontmatter. The app, the CLI,
              and external writers converge on the same folder. Spatial memory stays
              on the device.
            </p>
          </div>
          <div className="action-proof-lines">
            <article>
              <span>01</span>
              <h3>Capture anywhere</h3>
              <p>Hyper+N drops a glass panel. No library window. The desktop is the workspace.</p>
            </article>
            <article>
              <span>02</span>
              <h3>Place and remember</h3>
              <p>Frames restore exactly. Portable slot intent travels in frontmatter; the device keeps the pixel frame.</p>
            </article>
            <article>
              <span>03</span>
              <h3>Open to agents</h3>
              <p>Prefer the <code>blink</code> CLI. Atomic writes, live reconcile, no side database.</p>
            </article>
          </div>
        </section>

        <section className="action-final-cta" aria-labelledby="blink-final-title">
          <div>
            <p className="action-kicker">Blink for macOS</p>
            <h2 id="blink-final-title">Put the working set on the desk.</h2>
          </div>
          <div className="action-final-links">
            <a href={downloadUrl} data-router="reload" className="hero-primary-cta action-primary-cta">Download Blink</a>
            <a href={sourceUrl} className="hero-secondary-cta">View source</a>
          </div>
        </section>
      </main>

      <footer className="action-footer">
        <div className="action-footer-inner">
          <span>Blink is a spatial-notes product from Lattices.</span>
          <div>
            <a href="/">Lattices</a>
            <a href="/action">Action</a>
            <a href="/blink/llms.txt" data-router="reload">Blink docs</a>
            <a href={sourceUrl}>GitHub</a>
          </div>
        </div>
      </footer>
    </div>
  );
}
