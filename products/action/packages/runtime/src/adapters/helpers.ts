import type {
  ActionResult,
  AXSnapshot,
  ExtractionQuery,
  ExtractionResult,
  ObserveContext,
  SurfaceObservation,
  SurfaceRef,
  TargetCandidate,
  TargetEvidence,
  VerificationResult,
} from "@action/protocol";

export function emptyAXSnapshot(at = new Date().toISOString()): AXSnapshot {
  return {
    source: "accessibility",
    capturedAt: at,
    nodes: [],
  };
}

export function baseObservation(
  surface: SurfaceRef,
  context: ObserveContext,
  semantic?: SurfaceObservation["semantic"],
): SurfaceObservation {
  const at = context.now ?? new Date().toISOString();
  const ax = context.ax ?? emptyAXSnapshot(at);

  return {
    surface,
    ax,
    native: context.native ?? {},
    semantic,
    freshness: {
      axCapturedAt: ax.capturedAt,
      semanticCapturedAt: semantic ? at : undefined,
    },
  };
}

export function unsupportedActionResult(id: string, channel: ActionResult["channel"], detail: string): ActionResult {
  return {
    id,
    at: new Date().toISOString(),
    status: "needs-user",
    channel,
    detail,
  };
}

export function emptyExtractionResult(query: ExtractionQuery, data: Record<string, unknown> = {}): ExtractionResult {
  return {
    id: query.id ?? query.kind ?? "extraction",
    at: new Date().toISOString(),
    data,
  };
}

export function defaultVerification(summary: string, ok = false): VerificationResult {
  return {
    ok,
    confidence: ok ? 0.8 : 0,
    summary,
  };
}

export function evidence(
  source: TargetEvidence["source"],
  summary: string,
  extra: Omit<TargetEvidence, "source" | "summary"> = {},
): TargetEvidence {
  return {
    source,
    summary,
    ...extra,
  };
}

export function candidateFromSurface(surface: SurfaceRef, label: string, channel: TargetCandidate["preferredActionChannel"]): TargetCandidate {
  return {
    id: `${surface.id}:${label.toLowerCase().replace(/[^a-z0-9]+/g, "-")}`,
    label,
    rect: surface.bounds,
    confidence: 0.4,
    evidence: [
      evidence("native", `Fallback candidate for ${surface.label}`, { rect: surface.bounds }),
    ],
    preferredActionChannel: channel,
    fallbackChannels: ["ax", "hid"],
  };
}
