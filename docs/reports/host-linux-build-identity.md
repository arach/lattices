# Linux host build identity — October 9, 2026

Item 3, independent origin/main worktree.

Chosen fields: host.describe.build and daemon.status.build contain
{ version, commit, dirty }. Version is the host package version (currently
0.1.0), commit is the full Git hash, dirty is the tracked/untracked state under
packages/host-linux. Missing source/Git metadata yields commit:null, dirty:null.
The existing top-level version and api.schema definitions remain unchanged.

Source identity is immutable and captured once when the process loads, not on
each request. A running source host does not claim a newer revision merely
because somebody checks out another commit. The build script embeds this exact
shape in a relocatable Bun bundle; optionally compile that bundle for a
standalone binary. No per-request Git processes, timers or ambient watchers.

Checks:
- bun test --cwd packages/host-linux: 40 pass.
- bun run check:types: pass.
- Temporary Git tests cover clean, tracked/untracked dirty, moved HEAD and no
  Git metadata; frozen startup identity and both RPC responses verified.
- Bundle test runs outside a checkout with no git on PATH and returns the
  baked version/hash/dirty value.
- Actual host bundle built in /tmp and --describe verified the embedded
  identity. This did not start a server, bridge, VNC, capture or input.

Running :9399 remains unchanged. A pre-metadata process remains unknown until
a safe deployment/restart, after the Mac pairing implementation is ready.
The Mac UI can consume the additive fields; no Mac client files changed here.

Coordination: item 4 waits for operator merges of #181/#183/#184/#185, then a
pure domain move with a frozen pre-split schema and explicit method-list/full-
schema comparison tests. Claude's ax.* follows that split.
