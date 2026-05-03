import puppeteer from "puppeteer";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const publicDir = join(__dirname, "..", "public");

// ── Grid & layout constants ─────────────────────────────────────
// 30px grid: GCD(1200, 630) = 30, so it tiles perfectly in both axes.
// Both crosses land exactly on grid intersections.
const G = 30;
const W = 1200;
const H = 630; // 630 / 30 = 21 rows, 1200 / 30 = 40 cols

// Crosses: 2G (60px) from each edge → perfectly symmetric
const CROSS_D = G * 2; // 60px
const TL = { x: CROSS_D, y: CROSS_D }; // (60, 60)
const BR = { x: W - CROSS_D, y: H - CROSS_D }; // (1140, 570)
const CROSS_LEN = G * 6; // 180px arms

// Content starts 4G (120px) from top — one visual row below the cross
const PAD_TOP = G * 4; // 120px
const PAD_SIDE = G * 4; // 120px
const PAD_BOTTOM = G * 2; // 60px

// ── Logo (3×3 L-shape grid mark) ────────────────────────────────
function logoMark(size = 120) {
  const gap = 6;
  const cell = (size - gap * 2) / 3;
  const r = Math.round(cell * 0.12);
  const bright = "rgba(255,255,255,0.85)";
  const dim = "rgba(255,255,255,0.06)";
  const pattern = [
    bright, dim, dim,
    bright, dim, dim,
    bright, bright, bright,
  ];
  const cells = pattern
    .map((c) => `<div style="border-radius: ${r}px; background: ${c};"></div>`)
    .join("");
  return `<div style="display: grid; grid-template-columns: repeat(3, ${cell}px); gap: ${gap}px; width: ${size}px; height: ${size}px;">${cells}</div>`;
}

