# Shipping Blink

Three artifacts, one version (`packages/npm/package.json` `version` is the release
source of truth; the CLI's compile-time version must match and is checked during builds):

| Artifact | What | Who it's for |
|---|---|---|
| **npm** `@arach/blink` | the `blink` CLI (native binary in-tarball) + `blink-app` installer | agents / terminal |
| **DMG** on GitHub release | signed + notarized `Blink.app` | humans (double-click) |
| **CLI binary** on GitHub release | `blink-macos-arm64` | direct download / `blink-app` fallback |

Modeled on `@arach/lattices`' pipeline. All scripts live in `tools/release/`.

## One-time setup

1. **Signing identity** — a *Developer ID Application* cert in your login
   keychain. `tools/release/*.sh` auto-detect it (`security find-identity`), or
   set `BLINK_SIGN_IDENTITY`.
2. **Notarization profile** — store App Store Connect creds once:
   ```sh
   xcrun notarytool store-credentials notarytool \
     --key-id <KEY_ID> --issuer <ISSUER_ID> --key /path/AuthKey_<KEY_ID>.p8
   ```
   Then the scripts use `--keychain-profile notarytool` (override with
   `BLINK_NOTARY_PROFILE`). See `Config/signing.env.example`.
3. **npm** — `npm login` as `arach` (publishes `@arach/blink` with provenance).
4. **Hudson** — the app build needs the `hudson` dependency resolvable
   (`../hudson` checkout, or `BLINK_HUDSON_SOURCE=git` + a read token). The CLI
   build doesn't link Hudson but still needs the manifest to resolve.

## Cutting a release

```sh
# 0. bump the version
#    edit packages/npm/package.json and Sources/BlinkCLI/BlinkCLI.swift
#    -> "2.0.1"

# 1. preview the build commands and GitHub release assets
./tools/release/ship.sh --dry-run

# 2. from a clean, pushed commit: build + sign + notarize + staple the DMG and
#    CLI, then publish the GH release
./tools/release/ship.sh
#    -> creates/updates tag v<version> on arach/blink with Blink.dmg + blink-macos-arm64

# 3. publish npm from the signed GitHub CLI asset
git tag -a npm-v2.0.1 -m "@arach/blink 2.0.1"
git push origin npm-v2.0.1
```

### Individual steps

```sh
./tools/release/build-dmg.sh <version>   # just the signed+notarized DMG -> dist/Blink.dmg
./tools/release/build-cli.sh             # just the signed CLI -> packages/npm/dist/blink
BLINK_SKIP_NOTARIZE=1 ./tools/release/build-dmg.sh   # sign but skip notarization (faster)
BLINK_SKIP_SIGN=1 ./tools/release/build-dmg.sh       # unsigned local smoke build
BLINK_SKIP_SIGN=1 ./tools/release/build-cli.sh       # unsigned local CLI smoke build
```

`ship.sh` never publishes unsigned assets. It also verifies that tracked files
and release inputs are clean, local `HEAD` matches the configured remote target,
and an existing release tag still points at that exact commit before replacing
assets.

## npm CI

`.github/workflows/release-package-npm.yml` publishes on `npm-v*`. It downloads
the matching signed CLI from the GitHub release, verifies its version and code
signature, then publishes with provenance without rebuilding.

Configure npm trusted publishing for `arach/blink` and that workflow, or add an
`NPM_TOKEN` secret to the GitHub `release` environment. The token path is a
fallback; browser login is not part of the release procedure.

## Known limitations

- **Apple Silicon only.** The CLI + app are `arm64`. Universal (`lipo`
  arm64 + x86_64) is a follow-up; the npm shim errors clearly on Intel.
- No auto-update inside the app yet; `blink-app update` re-pulls the DMG.
