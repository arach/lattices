export interface Schema<T> {
  parse(value: unknown): T;
  safeParse(value: unknown):
    | { success: true; data: T }
    | { success: false; error: Error & { issues?: Array<{ path: Array<string | number>; message: string }> } };
}

export type ComputerTreatment = "observe" | "stage" | "present" | "execute";
export type ComputerClickTransport =
  | "auto"
  | "ax"
  | "accessibility"
  | "pointer"
  | "mouse"
  | "hardware";
export type CursorStyle = "spotlight" | "pulse" | "marker";
export type CursorShape =
  | "arrow"
  | "chevron"
  | "facet"
  | "shard"
  | "wedge"
  | "prism"
  | "notch"
  | "needle"
  | "petal"
  | "kite";
export type CursorSize = "tiny" | "small" | "regular" | "large";
export type CursorTrail = "none" | "thread" | "ribbon" | "spark" | "comet" | "route";
export type CursorMotion =
  | "glide"
  | "snap"
  | "float"
  | "rush"
  | "crawl"
  | "accelerate"
  | "teleport"
  | "spring"
  | "magnet"
  | "slingshot";
export type CursorTrajectory = "straight" | "soft" | "arc" | "swoop" | "overshoot";
export type CursorGlow = "none" | "soft" | "halo" | "comet";
export type CursorIdle =
  | "still"
  | "breathe"
  | "wiggle"
  | "orbit"
  | "hover"
  | "nod"
  | "drift"
  | "shimmer"
  | "blink"
  | "tremble";
export type CursorEdge =
  | "none"
  | "pulse"
  | "ripple"
  | "tick"
  | "reticle"
  | "blink"
  | "spark"
  | "underline"
  | "echo"
  | "scan"
  | "pin";
export type CursorSound = "none" | "tick" | "click" | "engage" | "chime";
export type CaptionPlacement =
  | "top-left"
  | "top-right"
  | "bottom-left"
  | "bottom-right"
  | "top-center"
  | "top"
  | "center"
  | "middle"
  | "near-cursor"
  | "cursor";

export interface WindowTarget {
  wid?: number;
  session?: string;
  app?: string;
  title?: string;
}

export interface ActionBase {
  treatment?: ComputerTreatment;
  dryRun?: boolean;
  capture?: boolean;
  source?: string;
}

export interface PointTarget {
  x?: number;
  y?: number;
  xRatio?: number;
  yRatio?: number;
}

export interface ComputerWindowStateParams extends WindowTarget {
  mode?: "ax" | "both" | "screenshot";
  capture?: boolean;
  maxDepth?: number;
  maxElements?: number;
  timeoutMs?: number;
  source?: string;
}

export interface ComputerElementActionParams extends ActionBase {
  snapshotId: string;
  elementId: string;
  action?: "press" | "showMenu" | "focus";
}

export interface ComputerTypeElementParams extends ActionBase {
  snapshotId: string;
  elementId: string;
  text: string;
  append?: boolean;
  typeIntervalMs?: number;
}

export interface ComputerSetValueParams extends ActionBase {
  snapshotId: string;
  elementId: string;
  value: string;
  append?: boolean;
  typeIntervalMs?: number;
}

export interface ComputerKeyboardParams extends WindowTarget, ActionBase {
  key?: string;
  shortcut?: string;
  modifiers?: string[] | string;
  count?: number;
  delayMs?: number;
  allowGlobal?: boolean;
}

export interface ComputerPressKeyParams extends ComputerKeyboardParams {
  key: string;
}

export type ComputerHotkeyParams = ComputerKeyboardParams;
export type ComputerFocusWindowParams = WindowTarget & ActionBase;

export interface ComputerLaunchAppParams extends ActionBase {
  app: string;
  bundleId?: string;
  path?: string;
  title?: string;
}

export interface ComputerTypeWindowTextParams extends WindowTarget, PointTarget, ActionBase {
  text: string;
  enter?: boolean;
  send?: boolean;
}

export interface ComputerTypeTextParams extends ActionBase {
  wid?: number;
  tty?: string;
  app?: string;
  text: string;
  enter?: boolean;
  transport?: "auto" | "tmux" | "iterm" | "iterm2" | "pasteboard";
}

