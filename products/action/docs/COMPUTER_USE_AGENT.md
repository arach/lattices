# Computer Use Agent — Action Spec

## Context

`action` today is a guided demo workstation: it stages scenes, records sessions, and produces artifacts for post-production. The agent runtime (`ActionAgentRuntime`) handles WebSocket transport and dispatches a small set of deterministic actions (click, type, press-key, drag, recording).

A computer use agent requires a different loop: **observe → think → act → repeat** with autonomous goal pursuit, ongoing perception, and a much wider action surface.

This document describes the gap and the changes needed to close it.

---

## 1. Current State

### What Exists

| Layer | What | Limitation |
|-------|------|------------|
| **Actions** | `click`, `type`, `press-key`, `drag`, `start/stop-recording`, `show-cue`, `wait-for-condition` | No scroll, no context menu, no hotkey combos beyond simple modifiers |
| **Target Resolution** | `semantic`, `accessibility`, `dom`, `textual`, `anchor`, `coordinate` | Resolution is one-shot; no ongoing observation |
| **Perception** | Screenshots on demand, AX snapshots, recording | No continuous frame stream; perception is pull-only |
| **Agent Loop** | None | Session is scripted/guided; no autonomous iteration |
| **Memory** | Trace + artifact persistence only | No working memory, no context accumulation across steps |
| **Tool Surface** | `CaptureEngine` interface | Not exposed as agent tools; no tool-call protocol |

### What Is Missing for Computer Use

- Continuous screen observation (video stream or periodic frames)
- Rich element interaction (scroll, hover, context menu, double-click, text selection)
- Autonomous goal decomposition and retry
- Working memory and context carry-across
- Mouse cursor control with smooth motion
- Key sequences and system hotkeys
- Clipboard access (read/write)
- File system operations
- Process and window management
- Natural language instruction parsing
- Self-correction on failure

---

## 2. Perception Layer

### 2.1 Continuous Frame Stream

Today: screenshots are captured on demand via `captureScreenshot`.

Computer use requires: a periodic frame grab (e.g., every 1–2 seconds) that feeds the agent's vision input.

**Changes:**

- Add a `FrameStream` service in the native layer
  - Captures `CGImage` frames at a configurable interval (default: 1fps)
  - Pushes frames to the agent runtime via WebSocket or a shared buffer
  - Supports pause/resume so the agent only pays for frames when active
- Add `startVisionStream()` / `stopVisionStream()` to `CaptureEngine`
- Frames are small JPEG thumbnails at ~720p for token efficiency

### 2.2 Accessibility Tree Persistence

Today: AX snapshots are taken as discrete artifacts.

Computer use requires: a live, queryable AX tree that the agent can re-query on every step without re-capturing the whole screen.

**Changes:**

- Add an `AccessibilityMonitor` that polls AX tree every ~500ms when active
- Cache the tree in the agent runtime
- Provide `queryAccessibleElement(query: TargetQuery)` method that hits the cache first
- Fall back to a fresh AX snapshot only when the cache is stale (>2s) or query misses

### 2.3 Cursor and Surface Tracking

**Changes:**

- Add `cursorPosition()` to report current mouse coordinates in real time
- Add `activeWindowInfo()` to report frontmost app, window title, and bounds
- These feed into the agent's observation payload on each step

---

## 3. Action Surface Expansion

### 3.1 Interaction Actions

Add these to `ActionKind` in the protocol:

| New Action | Description |
|------------|-------------|
| `scroll` | Scroll a target or the active surface by a delta |
| `double-click` | Double-click at a point or on a target |
| `right-click` | Context menu at a point or on a target |
| `hover` | Move mouse to a point without clicking |
| `text-select` | Select text in a text field or document |
| `text-copy` | Copy selected text to clipboard |
| `text-paste` | Paste clipboard contents |
| `screenshot` | One-off screenshot |

### 3.2 System Actions

| New Action | Description |
|------------|-------------|
| `open-url` | Open a URL in the default browser |
| `open-file` | Open a file with its default application |
| `launch-app` | Launch an application by bundle ID or name |
| `quit-app` | Quit an application |
| `focus-app` | Bring an app's window to front |
| `get-clipboard` | Read current clipboard contents |
| `set-clipboard` | Write text to clipboard |
| `run-shell-command` | Execute a shell command and return output |

### 3.3 Interaction Execution

The existing `executeInteractionAction` in `packages/runtime/src/interaction/index.ts` handles the current action set via `runHost` calls to CLI commands. This pattern should be extended:

```
Action → InteractionExecutor → HostCLI
                         ↘ NativeAutomationBridge (for AX-dependent actions)
```

For `scroll`, `double-click`, `right-click`, `hover`: new host CLI commands.

For `get-clipboard` / `set-clipboard`: native macOS `NSPasteboard` calls.

For `focus-app`, `launch-app`, `quit-app`: `NSRunningApplication` and `NSWorkspace`.

