# @lattices/agent-runtime

Lattices-facing wrapper for background agent session adapters.

This package is the public runtime contract used by lattices' agent dispatcher
(`bin/project-twin.ts` and friends). It currently delegates to
`@openscout/agent-sessions`, but lattices code should prefer this package name
so the implementation can move without changing call sites.

It mirrors `@talkie/agent-runtime`: both repos wrap the same
`@openscout/agent-sessions` adapters (pi, codex, claude-code, opencode, echo) so
they share one mental model and one place to pin the version.

```sh
npm install --prefix "$HOME/.lattices/agent-runtime" @lattices/agent-runtime
"$HOME/.lattices/agent-runtime/bin/lattices-agent-runtime" doctor
```

`doctor` asserts the expected adapter factories and `SessionRegistry` are
present — a post-install health check that catches adapter/version drift.
