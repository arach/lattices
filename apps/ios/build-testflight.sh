#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$ROOT"
PROJECT="$PROJECT_DIR/LatticesCompanion.xcodeproj"
SCHEME="LatticesCompanion"
DERIVED_DATA="$PROJECT_DIR/.derived-data-release"
ARCHIVE_PATH="$PROJECT_DIR/.archives/LatticesCompanion.xcarchive"
EXPORT_PATH="$PROJECT_DIR/.archives/export"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"
IPA_PATH="$EXPORT_PATH/LatticesCompanion.ipa"

usage() {
  cat <<'USAGE'
Usage: ./build-testflight.sh [archive|upload|all]

Builds a TestFlight-ready LatticesCompanion IPA.

Commands:
  archive   Generate the Xcode project, archive, and export an IPA
  upload    Upload the exported IPA to App Store Connect
  all       Archive, export, and upload

Upload requires App Store Connect API credentials:
  ASC_API_KEY_ID       Key ID, for example ABC123DEFG
  ASC_API_ISSUER_ID    Issuer UUID
  ASC_API_KEY_PATH     Path to AuthKey_<KEY_ID>.p8

USAGE
}

command="${1:-archive}"
if [[ "$command" != "archive" && "$command" != "upload" && "$command" != "all" ]]; then
  usage
  exit 1
fi

archive() {
  echo "Generating Xcode project"
  xcodegen generate --spec "$PROJECT_DIR/project.yml"

  rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
  mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"

  echo "Archiving $SCHEME"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=2U83JFPW66 \
    archive

  echo "Exporting IPA"
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates

  if [[ ! -f "$IPA_PATH" ]]; then
    echo "Expected IPA not found at $IPA_PATH" >&2
    exit 1
  fi

  echo "IPA ready: $IPA_PATH"
}

upload() {
  if [[ ! -f "$IPA_PATH" ]]; then
    echo "IPA not found at $IPA_PATH. Run ./build-testflight.sh archive first." >&2
    exit 1
  fi

  : "${ASC_API_KEY_ID:?Missing ASC_API_KEY_ID}"
  : "${ASC_API_ISSUER_ID:?Missing ASC_API_ISSUER_ID}"
  : "${ASC_API_KEY_PATH:?Missing ASC_API_KEY_PATH}"

  key_dir="$(dirname "$ASC_API_KEY_PATH")"
  key_name="$(basename "$ASC_API_KEY_PATH")"
  expected_name="AuthKey_${ASC_API_KEY_ID}.p8"
  if [[ "$key_name" != "$expected_name" ]]; then
    echo "ASC_API_KEY_PATH must point to $expected_name for altool API key upload." >&2
    exit 1
  fi

  echo "Uploading IPA to App Store Connect"
  API_PRIVATE_KEYS_DIR="$key_dir" xcrun altool \
    --upload-app \
    --type ios \
    --file "$IPA_PATH" \
    --apiKey "$ASC_API_KEY_ID" \
    --apiIssuer "$ASC_API_ISSUER_ID"
}

case "$command" in
  archive)
    archive
    ;;
  upload)
    upload
    ;;
  all)
    archive
    upload
    ;;
esac
