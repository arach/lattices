# Runtime Change Prompt

Use this prompt when planning changes to the native runtime split.

## Prompt

Propose a change to the `action` native runtime without regressing WebKit or recording.

You must:

1. read [docs/native-runtime.md](docs/native-runtime.md)
2. read [docs/api.md](docs/api.md)
3. inspect [ActionHostMain.swift](native/engine/Sources/ActionHostMain.swift)
4. inspect [ActionAgentRuntime.swift](native/engine/CoreSources/ActionAgentRuntime.swift)

Your answer must separate:

- what belongs in `Action.app`
- what belongs in the local agent
- what risks AppKit lifecycle regressions
- what should be tested after the change
