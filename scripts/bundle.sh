#!/bin/sh
# Build and sign "dist/Agent Awake.app" (app + CLI + privileged helper).
#   SIGN_IDENTITY  codesign identity, e.g. "Developer ID Application: Name (TEAMID)" (required for release)
#                  or "Apple Development: ..." for local testing. Ad-hoc ("-") cannot run the helper.
#   VERSION        marketing version, default 0.1.0; the build number is the commit count (always increases)
set -eu
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?set SIGN_IDENTITY (security find-identity -v -p codesigning)}"
VERSION="${VERSION:-0.1.0}"
APP="dist/Agent Awake.app"
# A release waiting on Apple notarizes this exact build; rebuilding would orphan it.
for s in dist/release-*/app.id; do
  [ -e "$s" ] && [ ! -e "$(dirname "$s")/released" ] || continue
  [ "${FORCE:-}" = 1 ] || { echo "a release is in progress ($(dirname "$s")); finish it or rerun with FORCE=1" >&2; exit 1; }
done

ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
BIN=$(swift build -c release $ARCHS --show-bin-path)

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"
cp "$BIN/AgentAwakeApp" "$BIN/agentawake" "$BIN/agentawake-helper" "$APP/Contents/MacOS/"
sed -e "s/@VERSION@/$VERSION/g" -e "s/@BUILD@/$(git rev-list --count HEAD)/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/com.hamardikan.agent-awake.helper.plist "$APP/Contents/Library/LaunchDaemons/"

# Hardened runtime + secure timestamp are required for notarization. Sign inside-out, no --deep.
# The helper gets its own identifier; the app gets the bundle id, which the helper's XPC check pins.
sign() { codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$@"; }
sign --identifier com.hamardikan.agent-awake.helper "$APP/Contents/MacOS/agentawake-helper"
sign --identifier com.hamardikan.agent-awake.cli "$APP/Contents/MacOS/agentawake"
sign "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "built $APP"
