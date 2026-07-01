import { useEffect, useState } from "react";

type PkgManager = "npm" | "pnpm" | "bun";

const commands: Record<PkgManager, string> = {
  npm: "npm install @lattices/sdk",
  pnpm: "pnpm add @lattices/sdk",
  bun: "bun add @lattices/sdk",
};

const pmOrder: PkgManager[] = ["npm", "pnpm", "bun"];

function LatticesLogo({ size = 20 }: { size?: number }) {
  // 3×3 grid with L-shape pattern (left column + bottom row bright, rest dim)
  const cells = [
    true, false, false,
    true, false, false,
    true, true, true,
  ];
  const pad = 2;
  const gap = 1.2;
  const cell = (size - 2 * pad - 2 * gap) / 3;
  return (
    <svg
      aria-hidden="true"
      className="lattices-logo"
      width={size}
      height={size}
      viewBox={`0 0 ${size} ${size}`}
      fill="none"
    >
      {cells.map((bright, i) => {
        const row = Math.floor(i / 3);
        const col = i % 3;
        return (
          <rect
            key={i}
            x={pad + col * (cell + gap)}
            y={pad + row * (cell + gap)}
            width={cell}
            height={cell}
            rx={1}
            className="lattices-logo-cell"
            style={{ fill: bright ? "var(--logo-ink)" : "var(--logo-dim)" }}
          />
        );
      })}
    </svg>
  );
}

declare global {
  interface Window {
    gtag?: (...args: unknown[]) => void
  }
}

function trackCta(action: string, destination: string) {
  if (typeof window !== 'undefined' && typeof window.gtag === 'function') {
    window.gtag('event', 'cta_click', {
      cta_action: action,
      cta_destination: destination,
    })
  }
}

function GitHubIcon() {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

function StarIcon() {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14">
      <path d="M8 .25a.75.75 0 01.673.418l1.882 3.815 4.21.612a.75.75 0 01.416 1.279l-3.046 2.97.719 4.192a.75.75 0 01-1.088.791L8 12.347l-3.766 1.98a.75.75 0 01-1.088-.79l.72-4.194L.818 6.374a.75.75 0 01.416-1.28l4.21-.611L7.327.668A.75.75 0 018 .25z" />
    </svg>
  );
}

function CopyIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
      <rect x="9" y="9" width="13" height="13" rx="2" />
      <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1" />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
      <polyline points="20 6 9 17 4 12" />
    </svg>
  );
}

function AppleIcon() {
  return (
    <svg viewBox="0 0 384 512" fill="currentColor" width="14" height="14">
      <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184 4 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" />
    </svg>
  );
}

function DownloadIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} width="14" height="14">
      <path d="M12 3v12" />
      <path d="m7 10 5 5 5-5" />
      <path d="M5 21h14" />
    </svg>
  );
}

type PaneLayout = 1 | 2 | 3;
type CuaStepId = "observe" | "stage" | "execute" | "verify";

const configExamples: Record<PaneLayout, string> = {
  1: `{
  <span class="hl-key">"panes"</span>: [
    { <span class="hl-key">"cmd"</span>: <span class="hl-str">"claude"</span> }
  ]
}`,
  2: `{
  <span class="hl-key">"ensure"</span>: <span class="hl-num">true</span>,
  <span class="hl-key">"panes"</span>: [
    { <span class="hl-key">"name"</span>: <span class="hl-str">"claude"</span>, <span class="hl-key">"cmd"</span>: <span class="hl-str">"claude"</span>, <span class="hl-key">"size"</span>: <span class="hl-num">60</span> },
    { <span class="hl-key">"name"</span>: <span class="hl-str">"dev"</span>,    <span class="hl-key">"cmd"</span>: <span class="hl-str">"bun dev"</span> }
  ]
}`,
  3: `{
  <span class="hl-key">"ensure"</span>: <span class="hl-num">true</span>,
  <span class="hl-key">"panes"</span>: [
    { <span class="hl-key">"name"</span>: <span class="hl-str">"claude"</span>, <span class="hl-key">"cmd"</span>: <span class="hl-str">"claude"</span>, <span class="hl-key">"size"</span>: <span class="hl-num">60</span> },
    { <span class="hl-key">"name"</span>: <span class="hl-str">"dev"</span>,    <span class="hl-key">"cmd"</span>: <span class="hl-str">"bun dev"</span> },
    { <span class="hl-key">"name"</span>: <span class="hl-str">"test"</span>,   <span class="hl-key">"cmd"</span>: <span class="hl-str">"bun test --watch"</span> }
  ]
}`,
};

