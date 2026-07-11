#!/bin/bash
# Full iNotes release: build → sign → notarize → staple BOTH artifacts, EdDSA-sign the
# Sparkle appcast, and publish to GitHub Pages (feed) + a GitHub Release (downloads).
#
# A signed release pipeline, adapted to
# iNotes's build: XcodeGen (project.yml) → xcodebuild Release, with Sparkle embedded via SPM
# into iNotes.app/Contents/Frameworks/Sparkle.framework (SPM-embedded, not a vendored framework).
#
# Produces per release:
#   iNotes.dmg             — first-time install: drag-and-drop disk image (notarized + stapled)
#   iNotes-<ver>.app.zip   — Sparkle auto-update payload (notarized + stapled .app)
#   site/appcast.xml       — the EdDSA-signed Sparkle feed (deploys to Pages on push)
#
# Usage:   installer/release.sh <version>        e.g. installer/release.sh 1.8
#
# Prerequisites (reused across my signed apps):
#   - Developer ID Application cert in the login keychain (87CWAR5GNP)
#   - notarytool profile "asc-notary"  (xcrun notarytool store-credentials)
#   - Sparkle EdDSA private key in the login keychain (generate_appcast finds it automatically;
#     public half PAH3T7Y8eL9tdQXBjIksAVFqv6xu2sv6seP8GXa8ukk= is iNotes's SUPublicEDKey)
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: installer/release.sh <version>   (e.g. 1.8)" >&2; exit 1; }
VERSION="$1"
TEAM_ID="87CWAR5GNP"
APP_IDENTITY="Developer ID Application: Vamsi Guntuku (${TEAM_ID})"
NOTARY_PROFILE="asc-notary"
SPARKLE_VER="2.9.4"
TAG="v${VERSION}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/build/Build/Products/Release/iNotes.app"   # where xcodebuild -derivedDataPath build lands it
DIST="$ROOT/build/release"            # gitignored work dir (generate_appcast scans this)
TOOLS="$ROOT/installer/.sparkle-tools" # gitignored cached Sparkle CLI tools
ZIP="$DIST/iNotes-${VERSION}.app.zip"
DMG="$ROOT/iNotes.dmg"

rm -rf "$DIST"; mkdir -p "$DIST"

# 0) Fetch Sparkle CLI tools (generate_appcast/sign_update) once, cached + gitignored.
if [ ! -x "$TOOLS/bin/generate_appcast" ]; then
  echo "==> Fetching Sparkle ${SPARKLE_VER} CLI tools"
  mkdir -p "$TOOLS"
  curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VER}/Sparkle-${SPARKLE_VER}.tar.xz" \
    | tar -xJ -C "$TOOLS"
fi

# 1) Stamp the version into Info.plist (Sparkle compares CFBundleVersion to decide "newer").
echo "==> Stamping version ${VERSION} into iNotes/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" iNotes/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" iNotes/Info.plist

# 2) Build + sign the .app with Developer ID + hardened runtime.
#    XcodeGen regenerates the project (keeps it in sync with project.yml), then xcodebuild does a
#    Release build and signs the app bundle. We let xcodebuild do the top-level signing…
echo "==> Regenerating Xcode project + building signed Release"
xcodegen generate
rm -rf "$ROOT/build/Build/Products/Release/iNotes.app"
xcodebuild -project iNotes.xcodeproj -scheme iNotes -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="$APP_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  ENABLE_HARDENED_RUNTIME=YES \
  build
[ -d "$APP" ] || { echo "build produced no app at $APP" >&2; exit 1; }

# 2b) Inside-out re-sign the embedded Sparkle framework. REQUIRED, not optional: xcodebuild signs
#     the app + framework top level with our Developer ID, but leaves Sparkle's nested helpers
#     (XPCServices, Updater.app, Autoupdate) with Sparkle's own AD-HOC signatures. `--deep --strict`
#     still passes on those (ad-hoc + runtime is "valid"), but the notary service REJECTS ad-hoc
#     nested code. So we re-sign deepest-first with OUR identity + hardened runtime, then re-seal the
#     framework and finally the app — the required inside-out signing loop.
echo "==> Re-signing embedded Sparkle helpers inside-out (Developer ID + hardened runtime)"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for nested in \
    "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
    "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
    "$SPARKLE/Versions/B/Updater.app" \
    "$SPARKLE/Versions/B/Autoupdate" \
    "$SPARKLE"
do
    codesign --force --sign "$APP_IDENTITY" --options runtime --timestamp "$nested"
done
codesign --force --sign "$APP_IDENTITY" --options runtime --timestamp "$APP"

# 2c) Prove the signature before we spend a notarization round-trip on it.
echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

# 3) Zip the app and notarize the ZIP (notarizes the .app's cdhash), then staple the .app.
echo "==> Notarizing the .app (via zip)"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
# Re-zip the now-stapled app — this is the payload Sparkle downloads.
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
xcrun stapler validate "$APP"

# 4) Build the drag-and-drop DMG from the SAME stapled app, then notarize + staple the .dmg.
echo "==> Building + notarizing iNotes.dmg"
APP_IDENTITY="$APP_IDENTITY" installer/build-dmg.sh
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# 5) Generate the EdDSA-signed appcast. generate_appcast finds the private key in the keychain and
#    signs each archive in $DIST; --download-url-prefix makes enclosures point at the Release assets.
echo "==> Generating EdDSA-signed appcast.xml"
"$TOOLS/bin/generate_appcast" \
  --download-url-prefix "https://github.com/spacegrowth/inotes/releases/download/${TAG}/" \
  "$DIST"
cp "$DIST/appcast.xml" "$ROOT/site/appcast.xml"

# 6) Publish the downloads as a GitHub Release FIRST — so the release + assets exist before the
#    push below deploys the site, and before the Pages workflow fetches iNotes.dmg into the site.
echo "==> Creating GitHub Release ${TAG}"
gh release create "$TAG" \
  "$DMG" \
  "$ZIP" \
  --title "${TAG}" \
  --notes "iNotes ${VERSION}. Download \`iNotes.dmg\` and drag iNotes to Applications (notarized). Existing installs auto-update via Sparkle."

# 7) Publish the feed (commit appcast.xml + version bump; push deploys Pages). The Pages workflow
#    fetches the just-published iNotes.dmg into the site so the website serves it SAME-ORIGIN.
echo "==> Publishing appcast to GitHub Pages (site/appcast.xml)"
git add site/appcast.xml iNotes/Info.plist
git commit -m "Release ${TAG}: appcast + version bump" || echo "(nothing to commit)"
git push origin main

echo ""
echo "Done. Released ${TAG}:"
echo "  dmg:     $DMG"
echo "  update:  $ZIP"
echo "  appcast: https://spacegrowth.github.io/inotes/appcast.xml (deploying via Pages)"
