import { mkdir, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

import type {
  BackdropPreset,
  CaptureEngine,
  CaptureProfile,
  ClickFeedbackConfig,
  CompiledTimeline,
  EngineDiagnostics,
  GuidedSessionEvent,
  GuidedSessionEventType,
  GuidedSessionPhase,
  HudControl,
  HudControlState,
  HudLogEntry,
  HudSnapshot,
  ResolvedTarget,
  RuntimeAction,
  RuntimeArtifact,
  StageInputOverlay,
  StageScene,
  StagePresentation,
  StageViewport,
  TargetApp,
  TargetQuery,
} from "@action/protocol";

import { Session } from "./session.js";
import { buildPersistedSession, buildSessionManifest } from "./session-storage.js";

function now(): string {
  return new Date().toISOString();
}

function createLogId(index: number): string {
  return `log_${index + 1}`;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function stringValue(input: unknown): string | undefined {
  return typeof input === "string" && input.length > 0 ? input : undefined;
}

function stringArray(input: unknown): string[] {
  if (!Array.isArray(input)) {
    return [];
  }

  return input.filter((value): value is string => typeof value === "string" && value.length > 0);
}

function inputOverlayForAction(action: RuntimeAction): StageInputOverlay | undefined {
  if (action.kind === "press-key") {
    const modifiers = stringArray(action.input?.modifiers);
    const keys = stringArray(action.input?.keys);
    const key = stringValue(action.input?.key);
    const overlayKeys = keys.length > 0
      ? keys
      : [...modifiers, ...(key ? [key] : [])];

    return overlayKeys.length > 0
      ? {
          kind: "keys",
          keys: overlayKeys,
        }
      : undefined;
  }

  if (action.kind === "type") {
    const text = stringValue(action.input?.overlayText) ?? stringValue(action.input?.text);
    if (!text) {
      return undefined;
    }

    const style = stringValue(action.input?.style);
    return {
      kind: "typing",
      text,
      style: style === "notes" || style === "terminal" || style === "code"
        ? style
        : "default",
    };
  }

  return undefined;
}

export interface GuidedCaptureSessionOptions {
  sessionId: string;
  outputDir: string;
  countdownSeconds?: number;
  captureProfile?: CaptureProfile;
  stageHoldMsAfterComplete?: number;
  initialActionDelayMs?: number;
  actionCadenceMs?: number;
  /**
   * Visible feedback for Action-driven clicks during the run. Off unless set: the normal macOS
   * cursor is what a guided capture shows by default.
   */
  clickFeedback?: ClickFeedbackConfig;
}

export type GuidedSessionListener = (event: GuidedSessionEvent) => void;

export class GuidedCaptureSession {
  private readonly session: Session;
  private readonly listeners = new Set<GuidedSessionListener>();
  private readonly logEntries: HudLogEntry[] = [];
  private readonly countdownSeconds: number;
  private readonly outputDir: string;
  private readonly captureProfile: CaptureProfile;
  private readonly manifestPath: string;
  private readonly sessionPath: string;
  private readonly tracePath: string;
  private readonly stageHoldMsAfterComplete: number;
  private readonly initialActionDelayMs: number;
  private readonly actionCadenceMs: number;
  private readonly clickFeedback?: ClickFeedbackConfig;
  private phase: GuidedSessionPhase = "created";
  private stage: StageScene = { backdrop: "neutral" };
  private targetApp?: TargetApp;
  private elapsedMs = 0;
  private latestCapture?: RuntimeArtifact;
  private diagnostics?: EngineDiagnostics;
  private recordingStartedAt?: number;
  private stageSummary = "Ready";
  private stageDetail?: string;
  private stepCurrent?: number;
  private stepTotal?: number;
  private stepLabel?: string;
  private inputOverlay?: StageInputOverlay;
  private stopRequested = false;
  private stagePresented = false;

  constructor(
    private readonly engine: CaptureEngine,
    options: GuidedCaptureSessionOptions,
  ) {
    this.session = new Session(options.sessionId, "capture");
    this.countdownSeconds = options.countdownSeconds ?? 3;
    this.outputDir = options.outputDir;
    this.captureProfile = options.captureProfile ?? "draft";
    this.manifestPath = `${this.outputDir}/manifest.json`;
    this.sessionPath = `${this.outputDir}/session.json`;
    this.tracePath = `${this.outputDir}/trace.json`;
    this.stageHoldMsAfterComplete = options.stageHoldMsAfterComplete ?? 0;
    this.initialActionDelayMs = options.initialActionDelayMs ?? 650;
    this.actionCadenceMs = options.actionCadenceMs ?? 900;
    this.clickFeedback = options.clickFeedback;
  }

  onEvent(listener: GuidedSessionListener): () => void {
    this.listeners.add(listener);

    return () => {
      this.listeners.delete(listener);
    };
  }

  snapshot(): HudSnapshot {
    const sessionSnapshot = this.session.snapshot();

    return {
      sessionId: sessionSnapshot.id,
      mode: sessionSnapshot.mode,
      state: sessionSnapshot.state,
      phase: this.phase,
      targetApp: this.targetApp?.name,
      elapsedMs: this.elapsedMs,
      isRecording: this.phase === "recording",
      diagnostics: this.diagnostics,
      controls: this.controls(),
      logs: [...this.logEntries],
      artifacts: this.session.artifacts(),
      stage: this.stage,
    };
  }

  trace() {
    return this.session.trace();
  }

  async stageScene(input: {
    backdrop: BackdropPreset;
    viewport: StageViewport;
    targetApp: TargetApp;
  }): Promise<HudSnapshot> {
    await this.ensureOutputDir();
    this.session.transition("preflight", { reason: "prepare guided capture" });
    this.setPhase("staging", "Preparing stage");
    this.diagnostics = await this.engine.diagnostics();

    this.targetApp = input.targetApp;
    this.stage = {
      backdrop: input.backdrop,
      viewport: input.viewport,
      targetApp: input.targetApp,
    };

    await this.engine.setBackdrop(input.backdrop);
    this.emit("backdrop.selected", `Backdrop set to ${input.backdrop}`, {
      backdrop: input.backdrop,
    });

    const surface = await this.engine.launchApp(input.targetApp);
    await this.engine.focusSurface(surface.id);
    const configuredViewport = await this.engine.configureViewport({
      ...input.viewport,
      surfaceId: surface.id,
    });

    this.stage = {
      ...this.stage,
      viewport: configuredViewport,
    };
    this.stagePresented = true;
    await this.syncStagePresentation("Stage ready", `${input.targetApp.name} framed in viewport`);
    await this.engine.focusSurface(surface.id);

    this.emit("app.launched", `Opened ${input.targetApp.name}`, {
      app: input.targetApp,
      surface,
    });
    this.emit("viewport.updated", `Viewport fit to ${surface.label}`, {
      viewport: this.stage.viewport,
    });

    this.session.transition("ready", { reason: "stage prepared" });
    this.addLog("info", "stage.ready", `${input.targetApp.name} is ready to record`);
    await this.persistSessionFiles();

    return this.snapshot();
  }

  async refreshDiagnostics(): Promise<HudSnapshot> {
    this.diagnostics = await this.engine.diagnostics();
    return this.snapshot();
  }

  async requestPermissions(): Promise<HudSnapshot> {
    this.diagnostics = await this.engine.requestPermissions();
    this.addLog("info", "permissions.requested", "Requested native permissions");
    return this.snapshot();
  }

  async openPermissionSettings(kind: "accessibility" | "screen-recording"): Promise<HudSnapshot> {
    await this.engine.openPermissionSettings(kind);
    this.addLog("info", "permissions.settings_opened", `Opened ${kind} settings`);
    return this.snapshot();
  }

  async beginRun(timeline: CompiledTimeline): Promise<HudSnapshot> {
    if (this.session.snapshot().state !== "ready") {
      throw new Error("Session must be ready before recording begins.");
    }

    this.setPhase("countdown", "Countdown started");
    this.stepTotal = timeline.steps.length;
    this.stepCurrent = undefined;
    this.stepLabel = undefined;
    this.inputOverlay = undefined;
    this.stopRequested = false;

    for (let remaining = this.countdownSeconds; remaining > 0; remaining -= 1) {
      if (this.stopRequested) {
        break;
      }
      this.emit("countdown.tick", `Recording in ${remaining}`, {
        remaining,
        total: this.countdownSeconds,
      });
      await sleep(1000);
    }

    if (this.stopRequested) {
      this.setPhase("staging", "Run aborted before capture");
      return this.snapshot();
    }

    const capturePath = `${this.outputDir}/capture.mov`;
    const surfaceId = this.stage.viewport?.surfaceId;
    if (surfaceId) {
      await this.engine.focusSurface(surfaceId);
    }
    await this.engine.startCapture({
      sessionId: this.session.snapshot().id,
      outputPath: capturePath,
      viewport: this.stage.viewport,
      profile: this.captureProfile,
      clickFeedback: this.clickFeedback,
    });

    this.session.transition("running", { reason: "capture started" });
    this.recordingStartedAt = Date.now();
    this.setPhase("recording", "Recording");
    this.emit("recording.started", "Capture started", {
      outputPath: capturePath,
    });
    await this.persistSessionFiles();

    if (this.initialActionDelayMs > 0) {
      await sleep(this.initialActionDelayMs);
    }

    await this.executeTimeline(timeline);

    return this.snapshot();
  }

  async pause(): Promise<HudSnapshot> {
    if (this.session.snapshot().state !== "running") {
      throw new Error("Cannot pause when the session is not recording.");
    }

    await this.engine.pauseCapture();
    this.session.transition("paused", { reason: "user paused recording" });
    this.setPhase("paused", "Recording paused");
    this.emit("recording.paused", "Capture paused", {});
    await this.persistSessionFiles();

    return this.snapshot();
  }

  async resume(): Promise<HudSnapshot> {
    if (this.session.snapshot().state !== "paused") {
      throw new Error("Cannot resume when the session is not paused.");
    }

    await this.engine.resumeCapture();
    this.session.transition("running", { reason: "resume recording" });
    this.setPhase("recording", "Recording resumed");
    this.emit("recording.resumed", "Capture resumed", {});
    await this.persistSessionFiles();

    return this.snapshot();
  }

  async captureScreenshot(
    name = "screenshot-final.png",
    scope: "viewport" | "full" = "viewport",
  ): Promise<RuntimeArtifact> {
    const outputPath = `${this.outputDir}/${name}`;
    const artifact = scope === "full"
      ? await this.engine.captureFullScreenshot(outputPath)
      : await this.engine.captureScreenshot(outputPath);
    this.session.registerArtifact(artifact);
    this.emit("artifact.created", `Saved ${artifact.kind}`, {
      artifact,
    });
    await this.persistSessionFiles();

    return artifact;
  }

  async stop(): Promise<HudSnapshot> {
    const state = this.session.snapshot().state;

    if (!["running", "paused"].includes(state)) {
      throw new Error("Cannot stop when the session is not active.");
    }

    this.session.transition("completing", { reason: "finalize guided capture" });
    this.inputOverlay = undefined;
    this.setPhase("completing", "Finalizing run");

    const capture = await this.engine.stopCapture();
    this.latestCapture = capture;
    this.session.registerArtifact(capture);
    this.emit("recording.stopped", "Capture stopped", {
      artifact: capture,
    });

    this.session.registerArtifact({
      kind: "trace",
      path: this.tracePath,
      metadata: {
        eventCount: this.session.trace().length,
      },
    });

    this.session.transition("completed", { reason: "guided capture complete" });
    if (this.recordingStartedAt) {
      this.elapsedMs = Date.now() - this.recordingStartedAt;
    }
    this.setPhase("completed", "Run completed");
    await this.persistSessionFiles();
    if (this.stageHoldMsAfterComplete > 0) {
      await sleep(this.stageHoldMsAfterComplete);
      await this.engine.clearStage();
      this.stagePresented = false;
    } else if (this.stageHoldMsAfterComplete === 0) {
      await this.engine.clearStage();
      this.stagePresented = false;
    }

    return this.snapshot();
  }

  async replayLastRun(): Promise<void> {
    if (!this.latestCapture) {
      throw new Error("No capture artifact is available to replay.");
    }

    this.emit("replay.requested", "Replaying latest capture", {
      artifact: this.latestCapture,
    });
    await this.engine.replayArtifact(this.latestCapture.path);
  }

  requestStop(): void {
    this.stopRequested = true;
    this.addLog("warning", "run.stop_requested", "Stop requested from stage controls");
  }

  async clearStage(): Promise<void> {
    await this.engine.clearStage();
    this.stagePresented = false;
  }

  async consumeStageControls(): Promise<string[]> {
    return this.engine.consumeStageControls();
  }

  private async executeTimeline(timeline: CompiledTimeline): Promise<void> {
    for (const [index, step] of timeline.steps.entries()) {
      if (this.stopRequested) {
        break;
      }
      const surfaceId = this.stage.viewport?.surfaceId;
      if (surfaceId) {
        await this.engine.focusSurface(surfaceId);
      }
      this.stepCurrent = index + 1;
      this.stepLabel = step.action.description;
      this.inputOverlay = inputOverlayForAction(step.action);
      this.session.recordAction(step.action, "planned");
      this.addLog("info", "action.planned", step.action.description);

      let resolvedTarget: ResolvedTarget | undefined;
      if (step.action.target) {
        resolvedTarget = await this.engine.resolveTarget(step.action.target);
        this.session.recordResolution(step.action.target, resolvedTarget);
        this.emit("target.resolved", `Resolved ${resolvedTarget.label}`, {
          target: resolvedTarget,
        });
      }

      this.session.recordAction(step.action, "started");
      this.emit("action.started", step.action.description, {
        action: step.action,
        target: resolvedTarget,
      });

      try {
        await this.engine.performAction(step.action, resolvedTarget);
        this.session.recordAction(step.action, "completed");
        this.emit("action.completed", step.action.description, {
          action: step.action,
        });
        if (this.actionCadenceMs > 0 && index < timeline.steps.length - 1) {
          await sleep(this.actionCadenceMs);
        }
      } catch (error) {
        const detail = error instanceof Error ? error.message : "Unknown action failure";
        this.session.recordAction(step.action, "failed", detail);
        this.emit("action.failed", `${step.action.description} failed`, {
          action: step.action,
          detail,
        });
        throw error;
      }
    }

    this.inputOverlay = undefined;
    await this.syncStagePresentation();
  }

  private controls(): HudControlState[] {
    const phase = this.phase;
    const captureAvailable = Boolean(this.latestCapture);

    return [
      this.control("start", phase === "created" || phase === "staging" || phase === "paused"),
      this.control("pause", phase === "recording"),
      this.control("stop", phase === "recording" || phase === "paused"),
      this.control("replay-last-run", captureAvailable),
      this.control("quit", true),
    ];
  }

  private control(control: HudControl, enabled: boolean): HudControlState {
    const label = control === "start" && this.phase === "paused" ? "Resume" : undefined;
    return { control, enabled, label };
  }

  private setPhase(next: GuidedSessionPhase, summary: string): void {
    this.phase = next;
    this.emit("phase.changed", summary, {
      phase: next,
    });
  }

  private emit<TPayload extends Record<string, unknown>>(
    type: GuidedSessionEventType,
    summary: string,
    payload: TPayload,
  ): void {
    const event: GuidedSessionEvent<TPayload> = {
      sessionId: this.session.snapshot().id,
      at: now(),
      type,
      summary,
      payload,
    };

    this.addLog("info", type, summary, event.at);
    this.stageSummary = summary;
    if (type === "action.started" || type === "action.completed" || type === "action.failed") {
      this.stageDetail = summary;
    } else if (type === "countdown.tick") {
      this.stageDetail = summary;
    }
    void this.syncStagePresentation(summary, this.stageDetail, type === "countdown.tick" ? (payload as { remaining?: number }).remaining : undefined);

    for (const listener of this.listeners) {
      listener(event);
    }
  }

  private addLog(
    level: HudLogEntry["level"],
    eventType: string,
    message: string,
    at = now(),
  ): void {
    this.logEntries.push({
      id: createLogId(this.logEntries.length),
      at,
      level,
      eventType,
      message,
    });
  }

  private async ensureOutputDir(): Promise<void> {
    await mkdir(this.outputDir, { recursive: true });
  }

  private async persistSessionFiles(): Promise<void> {
    await this.ensureOutputDir();
    const snapshot = this.snapshot();
    const sessionSnapshot = this.session.snapshot();
    const trace = this.session.trace();
    const manifest = buildSessionManifest({
      sessionId: sessionSnapshot.id,
      mode: sessionSnapshot.mode,
      generatedAt: now(),
      outputDir: this.outputDir,
      tracePath: this.tracePath,
      artifacts: snapshot.artifacts,
    });
    const persistedSession = buildPersistedSession({
      mode: sessionSnapshot.mode,
      outputDir: this.outputDir,
      tracePath: this.tracePath,
      manifestPath: this.manifestPath,
      snapshot,
      createdAt: sessionSnapshot.createdAt,
      updatedAt: sessionSnapshot.updatedAt,
      trace,
    });

    await writeFile(
      this.tracePath,
      JSON.stringify(trace, null, 2),
    );

    await writeFile(
      this.manifestPath,
      JSON.stringify(manifest, null, 2),
    );

    await writeFile(
      this.sessionPath,
      JSON.stringify(persistedSession, null, 2),
    );
  }

  private presentation(summary: string, detail?: string, countdownRemaining?: number): StagePresentation {
    return {
      sessionId: this.session.snapshot().id,
      phase: this.phase,
      backdrop: this.stage.backdrop,
      viewport: this.stage.viewport,
      targetApp: this.targetApp?.name,
      summary,
      detail,
      countdownRemaining,
      elapsedMs: this.elapsedMs,
      isRecording: this.phase === "recording",
      stepCurrent: this.stepCurrent,
      stepTotal: this.stepTotal,
      stepLabel: this.stepLabel,
      inputOverlay: this.inputOverlay,
      recentLogs: this.logEntries.slice(-12).map((entry) => entry.message),
    };
  }

  private async syncStagePresentation(
    summary = this.stageSummary,
    detail = this.stageDetail,
    countdownRemaining?: number,
  ): Promise<void> {
    if (!this.stage.viewport || !this.stagePresented) {
      return;
    }

    await this.engine.presentStage(this.presentation(summary, detail, countdownRemaining));
  }
}

export class MockCaptureEngine implements CaptureEngine {
  readonly actions: Array<{
    action: RuntimeAction;
    target?: ResolvedTarget;
  }> = [];

  private activeCapturePath?: string;
  private static readonly screenshotPixel =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9pFvdcAAAAAASUVORK5CYII=";

  async diagnostics(): Promise<EngineDiagnostics> {
    return {
      accessibility: "granted",
      screenRecording: "granted",
      notes: ["Mock engine reports permissions as granted for local development."],
    };
  }

  async requestPermissions(): Promise<EngineDiagnostics> {
    return this.diagnostics();
  }

  async openPermissionSettings(_kind: "accessibility" | "screen-recording"): Promise<void> {}

  async presentStage(_presentation: StagePresentation): Promise<void> {}

  async clearStage(): Promise<void> {}

  async setBackdrop(_backdrop: BackdropPreset): Promise<void> {}

  async launchApp(app: TargetApp) {
    return {
      id: `surface_${app.name.toLowerCase().replace(/\s+/g, "_")}`,
      kind: "window" as const,
      label: `${app.name} Window`,
    };
  }

  async focusSurface(_surfaceId: string): Promise<void> {}

  async configureViewport(viewport: StageViewport): Promise<StageViewport> {
    return viewport;
  }

  async startCapture(input: { outputPath: string }): Promise<void> {
    this.activeCapturePath = input.outputPath;
  }

  async pauseCapture(): Promise<void> {}

  async resumeCapture(): Promise<void> {}

  async stopCapture(): Promise<RuntimeArtifact> {
    const path = this.activeCapturePath ?? "artifacts/sessions/mock/capture.mov";
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, "");

    return {
      kind: "raw-capture",
      path,
      metadata: {
        placeholder: true,
        reason: "Mock capture artifact",
      },
    };
  }

  async captureScreenshot(path: string): Promise<RuntimeArtifact> {
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, Buffer.from(MockCaptureEngine.screenshotPixel, "base64"));

    return {
      kind: "screenshot",
      path,
    };
  }

  async captureFullScreenshot(path: string): Promise<RuntimeArtifact> {
    return this.captureScreenshot(path);
  }

  async consumeStageControls(): Promise<string[]> {
    return [];
  }

  async resolveTarget(query: TargetQuery): Promise<ResolvedTarget> {
    return {
      id: query.semanticId ?? query.text ?? "target",
      mode: query.point ? "coordinate" : "semantic",
      confidence: 0.96,
      label: query.semanticId ?? query.text ?? "Resolved Target",
      surfaceId: query.surfaceId,
    };
  }

  async performAction(action: RuntimeAction, target?: ResolvedTarget): Promise<void> {
    await sleep(250);
    this.actions.push({ action, target });
  }

  async replayArtifact(_path: string): Promise<void> {}
}
