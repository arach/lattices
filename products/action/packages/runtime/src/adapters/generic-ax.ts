import type {
  ExtractionQuery,
  RuntimeAction,
  SurfaceObservation,
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

export const genericAXAdapter: SurfaceAdapter = {
  id: "generic-ax",
  label: "Generic AX",
  priority: 0,
  capabilities: ["observe", "resolve", "act", "extract", "capture-hints", "verify"],

  canHandle(surface: SurfaceRef) {
    return {
      matched: true,
      confidence: surface.kind === "window" ? 0.45 : 0.25,
      reason: "Generic AX is the fallback adapter for every surface.",
    };
  },

  async observe(context) {
    return baseObservation(context.surface, context);
  },

  async resolve(query: TargetQuery, observation: SurfaceObservation): Promise<TargetCandidate[]> {
    const normalizedText = query.text?.toLowerCase();
    const normalizedRole = query.role?.toLowerCase();

    const candidates = observation.ax.nodes
      .filter((node) => {
        const roleMatches = !normalizedRole || node.role.toLowerCase() === normalizedRole;
        const haystack = [node.title, node.detail, node.value, node.identifier]
          .filter(Boolean)
          .join(" ")
          .toLowerCase();
        const textMatches = !normalizedText || haystack.includes(normalizedText);
        return roleMatches && textMatches;
      })
      .slice(0, 12)
      .map<TargetCandidate>((node, index) => ({
        id: `${observation.surface.id}:ax:${index}`,
        label: node.title ?? node.detail ?? node.value ?? node.identifier ?? node.role,
        role: node.role,
        rect: node.frame,
        confidence: node.frame ? 0.74 : 0.58,
        evidence: [
          evidence("ax", `Matched ${node.role} in AX snapshot`, {
            rect: node.frame,
            confidence: node.frame ? 0.74 : 0.58,
            metadata: {
              title: node.title,
              detail: node.detail,
              value: node.value,
              identifier: node.identifier,
              actions: node.actions,
              settableAttributes: node.settableAttributes,
            },
          }),
        ],
        preferredActionChannel: "ax",
        fallbackChannels: ["process", "hid"],
      }));

    return candidates.length > 0
      ? candidates
      : [candidateFromSurface(observation.surface, query.text ?? query.semanticId ?? "surface", "ax")];
  },

  async act(action: RuntimeAction) {
    return unsupportedActionResult(
      action.id,
      "ax",
      "Generic AX adapter selected a target; MacOSCommandEngine still performs the concrete action.",
    );
  },

  async extract(query: ExtractionQuery, observation: SurfaceObservation) {
    return emptyExtractionResult(query, {
      nodeCount: observation.ax.nodes.length,
      roles: [...new Set(observation.ax.nodes.map((node) => node.role))].sort(),
    });
  },

  async captureHints(target) {
    return target.rect
      ? [
          {
            id: `${target.id}:capture`,
            label: target.label,
            rect: target.rect,
            reason: "AX target frame",
            padding: 24,
            preferredAspectRatio: "free",
            evidence: target.evidence,
          },
        ]
      : [];
  },

  async verify() {
    return defaultVerification("Generic AX adapter requires a fresh observation to verify action outcome.");
  },
};
