# LAT-011: Release acceptance

Current status, 2026-09-14: all four release artifacts are Developer ID signed,
Apple-notarized and stapled. Publication is the next step. Earlier preparation
notes below are historical and do not describe current authorization or builds.

| Product | Release | Notarization submission |
| --- | --- | --- |
| Lattices | 0.12.0 | 9444db30-9c70-47d8-99c0-8fe7c39439c2 |
| Blink | 2.1.0 | e2b95340-d033-4aed-9387-9cbbff99fc19 |
| Action | 0.3.0 | 3179d4a8-44ca-4330-9b07-2d917f3ece20 |
| Speech | 0.2.0 | 00e36b7d-e794-4504-9da7-57dbd1bece27 |

Versions follow verified public predecessors: Lattices0.11.2, Blink2.0.5,
Action0.2.0. Speech is a new product advanced from its0.1.0 source version.
The user authorized minor bumps, owning-repository dependency integration,
Apple submission, source publication, release tags and asset uploads.

## Verified current evidence

- Hudson PR228 and Vox PR31 are merged. Clean remote dependency builds pass for
  Speech and Lattices; Blink builds with its existing remote pinned Hudson.
- Hudson40 tests pass. A cancelled shared-cache waiter now returns immediately
  while other waiters retain the shared synthesis task; this fixes the actual
  cancellation deadlock found during release testing.
- Lattices20 native release tests pass, including actual NSMenu dispatch and
  ephemeral daemon authorization. TypeScript and installer17 tests/45 assertions pass.
- Speech45 release tests pass. The exact notarized Speech process passes the
  proxy-exit/queue-survival probe with audio suppressed by a client reservation.
- Blink, Action and Speech DMGs each pass actual read-only mounting, source and
  staged Gatekeeper/signature checks, quarantine, exclusive atomic placement,
  final bundle verification and cleanup in temporary roots. The reusable probe
  is `tests/companion-artifact-install.ts`; it does not launch any app.
- The final Lattices bundled installer passes its real kernel-lock and exclusive
  commit runtime check.
- The site exports Blink, Action and Speech pages. Desktop1440 and mobile390
  browser checks show no overflow or JavaScript errors; local links/assets resolve.
  Blink spacing was corrected within the existing product design. Source merge
  does not deploy: Pages is manual workflow_dispatch. Production site deployment
  has not occurred.

## Remaining acceptance boundary

Public asset download checks remain pending until publication. Installed desktop
Open actions, normal app termination with active user audio/recordings, and live
menu-bar preference behavior are not exercised. No installed app was launched,
quit or replaced; no test account or DNS/account changes were made. Native menu,
discovery, lifecycle and preference tests provide bounded source/process evidence.

Exact artifact hashes and dependency resolution are recorded in adjacent JSON
manifests. Local artifacts and logs under /tmp are validation outputs, not source
requirements. Release builds use remote dependencies without local overrides.

---

# Historical implementation record: LAT-011: Implementation and acceptance evidence

Date: 2026-09-14. [Architecture](LAT-011-companion-app-architecture.md).

## Review locations

- Authoritative Lattices tree: `/Users/arach/.codex/worktrees/19f1/lattices-integration`, branch `codex/companion-app-integration-owned`.
- Isolated Vox patch: `/Users/arach/.codex/worktrees/19f1/vox-speech-integration`, branch `codex/speech-app-resource-resolution`.
- No commits or publications were made. Original Grok and active shared-speech trees were preserved.
- [Dependency manifest](LAT-011-dependencies/manifest.json) records base commits, file hashes and portable patches for unpublished Hudson work and the Vox manifest/resource fix. Both patches passed git apply --cached --check against their recorded base commits using isolated temporary indexes. Apply each patch to its recorded base in a fresh owning-repository checkout. Resolved files are evidence snapshots, not new version-pinning policy.
- [Speech provenance](../../products/speech/SOURCE-PROVENANCE.json) records imported dirty-source hashes, adaptations and final source/test hashes. [Import ledger](LAT-011-integration-import.json) records the supervisor's original integration import.

## Requirement-by-requirement evidence

