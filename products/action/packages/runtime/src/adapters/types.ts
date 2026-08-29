import type {
  ActionResult,
  AdapterCapability,
  AdapterMatch,
  CaptureHint,
  ExtractionQuery,
  ExtractionResult,
  ObserveContext,
  RuntimeAction,
  SurfaceObservation,
  SurfaceRef,
  TargetCandidate,
  TargetQuery,
  VerificationResult,
  VerifyContext,
} from "@action/protocol";

export interface SurfaceAdapter {
  id: string;
  label: string;
  priority: number;
  capabilities: AdapterCapability[];
  canHandle(surface: SurfaceRef): Promise<AdapterMatch> | AdapterMatch;
  observe(context: ObserveContext): Promise<SurfaceObservation>;
  resolve(query: TargetQuery, observation: SurfaceObservation): Promise<TargetCandidate[]>;
  act(action: RuntimeAction, target: TargetCandidate): Promise<ActionResult>;
  extract(query: ExtractionQuery, observation: SurfaceObservation): Promise<ExtractionResult>;
  captureHints(target: TargetCandidate): Promise<CaptureHint[]>;
  verify(result: ActionResult, context: VerifyContext): Promise<VerificationResult>;
}
