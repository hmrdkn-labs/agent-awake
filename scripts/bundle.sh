#!/bin/sh
# Build and sign dist/SmartWork.app (app + CLI + privileged helper).
#   SIGN_IDENTITY  codesign identity, e.g. "Developer ID Application: Name (TEAMID)" (required for release)
#                  or "Apple Development: ..." for local testing. Ad-hoc ("-") cannot run the helper.
#   VERSION        default 0.1.0
set -eu
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?set SIGN_IDENTITY (security find-identity -v -p codesigning)}"
VERSION="${VERSION:-0.1.0}"
APP=dist/SmartWork.app

ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
BIN=$(swift build -c release $ARCHS --show-bin-path)

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchDaemons"
cp "$BIN/SmartWork" "$BIN/smart-work" "$BIN/smart-work-helper" "$APP/Contents/MacOS/"
sed "s/@VERSION@/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/com.hamardikan.smart-work.helper.plist "$APP/Contents/Library/LaunchDaemons/"

# Hardened runtime + secure timestamp are required for notarization. Sign inside-out, no --deep.
# The helper gets its own identifier; the app gets the bundle id, which the helper's XPC check pins.
sign() { codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$@"; }
sign --identifier com.hamardikan.smart-work.helper "$APP/Contents/MacOS/smart-work-helper"
sign --identifier com.hamardikan.smart-work.cli "$APP/Contents/MacOS/smart-work"
sign "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "built $APP"
