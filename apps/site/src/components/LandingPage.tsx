import { useEffect, useRef, useState } from "react";
import type { CSSProperties, ReactNode } from "react";
import { motion, useReducedMotion } from "motion/react";
import { ThemeToggle } from "./ThemeToggle";
import { GestureMatrix } from "./GestureMatrix";
import { ProductsMenu } from "./SiteChrome";
import { heroDesktopMaps, heroWindowLayouts, heroWindowMeta } from "./heroDesktopMap";
import type { HeroDesktopPhase, HeroWindowId } from "./heroDesktopMap";

export function LatticesLogo({ size = 20 }: { size?: number }) {
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

// 12x12 pixel cat: solid body, eyes cut as negative space, tail drawn separately
// so it can flick without disturbing the silhouette.
const MASCOT_BODY = [
  "#....#......",
  "##..##......",
  "######......",
  "#.##.#......",
  "######......",
  ".####.......",
  ".#####......",
  ".######.....",
  ".######.....",
  ".#######....",
  ".#######....",
  ".##..##.....",
];

// Eye holes, filled in to close the lids on a blink.
const MASCOT_EYES: Array<[number, number]> = [
  [1, 3],
  [4, 3],
];

// Tail poses, low to high. Base pixel stays welded to the haunch.
const MASCOT_TAILS: Array<Array<[number, number]>> = [
  [[8, 10], [9, 10], [10, 10], [10, 9]],
  [[8, 10], [9, 10], [10, 9], [10, 8]],
  [[8, 10], [9, 9], [10, 8], [10, 7], [10, 6]],
];

const MASCOT_W = MASCOT_BODY[0].length;
const MASCOT_H = MASCOT_BODY.length;

function PixelMascot() {
  const wrapRef = useRef<HTMLSpanElement>(null);
  const reducedMotion = useReducedMotion() ?? false;
  const [blinking, setBlinking] = useState(false);
  const [tail, setTail] = useState(0);

  // Pointer lean — a few pixels, capped hard on the right so the cat stays
  // on the plinth.
  useEffect(() => {
    const wrap = wrapRef.current;
    if (!wrap || reducedMotion) return;

    const maxLeft = 8;
    const maxRight = 2;
    const maxY = 4;
    const ease = 0.14;
    let targetX = 0;
    let targetY = 0;
    let currentX = 0;
    let currentY = 0;
    let raf = 0;

    const tick = () => {
      currentX += (targetX - currentX) * ease;
      currentY += (targetY - currentY) * ease;
      wrap.style.setProperty("--cat-x", `${currentX.toFixed(2)}px`);
      wrap.style.setProperty("--cat-y", `${currentY.toFixed(2)}px`);
      wrap.style.setProperty("--cat-rotate", `${(currentX * 0.4).toFixed(2)}deg`);
      if (Math.abs(targetX - currentX) > 0.04 || Math.abs(targetY - currentY) > 0.04) {
        raf = requestAnimationFrame(tick);
      } else {
        raf = 0;
      }
    };

    const kick = () => {
      if (!raf) raf = requestAnimationFrame(tick);
    };

    const onMove = (event: PointerEvent) => {
      const rect = wrap.getBoundingClientRect();
      const nx = (event.clientX - (rect.left + rect.width / 2)) / Math.max(window.innerWidth * 0.5, 1);
      const ny = (event.clientY - (rect.top + rect.height / 2)) / Math.max(window.innerHeight * 0.5, 1);
      targetX = Math.max(-maxLeft, Math.min(maxRight, nx * 7));
      targetY = Math.max(-maxY, Math.min(maxY, ny * maxY));
      kick();
    };

    window.addEventListener("pointermove", onMove, { passive: true });
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("pointermove", onMove);
    };
  }, [reducedMotion]);

  // Idle blink — irregular gaps, occasional double blink.
  useEffect(() => {
    if (reducedMotion) return;
    let timer: ReturnType<typeof setTimeout>;
    const queue = (delay: number, fn: () => void) => {
      timer = setTimeout(fn, delay);
    };
    const shut = (remaining: number) => {
      setBlinking(true);
      queue(110, () => {
        setBlinking(false);
        if (remaining > 0) queue(150, () => shut(remaining - 1));
        else schedule();
      });
    };
    const schedule = () => {
      queue(3200 + Math.random() * 5600, () => shut(Math.random() < 0.18 ? 1 : 0));
    };
    schedule();
    return () => clearTimeout(timer);
  }, [reducedMotion]);

  // Idle tail — mostly still, then a short flick back down to rest.
  useEffect(() => {
    if (reducedMotion) return;
    let timer: ReturnType<typeof setTimeout>;
    const run = (steps: Array<[number, number]>, i: number) => {
      if (i >= steps.length) {
        schedule();
        return;
      }
      const [pose, hold] = steps[i];
      setTail(pose);
      timer = setTimeout(() => run(steps, i + 1), hold);
    };
    const schedule = () => {
      timer = setTimeout(() => {
        const big = Math.random() < 0.45;
        run(
          big
            ? [[1, 130], [2, 210], [1, 120], [2, 170], [1, 150], [0, 0]]
            : [[1, 190], [0, 0]],
          0,
        );
      }, 4200 + Math.random() * 7000);
    };
    schedule();
    return () => clearTimeout(timer);
  }, [reducedMotion]);

  return (
    <span ref={wrapRef} className="pixel-mascot-wrap" aria-hidden="true">
      <svg
        className="pixel-mascot"
        viewBox={`0 0 ${MASCOT_W} ${MASCOT_H}`}
        shapeRendering="crispEdges"
        fill="currentColor"
      >
        {MASCOT_BODY.flatMap((row, y) =>
          [...row].map((cell, x) =>
            cell === "#" ? <rect key={`b${x}-${y}`} x={x} y={y} width={1} height={1} /> : null,
          ),
        )}
        {blinking
          ? MASCOT_EYES.map(([x, y]) => <rect key={`e${x}`} x={x} y={y} width={1} height={1} />)
          : null}
        {MASCOT_TAILS[tail].map(([x, y]) => (
          <rect key={`t${x}-${y}`} x={x} y={y} width={1} height={1} />
        ))}
      </svg>
    </span>
  );
}

