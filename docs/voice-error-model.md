# Voice Error Model

## Goal + anchors

Use one error vocabulary for Mac voice capture/execution and iPad relay/status. The canonical protocol says Lattices borrows Vox for capture and never owns the mic directly (`docs/voice-command-protocol.md:5-7`), but the shared runtime already has a cross-platform `DeckVoiceState` slot (`swift/Sources/DeckKit/DeckRuntimeSnapshot.swift:49-68`). Current Mac code exposes local strings (`VoxError`, `executionResult`) instead of structured errors (`apps/mac/Sources/VoxClient.swift:43-59`, `apps/mac/Sources/AudioProvider.swift:343-349`); iPad has only a generic `errorMessage` (`apps/ios/Sources/DeckStore.swift:18`). Normalize at DeckKit, then let each surface render the same object.

## Error structure

Prefer `DeckVoiceError` now; if later reused for trackpad/deck actions, lift the same shape to `LatsError`.

```swift
public struct DeckVoiceError: Codable, Equatable, Identifiable, Sendable {
    public var id: String              // uuid or request id
    public var code: DeckVoiceErrorCode
    public var severity: DeckErrorSeverity
    public var recoverable: Bool
    public var retry: DeckRetryHint?
    public var source: DeckErrorSource // mac, ipad, vox, daemon, intent, bridge
    public var owner: String?          // e.g. "Vox", "Lattices", "Bridge"
    public var message: String         // cockpit copy, already human-readable
    public var remediation: DeckRemediationAction?
    public var occurredAt: Date
    public var detail: String?         // diagnostic-only
}

public enum DeckVoiceErrorCode: String, Codable, Sendable { case vox_unreachable, daemon_unreachable, network, connection_lost, mic_denied, accessibility_denied, mic_busy, no_active_target, vox_not_running, vox_loading, intent_unresolved, action_failed, transcription_failed, empty_transcript, language_unsupported }
public enum DeckErrorSeverity: String, Codable, Sendable { case info, warning, error, blocked }
public enum DeckRetryHint: String, Codable, Sendable { case silent, immediate, afterLaunch, userAction }
public enum DeckErrorSource: String, Codable, Sendable { case mac, ipad, vox, daemon, intent, bridge }
public enum DeckRemediationAction: Codable, Equatable, Sendable {
    case openVox, openSystemSettings(kind: String), retryVoice, openDiagnostics, chooseTarget
}
```

Add `var error: DeckVoiceError?` and optionally `var lastError: DeckVoiceError?` to `DeckVoiceState`, preserving existing `phase`, transcript, and provider fields (`swift/Sources/DeckKit/DeckRuntimeSnapshot.swift:49-68`). Codes should stay stable string raw values for JSON logs and iPad bridge snapshots.

## Categories

| Category | Codes | Recovery rule |
|---|---|---|
| Connection | `vox_unreachable`, `daemon_unreachable`, `network`, `connection_lost` | Recoverable unless active capture was lost. Silent reconnect when idle; visible banner during `listening`/`transcribing`. |
| Permission | `mic_denied`, `accessibility_denied` | Needs user action. `mic_denied` is Mac/Vox-owned; iPad only relays it. `accessibility_denied` blocks execution/navigation. |
| State | `mic_busy { owner }`, `no_active_target`, `vox_not_running`, `vox_loading` | Usually recoverable. `mic_busy` waits for owner; `vox_not_running` supports launch-on-demand. |
| Execution | `intent_unresolved`, `action_failed`, `transcription_failed` | Recoverable by retry or edited command; escalate to log if repeated. |
| Validation | `empty_transcript`, `language_unsupported` | Recoverable; no scary chrome. Treat as a missed command, not a crash. |

Copy examples: `Mic in use by Vox — finish memo first`, `No target window`, `Vox offline — starting`, `Connection lost — press again`, `Intent not found`.

## Presentation patterns

