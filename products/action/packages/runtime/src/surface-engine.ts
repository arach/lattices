import type { CaptureEngine, RuntimeArtifact } from "@action/protocol";
import type {
  CurrentSurfaceAccessibilityResult,
  CurrentSurfaceCaptureResult,
  CurrentSurfaceSnapshot,
} from "./macos.js";
import type { OCRResult } from "./vision.js";

/**
 * What inspection and the MCP server need from an engine beyond CaptureEngine:
 * the frontmost surface and a screenshot of it. Both the native macOS engine
 * and the remote engine (LAT-013) implement it.
 *
 * Optional members are platform features. An accessibility tree exists only on
 * macOS; an engine that runs OCR where the pixels are (a remote host) provides
 * `ocrScreenshot` so callers do not need the native OCR host locally.
 */
export interface SurfaceEngine extends CaptureEngine {
  readonly platform: "macos" | "remote";
  currentSurface(): Promise<CurrentSurfaceSnapshot>;
  captureCurrentSurfaceScreenshot(path: string): Promise<CurrentSurfaceCaptureResult>;
  captureSurfaceScreenshot(currentSurface: CurrentSurfaceSnapshot, path: string): Promise<RuntimeArtifact>;
  captureSurfaceAccessibilitySnapshot?(
    currentSurface: CurrentSurfaceSnapshot,
    path: string,
  ): Promise<Pick<CurrentSurfaceAccessibilityResult, "artifact" | "nodeCount">>;
  ocrSurface?(
    currentSurface: CurrentSurfaceSnapshot,
    imagePath: string,
    outputPath: string,
  ): Promise<{ artifact: RuntimeArtifact; result: OCRResult }>;
}
