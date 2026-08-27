import type {
  Observation,
  ResolvedTarget,
  RuntimeAction,
  RuntimeArtifact,
  SessionMode,
  SessionSnapshot,
  SessionState,
  TargetQuery,
  TraceEvent,
  TransitionOptions,
} from "@action/protocol";

const validTransitions: Record<SessionState, SessionState[]> = {
  created: ["preflight", "cancelled"],
  preflight: ["ready", "failed", "cancelled"],
  ready: ["running", "failed", "cancelled"],
  running: ["paused", "completing", "failed", "cancelled"],
  paused: ["running", "cancelled", "failed"],
  completing: ["completed", "failed"],
  completed: [],
  failed: [],
  cancelled: [],
};

function now(): string {
  return new Date().toISOString();
}

export class InvalidSessionTransitionError extends Error {
  constructor(
    readonly from: SessionState,
    readonly to: SessionState,
  ) {
    super(`Invalid session transition: ${from} -> ${to}`);
    this.name = "InvalidSessionTransitionError";
  }
}

export class Session {
  private state: SessionState = "created";
  private readonly traceEvents: TraceEvent[] = [];
  private readonly producedArtifacts: RuntimeArtifact[] = [];
  private readonly createdAt = now();
  private updatedAt = this.createdAt;

  constructor(
    public readonly id: string,
    public readonly mode: SessionMode = "capture",
  ) {}

  snapshot(): SessionSnapshot {
    return {
      id: this.id,
      mode: this.mode,
      state: this.state,
      createdAt: this.createdAt,
      updatedAt: this.updatedAt,
      traceCount: this.traceEvents.length,
      artifactCount: this.producedArtifacts.length,
    };
  }

  trace(): TraceEvent[] {
    return [...this.traceEvents];
  }

  artifacts(): RuntimeArtifact[] {
    return [...this.producedArtifacts];
  }

  transition(next: SessionState, options: TransitionOptions = {}): void {
    if (!validTransitions[this.state].includes(next)) {
      throw new InvalidSessionTransitionError(this.state, next);
    }

    const at = options.at ?? now();
    const previous = this.state;
    this.state = next;
    this.updatedAt = at;
    this.traceEvents.push({
      type: "session.state_changed",
      at,
      from: previous,
      to: next,
      reason: options.reason,
    });
  }

  recordObservation(observation: Observation): void {
    this.updatedAt = observation.at;
    this.traceEvents.push({
      type: "observation.recorded",
      at: observation.at,
      observation,
    });
  }

  recordResolution(query: TargetQuery, result: ResolvedTarget, at = now()): void {
    this.updatedAt = at;
    this.traceEvents.push({
      type: "target.resolved",
      at,
      query,
      result,
    });
  }

  recordAction(
    action: RuntimeAction,
    status: "planned" | "started" | "completed" | "failed",
    detail?: string,
    at = now(),
  ): void {
    this.updatedAt = at;
    this.traceEvents.push({
      type: "action.recorded",
      at,
      entry: {
        action,
        status,
        at,
        detail,
      },
    });
  }

  registerArtifact(artifact: RuntimeArtifact, at = now()): void {
    this.updatedAt = at;
    this.producedArtifacts.push(artifact);
    this.traceEvents.push({
      type: "artifact.registered",
      at,
      artifact,
    });
  }
}
