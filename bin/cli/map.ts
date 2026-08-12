type Frame = { x: number; y: number; w: number; h: number };

export type MapSpace = {
  id: number;
  index: number;
  name?: string;
  display: number;
  isCurrent: boolean;
};

export type MapDisplay = {
  displayIndex: number;
  displayId?: string;
  name?: string;
  currentSpaceId: number;
  spaces?: MapSpace[];
  frame?: Frame;
  visibleFrame?: Frame;
};

export type MapWindow = {
  wid: number;
  app: string;
  pid?: number;
  title: string;
  frame: Frame;
  spaceIds: number[];
  isOnScreen: boolean;
  axVerified?: boolean;
  latticesSession?: string;
  layerTag?: string;
};

type MapOptions = {
  width?: number;
  height?: number;
  display?: number;
};

export type WorkspaceMapSnapshotWindow = MapWindow & { zIndex: number };

export type WorkspaceMapSnapshotDisplay = MapDisplay & {
  spaces: MapSpace[];
  windows: WorkspaceMapSnapshotWindow[];
};

export type WorkspaceMapSnapshot = {
  version: 1;
  coordinateSystem: {
    origin: "top-left";
    units: "points";
    reference: "global-desktop";
  };
  displays: WorkspaceMapSnapshotDisplay[];
};

