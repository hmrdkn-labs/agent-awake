#!/bin/sh
# Build, sign and update the installed app in place, then relaunch it.
# macOS ties Login Items and the helper's approval to the app's path, bundle ID and Team ID. Replacing the
# bundle at the same path keeps all three, so an update does not ask for approval again. Deleting the app
# and copying a new one elsewhere is what makes macOS treat it as a new install.
#   SIGN_IDENTITY  as for bundle.sh
#   DEST           install path; default: the existing install in /Applications or ~/Applications,
#                  else /Applications/Agent Awake.app
set -eu
cd "$(dirname "$0")/.."
APP="dist/Agent Awake.app"
if [ -z "${DEST:-}" ]; then
  DEST="/Applications/Agent Awake.app"
  [ -d "$DEST" ] || [ ! -d "$HOME/Applications/Agent Awake.app" ] || DEST="$HOME/Applications/Agent Awake.app"
fi

scripts/bundle.sh
# Keep LaunchServices from seeing two copies of the app (Spotlight, `open`, login items).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true

# Quit the running copy. Its sleep assertion dies with it; the helper's lease runs out by itself.
if pkill -TERM -x AgentAwakeApp; then
  while pgrep -x AgentAwakeApp >/dev/null; do sleep 0.2; done
fi
mkdir -p "$DEST"
rsync -a --delete "$APP/" "$DEST/"
open "$DEST"
echo "updated $DEST to $(defaults read "$DEST/Contents/Info" CFBundleShortVersionString) ($(defaults read "$DEST/Contents/Info" CFBundleVersion))"