### 3.4 Mouse Motion Path

Today `click-point` snaps the cursor. For computer use with UI agents:

- Add `move-to` command with optional duration for smooth motion
- Use `CGEvent` posting with `kCGHIDEventTap` for smooth cursor movement
- Configurable speed (fast for demos, slow for screen recording legibility)

---

## 4. Agent Loop

### 4.1 Cycle Architecture

```
AgentRuntime
  ↕ vision frames + AX tree
  Agent Loop (external or embedded)
  ↕ tool calls
  CaptureEngine
  ↕ AX + CGEvent
  Action.app / Native Layer
```

The agent loop itself can live:
- **Embedded** in `ActionAgentRuntime.swift` — simple, synchronous loop
- **External** via WebSocket RPC — the agent runs in a separate process (safer isolation)

Option B (external) is preferred: it keeps the native app lifecycle clean and allows the agent to be upgraded without rebuilding Action.app.

### 4.2 Tool Call Protocol

Add a `tools.list` and `tools.call` RPC surface to the WebSocket interface:

```typescript
// Request: list tools
{ "method": "tools.list" }

// Response:
{ "tools": [
  { "name": "screenshot", "description": "...", "parameters": {...} },
  { "name": "click", "description": "...", "parameters": {...} },
  ...
]}

// Request: call tool
{ "method": "tools.call", "params": { "name": "click", "args": { "target": {...} } } }

// Response:
{ "success": true, "result": {...} }
// or
{ "success": false, "error": "..." }
```

### 4.3 Observation Payload

On each loop iteration, the agent receives:

```typescript
interface AgentObservation {
  frame: string;           // base64 JPEG thumbnail
  axTree: AXNode[];         // cached accessibility tree
  cursorPosition: Point;
  activeWindow: SurfaceRef;
  recentActions: ActionTrace[];  // last 5 actions + outcomes
  sessionHistory: ActionTrace[]; // full history
}
```

### 4.4 Self-Correction

When an action fails (AX element not found, app not responding):

1. Increment failure counter on the step
2. Retry with relaxed target (e.g., fall back to coordinate click)
3. After 2 retries, mark step as `failed` and report to agent
4. Agent decides whether to skip, substitute, or abort

---

## 5. Memory and Context

### 5.1 Working Memory

Add a `MemoryStore` to the protocol:

```typescript
interface MemoryEntry {
  key: string;
  value: string;
  ttlMs?: number;
}

interface MemoryStore {
  set(entry: MemoryEntry): void;
  get(key: string): string | undefined;
  delete(key: string): void;
  clear(): void;
}
```

Use cases:
- Remember the last button clicked so the agent can say "I clicked the submit button"
- Store intermediate task results (e.g., "found the settings menu")
- Carry context across steps (e.g., "we are in the Safari preferences pane")

### 5.2 Session Context Carry-Over

Currently each session is stateless. For computer use:

- Add a `session.context: Record<string, unknown>` field
- The agent can write/read this across the session lifetime
- Context is persisted to `manifest.json` so interrupted sessions can resume

---

## 6. Native Layer Changes

### 6.1 ActionHostMain.swift

- Add a `handleToolCall(method: String, args: [String: Any]) -> Any?` entry point
- Route `tools.call` to the appropriate native handler or forward to `ActionAgentRuntime`

### 6.2 AccessibilityMonitor

New Swift class that:
- Creates an `AXUIElement` for the systemwide accessibility observer
- Polls at a configurable interval
- Returns a serialized AX tree as JSON

### 6.3 FrameStreamService

New Swift class that:
- Uses `CGDisplayStream` or periodic `CGWindowListCreateImage` to capture frames
- Compresses to JPEG and pushes via a delegate or notification

### 6.4 AutomationBridge

Refactor `ActionAgentCommandBridge.swift` to expose a cleaner `AutomationBridge` interface:

```swift
protocol AutomationBridge {
    func click(at point: CGPoint) async throws
    func type(text: String, delayMs: Int?) async throws
    func scroll(delta: CGPoint, in bounds: CGRect?) async throws
    func getClipboard() async throws -> String?
    func setClipboard(text: String) async throws
    func getCursorPosition() -> CGPoint
    func getFrontmostApp() async throws -> AppInfo
    func launchApp(bundleId: String) async throws
    func quitApp(bundleId: String) async throws
}
```

This protocol is implemented in `Action.app` (AppKit context) and called from the agent via XPC or direct Swift invocation.

---

## 7. Protocol Changes

### 7.1 New `ActionKind` values

