# Voice Command Protocol — Lattices ↔ Vox

## Overview

Lattices delegates all audio capture and transcription to Vox via WebSocket JSON-RPC. Lattices never accesses the microphone directly — it borrows Vox's mic and transcription pipeline, receives English text back, and routes it through its own intent engine.

These dictations are **ephemeral** — Vox does not persist them as memos, sync them, or add them to Vox's history. Lattices is just using Vox as a transcription pipe.

## Vox Process Model

Vox consists of three independent processes:

| Process | Role | Relevance to Lattices |
|---|---|---|
| **Vox.app** | Main UI — menu bar, notch visualization, memo history | None |
| **Vox** | Background service — mic access, recording, hotkeys, orchestrates transcription, state notifications | **This is what Lattices connects to** |
| **VoxEngine** | Transcription engine — runs Whisper models, called by Vox internally | Indirect — Vox delegates to it |

Vox is the right target because:
- It owns the mic and recording lifecycle
- It's the long-running background process (always up when Vox is installed)
- It already orchestrates the record → transcribe → result pipeline
- It's easy to discover via its existing DistributedNotification

## Service Discovery

Lattices never hardcodes ports. Discovery uses two mechanisms:

### 1. Well-known file (at rest)

Vox writes its service configuration on startup:

```
~/.vox/services.json
```

```json
{
  "agent": {"port": 19823, "pid": 48209},
  "engine": {"port": 19821, "pid": 48210},
  "sync": {"port": 19820, "pid": 48208},
  "inference": {"port": 19822, "pid": 48212}
}
```

Lattices reads `agent.port` from this file. If the file doesn't exist, Vox isn't installed.

### 2. DistributedNotification (live discovery)

Vox posts when it comes online:

```
Notification: com.jdi.vox.agent.live.ready
UserInfo:     {"agentPort": 19823, "pid": 48209}
```

Lattices subscribes to this on startup. Handles:
- **Vox launches after Lattices** — Lattices picks up the port dynamically
- **Vox restarts** — Lattices reconnects with the new port
- **Port changes** — no stale config

### 3. Health check

After discovering a port, Lattices confirms Vox is alive:

```json
→ {"id": "hc", "method": "ping"}
← {"id": "hc", "result": {"pong": true}}
```

If ping fails, Lattices marks voice as unavailable and retries on the next `live.ready` or after ~30 seconds.

### When Vox is not running

Three possible states:

| State | How detected | Lattices behavior |
|---|---|---|
| **Not installed** | `/Applications/Vox.app` doesn't exist and no `~/.vox/` dir | Footer: `[Space] Voice (unavailable)` — no recovery action |
| **Installed but not running** | App bundle exists, but `services.json` missing/stale or ping fails | Footer: `[Space] Voice (start Vox)` — pressing Space runs `open /Applications/Vox.app`, which brings up Vox as a side effect |
| **Running** | Ping succeeds | Normal operation |

Launch-on-demand flow:
1. User presses Space while Vox is down but Vox is installed
2. Lattices runs `NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Vox.app"))`
3. Feedback strip shows "Starting Vox..."
4. Lattices waits for `live.ready` notification (timeout: 10s)
5. On `live.ready`, connects and proceeds with `startDictation`
6. On timeout, shows "Couldn't reach Vox — try opening it manually"

Passive behavior (no user action):
- No log spam — just a quiet unavailable state
- Lattices keeps listening for `live.ready` and re-checks `services.json` periodically (~30s)
- The moment Vox comes online, voice becomes available — no restart needed

## Protocol

### Wire Format

Uses Vox's JSON-RPC format over WebSocket:

```
Request:  {"id": "...", "method": "...", "params": {...}}
Response: {"id": "...", "result": {...}}  or  {"id": "...", "error": "..."}
Event:    {"event": "...", "data": {...}}   (server push, no id)
```

### Methods (Lattices → Vox)

**`startDictation`** — Start recording from the mic.

```json
{"id": "1", "method": "startDictation", "params": {
  "source": "lattices",
  "persist": false
}}
```