const MIN_WIDTH = 32;
const MAX_WIDTH = 120;
const MIN_HEIGHT = 8;
const MAX_HEIGHT = 40;

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function cleanLabel(value: string): string {
  return value
    .replace(/\u001B\][^\u0007]*(?:\u0007|\u001B\\)/gu, "")
    .replace(/\u001B\[[0-?]*[ -/]*[@-~]/gu, "")
    .replace(/[\p{Cc}\p{Cf}]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

// Canvas cells must stay exactly one terminal column wide. Keep full Unicode
// in the legend, but use a printable ASCII projection inside the fixed grid.
function canvasLabel(value: string): string {
  return cleanLabel(value).replace(/[^\x20-\x7e]/gu, "?");
}

function windowLabel(window: MapWindow, index: number, width: number): string {
  const app = canvasLabel(window.app);
  const title = canvasLabel(window.title);
  const full = `${index} ${app}${title ? ` - ${title}` : ""}`;
  return full.length <= width ? full : `${full.slice(0, Math.max(1, width - 1))}…`;
}

function intersects(a: Frame, b: Frame): boolean {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

function drawWindow(canvas: string[][], display: Frame, window: MapWindow, index: number): void {
  const rows = canvas.length;
  const columns = canvas[0]?.length ?? 0;
  if (rows < 3 || columns < 3) return;

  const clipped = {
    x: Math.max(display.x, window.frame.x),
    y: Math.max(display.y, window.frame.y),
    w: Math.min(display.x + display.w, window.frame.x + window.frame.w) - Math.max(display.x, window.frame.x),
    h: Math.min(display.y + display.h, window.frame.y + window.frame.h) - Math.max(display.y, window.frame.y),
  };
  if (clipped.w <= 0 || clipped.h <= 0) return;

  const x1 = clamp(Math.round(((clipped.x - display.x) / display.w) * (columns - 1)), 0, columns - 2);
  const y1 = clamp(Math.round(((clipped.y - display.y) / display.h) * (rows - 1)), 0, rows - 2);
  const x2 = clamp(Math.round(((clipped.x + clipped.w - display.x) / display.w) * (columns - 1)), x1 + 1, columns - 1);
  const y2 = clamp(Math.round(((clipped.y + clipped.h - display.y) / display.h) * (rows - 1)), y1 + 1, rows - 1);

  for (let y = y1 + 1; y < y2; y++) {
    for (let x = x1 + 1; x < x2; x++) canvas[y]![x] = " ";
  }
  for (let x = x1 + 1; x < x2; x++) {
    canvas[y1]![x] = "─";
    canvas[y2]![x] = "─";
  }
  for (let y = y1 + 1; y < y2; y++) {
    canvas[y]![x1] = "│";
    canvas[y]![x2] = "│";
  }
  canvas[y1]![x1] = "┌";
  canvas[y1]![x2] = "┐";
  canvas[y2]![x1] = "└";
  canvas[y2]![x2] = "┘";

  const available = x2 - x1 - 1;
  if (available > 2) {
    const label = windowLabel(window, index, available);
    for (let i = 0; i < label.length && i < available; i++) canvas[y1]![x1 + 1 + i] = label[i]!;
  }
}

function displayFrame(display: MapDisplay): Frame | undefined {
  return display.visibleFrame ?? display.frame;
}

function windowsForDisplay(display: MapDisplay, windows: MapWindow[]): MapWindow[] {
  const frame = displayFrame(display);
  if (!frame || frame.w <= 0 || frame.h <= 0) return [];
  return windows.filter((window) =>
    window.isOnScreen &&
    window.spaceIds.includes(display.currentSpaceId) &&
    intersects(window.frame, frame)
  );
}

function snapshotFrame(frame: Frame): Frame {
  return { x: frame.x, y: frame.y, w: frame.w, h: frame.h };
}

function snapshotSpace(space: MapSpace): MapSpace {
  return {
    id: space.id,
    index: space.index,
    ...(space.name === undefined ? {} : { name: space.name }),
    display: space.display,
    isCurrent: space.isCurrent,
  };
}

function snapshotWindow(window: MapWindow, zIndex: number): WorkspaceMapSnapshotWindow {
  return {
    wid: window.wid,
    app: window.app,
    ...(window.pid === undefined ? {} : { pid: window.pid }),
    title: window.title,
    frame: snapshotFrame(window.frame),
    spaceIds: [...window.spaceIds],
    isOnScreen: window.isOnScreen,
    ...(window.axVerified === undefined ? {} : { axVerified: window.axVerified }),
    ...(window.latticesSession === undefined ? {} : { latticesSession: window.latticesSession }),
    ...(window.layerTag === undefined ? {} : { layerTag: window.layerTag }),
    zIndex,
  };
}

function snapshotDisplay(display: MapDisplay, windows: MapWindow[]): WorkspaceMapSnapshotDisplay {
  return {
    displayIndex: display.displayIndex,
    ...(display.displayId === undefined ? {} : { displayId: display.displayId }),
    ...(display.name === undefined ? {} : { name: display.name }),
    currentSpaceId: display.currentSpaceId,
    spaces: (display.spaces ?? []).map(snapshotSpace),
    ...(display.frame === undefined ? {} : { frame: snapshotFrame(display.frame) }),
    ...(display.visibleFrame === undefined ? {} : { visibleFrame: snapshotFrame(display.visibleFrame) }),
    windows: windowsForDisplay(display, windows).map(snapshotWindow),
  };
}

export function createWorkspaceMapSnapshot(
  displays: MapDisplay[],
  windows: MapWindow[],
  options: Pick<MapOptions, "display"> = {},
): WorkspaceMapSnapshot {
  const selected = displays.filter((display) =>
    options.display === undefined || display.displayIndex === options.display
  );
  return {
    version: 1,
    coordinateSystem: {
      origin: "top-left",
      units: "points",
      reference: "global-desktop",
    },
    displays: selected.map((display) => snapshotDisplay(display, windows)),
  };
}

export function renderWorkspaceMap(
  displays: MapDisplay[],
  windows: MapWindow[],
  options: MapOptions = {},
): string {
  const selected = displays.filter((display) => options.display === undefined || display.displayIndex === options.display);
  if (!selected.length) return options.display === undefined ? "No displays found." : `Display ${options.display} not found.`;

  const width = clamp(Math.round(options.width ?? 72), MIN_WIDTH, MAX_WIDTH);
  const requestedHeight = options.height === undefined ? undefined : clamp(Math.round(options.height), MIN_HEIGHT, MAX_HEIGHT);
  const sections: string[] = [];

  for (const display of selected) {
    const frame = displayFrame(display);
    if (!frame || frame.w <= 0 || frame.h <= 0) {
      sections.push(`Display ${display.displayIndex}${display.name ? ` · ${display.name}` : ""}\n  Geometry unavailable. Update the Lattices app.`);
      continue;
    }

    const innerWidth = width - 2;
    const proportionalHeight = Math.round((innerWidth * frame.h) / frame.w / 2);
    const innerHeight = requestedHeight ? requestedHeight - 2 : clamp(proportionalHeight, MIN_HEIGHT - 2, MAX_HEIGHT - 2);
    const canvas = Array.from({ length: innerHeight }, () => Array.from({ length: innerWidth }, () => " "));
    const visible = windowsForDisplay(display, windows);

    // windows.list is front-to-back. Paint back-to-front so visible windows win.
    for (let i = visible.length - 1; i >= 0; i--) drawWindow(canvas, frame, visible[i]!, i + 1);

    const displayName = display.name ? ` · ${canvasLabel(display.name)}` : "";
    const fullTitle = ` Display ${display.displayIndex}${displayName} · Space ${display.currentSpaceId} `;
    const title = fullTitle.length <= innerWidth ? fullTitle : `${fullTitle.slice(0, Math.max(1, innerWidth - 1))}…`;
    const top = `┌${title}${"─".repeat(Math.max(0, innerWidth - title.length))}┐`;
    const body = canvas.map((row) => `│${row.join("")}│`);
    const bottom = `└${"─".repeat(innerWidth)}┘`;
    const legend = visible.map((window, index) => {
      const titleText = cleanLabel(window.title);
      const geometry = `${Math.round(window.frame.w)}×${Math.round(window.frame.h)} @ ${Math.round(window.frame.x)},${Math.round(window.frame.y)}`;
      const app = cleanLabel(window.app);
      return `  ${index + 1}  ${app}${titleText ? ` · ${titleText}` : ""}  wid:${window.wid}  ${geometry}`;
    });

    sections.push([top, ...body, bottom, ...(legend.length ? ["", ...legend] : ["", "  No visible windows on this Space."])].join("\n"));
  }

  return sections.join("\n\n");
}

export function mapUsage(): string {
  return `Usage: lattices map [options]

Render the current Space on each display as a terminal map.

Options:
  --display <n>  Render one display index
  --width <n>    Map width (32–120; defaults to terminal width)
  --height <n>   Map height (8–40; defaults to display aspect ratio)
  --json         Return a versioned current-Space snapshot for agents
  -h, --help     Show this help`;
}

export function parseMapOptions(args: string[]): MapOptions & { json: boolean } {
  const options: MapOptions & { json: boolean } = { json: false };
  const numericOptions = new Set(["display", "width", "height"]);

  for (let index = 0; index < args.length; index++) {
    const argument = args[index]!;
    if (argument === "--json") {
      options.json = true;
      continue;
    }

    const match = argument.match(/^--([^=]+)(?:=(.*))?$/u);
    if (!match || !numericOptions.has(match[1]!)) {
      throw new Error(`Unknown option: ${argument}`);
    }

    const name = match[1]! as "display" | "width" | "height";
    const inlineValue = match[2];
    const raw = inlineValue === undefined ? args[++index] : inlineValue;
    if (raw === undefined || raw === "" || raw.startsWith("--")) {
      throw new Error(`--${name} expects a non-negative integer`);
    }

    const parsed = Number(raw);
    if (!Number.isInteger(parsed) || parsed < 0) {
      throw new Error(`--${name} expects a non-negative integer`);
    }
    options[name] = parsed;
  }

  return options;
}

export async function mapCommand(
  args: string[],
  daemonCall: (method: string, params?: Record<string, unknown> | null) => Promise<unknown>,
): Promise<void> {
  if (args.includes("--help") || args.includes("-h")) {
    console.log(mapUsage());
    return;
  }
  const { json, display, height, width: requestedWidth } = parseMapOptions(args);
  const width = requestedWidth ?? process.stdout.columns;
  const [spacesPayload, windowsPayload] = await Promise.all([
    daemonCall("spaces.list"),
    daemonCall("windows.list"),
  ]);
  const displays = (Array.isArray(spacesPayload) ? spacesPayload : (spacesPayload as { displays?: MapDisplay[] })?.displays ?? []) as MapDisplay[];
  const windows = (Array.isArray(windowsPayload) ? windowsPayload : []) as MapWindow[];

  if (json) {
    console.log(JSON.stringify(createWorkspaceMapSnapshot(displays, windows, { display }), null, 2));
    return;
  }
  console.log(renderWorkspaceMap(displays, windows, { display, width, height }));
}
