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
background polling. Pairing status reads the host's existing trust records.
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
