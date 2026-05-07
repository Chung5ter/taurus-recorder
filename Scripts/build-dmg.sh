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
BACKGROUND_DIR="$BUILD_DIR/dmg-background"

APP_BUILD_OUTPUT="$("$ROOT_DIR/Scripts/build-app-bundle.sh")"
APP_DIR="$(printf '%s\n' "$APP_BUILD_OUTPUT" | tail -n 1)"

if [[ ! -d "$APP_DIR" ]]; then
  printf '%s\n' "$APP_BUILD_OUTPUT" >&2
  echo "error: app bundle was not created at expected path: $APP_DIR" >&2
  exit 1
fi

rm -rf "$MOUNT_DIR" "$RW_DMG" "$FINAL_DMG" "$BACKGROUND_DIR"
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
mkdir -p "$MOUNT_DIR/.background" "$BACKGROUND_DIR"

cat > "$BACKGROUND_DIR/background.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="640" height="420" viewBox="0 0 640 420">
  <defs>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="2" stdDeviation="3" flood-color="#000000" flood-opacity="0.18"/>
    </filter>
  </defs>
  <rect width="640" height="420" fill="#f5f5f7"/>
  <path d="M251 166 H343" fill="none" stroke="#6e6e73" stroke-width="14" stroke-linecap="round" filter="url(#shadow)"/>
  <path d="M337 132 L394 166 L337 200 Z" fill="#6e6e73" filter="url(#shadow)"/>
  <text x="320" y="266" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif" font-size="18" fill="#6e6e73">Drag Taurus Recorder to Applications</text>
</svg>
SVG

qlmanage -t -s 640 -o "$BACKGROUND_DIR" "$BACKGROUND_DIR/background.svg" >/dev/null 2>&1
mv "$BACKGROUND_DIR/background.svg.png" "$MOUNT_DIR/.background/background.png"

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
    set background picture of theViewOptions to POSIX file "$MOUNT_DIR/.background/background.png"
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
