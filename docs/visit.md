# Visiting cursor

A visit lends one machine's mouse and keyboard to another without moving the
other machine's own cursor. Push the pointer past the edge that faces a paired
host and it parks there, frozen. From then on your mouse drives a coral
**visitor** on the host, labelled with your machine's name, the way a screen
share shows a second cursor. Your keys type on the host. Nothing on the host
asks for a new permission: the visit rides the companion bridge's pairing, and
needs the `input.trackpad` capability that pairing already grants.

A visit ends when:

- the visitor goes back off the edge it came in by;
- you press **⌃⌥⌘ Home**, or pick Bring Cursor Home from the menu bar;
- the channel drops, or either side stops hearing from the other for 6 seconds.

Your own cursor never left, so ending a visit can't strand it.

## Channel

`GET /visit` on the bridge port (5287) upgrades to a WebSocket. The upgrade
request carries the same signed headers as every protected bridge request
(`X-Lattices-Device-Id`, `-Timestamp`, `-Nonce`, `-Signature`), signed over
method `GET`, path `/visit` and an empty body. The host checks them, and that
the device holds `input.trackpad`, before upgrading. Otherwise it answers
401 or 403 as for any other route.

Every frame after that is a **binary** message: a ChaChaPoly sealed box in its
combined form (12-byte nonce, ciphertext, 16-byte tag). There's no base64. The
key is the device's encryption key, the one bridge bodies already use. The AAD
is the UTF-8 of:

```
visit\n<direction>\n<device id>\n<upgrade nonce>\n<seq>
```

`direction` is `up` from the visiting device and `down` from the host. `seq`
starts at 0 in each direction and goes up by one per frame. A frame that
doesn't open, or arrives out of sequence, closes the socket with code 1008.

The plaintext is one JSON object with a type in `t`.

### Up (visiting device → host)

| `t` | Fields | Meaning |
| --- | --- | --- |
| `enter` | `name`, `edge`, `at` | Start a visit. `edge` is the side of the host's screens the visitor comes in by (`left`, `right`, `top`, `bottom`). `at` (0–1) is the position along that edge. `name` labels the visitor. |
| `move` | `dx`, `dy` | Relative motion in the device's points. |
| `button` | `button`, `down` | `left`, `right` or `middle`, pressed or released. |
| `scroll` | `dx`, `dy` | Pixels. Positive `dy` scrolls down, positive `dx` scrolls right. |
| `key` | `key`, `mods` | One keystroke. `key` is an XKB keysym name (`Return`, `a`, `Left`, `F5`); `mods` lists any of `ctrl`, `shift`, `alt`, `super`. The Mac sends ⌘ as `super`. |
| `text` | `text` | Characters to type as they are. |
| `ping` | | Sent every 2 seconds. |
| `leave` | | End the visit. |

### Down (host → visiting device)

| `t` | Fields | Meaning |
| --- | --- | --- |
| `ready` | `x`, `y` | The visitor is drawn at this host position. |
| `exit` | `edge`, `at` | The visitor went back off `edge` at `at` (0–1). The device ends the visit and puts its own cursor at the matching point of its edge. |
| `pong` | | Answers `ping`. |
| `error` | `message` | Something failed. The visit goes on unless the socket closes. |

## On the host

- **Area.** The visitor moves over the host's real screens. Virtual outputs, such
  as Lattices' own `LATS-*`, are left out, the same set Bring Cursor Home picks
  from. The edge in `enter` is the edge of that area.
- **Two cursors.** The host's own cursor stays where it is while the visitor
  moves. For a button press or a scroll, the real pointer goes to the visitor so
  the input lands there. Keyboard focus must end up where the visitor clicked.
  When the visit ends, the host's cursor goes back to where it was.
- **Release.** If the visit ends while a button is held, the host releases it.

## On the Mac

- Sharing is armed from the menu bar and only taps the mouse while it's armed.
  Crossing needs a deliberate push past the edge, not just touching it.
- During a visit the cursor is detached from the mouse
  (`CGAssociateMouseAndMouseCursorPosition`). A session event tap swallows mouse
  and key events and forwards them, so nothing on the Mac reacts.
- ⌃⌥⌘ Home ends the visit from inside that tap, so it works however the channel
  is doing.