| Requirement | Implemented / verified | Remaining acceptance |
| --- | --- | --- |
| Blink, Action, Speech discoverable from native Lattices | Apps submenu, all three identities, refreshed discovery and revalidated NSWorkspace Open; 20 focused native tests pass and app executable compiles. | Actual NSMenu action dispatch is tested without showing UI or downloading. Visual installed-menu acceptance remains. |
| Genuine on-demand Install | Menu calls installer bridge; compiled helper bundled by dev and release packaging; progress/Cancel/retry; product-specific resolver tested for all three. | Actual published notarized artifacts are absent; downloaded installation of each product is unverified. |
| Preserve existing apps | Preflight discovery, real kernel flock, same-volume exclusive rename; race/cancel/cleanup tests and actual filesystem tests pass. | Full DMG success path against a release artifact. |
| Trust validation | Expected bundle, OS/architecture, Developer ID team, Gatekeeper, quarantine and repeated staged validation implemented. Wrong/unsigned fixture rejected. Installed Lattices passed team-signature check but failed Gatekeeper as unnotarized. | Action release default corroborates team; new common policy enforces distributable team and Developer ID leaf. Notarized companion positive path remains. |
| Independent Blink/Action lifecycle | No process ownership/termination added; existing product lifecycles untouched. | Notes remain editable and recording completes after actual Lattices quit. |
| Independent Speech product | Separate package/app/menu/settings/queue/HUD/server; real Hudson/Vox adapters and direct Kokoro adapter; staged app strictly signed and resource diagnosis succeeds. | Normal UI, audible system/cloud/Kokoro playback and Keychain approval flow. |
| Authenticated legacy Speech access | Lattices handshake capability check and persistent per-caller forwarding. Tests cover malformed auth, reservation ownership, owner/unrelated disconnect and stale receive failure after reconnect. | Real ephemeral Lattices daemon rejects unauthenticated Speech request. Authorized forwarding is covered against the actual Speech host separately; combined live product path remains. |
| Speech survives client exit | Real staged diagnostic Speech host with production runtime and separately compiled production forwarding client; queued job survives proxy exit while control connection reserves playback. | Audible playback survival and actual installed Lattices app quit were deliberately not tested. |
| Credential/preference continuity | Same Keychain service/cache; one-time preference migration test passes. | Live existing-user credential access across signatures. |
| Independent icon/login control | Automatic / Always show implemented in all three; launch/terminate observation restores icons; Blink config hot-reload retained; recovery controls on reopen. All three app targets compile; transition/persistence test passes. | Observe actual icon transitions and Finder reopen in a dedicated desktop session. |
| Reproducible release build | Local dependency bases/patches and commands captured; valid resource layout proven without development fallback. | Land dependency changes; clean remote dependency build; notarization/release. Speech Developer ID release candidate is verified below. |

## Checks and artifacts

- **17 Bun tests, 45 assertions pass**: release, transaction, actual exclusive rename, real lock and negative trust paths. Log `/tmp/lattices-companion-installer-tests.log`.
- Focused strict TypeScript check passes for all companion modules and helper builder; repository-wide TypeScript suite was not run.
- **20 native tests pass**: catalog/discovery, real NSMenu Install dispatch for all three and real loopback daemon authorization boundary. Log `/tmp/lattices-companion-native-tests.log`. Swift test builds the Lattices app executable; ordinary unrelated compiler warnings remain.
- **45 Speech tests pass**: imported queue/provider/RPC/socket contracts plus migration, icon transition/persistence and production-client forwarding/reconnect tests. Log `/tmp/lattices-standalone-speech-tests.log`.
- **1 Vox resource test passes**; package source compiles. Log `/tmp/lattices-vox-resource-tests.log`. Vox docs generation/check exit 0; audit reports 99/100 with six documentation drift warnings, not a clean audit.
- `/tmp/lattices-speech-review-final3/Speech.app`: debug build, **ad hoc hardened-runtime signature**, strict codesign verification passed. Production resource diagnosis loaded 16 models and provider resources from `Contents/Resources` while this task's development resource bundle was temporarily hidden and then restored. No Developer ID/notarization claim.
- `/tmp/lattices-companion-installer-final2`: compiled standalone helper, **ad hoc hardened-runtime signature** with allow-jit; strict signature verification and `--check-runtime` real lock/exclusive-commit check passed.
- [Artifact hashes](LAT-011-artifacts.json) identify the exact executable bytes. Packaging log `/tmp/lattices-speech-package-final.log`.
- `tests/companion-speech-lifecycle.ts` starts only the explicitly selected staged diagnostic host and a temporary proxy. Latest log `/tmp/lattices-speech-lifecycle.log`: `proxyExited=true`, `queueSurvivedProxyExit=true`, `audioSuppressedByReservation=true`. It clears the queue before releasing playback and terminates only its owned diagnostic host.

