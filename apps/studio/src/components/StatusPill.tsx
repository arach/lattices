import { createStatusPalette } from "studio/atoms";
import type { StudioStatus } from "../lib/eng-docs";

export const palette = createStatusPalette<StudioStatus>({
  proposed: { tone: "info", label: "PROPOSED" },
  accepted: { tone: "ok", label: "ACCEPTED" },
  "in-flight": { tone: "warn", label: "IN-FLIGHT" },
  shipped: { tone: "neutral", label: "SHIPPED" },
});

export const StatusPill = palette.StatusPill;
export const statusToColor = palette.statusToColor;