export interface ComputerClickParams extends WindowTarget, PointTarget, ActionBase {
  button?: "left" | "right" | "secondary" | "context";
  count?: number;
  delayMs?: number;
  transport?: ComputerClickTransport;
  axLabel?: string;
  targetText?: string;
  noFocus?: boolean;
  label?: string;
}

export interface ComputerDoubleClickParams extends WindowTarget, PointTarget, ActionBase {
  delayMs?: number;
}

export interface ComputerRightClickParams extends WindowTarget, PointTarget, ActionBase {
  count?: number;
  delayMs?: number;
}

export interface ComputerScrollParams extends WindowTarget, PointTarget, ActionBase {
  direction?: "down" | "up" | "left" | "right";
  amount?: number;
  deltaX?: number;
  deltaY?: number;
  count?: number;
  delayMs?: number;
}

export interface ComputerDragParams extends WindowTarget, PointTarget, ActionBase {
  fromX?: number;
  fromY?: number;
  toX?: number;
  toY?: number;
  fromXRatio?: number;
  fromYRatio?: number;
  toXRatio?: number;
  toYRatio?: number;
  button?: "left" | "right" | "secondary" | "context";
  durationMs?: number;
  steps?: number;
}

export interface ComputerVerifyParams extends WindowTarget {
  mode?: "ocr" | "ax" | "artifactChanged";
  snapshotId?: string;
  elementId?: string;
  runId?: string;
  artifactId?: string;
  path?: string;
  contains?: string;
  expected?: string;
  notContains?: string;
  beforeArtifactId?: string;
  afterArtifactId?: string;
  beforePath?: string;
  afterPath?: string;
  source?: string;
}

export interface CaptureWindowParams extends WindowTarget {
  runId?: string;
  filename?: string;
  source?: string;
}

export interface CaptureRegionParams extends WindowTarget {
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  w?: number;
  h?: number;
  runId?: string;
  filename?: string;
  source?: string;
}

export interface ZoomArtifactParams {
  runId?: string;
  artifactId?: string;
  path?: string;
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  xRatio?: number;
  yRatio?: number;
  widthRatio?: number;
  heightRatio?: number;
  scale?: number;
  filename?: string;
  source?: string;
}

export interface VisionAnalyzeWindowParams extends WindowTarget {
  instruction: string;
  contains?: string;
  notContains?: string;
  source?: string;
}

export interface VisionAnalyzeArtifactParams {
  runId?: string;
  artifactId?: string;
  path?: string;
  instruction: string;
  contains?: string;
  notContains?: string;
  source?: string;
}

export type BrowserGetTextParams = WindowTarget;

export interface BrowserQueryDomParams extends WindowTarget {
  selector: string;
  limit?: number;
  allowAutomation: boolean;
}

export interface BrowserExecuteJavascriptParams extends WindowTarget {
  script: string;
  treatment?: ComputerTreatment;
  allowAutomation?: boolean;
  source?: string;
}

export interface ComputerMagicCursorParams extends WindowTarget, PointTarget, ActionBase {
  style?: CursorStyle;
  appearance?: CursorStyle;
  shape?: CursorShape;
  angleDeg?: number;
  size?: CursorSize;
  color?: string;
  durationMs?: number;
  label?: string;
  caption?: string;
  captionTitle?: string;
  captionBody?: string;
  captionDetail?: string;
  captionTags?: string;
  captionMode?: "auto" | "selection";
  captionEyebrow?: string;
  captionLeadMs?: number;
  captionSound?: CursorSound;
  captionPlacement?: CaptionPlacement;
  captionMargin?: number;
  captionX?: number;
  captionY?: number;
  captionXRatio?: number;
  captionYRatio?: number;
  captionLeftRatio?: number;
  captionTopRatio?: number;
  sound?: CursorSound;
  sfx?: CursorSound;
  showCaption?: boolean;
  captionSelections?: boolean;
  treatmentLabel?: string;
  variant?: string;
  trail?: CursorTrail;
  pathStyle?: CursorTrail;
  motion?: CursorMotion;
  trajectory?: CursorTrajectory;
  glow?: CursorGlow;
  bloom?: CursorGlow;
  idle?: CursorIdle;
  settle?: CursorIdle;
  presence?: CursorIdle;
  edge?: CursorEdge;
  edgeEffect?: CursorEdge;
  arrival?: CursorEdge;
  typewriter?: boolean;
  typing?: boolean;
  typeIntervalMs?: number;
  typingIntervalMs?: number;
  text?: string;
  append?: boolean;
  fromX?: number;
  fromY?: number;
  fromXRatio?: number;
  fromYRatio?: number;
}