// ── Screen Map mockup ───────────────────────────────────────────
function screenMapMockup() {
  return `
    <div style="
      width: 360px;
      background: #18181a;
      border-radius: 14px;
      border: 1px solid rgba(255,255,255,0.08);
      box-shadow: 0 24px 48px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.03);
      overflow: hidden;
      display: flex;
      flex-direction: column;
      font-family: 'JetBrains Mono', monospace;
    ">
      <div style="display: flex; align-items: center; padding: 12px 16px 8px; gap: 8px;">
        <div style="display: flex; gap: 6px;">
          <div style="width: 10px; height: 10px; border-radius: 50%; background: #ff5f57;"></div>
          <div style="width: 10px; height: 10px; border-radius: 50%; background: #febc2e;"></div>
          <div style="width: 10px; height: 10px; border-radius: 50%; background: #28c840;"></div>
        </div>
        <span style="font-size: 12px; font-weight: 600; color: rgba(255,255,255,0.7); margin-left: 6px;">Lattices</span>
        <span style="font-size: 10px; color: rgba(255,255,255,0.2); margin-left: auto;">2 monitors</span>
      </div>
      <div style="flex: 1; display: flex; overflow: hidden;">
        <div style="width: 86px; border-right: 1px solid rgba(255,255,255,0.06); padding: 8px 0; flex-shrink: 0;">
          <div style="font-size: 8px; font-weight: 600; color: rgba(255,255,255,0.25); padding: 0 10px 6px; letter-spacing: 0.1em;">LAYERS</div>
          <div style="display: flex; align-items: center; gap: 5px; padding: 4px 10px; font-size: 9px; color: rgba(255,255,255,0.35);">
            <div style="width: 5px; height: 5px; border-radius: 50%; background: #33c773;"></div>All
            <span style="margin-left: auto; color: rgba(255,255,255,0.15);">19</span>
          </div>
          <div style="display: flex; align-items: center; gap: 5px; padding: 4px 10px; font-size: 9px; color: rgba(255,255,255,0.35);">
            <div style="width: 5px; height: 5px; border-radius: 50%; background: #f5a623;"></div>L0
            <span style="margin-left: auto; color: rgba(255,255,255,0.15);">6</span>
          </div>
          <div style="display: flex; align-items: center; gap: 5px; padding: 4px 10px; font-size: 9px; background: rgba(51,199,115,0.08); color: rgba(255,255,255,0.6); border-radius: 4px; margin: 0 4px;">
            <div style="width: 5px; height: 5px; border-radius: 50%; background: #33c773;"></div>L1
            <span style="margin-left: auto; color: rgba(255,255,255,0.25);">4</span>
          </div>
          <div style="display: flex; align-items: center; gap: 5px; padding: 4px 10px; font-size: 9px; color: rgba(255,255,255,0.35);">
            <div style="width: 5px; height: 5px; border-radius: 50%; background: #f07c4f;"></div>L2
            <span style="margin-left: auto; color: rgba(255,255,255,0.15);">7</span>
          </div>
          <div style="display: flex; align-items: center; gap: 5px; padding: 4px 10px; font-size: 9px; color: rgba(255,255,255,0.35);">
            <div style="width: 5px; height: 5px; border-radius: 50%; background: #e74c8a;"></div>L3
            <span style="margin-left: auto; color: rgba(255,255,255,0.15);">4</span>
          </div>
          <div style="display: flex; align-items: center; gap: 5px; padding: 4px 10px; font-size: 9px; color: rgba(255,255,255,0.35);">
            <div style="width: 5px; height: 5px; border-radius: 50%; background: #e74c8a;"></div>L4
            <span style="margin-left: auto; color: rgba(255,255,255,0.15);">3</span>
          </div>
        </div>
        <div style="flex: 1; position: relative; padding: 10px; display: flex; flex-direction: column;">
          <div style="display: flex; gap: 4px; margin-bottom: 8px; padding: 0 2px;">
            <div style="font-size: 8px; padding: 3px 8px; border-radius: 4px; background: rgba(255,255,255,0.08); color: rgba(255,255,255,0.5); font-weight: 500;">ALL</div>
            <div style="font-size: 8px; padding: 3px 8px; border-radius: 4px; color: rgba(255,255,255,0.2);">1</div>
            <div style="font-size: 8px; padding: 3px 8px; border-radius: 10px; background: rgba(51,199,115,0.15); color: #33c773; font-weight: 600; border: 1px solid rgba(51,199,115,0.3);">2</div>
          </div>
          <div style="flex: 1; display: grid; grid-template-columns: 1fr 1fr 1fr; grid-template-rows: 1fr 1fr; gap: 4px;">
            <div style="grid-column: 1 / 3; background: rgba(51,199,115,0.06); border: 1px solid rgba(51,199,115,0.2); border-radius: 5px; padding: 8px;">
              <div style="font-size: 9px; font-weight: 600; color: rgba(255,255,255,0.6);">Google Chrome</div>
              <div style="font-size: 7px; color: rgba(255,255,255,0.15); margin-top: 2px;">688×720</div>
            </div>
            <div style="background: rgba(245,166,35,0.06); border: 1px solid rgba(245,166,35,0.15); border-radius: 5px; padding: 8px;">
              <div style="font-size: 9px; font-weight: 600; color: rgba(255,255,255,0.6);">Terminal</div>
              <div style="font-size: 7px; color: rgba(255,255,255,0.15); margin-top: 2px;">arach@~</div>
            </div>
            <div style="background: rgba(231,76,138,0.06); border: 1px solid rgba(231,76,138,0.15); border-radius: 5px; padding: 8px;">
              <div style="font-size: 9px; font-weight: 600; color: rgba(255,255,255,0.6);">Finder</div>
              <div style="font-size: 7px; color: rgba(255,255,255,0.15); margin-top: 2px;">wallpapers</div>
            </div>
            <div style="background: rgba(255,255,255,0.02); border: 1px dashed rgba(255,255,255,0.08); border-radius: 5px; padding: 8px;">
              <div style="font-size: 9px; font-weight: 600; color: rgba(255,255,255,0.4);">Messages</div>
            </div>
            <div style="background: rgba(255,255,255,0.02); border: 1px dashed rgba(255,255,255,0.08); border-radius: 5px; padding: 8px;">
              <div style="font-size: 9px; font-weight: 600; color: rgba(255,255,255,0.4);">Preview</div>
            </div>
          </div>
        </div>
      </div>
      <div style="padding: 8px 12px; border-top: 1px solid rgba(255,255,255,0.06); display: flex; gap: 4px; flex-wrap: wrap;">
        <div style="font-size: 8px; padding: 3px 8px; border-radius: 3px; background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.06); color: rgba(255,255,255,0.3);">s spread</div>
        <div style="font-size: 8px; padding: 3px 8px; border-radius: 3px; background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.06); color: rgba(255,255,255,0.3);">t tile</div>
        <div style="font-size: 8px; padding: 3px 8px; border-radius: 3px; background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.06); color: rgba(255,255,255,0.3);">d distrib</div>
        <div style="font-size: 8px; padding: 3px 8px; border-radius: 3px; background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.06); color: rgba(255,255,255,0.3);">g grow</div>
        <div style="font-size: 8px; padding: 3px 8px; border-radius: 3px; background: rgba(51,199,115,0.1); border: 1px solid rgba(51,199,115,0.2); color: #33c773;">f flatten</div>
      </div>
      <div style="display: flex; align-items: center; padding: 6px 14px; border-top: 1px solid rgba(255,255,255,0.04); font-size: 8px; color: rgba(255,255,255,0.2);">
        <div style="display: flex; align-items: center; gap: 5px;">
          <div style="width: 5px; height: 5px; border-radius: 50%; background: #33c773;"></div>
          <span>:9399</span>
        </div>
        <span style="margin-left: auto;">4 pending</span>
      </div>
    </div>`;
}

