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
sessions and active windows. Overview draws the desktop to scale, filters by
workspace or title, and provides focus and placement controls for the selected
window. Activity records actions and errors from this app session. Settings,
in the sidebar footer, contains host health and local device pairing controls.

Click the L-shaped brand mark or wordmark to collapse or expand the navigation.
Ctrl+K opens window search; Ctrl+1, Ctrl+2, and Ctrl+3 open Home, Overview, and
Activity. New session opens a project-directory launcher. Desktop changes update
the app through host events; Refresh reconnects after the host stops.

The colors and chrome dimensions in `Theme.qml` follow
`apps/mac/Sources/UI/Theme.swift`. The mark follows the Mac's
`LatticesMarkAvatar`, and the shell follows `AppShellView.swift`.

Start Host uses the existing `lattices-host.service` user unit. If that unit is
not installed, run the host command above in your graphical session.
`LATTICES_LINUX_PORT` selects another local host port; the address stays loopback.

This is a source-run first increment. It does not install desktop files or
change Hyprland, Omarchy, or system configuration.
