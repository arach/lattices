# Linux host health — October 9, 2026

Item 2 is independent of the command-socket PR #188. It keeps the current
method names and guards capabilities with actual desktop/Wayland probes,
rather than trusting the compositor signature or installed command alone.

## Chosen shapes

- host.describe.eventStream = source, state, reason, lastEventAt.
  States: not_started / connecting / connected / unavailable / disconnected /
  stopped. Source: hyprland. ISO lastEventAt is null until a valid socket2 event.
- host.describe.capabilityHealth = capability → { available, reason }.
- events.desktop capability means socket2 is currently connected.
- host.healthChanged event is additive; KNOWN_EVENTS remains the single list.
  events.subscribe/unsubscribe remain callable even when events.desktop is off.

No periodic health/reconnect timers. Filesystem changes recover socket2;
connection errors/loss are immediately visible and logged once per distinct
state/reason. Existing event-triggered window/workspace debounce is unchanged.

Tool checks read current PATH (not a cached shell result). Registry probes
require the protocols used by grim, wtype and the virtual pointer. Desktop
probes execute a real snapshot query. Capture/OCR/recording and pointer
capabilities also require their desktop dependencies.

## Checks

- bun test --cwd packages/host-linux: 40 pass.
- bun run check:types: pass.
- Fake event sockets: missing env/socket, UTF-8 line buffering, loss, recovery
  after socket recreation, deduplicated logging, clean shutdown.
- Missing tool/protocol/compositor tests cover truthful capabilities and hidden
  methods without sending input or changing any real window.
- Real scratch instance: 127.0.0.1:19499, --no-bridge. Describe reported connected,
  null lastEventAt (quiet stream), all 12 capabilities usable; 39 methods.
  windows.list and subscription to host.healthChanged succeeded.
- Removing HYPRLAND_INSTANCE_SIGNATURE, XDG_RUNTIME_DIR and WAYLAND_DISPLAY
  in a separate --describe process reported eventStream unavailable with the
  exact missing-variable reason; only sessions.tmux remained advertised.
- Scratch instance shut down. The everyday :9399 PID 826336 was not restarted.
  No system/Omarchy configuration or LATS-1/lats-probe/window mutation occurred.

## Coordination

Endpoint splitting waits until Claude's #181/#183/#184/#185 land. This PR
does not implement pairing, displays.create/remove, moveBack, computer.acted
or ax.*. #183's displays.virtual must be carried into host-capabilities.ts
when rebasing; #185's emit wiring and computer.acted KNOWN_EVENTS entry must
be retained. The stop-function onEvents API remains intact (ready is additive).