**Mac VoiceCommandWindow.** Keep the three-column cockpit. The top mic bar already owns live state (`connecting...`, `processing...`; `apps/mac/Sources/VoiceCommandWindow.swift:692-719`); render the active error as a compact red/amber status chip there. The center column uses `commandSection` cards (`apps/mac/Sources/VoiceCommandWindow.swift:1287-1304`): show a single `blocked`/`needs action` card only when the user can do something. The footer already has key chips (`apps/mac/Sources/VoiceCommandWindow.swift:1308-1348`); replace the generic command list with contextual remediation: `⌥ Retry`, `Return Open Vox`, `⌘, Permissions`. Logs stay in the right rail, using existing level colors (`apps/mac/Sources/VoiceCommandWindow.swift:1112-1150`).

**Mac HUD.** `HUDTopBar.voiceStatus` already has dot, label, transcript, response (`apps/mac/Sources/HUDTopBar.swift:134-198`). Add severity tint: green idle/listening, amber connecting/recoverable, red blocked. For active voice errors, HUD shows a one-line banner in the top bar; no sheet.

**iPad Home.** Add `HomeVoiceOverlay` as the full voice modal for active relay: title row `VOICE`, phase, transcript, Mac owner, and one remediation button. The bottom bar already has dense status slots and `hold·space` (`apps/ios/Sources/Home/HomeBottomBar.swift:58-68`, `apps/ios/Sources/Home/HomeBottomBar.swift:129-148`); render idle/recoverable errors inline there (`voice · reconnecting`, `voice · Vox offline`). Use a deck overlay banner only when an issued iPad action failed. Use sheets only for permissions/pairing because they need human action. This follows the chrome rule: do not remove noisy UI; replace it with state that answers “what am I controlling, who is listening, what failed?” (`/Users/arach/.claude/projects/-Users-arach-dev-lattices/memory/feedback_chrome_design.md:11-13`).

## Unhappy-path prescriptions

**Launch Vox on demand.** Spec flow is detect installed/not running, open Vox, show `Starting Vox...`, wait up to 10s, retry `startDictation`, then fail with manual-open copy (`docs/voice-command-protocol.md:73-89`). Current Mac waits 2s after `connect()` (`apps/mac/Sources/VoiceCommandWindow.swift:290-313`); design target is `vox_not_running` → `vox_loading` → retry → either clear error or `vox_unreachable` with `openVox`.

**Mic busy.** Preserve owner attribution from protocol (`docs/voice-command-protocol.md:127-135`). `mic_busy(owner: "Vox")` is warning, recoverable, retry hint `userAction`; message: `Mic in use by Vox — finish memo first`. If owner is unknown: `Mic busy — wait for current recording`.

**Connection recovery.** If idle, reconnect silently and write log only. If active, show red `Connection lost`; do not auto-retry captured audio because Vox cancels dropped sockets (`docs/voice-command-protocol.md:174-188`). iPad shows `Mac voice link lost` if bridge lost, not `network` unless the iPad transport failed.

**JSONL.** Add `~/.lattices/voice.jsonl` beside `lattices.log` (current log path is `~/.lattices/lattices.log`; `apps/mac/Sources/DiagnosticLog.swift:40-59`). Shape:

```json
{"ts":"2026-04-27T14:03:11.120Z","platform":"mac","sessionId":"...","phase":"listening","event":"error","error":{"code":"mic_busy","severity":"warning","recoverable":true,"source":"vox","owner":"Vox","message":"Mic in use by Vox — finish memo first"},"transcript":null,"intent":null,"durationMs":820}
```

## Cross-platform conventions

Tone: terse cockpit, no apologies. Prefer noun-state-action: `Vox offline — starting`, `No target — pick window`, `Access denied — enable Accessibility`. Tint maps to existing palettes: Mac `Palette.detach` amber and `Palette.kill` red (`apps/mac/Sources/Theme.swift:19-23`); iPad `LatsPalette.amber/red` (`apps/ios/Sources/LatsDeckScreen.swift:19-25`). Icons: `mic.fill` live, `mic.slash` denied, `waveform.badge.exclamationmark` transcription, `bolt.trianglebadge.exclamationmark` execution, `wifi.exclamationmark` connection, `scope` target. Ownership: Mac owns Vox, mic, Accessibility, intent execution, and JSONL. iPad owns relay/bridge/network presentation and never claims direct mic capture.
