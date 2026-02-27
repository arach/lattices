import puppeteer from "puppeteer";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const publicDir = join(__dirname, "..", "public");

function buildHTML(tag) {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700&family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }

    body {
      width: 1200px;
      height: 630px;
      font-family: 'Space Grotesk', -apple-system, sans-serif;
      background: #111113;
      color: #ebebef;
      position: relative;
      overflow: hidden;
    }

    /* Grid overlay */
    .grid {
      position: absolute;
      inset: 0;
      background-image:
        linear-gradient(rgba(51, 199, 115, 0.04) 1px, transparent 1px),
        linear-gradient(90deg, rgba(51, 199, 115, 0.04) 1px, transparent 1px);
      background-size: 60px 60px;
    }

    /* Corner crosses */
    .cross { position: absolute; opacity: 0.3; }
    .cross-h, .cross-v { position: absolute; background: repeating-linear-gradient(to right, #33c773 0px, #33c773 5px, transparent 5px, transparent 9px); }
    .cross-v { background: repeating-linear-gradient(to bottom, #33c773 0px, #33c773 5px, transparent 5px, transparent 9px); }
    .cross.tl { top: 40px; left: 40px; }
    .cross.tl .cross-h { width: 80px; height: 1px; top: 20px; left: 0; }
    .cross.tl .cross-v { width: 1px; height: 80px; top: 0; left: 20px; }
    .cross.br { bottom: 40px; right: 40px; }
    .cross.br .cross-h { width: 80px; height: 1px; bottom: 20px; right: 0; }
    .cross.br .cross-v { width: 1px; height: 80px; bottom: 0; right: 20px; }

    /* Accent glows */
    .glow-1 {
      position: absolute;
      top: -80px; left: -80px;
      width: 360px; height: 360px;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(51, 199, 115, 0.08) 0%, transparent 70%);
    }
    .glow-2 {
      position: absolute;
      bottom: -120px; right: 200px;
      width: 400px; height: 400px;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(51, 199, 115, 0.05) 0%, transparent 70%);
    }

    /* Content layout */
    .content {
      position: relative;
      z-index: 10;
      display: flex;
      height: 100%;
      padding: 70px 80px;
      gap: 60px;
    }

    .left {
      flex: 1;
      display: flex;
      flex-direction: column;
      justify-content: center;
    }

    .right {
      display: flex;
      align-items: center;
      flex-shrink: 0;
    }

    /* Tag badge */
    .tag {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 16px;
      border-radius: 6px;
      border: 1px solid rgba(51, 199, 115, 0.3);
      background: rgba(51, 199, 115, 0.08);
      font-family: 'JetBrains Mono', monospace;
      font-size: 13px;
      font-weight: 500;
      color: #33c773;
      margin-bottom: 32px;
      width: fit-content;
      letter-spacing: 0.02em;
    }

    /* Title */
    .title {
      font-family: 'JetBrains Mono', monospace;
      font-size: 64px;
      font-weight: 700;
      letter-spacing: -0.03em;
      line-height: 1;
      margin-bottom: 20px;
    }

    .subtitle {
      font-size: 20px;
      color: rgba(255, 255, 255, 0.45);
      line-height: 1.5;
      max-width: 420px;
    }

    /* Brand footer */
    .brand {
      display: flex;
      align-items: center;
      gap: 10px;
      margin-top: auto;
      padding-top: 32px;
    }

    .brand-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #33c773;
      box-shadow: 0 0 8px rgba(51, 199, 115, 0.4);
    }

    .brand-name {
      font-family: 'JetBrains Mono', monospace;
      font-size: 14px;
      font-weight: 500;
      color: rgba(255, 255, 255, 0.35);
    }

    /* ── App mockup ──────────────────────── */

    .app {
      width: 340px;
      background: #1c1c1e;
      border-radius: 14px;
      border: 1px solid rgba(255, 255, 255, 0.08);
      box-shadow:
        0 24px 48px rgba(0, 0, 0, 0.5),
        0 0 0 1px rgba(255, 255, 255, 0.03);
      overflow: hidden;
    }

    .app-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 16px 18px 12px;
    }

    .app-title {
      display: flex;
      align-items: baseline;
      gap: 10px;
    }

    .app-name {
      font-family: 'JetBrains Mono', monospace;
      font-size: 16px;
      font-weight: 700;
      color: rgba(255, 255, 255, 0.92);
    }

    .app-count {
      font-family: 'JetBrains Mono', monospace;
      font-size: 12px;
      color: #33c773;
    }

    .app-refresh {
      width: 22px;
      height: 22px;
      border-radius: 4px;
      border: 1px solid rgba(255, 255, 255, 0.08);
      display: flex;
      align-items: center;
      justify-content: center;
      color: rgba(255, 255, 255, 0.3);
      font-size: 12px;
    }

    .app-search {
      margin: 0 14px 12px;
      padding: 8px 12px;
      border-radius: 6px;
      background: rgba(255, 255, 255, 0.04);
      border: 1px solid rgba(255, 255, 255, 0.06);
      font-family: 'Space Grotesk', sans-serif;
      font-size: 12px;
      color: rgba(255, 255, 255, 0.2);
      display: flex;
      align-items: center;
      gap: 8px;
    }

    .app-search-icon {
      opacity: 0.3;
      font-size: 11px;
    }

    /* Project row */
    .project {
      margin: 0 14px 10px;
      padding: 12px 14px;
      border-radius: 8px;
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid rgba(255, 255, 255, 0.06);
      display: flex;
      align-items: center;
      gap: 12px;
    }

    .project-bar {
      width: 3px;
      height: 36px;
      border-radius: 2px;
      background: #33c773;
    }

    .project-info {
      flex: 1;
    }

    .project-name {
      font-family: 'JetBrains Mono', monospace;
      font-size: 14px;
      font-weight: 600;
      color: rgba(255, 255, 255, 0.9);
      margin-bottom: 3px;
    }

    .project-panes {
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      color: rgba(255, 255, 255, 0.3);
    }

    .project-bars {
      display: flex;
      gap: 3px;
      margin-right: 8px;
    }

    .pane-bar {
      width: 3px;
      height: 14px;
      border-radius: 1px;
      background: #33c773;
      opacity: 0.6;
    }

    .project-actions {
      display: flex;
      gap: 6px;
    }

    .btn-detach {
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      font-weight: 500;
      padding: 4px 10px;
      border-radius: 3px;
      border: 1px solid rgba(245, 166, 35, 0.4);
      color: #f5a623;
      background: transparent;
    }

    .btn-attach {
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      font-weight: 600;
      padding: 4px 10px;
      border-radius: 3px;
      background: rgba(255, 255, 255, 0.9);
      color: #111;
      border: none;
    }

    /* Second project (idle) */
    .project-idle .project-bar {
      background: rgba(255, 255, 255, 0.15);
    }

    .project-idle .pane-bar {
      background: rgba(255, 255, 255, 0.15);
    }

    .project-idle .project-name {
      color: rgba(255, 255, 255, 0.5);
    }

    .btn-launch {
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      font-weight: 500;
      padding: 4px 10px;
      border-radius: 3px;
      background: rgba(255, 255, 255, 0.06);
      border: 1px solid rgba(255, 255, 255, 0.1);
      color: rgba(255, 255, 255, 0.5);
    }

    /* Status bar */
    .app-status {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 10px 18px;
      border-top: 1px solid rgba(255, 255, 255, 0.05);
      margin-top: 8px;
    }

    .status-left {
      display: flex;
      align-items: center;
      gap: 10px;
    }

    .status-gear {
      font-size: 12px;
      opacity: 0.25;
    }

    .status-text {
      font-family: 'JetBrains Mono', monospace;
      font-size: 10px;
      color: rgba(255, 255, 255, 0.25);
    }

    .status-text span {
      color: rgba(255, 255, 255, 0.5);
    }

    .status-power {
      font-size: 11px;
      opacity: 0.2;
    }

    /* Bottom accent */
    .accent-bar {
      position: absolute;
      bottom: 0;
      left: 0;
      right: 0;
      height: 4px;
      background: linear-gradient(90deg, #33c773, #1a8f4a);
    }
  </style>
</head>
<body>
  <div class="grid"></div>
  <div class="glow-1"></div>
  <div class="glow-2"></div>

  <div class="cross tl"><div class="cross-h"></div><div class="cross-v"></div></div>
  <div class="cross br"><div class="cross-h"></div><div class="cross-v"></div></div>

  <div class="content">
    <div class="left">
      <div class="tag">${tag}</div>
      <div class="title">lattice</div>
      <div class="subtitle">Declarative tmux sessions. Define your panes in JSON, run one command.</div>
      <div class="brand">
        <div class="brand-dot"></div>
        <span class="brand-name">arach/lattice</span>
      </div>
    </div>

    <div class="right">
      <div class="app">
        <div class="app-header">
          <div class="app-title">
            <span class="app-name">lattice</span>
            <span class="app-count">2 sessions</span>
          </div>
          <div class="app-refresh">&#x21bb;</div>
        </div>

        <div class="app-search">
          <span class="app-search-icon">&#x2315;</span>
          Search projects...
        </div>

        <div class="project">
          <div class="project-bar"></div>
          <div class="project-info">
            <div class="project-name">my-app</div>
            <div class="project-panes">claude &middot; server</div>
          </div>
          <div class="project-bars">
            <div class="pane-bar"></div>
            <div class="pane-bar"></div>
          </div>
          <div class="project-actions">
            <div class="btn-detach">Detach</div>
            <div class="btn-attach">Attach</div>
          </div>
        </div>

        <div class="project project-idle">
          <div class="project-bar"></div>
          <div class="project-info">
            <div class="project-name">docs-site</div>
            <div class="project-panes">claude &middot; dev &middot; tests</div>
          </div>
          <div class="project-bars">
            <div class="pane-bar"></div>
            <div class="pane-bar"></div>
            <div class="pane-bar"></div>
          </div>
          <div class="project-actions">
            <div class="btn-launch">Launch</div>
          </div>
        </div>

        <div class="app-status">
          <div class="status-left">
            <span class="status-gear">&#x2699;</span>
            <span class="status-text">terminal: <span>iterm2</span> &middot; mode: <span>auto</span></span>
          </div>
          <span class="status-power">&#x23FB;</span>
        </div>
      </div>
    </div>
  </div>

  <div class="accent-bar"></div>
</body>
</html>`;
}

async function generate(html, filename) {
  const browser = await puppeteer.launch({ headless: true, args: ["--no-sandbox"] });
  const page = await browser.newPage();
  await page.setViewport({ width: 1200, height: 630, deviceScaleFactor: 2 });
  await page.setContent(html, { waitUntil: "networkidle0" });
  await page.evaluate(() => document.fonts.ready);
  await new Promise((r) => setTimeout(r, 800));
  const output = join(publicDir, filename);
  await page.screenshot({ path: output, type: "png", clip: { x: 0, y: 0, width: 1200, height: 630 } });
  await browser.close();
  console.log(`✓ ${filename}`);
}

console.log("Generating OG images...\n");
await generate(buildHTML("npm install -g lattice"), "og.png");
await generate(buildHTML("lattice.arach.dev"), "og-site.png");
console.log("\nDone!");