export interface CuaClientOptions {
  defaultTimeoutMs?: number;
}

export interface CuaClient {
  windowState(params: ComputerWindowStateParams): Promise<unknown>;
  elementAction(params: ComputerElementActionParams): Promise<unknown>;
  typeElement(params: ComputerTypeElementParams): Promise<unknown>;
  setValue(params: ComputerSetValueParams): Promise<unknown>;
  pressKey(params: ComputerPressKeyParams): Promise<unknown>;
  hotkey(params: ComputerHotkeyParams): Promise<unknown>;
  focusWindow(params: ComputerFocusWindowParams): Promise<unknown>;
  launchApp(params: ComputerLaunchAppParams): Promise<unknown>;
  typeWindowText(params: ComputerTypeWindowTextParams): Promise<unknown>;
  typeText(params: ComputerTypeTextParams): Promise<unknown>;
  click(params: ComputerClickParams): Promise<unknown>;
  doubleClick(params: ComputerDoubleClickParams): Promise<unknown>;
  rightClick(params: ComputerRightClickParams): Promise<unknown>;
  scroll(params: ComputerScrollParams): Promise<unknown>;
  drag(params: ComputerDragParams): Promise<unknown>;
  verify(params: ComputerVerifyParams): Promise<unknown>;
  captureWindow(params: CaptureWindowParams): Promise<unknown>;
  screenshotRegion(params: CaptureRegionParams): Promise<unknown>;
  zoomArtifact(params: ZoomArtifactParams): Promise<unknown>;
  analyzeWindow(params: VisionAnalyzeWindowParams): Promise<unknown>;
  analyzeArtifact(params: VisionAnalyzeArtifactParams): Promise<unknown>;
  browserGetText(params: BrowserGetTextParams): Promise<unknown>;
  browserQueryDom(params: BrowserQueryDomParams): Promise<unknown>;
  browserExecuteJavascript(params: BrowserExecuteJavascriptParams): Promise<unknown>;
  magicCursor(params: ComputerMagicCursorParams): Promise<unknown>;
}

