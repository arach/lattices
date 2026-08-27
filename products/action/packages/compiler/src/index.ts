import type {
  BackdropPreset,
  CompiledTimeline,
  Cue,
  RuntimeAction,
  StageViewport,
  TargetQuery,
  TargetApp,
} from "@action/protocol";

export interface SceneStepIntent {
  action: RuntimeAction["kind"];
  description: string;
  target?: TargetQuery;
  input?: Record<string, unknown>;
  preconditions?: string[];
  onAmbiguous?: "pause" | "fail";
  cue?: Omit<Cue, "id">;
}

export interface SceneIntent {
  goal: string;
  sequence: SceneStepIntent[];
}

export interface ScenarioDocument {
  id: string;
  title: string;
  targetApp: TargetApp;
  run?: {
    initialActionDelayMs?: number;
    actionCadenceMs?: number;
  };
  stage: {
    backdrop: BackdropPreset;
    viewport: Omit<StageViewport, "surfaceId">;
  };
  scene: SceneIntent;
}

export function compileScene(intent: SceneIntent): CompiledTimeline {
  const cues: Cue[] = [];

  const steps = intent.sequence.map((step, index) => {
    const cueId = step.cue ? `cue_${index + 1}` : undefined;

    if (step.cue && cueId) {
      cues.push({
        id: cueId,
        ...step.cue,
      });
    }

    return {
      id: `step_${index + 1}`,
      action: {
        id: `action_${index + 1}`,
        kind: step.action,
        description: step.description,
        target: step.target,
        input: step.input,
      },
      preconditions: step.preconditions ?? [],
      cueIds: cueId ? [cueId] : [],
      onAmbiguous: step.onAmbiguous ?? "pause",
    };
  });

  return {
    goal: intent.goal,
    cues,
    steps,
  };
}

export function compileScenario(document: ScenarioDocument): {
  document: ScenarioDocument;
  timeline: CompiledTimeline;
} {
  return {
    document,
    timeline: compileScene(document.scene),
  };
}

export function parseScenarioDocument(input: unknown): ScenarioDocument {
  if (!input || typeof input !== "object") {
    throw new Error("Scenario document must be an object.");
  }

  const document = input as Record<string, unknown>;
  const scene = document.scene as Record<string, unknown> | undefined;

  if (typeof document.id !== "string" || typeof document.title !== "string") {
    throw new Error("Scenario document must include string id and title fields.");
  }

  if (!document.targetApp || typeof document.targetApp !== "object") {
    throw new Error("Scenario document must include a targetApp object.");
  }

  if (!document.stage || typeof document.stage !== "object") {
    throw new Error("Scenario document must include a stage object.");
  }

  if (!scene || typeof scene.goal !== "string" || !Array.isArray(scene.sequence)) {
    throw new Error("Scenario document must include scene.goal and scene.sequence.");
  }

  return document as unknown as ScenarioDocument;
}
