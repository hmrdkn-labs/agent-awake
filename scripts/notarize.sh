#!/bin/sh
# Notarize dist/SmartWork.app (the DMG holds the stapled app), staple, and produce dist/smart-work-$VERSION.dmg. Run bundle.sh first with a
# "Developer ID Application" identity. One-time credential setup:
#   xcrun notarytool store-credentials smart-work --apple-id <id> --team-id <TEAMID> --password <app-specific-password>
set -eu
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
PROFILE="${NOTARY_PROFILE:-smart-work}"
APP=dist/SmartWork.app
DMG="dist/smart-work-$VERSION.dmg"

ditto -c -k --keepParent "$APP" dist/SmartWork.zip
xcrun notarytool submit dist/SmartWork.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm dist/SmartWork.zip

rm -rf dist/dmg && mkdir -p dist/dmg && cp -R "$APP" dist/dmg/ && ln -s /Applications dist/dmg/Applications
hdiutil create -volname smart-work -srcfolder dist/dmg -ov -format UDZO "$DMG"
rm -rf dist/dmg
codesign --force --timestamp --sign "${SIGN_IDENTITY:?set SIGN_IDENTITY}" "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
echo "ready: $DMG"
# Slow Apple queue? Run scripts/finish-release.sh <submission-id> from a launchd job instead of --wait.
