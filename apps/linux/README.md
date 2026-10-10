# Lattices on Linux

A local desktop window built with Quickshell and Qt Quick. It uses the existing
Linux host API over loopback. Desktop updates use events; the virtual preview
refreshes twice per second only while its view is open.

From the repository root, with Bun and Quickshell installed:

```sh
bun install --cwd packages/host-linux --frozen-lockfile
bun packages/host-linux/src/main.ts  # if the host is not already running
bun run linux:app
```

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