const agentExample = `<span class="hl-kw">import</span> { daemonCall } <span class="hl-kw">from</span> <span class="hl-str">'@lattices/sdk'</span>

<span class="hl-cmt">// Search the live desktop</span>
<span class="hl-kw">const</span> [match] = <span class="hl-kw">await</span> daemonCall(<span class="hl-str">'windows.search'</span>, {
  query: <span class="hl-str">'myproject'</span>
})
<span class="hl-kw">await</span> daemonCall(<span class="hl-str">'window.focus'</span>, {
  wid: match.wid
})

<span class="hl-cmt">// Bring up a configured workspace</span>
<span class="hl-kw">await</span> daemonCall(<span class="hl-str">'layer.activate'</span>, {
  name: <span class="hl-str">'review'</span>,
  mode: <span class="hl-str">'launch'</span>,
})

<span class="hl-cmt">// Balance whatever is now visible</span>
<span class="hl-kw">await</span> daemonCall(<span class="hl-str">'space.optimize'</span>, {
  scope: <span class="hl-str">'visible'</span>,
  strategy: <span class="hl-str">'balanced'</span>,
})`;

const cuaSteps: Array<{
  id: CuaStepId;
  number: string;
  title: string;
  heading: string;
  caption: string;
  filename: string;
  code: string;
}> = [
  {
    id: "observe",
    number: "01",
    title: "Observe",
    heading: "Read the app before acting",
    caption: "Capture AX, OCR, screenshots, and window state so the agent chooses from stable targets.",
    filename: "observe.ts",
    code: `<span class="hl-kw">const</span> ui = <span class="hl-kw">await</span> windowState({
  app: <span class="hl-str">'Calculator'</span>,
  mode: <span class="hl-str">'ax'</span>,
  capture: [<span class="hl-str">'tree'</span>, <span class="hl-str">'ocr'</span>, <span class="hl-str">'screen'</span>],
})`,
  },
  {
    id: "stage",
    number: "02",
    title: "Stage",
    heading: "Prepare a reviewable action",
    caption: "Bind the next move to an element, region, or coordinate while nothing has run yet.",
    filename: "stage.ts",
    code: `<span class="hl-kw">await</span> elementAction({
  snapshotId: ui.snapshotId,
  elementId: <span class="hl-str">'e7'</span>,
  action: <span class="hl-str">'press'</span>,
  treatment: <span class="hl-str">'stage'</span>,
})`,
  },
  {
    id: "execute",
    number: "03",
    title: "Execute",
    heading: "Run the exact staged command",
    caption: "Click, type, hotkey, scroll, drag, set values, or drive browser actions with recording on.",
    filename: "execute.ts",
    code: `<span class="hl-kw">await</span> elementAction({
  snapshotId: ui.snapshotId,
  elementId: <span class="hl-str">'e7'</span>,
  action: <span class="hl-str">'press'</span>,
  treatment: <span class="hl-str">'execute'</span>,
  recording: <span class="hl-num">true</span>,
})`,
  },
  {
    id: "verify",
    number: "04",
    title: "Verify",
    heading: "Check the result on-device",
    caption: "Confirm the outcome with OCR, AX, or artifact diff, then feed that receipt into the next observation.",
    filename: "verify.ts",
    code: `<span class="hl-kw">const</span> receipt = <span class="hl-kw">await</span> verify({
  app: <span class="hl-str">'Calculator'</span>,
  mode: <span class="hl-str">'ocr'</span>,
  contains: <span class="hl-str">'42'</span>,
  attachArtifact: <span class="hl-num">true</span>,
})`,
  },
];

const showLatsDevTeaser = import.meta.env.PUBLIC_SHOW_LATS_DEV_TEASER === "true";

