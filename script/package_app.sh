#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Fonim"
PRODUCT_NAME="Fonim"
BUNDLE_ID="local.vibevoice.batch"
MIN_SYSTEM_VERSION="13.0"
VERSION="${VERSION:-0.13.0}"
BUILD_NUMBER="${BUILD_NUMBER:-13}"
CONFIGURATION="${CONFIGURATION:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
CREATE_ARCHIVE="${CREATE_ARCHIVE:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
PKG_INFO="$APP_CONTENTS/PkgInfo"
ZIP_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.zip"

usage() {
  cat >&2 <<USAGE
usage: $0 [--debug] [--release] [--no-archive] [--sign-identity IDENTITY]

Environment:
  VERSION=0.13.0
  BUILD_NUMBER=13
  SIGN_IDENTITY=-          # "-" means ad-hoc signing
  CREATE_ARCHIVE=1
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      CONFIGURATION="debug"
      shift
      ;;
    --release)
      CONFIGURATION="release"
      shift
      ;;
    --no-archive)
      CREATE_ARCHIVE="0"
      shift
      ;;
    --sign-identity)
      SIGN_IDENTITY="${2:-}"
      if [[ -z "$SIGN_IDENTITY" ]]; then
        usage
        exit 2
      fi
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

mkdir -p "$DIST_DIR"

if [[ "$CONFIGURATION" == "release" ]]; then
  swift build -c release --product "$PRODUCT_NAME"
  BUILD_BINARY="$(swift build -c release --show-bin-path)/$PRODUCT_NAME"
else
  swift build --product "$PRODUCT_NAME"
  BUILD_BINARY="$(swift build --show-bin-path)/$PRODUCT_NAME"
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Fonim</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright (c) 2026.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key>
  <true/>
  <key>NSSupportsSuddenTermination</key>
  <true/>
</dict>
</plist>
PLIST

printf "APPL????" >"$PKG_INFO"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --sign - --timestamp=none "$APP_BUNDLE"
else
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP_BUNDLE"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/codesign -dvv "$APP_BUNDLE" >/dev/null
/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null

if [[ "$CREATE_ARCHIVE" == "1" ]]; then
  rm -f "$ZIP_PATH"
  (cd "$DIST_DIR" && /usr/bin/ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH")
fi

echo "Built $APP_BUNDLE"
if [[ "$CREATE_ARCHIVE" == "1" ]]; then
  echo "Created $ZIP_PATH"
fi

if ! /usr/sbin/spctl -a -vv "$APP_BUNDLE" >/dev/null 2>&1; then
  echo "Gatekeeper assessment did not accept this local build. Use a Developer ID identity and notarization for public distribution."
fi
