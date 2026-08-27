# Blink → Action: targeting LSUIElement note panels

Problem statement and acceptance params. Not a design. Action owns the
solution.

## Who we are

Blink is an `LSUIElement` menubar app (`dev.arach.blink`). The note is the
window: one floating `NSPanel` per note, no Dock icon, no main library
window. A detached chrome rail can sit outside the page. We live-verify
that chrome from agent harnesses.

Two processes often share the bundle id at once:

- Production: `/Applications/Blink.app` (no `BLINK_HOME`)
- Dev/sandbox: `/Users/art/dev/blink/dist/Blink.app` (`BLINK_HOME` set)

Both advertise `dev.arach.blink`.

## What failed

A green Blink chrome build could not be live-verified through Action
(flight `flt-msxb3t9a-kojz45`). Observed:

1. Targeting by bundle id hit the wrong process, or neither.
2. After `blink present` against the sandbox bundle, inspect reported 0
   windows even when a note panel existed.
3. Activate / focus-window timed out waiting for Blink to become
   frontmost. Accessory apps do not.
4. Layer-0 / large-titled-window filters dropped the floating note and
   the detached rail.
5. We could not launch the sandbox bundle with `BLINK_HOME` and fail
   closed on “present created no windows.”

Keychain password prompts and Computer Use click+wait batches are
**not** this problem. Keychain is Blink signing. Click+wait is a harness
schema issue, not Action MCP.

## What any acceptable solution must make true

These are outcomes. Names, APIs, and file layout are yours.

1. **Instance identity.** We can name one running Blink when two share
   `dev.arach.blink`. Path of the running bundle, or pid, is enough.
   Bundle id alone with two matches must not silently pick one.

2. **Accessory is first-class.** An `LSUIElement` / accessory app is a
   valid target. Success must not require Blink to become
   `NSWorkspace.frontmostApplication`.

3. **Note panels count as windows.** A floating `NSPanel`, including
   child / non-activating / non-layer-0 chrome, must appear in the
   window list for that instance. “0 windows” is only correct when that
   process actually has none.

4. **Fail closed on the instance we named.** If we asked for
   `dist/Blink.app` and that process has no panel, say so. Do not
   substitute `/Applications/Blink.app`.

5. **Raise without stealing the Dock.** We need the named panel ordered
   front enough to screenshot and click. We do not need Blink to look
   like a regular app.

6. **Deterministic sandbox launch (nice, not the unblock).** Starting
   `dist/Blink.app` with `BLINK_HOME=…` and waiting until N windows exist
   would make the verify loop honest. Identity + window list unblocks us
   first.

## Acceptance case

Both Blink binaries running. Then, against the **sandbox** instance only:

```text
blink present <id>          # writes the note; sandbox should show a panel
<Action: target dist/Blink.app>
<Action: list / raise its windows>
```

Pass: the sandbox note panel is in the list (`>= 1` window) and can be
raised for a screenshot. Production Blink is still running and is not
the target.

Fail: Action activates or lists the production app; reports 0 windows
while the sandbox panel is on screen; or errors because Blink never
became frontmost.

## Out of scope for this ask

- Designing Action’s MCP surface or method names
- Computer Use batching
- Blink Keychain / codesign
- OpenScout HUD / SCO-094
- A full “LSUIElement adapter” unless you decide you need one
