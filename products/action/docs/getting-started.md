# Getting Started

This is the shortest path to a useful local dev loop for `action`.

## Prerequisites

- macOS on Apple Silicon
- Bun
- Swift/Xcode native build tooling
- willingness to grant Accessibility and Screen Recording permissions for native automation tests

## Install

```bash
bun install
```

## Build The Native App

```bash
bun run native:app:build
```

This produces a signed app bundle at:

`native/dist/Action.app`

## Check Native Health

Use the doctor wrapper before debugging anything capture-related:

```bash
bun run native:doctor
```

This is the safest high-signal command because it:

- builds the app if needed
- signs it
- verifies signature state
- reports current Accessibility and Screen Recording status

## Useful Smoke Commands

Check permissions:

```bash
bun run native:permissions:status
```

Request permissions:

```bash
bun run native:permissions:request
```

Run a screenshot smoke test:

```bash
bun run native:test:screenshot
```

Run a recording smoke test:

```bash
bun run native:test:record
```

## Important Runtime Note

Recording is asynchronous.

The initial CLI response means recording startup was accepted. Completion is
represented by the artifact plus a finished marker file written later by the
recording path.

If you are debugging recording, inspect:

- the `.mov` output
- the `.finished` marker
- the debug log passed through `--debug-log`

## Where To Read Next

- [docs/native-runtime.md](docs/native-runtime.md)
- [docs/recording.md](docs/recording.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