// ── Terminal mockup ─────────────────────────────────────────────
function terminalMockup() {
  return `
    <div style="
      width: 320px; height: 220px;
      background: #18181a;
      border-radius: 14px;
      border: 1px solid rgba(255,255,255,0.08);
      box-shadow: 0 24px 48px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.03);
      overflow: hidden;
      display: flex;
      flex-direction: column;
      font-family: 'JetBrains Mono', monospace;
    ">
      <div style="padding: 14px 16px 10px; display: flex; gap: 7px;">
        <div style="width: 10px; height: 10px; border-radius: 50%; background: #ff5f57;"></div>
        <div style="width: 10px; height: 10px; border-radius: 50%; background: #febc2e;"></div>
        <div style="width: 10px; height: 10px; border-radius: 50%; background: #28c840;"></div>
      </div>
      <div style="flex: 1; padding: 8px 18px; font-size: 13px; line-height: 1.8;">
        <div style="color: #33c773;">$ lattices start my-app</div>
        <div style="color: rgba(255,255,255,0.35);">&#x2714; Created session my-app</div>
        <div style="color: rgba(255,255,255,0.35);">&#x2714; 3 panes configured</div>
        <div style="color: rgba(255,255,255,0.35);">&#x2714; Attached to my-app</div>
        <div style="color: #33c773; margin-top: 4px;">$ <span style="opacity: 0.5;">&#x2588;</span></div>
      </div>
    </div>`;
}

