import type { z } from "zod";

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

export interface ComputerClickParams extends WindowTarget, PointTarget, ActionBase {
  button?: "left" | "right" | "secondary" | "context";
  transport?: ComputerClickTransport;
  axLabel?: string;
  targetText?: string;
  noFocus?: boolean;
  label?: string;
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
  click(params: ComputerClickParams): Promise<unknown>;
  magicCursor(params: ComputerMagicCursorParams): Promise<unknown>;
}

export declare const computerTreatmentSchema: z.ZodType<ComputerTreatment>;
export declare const computerClickTransportSchema: z.ZodType<ComputerClickTransport>;
export declare const cursorStyleSchema: z.ZodType<CursorStyle>;
export declare const cursorShapeSchema: z.ZodType<CursorShape>;
export declare const cursorSizeSchema: z.ZodType<CursorSize>;
export declare const cursorTrailSchema: z.ZodType<CursorTrail>;
export declare const cursorMotionSchema: z.ZodType<CursorMotion>;
export declare const cursorTrajectorySchema: z.ZodType<CursorTrajectory>;
export declare const cursorGlowSchema: z.ZodType<CursorGlow>;
export declare const cursorIdleSchema: z.ZodType<CursorIdle>;
export declare const cursorEdgeSchema: z.ZodType<CursorEdge>;
export declare const cursorSoundSchema: z.ZodType<CursorSound>;
export declare const captionPlacementSchema: z.ZodType<CaptionPlacement>;
export declare const computerClickParamsSchema: z.ZodType<ComputerClickParams>;
export declare const computerMagicCursorParamsSchema: z.ZodType<ComputerMagicCursorParams>;

export declare function createCuaClient(options?: CuaClientOptions): CuaClient;
export declare function click(params: ComputerClickParams): Promise<unknown>;
export declare function magicCursor(params: ComputerMagicCursorParams): Promise<unknown>;

export declare const cua: CuaClient;
