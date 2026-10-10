# Lattices on Linux

A local desktop window built with Quickshell and Qt Quick. It uses the existing
Linux host API over loopback and adds no listener or background polling.

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