// ── API mockup ──────────────────────────────────────────────────
function apiMockup() {
  return `
    <div style="
      width: 320px; height: 220px;
      background: #18181a;
      border-radius: 14px;
      border: 1px solid rgba(255,255,255,0.08);
      box-shadow: 0 24px 48px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.03);
      overflow: hidden;
      display: flex;
      flex-direction: column;
      font-family: 'JetBrains Mono', monospace;
    ">
      <div style="padding: 12px 16px 8px; display: flex; align-items: center; gap: 10px; border-bottom: 1px solid rgba(255,255,255,0.06);">
        <div style="font-size: 11px; color: #33c773; padding: 3px 8px; background: rgba(51,199,115,0.1); border-radius: 4px;">WS</div>
        <div style="font-size: 12px; color: rgba(255,255,255,0.5);">127.0.0.1:9399</div>
      </div>
      <div style="flex: 1; padding: 10px 18px; font-size: 11.5px; line-height: 1.9;">
        <div style="color: rgba(255,255,255,0.25);">&#x2192; windows.list</div>
        <div style="color: rgba(255,255,255,0.25);">&#x2192; windows.tile</div>
        <div style="color: rgba(255,255,255,0.25);">&#x2192; screenmap.snapshot</div>
        <div style="color: rgba(255,255,255,0.25);">&#x2192; terminals.search</div>
        <div style="color: rgba(255,255,255,0.25);">&#x2192; sessions.create</div>
      </div>
    </div>`;
}

// ── Pages config ────────────────────────────────────────────────
const pages = [
  {
    filename: "og.png",
    tag: "npm install -g lattices",
    title: "lattices",
    subtitle:
      "Screen map, window tiling, and workspace management for macOS developers.",
    mockup: "screenmap",
  },
  {
    filename: "og-docs.png",
    tag: "docs",
    title: "lattices",
    subtitle:
      "CLI reference, Screen Map guide, RPC API, and configuration docs.",
    mockup: "screenmap",
  },
  {
    filename: "og-cli.png",
    tag: "CLI",
    title: "lattices cli",
    subtitle:
      "Declarative tmux sessions. Define your layouts in JSON, launch with one command.",
    mockup: "terminal",
  },
  {
    filename: "og-api.png",
    tag: "WebSocket API",
    title: "lattices api",
    subtitle:
      "20+ RPC methods over WebSocket. Window tiling, screen map, terminal discovery, and more.",
    mockup: "api",
  },
];

