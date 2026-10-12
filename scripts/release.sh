#!/bin/sh
# Notarize and publish a release without waiting on Apple: each run moves one step forward and exits.
#   1. preflight + submit the app         4. submit the DMG
#   2. (Apple accepts) staple the app     5. (Apple accepts) staple the DMG
#   3. build and sign the DMG             6. publish the GitHub release
# Run it until it prints "released", or let launchd run it every 5 minutes:
#   scripts/release.sh --schedule      (the job removes itself when done or when Apple rejects)
# Build first: SIGN_IDENTITY=... VERSION=x.y.z scripts/bundle.sh
#   SIGN_IDENTITY  Developer ID Application identity (required)
#   VERSION        must match the bundle (default: read from the built app)
#   NOTARY_PROFILE notarytool keychain profile (default agent-awake)
#   REPO           GitHub repo (default hmrdkn-labs/agent-awake)
set -eu
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
APP="dist/Agent Awake.app"
: "${SIGN_IDENTITY:?set SIGN_IDENTITY}"
VERSION="${VERSION:-$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)}"
PROFILE="${NOTARY_PROFILE:-agent-awake}"
REPO="${REPO:-hmrdkn-labs/agent-awake}"
DMG="dist/AgentAwake-$VERSION.dmg"
STATE="dist/release-$VERSION"
JOB="com.hamardikan.agent-awake.release"
PLIST="$HOME/Library/LaunchAgents/$JOB.plist"
mkdir -p "$STATE"

log() { echo "$(date '+%F %T') $*"; }
notify() { osascript -e "display notification \"$1\" with title \"Agent Awake release\"" 2>/dev/null || true; log "$1"; }
unschedule() { launchctl bootout "gui/$(id -u)/$JOB" 2>/dev/null || true; rm -f "$PLIST"; }

if [ "${1:-}" = "--schedule" ]; then
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$JOB</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>$PWD/scripts/release.sh</string></array>
  <key>EnvironmentVariables</key><dict>
    <key>SIGN_IDENTITY</key><string>$SIGN_IDENTITY</string>
    <key>VERSION</key><string>$VERSION</string>
    <key>NOTARY_PROFILE</key><string>$PROFILE</string>
    <key>REPO</key><string>$REPO</string>
  </dict>
  <key>StartInterval</key><integer>300</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$PWD/$STATE/log</string>
  <key>StandardErrorPath</key><string>$PWD/$STATE/log</string>
</dict></plist>
EOF
  launchctl bootout "gui/$(id -u)/$JOB" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "scheduled; log: $STATE/log"
  exit 0
fi

# Prints Accepted / In Progress / Invalid / Rejected, or nothing if Apple can't be asked right now
# (offline, locked keychain); then the next run tries again.
status() {
  xcrun notarytool info "$1" --keychain-profile "$PROFILE" 2>/dev/null | sed -n 's/^ *status: //p' || true
}

# Waits for submission $1 (read from $2); returns 0 when accepted, exits otherwise.
gate() {
  s=$(status "$(cat "$2")")
  case "$s" in
    Accepted) return 0 ;;
    Invalid|Rejected)
      notify "Apple rejected the $1 ($s). See $STATE/log."
      xcrun notarytool log "$(cat "$2")" --keychain-profile "$PROFILE" || true
      unschedule; exit 1 ;;
    *) log "$1: waiting for Apple (${s:-no answer})"; exit 0 ;;
  esac
}

submit() {  # file, id file
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --output-format json \
    | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' > "$2"
  [ -s "$2" ] || { rm -f "$2"; log "submit of $1 failed; will retry"; exit 0; }
  log "submitted $1 as $(cat "$2")"
}

if [ ! -s "$STATE/app.id" ]; then
  scripts/preflight.sh
  ditto -c -k --keepParent "$APP" "$STATE/app.zip"
  submit "$STATE/app.zip" "$STATE/app.id"
  exit 0
fi
gate "app" "$STATE/app.id"
xcrun stapler validate "$APP" >/dev/null 2>&1 || xcrun stapler staple "$APP"

if [ ! -s "$STATE/dmg.id" ]; then
  rm -rf dist/dmg "$DMG" && mkdir -p dist/dmg && cp -R "$APP" dist/dmg/ && ln -s /Applications dist/dmg/Applications
  hdiutil create -volname "Agent Awake" -srcfolder dist/dmg -ov -format UDZO "$DMG"
  rm -rf dist/dmg
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  submit "$DMG" "$STATE/dmg.id"
  exit 0
fi
gate "DMG" "$STATE/dmg.id"
xcrun stapler validate "$DMG" >/dev/null 2>&1 || xcrun stapler staple "$DMG"
spctl --assess --type execute "$APP"
spctl --assess --type open --context context:primary-signature "$DMG"

if ! gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
  # Notes: this version's CHANGELOG section, then how to install.
  changes=$(awk -v v="## $VERSION " 'index($0, v) == 1 { on = 1; next } on && /^## / { exit } on' CHANGELOG.md)
  [ -n "$changes" ] || { log "no CHANGELOG.md section for $VERSION"; exit 1; }
  gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "Agent Awake $VERSION" --notes-file - <<EOF
Keeps your Mac awake while AI coding agents work, lets it sleep when they finish, and pings your phone.
$changes

Open the DMG, drag Agent Awake to Applications, and open it. Signed with Developer ID and notarized by Apple.
Requires macOS 13 or later.
EOF
fi
notify "Released v$VERSION: https://github.com/$REPO/releases/tag/v$VERSION"
rm -f "$STATE/app.zip"
touch "$STATE/released"
unschedule
echo released