export default function App() {
  const [pm, setPm] = useState<PkgManager>("npm");
  const [copied, setCopied] = useState(false);
  const [paneLayout, setPaneLayout] = useState<PaneLayout>(2);
  const [cuaStep, setCuaStep] = useState<CuaStepId>("observe");
  // Initial theme is set synchronously by the inline script in index.html
  // (saved choice → system preference → dark). This re-syncs on toggle.
  const [theme, setTheme] = useState<"light" | "dark">(
    () => (document.documentElement.getAttribute("data-theme") as "light" | "dark") || "dark",
  );
  const activeCuaStep = cuaSteps.find((step) => step.id === cuaStep) ?? cuaSteps[0];

  useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem("theme", theme);
  }, [theme]);

  const copy = async () => {
    await navigator.clipboard.writeText(commands[pm]);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <>
      {/* Nav */}
      <nav className="nav">
        <div className="nav-inner">
          <a href="/" className="nav-brand">
            <LatticesLogo size={20} />
            <span className="nav-name">lattices</span>
          </a>
          <div className="nav-links">
            <a href="/blog" className="nav-link">
              Blog
            </a>
            <a href="/docs/overview" className="nav-link">
              Docs
            </a>
            <a href="/docs/api" className="nav-link">
              API
            </a>
            <a href="#cua" className="nav-link">
              CUA
            </a>
            <a href="#config" className="nav-link nav-optional-mobile">
              Config
            </a>
            <a href="#app" className="nav-link nav-optional-mobile">
              App
            </a>
            <button
              type="button"
              className="nav-link"
              onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
              aria-label={`Switch to ${theme === "dark" ? "light" : "dark"} theme`}
            >
              Theme
            </button>
            <a
              href="https://github.com/arach/lattices"
              target="_blank"
              rel="noopener noreferrer"
              className="nav-github"
            >
              <GitHubIcon />
              <span className="github-label">GitHub</span>
            </a>
          </div>
        </div>
      </nav>

      {/* Hero */}
      <div className="shell">
        <section className="hero fade-in">
          <div className="hero-badge">
            <LatticesLogo size={14} />
            Open source
          </div>
          <h1>
            agentic window
            <br />
            <span className="accent">management</span>
          </h1>
          <p className="hero-sub">
            When your desktop is full of windows, terminals, and agents, Lattices gives you one place to arrange, launch, and control all of it — by hand or from code.
          </p>
          <div className="hero-pillars">
            <div className="hero-pillar">
              <h2>Window manager</h2>
              <p>Resize, move, and switch windows with mouse or keyboard. Snap to grids, layers, and spaces across your Mac.</p>
            </div>
            <div className="hero-pillar">
              <h2>Managed terminal sessions</h2>
              <p>Configurable terminal sessions powered by tmux today — panes, tabs, groups, and layouts that you control and restore.</p>
            </div>
            <div className="hero-pillar">
              <h2>Computer use (CUA)</h2>
              <p>Full mouse, keyboard, and screen actions with recording and verification so agents can act and confirm every step.</p>
            </div>
            <div className="hero-pillar">
              <h2>API for your agents</h2>
              <p>40+ typed methods over one connection so agents control windows, terminals, and your full desktop from code or AI.</p>
            </div>
          </div>

          <div className="install fade-in fade-in-delay-1">
            <a
              href="https://github.com/arach/lattices/releases/latest/download/Lattices.dmg"
              className="install-app-download"
              onClick={() => trackCta('download_dmg_hero', 'https://github.com/arach/lattices/releases/latest/download/Lattices.dmg')}
            >
              <span className="install-app-icon">
                <AppleIcon />
              </span>
              <span className="install-app-copy">
                <span>Native macOS app</span>
                <span>Apple Silicon .dmg</span>
              </span>
              <span className="install-app-go" aria-hidden="true">
                <DownloadIcon />
              </span>
            </a>
            <div className="install-surface">
              <div className="install-surface-head">
                <span>SDK package</span>
                <span>Agent API</span>
              </div>
              <div className="install-tabs">
                {pmOrder.map((p) => (
                  <button
                    key={p}
                    className={`install-tab ${pm === p ? "active" : ""}`}
                    onClick={() => setPm(p)}
                  >
                    {p}
                  </button>
                ))}
              </div>
              <div className="install-cmd">
                <code>
                  <span className="prompt">$</span>
                  {commands[pm]}
                </code>
                <button className="install-copy" onClick={copy} aria-label="Copy install command">
                  {copied ? <CheckIcon /> : <CopyIcon />}
                </button>
              </div>
            </div>
            <div className="hero-links">
              <a
                href="https://github.com/arach/lattices"
                target="_blank"
                rel="noopener noreferrer"
                className="star-link"
                onClick={() => trackCta('star_github', 'https://github.com/arach/lattices')}
              >
                <StarIcon />
                Star us on GitHub
              </a>
              <a
                href="/docs/overview"
                className="docs-link"
                onClick={() => trackCta('read_docs', '/docs/overview')}
              >
                Read the docs
              </a>
            </div>
          </div>
        </section>

        {/* Computer use (CUA) */}
        <section className="section cua-section" id="cua">
          <div className="cua-head fade-in">
            <div className="cua-kicker">On-device automation</div>
            <h2>Safe computer use, built for agents</h2>
            <p>
              Observe the screen, stage each action for review, execute on-device,
              then verify the result — and loop.
            </p>
          </div>

          <div className="cua-showcase fade-in fade-in-delay-1">
            <div className="cua-loop-rail" aria-label="Computer use safety loop">
              {cuaSteps.map((step) => (
                <button
                  key={step.id}
                  type="button"
                  className={`cua-stage-chip${cuaStep === step.id ? " active" : ""}`}
                  onClick={() => setCuaStep(step.id)}
                  aria-pressed={cuaStep === step.id}
                >
                  <span className="cua-stage-number">{step.number}</span>
                  <span className="cua-stage-chip-copy">
                    <span>{step.title}</span>
                  </span>
                </button>
              ))}
            </div>

            <div className="cua-stage-panel">
              <div className="cua-stage-copy">
                <p className="cua-stage-eyebrow">
                  {activeCuaStep.number} / {activeCuaStep.title}
                </p>
                <h3>{activeCuaStep.heading}</h3>
                <p>{activeCuaStep.caption}</p>
              </div>

              <div className="code-block">
                <div className="code-header">
                  <span className="code-dot code-dot-red" />
                  <span className="code-dot code-dot-yellow" />
                  <span className="code-dot code-dot-green" />
                  <span className="code-filename">{activeCuaStep.filename}</span>
                </div>
                <pre
                  className="code-pre"
                  dangerouslySetInnerHTML={{ __html: activeCuaStep.code }}
                />
              </div>

              <div className="cua-stage-footer">
                <div className="cua-action-tags" aria-label="Supported computer use actions">
                  <span>mouse</span>
                  <span>keyboard</span>
                  <span>browser</span>
                  <span>local verify</span>
                </div>
                <a href="/docs/api" className="agent-api-link cua-stage-api-link">
                  Computer-use API &rarr;
                </a>
              </div>
            </div>
          </div>
        </section>

        {showLatsDevTeaser && (
          <section className="next-section fade-in fade-in-delay-2">
            <div className="next-card">
              <div className="next-copy">
                <div className="next-kicker">Opening for TestFlight</div>
                <h2>Lats.dev for iPad</h2>
                <p>
                  A new app and domain for controlling your Mac workspace from
                  beside the keyboard: trackpad gestures, window actions, live state,
                  and shortcuts tuned for iPad. Early testing starts next.
                </p>
              </div>
              <div className="next-preview" aria-hidden="true">
                <div className="deck-shell">
                  <div className="deck-top">
                    <span>lats.dev</span>
                    <span>mac · live</span>
                  </div>
                  <div className="deck-trackpad">
                    <div className="deck-crosshair" />
                  </div>
                  <div className="deck-actions">
                    {["tile", "focus", "voice", "agent", "spaces", "keys"].map((label) => (
                      <div className="deck-action" key={label}>{label}</div>
                    ))}
                  </div>
                </div>
              </div>
            </div>
          </section>
        )}

        {/* macOS app */}
        <section className="app-section" id="app">
          <div className="app-heading-row">
            <div>
              <div className="app-title-row">
                <h2 className="app-title">Native macOS app</h2>
                <a
                  href="https://github.com/arach/lattices/releases/latest/download/Lattices.dmg"
                  className="app-download-icon"
                  aria-label="Download Lattices for macOS"
                  title="Download Lattices for macOS"
                  onClick={() => trackCta('download_dmg', 'https://github.com/arach/lattices/releases/latest/download/Lattices.dmg')}
                >
                  <DownloadIcon />
                </a>
              </div>
              <p className="app-desc">
                Built with SwiftUI. Manage your workspace — terminal
                sessions, app windows, and layers — from an installed Mac app.
              </p>
            </div>
          </div>
          <div className="app-grid">
            <div className="app-copy">
              <ul className="app-features">
                <li>See all projects and session status</li>
                <li>Launch, attach, or detach with a click</li>
                <li>
                  Command palette via <code>Cmd+Shift+M</code>
                </li>
                <li>Window tiling, layers, and tab groups</li>
                <li>
                  <a href="/docs/layers">Workspace layers</a> via <code>Cmd+Option+1/2/3</code>
                </li>
                <li>Gestures, overlays, and omni search</li>
                <li>Voice commands for tiling, search, focus, and launch</li>
              </ul>
            </div>
            <div className="app-demo-reel" aria-label="Animated preview of lattices arranging windows, layers, search, and voice commands">
              <img
                src="/app-latest.png"
                alt="lattices app showing screen map with dual displays, layers, and inspector"
                className="app-screenshot"
              />
              <div className="app-demo-cursor" aria-hidden="true" />
              <div className="app-demo-focus app-demo-focus-one" aria-hidden="true" />
              <div className="app-demo-focus app-demo-focus-two" aria-hidden="true" />
              <div className="app-demo-tile app-demo-tile-left" aria-hidden="true" />
              <div className="app-demo-tile app-demo-tile-right" aria-hidden="true" />
            </div>
          </div>
        </section>

        {/* Features */}
        <section className="feature-buckets fade-in fade-in-delay-2" id="features">
          <div className="bucket">
            <h3 className="bucket-label">Durable Terminal Sessions</h3>
            <div className="bucket-cards">
              <div className="feature">
                <h3>One command, zero config</h3>
                <p>Run <code>lattices start</code> — session created, dev server running.</p>
              </div>
              <div className="feature">
                <h3>Persistent sessions</h3>
                <p>Survives reboots. Reattach anytime.</p>
              </div>
              <div className="feature">
                <h3>Tab groups</h3>
                <p>Related projects as tabs in one session.</p>
              </div>
            </div>
          </div>
          <div className="bucket">
            <h3 className="bucket-label">Smart Layout Manager</h3>
            <div className="bucket-cards">
              <div className="feature">
                <h3>Tiling + layers</h3>
                <p>Hotkeys, snap to grids, switchable window groups.</p>
              </div>
              <div className="feature">
                <h3>Mouse gestures</h3>
                <p>Draw shapes to tile, focus, launch, or run shortcuts with visible feedback.</p>
              </div>
              <div className="feature">
                <h3>Screen animations</h3>
                <p>Put little visuals on screen for gesture trails, status, and workspace cues.</p>
              </div>
            </div>
          </div>
          <div className="bucket">
            <h3 className="bucket-label">Programmable Workspace</h3>
            <div className="bucket-cards">
              <div className="feature">
                <h3>40+ RPC methods</h3>
                <p>WebSocket on localhost. Full workspace control.</p>
              </div>
              <div className="feature">
                <h3>Agent automation</h3>
                <p>AI agents and scripts drive your desktop.</p>
              </div>
              <div className="feature">
                <h3>Screen text indexing</h3>
                <p>AX + OCR. Search text across all windows.</p>
              </div>
            </div>
          </div>
        </section>

        {/* Config */}
        <section className="section" id="config">
          <div className="config-head fade-in fade-in-delay-2">
            <h2 className="config-title">
              Managed terminal sessions
            </h2>
            <p className="config-desc">
              tmux made easy today — configurable panes, tabs, and layouts that save, restore, and fit your workflow.
            </p>
          </div>

          <div className="config-grid fade-in fade-in-delay-2">
            <div>
              <div className="layouts">
                <div className={`layout-card${paneLayout === 1 ? " active" : ""}`} onClick={() => setPaneLayout(1)}>
                  <h3>1 pane</h3>
                  <p>Single focus</p>
                  <div className="layout-diagram layout-1">
                    <div className="layout-pane main">claude</div>
                  </div>
                </div>
                <div className={`layout-card${paneLayout === 2 ? " active" : ""}`} onClick={() => setPaneLayout(2)}>
                  <h3>2 panes</h3>
                  <p>Side-by-side</p>
                  <div className="layout-diagram layout-2">
                    <div className="layout-pane main">claude</div>
                    <div className="layout-pane">server</div>
                  </div>
                </div>
                <div className={`layout-card${paneLayout === 3 ? " active" : ""}`} onClick={() => setPaneLayout(3)}>
                  <h3>3+ panes</h3>
                  <p>Main-vertical</p>
                  <div className="layout-diagram layout-3">
                    <div className="layout-pane main">claude</div>
                    <div className="layout-pane">server</div>
                    <div className="layout-pane">tests</div>
                  </div>
                </div>
              </div>
            </div>

            <div className="code-block">
              <div className="code-header">
                <span className="code-dot code-dot-red" />
                <span className="code-dot code-dot-yellow" />
                <span className="code-dot code-dot-green" />
                <span className="code-filename">.lattices.json</span>
              </div>
              <pre
                className="code-pre"
                dangerouslySetInnerHTML={{ __html: configExamples[paneLayout] }}
              />
            </div>
          </div>
        </section>

        {/* Agent-managed workspaces */}
        <section className="section" id="agents">
          <div className="config-grid fade-in fade-in-delay-2">
            <div>
              <h2 className="config-title">
                Your agents need to see what you see
              </h2>
              <p className="config-desc">
                Agents are limited to a terminal. Lattices gives them
                eyes — every window, every pixel of text, every layout
                change — over a single WebSocket.
              </p>
              <ul className="agent-methods">
                <li><code>windows.search</code> — find windows by title, app, session, OCR</li>
                <li><code>terminals.search</code> — inspect terminal tabs, processes, cwds</li>
                <li><code>ocr.search</code> — full-text search across all screen content</li>
                <li><code>computer.windowState</code> — AX snapshot with actionable element IDs</li>
                <li><code>computer.verify</code> — confirm outcomes via OCR, AX, or artifact diff</li>
                <li><code>layer.activate</code> — launch or focus a whole workspace</li>
                <li><code>space.optimize</code> — balance visible windows after launch</li>
                <li>40+ methods + live workspace updates pushed over WebSocket</li>
              </ul>
              <a href="/docs/api" className="agent-api-link">
                Full API reference &rarr;
              </a>
            </div>

            <div className="code-block">
              <div className="code-header">
                <span className="code-dot code-dot-red" />
                <span className="code-dot code-dot-yellow" />
                <span className="code-dot code-dot-green" />
                <span className="code-filename">agent-example.js</span>
              </div>
              <pre
                className="code-pre"
                dangerouslySetInnerHTML={{ __html: agentExample }}
              />
            </div>
          </div>
        </section>

        {/* CTA */}
        <section className="cta">
          <h2>Ready to lattices?</h2>
          <p>Install globally. Up and running in seconds.</p>
          <div className="cta-download-row">
            <a
              href="https://github.com/arach/lattices/releases/latest/download/Lattices.dmg"
              className="cta-download-button"
              onClick={() => trackCta('download_dmg', 'https://github.com/arach/lattices/releases/latest/download/Lattices.dmg')}
            >
              <span className="cta-download-icon">
                <AppleIcon />
              </span>
              <span className="cta-download-copy">
                <span>Download for macOS</span>
                <span className="cta-download-meta">Apple Silicon · .dmg</span>
              </span>
              <span className="cta-download-go" aria-hidden="true">
                <DownloadIcon />
              </span>
            </a>
          </div>
          <div className="cta-actions">
            <a
              href="https://github.com/arach/lattices"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-secondary"
              onClick={() => trackCta('view_github', 'https://github.com/arach/lattices')}
            >
              View on GitHub
            </a>
            <a
              href="https://www.npmjs.com/package/lattices"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-secondary"
              onClick={() => trackCta('view_npm', 'https://www.npmjs.com/package/lattices')}
            >
              npm package
            </a>
            <a
              href="/docs/api"
              className="btn btn-secondary"
              onClick={() => trackCta('view_api', '/docs/api')}
            >
              API Reference
            </a>
          </div>
        </section>

        {/* Footer */}
        <footer className="footer">
          <div className="footer-group">
            <span>
              Built by{" "}
              <a
                href="https://github.com/arach"
                target="_blank"
                rel="noopener noreferrer"
              >
                @arach
              </a>
            </span>
            <span className="footer-dot" aria-hidden="true">·</span>
            <span>macOS only. tmux optional.</span>
          </div>
          <nav className="footer-links" aria-label="Footer">
            <a href="/docs/overview">Docs</a>
            <a href="/blog">Blog</a>
            <a href="/rss.xml">RSS</a>
            <a
              href="https://github.com/arach/lattices"
              target="_blank"
              rel="noopener noreferrer"
            >
              GitHub
            </a>
            <a
              href="https://www.npmjs.com/package/lattices"
              target="_blank"
              rel="noopener noreferrer"
            >
              npm
            </a>
          </nav>
        </footer>
      </div>
    </>
  );
}
