# Intent Protocol

Lattices implements a structured intent system for voice control, agent automation, and cross-service integration. Any service that can send JSON over WebSocket can control Lattices through intents.

## Protocol

Two endpoints:

### `intents.list` — Discover available intents

**Params**: none

**Returns**: Array of intent definitions:

```json
[
  {
    "intent": "tile_window",
    "description": "Tile a window to a screen position",
    "examples": [
      "tile this left",
      "snap to the right half",
      "maximize the window"
    ],
    "slots": [
      {
        "name": "position",
        "type": "position",
        "required": true,
        "description": "Target tile position",
        "values": ["left", "right", "top", "bottom", "top-left", "top-right",
                   "bottom-left", "bottom-right", "maximize", "center"]
      },
      {
        "name": "app",
        "type": "string",
        "required": false,
        "description": "Target app name (defaults to frontmost)"
      }
    ]
  }
]
```

### `intents.execute` — Execute a structured intent

**Params**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `intent` | string | yes | Intent name from the catalog |
| `slots` | object | no | Named parameters for the intent |
| `rawText` | string | no | Original transcription text |
| `confidence` | double | no | Transcription confidence (0.0-1.0) |
| `source` | string | no | Source identifier (e.g. "talkie", "siri", "agent") |

**Example request**:

```json
{
  "id": "v1",
  "method": "intents.execute",
  "params": {
    "intent": "tile_window",
    "slots": { "position": "left", "app": "Chrome" },
    "rawText": "tile Chrome to the left",
    "confidence": 0.95,
    "source": "talkie"
  }
}
```

**Returns**: Intent-specific result (same as the underlying API method).

## Available Intents

### `tile_window`
Tile a window to a screen position. Defaults to the frontmost window if no target is specified.

**Slots**: `position` (required), `app`, `session`, `wid`

### `focus`
Focus a window, app, or session. Switches Spaces if needed. If the app isn't open, launches it.

**Slots**: `app`, `session`, `wid` (one required)

### `launch`
Launch a project session. Matches by project name against discovered projects.

**Slots**: `project` (required)

### `switch_layer`
Switch workspace layers. Tries session layers first, then config layers. Accepts name or index.

**Slots**: `layer` (required)

### `search`
Search for text across all windows using OCR index.

**Slots**: `query` (required)

### `list_windows`
List all visible windows.

### `list_sessions`
List active terminal sessions.

### `distribute`
Distribute all windows evenly across the screen.

### `create_layer`
Create a new session layer. Optionally captures all visible windows.

**Slots**: `name` (required), `capture_visible`

### `kill`
Kill a terminal session by name.

**Slots**: `session` (required)

### `scan`
Trigger an immediate screen text scan (OCR).

## Voice Integration Pattern

A voice service like Talkie integrates in three steps:

### 1. Fetch the catalog

```js
const catalog = await daemonCall('intents.list')
// Use catalog as context for intent extraction
```

### 2. Extract intent from speech

The catalog's `examples` and `slots` fields give an LLM everything it needs:

```js
const systemPrompt = `You extract structured intents from voice commands.
Available intents: ${JSON.stringify(catalog)}
Return JSON: { "intent": "...", "slots": { ... } }`

const result = await llm.complete({
  system: systemPrompt,
  user: transcription  // "put Chrome on the left side"
})
// → { "intent": "tile_window", "slots": { "position": "left", "app": "Chrome" } }
```

### 3. Execute

```js
await daemonCall('intents.execute', {
  intent: result.intent,
  slots: result.slots,
  rawText: transcription,
  confidence: 0.95,
  source: 'talkie'
})
```

### Why this works

- **No hardcoding**: Talkie doesn't know about Lattices-specific methods. It fetches the catalog dynamically.
- **Any service**: Any app that exposes `intents.list` + `intents.execute` becomes voice-controllable.
- **Few-shot examples**: The `examples` field acts as few-shot prompts for intent extraction.
- **Typed slots**: The `values` field on enum slots (like tile positions) constrains the LLM's output.
- **Graceful degradation**: `rawText` and `confidence` let the receiving service do its own fallback matching if needed.
