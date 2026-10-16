# Lattices on Linux

A local desktop window built with Quickshell and Qt Quick. It uses the existing
Linux host API over loopback. Desktop updates use events; the virtual preview
refreshes twice per second only while its view is open.

From the repository root, with Bun and Quickshell installed:

```sh
bun install --cwd packages/host-linux --frozen-lockfile --ignore-scripts --omit optional
bun packages/host-linux/src/main.ts  # if the host is not already running
bun run linux:app
```

The repository root and `packages/host-linux` are separate Bun packages.
The host declares `dbus-next` in its own manifest and lockfile; a root-only
install does not install it. For root typechecking and host tests, install both:

```sh
bun install --frozen-lockfile
bun install --cwd packages/host-linux --frozen-lockfile --ignore-scripts --omit optional
bun run check:types
bun test packages/host-linux/test
```

The host install skips dependency lifecycle scripts and the optional native
Unix-FD addon, matching the host's documented JavaScript D-Bus setup.

The shell follows the macOS app's layout and navigation. Home shows running
sessions, active windows, and saved layer layouts. Layers saves windows into named
contexts, chooses In place, Auto, Columns or Master stack, and switches them on
the current display and desktop. Show all restores windows put away by a layer
switch. New layers can start with visible windows or be filled with Add windows.
Rename, remove and delete edit the same `~/.lattices/workspace.json` used on Mac.
The first edit backs up an existing file to `workspace.json.bak`.

Overview draws the desktop to scale, filters by
workspace or title, and provides focus and placement controls for the selected
window. Activity records actions and errors from this app session. Settings,
in the sidebar footer, contains host health and local device pairing controls.

Click the L-shaped brand mark or wordmark to collapse or expand the navigation.
Ctrl+K opens window search; Ctrl+1 through Ctrl+4 open Home, Overview, Layers, and
Activity. New session opens a project-directory launcher. Desktop changes update
the app through host events; Refresh reconnects after the host stops.

The colors and chrome dimensions in `Theme.qml` follow
`apps/mac/Sources/UI/Theme.swift`. The mark follows the Mac's
`LatticesMarkAvatar`, and the shell follows `AppShellView.swift`.

Start Host uses the existing `lattices-host.service` user unit. If that unit is
not installed, run the host command above in your graphical session.
`LATTICES_LINUX_PORT` selects another local host port; the address stays loopback.

Layers requires an updated Linux host. Its `layers.*` endpoints also work from
the CLI. Linux supports focus and tile switching; launch commands, Mac app
hiding, layer undo and project companion rules are not implemented. Saved pins
hold the original live window and process. Reopened windows can be added again.
Window classes in hand-written app rules should use the Linux app identifier.
Parked windows and the active layer are recorded in `layers-stage-linux.json`
so Show all remains available after the host restarts. Windows on other desktops
are restored when those desktops are showing.

This is a source-run first increment. It does not install desktop files or
change Hyprland, Omarchy, or system configuration.

## Virtual space

Open **Overview → Virtual space → Start virtual space**. Browser and Terminal
launch apps on a separate 1280 × 800 headless desktop, with a live preview in the
same view. **Control preview** enables clicks, scrolling, the key buttons and
Send text. Watching and agent input leave the physical desktop's pointer and
focus alone. Stop closes the virtual apps; closing this window leaves the space
running until the host stops.

Virtual space needs `sway`, `grim`, `wtype` and `dbus-run-session` on PATH. The
Browser preset needs Chromium or Chrome and keeps a separate profile in
`~/.lattices/virtual-space/browser`; Terminal needs `foot`. On Arch, install the
optional tools with `sudo pacman -S sway grim wtype foot chromium`. Existing
physical windows stay on their original desktop; launch new Wayland apps here.

Agents use `computer.virtual.start/status/launch/capture/stop` and add
`space: "virtual"` to `computer.*` input or observe calls. Input still stages by
default and requires `treatment: "execute"` to act. See the
[host API notes](../../packages/host-linux/README.md#virtual-computer-use).

## Opt-in acceptance checks

These checks are not part of the ordinary unit-test command. Run them from the
repository root after installing both packages:

```sh
bun packages/host-linux/test/virtual-runtime.acceptance.ts
mkdir -p /tmp/lattices-qml-evidence
LATTICES_ACCEPTANCE_ARTIFACTS=/tmp/lattices-qml-evidence \
  bun packages/host-linux/test/qml-runtime.acceptance.ts
```

The virtual check owns a fresh private Sway runtime and disposable foot windows.
The QML check uses a fresh private Sway runtime, a copied shell with a navigation
timer, and a fixture backend. It captures Home, Overview, Layers, Activity,
Settings, and the Virtual space view. It does not test host RPC integration.

For live Hyprland acceptance, an explicit opt-in permits creating two new owned
headless outputs and three disposable foot windows in the current compositor:

```sh
LATTICES_ACCEPT_LIVE_OWNED_OUTPUTS=1 \
  bun packages/host-linux/test/hyprland-runtime.acceptance.ts
```

This check does not edit compositor configuration or workspace assignments. It
uses temporary registry/workspace files, verifies floating and tiled move-back,
layer parking and restart recovery, and an injected lost acknowledgement after
a real park. It removes only its own outputs/windows, restores baseline focus
and pointer, and compares preexisting window geometry and workspace assignments.
Do not run it while someone is interacting with the desktop: concurrent changes
can invalidate the baseline assertions.
