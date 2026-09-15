# LAT-011: Independent companion apps

Status: implementation and notarized release verification, 2026-09-14. Public
releases and website are verified; installed desktop acceptance remains open; see the [evidence matrix](LAT-011-companion-app-implementation.md).

## Ownership

Lattices offers a native Apps menu for Blink, Action and Speech. Each companion
is a separate application with an independent lifetime. Lattices owns discovery,
installation progress and launch requests; it retains no companion process handle.

| Layer | Responsibility |
| --- | --- |
| Distribution | Each product owns a signed, notarized DMG. The Lattices installer resolves a product-specific release and installs on demand. |
| Runtime | Blink owns notes/panels; Action owns its agent, permissions and recording; Speech owns queue, playback, RPC, settings and HUD. |
| Presentation | Lattices Apps offers Install or Open. Automatic icon visibility hides companion icons while Lattices runs and restores them on exit. Each companion offers Always show and retains native reopen controls. |
| Lifecycle | Installation does not launch the app or enable login items. Explicit Open uses NSWorkspace. Quitting Lattices closes its client transports, not companion processes. |

| Product | Bundle identity | Stable tag / asset |
| --- | --- | --- |
| Blink | `dev.arach.blink` | `blink-vX.Y.Z` / `Blink.dmg` |
| Action | `dev.lattices.Action` | `action-vX.Y.Z` / `Action.dmg` |
| Speech | `dev.lattices.Speech` | `speech-vX.Y.Z` / `Speech.dmg` |

Speech is this repository's extracted product, not SpeakEasy. Its executable is
`Speech`; its Swift module is `SpeechAppRuntime` to avoid Apple's Speech module.

## Native discovery and installation

`CompanionAppsMenu` refreshes Launch Services and standard Applications locations,
validates bundle identity/type/executable, and rechecks before Open. An independently
installed app is recognized. Install calls `CompanionInstallerBridge`, which runs
its packaged standalone Bun executable and displays progress, cancellation and
retry. It does not route the Install action to a website.

The resolver paginates `arach/lattices` releases and selects the newest stable
semantic version in the exact product namespace. Drafts, prereleases, ambiguous
assets and wrong origins are rejected. Transport failure remains distinct from
no available release. A release catalog entry alone is not a published artifact.

The helper checks existing installations before network work, takes a per-product
kernel lock, and creates private staging on the destination filesystem. It bounds
archive size, time and redirects, retains quarantine, mounts the DMG read-only,
and checks the expected root app. Both mounted and staged copies must pass bundle,
OS, architecture, strict Developer ID/team signature and Gatekeeper validation.
Team `2U83JFPW66` is corroborated by Action’s existing `Installer/build.sh` Developer ID default and the installed Lattices signature. A new shared `tools/release/companion-signing.json` policy requires that team and the Developer ID Application leaf extension for downloaded installs and distributable release checks. Blink previously selected any Developer ID; its release wrapper now enforces this policy. Action’s distributable wrapper does likewise. Speech enables the distribution check with `SPEECH_DISTRIBUTABLE=1`; local ad hoc builds remain supported.

A Darwin exclusive rename commits into `~/Applications` without replacing or
nesting into an existing destination. Cancellation before commit cleans owned
staging; after commit the installed result is retained. Failed detach preserves
staging rather than deleting through a mounted filesystem. Nothing is launched
or registered as a login item by installation.

## Companion icon policy

`products/shared/CompanionMenuBarVisibility.swift` is compiled independently into
each app through a source symlink; there is no shared runtime process. It observes
NSWorkspace launch/termination notifications, including the event’s process data
to avoid stale running-app snapshots. Automatic is the default; Always show
preserves a separate icon. Blink stores the preference in
`behavior.alwaysShowMenuBarIcon` in its hot-reloaded config. Action and Speech use
their own defaults. The preference changes no login registration.

Finder or Lattices Open exposes Blink Settings, Action’s existing main window,
or Speech controls even when an icon is hidden. These source links require the
monorepo layout when building; binary app bundles have no source-link dependency.
A source-only product export must include or dereference the shared source.

## Standalone Speech

`products/speech` imports the unshipped queue, voice catalog, HUD and RPC source
with file hashes and an adaptation ledger. Hudson retains caching, system/cloud
speech and playback; Vox retains provider/catalog engines. Kokoro uses Vox directly
in the Speech process, with no Lattices voice-runtime dependency. Speech positions
its own HUD 24 points above the pointer's screen bottom, without claiming that a
Lattices voice HUD is occupied.

| Boundary | Contract |
| --- | --- |
| Speech host | Loopback WebSocket port **9397**, authenticated with `Speech/RPC/capability` under Application Support; directory 0700, file 0600. |
| Existing Lattices | Agent port **9399**; existing in-process voice port **9398** remains separate. |
| Legacy speech calls | Lattices verifies the Speech capability at its own handshake boundary, then forwards `speech.*` through one persistent connection per caller. Browser Origin and missing, wrong or duplicate token headers are rejected. |
| Reservations | A caller owns its reservation until its connection closes. Unrelated disconnection cannot release it. Queued jobs belong to Speech and survive client exit. Stale receive-loop failures cannot tear down a replacement connection. |
| Credentials | Existing Keychain service `dev.lattices.app.voice` is retained; no secret bytes are copied. Cross-app Keychain approval remains possible and needs live acceptance. |
| Preferences/cache | Import absent `speech.preferredVoice.*` values once from verified Lattices release/dev and legacy domains; preserve Speech values and deliberate deletion. Existing `Caches/Lattices/Speech` storage remains in use. |

The app bundle places SwiftPM resources in `Contents/Resources`. The isolated Vox
patch makes production catalog/provider lookups use that location inside an app,
and never silently fall back to a development build directory when an app resource
is missing. This resolves strict signing's rejection of resource bundles placed
at the app root.

## Release boundary

Packaging produces an independent Speech.app and optional DMG. Current validation
uses unpublished Hudson changes and the isolated Vox resource patch, captured as
portable patches. Those changes must land through their owning repositories before
a clean default remote build can be promised. No released Blink, Action or Speech
assets were returned by the paginated API check on 2026-09-14. Publication,
notarization, downloaded installation and installed-app UI/audio/lifecycle checks
remain acceptance gates, not inferred successes.