- **ActionHost and BlinkApp full builds pass** with indexing/debug-info generation disabled to limit disk use. Logs `/tmp/lattices-action-companion-build.log` and `/tmp/lattices-blink-companion-build.log`. Both generated source lists include the shared visibility implementation. Action’s native build script invokes the same SwiftPM package.
- Initial Blink override attempts failed for dependency identity/deployment-floor reasons. Final build uses the exact pinned Hudson commit `79ca548b2b30335a3c37fb031a753481dedaaf79` as a local path plus a `vox`-named symlink to the isolated Vox tree. Its checked-in Package.resolved was restored after saving validation evidence.
- During low disk conditions (123 MiB free), code signing reported an internal error after linking, without a specific errno. After removing only task-owned superseded artifacts using non-force commands and space recovering, final builds/tests and strict executable signature checks passed. Disk pressure is the observed correlation, not a separately proven codesign cause. No active source or installed app was removed.

## Reproduction

From the authoritative Lattices tree, after restoring the dependency bases/patches:

```sh
SPEECH_HUDSON_PATH=/tmp/hudson-shared-speech \
SPEECH_VOX_PATH=/Users/arach/.codex/worktrees/19f1/vox-speech-integration \
HUDSON_VOX_PATH=/Users/arach/.codex/worktrees/19f1/vox-speech-integration \
swift test --package-path products/speech
swift test --package-path apps/mac --filter 'CompanionApp|CompanionDaemonBoundary'
bun test tests/companion-release.test.ts tests/companion-install.test.ts tests/companion-commit.test.ts tests/companion-lock.test.ts tests/companion-trust.test.ts
SPEECH_REVIEW_APP=/tmp/lattices-speech-review-final3/Speech.app bun tests/companion-speech-lifecycle.ts
```

`products/speech/tools/package.sh` accepts the same dependency environment plus
`SPEECH_BUILD_CONFIGURATION`, `SPEECH_ARTIFACT_DIR` and `SPEECH_SIGN_IDENTITY`.
The Lattices build resolves its existing sibling Hudson dependency via the local
`../hudson` symlink to `/Users/arach/dev/hudson`; Speech uses the explicit paths above.

### Product builds

```sh
swift build --package-path products/action/native/engine --product ActionHost --disable-index-store -Xswiftc -gnone
BLINK_HUDSON_SOURCE=path \
BLINK_HUDSON_PATH=/Users/arach/.codex/worktrees/19f1/lattices-integration/products/blink/.build/checkouts/hudson \
HUDSON_VOX_PATH=/tmp/lattices-blink-dependencies/vox \
swift build --package-path products/blink --product BlinkApp --disable-index-store -Xswiftc -gnone
```

The Blink Hudson path is the recorded pinned checkout, not current Hudson main.
On a fresh machine, create a checkout at that exact commit and set the path. The
`vox` symlink resolves to the isolated Vox tree named above.

## Smallest remaining acceptance gates

1. A dedicated desktop session can open the final staged Speech.app normally to inspect its controls and icon behavior. Normal mode uses port9397 and the real Speech defaults/Keychain/cache; it is not the isolated diagnostic mode, and no normal launch was performed here. Check port availability first; never stop an existing owner.
2. The safe headless reproduction is the checked-in lifecycle command above: it owns an ephemeral host port and a temporary capability, suppresses audio with a reservation, and touches no installed app. The native daemon boundary XCTest likewise uses port0 and a temporary capability.
3. Blink/Action live UI/lifecycle acceptance needs staged bundles and a dedicated user/session. Blink’s `BLINK_HOME` isolates note files but not UserDefaults; Action’s normal launch starts its agent. Do not treat a different bundle path alone as state isolation. No installed-app replacement/quit or active recording manipulation is needed to prepare these artifacts.
4. Land the captured shared-engine dependency changes, produce Developer ID signed/notarized companion releases, then exercise real downloaded installation for each product. The current release API has no namespaced artifacts; source tests cannot close that gate.

## Release readiness and desktop handoff

- Available signing identity: Developer ID Application: Arach Tchoupani (`2U83JFPW66`), SHA-1 `7674A1E3313C27B3969E1861F3A57728FE9D9072`. Read-only `notarytool history --keychain-profile notarytool` succeeded; no submission occurred and credentials were not printed.
- Existing source versions: Blink **2.0.5**; Action **0.0.0**, plist build **1**; new Speech **0.1.0**, build **1**. Action's release script otherwise generates a timestamp build number. Action's placeholder release version needs an explicit release decision; no new version was selected.
- `/tmp/lattices-speech-distribution-candidate/Speech.app` and `Speech.dmg` are local release candidates. The arm64 app has a timestamped Developer ID hardened-runtime signature; strict verification and the shared signing policy pass. `hdiutil verify` passes. The DMG contains the signed app; the packaging script does not separately sign the DMG.
- The exact release app passes the isolated process lifecycle probe (`/tmp/lattices-speech-distribution-lifecycle.log`). Gatekeeper reports **Unnotarized Developer ID**; this is not an install-ready notarized release. No notarization, publication, normal launch, or installed-app replacement occurred.
- Build log: `/tmp/lattices-speech-distribution-candidate.log`; exact hashes are in the artifact manifest. Source/dependency patches remain reviewable and unapplied to active repositories. A subsequent Blink release build succeeded using cached dependencies; 1.7 GiB remained afterward. Existing Action full debug build passes.