export declare const computerTreatmentSchema: Schema<ComputerTreatment>;
export declare const computerClickTransportSchema: Schema<ComputerClickTransport>;
export declare const cursorStyleSchema: Schema<CursorStyle>;
export declare const cursorShapeSchema: Schema<CursorShape>;
export declare const cursorSizeSchema: Schema<CursorSize>;
export declare const cursorTrailSchema: Schema<CursorTrail>;
export declare const cursorMotionSchema: Schema<CursorMotion>;
export declare const cursorTrajectorySchema: Schema<CursorTrajectory>;
export declare const cursorGlowSchema: Schema<CursorGlow>;
export declare const cursorIdleSchema: Schema<CursorIdle>;
export declare const cursorEdgeSchema: Schema<CursorEdge>;
export declare const cursorSoundSchema: Schema<CursorSound>;
export declare const captionPlacementSchema: Schema<CaptionPlacement>;
export declare const computerWindowStateParamsSchema: Schema<ComputerWindowStateParams>;
export declare const computerElementActionParamsSchema: Schema<ComputerElementActionParams>;
export declare const computerTypeElementParamsSchema: Schema<ComputerTypeElementParams>;
export declare const computerSetValueParamsSchema: Schema<ComputerSetValueParams>;
export declare const computerPressKeyParamsSchema: Schema<ComputerPressKeyParams>;
export declare const computerHotkeyParamsSchema: Schema<ComputerHotkeyParams>;
export declare const computerFocusWindowParamsSchema: Schema<ComputerFocusWindowParams>;
export declare const computerLaunchAppParamsSchema: Schema<ComputerLaunchAppParams>;
export declare const computerTypeWindowTextParamsSchema: Schema<ComputerTypeWindowTextParams>;
export declare const computerTypeTextParamsSchema: Schema<ComputerTypeTextParams>;
export declare const computerClickParamsSchema: Schema<ComputerClickParams>;
export declare const computerDoubleClickParamsSchema: Schema<ComputerDoubleClickParams>;
export declare const computerRightClickParamsSchema: Schema<ComputerRightClickParams>;
export declare const computerScrollParamsSchema: Schema<ComputerScrollParams>;
export declare const computerDragParamsSchema: Schema<ComputerDragParams>;
export declare const computerVerifyParamsSchema: Schema<ComputerVerifyParams>;
export declare const captureWindowParamsSchema: Schema<CaptureWindowParams>;
export declare const captureRegionParamsSchema: Schema<CaptureRegionParams>;
export declare const zoomArtifactParamsSchema: Schema<ZoomArtifactParams>;
export declare const visionAnalyzeWindowParamsSchema: Schema<VisionAnalyzeWindowParams>;
export declare const visionAnalyzeArtifactParamsSchema: Schema<VisionAnalyzeArtifactParams>;
export declare const browserGetTextParamsSchema: Schema<BrowserGetTextParams>;
export declare const browserQueryDomParamsSchema: Schema<BrowserQueryDomParams>;
export declare const browserExecuteJavascriptParamsSchema: Schema<BrowserExecuteJavascriptParams>;
export declare const computerMagicCursorParamsSchema: Schema<ComputerMagicCursorParams>;

export declare function createCuaClient(options?: CuaClientOptions): CuaClient;
export declare const cua: CuaClient;

export declare function daemonCall(
  method: string,
  params?: Record<string, unknown> | null,
  timeoutMs?: number,
): Promise<unknown>;

export declare function windowState(params: ComputerWindowStateParams): Promise<unknown>;
export declare function elementAction(params: ComputerElementActionParams): Promise<unknown>;
export declare function typeElement(params: ComputerTypeElementParams): Promise<unknown>;
export declare function setValue(params: ComputerSetValueParams): Promise<unknown>;
export declare function pressKey(params: ComputerPressKeyParams): Promise<unknown>;
export declare function hotkey(params: ComputerHotkeyParams): Promise<unknown>;
export declare function focusWindow(params: ComputerFocusWindowParams): Promise<unknown>;
export declare function launchApp(params: ComputerLaunchAppParams): Promise<unknown>;
export declare function typeWindowText(params: ComputerTypeWindowTextParams): Promise<unknown>;
export declare function typeText(params: ComputerTypeTextParams): Promise<unknown>;
export declare function click(params: ComputerClickParams): Promise<unknown>;
export declare function doubleClick(params: ComputerDoubleClickParams): Promise<unknown>;
export declare function rightClick(params: ComputerRightClickParams): Promise<unknown>;
export declare function scroll(params: ComputerScrollParams): Promise<unknown>;
export declare function drag(params: ComputerDragParams): Promise<unknown>;
export declare function verify(params: ComputerVerifyParams): Promise<unknown>;
export declare function captureWindow(params: CaptureWindowParams): Promise<unknown>;
export declare function screenshotRegion(params: CaptureRegionParams): Promise<unknown>;
export declare function zoomArtifact(params: ZoomArtifactParams): Promise<unknown>;
export declare function analyzeWindow(params: VisionAnalyzeWindowParams): Promise<unknown>;
export declare function analyzeArtifact(params: VisionAnalyzeArtifactParams): Promise<unknown>;
export declare function browserGetText(params: BrowserGetTextParams): Promise<unknown>;
export declare function browserQueryDom(params: BrowserQueryDomParams): Promise<unknown>;
export declare function browserExecuteJavascript(params: BrowserExecuteJavascriptParams): Promise<unknown>;
export declare function magicCursor(params: ComputerMagicCursorParams): Promise<unknown>;
