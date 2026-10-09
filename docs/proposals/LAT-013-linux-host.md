# LAT-013: Linux host

Status: Phases 1–2 built, 2026-10-08. Builds on [LAT-012](LAT-012-domain-api.md).

## Summary

A Linux machine joins lattices as a remote host. A small agent,
`lattices-host` (`packages/host-linux`), speaks the Mac daemon's protocol over
the tailnet, so Macs and agents can list, place, see and drive its windows
with the same methods they use locally. Lattices itself stays macOS-native.

## Why this is an exception

LAT-008 (principle 1), LAT-006 (non-goals) and Action's ARCHITECTURE.md rule
out cross-platform scope. This stays inside them:

- The Mac app, its daemon and its accessibility-first model are untouched.
- Linux gets a separate agent that implements a subset of the same protocol.
- Callers branch on advertised capabilities, never on platform, so no shared
  abstraction is pushed into the Mac code.

## Shape

```
Mac clients (lats CLI, MCP, Action)
  └─ daemon client ── 127.0.0.1:9399 ──▶ Mac daemon (unchanged)
                  └── archie:9399 ─────▶ lattices-host (Bun) ──▶ hyprctl, grim, wtype,
                      tailnet WS,                                virtual pointer, tmux,
                      tailscale whois                            tesseract, wayvnc
Screen Sharing ◀──── vnc://archie:5900 ── wayvnc (started by capture.live)
```

- **Protocol**: the daemon's envelope and error strings, LAT-012 names, old
  names as aliases. `api.schema` lists methods and aliases.
- **Discovery**: `host.describe` returns platform, displays, capabilities and
  methods. Capabilities: `windows.read`, `windows.place`, `spaces.read`,
  `capture.still`, `capture.live`, `input.keys`, `input.pointer`, `ocr`,
  `sessions.tmux`. A method whose capability is missing is hidden and refused.
- **Routing on the Mac side**: `LATTICES_DAEMON_HOST` / `LATTICES_DAEMON_PORT`
  or `lats --host <name>[:port]` point the CLI's daemon client at a host.
- **Shapes**: windows, displays and receipts use the Mac's fields (`wid`,
  `frame`, `spaceIds`, `visibleFrame`...). Hyprland workspaces stand in for
  Spaces. `wid` is Hyprland's hex `stableId`.

## Decisions

- **Agent location**: `packages/host-linux` in this repo, Bun/TypeScript,
  no dependencies.
- **Pointer input**: the host speaks the Wayland `zwlr_virtual_pointer_v1`
  protocol directly (`src/wayland.ts`). No root, no uinput, no extra package;
  `wlrctl`/`dotool` are not packaged on Arch and `ydotool` needs uinput access.
- **Hyprland dialects**: 0.55 moved `hyprctl dispatch` to Lua
  (`hl.dsp.window.move({ x = 0, y = 24, window = "address:0x…" })`). The host
  detects the dialect with `hl.dsp.no_op()` and spells every operation for it,
  keeping the legacy strings for older versions.
- **Trust**: listen only on the tailnet address and loopback. Each tailnet
  connection is identified with `tailscale whois`; by default only untagged
  devices of this machine's Tailscale user are admitted (`--allow-user`,
  `--allow-tag` widen it). The Mac daemon stays loopback-only. Companion-style
  pairing is the path for devices outside the tailnet.
- **Safety**: `computer.*` input stages by default and acts only with
  `treatment: "execute"`, as on the Mac.
- **Key mapping**: `command` and `control` → ctrl, `option` → alt,
  `super`/`meta`/`win` → logo.
- **Viewing**: `capture.still` returns an inline JPEG (pull, like the iOS
  preview); `capture.live` starts wayvnc on the host's address and returns a
  `vnc://` URL.

## Phases

1. **Read-only** (done): `host.describe`, windows, spaces, captures, live view,
   CLI `--host`.
2. **Control** (done): keyboard, pointer, placement, workspace moves, tmux
   sessions, `computer.observe` (OCR), Hyprland events as `windows.changed` /
   `spaces.changed`.
3. **Action integration**: a `RemoteEngine` implementing Action's
   `CaptureEngine`. Needs Action's MCP off its hardcoded `MacOSCommandEngine`,
   and `SurfaceObservation.ax` and the TCC fields of `EngineDiagnostics`
   optional.
4. **Fleet**: a `hosts` MCP toolset that takes a host per call, the iOS fleet
   view reading `capture.still`, and a subscribe RPC for filtered events.

## Open questions

- Whether a Mac should also expose itself as a remote host (its daemon would
  need the same tailnet listener and identity check), or stay client-only.
- Whether `computer.observe` should grow an AT-SPI element tree once Wayland
  accessibility is usable.