Speech candidate command (using the dependency environment in Reproduction):

```sh
SPEECH_BUILD_CONFIGURATION=release \
SPEECH_ARTIFACT_DIR=/tmp/lattices-speech-distribution-candidate \
SPEECH_SIGN_IDENTITY=7674A1E3313C27B3969E1861F3A57728FE9D9072 \
SPEECH_DISTRIBUTABLE=1 SPEECH_CREATE_DMG=1 bash products/speech/tools/package.sh
```

Choose a fresh artifact directory when repeating. Blink command below was executed with the exact dependency environment above; Action remains a prepared local-candidate command:

```sh
BLINK_ARTIFACT_DIR=/tmp/lattices-blink-distribution-candidate \
BLINK_SKIP_NOTARIZE=1 BLINK_SIGN_IDENTITY=7674A1E3313C27B3969E1861F3A57728FE9D9072 \
bash products/blink/tools/release/build-dmg.sh 2.0.5
SKIP_NOTARIZE=1 VERSION=0.0.0 BUILD_NUMBER=1 bash products/action/Installer/build.sh
```

- **Blink 2.0.5 release candidate verified:** `/tmp/lattices-blink-distribution-candidate/Blink.app` and `Blink.dmg`. The app and DMG have timestamped Developer ID signatures; app hardened runtime, strict app/DMG signature checks, shared team policy, and DMG integrity all pass. Notarization explicitly skipped; Gatekeeper reports Unnotarized Developer ID. No normal launch occurred. Log: `/tmp/lattices-blink-distribution-candidate.log`.
- Initial inputs: cached native artifacts/checkouts but no release executable or editor bundle. The editor and native release builds succeeded without cleanup or modifying tracked dependency locks. Added `BLINK_ARTIFACT_DIR` to the packaging script so output is isolated; default output behavior is unchanged. Shell syntax and diff whitespace checks pass.
- **Action version conclusion:** `0.0.0` is the private package/plist fallback, not evidence of an approved public release version. Current `.github/workflows/release-action-macos.yml` requires a version input and passes it to the installer; `scripts/tag-release` and `scripts/ship-release` require explicit semver and use `action-vX.Y.Z`. The installer accepts an explicit version/build and otherwise falls back to package version/timestamp. No convention mandates publishing 0.0.0; the remaining decision is the intended public Action semver and build number. No value was invented.

The Action command preserves current source identity for a local candidate only. These scripts write product build/installer directories; run in an isolated checkout with adequate disk space. Neither command authorizes publication.

**Desktop decision needed:** use a dedicated macOS test account/session with no active Lattices, Blink, Action, or Speech services. Do not create/switch accounts automatically. Copy staged bundles there; check ports 9397–9399 and companion service ownership before launch. Then verify Automatic/Always show and Finder reopen; edit a disposable Blink note and finish a disposable Action recording after quitting only that session's Lattices; verify Speech playback continues after that quit. Test system speech first, then deliberately configured test cloud/Kokoro credentials. Existing-user Keychain migration is a separate explicit acceptance action and cannot be proven by a fresh account. The current session was used only for isolated ephemeral-port, temporary-capability, audio-suppressed probes.

## Grok supervision and reconciliation

Two delayed/overlapping reserved-profile dispatches occurred:
`flt-mu1w3sgj-m5kpxd` (`project-maxwell-2`) and
`flt-mu1w3se8-vp01yi` (`project-borges-2`). Both broker records now report
**failed: Local agent turn was interrupted**. No worker completion is claimed and
no replacement worker was created. Partial catalog/discovery/menu/tests were
reviewed, reconciled into one enum-based implementation, then extended by the
supervisor. Conflicting duplicate product/action definitions were omitted only
from the authoritative integration tree.

The stopped writers' final files and hashes are preserved at
`/var/folders/jm/ygrbdbjd7618slznbdm43sf00000gn/T/lattices-grok-terminal-tidxc39n`.
The original tree `/Users/arach/.codex/worktrees/19f1/lattices` remains intact.
The initial build's disk-full failure was followed by successful focused builds;
only task-owned partial build output was removed. Nothing installed was replaced,
launched or quit, and no release was published.
