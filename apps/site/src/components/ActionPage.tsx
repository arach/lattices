import { useEffect, useState } from "react";
import actionHeroArt from "../../../../products/action/docs/assets/brand/landing-hero.webp";
import actionTraceField from "../../../../products/action/docs/assets/brand/landing-trace-field.webp";
import actionProductFilm from "../../../../products/action/docs/assets/action-record-the-work.mp4";
import actionProductFilmCaptions from "../../../../products/action/docs/assets/action-record-the-work.vtt";
import actionProductFilmPoster from "../../../../products/action/docs/assets/action-record-the-work-poster.jpg";
import { ActionArchitectureDiagram } from "./ActionArchitectureDiagram";
import { LatticesLogo } from "./LandingPage";
import { ThemeToggle } from "./ThemeToggle";

const downloadUrl = "/action/download";
const sourceUrl = "https://github.com/arach/lattices/tree/main/products/action";

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
            <a href="/docs/agents" className="nav-link action-nav-optional">For agents</a>
            <a href={sourceUrl} className="nav-link action-nav-source">Source</a>
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
          <div className="action-hero-art" aria-hidden="true">
            <img src={actionHeroArt} alt="" />
          </div>
          <div className="action-hero-inner">
            <div className="action-hero-copy">
              <p className="action-kicker action-hero-kicker">A Lattices product · native macOS automation</p>
              <h1 id="action-title">Action is a unified API for computer use.</h1>
              <p className="action-hero-lead">
                Record and share macOS runs with video, screenshots, accessibility context, and traces.
              </p>
              <div className="action-hero-actions">
                <a href={downloadUrl} data-router="reload" className="hero-primary-cta action-primary-cta">
                  Download for macOS
                  <span aria-hidden="true">↓</span>
                </a>
                <a href="/docs/agents" className="hero-secondary-cta action-secondary-cta">
                  Install for agents
                </a>
              </div>
              <p className="action-agent-entry">
                Reading this as an agent? <a href="/docs/agents">Start here</a>
                <span aria-hidden="true"> — </span>capabilities, connection, and which browser to drive.
              </p>
              <p className="action-platform-note">
                <span>macOS native</span>
                <span>local first</span>
                <span>inspectable runs</span>
              </p>
            </div>
          </div>
        </section>

        <div className="action-tech-rail" aria-label="Core technologies">
          <span>AppKit lifecycle</span>
          <span>ScreenCaptureKit</span>
          <span>AX + OCR</span>
          <span>CLI + MCP</span>
        </div>

        <section className="action-film" aria-labelledby="action-film-title">
          <div className="action-film-heading">
            <div>
              <p className="action-kicker">Product film · 21 seconds</p>
              <h2 id="action-film-title">Drive any actions on the Mac, safely.</h2>
            </div>
            <p>
              Watch Action use a real browser and native macOS runtime, then leave the video, trace, screenshots, and context attached to the run.
            </p>
          </div>
          <div className="action-film-frame">
            <video
              className="action-film-video"
              controls
              playsInline
              preload="metadata"
              poster={actionProductFilmPoster}
              aria-label="Action product film: Drive any actions on the Mac, safely"
            >
              <source src={actionProductFilm} type="video/mp4" />
              <track
                kind="captions"
                srcLang="en"
                label="English"
                src={actionProductFilmCaptions}
              />
              <a href={actionProductFilm}>Open the Action product film.</a>
            </video>
          </div>
          <div className="action-film-foot" aria-hidden="true">
            <span>Observe</span>
            <i />
            <span>Act</span>
            <i />
            <span>Record</span>
            <i />
            <span>Review</span>
          </div>
        </section>

        <section id="architecture" className="action-architecture" aria-labelledby="action-architecture-title">
          <div className="action-architecture-copy">
            <h2 id="action-architecture-title">
              <span>One local path from</span>
              <span>intent to evidence.</span>
            </h2>
            <p>
              An agent or operator calls the local Action runtime, which owns the session, targets, and orchestration. ActionAgent bridges those requests into native macOS work.
            </p>
            <p>
              Action.app owns AppKit, WebKit, permissions, and capture. The run comes back with its receipts attached—including an explicit finished marker when recording is actually complete.
            </p>
          </div>
          <ActionArchitectureDiagram theme={theme} />
        </section>

        <section className="action-purpose" aria-labelledby="action-purpose-title">
          <div className="action-section-heading">
            <p className="action-kicker">One family, two focused products</p>
            <h2 id="action-purpose-title">The workspace and the run belong together.</h2>
          </div>
          <div className="action-product-boundary">
            <article>
              <span className="action-boundary-label">Lattices</span>
              <h3>Unified API for your workspace</h3>
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
              <h3>Unified API for computer use</h3>
              <p>Target resolution, on-device actions, capture, trace, and review for one inspectable piece of work.</p>
              <a href={downloadUrl} data-router="reload">Download Action &rarr;</a>
            </article>
          </div>
          <p className="action-boundary-note">
            Use Action on its own, or pair it with Lattices when the whole workspace needs to stay organized and programmable.
          </p>
        </section>

        <section className="action-proof" aria-labelledby="action-proof-title">
          <img className="action-proof-art" src={actionTraceField} alt="" aria-hidden="true" />
          <div className="action-proof-inner">
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
