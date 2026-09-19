---
name: speech
description: Control Lattices by speech. Use when simulating a voice command, listing voice intents, checking the voice runtime, or turning spoken window management into the same canonical mutations as the lattices skill.
compatibility: Requires macOS with the Lattices menu bar app running. Voice live session is ws://127.0.0.1:9398.
metadata:
  author: arach
  homepage: https://lattices.dev/docs/voice
---

# Speech

Lattices hosts an in-process voice runtime. Speech is another client of the
same execution layer as the CLI and daemon. Spoken commands must resolve
into the same canonical mutations as the `lattices` skill
(`window.place`, `layer.activate`, `space.optimize`).

When this skill is invoked, run the command. Summarize the matched intent
and the result. Do not invent intent names or slot values.

## Prerequisite

```bash
lattices voice status
```

If the daemon is down, start it with `lattices app`. Voice lives on
`ws://127.0.0.1:9398`. The agent API stays on `9399`.

Capability file:

`~/Library/Application Support/Lattices/Voice/hudson-voice-runtime.json`

Override the voice port only for tests with `LATTICES_VOICE_PORT`.

## Agent surface

Agents do not hold the microphone. They simulate speech through the CLI:

```bash
lattices voice intents
lattices voice simulate "tile this left"
lattices voice simulate "focus chrome" --dry-run
```

`--dry-run` parses and does not execute. Read `lattices voice intents`
before sending a novel phrase.

Equivalent daemon calls:

```bash
lattices call voice.status
lattices call voice.simulate '{"text":"tile this left","execute":true}'
lattices call intents.list
lattices call intents.execute '{"intent":"tile_window","slots":{"position":"left"},"rawText":"put this on the left","source":"agent"}'
```

## What people say

Humans open the voice window with **Hyper+D**, hold **Option** to talk,
and release to stop.

| Phrase | Result |
| --- | --- |
| "Tile this left" | `window.place` left |
| "Focus Safari" | Focus that app |
| "Find all vox windows" | Search |
| "Launch the vox project" | Session launch |
| "Switch to layer 2" | `layer.activate` |
| "Scan the screen" | OCR scan |
| "List all windows" | Window list |

Category words such as "terminals", "browsers", and "editors" expand to
real app names before search.

## Policy

- Local intent matching runs first. Provider-backed interpretation is
  optional (Settings > Voice).
- Do not skip the local matcher and send every phrase to an LLM.
- Voice search uses the same backend as `lattices search`.
- Keep `wid` in structured actions. In speech the user says an app name;
  the JSON action uses the window id from a snapshot.
- Advisor learning, when a suggestion is used after a local miss, is
  appended to `~/.lattices/advisor-learning.jsonl`.

## Live docs

1. `lattices voice intents`
2. https://lattices.dev/docs/voice
3. https://lattices.dev/docs/agents
4. `docs/voice-command-protocol.md` in this repository
