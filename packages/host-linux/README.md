# lattices-host

Expose a Linux desktop to other lattices machines, so a Mac (or an agent on
one) can list, place, see and drive its windows over your tailnet. This is
[LAT-013](../../docs/proposals/LAT-013-linux-host.md).

It speaks the Mac daemon's protocol: the same `{id, method, params}` envelope,
the same LAT-012 method names, and the same response shapes. Point the CLI at
it and the usual commands work:

```sh
lats --host archie pair                         # once per client machine; approve on archie
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

### Which build is running?

Both **host.describe.build** and **daemon.status.build** contain:

    { "version": "0.1.0", "commit": "<full Git revision>", "dirty": false }

The existing top-level version stays intact. The version comes from this
package's package.json, not a second hard-coded constant. A source run snapshots
HEAD and the host package's tracked/untracked dirty state **once at startup**;
editing the checkout or moving HEAD later cannot make an old process report
new code. If Git metadata is absent/unreadable, commit and dirty are null,
rather than a fabricated revision.

For a relocatable build with its identity embedded:

    bun packages/host-linux/scripts/build.ts
    bun packages/host-linux/dist/lattices-host.js --describe

Or inside the package: bun run build. Pass an output file as the script's first
argument to put it elsewhere. Building requires a known source commit and
preserves dirty: true when building uncommitted work. The emitted bundle can
run without Git/a checkout; optionally compile **that bundle** with
bun build --compile to make a standalone executable with the same identity.

Clients should compare build.commit as well as build.version; null is unknown,
not current. These fields cannot retrospectively identify an older running host
that predates this change. Deploy/restart only after its clients are ready for
the pairing protocol; do not restart the everyday host just to obtain metadata.

## Omarchy tray

The tray is a small StatusNotifierItem and dbusmenu on the session D-Bus.
Omarchy's existing Quickshell tray renders it (inside the tray drawer unless
you pin it). Nothing is installed into `/usr/share/omarchy`, and no shell,
monitor or lan-mouse configuration is changed.

Install from this checkout, inside the graphical session:

```sh
bun install --cwd packages/host-linux --ignore-scripts --omit optional
bun packages/host-linux/scripts/install-tray.ts
```

The installer renders units into `packages/host-linux/.systemd/`, with literal
paths to this checkout and the current Bun executable, and links them through
the systemd user manager. Keep this checkout in place. It enables and starts
`lattices-tray.service` with `graphical-session.target`, and links
`lattices-host.service` for the menu's Start/Stop controls. It leaves the host
disabled at login until you choose to enable it. Existing units from another
location are refused rather than replaced. Re-run the installer after moving
the checkout or changing the Bun executable (remove the old unit links first
if the checkout moved).

For a foreground run:

```sh
bun packages/host-linux/src/main.ts tray
```

The menu contains Bring Cursor Home, a Share Pointer checkmark, host and
companion pairing status, Start/Stop Host, and Quit. The lattice icon is
monochrome; it becomes coral while pointer sharing is enabled. Quit exits
only the tray, leaving the host and lan-mouse alone; start it again with
`systemctl --user start lattices-tray`.

State refreshes when the menu opens, on lan-mouse frontend events, and on
systemd unit changes. Socket lifecycle notifications reconnect lan-mouse;
the tray re-registers when Quickshell's tray watcher restarts. There is no
background polling outside a pointer trial. Pairing status reads the host's existing trust records.
If a host is already running outside `lattices-host.service`, Stop Host is
disabled: quit that foreground host before starting the managed service.

Bring Cursor Home also works without either the tray or the network host:

```sh
bun packages/host-linux/src/main.ts mouse-home
lattices-host mouse-home                 # if the package's bin is on PATH
lats --host archie call mouse.home       # when this host version is running
```

It lists lan-mouse clients and deactivates each with an 800 ms timeout. Only
an unreachable daemon whose user service is active gets a restart fallback;
startup clients are deactivated after that restart as well. A stopped or
missing lan-mouse stays stopped. Release failures are included in the JSON
receipt and do not prevent the cursor warp. The target is the focused real
monitor, otherwise the first real monitor, excluding LATS/headless/virtual,
disabled and mirrored outputs. Coordinates account for scaling and rotation.
It tries `hyprctl dispatch movecursor X Y`, with the Lua cursor dispatcher
fallback required by Hyprland 0.55+.

### Pointer sharing trials

Turning Share Pointer on starts a five-minute trial. If lan-mouse is stopped,
its user service starts first; every configured client is then activated.
While the trial is armed, **Keep Sharing** appears immediately below Share
Pointer. Keep cancels the deadline and watchdog and leaves sharing enabled.
Bring Cursor Home and turning Share Pointer off cancel the trial and recover
the cursor. The coral icon follows sharing, including after Keep.

The same local commands work with the tray and network host stopped:

```sh
lattices-host mouse-share              # five minutes
lattices-host mouse-share --for 1m
lattices-host mouse-status             # sharing, clients, until
lattices-host mouse-keep
lattices-host mouse-home
```

In this checkout, substitute `bun packages/host-linux/src/main.ts` for
`lattices-host`. Durations are positive whole numbers of seconds, optionally
with `s`, `m`, or `h`: `90`, `30s`, `5m`, `1h`. `until` is an ISO 8601 UTC
deadline during a trial and `null` otherwise. A running host exposes the same
`mouse.share {"for":"5m"}`, `mouse.keep`, `mouse.status`, and `mouse.home`
methods. Share defaults to five minutes when `for` is omitted.

The trial belongs to the systemd user manager, independently of the process
that requested it. `lattices-pointer-trial.timer` launches the transient
`lattices-pointer-trial.service` to run `mouse-home --expired`. The timer and
recovery service are submitted together through `StartTransientUnit` before
activating clients; timer accuracy is 100 ms. Status reads the manager's
deadline and paired timestamps, so fresh CLI processes report the same time.
Units use the absolute Bun and checkout paths and the graphical session
environment, without a shell or config-file changes. Keep/Home stop the
timer, watchdog and any pending recovery service; recovery never stops itself.

`lattices-pointer-watch.service` runs `mouse-check` only during a trial. This
detached service checks `lan-mouse cli list` every 15 seconds with the same
800 ms timeout. A success resets its failure count; two consecutive failures
run Bring Cursor Home, including the existing service-restart fallback for an
unreachable running daemon. A managed service keeps the count without a
state file or a new CLI process on each tick, and survives the requesting
process exiting or crashing. It restarts on failure while the deadline is
armed. No watchdog runs after Keep, Home, Share off, or expiry. Each start,
keep, expiry and watchdog revert writes one line to stderr/the user journal.
These transient units survive a tray/host/CLI crash, not a user-manager
restart or reboot. Keep this checkout and Bun executable in place.

`dbus-next` is the one direct dependency: it serves the notifier/menu and
talks to the systemd user manager without a GUI toolkit. The install command
omits its optional native Unix-FD addon and disables install scripts; these
interfaces use the JavaScript Unix-socket transport and need no native addon.

Remove the autostart and linked units with:

```sh
systemctl --user disable --now lattices-tray
systemctl --user stop lattices-host
rm ~/.config/systemd/user/lattices-tray.service ~/.config/systemd/user/lattices-host.service
systemctl --user daemon-reload
```

## Who can connect

The host listens only on this machine's tailnet IPv4 address and on loopback.
Every tailnet connection is checked with `tailscale whois`: by default only
untagged devices owned by this machine's Tailscale user get in. Widen it with
`--allow-user <id|login>` or `--allow-tag tag:name`. Loopback is trusted, as
on the Mac.

Past whois, a remote client must be **paired** before any method runs; being
on the tailnet is not enough. This is the companion bridge's scheme (below)
applied to the daemon socket:

1. From the client: `lats --host archie pair` (or `--read-only`, or `--drive`). The CLI
   makes an X25519 key and id for this machine and calls `clients.pair`, the
   only method an unpaired client may call. It prints a code; wait.
2. On the host, a notification shows the client's name, its tailnet node and
   the same code: Approve or Deny. Or, on the host itself:
   `lats call clients.list` then `lats call clients.approve '{"clientID":"…"}'`.
   Approval is never accepted from a remote connection (`clients.approve`,
   `clients.deny`, and companion `bridge.pairing.approve` / `deny` are loopback-only), so a client cannot approve itself.
   Undecided requests are denied after two minutes.
3. Every later connection is signed: the WebSocket upgrade carries
   `x-lattices-device-id`, `-timestamp`, `-nonce` and `-signature`, an
   HMAC-SHA256 keyed by HKDF-SHA256 over the X25519 shared secret, over
   `GET`, the path, client id, timestamp, nonce and the empty body's hash.
   Timestamps must be within 2 minutes; a nonce is accepted once. A bad or
   revoked signature gets a 401/403 before the socket opens.

Each client has a scope, matching LAT-014's grants:

| Scope | Runs | Granted |
| --- | --- | --- |
| `read` | `access: "read"` methods (listed in `api.schema`) | always |
| `act` | focus, place, move, displays, sessions | by default |
| `drive` | `computer.*` input, `capture.live` (VNC takes input), `apps.open` (arbitrary command), and `mouse.share` / `mouse.keep` | only when asked for (`--drive`, or `scope: "drive"`) |

Each scope includes the ones above it. Clients that paired with `mutate`
before the split are `act`, and a request for `mutate` means `act`. Asking
for more scope later, such as `drive`, needs a new approval. `clients.list` shows each client's name, node, scope, created
and last-seen times; `clients.revoke '{"clientID":"…"}'` forgets one and closes
its open connections.

The host side lives in `~/.lattices/host/` (`daemon-key.json`,
`daemon-clients.json`, 0600). The client side lives in `~/.lattices/client.json`
(its key and id) and `~/.lattices/paired-hosts.json` (each host's public key
and the scope it granted), keyed by `address:port` and matched by the host's
tailnet name too, so `--host archie` and `--host 100.x.y.z` share a pairing.
This works the same from macOS or Linux.

`--no-pairing` turns this off for development: whois-admitted clients then get
full access, as before. Loopback-only methods stay loopback-only.

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