```typescript
export type ActionKind =
  | "click"
  | "type"
  | "press-key"
  | "focus-window"
  | "open-app"
  | "drag"
  | "start-recording"
  | "stop-recording"
  | "show-cue"
  | "wait-for-condition"
  | "scroll"           // NEW
  | "double-click"      // NEW
  | "right-click"       // NEW
  | "hover"            // NEW
  | "text-select"      // NEW
  | "text-copy"        // NEW
  | "text-paste"       // NEW
  | "open-url"         // NEW
  | "open-file"        // NEW
  | "quit-app"         // NEW
  | "get-clipboard"    // NEW
  | "set-clipboard"    // NEW
  | "run-shell-command" // NEW
  | "screenshot";      // NEW (rename from captureScreenshot alias)
```

### 7.2 New `RuntimeAction.input` fields

```typescript
// scroll
{ "deltaX": number, "deltaY": number, "targetId"?: string }

// double-click / right-click
{ "point"?: Point, "targetId"?: string }

// hover
{ "point": Point }

// text-select
{ "start": number, "end": number, "targetId": string }

// open-url
{ "url": string }

// open-file
{ "path": string }

// quit-app
{ "bundleId": string }

// run-shell-command
{ "command": string, "timeoutMs"?: number }

// get-clipboard / set-clipboard
{ "text": string }  // for set-clipboard
// get-clipboard has no input
```

### 7.3 New `SurfaceRef` kinds

```typescript
// Extend SurfaceRef
{ id: string; kind: "desktop" | "window" | "browser-tab" | "region" | "menu" | "dialog"; label: string; bounds?: Bounds }
```

---

## 8. Agent-External vs Agent-Embedded

Two integration strategies:

### Option A: Embedded Agent Loop

The agent logic runs inside `ActionAgentRuntime.swift`, called via WebSocket messages from an external orchestrator.

- **Pros**: Simple IPC, shared memory
- **Cons**: Agent code is coupled to the app; hard to update agent independently

### Option B: External Agent (Recommended)

A separate agent process (Node.js, Python, or custom) connects to `ActionAgentRuntime` via WebSocket as a client. The agent sends `tools.call` messages and receives observation payloads.

- **Pros**: Agent can be updated independently; agent can run on a different machine; cleaner isolation
- **Cons**: Requires a stable WebSocket protocol with backpressure handling

**Recommendation**: Start with Option B using a JSON-RPC-over-WebSocket protocol. Define it in `packages/protocol/src/agent.ts`:

```typescript
export interface AgentMessage {
  jsonrpc: "2.0";
  id: string;
  method: string;
  params?: Record<string, unknown>;
}

export interface AgentNotification {
  jsonrpc: "2.0";
  method: string;
  params: Record<string, unknown>;
}
```

Methods:
- `agent.observation` (notification from app → agent, pushed each loop tick)
- `tools.list` / `tools.call` (request/response)
- `memory.get` / `memory.set` / `memory.delete`
- `session.finish`

---

## 9. Security Considerations

Computer use implies autonomous system interaction. Key concerns:

| Concern | Mitigation |
|---------|------------|
| Unintended file access | Sandboxed to `~/action-sessions/` output dir; no arbitrary file read |
| Password / credential exposure | Never store secrets; agent sees only AX tree and screen frames |
| Unbounded loop | Agent loop must report a maximum step count; session times out |
| Click spam | Cooldown between actions (configurable, default 300ms) |
| Permission escalation | `requestPermissions()` must be user-gesture initiated |

The `Action.app` sandbox profile should be updated to reflect these constraints. For now, this is a local-only tool — no network-exposed agent by default.

---

## 10. Verification

### Smoke Tests for Computer Use Readiness

```bash
# Vision stream
$ curl -X POST ws://localhost:9234 --json '{ "method": "tools.call", "params": { "name": "startVisionStream", "args": {} } }'
$ # Should receive frame payloads every second

# AX tree query
$ curl -X POST ws://localhost:9234 --json '{ "method": "tools.call", "params": { "name": "queryAccessible", "args": { "query": { "role": "AXButton" } } } }'
$ # Should return list of buttons

# Continuous observation loop (5 steps)
$ curl -X POST ws://localhost:9234 --json '{ "method": "agent.startLoop", "params": { "goal": "Open Safari and go to example.com", "maxSteps": 5 } }'
$ # Should stream back 5 observation payloads with decreasing uncertainty
```

---

## 11. Priority Order

1. **Frame stream + AX cache** — foundation for all perception
2. **Expanded action surface** (scroll, right-click, double-click, hover)
3. **Tool call protocol over WebSocket** — makes the external agent possible
4. **Clipboard + shell commands** — unlocks most practical workflows
5. **Memory store** — enables context carry-over
6. **External agent loop** — the actual computer use brain
7. **Self-correction / retry** — closes the loop reliably
8. **Smooth mouse motion** — better demo output

---

## 12. Open Questions

- Should the agent runtime support **interrupt** mid-action (user says "stop")?
- Should there be a **dry-run** mode where the agent describes what it would do without executing?
- Do we want **multiple simultaneous agent sessions**? Today sessions are single.
- What is the **authorization model** for shell commands? Any agent-requested shell is a risk.
- Should we support a **headless variant** of Action.app for server-side computer use?
