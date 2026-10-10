#!/bin/sh
# Resume a pending notarization: if Apple accepted submission $1, staple the app, build and sign the DMG,
# publish the GitHub release, then remove the launchd job that called us. Safe to run repeatedly; does
# nothing while Apple is still working.
#   SIGN_IDENTITY, VERSION (default 0.1.0), NOTARY_PROFILE (default smart-work), REPO (default hmrdkn-labs/smart-work)
set -eu
cd "$(dirname "$0")/.."
ID="${1:?usage: finish-release.sh <submission-id>}"
VERSION="${VERSION:-0.1.0}"
PROFILE="${NOTARY_PROFILE:-smart-work}"
REPO="${REPO:-hmrdkn-labs/smart-work}"
JOB="com.hamardikan.smart-work-release"
APP=dist/SmartWork.app
DMG="dist/smart-work-$VERSION.dmg"

stop_job() { launchctl bootout "gui/$(id -u)/$JOB" 2>/dev/null || true; rm -f "$HOME/Library/LaunchAgents/$JOB.plist"; }
say() { osascript -e "display notification \"$1\" with title \"smart-work release\"" 2>/dev/null || true; echo "$(date '+%F %T') $1"; }

if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then stop_job; exit 0; fi

# A transient failure (locked keychain, offline) leaves STATUS empty: just try again next time.
STATUS=$(xcrun notarytool info "$ID" --keychain-profile "$PROFILE" 2>/dev/null | awk '/status:/{print $2}' || true)
case "$STATUS" in
  Accepted) ;;
  Invalid|Rejected)
     say "Notarization $STATUS. See: xcrun notarytool log $ID --keychain-profile $PROFILE"
     xcrun notarytool log "$ID" --keychain-profile "$PROFILE" || true
     stop_job; exit 1 ;;
  *) echo "$(date '+%F %T') waiting (status: ${STATUS:-unreadable})"; exit 0 ;;
esac

xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"
rm -rf dist/dmg && mkdir -p dist/dmg && cp -R "$APP" dist/dmg/ && ln -s /Applications dist/dmg/Applications
rm -f "$DMG"
hdiutil create -volname smart-work -srcfolder dist/dmg -ov -format UDZO "$DMG"
rm -rf dist/dmg
codesign --force --timestamp --sign "${SIGN_IDENTITY:?set SIGN_IDENTITY}" "$DMG"
gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "smart-work $VERSION" \
  --notes "Signed with Developer ID and notarized. Open the DMG, drag SmartWork to Applications, launch it from the menu bar. See the README."
say "Released v$VERSION"
stop_job
