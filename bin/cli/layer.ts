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
    if (sub === "add") {
      await layerAddCommand(client, rest);
      return;
    }
    if (sub === "remove") {
      const fromIdx = rest.indexOf("--from");
      const layer = fromIdx !== -1 ? rest[fromIdx + 1] : undefined;
      const wids = parseWids(rest.filter((_, i) => fromIdx === -1 || (i !== fromIdx && i !== fromIdx + 1)));
      if (!wids.length) { console.log("Usage: lattices layer remove wid:123 [wid:456 ...] [--from <layer>]"); return; }
      const result = await daemonCall("layers.unassign", { windowIds: wids, ...(layer ? { layer } : {}) }) as any;
      console.log(`Removed ${result.removed.length} window(s).`);
      if (result.held.length) console.log(`  Still held by an entry that matches other windows: ${result.held.map((w: number) => `wid:${w}`).join(" ")}. Edit workspace.json to narrow it.`);
      return;
    }
    if (sub === "rename") {
      if (!rest[0] || !rest[1]) { console.log("Usage: lattices layer rename <layer> <new name>"); return; }
      await daemonCall("layers.rename", { layer: rest[0], name: rest.slice(1).join(" ") });
      console.log(`Renamed layer "${rest[0]}" to "${rest.slice(1).join(" ")}".`);
      return;
    }
    if (sub === "reveal" || sub === "show-all") {
      const result = await daemonCall("layers.reveal") as any;
      const unhidden: string[] = result.unhidden ?? [];
      const rescued: number = result.rescued ?? 0;
      console.log(`Put back ${result.unparked} parked window${result.unparked === 1 ? "" : "s"}` +
        (rescued ? `, rescued ${rescued} stranded in the corner` : "") +
        (unhidden.length ? `, unhid ${unhidden.join(", ")}` : "") + ".");
      if (result.stillParked > 0) {
        console.log(`${result.stillParked} still parked on a desktop that isn't showing; run this again from there.`);
      }
      return;
    }
    if (sub === "delete" || sub === "rm") {
      if (!rest[0]) { console.log("Usage: lattices layer delete <layer>"); return; }
      const result = await daemonCall("layers.delete", { layer: rest[0] }) as any;
      console.log(`Deleted layer "${result.label ?? rest[0]}" from workspace.json.`);
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
      const parked = result.stage?.parked?.length ?? 0;
      const hidden: string[] = result.stage?.hidden ?? [];
      if (parked || hidden.length) {
        const parts = [];
        if (parked) parts.push(`${parked} window${parked === 1 ? "" : "s"} parked`);
        if (hidden.length) parts.push(`${hidden.join(", ")} hidden`);
        console.log(`\n  ${parts.join(" · ")} — \`lattices layer reveal\` brings them back`);
      }
      return;
    }
    // As ⌘⌥ switches; --tile lays the windows out again, --launch starts
    // what isn't running first.
    const mode = rest.includes("--launch") ? "launch" : rest.includes("--tile") ? "tile" : "focus";
    const idx = parseInt(sub, 10);
    const target = isNaN(idx) ? { name: sub } : { index: idx };
    await daemonCall("layer.activate", { ...target, mode });
    const name = isNaN(idx) ? `"${sub}"` : `${idx}`;
    console.log(mode === "focus" ? `Switched to layer ${name}` : `Switched to layer ${name} (${mode})`);
  });
}

