import { useState } from "react";
import "./index.css";

type PkgManager = "npm" | "pnpm" | "bun";

const commands: Record<PkgManager, string> = {
  npm: "npm install -g lattices",
  pnpm: "pnpm add -g lattices",
  bun: "bun add -g lattices",
};

const pmOrder: PkgManager[] = ["npm", "pnpm", "bun"];

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

const configExample = `{
  <span class="hl-key">"ensure"</span>: <span class="hl-num">true</span>,
  <span class="hl-key">"panes"</span>: [
    {
      <span class="hl-key">"name"</span>: <span class="hl-str">"claude"</span>,
      <span class="hl-key">"cmd"</span>: <span class="hl-str">"claude"</span>,
      <span class="hl-key">"size"</span>: <span class="hl-num">60</span>
    },
    {
      <span class="hl-key">"name"</span>: <span class="hl-str">"server"</span>,
      <span class="hl-key">"cmd"</span>: <span class="hl-str">"pnpm dev"</span>
    },
    {
      <span class="hl-key">"name"</span>: <span class="hl-str">"tests"</span>,
      <span class="hl-key">"cmd"</span>: <span class="hl-str">"pnpm test --watch"</span>
    }
  ]
}`;

const agentExample = `<span class="hl-kw">import</span> { daemonCall } <span class="hl-kw">from</span> <span class="hl-str">'lattices/daemon-client'</span>

<span class="hl-cmt">// Discover projects</span>
<span class="hl-kw">const</span> projects = <span class="hl-kw">await</span> daemonCall(<span class="hl-str">'projects.list'</span>)

<span class="hl-cmt">// Launch two sessions</span>
<span class="hl-kw">await</span> daemonCall(<span class="hl-str">'session.launch'</span>, {
  path: <span class="hl-str">'/Users/you/dev/frontend'</span>
})
<span class="hl-kw">await</span> daemonCall(<span class="hl-str">'session.launch'</span>, {
  path: <span class="hl-str">'/Users/you/dev/api'</span>
})

<span class="hl-cmt">// Tile side-by-side</span>
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
            <span className="nav-dot" />
            <span className="nav-name">lattices</span>
          </a>
          <div className="nav-links">
            <a href="/docs/concepts" className="nav-link">
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
            <span className="hero-badge-dot" />
            Open source · 100% free
          </div>
          <h1>
            The workspace
            <br />
            <span className="accent">control plane</span>
          </h1>
          <p className="hero-sub">
            Give AI coding agents full control over tmux sessions,
            window tiling, and project layouts — or use the CLI and
            menu bar app yourself. 20 RPC methods. Zero config required.
          </p>

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
              <a href="/docs/concepts" className="docs-link">
                Read the docs
              </a>
            </div>
          </div>
        </section>

        {/* Config */}
        <section className="section" id="config">
          <div className="config-grid fade-in fade-in-delay-2">
            <div>
              <h2 className="config-title">
                One file. Any layout.
              </h2>
              <p className="config-desc">
                Drop a <code>.lattices.json</code> in your project root.
                Define panes, commands, and sizes.
              </p>
              <div className="layouts">
                <div className="layout-card">
                  <h3>1 pane</h3>
                  <p>Single focus</p>
                  <div className="layout-diagram layout-1">
                    <div className="layout-pane main">claude</div>
                  </div>
                </div>
                <div className="layout-card">
                  <h3>2 panes</h3>
                  <p>Side-by-side</p>
                  <div className="layout-diagram layout-2">
                    <div className="layout-pane main">claude</div>
                    <div className="layout-pane">server</div>
                  </div>
                </div>
                <div className="layout-card">
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
                dangerouslySetInnerHTML={{ __html: configExample }}
              />
            </div>
          </div>
        </section>

        {/* Agent Control Plane */}
        <section className="section" id="agents">
          <div className="config-grid fade-in fade-in-delay-2">
            <div>
              <h2 className="config-title">
                Agents need more than a shell
              </h2>
              <p className="config-desc">
                The daemon API gives AI agents full workspace control
                over WebSocket. Discover projects, launch sessions,
                tile windows, and react to changes — all programmatically.
              </p>
              <ul className="agent-methods">
                <li><code>windows.list</code> — see every window on screen</li>
                <li><code>session.launch</code> — start a project session</li>
                <li><code>window.tile</code> — snap windows to screen positions</li>
                <li><code>layer.switch</code> — switch workspace contexts</li>
                <li>Real-time events for window and session changes</li>
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

        {/* Features */}
        <section className="features fade-in fade-in-delay-2" id="features">
          <div className="feature">
            <span className="feature-icon">&#9654;</span>
            <h3>One command</h3>
            <p>
              Run <code>lattices</code> in any project directory to create a named
              tmux session with your panes running.
            </p>
          </div>
          <div className="feature">
            <span className="feature-icon">&#9881;</span>
            <h3>Daemon API</h3>
            <p>
              20 JSON-RPC methods over WebSocket. Read windows, launch sessions,
              tile, switch layers. Built for agents, scripts, and automation.
            </p>
          </div>
          <div className="feature">
            <span className="feature-icon">&#9881;</span>
            <h3>Auto-detect</h3>
            <p>
              Reads <code>package.json</code> and lock files to pick
              the right dev command automatically.
            </p>
          </div>
          <div className="feature">
            <span className="feature-icon">&#8644;</span>
            <h3>Persistent</h3>
            <p>
              Sessions run in the background. Detach, reattach, pick up
              where you left off.
            </p>
          </div>
          <div className="feature">
            <span className="feature-icon">&#9638;</span>
            <h3>Workspace layers</h3>
            <p>
              Group projects into switchable layers. <code>Cmd+Option+1/2/3</code> to
              instantly focus and tile a whole context.
            </p>
          </div>
          <div className="feature">
            <span className="feature-icon">&#9783;</span>
            <h3>Tab groups</h3>
            <p>
              Bundle related projects as tabs in one window. iOS, macOS,
              Web, API — one <code>lattices group</code> to launch them all.
            </p>
          </div>
        </section>

        {/* Menu bar app */}
        <section className="app-section" id="app">
          <div className="app-grid">
            <div>
              <h2 className="app-title">Native macOS menu bar app</h2>
              <p className="app-desc">
                Built with SwiftUI. Manage all your tmux sessions
                without touching the terminal.
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
                <li>Space navigation and window highlighting</li>
              </ul>
            </div>
            <div className="app-screenshot-wrap">
              <img
                src="/app-screenshot.png"
                alt="lattices menu bar app showing a running session"
                className="app-screenshot"
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
          <a href="/docs/concepts" className="footer-link">
            Documentation
          </a>
          <span>macOS only. Requires tmux.</span>
        </footer>
      </div>
    </>
  );
}
