import { mkdir, writeFile } from "node:fs/promises"
import { resolve } from "node:path"

import type {
  Bounds,
  GuidedSessionPhase,
  HudSnapshot,
  PersistedRuntimeSession,
  RuntimeAction,
  SessionArtifactManifest,
  StageViewport,
} from "@action/protocol"

import { Session } from "./session.js"
import {
  type CurrentSurfaceSnapshot,
  MacOSCommandEngine,
} from "./macos.js"
import { buildPersistedSession, buildSessionManifest } from "./session-storage.js"
import {
  type ViewportSettleProvider,
  type ViewportSettleProviderRequest,
  createViewportSettleProvider,
  viewportSettlePrompt,
} from "./providers/minimax-pie.js"

function now(): string {
  return new Date().toISOString()
}

function sessionSuffix(): string {
  return now().replace(/[-:.]/g, "").replace("T", "_").replace("Z", "")
}

function outputDirFor(sessionId: string): string {
  return resolve(process.cwd(), "artifacts", "sessions", sessionId)
}

function viewportFor(bounds: Bounds): StageViewport {
  return {
    id: "settle",
    bounds,
    dimming: "surround",
  }
}

function buildInspectionSnapshot(input: {
  sessionId: string
  state: HudSnapshot["state"]
  phase: GuidedSessionPhase
  targetApp?: CurrentSurfaceSnapshot
  targetViewport: Bounds
  artifacts: HudSnapshot["artifacts"]
}): HudSnapshot {
  return {
    sessionId: input.sessionId,
    mode: "inspection",
    state: input.state,
    phase: input.phase,
    targetApp: input.targetApp?.appName,
    elapsedMs: 0,
    isRecording: false,
    controls: [],
    logs: [],
    artifacts: input.artifacts,
    stage: {
      backdrop: "neutral",
      viewport: input.targetViewport ? viewportFor(input.targetViewport) : undefined,
      targetApp: input.targetApp
        ? {
            name: input.targetApp.appName,
            bundleId: input.targetApp.bundleId,
          }
        : undefined,
    },
  }
}

async function persistInspectionFiles(input: {
  outputDir: string
  session: Session
  phase: GuidedSessionPhase
  targetApp?: CurrentSurfaceSnapshot
  targetViewport: Bounds
}): Promise<{
  manifest: SessionArtifactManifest
  sessionRecord: PersistedRuntimeSession
}> {
  const tracePath = resolve(input.outputDir, "trace.json")
  const manifestPath = resolve(input.outputDir, "manifest.json")
  const sessionPath = resolve(input.outputDir, "session.json")
  const trace = input.session.trace()
  const sessionSnapshot = input.session.snapshot()
  const hudSnapshot = buildInspectionSnapshot({
    sessionId: sessionSnapshot.id,
    state: sessionSnapshot.state,
    phase: input.phase,
    targetApp: input.targetApp,
    targetViewport: input.targetViewport,
    artifacts: input.session.artifacts(),
  })
  const manifest = buildSessionManifest({
    sessionId: sessionSnapshot.id,
    mode: sessionSnapshot.mode,
    generatedAt: now(),
    outputDir: input.outputDir,
    tracePath,
    artifacts: hudSnapshot.artifacts,
  })
  const sessionRecord = buildPersistedSession({
    mode: sessionSnapshot.mode,
    outputDir: input.outputDir,
    tracePath,
    manifestPath,
    snapshot: hudSnapshot,
    createdAt: sessionSnapshot.createdAt,
    updatedAt: sessionSnapshot.updatedAt,
    trace,
  })

  await writeFile(tracePath, JSON.stringify(trace, null, 2))
  await writeFile(manifestPath, JSON.stringify(manifest, null, 2))
  await writeFile(sessionPath, JSON.stringify(sessionRecord, null, 2))

  return {
    manifest,
    sessionRecord,
  }
}

