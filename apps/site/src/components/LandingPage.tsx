import { useState } from "react";

type PkgManager = "npm" | "pnpm" | "bun";

const commands: Record<PkgManager, string> = {
  npm: "npm install -g @lattices/cli",
  pnpm: "pnpm add -g @lattices/cli",
  bun: "bun add -g @lattices/cli",
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
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} fill="none">
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
            fill={bright ? "#f2f2f2" : "rgba(255,255,255,0.18)"}
          />
        );
      })}
    </svg>
  );
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

type PaneLayout = 1 | 2 | 3;

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

const agentExample = `<span class="hl-kw">import</span> { daemonCall } <span class="hl-kw">from</span> <span class="hl-str">'@lattices/cli'</span>

<span class="hl-cmt">// Search windows by content</span>
<span class="hl-kw">const</span> hits = <span class="hl-kw">await</span> daemonCall(<span class="hl-str">'windows.search'</span>, {
  query: <span class="hl-str">'myproject'</span>
})

<span class="hl-cmt">// Launch and tile side-by-side</span>
<span class="hl-kw">await</span> daemonCall(<span class="hl-str">'session.launch'</span>, {
  path: <span class="hl-str">'/Users/you/dev/frontend'</span>
})
<span class="hl-kw">await</span> daemonCall(<span class="hl-str">'session.launch'</span>, {
  path: <span class="hl-str">'/Users/you/dev/api'</span>
})
<span class="hl-kw">const</span> sessions = <span class="hl-kw">await</span> daemonCall(<span class="hl-str">'tmux.sessions'</span>)
<span class="hl-kw">await</span> daemonCall(<span class="hl-str">'window.tile'</span>, {
  session: sessions[<span class="hl-num">0</span>].name,
  position: <span class="hl-str">'left'</span>
})
<span class="hl-kw">await</span> daemonCall(<span class="hl-str">'window.tile'</span>, {
  session: sessions[<span class="hl-num">1</span>].name,
  position: <span class="hl-str">'right'</span>
})`;

export default function App() {
  const [pm, setPm] = useState<PkgManager>("npm");
  const [copied, setCopied] = useState(false);
  const [paneLayout, setPaneLayout] = useState<PaneLayout>(2);

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
            <a href="#config" className="nav-link">
              Config
            </a>
            <a href="#app" className="nav-link">
              App
            </a>
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
            Open source · 100% free
          </div>
          <h1>
            The agentic
            <br />
            <span className="accent">window manager</span>
          </h1>
          <div className="hero-pillars">
            <div className="hero-pillar">
              <h2>Programmable workspace</h2>
              <p>35+ RPC methods. AI agents and scripts drive the same desktop you do.</p>
            </div>
            <div className="hero-pillar">
              <h2>Smart layout manager</h2>
              <p>Tile with hotkeys, organize into layers, search text across every window.</p>
            </div>
            <div className="hero-pillar">
              <h2>Managed tmux sessions</h2>
              <p>We make tmux easy. Use your own terminal — panes and layouts just work.</p>
            </div>
          </div>

          <div className="install fade-in fade-in-delay-1">
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
              <button className="install-copy" onClick={copy}>
                {copied ? <CheckIcon /> : <CopyIcon />}
              </button>
            </div>
            <div className="hero-links">
              <a
                href="https://github.com/arach/lattices"
                target="_blank"
                rel="noopener noreferrer"
                className="star-link"
              >
                <StarIcon />
                Star us on GitHub
              </a>
              <a href="/docs/overview" className="docs-link">
                Read the docs
              </a>
            </div>
          </div>
        </section>

        {/* Coming soon */}
        <section className="next-section fade-in fade-in-delay-2">
          <div className="next-card">
            <div className="next-copy">
              <div className="next-kicker">Opening for TestFlight</div>
              <h2>Lats.dev for iPad</h2>
              <p>
                A new companion app and domain for controlling your Mac workspace
                from beside the keyboard: trackpad gestures, window actions, live
                state, and shortcuts tuned for iPad. Early testing starts next.
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

        {/* Menu bar app */}
        <section className="app-section" id="app">
          <div className="app-grid">
            <div>
              <h2 className="app-title">Native macOS menu bar app</h2>
              <p className="app-desc">
                Built with SwiftUI. Manage your workspace — terminal
                sessions, app windows, and layers — from the menu bar.
              </p>
              <ul className="app-features">
                <li>See all projects and session status</li>
                <li>Launch, attach, or detach with a click</li>
                <li>
                  Command palette via <code>Cmd+Shift+M</code>
                </li>
                <li>Window tiling to halves, quarters, or full screen</li>
                <li>
                  <a href="/docs/layers">Workspace layers</a> with <code>Cmd+Option+1/2/3</code>
                </li>
                <li>
                  <a href="/docs/layers#tab-groups">Tab groups</a> — related projects as tabs in one session
                </li>
                <li>Cheat sheet HUD and omni search</li>
                <li>Voice commands via Vox integration <span className="beta-badge">beta</span></li>
              </ul>
              <a
                href="https://github.com/arach/lattices/releases/latest/download/Lattices.dmg"
                className="app-download"
              >
                <AppleIcon />
                Download for macOS
                <span className="app-download-meta">Apple Silicon · Free · .dmg</span>
              </a>
            </div>
            <div className="app-screenshot-wrap">
              <img
                src="/app-latest.png"
                alt="lattices app showing screen map with dual displays, layers, and inspector"
                className="app-screenshot"
              />
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
                <h3>Screen text indexing</h3>
                <p>AX + OCR. Search text across all windows.</p>
              </div>
              <div className="feature">
                <h3>Voice commands <span className="beta-badge">beta</span></h3>
                <p>Speak to tile, search, focus, and launch — via Vox.</p>
              </div>
            </div>
          </div>
          <div className="bucket">
            <h3 className="bucket-label">Programmable Workspace</h3>
            <div className="bucket-cards">
              <div className="feature">
                <h3>35+ RPC methods</h3>
                <p>WebSocket on localhost. Full workspace control.</p>
              </div>
              <div className="feature">
                <h3>Agent automation</h3>
                <p>AI agents and scripts drive your desktop.</p>
              </div>
            </div>
          </div>
        </section>

        {/* Config */}
        <section className="section" id="config">
          <div className="config-grid fade-in fade-in-delay-2">
            <div>
              <h2 className="config-title">
                Managed tmux sessions
              </h2>
              <p className="config-desc">
                We make tmux easy. Use your own terminal — define
                panes and layouts in a single JSON file.
              </p>
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
                Your AI co-pilot needs to see what you see
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
                <li><code>session.launch</code> — start a project session</li>
                <li><code>window.tile</code> — snap windows to screen positions</li>
                <li>35+ methods + 5 real-time events</li>
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
          <p>Install globally. Your agent gets a control plane in seconds.</p>
          <div className="cta-actions">
            <a
              href="https://github.com/arach/lattices"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-primary"
            >
              View on GitHub
            </a>
            <a
              href="https://www.npmjs.com/package/lattices"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-secondary"
            >
              npm package
            </a>
            <a
              href="https://github.com/arach/lattices/releases/latest/download/Lattices.dmg"
              className="btn btn-secondary"
            >
              <AppleIcon /> Download .dmg
            </a>
            <a
              href="/docs/api"
              className="btn btn-secondary"
            >
              API Reference
            </a>
          </div>
        </section>

        {/* Footer */}
        <footer className="footer">
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
          <a href="/docs/overview" className="footer-link">
            Documentation
          </a>
          <span>macOS only. tmux optional.</span>
        </footer>
      </div>
    </>
  );
}
