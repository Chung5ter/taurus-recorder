#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Taurus Recorder"
VOLUME_NAME="$APP_NAME"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/.build"
MOUNT_DIR="$BUILD_DIR/dmg-mount"
RW_DMG="$BUILD_DIR/${APP_NAME}.rw.dmg"
FINAL_DMG="${DMG_PATH:-$DIST_DIR/${APP_NAME}.dmg}"

APP_BUILD_OUTPUT="$("$ROOT_DIR/Scripts/build-app-bundle.sh")"
APP_DIR="$(printf '%s\n' "$APP_BUILD_OUTPUT" | tail -n 1)"

if [[ ! -d "$APP_DIR" ]]; then
  printf '%s\n' "$APP_BUILD_OUTPUT" >&2
  echo "error: app bundle was not created at expected path: $APP_DIR" >&2
  exit 1
fi

rm -rf "$MOUNT_DIR" "$RW_DMG" "$FINAL_DMG"
mkdir -p "$DIST_DIR" "$MOUNT_DIR"

APP_SIZE_KB="$(du -sk "$APP_DIR" | awk '{print $1}')"
DMG_SIZE_MB="$((APP_SIZE_KB / 1024 + 100))"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -size "${DMG_SIZE_MB}m" \
  "$RW_DMG" >/dev/null

hdiutil attach "$RW_DMG" \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "$MOUNT_DIR" >/dev/null

cleanup() {
  if mount | grep -F "$MOUNT_DIR" >/dev/null; then
    hdiutil detach "$MOUNT_DIR" -quiet || true
  fi
}
trap cleanup EXIT

cp -R "$APP_DIR" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"

osascript <<APPLESCRIPT >/dev/null
tell application "Finder"
  set dmgFolder to POSIX file "$MOUNT_DIR" as alias
  tell folder dmgFolder
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 640, 420}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set position of item "$APP_NAME.app" of container window to {165, 160}
    set position of item "Applications" of container window to {375, 160}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" -quiet
trap - EXIT

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$FINAL_DMG" >/dev/null

rm -f "$RW_DMG"
echo "$FINAL_DMG"