- `source` — identifies the caller (for Vox's logging/UI)
- `persist: false` — do not save as a memo, do not sync, do not show in Vox history

Response (immediate ack):
```json
{"id": "1", "result": {"ok": true}}
```

Error responses:
```json
{"id": "1", "error": "Microphone access denied"}
{"id": "1", "error": "No model loaded"}
{"id": "1", "error": "mic_busy", "owner": "vox"}
```

The `mic_busy` error means another consumer (Vox's own memo recording, or another client) already has an active dictation. The `owner` field identifies who holds the mic. Lattices shows: "Mic in use by Vox — finish your memo first".

The reverse case (user hits Vox hotkey while Lattices has the mic) is handled on Vox's side — it should reject its own recording with an equivalent busy state. Vox is the single owner of mic arbitration.

**`stopDictation`** — Stop recording and return the transcript.

```json
{"id": "2", "method": "stopDictation"}
```

Response (after transcription completes):
```json
{"id": "2", "result": {
  "transcript": "tile this left",
  "confidence": 0.94,
  "durationMs": 1820
}}
```

**`cancelDictation`** — Abort without transcribing.

```json
{"id": "3", "method": "cancelDictation"}
```

```json
{"id": "3", "result": {"ok": true}}
```

### Events (Vox → Lattices)

Pushed over the WebSocket connection during an active dictation.

| Event | When | Data |
|---|---|---|
| `dictation.started` | Mic is hot, recording has begun | `{"source": "lattices"}` |
| `dictation.transcribing` | Recording stopped, model is running | `{}` |
| `dictation.result` | Transcription complete | `{"transcript": "...", "confidence": 0.94, "durationMs": 1820}` |
| `dictation.error` | Something failed during recording or transcription | `{"message": "..."}` |

## Disconnect Contract

If the WebSocket connection drops mid-dictation (Lattices crashes, user quits, network hiccup), Vox **must** auto-cancel the in-flight dictation:

1. Stop recording immediately
2. Discard any captured audio — do not transcribe
3. Release the mic so Vox's own UI or a reconnecting client can use it
4. Log the orphaned dictation for diagnostics: `[dictation] orphaned session from lattices — connection dropped, auto-cancelled`

Vox treats a closed WebSocket as an implicit `cancelDictation`. No grace period, no buffering — if the consumer is gone, the recording is worthless.

On the Lattices side, if the connection drops while in `listening` or `transcribing` state:
- Feedback strip: "Connection lost" (red)
- Attempt reconnect via normal discovery (ping → `services.json` → wait for `live.ready`)
- Do not auto-retry the dictation — the user needs to press Space again

## End-to-End Lifecycle

```mermaid
sequenceDiagram
    participant U as User
    participant L as Lattices UI
    participant TA as Vox
    participant IE as Intent Engine

    U->>L: Press Space (in cheat sheet)
    L->>TA: startDictation (persist: false)

    alt Error
        TA-->>L: error (mic denied / no model)
        L->>U: Red text in feedback strip
    else OK
        TA-->>L: {ok: true}
        TA-->>L: dictation.started
        L->>U: Green dot (pulsing) + "Listening..."

        Note over U,TA: User speaks...

        U->>L: Press Space again
        L->>TA: stopDictation
        TA-->>L: dictation.transcribing
        L->>U: "Transcribing..."

        TA-->>L: {transcript: "tile this left", confidence: 0.94}
        L->>U: Show transcript
    end

    L->>IE: Classify via NLEmbedding
    IE-->>L: intent: tile_window, slots: {position: left}, confidence: 0.95
    L->>U: Show intent + slots

    L->>IE: Execute
    IE-->>L: result
    L->>U: "Done" or error

    Note over L: Log entry written
```

## UI States

| State | Feedback strip | Footer |
|---|---|---|
| **Idle** | Hidden | `[Space] Voice  [ESC] Dismiss` |
| **Not installed** | Hidden | `[Space] Voice (unavailable)  [ESC] Dismiss` |
| **Installed, not running** | Hidden | `[Space] Voice (start Vox)  [ESC] Dismiss` |
| **Starting** | "Starting Vox..." | `[ESC] Cancel` |
| **Error** | Red: "Mic access denied" or "Mic in use by Vox" | `[ESC] Dismiss` |
| **Disconnected** | Red: "Connection lost" | `[ESC] Dismiss` |
| **Listening** | Green dot + "Listening..." | `[Space] Stop  [ESC] Cancel` |
| **Transcribing** | "Transcribing..." | `[ESC] Cancel` |
| **Result** | `"tile this left"` → `tile window · position: left` → `Done` | `[Space] New  [ESC] Dismiss` |

## Logging

Every voice command produces a diagnostic log entry:

```
[voice] "tile this left" → tile_window(position: left) → ok (conf=0.95, 1820ms)
[voice] "organize my stuff" → distribute() → ok (conf=0.79, 2100ms)
[voice] "do something weird" → (no match, conf=0.41, 900ms)
[voice] error: Vox not running
[voice] error: mic_busy (owner: vox)
[voice] error: connection dropped mid-dictation
[voice] launched Vox, connected in 2.1s
```

## Implementation Scope

### Lattices side
- Use `@vox/client` SDK (`VoxClient` with `service: "agent"`, `clientId: "lattices"`, `capabilities: ["dictation"]`) — see `vox/sdk/SDK.md` for full reference
- Replace `AVAudioRecorder` in `VoxAudioProvider` with `createDictationSession().start({ persist: false })`
- Remove mic entitlement and `NSMicrophoneUsageDescription` (Lattices never touches the mic)
- Service discovery, auto-reconnect, and auth are handled by the SDK
- Map `DictationSession` events (`stateChange`, `partialTranscript`, `finalTranscript`, `error`) to cheat sheet UI states
- Handle `MicBusyError` — show `"Mic in use by ${error.owner}"`

### Vox side (separate repo)
- Expose a WebSocket bridge (or add methods to existing bridge)
- Add `startDictation`, `stopDictation`, `cancelDictation` handlers
- Emit `dictation.started`, `dictation.transcribing`, `dictation.result`, `dictation.error` events
- Honor `persist: false` — skip memo creation and sync
- Write `~/.vox/services.json` on startup (all service ports)
- Include `agentPort` in `live.ready` notification userInfo
- Return `mic_busy` error with `owner` field when another consumer holds the mic
- Auto-cancel dictation on WebSocket disconnect (closed socket = implicit cancel)
