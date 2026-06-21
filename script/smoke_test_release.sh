#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Fonim"
EXPECTED_BUNDLE_ID="local.vibevoice.batch"
EXPECTED_VERSION="${VERSION:-0.13.0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
APP_ICON="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
ZIP_PATH="$ROOT_DIR/dist/${APP_NAME}-${EXPECTED_VERSION}.zip"

cd "$ROOT_DIR"

swift build
swift run VibeVoiceBatchCoreChecks
./script/build_and_run.sh --verify
./script/package_app.sh
git diff --check

if rg -n "b[a]tch_gui" Sources ARCHITECTURE.md BACKENDS.md HIG_CHECKLIST.md MODEL_ADAPTER_SPEC.md INSTALLATION_FLOW.md ERROR_HANDLING.md PACKAGING.md Package.swift script; then
  echo "Unexpected legacy Python GUI reference found." >&2
  exit 1
fi

test -d "$APP_BUNDLE"
test -x "$APP_BINARY"
test -f "$APP_ICON"
test -f "$ZIP_PATH"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
VERSION_STRING="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST")"

test "$BUNDLE_ID" = "$EXPECTED_BUNDLE_ID"
test "$VERSION_STRING" = "$EXPECTED_VERSION"
test "$ICON_FILE" = "AppIcon"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null

echo "Release smoke test passed:"
echo "  $APP_BUNDLE"
echo "  $ZIP_PATH"
