# Lats Deck App Store submission

Canonical App Store copy, review notes, deterministic product captures, and marketing screenshots for the iPad release.

## Capture and render

From the repository root:

```bash
bash apps/ios/scripts/capture-app-store-screenshots.sh
```

The script builds a Simulator app in a disposable DerivedData directory under `~/Library/Caches/codex-builds/`, launches five deterministic product scenes, renders the final 2064 × 2752 App Store creatives, and validates them with `asc`.

Raw captures are written to `apps/ios/.artifacts/app-store-screenshots/raw-ipad/`. Final assets live in `ipad-pro-129/` and only use real SwiftUI product renders; the renderer never invents app UI.

## Metadata

Validate canonical metadata offline:

```bash
asc metadata validate --dir apps/ios/marketing/app-store/metadata
```

Apply it after the App Store Connect app record exists:

```bash
asc metadata apply --app "$LATS_ASC_APP_ID" --version 1.0 \
  --dir apps/ios/marketing/app-store/metadata
```

Upload the approved screenshots:

```bash
asc screenshots upload --app "$LATS_ASC_APP_ID" --version 1.0 \
  --path apps/ios/marketing/app-store/ipad-pro-129 \
  --device-type IPAD_PRO_3GEN_129 --replace
```

Run App Store readiness validation after a build is uploaded and attached:

```bash
asc validate --app "$LATS_ASC_APP_ID" --version 1.0 --platform IOS
```

The first release intentionally omits `whatsNew`; App Store Connect does not accept release notes until a subsequent version.