// ── HTML builder ────────────────────────────────────────────────
function buildHTML(config) {
  const { tag, title, subtitle } = config;

  const rightContent =
    config.mockup === "screenmap"
      ? screenMapMockup()
      : config.mockup === "terminal"
        ? terminalMockup()
        : apiMockup();

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
      width: ${W}px;
      height: ${H}px;
      font-family: 'Space Grotesk', -apple-system, sans-serif;
      background: #111113;
      color: #ebebef;
      position: relative;
      overflow: hidden;
    }

    /* ── 30px grid — tiles perfectly (1200/30=40, 630/30=21) ── */
    .grid {
      position: absolute;
      inset: 0;
      background-image:
        linear-gradient(rgba(255, 255, 255, 0.025) 1px, transparent 1px),
        linear-gradient(90deg, rgba(255, 255, 255, 0.025) 1px, transparent 1px);
      background-size: ${G}px ${G}px;
    }

    /* ── Crosses: symmetric at ${CROSS_D}px from each edge ── */

    /* TL at (${TL.x}, ${TL.y}) — arms go right + down, fade out */
    .cross-tl-h {
      position: absolute;
      top: ${TL.y}px; left: ${TL.x}px;
      width: ${CROSS_LEN}px; height: 1px;
      background: linear-gradient(to right, rgba(255,255,255,0.25), rgba(255,255,255,0.06) 50%, transparent);
    }
    .cross-tl-v {
      position: absolute;
      top: ${TL.y}px; left: ${TL.x}px;
      width: 1px; height: ${CROSS_LEN}px;
      background: linear-gradient(to bottom, rgba(255,255,255,0.25), rgba(255,255,255,0.06) 50%, transparent);
    }

    /* BR at (${BR.x}, ${BR.y}) — arms go left + up, fade out */
    .cross-br-h {
      position: absolute;
      top: ${BR.y}px; left: ${BR.x - CROSS_LEN}px;
      width: ${CROSS_LEN}px; height: 1px;
      background: linear-gradient(to right, transparent, rgba(255,255,255,0.06) 50%, rgba(255,255,255,0.25));
    }
    .cross-br-v {
      position: absolute;
      top: ${BR.y - CROSS_LEN}px; left: ${BR.x}px;
      width: 1px; height: ${CROSS_LEN}px;
      background: linear-gradient(to bottom, transparent, rgba(255,255,255,0.06) 50%, rgba(255,255,255,0.25));
    }

    /* ── Subtle glows ────────────────────── */
    .glow-1 {
      position: absolute;
      top: -${G * 2}px; left: -${G * 2}px;
      width: ${G * 12}px; height: ${G * 12}px;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(255,255,255,0.03) 0%, transparent 70%);
    }
    .glow-2 {
      position: absolute;
      bottom: -${G * 4}px; right: ${G * 6}px;
      width: ${G * 14}px; height: ${G * 14}px;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(255,255,255,0.02) 0%, transparent 70%);
    }

    /* ── Layout ──────────────────────────── */
    .content {
      position: relative;
      z-index: 10;
      display: flex;
      align-items: flex-start; /* logo top = mockup top */
      height: 100%;
      padding: ${PAD_TOP}px ${PAD_SIDE}px ${PAD_BOTTOM}px;
      gap: ${G * 2}px;
    }

    .left {
      flex: 1;
      display: flex;
      flex-direction: column;
      min-width: 0;
    }

    .right {
      display: flex;
      align-items: flex-start;
      flex-shrink: 0;
    }

    .logo { margin-bottom: ${G}px; }

    .title {
      font-family: 'JetBrains Mono', monospace;
      font-size: 48px;
      font-weight: 700;
      letter-spacing: -0.03em;
      line-height: 1;
      margin-bottom: 16px;
    }

    .subtitle {
      font-size: 17px;
      color: rgba(255, 255, 255, 0.4);
      line-height: 1.5;
      max-width: 400px;
      margin-bottom: 24px;
    }

    .tag {
      display: inline-flex;
      align-items: center;
      padding: 6px 16px;
      border-radius: 6px;
      border: 1px solid rgba(255, 255, 255, 0.12);
      background: rgba(255, 255, 255, 0.04);
      font-family: 'JetBrains Mono', monospace;
      font-size: 13px;
      font-weight: 500;
      color: rgba(255, 255, 255, 0.45);
      width: fit-content;
      letter-spacing: 0.02em;
    }

    .accent-bar {
      position: absolute;
      bottom: 0; left: 0; right: 0;
      height: 4px;
      background: linear-gradient(90deg, #33c773, #1a8f4a);
    }
  </style>
</head>
<body>
  <div class="grid"></div>
  <div class="glow-1"></div>
  <div class="glow-2"></div>

  <div class="cross-tl-h"></div>
  <div class="cross-tl-v"></div>
  <div class="cross-br-h"></div>
  <div class="cross-br-v"></div>

  <div class="content">
    <div class="left">
      <div class="logo">${logoMark(120)}</div>
      <div class="title">${title}</div>
      <div class="subtitle">${subtitle}</div>
      <div class="tag">${tag}</div>
    </div>
    <div class="right">
      ${rightContent}
    </div>
  </div>

  <div class="accent-bar"></div>
</body>
</html>`;
}

// ── Generate ────────────────────────────────────────────────────
async function generate(configs) {
  const browser = await puppeteer.launch({
    headless: true,
    args: ["--no-sandbox"],
  });

  for (const config of configs) {
    const page = await browser.newPage();
    await page.setViewport({ width: W, height: H, deviceScaleFactor: 2 });

    const html = buildHTML(config);
    await page.setContent(html, { waitUntil: "networkidle0" });
    await page.evaluate(() => document.fonts.ready);
    await new Promise((r) => setTimeout(r, 800));

    const output = join(publicDir, config.filename);
    await page.screenshot({
      path: output,
      type: "png",
      clip: { x: 0, y: 0, width: W, height: H },
    });
    await page.close();
    console.log(`  ✓ ${config.filename}`);
  }

  await browser.close();
}

console.log("Generating OG images...\n");
await generate(pages);
console.log("\nDone!");
