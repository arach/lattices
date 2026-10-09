# lattices-host

Expose a Linux desktop to other lattices machines, so a Mac (or an agent on
one) can list, place, see and drive its windows over your tailnet. This is
[LAT-013](../../docs/proposals/LAT-013-linux-host.md).

It speaks the Mac daemon's protocol: the same `{id, method, params}` envelope,
the same LAT-012 method names, and the same response shapes. Point the CLI at
it and the usual commands work:

```sh
lats --host archie call host.describe
lats --host archie call windows.list
lats --host archie call windows.place '{"app":"firefox","placement":"left"}'
LATTICES_DAEMON_HOST=archie lats call capture.still '{"maxWidth":1280}'
```

## Run it

Needs Bun, a Hyprland session, and Tailscale.

```sh
bun packages/host-linux/src/main.ts             # tailnet address + 127.0.0.1, port 9399
bun packages/host-linux/src/main.ts --describe  # print capabilities and exit
```

Or as a systemd user service: see `systemd/lattices-host.service`.

## Who can connect

The host listens only on this machine's tailnet IPv4 address and on loopback.
Every tailnet connection is checked with `tailscale whois`: by default only
untagged devices owned by this machine's Tailscale user get in. Widen it with
`--allow-user <id|login>` or `--allow-tag tag:name`. Loopback is trusted, as
on the Mac.

## What it can do

`host.describe` reports what this machine actually has. Each capability turns
on its methods; missing tools just hide them.

| Capability | Backend | Methods |
| --- | --- | --- |
| `windows.read`, `windows.place`, `spaces.read` | `hyprctl` (Lua dispatchers on 0.55+, legacy strings before) | `windows.list/get/search/resolve/focus/place/move`, `spaces.list`, `desktop.snapshot` |
| `capture.still` | `grim` | `capture.screenshotDisplay/Window/Region`, `capture.still` (inline JPEG) |
| `capture.live` | `wayvnc`, started on demand on the host's address | `capture.live` returns a `vnc://` URL for Screen Sharing |
| `input.keys` | `wtype` | `computer.typeText`, `computer.pressKey`, `computer.hotkey` |
| `input.pointer` | Wayland `zwlr_virtual_pointer_v1`, spoken directly; no root, no uinput | `computer.click/doubleClick/rightClick/drag/scroll/aim` |
| `sessions.tmux` | `tmux` | `tmux.list`, `sessions.launch/kill/detach`, `terminals.capture`, `computer.typeText` with `session` |
| `ocr` | `tesseract` on a grim capture (2x for `ocr.*`) | `computer.observe`, `ocr.read` (lines with screen boxes), `ocr.find` (fuzzy, tolerates misreads) |
| `capture.record` | grim frames at 1-15 fps, encoded by `ffmpeg` on stop | `capture.record` (`start`, `pause`, `resume`, `stop`, `status`) |
| `apps.open` | the compositor's exec dispatcher | `apps.open` waits for the new window |

`files.read` returns files under `~/.lattices/captures` in base64 chunks, so a
remote client can fetch the recordings and captures it asked for. Action's
`RemoteEngine` (LAT-013 phase 3) drives this host through these methods.

`computer.*` input methods stage by default and act only with
`treatment: "execute"`, as on the Mac. Mac modifier names are mapped:
`command` and `control` become ctrl, `option` becomes alt, `super`/`meta`/`win`
the logo key.

Events: Hyprland's event socket becomes `windows.changed` and
`spaces.changed`, pushed to every connected client.

## The iOS companion

lattices-host also speaks the companion bridge the iOS app uses with a Mac
(port 5287, the same routes and security), so a Linux machine joins the
phone's fleet without app changes.

1. In the app, add a host by address: `archie:5287` over Tailscale, or a LAN
   IP if you start the host with `--bridge-bind <lan-ip>` (that also
   advertises it over Bonjour through Avahi).
2. The host shows a notification, "Pair <device>?", with the device's code.
   Check the code matches the phone and approve. You can also approve from
   anywhere you can reach the host: `lats --host archie call bridge.status`,
   then `bridge.pairing.approve '{"deviceID":"..."}'`. Requests nobody
   decides are denied after two minutes.
3. Every later request is signed and encrypted with keys from that pairing.
   `bridge.devices.revoke` forgets a device.

The deck shows the windows (switcher and layout preview), workspaces,
system telemetry, a placement cockpit, the screen preview and the trackpad.
Actions: `layout.placeFrontmost`, `switch.focusItem`, `keys.send`,
`keys.type`, `clipboard.pasteFromDevice`, `window.dragBy`,
`spaces.focusIndex`, `spaces.focusRelative`, `displays.focus`. Mac-only
actions (voice, Talkie, layers) answer "Not available on Linux".

The bridge identity and trusted devices live in `~/.lattices/host/`
(`bridge-key.json`, `bridge-devices.json`, both 0600). `--no-bridge` turns
it off.

## Tests

```sh
bun test --cwd packages/host-linux
```

### Health is not an empty change stream

The additive fields in **host.describe** distinguish a healthy, quiet desktop
from a host that cannot observe it:

- **eventStream**: source (hyprland), state (not_started, connecting, connected,
  unavailable, disconnected or stopped), reason (null when connected), and
  lastEventAt (ISO timestamp; null until the first actual event).
- **events.desktop** is advertised only while socket2 is connected. The
  events.subscribe / events.unsubscribe methods still exist when it is not:
  clients can subscribe to **host.healthChanged** to see stream state changes.
- **capabilityHealth** maps capability names to available and reason. Missing
  grim/wtype/etc., a failing desktop query, or an absent Wayland protocol
  removes the capability and hides dependent methods in api.schema.

A null lastEventAt with state connected means no event has been observed yet,
not that observation is broken. Disconnection immediately removes events.desktop
and publishes host.healthChanged. Query host.describe again after that event.

Startup probes only read the desktop and Wayland registry; they do not capture,
send input, start VNC or modify a window. Probes run at startup or an explicit
refresh, never periodically. If the compositor becomes unreachable between
startup and a describe call, describe still returns health, not a failed RPC.

Socket2 state is logged once per distinct status/reason (no recurring retry
noise). Recovery watches the runtime/Hyprland socket directories and reconnects
when socket2 is created/replaced. There is no reconnect timer or polling loop.
A stopped subscription closes its socket and all filesystem watchers.
