# Runtime Area Boundaries

The runtime stack is now split by intent:

- `interaction` (`src/interaction/*`) owns desktop control primitives: typing, key input, click, and drag/file-drop.
- `capture` (`src/macos.ts` capture paths) owns recording and screenshot workflows, including window/region/full-screen captures and geometry artifacts.
- `orchestration` (`src/guided.ts`, `src/session.ts`) owns scene execution, action timeline progress, and session state.

This keeps action semantics and media semantics independent while letting the same command engine execute both during guided runs.
