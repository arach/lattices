import { withDaemon, type DaemonClient } from "./daemon.ts";

export async function layerCommand(sub?: string, ...rest: string[]): Promise<void> {
  await withDaemon(async (client) => {
    const { daemonCall } = client;

    if (sub === "create") {
      await layerCreateCommand(client, rest);
      return;
    }
    if (sub === "snap") {
      await layerSnapCommand(client, rest[0]);
      return;
    }
    if (sub === "session" || sub === "sessions") {
      await layerSessionCommand(client, rest[0]);
      return;
    }
    if (sub === "clear") {
      await daemonCall("session.layers.clear");
      console.log("Cleared all session layers.");
      return;
    }
    if (sub === "delete" || sub === "rm") {
      if (!rest[0]) { console.log("Usage: lattices layer delete <name>"); return; }
      await daemonCall("session.layers.delete", { name: rest[0] });
      console.log(`Deleted session layer "${rest[0]}".`);
      return;
    }

    if (sub === undefined || sub === null || sub === "") {
      const result = await daemonCall("layers.list") as any;
      if (!result.layers.length) {
        console.log("No layers configured.");
        return;
      }
      console.log("Layers:\n");
      for (const layer of result.layers) {
        const active = layer.index === result.active ? " \x1b[32m● active\x1b[0m" : "";
        console.log(`  [${layer.index}] ${layer.label}  (${layer.projectCount} projects)${active}`);
      }
      return;
    }
    const idx = parseInt(sub, 10);
    if (!isNaN(idx)) {
      await daemonCall("layer.activate", { index: idx, mode: "launch" });
      console.log(`Activated layer ${idx}`);
    } else {
      await daemonCall("layer.activate", { name: sub, mode: "launch" });
      console.log(`Activated layer "${sub}"`);
    }
  });
}

// ── Layer create: build a session layer from window specs ────────────
// Usage: lattices layer create <name> [wid:123 wid:456 ...]
//        lattices layer create <name> --json '[{"app":"Chrome","tile":"left"},...]'
export async function layerCreateCommand(client: DaemonClient, args: string[]): Promise<void> {
  const { daemonCall } = client;
  const name = args[0];
  if (!name) {
    console.log("Usage: lattices layer create <name> [wid:123 ...] [--json '<specs>']");
    return;
  }

  const jsonIdx = args.indexOf("--json");
  if (jsonIdx !== -1 && args[jsonIdx + 1]) {
    // JSON mode: parse window specs with tile positions
    const specs = JSON.parse(args[jsonIdx + 1]) as Array<{
      wid?: number; app?: string; title?: string; tile?: string;
    }>;

    // Collect wids, resolve app-based specs
    const windowIds: number[] = [];
    const windows: Array<{ app: string; contentHint?: string }> = [];
    const tiles: Array<{ wid?: number; app?: string; title?: string; tile: string }> = [];

    for (const spec of specs) {
      if (spec.wid) {
        windowIds.push(spec.wid);
        if (spec.tile) tiles.push({ wid: spec.wid, tile: spec.tile });
      } else if (spec.app) {
        windows.push({ app: spec.app, contentHint: spec.title });
        if (spec.tile) tiles.push({ app: spec.app, title: spec.title, tile: spec.tile });
      }
    }

    await daemonCall("session.layers.create", {
      name,
      ...(windowIds.length ? { windowIds } : {}),
      ...(windows.length ? { windows } : {}),
    }) as any;

    console.log(`Created session layer "${name}" with ${specs.length} window(s).`);

    // Apply tile positions
    for (const t of tiles) {
      try {
        await daemonCall("window.place", {
          ...(t.wid ? { wid: t.wid } : { app: t.app, title: t.title }),
          placement: t.tile,
        });
      } catch { /* window may not be resolved yet */ }
    }

    if (tiles.length) console.log(`Tiled ${tiles.length} window(s).`);
    return;
  }

  // Simple wid mode: lattices layer create <name> wid:123 wid:456
  const wids = args.slice(1)
    .filter(a => a.startsWith("wid:"))
    .map(a => parseInt(a.slice(4), 10))
    .filter(n => !isNaN(n));

  await daemonCall("session.layers.create", {
    name,
    ...(wids.length ? { windowIds: wids } : {}),
  }) as any;

  console.log(`Created session layer "${name}"${wids.length ? ` with ${wids.length} window(s)` : ""}.`);
}

// ── Layer snap: snapshot current visible windows into a session layer ─
export async function layerSnapCommand(client: DaemonClient, name?: string): Promise<void> {
  const { daemonCall } = client;
  const layerName = name || `snap-${new Date().toISOString().slice(11, 19).replace(/:/g, "")}`;

  // Get all current windows
  const windows = await daemonCall("windows.list") as any[];
  const visibleWids = windows
    .filter((w: any) => !w.isMinimized && w.app !== "lattices")
    .map((w: any) => w.wid);

  if (!visibleWids.length) {
    console.log("No visible windows to snapshot.");
    return;
  }

  await daemonCall("session.layers.create", {
    name: layerName,
    windowIds: visibleWids,
  });

  console.log(`Snapped ${visibleWids.length} window(s) → session layer "${layerName}".`);
}

// ── Layer session: list or switch session layers ─────────────────────
export async function layerSessionCommand(client: DaemonClient, nameOrIndex?: string): Promise<void> {
  const { daemonCall } = client;
  const result = await daemonCall("session.layers.list") as any;

  if (!nameOrIndex) {
    // List session layers
    if (!result.layers.length) {
      console.log("No session layers. Create one with: lattices layer create <name>");
      return;
    }
    console.log("Session layers:\n");
    for (let i = 0; i < result.layers.length; i++) {
      const l = result.layers[i];
      const active = i === result.activeIndex ? " \x1b[32m● active\x1b[0m" : "";
      const winCount = l.windows?.length || 0;
      console.log(`  [${i}] ${l.name}  (${winCount} windows)${active}`);
    }
    return;
  }

  // Switch by index or name
  const idx = parseInt(nameOrIndex, 10);
  if (!isNaN(idx)) {
    await daemonCall("session.layers.switch", { index: idx });
    console.log(`Switched to session layer ${idx}.`);
  } else {
    await daemonCall("session.layers.switch", { name: nameOrIndex });
    console.log(`Switched to session layer "${nameOrIndex}".`);
  }
}
