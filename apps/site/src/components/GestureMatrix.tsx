import { useState } from "react";
import { motion, useReducedMotion } from "motion/react";

type Point = [number, number];

type PrimerGesture = {
  id: string;
  trigger: string;
  action: string;
  hint: string;
  cells: number[];
  path: Point[];
  closed?: boolean;
};

const CELL = 18;
const GAP = 10;
const PAD = 16;
const GRID = CELL * 3 + GAP * 2;
const SIZE = GRID + PAD * 2;

function cellOrigin(index: number): Point {
  const col = index % 3;
  const row = Math.floor(index / 3);
  return [PAD + col * (CELL + GAP), PAD + row * (CELL + GAP)];
}

function cellCenter(index: number): Point {
  const [x, y] = cellOrigin(index);
  return [x + CELL / 2, y + CELL / 2];
}

function through(cells: number[]): Point[] {
  return cells.map(cellCenter);
}

function circlePath(): Point[] {
  const [cx, cy] = cellCenter(4);
  const r = CELL + GAP * 0.55;
  const points: Point[] = [];
  for (let i = 0; i <= 16; i++) {
    const t = (i / 16) * Math.PI * 2 - Math.PI / 2;
    points.push([cx + Math.cos(t) * r, cy + Math.sin(t) * r]);
  }
  return points;
}

const defaultGestures: PrimerGesture[] = [
  { id: "up", trigger: "middle ↑", action: "Dictation", hint: "Hold middle, draw up, release.", cells: [7, 4, 1], path: through([7, 4, 1]) },
  { id: "right", trigger: "middle →", action: "Next Space", hint: "Hold middle, draw right, release.", cells: [3, 4, 5], path: through([3, 4, 5]) },
  { id: "left", trigger: "middle ←", action: "Previous Space", hint: "Hold middle, draw left, release.", cells: [5, 4, 3], path: through([5, 4, 3]) },
  { id: "down", trigger: "middle ↓", action: "Screen Map", hint: "Hold middle, draw down, release.", cells: [1, 4, 7], path: through([1, 4, 7]) },
  { id: "circle", trigger: "back ○", action: "Screenshot area", hint: "Hold back, draw a loose loop.", cells: [1, 2, 5, 8, 7, 6, 3, 0], path: circlePath(), closed: true },
];

const alphabetGestures: PrimerGesture[] = [
  { id: "l-dr", trigger: "L ↓→", action: "Shape", hint: "Down, then right.", cells: [1, 4, 7, 8], path: through([1, 4, 7, 8]) },
  { id: "l-dl", trigger: "L ↓←", action: "Shape", hint: "Down, then left.", cells: [1, 4, 7, 6], path: through([1, 4, 7, 6]) },
  { id: "l-ur", trigger: "L ↑→", action: "Shape", hint: "Up, then right.", cells: [7, 4, 1, 2], path: through([7, 4, 1, 2]) },
  { id: "l-ul", trigger: "L ↑←", action: "Shape", hint: "Up, then left.", cells: [7, 4, 1, 0], path: through([7, 4, 1, 0]) },
  { id: "rl-rd", trigger: "⌐ →↓", action: "Shape", hint: "Right, then down.", cells: [3, 4, 5, 8], path: through([3, 4, 5, 8]) },
  { id: "rl-ld", trigger: "¬ ←↓", action: "Shape", hint: "Left, then down.", cells: [5, 4, 3, 6], path: through([5, 4, 3, 6]) },
  { id: "v", trigger: "V ↓↑", action: "Shape", hint: "Down, then up.", cells: [1, 4, 7, 4, 1], path: through([1, 4, 7, 1]) },
  { id: "rv", trigger: "Λ ↑↓", action: "Shape", hint: "Up, then down.", cells: [7, 4, 1, 4, 7], path: through([7, 4, 1, 7]) },
];

const logoCells = new Set([0, 3, 6, 7, 8]);

function pointsToPath(points: Point[], closed = false): string {
  return `${points.map(([x, y], i) => `${i === 0 ? "M" : "L"} ${x.toFixed(1)} ${y.toFixed(1)}`).join(" ")}${closed ? " Z" : ""}`;
}

function MatrixFace({
  gesture,
  reducedMotion,
  compact = false,
}: {
  gesture: PrimerGesture;
  reducedMotion: boolean;
  compact?: boolean;
}) {
  const d = pointsToPath(gesture.path, gesture.closed);
  const size = compact ? 56 : SIZE;

  return (
    <svg
      className={`gesture-matrix-face${compact ? " is-compact" : ""}`}
      viewBox={`0 0 ${SIZE} ${SIZE}`}
      width={size}
      height={size}
      aria-hidden="true"
    >
      {Array.from({ length: 9 }, (_, index) => {
        const [x, y] = cellOrigin(index);
        const active = gesture.cells.includes(index);
        const mark = logoCells.has(index);
        return (
          <rect
            key={index}
            x={x}
            y={y}
            width={CELL}
            height={CELL}
            rx={5}
            className={`gesture-matrix-cell${active ? " is-active" : ""}${mark && !active ? " is-mark" : ""}`}
          />
        );
      })}
      <motion.path
        key={gesture.id}
        d={d}
        className="gesture-matrix-path"
        fill="none"
        initial={{ pathLength: reducedMotion || compact ? 1 : 0, opacity: 1 }}
        animate={{ pathLength: 1 }}
        transition={{ duration: reducedMotion || compact ? 0 : 0.55, ease: [0.16, 1, 0.3, 1] }}
      />
    </svg>
  );
}

export function GestureMatrix() {
  const prefersReducedMotion = useReducedMotion() ?? false;
  const [selectedId, setSelectedId] = useState(defaultGestures[0].id);
  const selected =
    defaultGestures.find((gesture) => gesture.id === selectedId) ??
    alphabetGestures.find((gesture) => gesture.id === selectedId) ??
    defaultGestures[0];

  return (
    <div className="gesture-primer" aria-label="Gesture matrix primer">
      <div className="gesture-primer-stage">
        <MatrixFace gesture={selected} reducedMotion={prefersReducedMotion} />
        <div className="gesture-primer-readout">
          <span className="hands-trigger">{selected.trigger}</span>
          <strong>{selected.action}</strong>
          <p>{selected.hint}</p>
        </div>
      </div>

      <div className="gesture-primer-group">
        <h4>Defaults</h4>
        <div className="gesture-primer-picks">
          {defaultGestures.map((gesture) => (
            <button
              key={gesture.id}
              type="button"
              className={gesture.id === selectedId ? "is-active" : ""}
              aria-pressed={gesture.id === selectedId}
              onClick={() => setSelectedId(gesture.id)}
              onMouseEnter={() => setSelectedId(gesture.id)}
              onFocus={() => setSelectedId(gesture.id)}
            >
              {gesture.trigger}
              <span>{gesture.action}</span>
            </button>
          ))}
        </div>
      </div>

      <div className="gesture-primer-group">
        <h4>Shape alphabet</h4>
        <div className="gesture-primer-alphabet">
          {alphabetGestures.map((gesture) => (
            <button
              key={gesture.id}
              type="button"
              className={gesture.id === selectedId ? "is-active" : ""}
              aria-pressed={gesture.id === selectedId}
              aria-label={`${gesture.trigger} — ${gesture.hint}`}
              onClick={() => setSelectedId(gesture.id)}
              onMouseEnter={() => setSelectedId(gesture.id)}
              onFocus={() => setSelectedId(gesture.id)}
            >
              <MatrixFace gesture={gesture} reducedMotion compact />
              <span>{gesture.trigger}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
