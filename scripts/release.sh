#!/bin/bash
# release.sh — DOCUMENTED SKELETON, not wired up to run unattended.
#
# Builds a Developer-ID-signed, notarized .app for the DIRECT-download
# distribution of iNotes, EdDSA-signs it for Sparkle, and appends/updates the
# corresponding <item> in appcast.xml.
#
# This script is NOT executed as part of any packet/CI here — it needs the
# user's Apple Developer ID identity, notarytool credentials, and a decision
# on where the appcast/zip get hosted. Every spot needing that is marked
# `# TODO(user)` below. Do not run this blind.
#
# Prerequisites (all one-time, user-side):
#   - A "Developer ID Application" signing identity in the login keychain.
#   - An App Store Connect API key or Apple ID app-specific password set up
#     for `xcrun notarytool` (see: xcrun notarytool store-credentials).
#   - The Sparkle EdDSA private key already in the login keychain (this repo
#     already has one — see DISTRIBUTION.md; `generate_keys` from the
#     resolved Sparkle package's `bin/` directory manages it, never write it
#     to disk).

set -euo pipefail

# TODO(user): fill in your Developer ID identity, e.g. "Developer ID Application: Your Name (TEAMID)"
DEVELOPER_ID_IDENTITY="TODO(user): Developer ID Application identity"

# TODO(user): the notarytool keychain profile you set up via
#   xcrun notarytool store-credentials
NOTARYTOOL_PROFILE="TODO(user): notarytool keychain profile name"

# TODO(user): where the built zip + appcast actually get uploaded/hosted.
# SUFeedURL in iNotes/Info.plist must match wherever appcast.xml ends up.
RELEASE_HOST="TODO(user): e.g. a GitHub Releases page + raw.githubusercontent.com for appcast.xml"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION="$(defaults read "$PROJECT_ROOT/iNotes/Info" CFBundleShortVersionString 2>/dev/null || echo "UNKNOWN")"
BUILD="$(defaults read "$PROJECT_ROOT/iNotes/Info" CFBundleVersion 2>/dev/null || echo "UNKNOWN")"
ARCHIVE_PATH="build/iNotes.xcarchive"
EXPORT_PATH="build/export"
ZIP_PATH="build/iNotes-${VERSION}.zip"

echo "==> Releasing iNotes ${VERSION} (build ${BUILD})"

echo "==> 1/6 Regenerating the Xcode project (xcodegen)"
xcodegen generate

echo "==> 2/6 Archiving a Release build (Developer ID signed)"
xcodebuild -project iNotes.xcodeproj -scheme iNotes -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_IDENTITY" \
  archive
# TODO(user): a real release also needs an ExportOptionsPlist for
# `xcodebuild -exportArchive` (method: developer-id). Not scaffolded here
# since it depends on your team/identity specifics.
echo "    (exportArchive step intentionally left for you to wire up with your ExportOptions.plist)"

echo "==> 3/6 Zipping the exported .app"
mkdir -p build
# TODO(user): once exportArchive above produces $EXPORT_PATH/iNotes.app, e.g.:
#   ditto -c -k --sequesterRsrc --keepParent "$EXPORT_PATH/iNotes.app" "$ZIP_PATH"

echo "==> 4/6 Notarizing"
# TODO(user):
#   xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
#   xcrun stapler staple "$EXPORT_PATH/iNotes.app"
#   (re-zip after stapling if the notarized ticket must be embedded in the shipped zip)

echo "==> 5/6 EdDSA-signing the zip for Sparkle"
GEN_KEYS_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*artifacts/sparkle/Sparkle/bin/sign_update' -print -quit 2>/dev/null || true)"
if [ -z "$GEN_KEYS_BIN" ]; then
  echo "    sign_update not found under DerivedData — build the project at least once so SPM resolves Sparkle, then re-run."
else
  # "$GEN_KEYS_BIN" "$ZIP_PATH"
  echo "    (would run: $GEN_KEYS_BIN \"$ZIP_PATH\" — prints the sparkle:edSignature to embed below)"
fi

echo "==> 6/6 Updating appcast.xml"
# TODO(user): append/update an <item> in appcast.xml with:
#   - sparkle:version = $BUILD (CFBundleVersion)
#   - sparkle:shortVersionString = $VERSION (CFBundleShortVersionString)
#   - enclosure url = wherever $ZIP_PATH gets uploaded ($RELEASE_HOST)
#   - enclosure length = the zip's byte size (`stat -f%z "$ZIP_PATH"`)
#   - sparkle:edSignature = the output of sign_update above
# Then publish the updated appcast.xml to $RELEASE_HOST so SUFeedURL in
# Info.plist resolves to it.

echo "==> Done (skeleton only — fill in the TODO(user) sections above before relying on this)."
