import type {
  ExtractionQuery,
  RuntimeAction,
  SurfaceRef,
  TargetCandidate,
  TargetQuery,
} from "@action/protocol";
import {
  baseObservation,
  candidateFromSurface,
  defaultVerification,
  emptyExtractionResult,
  evidence,
  unsupportedActionResult,
} from "./helpers.js";
import type { SurfaceAdapter } from "./types.js";

const terminalBundleHints = new Set([
  "com.apple.Terminal",
  "com.googlecode.iterm2",
  "com.mitchellh.ghostty",
  "dev.warp.Warp-Stable",
]);

function bundleId(surface: SurfaceRef): string | undefined {
  return surface.id.startsWith("surface_")
    ? surface.id.slice("surface_".length).replace(/_/g, ".")
    : undefined;
}

export const tmuxAdapter: SurfaceAdapter = {
  id: "tmux",
  label: "tmux",
  priority: 60,
  capabilities: ["observe", "resolve", "act", "extract", "capture-hints", "verify"],

  canHandle(surface: SurfaceRef) {
    const id = bundleId(surface);
    const matched = surface.kind === "window" && !!id && terminalBundleHints.has(id);

    return {
      matched,
      confidence: matched ? 0.58 : 0,
      reason: matched
        ? "Terminal-hosted windows may expose tmux panes through complementary shell state."
        : "tmux adapter only handles known terminal host windows.",
      evidence: id ? { bundleId: id } : undefined,
    };
  },

  async observe(context) {
    return baseObservation(context.surface, context, {
      kind: "terminal",
      host: "unknown",
      panes: [],
      metadata: {
        status: "stub",
        next: "Wire tmux list-panes/capture-pane/send-keys through a constrained host helper.",
      },
    });
  },

  async resolve(query: TargetQuery, observation): Promise<TargetCandidate[]> {
    return [
      {
        ...candidateFromSurface(observation.surface, query.text ?? query.semanticId ?? "tmux pane", "tmux"),
        confidence: 0.42,
        evidence: [
          evidence("tmux", "tmux pane resolution stub; shell metadata is not wired yet.", {
            rect: observation.surface.bounds,
            confidence: 0.42,
          }),
        ],
        fallbackChannels: ["ax", "process", "hid"],
      },
    ];
  },

  async act(action: RuntimeAction) {
    return unsupportedActionResult(
      action.id,
      "tmux",
      "tmux actions are planned but not wired to a host helper yet.",
    );
  },

  async extract(query: ExtractionQuery) {
    return emptyExtractionResult(query, {
      status: "stub",
      command: "tmux capture-pane/list-panes integration pending",
    });
  },

  async captureHints(target) {
    return target.rect
      ? [
          {
            id: `${target.id}:tmux-capture`,
            label: target.label,
            rect: target.rect,
            reason: "tmux pane candidate frame",
            padding: 16,
            preferredAspectRatio: "16:9",
            evidence: target.evidence,
          },
        ]
      : [];
  },

  async verify() {
    return defaultVerification("tmux adapter verification is pending shell-state integration.");
  },
};
