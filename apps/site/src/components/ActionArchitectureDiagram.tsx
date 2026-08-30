import { useEffect, useMemo, useRef, useState } from "react";
import { ArcDiagramIsometric } from "@arach/arc";
import type { DiagramConfig } from "@arach/arc";
import actionTraceField from "../../../../products/action/docs/assets/brand/landing-trace-field.webp";

const desktopCanvas = { width: 760, height: 620 };
const compactCanvas = { width: 360, height: 430 };
const zoomRange = { min: 0.75, max: 1.6, step: 0.1 };
const actionMaterials = {
  graphite: {
    label: "Graphite",
    node: { color: "slate", opacity: 0.82 },
    light: { floorColor: "#ece7dc", borderColor: "#77746c" },
    dark: { floorColor: "#151d20", borderColor: "#778086" },
    swatch: "#596269",
  },
  coral: {
    label: "Coral",
    node: { color: "rose", opacity: 0.72 },
    light: { floorColor: "#f4e5dc", borderColor: "#b47861" },
    dark: { floorColor: "#281d1a", borderColor: "#a76750" },
    swatch: "#d66f52",
  },
  oxidizedCyan: {
    label: "Oxidized cyan",
    node: { color: "cyan", opacity: 0.68 },
    light: { floorColor: "#e5efef", borderColor: "#658b8c" },
    dark: { floorColor: "#122326", borderColor: "#4f8589" },
    swatch: "#4f8c8f",
  },
  moss: {
    label: "Moss",
    node: { color: "emerald", opacity: 0.66 },
    light: { floorColor: "#e8efe5", borderColor: "#718b6d" },
    dark: { floorColor: "#17231a", borderColor: "#5e8466" },
    swatch: "#648365",
  },
  blueprint: {
    label: "Blueprint",
    node: { color: "blue", opacity: 0.7 },
    light: { floorColor: "#e6edf1", borderColor: "#6d8390" },
    dark: { floorColor: "#152128", borderColor: "#54758a" },
    swatch: "#587789",
  },
} as const;

type ActionMaterialName = keyof typeof actionMaterials;
type LayerPalette = [ActionMaterialName, ActionMaterialName, ActionMaterialName, ActionMaterialName];

const defaultLayerPalette: LayerPalette = ["coral", "graphite", "oxidizedCyan", "moss"];

function clampZoom(value: number) {
  return Math.min(zoomRange.max, Math.max(zoomRange.min, Math.round(value * 100) / 100));
}

const architectureLayers = [
  {
    number: "01",
    name: "Request",
    detail: "Agent, MCP, CLI, or the native launcher",
  },
  {
    number: "02",
    name: "Local runtime",
    detail: "Session state, targets, orchestration, and traces",
  },
  {
    number: "03",
    name: "Native macOS",
    detail: "ActionAgent bridges to Action.app, AX, WebKit, and capture",
  },
  {
    number: "04",
    name: "Evidence",
    detail: "Video, screenshots, trace, context, and a finished marker",
  },
];

