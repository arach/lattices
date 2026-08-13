export type MapFrame = { x: number; y: number; w: number; h: number };

export type MapCanvasRect = {
  left: number;
  top: number;
  right: number;
  bottom: number;
};

export type DesktopMapReference = {
  viewport: MapFrame;
  columns: number;
  rows: number;
  cellsPerPoint: number;
  cellAspectRatio: number;
};

export const DEFAULT_TERMINAL_CELL_ASPECT_RATIO = 2;

export function unionMapFrames(frames: MapFrame[]): MapFrame | undefined {
  const valid = frames.filter((frame) =>
    Number.isFinite(frame.x) &&
    Number.isFinite(frame.y) &&
    Number.isFinite(frame.w) &&
    Number.isFinite(frame.h) &&
    frame.w > 0 &&
    frame.h > 0
  );
  if (!valid.length) return undefined;

  const left = Math.min(...valid.map((frame) => frame.x));
  const top = Math.min(...valid.map((frame) => frame.y));
  const right = Math.max(...valid.map((frame) => frame.x + frame.w));
  const bottom = Math.max(...valid.map((frame) => frame.y + frame.h));
  return { x: left, y: top, w: right - left, h: bottom - top };
}

export function intersectMapFrames(a: MapFrame, b: MapFrame): MapFrame | undefined {
  const left = Math.max(a.x, b.x);
  const top = Math.max(a.y, b.y);
  const right = Math.min(a.x + a.w, b.x + b.w);
  const bottom = Math.min(a.y + a.h, b.y + b.h);
  if (right <= left || bottom <= top) return undefined;
  return { x: left, y: top, w: right - left, h: bottom - top };
}

export function createDesktopMapReference(
  frames: MapFrame[],
  options: {
    maxColumns: number;
    maxRows: number;
    cellAspectRatio?: number;
  },
): DesktopMapReference | undefined {
  const viewport = unionMapFrames(frames);
  if (!viewport) return undefined;

  const maxColumns = Math.max(2, Math.floor(options.maxColumns));
  const maxRows = Math.max(2, Math.floor(options.maxRows));
  const cellAspectRatio = options.cellAspectRatio ?? DEFAULT_TERMINAL_CELL_ASPECT_RATIO;
  if (!Number.isFinite(cellAspectRatio) || cellAspectRatio <= 0) {
    throw new Error("cellAspectRatio must be a positive number");
  }

  // A terminal row is taller than a terminal column is wide. Use one uniform
  // physical scale, then divide vertical coordinates by the cell aspect ratio.
  const horizontalScale = (maxColumns - 1) / viewport.w;
  const verticalScale = ((maxRows - 1) * cellAspectRatio) / viewport.h;
  const cellsPerPoint = Math.min(horizontalScale, verticalScale);
  const columns = Math.max(2, Math.round(viewport.w * cellsPerPoint) + 1);
  const rows = Math.max(2, Math.round((viewport.h * cellsPerPoint) / cellAspectRatio) + 1);

  return {
    viewport,
    columns,
    rows,
    cellsPerPoint,
    cellAspectRatio,
  };
}

export function projectMapFrame(reference: DesktopMapReference, frame: MapFrame): MapCanvasRect {
  const horizontal = (value: number): number =>
    Math.round((value - reference.viewport.x) * reference.cellsPerPoint);
  const vertical = (value: number): number =>
    Math.round(((value - reference.viewport.y) * reference.cellsPerPoint) / reference.cellAspectRatio);

  return {
    left: horizontal(frame.x),
    top: vertical(frame.y),
    right: horizontal(frame.x + frame.w),
    bottom: vertical(frame.y + frame.h),
  };
}
