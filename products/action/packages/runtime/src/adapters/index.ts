import type {
  AdapterMatch,
  SurfaceRef,
} from "@action/protocol";
import { chromeAdapter } from "./chrome.js";
import { genericAXAdapter } from "./generic-ax.js";
import { tmuxAdapter } from "./tmux.js";
import type { SurfaceAdapter } from "./types.js";

export interface RegisteredAdapter {
  adapter: SurfaceAdapter;
  match: AdapterMatch;
}

export class SurfaceAdapterRegistry {
  private readonly adapters: SurfaceAdapter[] = [];

  constructor(adapters: SurfaceAdapter[] = []) {
    for (const adapter of adapters) {
      this.register(adapter);
    }
  }

  register(adapter: SurfaceAdapter): void {
    const existingIndex = this.adapters.findIndex((candidate) => candidate.id === adapter.id);
    if (existingIndex >= 0) {
      this.adapters.splice(existingIndex, 1, adapter);
    } else {
      this.adapters.push(adapter);
    }

    this.adapters.sort((left, right) => right.priority - left.priority);
  }

  list(): readonly SurfaceAdapter[] {
    return this.adapters;
  }

  async matches(surface: SurfaceRef): Promise<RegisteredAdapter[]> {
    const matched: RegisteredAdapter[] = [];

    for (const adapter of this.adapters) {
      const match = await adapter.canHandle(surface);
      if (match.matched) {
        matched.push({ adapter, match });
      }
    }

    return matched.sort((left, right) => {
      const priorityDelta = right.adapter.priority - left.adapter.priority;
      if (priorityDelta !== 0) {
        return priorityDelta;
      }

      return right.match.confidence - left.match.confidence;
    });
  }

  async best(surface: SurfaceRef): Promise<RegisteredAdapter | undefined> {
    return (await this.matches(surface)).at(0);
  }
}

export function createSurfaceAdapterRegistry(adapters: SurfaceAdapter[] = []): SurfaceAdapterRegistry {
  return new SurfaceAdapterRegistry(adapters);
}

export function createDefaultSurfaceAdapterRegistry(): SurfaceAdapterRegistry {
  return new SurfaceAdapterRegistry([
    chromeAdapter,
    tmuxAdapter,
    genericAXAdapter,
  ]);
}

export {
  chromeAdapter,
  genericAXAdapter,
  tmuxAdapter,
};
export type {
  SurfaceAdapter,
};
