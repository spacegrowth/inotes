#!/bin/bash
# Build iNotes.dmg — a drag-and-drop disk image: iNotes.app beside an "Applications" alias, in a
# tidy icon-view window. Assumes build/Build/Products/Release/iNotes.app is already built, Developer
# ID-signed, and notarized+stapled. Signs the .dmg with APP_IDENTITY when set (Developer ID App).
#
# iNotes's app icon lives in the asset catalog (compiled into
# Assets.car), not a standalone AppIcon.icns, so the custom volume-icon step is best-effort: if no
# source .icns is found the DMG just keeps the default volume icon — it still works.
#
# Usage:  APP_IDENTITY="Developer ID Application: …" installer/build-dmg.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
APP="$ROOT/build/Build/Products/Release/iNotes.app"
DMG="$ROOT/iNotes.dmg"
APP_IDENTITY="${APP_IDENTITY:-}"
VOL="iNotes"

[ -d "$APP" ] || { echo "no app at $APP — build it first" >&2; exit 1; }

STAGE="$(mktemp -d)"; RW="$(mktemp -u).dmg"
trap 'rm -rf "$STAGE" "$RW"' EXIT
cp -R "$APP" "$STAGE/iNotes.app"
ln -s /Applications "$STAGE/Applications"                 # the drag target

# Read-write image first, so we can set the volume icon + window layout, then compress to read-only.
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
MP="$(hdiutil attach "$RW" -nobrowse -noverify -noautoopen | grep -oE '/Volumes/.*$' | tail -1)"

# Tidy icon-view window: iNotes on the left, Applications on the right. Best-effort — a headless run
# without Finder access just keeps the default layout; the DMG still works. Do this FIRST — Finder
# rewrites the volume, so any icon written below must come AFTER it.
osascript >/dev/null 2>&1 <<OSA || true
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 150, 700, 470}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set position of item "iNotes.app" of container window to {140, 165}
    set position of item "Applications" of container window to {360, 165}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

# Optional custom volume icon — written LAST so the Finder step above can't drop it. iNotes ships its
# icon in the asset catalog, so there's usually no standalone .icns; use one if a build placed it at
# installer/VolumeIcon.icns, otherwise skip. Best-effort — needs Xcode's SetFile for the custom bit.
if [ -f "$ROOT/installer/VolumeIcon.icns" ]; then
  cp "$ROOT/installer/VolumeIcon.icns" "$MP/.VolumeIcon.icns"
  SetFile -a C "$MP" 2>/dev/null || xcrun SetFile -a C "$MP" 2>/dev/null || true
fi

sync
hdiutil detach "$MP" >/dev/null 2>&1 || true
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

if [ -n "$APP_IDENTITY" ]; then                          # sign the container so Gatekeeper trusts it
  codesign --force --sign "$APP_IDENTITY" --timestamp "$DMG"
fi
echo "built: $DMG ($(du -h "$DMG" | cut -f1))"
