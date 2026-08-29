---
name: action-browser
description: Use Action Browser when the user wants an agent to open a URL in a real Chrome session, inspect a page, click or fill a DOM element, or capture a browser screenshot without setting up a headless browser.
---

# Action Browser

Action Browser drives **Action-owned Chrome identities**. It never drives the
user's regular Chrome.

## Which browser are we talking about?

Three different browsers can be in play. Pick deliberately, and say which one
you picked.

| | What it is | How you control it |
|---|---|---|
| **The user's regular Chrome** | Their everyday browser — real profiles (`Default`, `Profile 1` / "Work"), their tabs, history, extensions, logins | `browser_open { mode: "regular" }` opens a URL and stops there. **No DOM tools.** Drive that window with Action's native macOS control: `action.observe.snapshot` (screen + accessibility), `action.resolve.target`, `action.act.execute` |
| **An Action browser** | Real, non-headless Chrome that Action owns, on its own user-data-dir. Default identity `agent-browser` is blank and signed into nothing | Full DOM tools over CDP: `browser_snapshot`, `browser_click`, `browser_fill`, `browser_resize`, `browser_screenshot` |
| **An Action browser identity seeded from a regular Chrome profile** | The same Action-owned Chrome under a name like `work`, carrying cookies copied from one of the user's real profiles for an allowlist of domains | Full DOM tools, on sites the user is already signed in to |

The tradeoff in one line: **regular Chrome gives you their real session but only
screen-and-accessibility control; an Action browser gives you DOM control but
starts as a stranger.** Seeding is how you get both.

Regular mode is not a limitation Action can lift. [Chrome 136 and later ignore
remote-debugging switches for the user's default data
directory](https://developer.chrome.com/blog/remote-debugging-port), and Action
does not attempt to bypass that boundary.

## Default workflow

1. If the user names an identity, call `browser_use_profile` or pass `profile`
   to `browser_open`. Otherwise the blank `agent-browser` identity is used.
2. Call `browser_open` with the requested URL. It reuses this agent session's
   current tab by default. Leave `background: true` unless the user asks to see
   the Chrome window, and set `newTab: true` only when parallel page state is
   intentional.
3. Call `browser_screenshot` and show the returned image to the user. To check a
   responsive layout, call `browser_resize` with an explicit width and height first.
4. Call `browser_snapshot` before interacting with unfamiliar pages.
5. Use selectors returned by the snapshot for `browser_click` and `browser_fill`.
6. Take another screenshot after an action when visual confirmation matters.

## Responsive checks: resize, then screenshot

`browser_resize` sets an already-open tab to an explicit width and height, so a
breakpoint can be captured rather than guessed at.

```text
browser_open   { url: "http://localhost:3000" }
browser_resize { width: 1440, height: 900 }
browser_screenshot

browser_resize { width: 390, height: 844, mobile: true,
                 matchMedia: ["(max-width: 767px)"] }
browser_screenshot

browser_resize { reset: true }
```

- `target: "tab"` (default) emulates the size for that one tab. It is exact, it
  leaves every other tab alone, and `deviceScaleFactor: 1` makes screenshot
  pixels equal CSS pixels — a 390-wide viewport returns a 390px-wide PNG.
- `target: "window"` resizes the real Chrome window instead. Use it when
  emulation is not trustworthy for what is being checked; it moves every tab in
  that window, the display is a hard ceiling, and it drops the tab's emulated
  viewport first.
- The size **sticks to that tab** across later `browser_open`, `browser_snapshot`,
  and `browser_screenshot` calls until `reset: true`. It is dropped when the tab
  or the browser closes, and nothing is written to the profile.
- Pass `matchMedia` to have the breakpoint answered rather than eyeballed, and
  read `exact` in the reply — a page with a hard `min-width` can refuse to lay
  out as narrow as requested.
- `mobile: true` additionally honours the viewport meta tag and enables touch,
  which is what makes a real phone layout appear instead of a squeezed desktop one.

## Signed-in work: seed, then drive

When the page needs the user's login, seed an identity instead of handing off to
regular Chrome. `source` is the profile **directory** name, not the display
name — a browser the user calls "Work" is usually the `Profile 1` directory.

```text
browser_import_cookies { listSourceProfiles: true }
# -> maps display names to directories, e.g. "Work" -> "Profile 1"

browser_import_cookies { into: "work", source: "Profile 1", domains: ["github.com"] }
# dry run: lists the cookies that would be copied

browser_import_cookies { into: "work", source: "Profile 1", domains: ["github.com"], confirm: true }
# writes them, after the user approves

browser_open { url: "https://github.com/notifications", profile: "work" }
browser_snapshot
browser_screenshot
```

Rules for seeding:

- Always pass a domain allowlist. Never copy the whole cookie jar.
- Dry-run first; `confirm: true` needs the user's approval.
- Cookies are not a complete identity. localStorage and passkeys may still need
  a one-time interactive login in the Action browser.
- Never claim a page is authenticated without observing it after the seed.

## Handing off to regular Chrome

When the user explicitly asks to open something in *their* browser:

```text
browser_open { url: "https://github.com", mode: "regular" }
```

This is a visible, open-only handoff. Do not follow it with `browser_snapshot`,
`browser_click`, `browser_fill`, or `browser_screenshot` — those stay attached
to the Action browser. If the user then wants the agent to act on that window,
switch to Action's native tools rather than the browser tools.

## Identities and companion

- Identities live under `~/Library/Application Support/Action/ChromeProfiles/<name>`.
- Default is `agent-browser` unless `ACTION_BROWSER_PROFILE` is set.
- `browser_profiles` lists identities; `browser_profile_info` shows the active one.
- Any unused name creates a fresh blank identity on first open.
- `browser_companion_status` reports the Chrome Companion extension dist and
  localhost bridge. Richer DOM tooling lives in `packages/chrome-companion`;
  load its `dist` unpacked once per identity when the user wants that path.

## Important behavior

- Real Chrome with CDP — not headless.
- `browser_open` defaults to `mode: "action"`; `mode: "regular"` truthfully
  returns `controlAvailable: false` plus the native control path.
- `browser_open` creates one working tab per agent session, then navigates that
  tab on later calls. Use `newTab: true` for an intentional additional tab.
- `browser_screenshot` saves a PNG artifact and returns the image in the tool
  response, and reports the `viewport` it was captured at.
- `browser_resize` needs a tab already open; it changes size, never navigation.
- Prefer a stable CSS selector from `browser_snapshot` over text matching.
- Chrome belongs to the agent session that started it. It quits when that
  session ends, after fifteen idle minutes, or on `browser_close` with
  `scope: "browser"` — whichever comes first.
- Call `browser_close` with `scope: "browser"` when a browsing task is finished
  and nothing further is expected.

## Safety

Opening, inspecting, and capturing pages are ordinary read actions. Treat clicks
and form fills according to their actual consequence. Do not submit purchases,
publish content, delete data, or confirm other consequential actions without
the user's authority. Cookie import requires an explicit `confirm: true`.