function createArchitectureConfig(
  theme: "light" | "dark",
  compact: boolean,
  layerPalette: LayerPalette,
): DiagramConfig {
  const dark = theme === "dark";
  const canvas = compact ? compactCanvas : desktopCanvas;
  const materialForTier = (tier: number) => actionMaterials[layerPalette[architectureLayers.length - tier - 1]];
  const surfaceForTier = (tier: number) => materialForTier(tier)[dark ? "dark" : "light"];
  const nodeForTier = (tier: number) => materialForTier(tier).node;

  return {
    id: `action-runtime-${theme}-${layerPalette.join("-")}`,
    title: "Action local runtime architecture",
    description: "The request path from an agent or operator to native macOS execution and inspectable evidence.",
    theme,
    canvas,
    origin: compact ? { x: 180, y: 355 } : { x: 383, y: 510 },
    cornerRadius: 2,
    floorSize: compact ? { width: 150, depth: 96 } : { width: 240, depth: 164 },
    tiers: [
      {
        name: "EVIDENCE",
        elevation: 0,
        ...surfaceForTier(0),
        floorOpacity: 0.96,
      },
      {
        name: "NATIVE MACOS",
        elevation: compact ? 54 : 92,
        ...surfaceForTier(1),
        floorOpacity: 0.58,
        offset: compact ? { x: 18, y: -8 } : { x: 42, y: -16 },
      },
      {
        name: "LOCAL RUNTIME",
        elevation: compact ? 108 : 184,
        ...surfaceForTier(2),
        floorOpacity: 0.46,
        offset: compact ? { x: 36, y: -14 } : { x: 84, y: -28 },
      },
      {
        name: "REQUEST",
        elevation: compact ? 162 : 276,
        ...surfaceForTier(3),
        floorOpacity: 0.4,
        offset: compact ? { x: 54, y: -20 } : { x: 126, y: -40 },
      },
    ],
    nodes: compact ? [
      { tier: 0, x: 14, y: 18, width: 64, depth: 28, height: 9, ...nodeForTier(0), label: "VIDEO + TRACE" },
      { tier: 0, x: 84, y: 42, width: 54, depth: 28, height: 9, ...nodeForTier(0), label: "FINISHED" },

      { tier: 1, x: 10, y: 18, width: 62, depth: 28, height: 10, ...nodeForTier(1), label: "ACTIONAGENT" },
      { tier: 1, x: 80, y: 18, width: 56, depth: 28, height: 10, ...nodeForTier(1), label: "ACTION.APP" },
      { tier: 1, x: 48, y: 55, width: 62, depth: 26, height: 9, ...nodeForTier(1), label: "AX + CAPTURE" },

      { tier: 2, x: 18, y: 20, width: 66, depth: 30, height: 11, ...nodeForTier(2), label: "RUNTIME" },
      { tier: 2, x: 88, y: 40, width: 50, depth: 26, height: 9, ...nodeForTier(2), label: "TARGETS" },

      { tier: 3, x: 12, y: 18, width: 68, depth: 30, height: 10, ...nodeForTier(3), label: "AGENT + MCP" },
      { tier: 3, x: 88, y: 38, width: 46, depth: 26, height: 9, ...nodeForTier(3), label: "CLI" },
    ] : [
      { tier: 0, x: 20, y: 28, width: 74, depth: 42, height: 12, ...nodeForTier(0), label: "VIDEO + TRACE" },
      { tier: 0, x: 112, y: 30, width: 72, depth: 42, height: 12, ...nodeForTier(0), label: "SNAPSHOTS" },
      { tier: 0, x: 68, y: 96, width: 92, depth: 42, height: 12, ...nodeForTier(0), label: "FINISHED" },

      { tier: 1, x: 12, y: 24, width: 88, depth: 44, height: 15, ...nodeForTier(1), label: "ACTIONAGENT" },
      { tier: 1, x: 112, y: 26, width: 82, depth: 44, height: 15, ...nodeForTier(1), label: "ACTION.APP" },
      { tier: 1, x: 32, y: 96, width: 76, depth: 40, height: 13, ...nodeForTier(1), label: "AX + WEBKIT" },
      { tier: 1, x: 126, y: 98, width: 92, depth: 40, height: 13, ...nodeForTier(1), label: "CAPTURE PROBE" },

      { tier: 2, x: 28, y: 34, width: 100, depth: 52, height: 18, ...nodeForTier(2), label: "RUNTIME" },
      { tier: 2, x: 142, y: 44, width: 76, depth: 46, height: 14, ...nodeForTier(2), label: "SESSION" },
      { tier: 2, x: 86, y: 106, width: 86, depth: 38, height: 12, ...nodeForTier(2), label: "TARGETS" },

      { tier: 3, x: 26, y: 36, width: 80, depth: 46, height: 14, ...nodeForTier(3), label: "AGENT + MCP" },
      { tier: 3, x: 126, y: 38, width: 72, depth: 44, height: 14, ...nodeForTier(3), label: "CLI" },
      { tier: 3, x: 76, y: 100, width: 92, depth: 42, height: 14, ...nodeForTier(3), label: "LAUNCHER" },
    ],
  };
}

