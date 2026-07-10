#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Fonim"
PRODUCT_NAME="Fonim"
BUNDLE_ID="local.vibevoice.batch"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --product "$PRODUCT_NAME"
BUILD_BINARY="$(swift build --show-bin-path)/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi
if [ -f "$ROOT_DIR/Resources/media_runtimes.csv" ]; then
  cp "$ROOT_DIR/Resources/media_runtimes.csv" "$APP_RESOURCES/media_runtimes.csv"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

ensure_xctrace() {
  if xcrun xctrace version >/dev/null 2>&1; then
    return 0
  fi

  local xcode_developer_dir="/Applications/Xcode.app/Contents/Developer"
  if [ -d "$xcode_developer_dir" ]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-$xcode_developer_dir}"
  fi

  xcrun xctrace version >/dev/null
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --profile|profile)
    ensure_xctrace
    open_app
    sleep 1
    TRACE_OUTPUT="${TRACE_OUTPUT:-$DIST_DIR/${APP_NAME}-time-profile-$(date +%Y%m%d_%H%M%S).trace}"
    PROFILE_TIME_LIMIT="${PROFILE_TIME_LIMIT:-20s}"
    rm -rf "$TRACE_OUTPUT"
    xcrun xctrace record \
      --quiet \
      --template "Time Profiler" \
      --attach "$APP_NAME" \
      --time-limit "$PROFILE_TIME_LIMIT" \
      --output "$TRACE_OUTPUT" \
      --no-prompt
    echo "Trace saved: $TRACE_OUTPUT"
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--profile|--verify]" >&2
    exit 2
    ;;
esac
