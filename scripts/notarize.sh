#!/bin/sh
# Notarize and staple "dist/Agent Awake.app", then put it in dist/AgentAwake-$VERSION.dmg and notarize and staple
# the DMG too, so a downloaded DMG opens without a Gatekeeper warning. Run bundle.sh first with a
# "Developer ID Application" identity. One-time credential setup:
#   xcrun notarytool store-credentials agent-awake --apple-id <id> --team-id <TEAMID> --password <app-specific-password>
set -eu
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
PROFILE="${NOTARY_PROFILE:-agent-awake}"
APP="dist/Agent Awake.app"
DMG="dist/AgentAwake-$VERSION.dmg"

scripts/preflight.sh
ditto -c -k --keepParent "$APP" dist/AgentAwake.zip
xcrun notarytool submit dist/AgentAwake.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm dist/AgentAwake.zip

rm -rf dist/dmg && mkdir -p dist/dmg && cp -R "$APP" dist/dmg/ && ln -s /Applications dist/dmg/Applications
hdiutil create -volname "Agent Awake" -srcfolder dist/dmg -ov -format UDZO "$DMG"
rm -rf dist/dmg
codesign --force --timestamp --sign "${SIGN_IDENTITY:?set SIGN_IDENTITY}" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "ready: $DMG"