// ── Layer create: save windows as a new ⌘⌥ layer in workspace.json ──
// Usage: lattices layer create <name> [wid:123 wid:456 ...]
//        lattices layer create <name> --json '[{"app":"Chrome","tile":"left"},...]'
// With no windows named, it saves the windows on screen.
export async function layerCreateCommand(client: DaemonClient, args: string[]): Promise<void> {
  const { daemonCall } = client;
  const name = args[0];
  if (!name) {
    console.log("Usage: lattices layer create <name> [wid:123 ...] [--json '<specs>']");
    return;
  }

  const jsonIdx = args.indexOf("--json");
  if (jsonIdx !== -1 && args[jsonIdx + 1]) {
    // JSON mode: window specs, each by wid or by app + title, with an optional tile
    const specs = JSON.parse(args[jsonIdx + 1]) as Array<{
      wid?: number; app?: string; title?: string; tile?: string;
    }>;
    const windows = await daemonCall("windows.list") as any[];
    const picked: Array<{ wid: number; tile?: string }> = [];
    for (const spec of specs) {
      const wid = spec.wid ?? windows.find((w: any) =>
        spec.app && w.app.toLowerCase().includes(spec.app.toLowerCase())
          && (!spec.title || w.title.toLowerCase().includes(spec.title.toLowerCase())))?.wid;
      if (wid) picked.push({ wid, tile: spec.tile });
      else console.log(`  No window for ${spec.app ?? "?"}${spec.title ? ` "${spec.title}"` : ""}; skipped.`);
    }
    if (!picked.length) { console.log("No windows matched; nothing saved."); return; }

    const result = await daemonCall("layers.create", { name, windows: picked }) as any;
    console.log(`Saved layer "${result.label}"${slotNote(result.index)} with ${result.count} window(s).`);

    const tiles = picked.filter(p => p.tile);
    for (const t of tiles) {
      try {
        await daemonCall("window.place", { wid: t.wid, placement: t.tile });
      } catch { /* the window may have closed */ }
    }
    if (tiles.length) console.log(`Tiled ${tiles.length} window(s).`);
    return;
  }

  const wids = parseWids(args.slice(1));
  const result = await daemonCall("layers.create", {
    name,
    ...(wids.length ? { windowIds: wids } : { visible: true }),
  }) as any;
  console.log(`Saved layer "${result.label}"${slotNote(result.index)} with ${result.count} window(s).`);
}

/** The ⌘⌥ pad's slots in layer order; 5 is the pad's centre. */
const PAD_SLOTS = [1, 2, 3, 4, 6, 7, 8, 9];

function slotNote(index: number): string {
  const slot = PAD_SLOTS[index];
  return slot ? ` on ⌘⌥${slot}` : "";
}

// ── Layer snap: save the windows on screen as a new layer ─────────────
export async function layerSnapCommand(client: DaemonClient, name?: string): Promise<void> {
  const { daemonCall } = client;
  const layerName = name || `snap-${new Date().toISOString().slice(11, 19).replace(/:/g, "")}`;
  const result = await daemonCall("layers.create", { name: layerName, visible: true }) as any;
  if (!result.count) {
    console.log(`Saved layer "${result.label}", but no windows were on screen.`);
    return;
  }
  console.log(`Snapped ${result.count} window(s) → layer "${result.label}"${slotNote(result.index)}.`);
}

// ── Layer add: put windows in a layer (default: the one you're on) ────
// Usage: lattices layer add wid:123 [wid:456 ...] [--to <layer>]
export async function layerAddCommand(client: DaemonClient, args: string[]): Promise<void> {
  const { daemonCall } = client;
  const toIdx = args.indexOf("--to");
  const layer = toIdx !== -1 ? args[toIdx + 1] : undefined;
  const wids = parseWids(args.filter((_, i) => toIdx === -1 || (i !== toIdx && i !== toIdx + 1)));
  if (!wids.length) {
    console.log("Usage: lattices layer add wid:123 [wid:456 ...] [--to <layer>]");
    return;
  }
  const result = await daemonCall("layers.assign", { windowIds: wids, ...(layer ? { layer } : {}) }) as any;
  const list = await daemonCall("layers.list") as any;
  const label = list.layers?.[result.index]?.label ?? `#${result.index}`;
  const skipped = wids.length - result.added;
  console.log(`Added ${result.added} window(s) to "${label}"${skipped ? ` (${skipped} already in it)` : ""}.`);
}

function parseWids(args: string[]): number[] {
  return args
    .map(a => parseInt(a.startsWith("wid:") ? a.slice(4) : a, 10))
    .filter(n => !isNaN(n));
}