export function ActionArchitectureDiagram({ theme }: { theme: "light" | "dark" }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [layout, setLayout] = useState({ compact: false, scale: 1 });
  const [selectedTier, setSelectedTier] = useState<number | null>(null);
  const [zoom, setZoom] = useState(1);
  const canvas = layout.compact ? compactCanvas : desktopCanvas;
  const config = useMemo(
    () => createArchitectureConfig(theme, layout.compact, defaultLayerPalette),
    [theme, layout.compact],
  );

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const updateScale = () => {
      const compact = container.clientWidth < 520;
      const nextCanvas = compact ? compactCanvas : desktopCanvas;
      setLayout({ compact, scale: Math.min(1, container.clientWidth / nextCanvas.width) });
    };
    updateScale();

    const observer = new ResizeObserver(updateScale);
    observer.observe(container);

    // React delegates wheel events at the root. Keep this listener native and
    // non-passive so modified wheel input can cancel document scrolling.
    const handleModifiedWheel = (event: WheelEvent) => {
      const isModified = event.ctrlKey || event.metaKey;
      if (!isModified) return;

      event.preventDefault();
      event.stopPropagation();
      setZoom((current) => clampZoom(current - event.deltaY * 0.002));
    };

    container.addEventListener("wheel", handleModifiedWheel, { passive: false });
    return () => {
      observer.disconnect();
      container.removeEventListener("wheel", handleModifiedWheel);
    };
  }, []);

  const selectTier = (tier: number) => {
    setSelectedTier((current) => (current === tier ? null : tier));
  };

  const selectTierFromDiagram = (target: EventTarget | null) => {
    if (!(target instanceof SVGElement)) {
      setSelectedTier(null);
      return;
    }

    const svg = target.closest("svg");
    const tierRoot = svg
      ? Array.from(svg.children).find((child) => child.tagName.toLowerCase() === "g" && child.hasAttribute("transform"))
      : null;
    const tier = tierRoot
      ? Array.from(tierRoot.children).findIndex((child) => child.contains(target))
      : -1;

    if (tier >= 0 && tier < architectureLayers.length) selectTier(architectureLayers.length - tier - 1);
    else setSelectedTier(null);
  };

  const selectedLayer = selectedTier === null ? null : architectureLayers[selectedTier];
  const resetView = () => {
    setSelectedTier(null);
    setZoom(1);
  };

  return (
    <div className="action-architecture-visual">
      <div className="action-architecture-player">
        <div className="action-architecture-player-bar">
          <span className="action-architecture-player-title">
            <i aria-hidden="true" />
            Action system map
          </span>
          <div className="action-architecture-player-tools">
            <span className="action-architecture-player-hint">Hover to separate · click to hold</span>
            <div className="action-architecture-zoom" role="group" aria-label="Diagram zoom controls">
              <button
                type="button"
                aria-label="Zoom out"
                disabled={zoom <= zoomRange.min}
                onClick={() => setZoom((current) => clampZoom(current - zoomRange.step))}
              >
                <svg viewBox="0 0 16 16" aria-hidden="true">
                  <path d="M3 8h10" />
                </svg>
              </button>
              <button
                type="button"
                className="action-architecture-zoom-value"
                aria-label={`Reset zoom to 100 percent. Current zoom ${Math.round(zoom * 100)} percent.`}
                disabled={zoom === 1}
                onClick={() => setZoom(1)}
              >
                {Math.round(zoom * 100)}%
              </button>
              <button
                type="button"
                aria-label="Zoom in"
                disabled={zoom >= zoomRange.max}
                onClick={() => setZoom((current) => clampZoom(current + zoomRange.step))}
              >
                <svg viewBox="0 0 16 16" aria-hidden="true">
                  <path d="M3 8h10M8 3v10" />
                </svg>
              </button>
            </div>
          </div>
        </div>
        <div
          ref={containerRef}
          className="action-architecture-canvas"
          role="group"
          aria-label="Interactive isometric architecture diagram. Hover over a plane to separate it, click to hold it, use the arrow keys to move between layers, or pinch and Command-scroll to zoom."
          tabIndex={0}
          data-selected-tier={selectedTier ?? undefined}
          onClick={(event) => selectTierFromDiagram(event.target)}
          onKeyDown={(event) => {
            if (event.key === "Escape") {
              resetView();
              return;
            }

            if (["+", "=", "-", "_", "0"].includes(event.key)) {
              event.preventDefault();
              if (event.key === "0") setZoom(1);
              else if (event.key === "+" || event.key === "=") {
                setZoom((current) => clampZoom(current + zoomRange.step));
              } else {
                setZoom((current) => clampZoom(current - zoomRange.step));
              }
              return;
            }

            if (!["ArrowDown", "ArrowLeft", "ArrowRight", "ArrowUp", "Home", "End"].includes(event.key)) return;

            event.preventDefault();
            setSelectedTier((current) => {
              if (event.key === "Home") return 0;
              if (event.key === "End") return architectureLayers.length - 1;

              const direction = event.key === "ArrowLeft" || event.key === "ArrowUp" ? -1 : 1;
              const start = current ?? (direction > 0 ? -1 : 0);
              return (start + direction + architectureLayers.length) % architectureLayers.length;
            });
          }}
        >
          <div
            className="action-architecture-canvas-scale"
            style={{
              width: canvas.width,
              height: canvas.height,
              transform: `translate(-50%, -50%) scale(${layout.scale * zoom})`,
            }}
          >
            <ArcDiagramIsometric
              config={config}
              options={{
                interactive: true,
                animate: false,
                showLabels: true,
              }}
            />
          </div>
          <img className="action-architecture-texture" src={actionTraceField} alt="" aria-hidden="true" />
        </div>
        <div className="action-architecture-player-readout" aria-live="polite">
          <span>
            <b>{selectedLayer?.name ?? "System"}</b>
            {selectedLayer
              ? ` · ${layout.compact ? "Layer held" : selectedLayer.detail}`
              : ` · ${layout.compact ? "Tap a plane to inspect" : "Four local planes, one inspectable run"}`}
          </span>
          <button type="button" onClick={resetView} disabled={selectedTier === null && zoom === 1}>
            Reset view
          </button>
        </div>
      </div>
    </div>
  );
}
