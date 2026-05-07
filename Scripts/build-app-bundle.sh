#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT_NAME="TaurusRecorder"
APP_NAME="Taurus Recorder"
DEFAULT_SIGN_IDENTITY="Taurus Recorder Local Code Signing"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ENCODERS_DIR="$RESOURCES_DIR/Encoders"
LICENSES_DIR="$RESOURCES_DIR/Licenses"

cd "$ROOT_DIR"
swift build -c release --product "$PRODUCT_NAME"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/$PRODUCT_NAME" "$MACOS_DIR/$PRODUCT_NAME"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

find_lame_binary() {
  if [[ -n "${LAME_BINARY_PATH:-}" && -x "$LAME_BINARY_PATH" ]]; then
    printf '%s\n' "$LAME_BINARY_PATH"
    return 0
  fi

  for candidate in /opt/homebrew/bin/lame /usr/local/bin/lame /usr/bin/lame; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  command -v lame 2>/dev/null || true
}

if LAME_PATH="$(find_lame_binary)" && [[ -n "$LAME_PATH" ]]; then
  if command -v realpath >/dev/null 2>&1; then
    LAME_REAL_PATH="$(realpath "$LAME_PATH")"
  else
    LAME_REAL_PATH="$LAME_PATH"
  fi
  mkdir -p "$ENCODERS_DIR" "$LICENSES_DIR"
  cp -f "$LAME_REAL_PATH" "$ENCODERS_DIR/lame"
  chmod 755 "$ENCODERS_DIR/lame"

  LAME_CELLAR_DIR="$(cd "$(dirname "$LAME_REAL_PATH")/.." && pwd -P)"
  for license_file in LICENSE COPYING; do
    if [[ -f "$LAME_CELLAR_DIR/$license_file" ]]; then
      cp -f "$LAME_CELLAR_DIR/$license_file" "$LICENSES_DIR/LAME-$license_file.txt"
    fi
  done
else
  echo "warning: LAME encoder not found; MP3 export will use system LAME if available at runtime" >&2
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>TaurusRecorder</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.TaurusRecorder</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Taurus Recorder</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Taurus Recorder captures system audio so you can save local recordings.</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${SIGN_IDENTITY:-$DEFAULT_SIGN_IDENTITY}"
if ! security find-identity -v -p codesigning | grep -F "\"$SIGN_IDENTITY\"" >/dev/null; then
  echo "warning: code signing identity '$SIGN_IDENTITY' not found; falling back to ad-hoc signing" >&2
  SIGN_IDENTITY="-"
fi

if [[ -x "$ENCODERS_DIR/lame" ]]; then
  codesign --force --options runtime --sign "$SIGN_IDENTITY" "$ENCODERS_DIR/lame" >/dev/null
fi
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
echo "$APP_DIR"