function GitHubIcon() {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
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

<span class="hl-cmt">// Find a window by title, app, session, or cwd</span>
<span class="hl-kw">const</span> [match] = <span class="hl-kw">await</span> daemonCall(<span class="hl-str">'lattices.search'</span>, {
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
    caption: "Read the Accessibility tree and optional screenshot so the agent chooses from stable element ids.",
    filename: "observe.ts",
    code: `<span class="hl-kw">const</span> ui = <span class="hl-kw">await</span> daemonCall(<span class="hl-str">'computer.windowState'</span>, {
  app: <span class="hl-str">'Calculator'</span>,
  mode: <span class="hl-str">'ax'</span>,
})`,
  },
  {
    id: "stage",
    number: "02",
    title: "Stage",
    heading: "Prepare a reviewable action",
    caption: "Bind the next move to a snapshot element while nothing has run yet.",
    filename: "stage.ts",
    code: `<span class="hl-kw">await</span> daemonCall(<span class="hl-str">'computer.elementAction'</span>, {
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
    caption: "Click, type, hotkey, or set a value on-device after the same safety checks.",
    filename: "execute.ts",
    code: `<span class="hl-kw">await</span> daemonCall(<span class="hl-str">'computer.elementAction'</span>, {
  snapshotId: ui.snapshotId,
  elementId: <span class="hl-str">'e7'</span>,
  action: <span class="hl-str">'press'</span>,
  treatment: <span class="hl-str">'execute'</span>,
})`,
  },
  {
    id: "verify",
    number: "04",
    title: "Verify",
    heading: "Check the result on-device",
    caption: "Confirm the outcome with OCR or AX, then feed that receipt into the next observation.",
    filename: "verify.ts",
    code: `<span class="hl-kw">const</span> receipt = <span class="hl-kw">await</span> daemonCall(<span class="hl-str">'computer.verify'</span>, {
  app: <span class="hl-str">'Calculator'</span>,
  mode: <span class="hl-str">'ocr'</span>,
  contains: <span class="hl-str">'42'</span>,
})`,
  },
];

const showLatsDevTeaser = import.meta.env.PUBLIC_SHOW_LATS_DEV_TEASER === "true";

function HeroWindowContent({ id }: { id: HeroWindowId }) {
  if (id === "agent") {
    return (
      <div className="desktop-terminal-lines desktop-agent-lines">
        <span><b>~/dev/atlas</b> codex</span>
        <span className="agent-prompt">› fix the flaky session test</span>
        <span className="terminal-dim">• reading src/auth/session.ts</span>
        <span className="terminal-dim">• editing refreshSession()</span>
        <span>$ bun test auth</span>
        <span className="terminal-ready">✓ 12 passed, 0 failed</span>
      </div>
    );
  }

  if (id === "editor") {
    return (
      <div className="desktop-editor">
        <div className="desktop-editor-sidebar">
          <strong>ATLAS</strong>
          <span>src</span>
          <span className="is-active">session.ts</span>
          <span>auth.ts</span>
          <span>routes.ts</span>
        </div>
        <div className="desktop-code-lines" aria-hidden="true">
          <span><i>export async function</i> refreshSession() {'{'}</span>
          <span className="indent"><i>const</i> s = <i>await</i> sessions.get(token)</span>
          <span className="indent"><i>if</i> (s.expired) <i>return</i> renew(s)</span>
          <span className="indent"><i>return</i> s</span>
          <span>{'}'}</span>
        </div>
      </div>
    );
  }

  if (id === "browser") {
    return (
      <div className="desktop-browser-view">
        <div className="desktop-browser-mark">atlas · localhost:5173</div>
        <div className="desktop-browser-ready"><i /> Ready</div>
        <span>vite preview</span>
      </div>
    );
  }

  return (
    <div className="desktop-terminal-lines">
      <span><b>~/dev/atlas</b> bun dev</span>
      <span className="terminal-dim">VITE v7.3.3</span>
      <span><i>➜</i> Local: http://localhost:5173</span>
      <span className="terminal-ready">✓ Ready in 612ms</span>
    </div>
  );
}

function HeroDesktopWindow({
  id,
  phase,
  reducedMotion,
  children,
}: {
  id: HeroWindowId;
  phase: HeroDesktopPhase;
  reducedMotion: boolean;
  children: ReactNode;
}) {
  const layout = heroWindowLayouts[id][phase];
  const meta = heroWindowMeta[id];

  return (
    <motion.div
      className={`hero-desktop-window hero-window-${id}${meta.focused ? " is-focused" : ""}`}
      style={{ "--window-tint": meta.tint, zIndex: layout.z } as CSSProperties}
      animate={{
        left: `${layout.left}%`,
        top: `${layout.top}%`,
        width: `${layout.width}%`,
        height: `${layout.height}%`,
      }}
      transition={{ duration: reducedMotion ? 0 : 0.74, ease: [0.16, 1, 0.3, 1] }}
    >
      <div className="hero-window-bar">
        <span className="hero-window-lights"><i /><i /><i /></span>
        <span className="hero-window-title">{meta.title}</span>
        <span className="hero-window-app">{meta.app}</span>
      </div>
      <div className="hero-window-body">{children}</div>
    </motion.div>
  );
}

function HeroWorkspaceStage() {
  const prefersReducedMotion = useReducedMotion() ?? false;
  const [phaseChoice, setPhaseChoice] = useState<HeroDesktopPhase>("messy");
  // The loop alternates who organizes the mess: your keycast, then the agent.
  const [driver, setDriver] = useState<"you" | "agent">("you");
  const [autoPlay, setAutoPlay] = useState(true);
  const [inView, setInView] = useState(true);
  const stageRef = useRef<HTMLDivElement | null>(null);
  // Reduced-motion visitors land on the organized result instead of the loop.
  const phase = prefersReducedMotion && autoPlay ? "organized" : phaseChoice;
  const organized = phase === "organized";

  useEffect(() => {
    const stage = stageRef.current;
    if (!stage || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(
      ([entry]) => setInView(entry.isIntersecting),
      { threshold: 0.35 },
    );
    observer.observe(stage);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (!autoPlay || prefersReducedMotion || !inView) return;
    // Linger on the organized result — longest after the agent's turn, so
    // the tiled desktop and the full two-command transcript sit together.
    // The messy beat holds long enough to read the scatter; longer on agent
    // turns, where the request and tool call appear before the snap.
    const delay = organized
      ? driver === "agent" ? 7200 : 4600
      : driver === "you" ? 3000 : 4200;
    const timer = window.setTimeout(() => {
      if (organized) {
        setDriver(driver === "you" ? "agent" : "you");
        setPhaseChoice("messy");
      } else {
        setPhaseChoice("organized");
      }
    }, delay);
    return () => window.clearTimeout(timer);
  }, [autoPlay, organized, driver, prefersReducedMotion, inView]);

  const selectPhase = (next: HeroDesktopPhase) => {
    setAutoPlay(false);
    setPhaseChoice(next);
  };

  return (
    <div className="hero-desktop-demo" id="workspace-demo">
      <div className="hero-desktop-comparison" role="group" aria-label="Compare the desktop without and with Lattices">
        <button
          type="button"
          className={!organized ? "is-active" : ""}
          aria-pressed={!organized}
          onClick={() => selectPhase("messy")}
        >
          <span aria-hidden="true">○</span>
          Without Lattices
        </button>
        <button
          type="button"
          className={organized ? "is-active" : ""}
          aria-pressed={organized}
          onClick={() => selectPhase("organized")}
        >
          <span aria-hidden="true">●</span>
          With Lattices
        </button>
      </div>

      <div
        ref={stageRef}
        className={`hero-workspace-stage is-${phase}`}
        role="img"
        aria-label={organized
          ? "A simulated Mac desktop with four windows tiled by Lattices, an agent terminal in focus"
          : "A simulated Mac desktop with four overlapping, scattered windows"}
      >
        <div className="hero-laptop-camera" aria-hidden="true"><i /></div>
        <div className="hero-desktop-screen">
          <div className="hero-macos-bar">
            <span className="hero-macos-brand"><span className="hero-macos-apple" aria-hidden="true"><AppleIcon /></span> Terminal</span>
            <span className="hero-macos-menu">File&nbsp;&nbsp; Edit&nbsp;&nbsp; View&nbsp;&nbsp; Window</span>
            <span className="hero-macos-status"><span className="hero-macos-lattices">⌁ lattices</span>&nbsp;&nbsp; 9:41 AM</span>
          </div>

          {(Object.keys(heroWindowMeta) as HeroWindowId[]).map((id) => (
            <HeroDesktopWindow
              key={id}
              id={id}
              phase={phase}
              reducedMotion={prefersReducedMotion}
            >
              <HeroWindowContent id={id} />
            </HeroDesktopWindow>
          ))}

          <motion.div
            className="hero-keycast"
            aria-hidden="true"
            initial={false}
            animate={{ opacity: !organized && autoPlay && driver === "you" ? 1 : 0 }}
            transition={
              !organized && autoPlay && driver === "you"
                ? { duration: 0.26, delay: 1.4 }
                : { duration: 0.18 }
            }
          >
            <kbd>⌃</kbd>
            <kbd>⌥</kbd>
            <kbd>G</kbd>
            <span>organize</span>
          </motion.div>

          <motion.div
            className="hero-desktop-result"
            animate={{ opacity: organized ? 1 : 0, y: organized ? 0 : 6 }}
            transition={{ duration: prefersReducedMotion ? 0 : 0.24, delay: organized ? 0.5 : 0 }}
            aria-hidden={!organized}
          >
            <i /> 4 windows organized
          </motion.div>
        </div>
      </div>

      <div className="hero-agent-harness" role="group" aria-label="A coding agent reading the same desktop over the local API">
        <div className="hero-harness-head">
          <span className="hero-harness-dot" aria-hidden="true" />
          <span>claude · agent session</span>
          <span className="hero-harness-transport">ws://localhost · live</span>
        </div>
        <div className="hero-harness-body">
          <span className="hero-harness-user">
            <b>&gt;</b> what&apos;s on my screen?
          </span>
          <span className="hero-harness-tool">
            <i aria-hidden="true">⏺</i> lattices — map
          </span>
          <motion.div
            key={driver === "agent" ? "agent" : phase}
            className="hero-harness-result hero-harness-map-result"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: prefersReducedMotion ? 0 : 0.3, delay: prefersReducedMotion ? 0 : 0.6 }}
          >
            <span>
              <b aria-hidden="true">⎿</b> 4 windows · {driver === "agent" || !organized ? "3 overlapping" : "tiled main-left"} · focused: atlas — codex
            </span>
            <pre className="hero-harness-map" aria-hidden="true">{heroDesktopMaps[phase]}</pre>
          </motion.div>
          <motion.span
            className="hero-harness-user"
            initial={false}
            animate={{ opacity: driver === "agent" ? 1 : 0 }}
            transition={{ duration: driver === "agent" ? 0.3 : 0.2, delay: driver === "agent" ? 0.9 : 0 }}
            style={{ visibility: driver === "agent" ? "visible" : "hidden" }}
            aria-hidden={driver !== "agent"}
          >
            <b>&gt;</b> put codex on the left half, stack the rest on the right
          </motion.span>
          <motion.span
            className="hero-harness-tool"
            initial={false}
            animate={{ opacity: driver === "agent" ? 1 : 0 }}
            transition={{ duration: driver === "agent" ? 0.3 : 0.2, delay: driver === "agent" ? 2.1 : 0 }}
            style={{ visibility: driver === "agent" ? "visible" : "hidden" }}
            aria-hidden={driver !== "agent"}
          >
            <i aria-hidden="true">⏺</i> lattices — space.optimize
          </motion.span>
          <motion.span
            className="hero-harness-result"
            initial={false}
            animate={{ opacity: driver === "agent" && organized ? 1 : 0 }}
            transition={{
              duration: driver === "agent" && organized ? 0.3 : 0.2,
              delay: driver === "agent" && organized ? 0.9 : 0,
            }}
            style={{ visibility: driver === "agent" && organized ? "visible" : "hidden" }}
            aria-hidden={driver !== "agent" || !organized}
          >
            <b aria-hidden="true">⎿</b> codex left half · 3 stacked right · done
          </motion.span>
        </div>
      </div>
    </div>
  );
}

const handsShortcuts: Array<{ keys: string[]; action: string }> = [
  { keys: ["⌃", "⌥", "← / →"], action: "Tile halves" },
  { keys: ["⌃", "⌥", "G"], action: "4×4 grid on the front window" },
  { keys: ["⌃", "⌥", "V"], action: "Fill the next 3×2 cell" },
  { keys: ["⌘", "⌥", "1 / 2 / 3"], action: "Switch workspace layer" },
  { keys: ["⌘", "⇧", "M"], action: "Command palette" },
  { keys: ["Hyper", "L"], action: "Studio / screen map" },
];

function HandsOnSection() {
  return (
    <section className="hands-section fade-in" id="hands">
      <div className="hands-copy">
        <div className="cua-kicker">Keyboard and mouse</div>
        <h2>Shortcuts and mouse gestures, not just the palette.</h2>
        <p>
          Caps Lock is Hyper. ⌃⌥ tiles halves and grids. Hold a mouse button,
          draw a direction or a shape, release. The app replays that path in
          a 3×3 <em>matrix</em> — the same completer as the logo.
        </p>
        <div className="hands-links">
          <a href="/docs/app">Shortcut reference &rarr;</a>
          <a href="/docs/mouse-gestures">Mouse gestures &rarr;</a>
        </div>
      </div>

      <div className="hands-stage">
        <div className="hands-panel">
          <h3>Keyboard</h3>
          <ul className="hands-list">
            {handsShortcuts.map((row) => (
              <li key={row.action}>
                <span className="hands-chords">
                  {row.keys.map((key) => (
                    <kbd key={key}>{key}</kbd>
                  ))}
                </span>
                <span>{row.action}</span>
              </li>
            ))}
          </ul>
          <p className="hands-note">Hold Caps Lock for Hyper. Defaults — change them in Settings.</p>
        </div>

        <div className="hands-panel">
          <h3>The matrix</h3>
          <GestureMatrix />
        </div>
      </div>
    </section>
  );
}

function HeroGestureDemo() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const reducedMotion = useReducedMotion() ?? false;

  const playPreview = () => {
    if (reducedMotion) return;
    void videoRef.current?.play();
  };

  const resetPreview = () => {
    const video = videoRef.current;
    if (!video) return;
    video.pause();
    video.currentTime = 0;
  };

  return (
    <a
      className="hero-demo-peek"
      href="/blog/gesture-completion-matrix"
      aria-label="Watch the 12-second mouse gesture demo"
      onMouseEnter={playPreview}
      onMouseLeave={resetPreview}
      onFocus={playPreview}
      onBlur={resetPreview}
    >
      <video
        ref={videoRef}
        className="hero-demo-peek-media"
        muted
        playsInline
        preload="metadata"
        poster="/blog/gesture-completion-matrix-poster.png"
        aria-hidden="true"
      >
        <source src="/blog/gesture-completion-matrix.mp4" type="video/mp4" />
      </video>
      <span className="hero-demo-peek-copy">
        <span className="hero-demo-peek-label">12 sec demo</span>
        <strong>Draw a gesture. Lattices does the rest.</strong>
        <span className="hero-demo-peek-link">Watch the demo &rarr;</span>
      </span>
    </a>
  );
}

export default function App() {
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
            <a href="/blog" className="nav-link nav-blog-link">
              Blog
            </a>
            <a href="/docs/overview" className="nav-link">
              Docs
            </a>
            <ProductsMenu />
            <a
              href="https://github.com/arach/lattices"
              target="_blank"
              rel="noopener noreferrer"
              className="nav-github"
            >
              <GitHubIcon />
              <span className="github-label">GitHub</span>
            </a>
            <ThemeToggle
              theme={theme}
              onToggle={() => setTheme(theme === "dark" ? "light" : "dark")}
            />
          </div>
        </div>
      </nav>

      {/* Hero */}
      <main>
        <section className="hero fade-in">
         <div className="hero-editorial">
          <div className="hero-copy">
            <p className="hero-eyebrow">Native macOS workspace manager</p>
            <h1>The workspace manager for you and your agents.</h1>
            <p className="hero-sub">
              Every window, terminal, and layout on your Mac organized and
              accessible, by shortcut, mouse gesture, or API.
            </p>
            <div className="hero-actions">
              <a
                href="https://github.com/arach/lattices/releases/latest/download/Lattices.dmg"
                className="hero-primary-cta"
                onClick={() => trackCta('download_dmg_hero', 'https://github.com/arach/lattices/releases/latest/download/Lattices.dmg')}
              >
                <DownloadIcon />
                Download for macOS
              </a>
              <a href="/docs/overview" className="hero-secondary-cta">
                Read the docs
              </a>
            </div>
            <ul className="hero-meta">
              <li>5,500+ installs</li>
              <li>Local first</li>
              <li>API driven</li>
              <li>Built for macOS</li>
            </ul>
            <HeroGestureDemo />
          </div>

          <div className="hero-apparatus">
            <div className="hero-rail" aria-hidden="true">
              <span>Windows</span>
              <span>Terminal</span>
              <span>Layout</span>
              <span>Agent API</span>
            </div>
            <div className="hero-apparatus-body">
              <HeroWorkspaceStage />
              <ol className="hero-index" aria-hidden="true">
                <li>01</li>
                <li>02</li>
                <li>03</li>
              </ol>
            </div>
            <div className="hero-plinth" aria-hidden="true">
              <span>Lattices engine</span>
              <span className="hero-plinth-state">state: synced</span>
              <PixelMascot />
            </div>
          </div>
         </div>
        </section>

        <section className="section shared-state-section" id="shared-state">
         <div className="shared-state-inner">
          <div className="shared-state-copy fade-in">
            <div className="cua-kicker">One state, two operators</div>
            <h2>Same desktop, whether you drive or your agent does.</h2>
            <p>
              Agents can write code and run tests, but arranging the Mac around
              that work is still brittle. Lattices gives you and your agents
              the same workspace controls, from one-window moves to
              multi-window layouts. Every change lands visibly on the desktop
              with a receipt.
            </p>
          </div>
          <div className="operator-rows fade-in fade-in-delay-1" aria-label="The same workspace request from a person or an agent">
            <div className="operator-row is-you">
              <span className="operator-row-label">You</span>
              <span className="operator-row-action">
                <span>&ldquo;Put all my terminals in a grid.&rdquo;</span>
              </span>
            </div>
            <div className="operator-row is-agent">
              <span className="operator-row-label">Your agent</span>
              <span className="operator-row-action">
                <code>space.optimize {'{'} app: &apos;iTerm2&apos;, strategy: &apos;mosaic&apos; {'}'}</code>
              </span>
            </div>
            <p className="operator-result">
              <i aria-hidden="true" /> All terminals, one grid — one live state.
            </p>
          </div>
         </div>
        </section>

        <div className="shell">
        <HandsOnSection />

        {/* Computer use (CUA) */}
        <section className="section cua-section" id="cua">
          <div className="cua-head fade-in">
            <div className="cua-kicker">Action · a Lattices product</div>
            <h2>Computer use you can control</h2>
            <p>
              Action is the focused computer-use product in the Lattices family.
              Observe the screen, stage each action for review, execute on-device,
              then verify the result.
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
                <div className="cua-stage-links">
                  <a href="/action" className="agent-api-link cua-stage-api-link">
                    Meet Action &rarr;
                  </a>
                  <a href="/docs/api" className="agent-api-link cua-stage-api-link cua-stage-api-secondary">
                    Computer-use API &rarr;
                  </a>
                </div>
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
          <div className="app-grid">
            <div className="app-copy">
              <div className="app-kicker-row">
                <span>Native macOS app</span>
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
              <h2 className="app-title">The whole workspace, visible.</h2>
              <p className="app-desc">
                See every project, session, window, and layer in one native
                SwiftUI control surface.
              </p>
              <ul className="app-features">
                <li>See every project and live session</li>
                <li>Launch, attach, or detach with a click</li>
                <li>Tile with ⌃⌥ chords, a 4×4 grid, or a mouse drag</li>
                <li>Search windows, terminals, and screen text</li>
                <li>Middle-drag for Spaces, Screen Map, and dictation</li>
              </ul>
            </div>
            <div className="app-demo-reel" aria-label="Animated preview of lattices arranging windows, layers, search, and voice commands">
              <img
                src="/app-latest.png"
                alt="lattices app showing screen map with dual displays, layers, and inspector"
                className="app-screenshot"
                width="1172"
                height="764"
                loading="lazy"
              />
              <div className="app-demo-cursor" aria-hidden="true" />
              <div className="app-demo-focus app-demo-focus-one" aria-hidden="true" />
              <div className="app-demo-focus app-demo-focus-two" aria-hidden="true" />
              <div className="app-demo-tile app-demo-tile-left" aria-hidden="true" />
              <div className="app-demo-tile app-demo-tile-right" aria-hidden="true" />
            </div>
          </div>
        </section>

        {/* Product spine */}
        <section className="workflow-spine fade-in fade-in-delay-2" id="features">
          <article>
            <span className="workflow-number">01</span>
            <div>
              <h3>Window manager</h3>
              <h2>Put every window in its place.</h2>
              <p>
                Tile windows, group them into layers, launch whole projects,
                and switch contexts from the app, a shortcut, or a mouse
                gesture.
              </p>
            </div>
          </article>
          <article>
            <span className="workflow-number">02</span>
            <div>
              <h3>Computer use</h3>
              <h2>Give agents fast, inspectable control.</h2>
              <p>
                Agents observe the screen, resolve accessible targets, stage
                actions, execute on-device, and verify the result before
                moving on.
              </p>
            </div>
          </article>
          <article>
            <span className="workflow-number">03</span>
            <div>
              <h3>Collaboration</h3>
              <h2>Share one live workspace.</h2>
              <p>
                You and your agents work with the same windows and layers.
                Actions stay visible to both sides, with a receipt for what
                happened.
              </p>
            </div>
          </article>
        </section>

        {/* Config */}
        <section className="section" id="config">
          <div className="config-head fade-in fade-in-delay-2">
            <h2 className="config-title">
              Managed project layouts
            </h2>
            <p className="config-desc">
              Define a project scene — terminals, browser and editor windows,
              commands, and placement — then bring the whole workspace back in
              one step.
            </p>
          </div>

          <div className="config-grid fade-in fade-in-delay-2">
            <div>
              <div className="layouts">
                <button type="button" className={`layout-card${paneLayout === 1 ? " active" : ""}`} onClick={() => setPaneLayout(1)} aria-pressed={paneLayout === 1}>
                  <h3>1 pane</h3>
                  <p>Single focus</p>
                  <div className="layout-diagram layout-1">
                    <div className="layout-pane main">claude</div>
                  </div>
                </button>
                <button type="button" className={`layout-card${paneLayout === 2 ? " active" : ""}`} onClick={() => setPaneLayout(2)} aria-pressed={paneLayout === 2}>
                  <h3>2 panes</h3>
                  <p>Side-by-side</p>
                  <div className="layout-diagram layout-2">
                    <div className="layout-pane main">claude</div>
                    <div className="layout-pane">server</div>
                  </div>
                </button>
                <button type="button" className={`layout-card${paneLayout === 3 ? " active" : ""}`} onClick={() => setPaneLayout(3)} aria-pressed={paneLayout === 3}>
                  <h3>3+ panes</h3>
                  <p>Main-vertical</p>
                  <div className="layout-diagram layout-3">
                    <div className="layout-pane main">claude</div>
                    <div className="layout-pane">server</div>
                    <div className="layout-pane">tests</div>
                  </div>
                </button>
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
                Your agents need the same desktop
              </h2>
              <p className="config-desc">
                Agent harnesses can run code, but computer use is still slow
                and brittle. Lattices adds fast, typed workspace and
                computer-use tools on localhost: search, place, activate,
                observe, stage, execute, and verify.
              </p>
              <ul className="agent-methods">
                <li><code>lattices.search</code> — title, app, session, or cwd</li>
                <li><code>window.place</code> — tile by session, app, or window id</li>
                <li><code>layer.activate</code> — launch or focus a workspace</li>
                <li><code>space.optimize</code> — rebalance visible windows</li>
                <li><code>computer.windowState</code> — AX snapshot, element ids</li>
                <li><code>computer.elementAction</code> — stage or execute those ids</li>
                <li><code>computer.verify</code> — confirm via OCR or AX</li>
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

        <section className="local-trust fade-in" id="local-first">
          <div>
            <div className="cua-kicker">Local core, open source</div>
            <h2>The core runs on your Mac.</h2>
          </div>
          <p>
            Lattices runs as a local service and exposes a typed API over
            localhost. Workspace control and action traces stay on-device.
            Optional vision-model features may send screen context to the
            provider you configure. The source is open, and agent actions are
            recorded and verifiable.
          </p>
        </section>

        <section className="install-chooser fade-in" id="install">
          <div className="install-chooser-head">
            <div className="cua-kicker">Three ways in. One workspace.</div>
            <h2>Start where you work.</h2>
          </div>
          <div className="install-chooser-grid">
            <article>
              <span className="install-chooser-label">App</span>
              <h3>Native macOS app</h3>
              <p>Manage projects, windows, and layers with a click.</p>
              <a
                href="https://github.com/arach/lattices/releases/latest/download/Lattices.dmg"
                onClick={() => trackCta('download_dmg_install', 'https://github.com/arach/lattices/releases/latest/download/Lattices.dmg')}
              >
                Download for macOS <span aria-hidden="true">↗</span>
              </a>
              <small>Apple Silicon · .dmg</small>
            </article>
            <article>
              <span className="install-chooser-label">CLI</span>
              <h3>Command line</h3>
              <p>Launch, search, place, and script the same workspace.</p>
              <a href="/docs/quickstart">
                Get the CLI <span aria-hidden="true">→</span>
              </a>
              <small><code>npm i -g @arach/lattices</code></small>
            </article>
            <article>
              <span className="install-chooser-label">SDK</span>
              <h3>Typed agent SDK</h3>
              <p>Build agents and scripts against the whole desktop.</p>
              <a href="/docs/api">
                Read the API <span aria-hidden="true">→</span>
              </a>
              <small><code>npm i @lattices/sdk</code></small>
            </article>
          </div>
          <p className="install-chooser-footnote">Same service, same live state — pick the surface that fits.</p>
        </section>

        {/* CTA */}
        <section className="cta">
          <h2>Put your whole desktop to work.</h2>
          <p>Free and open source. Running on your Mac in seconds.</p>
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
              href="https://www.npmjs.com/package/@arach/lattices"
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-secondary"
              onClick={() => trackCta('view_npm', 'https://www.npmjs.com/package/lattices')}
            >
              CLI package
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
            <a href="/action">Action</a>
            <a href="/blink">Blink</a>
            <a href="/rss.xml">RSS</a>
            <a
              href="https://github.com/arach/lattices"
              target="_blank"
              rel="noopener noreferrer"
            >
              GitHub
            </a>
            <a
                href="https://www.npmjs.com/package/@arach/lattices"
              target="_blank"
              rel="noopener noreferrer"
            >
              npm
            </a>
          </nav>
        </footer>
        </div>
      </main>
    </>
  );
}
