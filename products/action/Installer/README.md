# Action Installer Build System

Build, sign, and notarize the macOS DMG for Action.

## Prerequisites

- Xcode Command Line Tools
- Developer ID Application certificate
- Notarization credentials stored with `xcrun notarytool store-credentials`

The default local signing values match the Talkie release setup:

```bash
ACTION_DEVELOPER_ID_APP="Developer ID Application: Arach Tchoupani (2U83JFPW66)"
ACTION_NOTARY_PROFILE="notarytool"
```

If multiple certificates have the same display name, the build script resolves
the name to the first matching SHA-1 identity before calling `codesign`. You can
also set `ACTION_DEVELOPER_ID_APP` directly to a 40-character identity hash.

## Usage

```bash
bun run native:dmg:build
```

For local packaging without notarization:

```bash
SKIP_NOTARIZE=1 bun run native:dmg:build
```

To set release metadata:

```bash
bun run native:dmg:build -- --version 0.1.0 --build 12
```

## Output

The script creates:

| Artifact | Output | Contents |
|----------|--------|----------|
| DMG | `Installer/Action-for-Mac.dmg` | `Action.app` plus an Applications alias |

When notarization is enabled, the finished DMG is also copied to:

```text
Installer/releases/<version>/Action-for-Mac.dmg
```

## What The Script Does

1. Verifies the Developer ID Application certificate.
2. Builds `Action.app` in release mode.
3. Signs the app and embedded `ActionAgent.app` with hardened runtime and timestamp.
4. Creates a Finder-style drag-to-Applications DMG.
5. Signs the DMG.
6. Submits the DMG for Apple notarization, unless `SKIP_NOTARIZE=1`.
7. Staples the notarization ticket and runs a Gatekeeper assessment.

## User Installation

Users install Action the same way they install Talkie:

1. Open `Action-for-Mac.dmg`.
2. Drag `Action.app` to Applications.
3. Launch Action from Applications.
4. Grant Accessibility and Screen Recording when prompted.

## Troubleshooting

Check notarization history:

```bash
xcrun notarytool history --keychain-profile notarytool
```

Verify the final DMG:

```bash
codesign --verify --verbose Installer/Action-for-Mac.dmg
spctl --assess --type open --context context:primary-signature -vv Installer/Action-for-Mac.dmg
```

## GitHub Release Workflow

The Talkie-style workflow lives at:

```text
.github/workflows/release-mac.yml
```

It expects these release environment secrets:

```text
DEVELOPER_ID_APPLICATION_CERT_BASE64
DEVELOPER_ID_APPLICATION_CERT_PASSWORD
KEYCHAIN_PASSWORD
APP_STORE_CONNECT_API_KEY_P8
```

And these release environment variables:

```text
APP_STORE_CONNECT_KEY_ID
APP_STORE_CONNECT_ISSUER_ID
```

The workflow stores a temporary `notarytool` profile on the runner and then
calls:

```bash
bun run native:dmg:build -- --version "$VERSION" --build "$BUILD_NUMBER"
```

On `v*` tag pushes, it publishes the notarized DMG to the current repository's
GitHub Release as `Action.dmg` and `Action-<version>.dmg`.

Create and push a release tag:

```bash
bun run release:tag -- 0.1.0
```

To upload an already-built local DMG to the GitHub Release too:

```bash
bun run release:tag -- 0.1.0 --upload-bin
```
