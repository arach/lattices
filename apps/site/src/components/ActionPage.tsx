import { useEffect, useRef, useState } from "react";
import actionDownload from "../action-download.json";
import type { MouseEvent } from "react";
import { ActionMark } from "./ActionMark";
import actionHeroArt from "../../../../products/action/docs/assets/brand/landing-hero.webp";
import actionMiraArt from "../../../../products/action/docs/assets/brand/landing-mira.webp";
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
  const [downloadStatus, setDownloadStatus] = useState<"idle" | "loading" | "requested">("idle");
  const downloading = useRef(false);
  const downloadFrame = useRef<HTMLIFrameElement>(null);

  async function startDownload(event: MouseEvent<HTMLAnchorElement>) {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return;
    event.preventDefault();
    const linkText = event.currentTarget.textContent || "Download Action";
    if (downloading.current) return;
    downloading.current = true;
    setDownloadStatus("loading");
    let url = actionDownload.fallbackUrl;
    try {
      const response = await fetch(actionDownload.releasesUrl, {
        headers: { Accept: "application/vnd.github+json" },
        signal: AbortSignal.timeout(8000),
      });
      if (!response.ok) throw new Error("Release lookup failed");
      const releases = await response.json();
      const release = releases.find((release: { draft: boolean; prerelease: boolean; tag_name: string }) =>
        !release.draft && !release.prerelease && release.tag_name?.startsWith("action-v"));
      const asset = release?.assets?.find((asset: { name: string }) => asset.name === "Action.dmg");
      if (asset?.browser_download_url) url = asset.browser_download_url;
    } catch {
      // Keep the established release download available if GitHub's API is unavailable.
    }
    if (downloadFrame.current) downloadFrame.current.src = url;
    window.gtag?.("event", "file_download", {
      file_name: "Action.dmg", file_extension: "dmg", link_url: url,
      link_text: linkText,
      product: "action",
    });
    setDownloadStatus("requested");
    downloading.current = false;
  }

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
      <iframe ref={downloadFrame} title="Action download" hidden />
      {downloadStatus !== "idle" && (
        <aside className="action-download-notice" role="status" aria-live="polite">
          <div>
            <strong>{downloadStatus === "loading" ? "Preparing your download…" : "Your Action download has been requested."}</strong>
            <p>{downloadStatus === "loading" ? "Finding the latest release for macOS." : "Check your browser downloads."}</p>
            {downloadStatus === "requested" && <a href={downloadUrl} data-router="reload" target="_blank" rel="noopener noreferrer">If the download did not start, try again ↗</a>}
          </div>
          <button type="button" onClick={() => setDownloadStatus("idle")} aria-label="Dismiss download message">×</button>
        </aside>
      )}
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
            <a href={downloadUrl} data-router="reload" onClick={startDownload} className="action-nav-download">Download</a>
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
              <img className="action-hero-mark" src={`/brand/action/action-${theme}.svg`} width={80} height={80} alt="" />
              <p className="action-kicker action-hero-kicker">A Lattices product · native macOS automation</p>
              <h1 id="action-title">Action is a unified API for computer use.</h1>
              <p className="action-hero-lead">
                Record and share macOS runs with video, screenshots, accessibility context, and traces.
              </p>
              <div className="action-hero-actions">
                <a href={downloadUrl} data-router="reload" onClick={startDownload} className="hero-primary-cta action-primary-cta">
                  Download for macOS
                  <span aria-hidden="true">↓</span>
                </a>
                <a href="/docs/agents" className="hero-secondary-cta action-secondary-cta">
                  Install for agents
                </a>
              </div>
              <p className="action-agent-entry">
                Reading this as an agent? <a href="/docs/agents">Start here</a> for capabilities, connection, and which browser to drive.
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
              aria-label="Action product film: Give your agents a way to use your Mac"
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
              Action.app owns AppKit, WebKit, permissions, and capture. The run comes back with its receipts attached, including an explicit finished marker when recording is actually complete.
            </p>
          </div>
          <ActionArchitectureDiagram theme={theme} />
        </section>

        <section className="action-purpose" aria-labelledby="action-purpose-title">
          <div className="action-section-heading">
            <p className="action-kicker">One family, two focused products</p>
            <h2 id="action-purpose-title">Action and Lattices.</h2>
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
              <a href={downloadUrl} data-router="reload" onClick={startDownload}>Download Action &rarr;</a>
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
              <p className="action-kicker">Built for macOS</p>
              <h2 id="action-proof-title">See what happened.</h2>
              <p>
                Review the video, screenshots, and activity log after a run. Action also records when capture has finished.
              </p>
            </div>
            <div className="action-proof-lines">
              <article>
                <span>01</span>
                <h3>Find the right control</h3>
                <p>Action finds buttons and fields through Accessibility and the browser DOM before falling back to screen coordinates.</p>
              </article>
              <article>
                <span>02</span>
                <h3>Run on the Mac</h3>
                <p>Action uses AppKit and ScreenCaptureKit, with access controlled by your macOS permissions.</p>
              </article>
              <article>
                <span>03</span>
                <h3>Review the recording</h3>
                <p>Each run keeps its video, screenshots, activity log, and capture completion status together.</p>
              </article>
            </div>
          </div>
        </section>

        <section className="action-companion" aria-labelledby="action-companion-title">
          <div className="action-companion-copy">
            <p className="action-kicker">Field companion</p>
            <h2 id="action-companion-title">The runtime has a witness.</h2>
            <p>
              The Action visual language is a technical field manual. Mira sits in the margin while the Mac does the work.
            </p>
          </div>
          <figure className="action-companion-art">
            <img src={actionMiraArt} alt="Mira, a compact field companion in goggles and a scarf, sitting beside a capture console" />
          </figure>
        </section>

        <section className="action-source" aria-labelledby="action-source-title">
          <div className="action-source-copy">
            <p className="action-kicker">From source</p>
            <h2 id="action-source-title">Build it. Launch it. Prove it.</h2>
            <p>
              Local commands live in <code>package.json</code>. Run them with bun from <code>products/action</code>.
            </p>
            <ul className="action-source-reqs">
              <li>macOS on Apple Silicon</li>
              <li>Bun and the Swift toolchain</li>
              <li>Accessibility permission</li>
              <li>Screen Recording permission</li>
            </ul>
            <a href="/action/getting-started.md" data-router="reload" className="action-source-link">Getting started &rarr;</a>
          </div>
          <div className="action-terminal" aria-label="Action source commands">
            <div className="action-terminal-bar">products/action</div>
            <pre className="action-terminal-body">
              <code>
                <span className="action-terminal-line"><span className="action-terminal-prompt">$</span> bun install</span>
                <span className="action-terminal-line"><span className="action-terminal-prompt">$</span> bun run native:app:build</span>
                <span className="action-terminal-output">Action.app signed and ready</span>
                <span className="action-terminal-line"><span className="action-terminal-prompt">$</span> bun run native:doctor</span>
                <span className="action-terminal-output">Accessibility: granted · Screen Recording: granted</span>
                <span className="action-terminal-line"><span className="action-terminal-prompt">$</span> bun run native:launch</span>
                <span className="action-terminal-output">Action.app running</span>
              </code>
            </pre>
          </div>
        </section>

        <section className="action-final-cta" aria-labelledby="action-final-title">
          <div className="action-final-copy">
            <p className="action-kicker">Action for macOS</p>
            <h2 id="action-final-title">Give the agent a computer-use path you can review.</h2>
            <div className="action-final-links">
              <a href={downloadUrl} data-router="reload" onClick={startDownload} className="hero-primary-cta action-primary-cta">Download Action</a>
              <a href={sourceUrl} className="hero-secondary-cta action-secondary-cta">View source</a>
            </div>
          </div>
          <figure className="action-brand-study" aria-hidden="true">
            <ActionMark theme={theme} padding={36} decorative />
          </figure>
        </section>
      </main>

      <footer className="action-footer">
        <div className="action-footer-inner">
          <span>Action is a focused computer-use product from Lattices.</span>
          <div>
            <a href="/">Lattices</a>
            <a href="/blink">Blink</a>
            <a href="/speech">Speech</a>
            <a href="/action/llms.txt" data-router="reload">Action docs</a>
            <a href={sourceUrl}>GitHub</a>
          </div>
        </div>
      </footer>
    </div>
  );
}
