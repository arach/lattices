---
title: Voice Commands
description: Natural language voice control for window management
order: 7
---

Voice commands let you control Lattices by speaking. Press **Hyper+3**
to open the voice command window, hold **Option** to speak, release to
stop. Lattices transcribes your speech via [Talkie](https://usetalkie.com),
matches it to an intent, and executes it.

## Quick start

1. Install [Talkie](https://usetalkie.com) (provides mic + transcription)
2. Install [Claude Code](https://claude.ai/code) CLI (provides AI advisor)
3. Press **Hyper+3** to open the voice command window
4. Hold **Option** and speak a command
5. Release **Option** — Lattices transcribes and executes

## Keyboard shortcuts

| Key | Action |
|-----|--------|
| **Hyper+3** | Open/close voice command window |
| **⌥ (hold)** | Push-to-talk — hold to record, release to stop |
| **Tab** | Arm/disarm the mic |
| **Escape** | Cancel recording or dismiss window |

## Built-in commands

### Search

Find windows by app name, title, content, or category.

```
"Find all talkie windows"
"Find terminals"           → expands to iTerm, Terminal, Warp, etc.
"Show me all browsers"     → expands to Safari, Chrome, Firefox, Arc, etc.
"Where is my editor?"      → expands to VS Code, Cursor, Xcode, etc.
```

Category synonyms are built in — saying "terminals", "browsers", "editors",
"chat", "music", "mail", or "notes" automatically expands to search for
the actual app names.

### Tile

Move windows to screen positions.

```
"Tile this left"
"Snap to the right half"
"Maximize the window"
"Put this in the top right corner"
```

### Focus

Bring a window or app to the front.

```
"Focus Safari"
"Switch to Slack"
"Go to the lattices window"
```

### Open / Launch

Open applications or project workspaces.

```
"Open Spotify"
"Launch the talkie project"
```

### Kill

Close windows or quit applications.

```
"Kill this window"
"Close Safari"
"Quit Spotify"
```

### Scan

Trigger an OCR scan of visible windows.

```
"Scan the screen"
"Read what's on screen"
```

### Other

```
"List all windows"
"Show my sessions"
"Switch to layer 2"
"Help"
```

## AI advisor

Every voice command fires a Claude Haiku advisor in parallel. The
advisor provides commentary and follow-up suggestions in the **AI
corner** (bottom-right of the voice command window).

When local matching handles the command well, the AI corner shows
"no AI needed" with an optional "ask AI" button. When the advisor
has something useful, it shows a one-line comment and an actionable
suggestion button.

### How it works

1. You speak a command
2. Local intent matching runs immediately (fast, free)
3. Haiku advisor runs in parallel (takes ~2-5 seconds)
4. If the advisor suggests something, a button appears in the AI corner
5. Click the suggestion to execute it
6. If you engage with a suggestion that the local matcher missed,
   it's recorded in `~/.lattices/advisor-learning.jsonl` for future
   improvement

### Session persistence

The advisor maintains a conversation session across voice commands.
It remembers what you've asked and what worked. When the context
reaches 75% of the model's limit, the session auto-resets.

Context usage and session cost are shown in the AI corner header.

## Configuration

Open **Settings > AI** to configure:

| Setting | Default | Description |
|---------|---------|-------------|
| Claude CLI path | Auto-detected | Path to the `claude` binary. Checks `~/.local/bin/claude`, `/usr/local/bin/claude`, `/opt/homebrew/bin/claude`, then `which claude`. |
| Advisor model | Haiku | `haiku` (fast, cheap) or `sonnet` (smarter, slower) |
| Budget per session | $0.50 | Maximum spend per Claude CLI invocation |

### Installing Claude Code

```bash
npm install -g @anthropic-ai/claude-code
```

Or see [claude.ai/code](https://claude.ai/code) for other install methods.

## Layout

The voice command window has four sections:

| Section | Position | Content |
|---------|----------|---------|
| **History** | Left column | Past commands with expandable details |
| **Voice Command** | Center column | Current transcript, matched intent, results |
| **Log** | Top-right | Rolling diagnostic log (last 12 entries) |
| **AI Corner** | Bottom-right | Advisor commentary, suggestions, session stats |

## Search architecture

Voice search uses the same backend as `lattices search`:

1. **Quick search** — window titles, app names, session tags (instant)
2. **Complete search** — adds terminal cwd/processes + OCR content
3. **Synonym expansion** — category terms like "terminals" expand to
   actual app names before searching
4. **Query cleanup** — strips natural language qualifiers ("and sort by...",
   "please", "for me") before searching

## Processing resilience

- **15-second timeout** — if processing doesn't complete, returns to idle
- **Cancellation on dismiss** — closing the window cancels in-flight work
- **Double-execution prevention** — streaming and stop callbacks can't
  both fire the intent

## Advisor learning

When the local matcher fails but the AI advisor suggests something that
you engage with, the interaction is recorded:

```
~/.lattices/advisor-learning.jsonl
```

Each line is a JSON object:

```json
{
  "timestamp": "2026-03-15T18:30:00.000Z",
  "transcript": "find all terminals",
  "localIntent": "search",
  "localSlots": {"query": "terminals"},
  "localResultCount": 0,
  "advisorIntent": "search",
  "advisorSlots": {"query": "iterm"},
  "advisorLabel": "Search iTerm"
}
```

This dataset captures where the local system falls short and what the
right answer was. Future work can mine it for automatic synonym
mappings and phrase pattern improvements.

## Requirements

- **[Talkie](https://usetalkie.com)** — provides microphone access and
  speech-to-text transcription
- **[Claude Code](https://claude.ai/code)** CLI — provides the AI advisor
  (optional, voice commands work without it but no AI suggestions)
- **Accessibility** permission — for window tiling and focus
- **Screen Recording** permission — for window discovery