function dragActionFor(turn: number, bundleId: string, input: {
  from: { x: number; y: number }
  to: { x: number; y: number }
  durationMs?: number
}): RuntimeAction {
  return {
    id: `viewport_settle_drag_${turn}`,
    kind: "drag",
    description: `Move ${bundleId} toward viewport target`,
    input: {
      from: input.from,
      to: input.to,
      durationMs: input.durationMs ?? 260,
    },
  }
}

export interface ViewportSettleTurnSummary {
  turn: number
  screenshotPath: string
  requestPath: string
  responsePath: string
  status: "drag" | "done"
  summary: string
}

export interface SettleCurrentSurfaceViewportOptions {
  engine?: MacOSCommandEngine
  outputDir?: string
  provider?: ViewportSettleProvider
  providerId?: "mock" | "pie-minimax"
  sessionId?: string
  targetViewport: Bounds
  maxTurns?: number
}

export interface SettleCurrentSurfaceViewportResult {
  currentSurface: CurrentSurfaceSnapshot
  manifest: SessionArtifactManifest
  session: PersistedRuntimeSession
  provider: string
  targetViewport: Bounds
  finalBounds?: Bounds
  settled: boolean
  summary: string
  turns: ViewportSettleTurnSummary[]
}

export async function settleCurrentSurfaceViewport(
  options: SettleCurrentSurfaceViewportOptions,
): Promise<SettleCurrentSurfaceViewportResult> {
  const sessionId = options.sessionId ?? `inspection_settle_current_surface_${sessionSuffix()}`
  const outputDir = options.outputDir ?? outputDirFor(sessionId)
  const engine = options.engine ?? new MacOSCommandEngine()
  const provider = options.provider ?? createViewportSettleProvider(options.providerId ?? "pie-minimax")
  const session = new Session(sessionId, "inspection")
  const maxTurns = Math.max(1, options.maxTurns ?? 2)
  const targetViewport = options.targetViewport
  let phase: GuidedSessionPhase = "created"
  let currentSurface: CurrentSurfaceSnapshot | undefined
  let finalBounds: Bounds | undefined
  let settled = false
  let summary = "Viewport settle did not complete"
  const turns: ViewportSettleTurnSummary[] = []

  await mkdir(outputDir, { recursive: true })

  try {
    session.transition("preflight", { reason: "resolve current surface for viewport settle" })
    phase = "observing"

    currentSurface = await engine.currentSurface()
    session.recordObservation({
      kind: "window",
      source: "engine",
      at: now(),
      surfaceId: currentSurface.surface.id,
      data: {
        bundleId: currentSurface.bundleId,
        appName: currentSurface.appName,
        bounds: currentSurface.surface.bounds,
        targetViewport,
      },
    })

    const surfacePath = resolve(outputDir, "surface.json")
    await writeFile(surfacePath, JSON.stringify(currentSurface, null, 2))
    session.registerArtifact({
      kind: "focus-metadata",
      path: surfacePath,
      metadata: {
        bundleId: currentSurface.bundleId,
        appName: currentSurface.appName,
        surfaceId: currentSurface.surface.id,
      },
    })

    await engine.setWindowFrame(currentSurface.bundleId, targetViewport)
    finalBounds = await engine.readWindowBounds(currentSurface.bundleId)

    const axPath = resolve(outputDir, "ax-snapshot.json")
    const axSnapshot = await engine.captureSurfaceAccessibilitySnapshot(currentSurface, axPath)
    session.recordObservation({
      kind: "accessibility",
      source: "engine",
      at: now(),
      surfaceId: currentSurface.surface.id,
      data: {
        bundleId: currentSurface.bundleId,
        nodeCount: axSnapshot.nodeCount,
        artifactPath: axPath,
      },
    })
    session.registerArtifact(axSnapshot.artifact)

    session.transition("ready", { reason: "viewport settle context captured" })
    session.transition("running", { reason: "viewport settle active" })

    for (let turn = 1; turn <= maxTurns; turn += 1) {
      phase = "observing"
      const screenshotPath = resolve(outputDir, `turn-${String(turn).padStart(2, "0")}-screen.png`)
      const screenshot = await engine.captureFullScreenshot(screenshotPath)
      session.registerArtifact({
        ...screenshot,
        metadata: {
          ...screenshot.metadata,
          turn,
          workflow: "viewport-settle",
          provider: provider.id,
        },
      })

      const requestPath = resolve(outputDir, `turn-${String(turn).padStart(2, "0")}-request.json`)
      const request: ViewportSettleProviderRequest = {
        kind: "viewport-settle",
        sessionId,
        turn,
        maxTurns,
        provider: provider.id,
        model: provider.id.replace(/^pie:/, ""),
        screenshotPath,
        axSnapshotPath: axPath,
        targetViewport,
        currentBounds: finalBounds,
        currentSurface,
        prompt: viewportSettlePrompt(),
        metadata: {
          workflow: "viewport-settle",
        },
      }
      await writeFile(requestPath, JSON.stringify(request, null, 2))
      session.registerArtifact({
        kind: "inspection-request",
        path: requestPath,
        metadata: {
          provider: provider.id,
          turn,
        },
      })

      phase = "analyzing"
      const response = await provider.analyzeViewportTurn(request)
      const responsePath = resolve(outputDir, `turn-${String(turn).padStart(2, "0")}-response.json`)
      await writeFile(responsePath, JSON.stringify(response.raw ?? response, null, 2))
      session.registerArtifact({
        kind: "inspection-response",
        path: responsePath,
        metadata: {
          provider: provider.id,
          turn,
          status: response.status,
        },
      })
      session.recordObservation({
        kind: "analysis",
        source: "runtime",
        at: now(),
        surfaceId: currentSurface.surface.id,
        data: {
          provider: provider.id,
          turn,
          status: response.status,
          summary: response.summary,
          observedBounds: response.observedBounds,
        },
      })

      turns.push({
        turn,
        screenshotPath,
        requestPath,
        responsePath,
        status: response.status,
        summary: response.summary,
      })

      summary = response.summary
      if (response.observedBounds) {
        finalBounds = response.observedBounds
      }

      if (response.status === "done") {
        settled = true
        break
      }

      if (!response.drag) {
        throw new Error(`Viewport settle provider requested drag on turn ${turn} but returned no drag payload`)
      }

      phase = "acting"
      const action = dragActionFor(turn, currentSurface.bundleId, response.drag)
      session.recordAction(action, "planned")
      session.recordAction(action, "started")
      await engine.focusSurface(currentSurface.surface.id)
      await engine.dragMouse(
        response.drag.from,
        response.drag.to,
        response.drag.durationMs ?? 260,
      )
      session.recordAction(action, "completed")
      finalBounds = await engine.readWindowBounds(currentSurface.bundleId)
    }

    const finalScreenshotPath = resolve(outputDir, "final-screen.png")
    const finalScreenshot = await engine.captureFullScreenshot(finalScreenshotPath)
    session.registerArtifact({
      ...finalScreenshot,
      metadata: {
        ...finalScreenshot.metadata,
        workflow: "viewport-settle",
        final: true,
        provider: provider.id,
      },
    })

    session.transition("completing", { reason: "persist viewport settle session" })
    session.transition("completed", { reason: settled ? "viewport settled" : "viewport settle bounded without verification" })
    phase = "completed"
  } catch (error) {
    const state = session.snapshot().state
    if (!["completed", "failed", "cancelled"].includes(state)) {
      session.transition("failed", { reason: error instanceof Error ? error.message : "viewport settle failed" })
    }
    phase = "failed"
    await persistInspectionFiles({
      outputDir,
      session,
      phase,
      targetApp: currentSurface,
      targetViewport,
    })
    throw error
  }

  const { manifest, sessionRecord } = await persistInspectionFiles({
    outputDir,
    session,
    phase,
    targetApp: currentSurface,
    targetViewport,
  })

  return {
    currentSurface: currentSurface!,
    manifest,
    session: sessionRecord,
    provider: provider.id,
    targetViewport,
    finalBounds,
    settled,
    summary,
    turns,
  }
}
