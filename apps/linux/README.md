# Lattices on Linux

A local desktop window built with Quickshell and Qt Quick. It uses the existing
Linux host API over loopback and adds no listener or background polling.

From the repository root, with Bun and Quickshell installed:

```sh
bun install --cwd packages/host-linux --frozen-lockfile
bun packages/host-linux/src/main.ts  # if the host is not already running
bun run linux:app
```

The first version shows displays and workspaces, searchable windows, focus and
placement actions, and tmux sessions with a project-directory launcher. The
Host view shows build/event health, paired clients, and requests that can be
approved, denied, or revoked locally. Desktop changes update the window through
the host's events; Refresh also reconnects after the host stops.

Start Host uses the existing `lattices-host.service` user unit. If that unit is
not installed, run the host command above in your graphical session.
`LATTICES_LINUX_PORT` selects another local host port; the address stays loopback.

This is a source-run first increment. It does not install desktop files or
change Hyprland, Omarchy, or system configuration.
